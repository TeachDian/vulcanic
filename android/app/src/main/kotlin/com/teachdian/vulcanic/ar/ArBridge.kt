package com.teachdian.vulcanic.ar

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.google.ar.core.ArCoreApk
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * The Flutter side of markerless AR.
 *
 * Flutter asks whether ARCore is available, starts a session, and receives
 * one packet of tracking data per camera frame. The camera image itself
 * reaches Flutter as a texture, so the whole screen stays a Flutter widget
 * tree with no platform view.
 */
class ArBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val textures: TextureRegistry,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, DefaultLifecycleObserver {

    private val methods = MethodChannel(messenger, "vulcanic/ar")
    private val frames = EventChannel(messenger, "vulcanic/ar/frames")
    private val main = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private var runner: ArSessionRunner? = null
    private var producer: TextureRegistry.SurfaceProducer? = null

    private var pendingPermission: MethodChannel.Result? = null

    /** Set while the activity is in the background. */
    private var inBackground = false

    init {
        methods.setMethodCallHandler(this)
        frames.setStreamHandler(this)
        (activity as? LifecycleOwner)?.lifecycle?.addObserver(this)
    }

    fun dispose() {
        (activity as? LifecycleOwner)?.lifecycle?.removeObserver(this)
        methods.setMethodCallHandler(null)
        frames.setStreamHandler(null)
        stop()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cameraPermission" -> cameraPermission(call.argument<Boolean>("request") == true, result)
            "openSettings" -> {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", activity.packageName, null),
                    ),
                )
                result.success(null)
            }
            "availability" -> result.success(availability())
            "install" -> install(result)
            "start" -> start(call.argument<Int>("width")!!, call.argument<Int>("height")!!, result)
            "resize" -> {
                resize(call.argument<Int>("width")!!, call.argument<Int>("height")!!)
                result.success(null)
            }
            "hitTest" -> {
                val active = runner
                if (active == null) {
                    result.success(false)
                } else {
                    active.hitTest(
                        call.argument<Double>("x")!!.toFloat(),
                        call.argument<Double>("y")!!.toFloat(),
                    ) { placed -> main.post { result.success(placed) } }
                }
            }
            "clearAnchor" -> {
                runner?.clearAnchor()
                result.success(null)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun cameraGranted(): Boolean =
        ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Reports the camera permission as `granted`, `denied` or `blocked`
     * (denied for good; only the settings page can change it), asking the
     * user first when [request] is set.
     */
    private fun cameraPermission(request: Boolean, result: MethodChannel.Result) {
        when {
            cameraGranted() -> result.success("granted")
            !request -> result.success("denied")
            pendingPermission != null -> result.error("busy", "Already asking", null)
            else -> {
                pendingPermission = result
                ActivityCompat.requestPermissions(
                    activity,
                    arrayOf(Manifest.permission.CAMERA),
                    PERMISSION_REQUEST,
                )
            }
        }
    }

    /** Forwarded from the activity. Returns true if the result was ours. */
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val result = pendingPermission ?: return true
        pendingPermission = null
        val canAskAgain = ActivityCompat.shouldShowRequestPermissionRationale(
            activity,
            Manifest.permission.CAMERA,
        )
        result.success(
            when {
                cameraGranted() -> "granted"
                canAskAgain -> "denied"
                else -> "blocked"
            },
        )
        return true
    }

    /** One of `supported`, `installable`, `unsupported` or `checking`. */
    private fun availability(): String {
        val availability = ArCoreApk.getInstance().checkAvailability(activity)
        return when {
            availability.isTransient -> "checking"
            availability == ArCoreApk.Availability.SUPPORTED_INSTALLED -> "supported"
            availability == ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD ||
                availability == ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED -> "installable"
            else -> "unsupported"
        }
    }

    /** Opens the Play Store page for Google Play Services for AR if needed. */
    private fun install(result: MethodChannel.Result) {
        try {
            val status = ArCoreApk.getInstance().requestInstall(activity, true)
            result.success(
                if (status == ArCoreApk.InstallStatus.INSTALLED) "installed" else "requested",
            )
        } catch (e: UnavailableUserDeclinedInstallationException) {
            result.success("declined")
        } catch (e: Exception) {
            result.error("ar_unavailable", e.message, null)
        }
    }

    private fun start(width: Int, height: Int, result: MethodChannel.Result) {
        if (!cameraGranted()) {
            result.error("camera_permission", "Camera permission has not been granted", null)
            return
        }
        stop()

        val texture = textures.createSurfaceProducer()
        texture.setSize(width, height)
        val session = ArSessionRunner(
            context = activity.applicationContext,
            onFrame = { packet -> main.post { sink?.success(packet) } },
            onError = { code, message -> main.post { sink?.error(code, message, null) } },
        )
        texture.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceAvailable() {
                if (runner === session) {
                    session.setWindow(texture.surface, texture.width, texture.height)
                }
            }

            override fun onSurfaceCleanup() {
                if (runner === session) session.setWindow(null, 0, 0)
            }
        })
        producer = texture
        runner = session
        // The texture must outlive the GL surface that draws into it.
        session.start(texture.surface, width, height) { main.post { texture.release() } }
        if (inBackground) session.pause()
        result.success(mapOf("textureId" to texture.id()))
    }

    private fun resize(width: Int, height: Int) {
        val texture = producer ?: return
        if (texture.width == width && texture.height == height) return
        texture.setSize(width, height)
        runner?.setWindow(texture.surface, width, height)
    }

    private fun stop() {
        producer?.setCallback(null)
        runner?.stop()
        runner = null
        producer = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    // The camera is a shared resource: release it whenever we are not visible.
    override fun onPause(owner: LifecycleOwner) {
        inBackground = true
        runner?.pause()
    }

    override fun onResume(owner: LifecycleOwner) {
        inBackground = false
        runner?.resume()
    }

    private companion object {
        const val PERMISSION_REQUEST = 7301
    }
}
