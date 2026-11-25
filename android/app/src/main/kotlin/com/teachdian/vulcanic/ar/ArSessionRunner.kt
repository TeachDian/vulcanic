package com.teachdian.vulcanic.ar

import android.content.Context
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.util.Log
import android.view.Surface
import com.google.ar.core.Anchor
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.HitResult
import com.google.ar.core.LightEstimate
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingFailureReason
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Owns the ARCore session and the thread it runs on.
 *
 * Each iteration asks ARCore for the next camera frame, draws the camera
 * image into the Flutter texture, and reports what ARCore knows about the
 * world as a flat packet of floats (see [buildPacket]). Flutter draws
 * everything else on top.
 *
 * ARCore needs a current GL context on the thread that updates the session,
 * so the thread owns a small EGL setup of its own. All session calls happen
 * on that thread; other threads talk to it through [commands].
 */
internal class ArSessionRunner(
    private val context: Context,
    private val onFrame: (FloatArray) -> Unit,
    private val onError: (code: String, message: String) -> Unit,
) {
    private val commands = ConcurrentLinkedQueue<() -> Unit>()

    @Volatile
    private var running = false
    private var thread: Thread? = null

    // Everything below is touched only on the AR thread.
    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglConfig: EGLConfig? = null
    private var window: EGLSurface = EGL14.EGL_NO_SURFACE
    private var offscreen: EGLSurface = EGL14.EGL_NO_SURFACE
    private var session: Session? = null
    private var background: CameraBackground? = null
    private var anchor: Anchor? = null
    private var paused = false
    private var width = 1
    private var height = 1
    private var pendingTap: Tap? = null

    private val view = FloatArray(16)
    private val projection = FloatArray(16)
    private val pose = FloatArray(16)
    private val point = FloatArray(3)
    private val packet = FloatArray(MAX_PACKET)

    private class Tap(val x: Float, val y: Float, val reply: (Boolean) -> Unit)

    fun start(surface: Surface, width: Int, height: Int, onStopped: () -> Unit) {
        running = true
        thread = Thread({
            try {
                setUp(surface, width, height)
                loop()
            } catch (e: Throwable) {
                Log.e(TAG, "AR session failed", e)
                onError(errorCode(e), e.message ?: e.javaClass.simpleName)
            } finally {
                tearDown()
                onStopped()
            }
        }, "vulcanic-ar").also { it.start() }
    }

    /** Ends the loop. `onStopped` from [start] fires once GL is torn down. */
    fun stop() {
        running = false
    }

    /** Points rendering at a new surface, or at nothing when null. */
    fun setWindow(surface: Surface?, width: Int, height: Int) = post {
        releaseWindow()
        if (surface != null && surface.isValid) attachWindow(surface, width, height)
    }

    fun pause() = post {
        if (!paused) {
            session?.pause()
            paused = true
        }
    }

    fun resume() = post {
        if (paused) {
            session?.resume()
            background?.invalidate()
            paused = false
        }
    }

    /** Anchors the model where the screen point meets a detected plane. */
    fun hitTest(x: Float, y: Float, reply: (Boolean) -> Unit) = post {
        pendingTap?.reply?.invoke(false)
        pendingTap = Tap(x, y, reply)
    }

    fun clearAnchor() = post {
        anchor?.detach()
        anchor = null
    }

    private fun post(command: () -> Unit) {
        commands.add(command)
    }

    // --- AR thread -------------------------------------------------------

    private fun setUp(surface: Surface, width: Int, height: Int) {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) { "EGL init failed" }
        val attributes = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT or EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        check(
            EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0) &&
                count[0] > 0,
        ) { "No EGL config" }
        eglConfig = configs[0]
        eglContext = EGL14.eglCreateContext(
            display,
            eglConfig,
            EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
            0,
        )
        check(eglContext != EGL14.EGL_NO_CONTEXT) { "No EGL context" }
        // A 1x1 surface keeps the context current while there is no window.
        offscreen = EGL14.eglCreatePbufferSurface(
            display,
            eglConfig,
            intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE),
            0,
        )
        EGL14.eglMakeCurrent(display, offscreen, offscreen, eglContext)

        val background = CameraBackground().also { background = it }
        val session = Session(context).also { session = it }
        session.configure(
            Config(session).apply {
                planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                lightEstimationMode = Config.LightEstimationMode.AMBIENT_INTENSITY
                updateMode = Config.UpdateMode.BLOCKING
                focusMode = Config.FocusMode.AUTO
                depthMode = Config.DepthMode.DISABLED
                instantPlacementMode = Config.InstantPlacementMode.DISABLED
            },
        )
        session.setCameraTextureName(background.textureId)
        attachWindow(surface, width, height)
        session.resume()
    }

    private fun attachWindow(surface: Surface, width: Int, height: Int) {
        window = EGL14.eglCreateWindowSurface(
            display,
            eglConfig,
            surface,
            intArrayOf(EGL14.EGL_NONE),
            0,
        )
        if (window == EGL14.EGL_NO_SURFACE) {
            Log.w(TAG, "Could not create window surface: ${EGL14.eglGetError()}")
            return
        }
        EGL14.eglMakeCurrent(display, window, window, eglContext)
        this.width = width
        this.height = height
        session?.setDisplayGeometry(Surface.ROTATION_0, width, height)
        background?.invalidate()
    }

    private fun releaseWindow() {
        if (window == EGL14.EGL_NO_SURFACE) return
        EGL14.eglMakeCurrent(display, offscreen, offscreen, eglContext)
        EGL14.eglDestroySurface(display, window)
        window = EGL14.EGL_NO_SURFACE
    }

    private fun loop() {
        val session = checkNotNull(session)
        val background = checkNotNull(background)
        while (running) {
            while (true) {
                val command = commands.poll() ?: break
                command()
            }
            if (paused || window == EGL14.EGL_NO_SURFACE) {
                Thread.sleep(40)
                continue
            }
            // Blocks until the camera delivers the next image.
            val frame = session.update()
            GLES20.glViewport(0, 0, width, height)
            GLES20.glClearColor(0f, 0f, 0f, 1f)
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
            background.draw(frame)
            if (!EGL14.eglSwapBuffers(display, window)) {
                // The surface went away under us; wait for a new one.
                releaseWindow()
                continue
            }
            placeAnchor(frame)
            onFrame(buildPacket(session, frame))
        }
    }

    private fun tearDown() {
        pendingTap?.reply?.invoke(false)
        pendingTap = null
        runCatching { anchor?.detach() }
        anchor = null
        runCatching { session?.close() }
        session = null
        if (display != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglMakeCurrent(
                display,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_CONTEXT,
            )
            if (window != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, window)
            if (offscreen != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, offscreen)
            if (eglContext != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, eglContext)
            EGL14.eglTerminate(display)
        }
        window = EGL14.EGL_NO_SURFACE
        offscreen = EGL14.EGL_NO_SURFACE
        eglContext = EGL14.EGL_NO_CONTEXT
        display = EGL14.EGL_NO_DISPLAY
    }

    /** The first hit on an upward-facing plane, inside its detected outline. */
    private fun planeHit(frame: Frame, x: Float, y: Float): HitResult? =
        frame.hitTest(x, y).firstOrNull { hit ->
            val plane = hit.trackable as? Plane ?: return@firstOrNull false
            plane.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                plane.isPoseInPolygon(hit.hitPose) &&
                hit.distance > 0.05f
        }

    private fun placeAnchor(frame: Frame) {
        val tap = pendingTap ?: return
        pendingTap = null
        val hit = if (frame.camera.trackingState == TrackingState.TRACKING) {
            planeHit(frame, tap.x, tap.y)
        } else {
            null
        }
        if (hit != null) {
            anchor?.detach()
            anchor = hit.createAnchor()
        }
        tap.reply(hit != null)
    }

    /**
     * Packs one frame for Flutter.
     *
     * ```
     * [0] camera tracking (0/1)        [4] reticle valid (0/1)
     * [1] tracking failure reason      [5] plane count
     * [2] light intensity, -1 unknown  [6] feature point count
     * [3] anchor: 0 none, 1 tracking,  [7] unused
     *     2 not tracking
     * [8..24)  view matrix        [40..56) anchor pose
     * [24..40) projection matrix  [56..72) reticle pose
     * then per plane: vertex count, followed by that many xyz world points
     * then per feature point: xyz
     * ```
     * Matrices are column-major, as OpenGL and vector_math expect.
     */
    private fun buildPacket(session: Session, frame: Frame): FloatArray {
        val camera = frame.camera
        val tracking = camera.trackingState == TrackingState.TRACKING
        val out = packet
        out.fill(0f, 0, HEADER)
        out[0] = if (tracking) 1f else 0f
        out[1] = when (camera.trackingFailureReason) {
            TrackingFailureReason.NONE -> 0f
            TrackingFailureReason.BAD_STATE -> 1f
            TrackingFailureReason.INSUFFICIENT_LIGHT -> 2f
            TrackingFailureReason.EXCESSIVE_MOTION -> 3f
            TrackingFailureReason.INSUFFICIENT_FEATURES -> 4f
            TrackingFailureReason.CAMERA_UNAVAILABLE -> 5f
            else -> 1f
        }
        val light = frame.lightEstimate
        out[2] = if (light.state == LightEstimate.State.VALID) light.pixelIntensity else -1f

        camera.getViewMatrix(view, 0)
        camera.getProjectionMatrix(projection, 0, 0.05f, 60f)
        view.copyInto(out, 8)
        projection.copyInto(out, 24)

        anchor?.let { current ->
            when (current.trackingState) {
                TrackingState.TRACKING -> {
                    current.pose.toMatrix(pose, 0)
                    pose.copyInto(out, 40)
                    out[3] = 1f
                }
                TrackingState.PAUSED -> out[3] = 2f
                else -> {
                    current.detach()
                    anchor = null
                }
            }
        }

        var n = HEADER
        if (tracking) {
            planeHit(frame, width * 0.5f, height * RETICLE_Y)?.let { hit ->
                hit.hitPose.toMatrix(pose, 0)
                pose.copyInto(out, 56)
                out[4] = 1f
            }

            val planes = session.getAllTrackables(Plane::class.java)
                .filter {
                    it.trackingState == TrackingState.TRACKING &&
                        it.subsumedBy == null &&
                        it.type == Plane.Type.HORIZONTAL_UPWARD_FACING
                }
                .sortedByDescending { it.extentX * it.extentZ }
                .take(MAX_PLANES)
            for (plane in planes) {
                val polygon = plane.polygon
                val vertices = polygon.remaining() / 2
                if (vertices < 3) continue
                val stride = (vertices + MAX_PLANE_VERTICES - 1) / MAX_PLANE_VERTICES
                val countIndex = n++
                var written = 0
                val center = plane.centerPose
                var i = 0
                while (i < vertices) {
                    point[0] = polygon.get(i * 2)
                    point[1] = 0f
                    point[2] = polygon.get(i * 2 + 1)
                    center.transformPoint(point, 0, out, n)
                    n += 3
                    written++
                    i += stride
                }
                out[countIndex] = written.toFloat()
                out[5] += 1f
            }

            frame.acquirePointCloud().use { cloud ->
                val points = cloud.points
                val total = points.remaining() / 4
                val stride = maxOf(1, (total + MAX_POINTS - 1) / MAX_POINTS)
                var i = 0
                var written = 0
                while (i < total && written < MAX_POINTS) {
                    if (points.get(i * 4 + 3) > 0.12f) {
                        out[n] = points.get(i * 4)
                        out[n + 1] = points.get(i * 4 + 1)
                        out[n + 2] = points.get(i * 4 + 2)
                        n += 3
                        written++
                    }
                    i += stride
                }
                out[6] = written.toFloat()
            }
        }
        return out.copyOf(n)
    }

    private fun errorCode(e: Throwable): String = when (e) {
        is CameraNotAvailableException -> "camera_unavailable"
        is SecurityException -> "camera_permission"
        else -> "ar_unavailable"
    }

    companion object {
        private const val TAG = "VulcanicAR"
        private const val HEADER = 72
        private const val MAX_PLANES = 6
        private const val MAX_PLANE_VERTICES = 40
        private const val MAX_POINTS = 160
        private const val MAX_PACKET =
            HEADER + MAX_PLANES * (1 + MAX_PLANE_VERTICES * 3) + MAX_POINTS * 3

        /** Where the placement reticle looks, as a fraction of the height. */
        const val RETICLE_Y = 0.46f
    }
}
