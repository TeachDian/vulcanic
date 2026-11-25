package com.teachdian.vulcanic

import com.teachdian.vulcanic.ar.ArBridge
import com.teachdian.vulcanic.media.MediaBridge
import com.teachdian.vulcanic.motion.MotionBridge
import com.teachdian.vulcanic.narration.NarrationBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var ar: ArBridge? = null
    private var media: MediaBridge? = null
    private var narration: NarrationBridge? = null
    private var motion: MotionBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        ar = ArBridge(this, messenger, flutterEngine.renderer)
        media = MediaBridge(this, messenger)
        narration = NarrationBridge(this, messenger)
        motion = MotionBridge(this, messenger)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (ar?.onRequestPermissionsResult(requestCode) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ar?.dispose()
        ar = null
        media?.dispose()
        narration?.dispose()
        narration = null
        motion?.dispose()
        motion = null
        media = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
