package com.teachdian.vulcanic.narration

import android.app.Activity
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Plays a recorded narration clip that ships with the app.
 *
 * Flutter names the clip by its asset path; Android's own [MediaPlayer]
 * plays it straight from the APK. When a clip plays to its end (or cannot
 * be played) Flutter is told with `done`. Stopping one says nothing, so a
 * new clip is never mistaken for the end of the previous one.
 */
class NarrationBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, DefaultLifecycleObserver {

    private val channel = MethodChannel(messenger, "vulcanic/narration")
    private var player: MediaPlayer? = null

    init {
        channel.setMethodCallHandler(this)
        (activity as? LifecycleOwner)?.lifecycle?.addObserver(this)
    }

    fun dispose() {
        (activity as? LifecycleOwner)?.lifecycle?.removeObserver(this)
        channel.setMethodCallHandler(null)
        stop()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "play" -> result.success(play(call.argument<String>("asset") ?: ""))
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Starts [asset]. Returns false if it cannot be opened. */
    private fun play(asset: String): Boolean {
        stop()
        return try {
            val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
            val created = MediaPlayer()
            activity.assets.openFd(key).use { file ->
                created.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                created.setDataSource(file.fileDescriptor, file.startOffset, file.length)
            }
            created.setOnPreparedListener { it.start() }
            created.setOnCompletionListener { finished(it) }
            created.setOnErrorListener { failed, _, _ ->
                finished(failed)
                true
            }
            player = created
            created.prepareAsync()
            true
        } catch (e: Exception) {
            Log.w("VulcanicNarration", "Could not play $asset", e)
            false
        }
    }

    private fun finished(which: MediaPlayer) {
        if (player !== which) return // already replaced or stopped
        player = null
        which.release()
        channel.invokeMethod("done", null)
    }

    private fun stop() {
        player?.let {
            player = null
            runCatching { it.stop() }
            it.release()
        }
    }

    // A reading should not carry on after the app leaves the screen.
    override fun onPause(owner: LifecycleOwner) {
        if (player != null) {
            stop()
            channel.invokeMethod("done", null)
        }
    }
}
