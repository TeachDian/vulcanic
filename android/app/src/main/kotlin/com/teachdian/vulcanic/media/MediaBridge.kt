package com.teachdian.vulcanic.media

import android.app.Activity
import android.content.ContentValues
import android.graphics.Bitmap
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Saves pictures to the phone's gallery.
 *
 * `capture` photographs exactly what is on screen, camera image included,
 * by copying the surface Flutter renders into. `saveImage` stores PNG bytes
 * that Flutter rendered itself. Both write to Pictures/Vulcanic through
 * MediaStore, which needs no storage permission.
 */
class MediaBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "vulcanic/media")
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capture" -> capture(result)
            "saveImage" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name") ?: "vulcanic"
                if (bytes == null) {
                    result.error("bad_args", "No image bytes", null)
                } else {
                    io.execute {
                        val saved = runCatching { write("$name.png", "image/png") { it.write(bytes) } }
                        main.post { reply(result, saved) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun capture(result: MethodChannel.Result) {
        val surface = findSurface(activity.window.decorView)
        if (surface == null || surface.width == 0 || surface.height == 0) {
            result.error("no_surface", "Nothing to capture", null)
            return
        }
        val bitmap = Bitmap.createBitmap(surface.width, surface.height, Bitmap.Config.ARGB_8888)
        try {
            PixelCopy.request(surface, bitmap, { status ->
                if (status != PixelCopy.SUCCESS) {
                    bitmap.recycle()
                    result.error("copy_failed", "Could not read the screen ($status)", null)
                    return@request
                }
                io.execute {
                    val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
                    val saved = runCatching {
                        write("vulcanic_$stamp.jpg", "image/jpeg") {
                            bitmap.compress(Bitmap.CompressFormat.JPEG, 94, it)
                        }
                    }
                    bitmap.recycle()
                    main.post { reply(result, saved) }
                }
            }, main)
        } catch (e: IllegalArgumentException) {
            bitmap.recycle()
            result.error("copy_failed", e.message, null)
        }
    }

    private fun reply(result: MethodChannel.Result, saved: Result<String>) {
        saved.fold(
            onSuccess = { result.success(it) },
            onFailure = { result.error("save_failed", it.message, null) },
        )
    }

    /** The surface Flutter draws into, found by walking the view tree. */
    private fun findSurface(view: View): SurfaceView? {
        if (view is SurfaceView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findSurface(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    /** Writes a new picture and returns its display name. */
    private fun write(name: String, mime: String, body: (java.io.OutputStream) -> Unit): String {
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, mime)
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Vulcanic")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = checkNotNull(
            resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values),
        ) { "Could not create the picture" }
        try {
            checkNotNull(resolver.openOutputStream(uri)) { "Could not open the picture" }.use(body)
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return name
    }
}
