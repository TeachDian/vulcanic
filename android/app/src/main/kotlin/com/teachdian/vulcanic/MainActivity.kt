package com.teachdian.vulcanic

import com.teachdian.vulcanic.ar.ArBridge
import com.teachdian.vulcanic.media.MediaBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var ar: ArBridge? = null
    private var media: MediaBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        ar = ArBridge(this, messenger, flutterEngine.renderer)
        media = MediaBridge(this, messenger)
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
        media = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
