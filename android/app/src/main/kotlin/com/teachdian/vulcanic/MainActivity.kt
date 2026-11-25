package com.teachdian.vulcanic

import com.teachdian.vulcanic.ar.ArBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var ar: ArBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ar = ArBridge(this, flutterEngine.dartExecutor.binaryMessenger, flutterEngine.renderer)
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
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
