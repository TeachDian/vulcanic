package com.teachdian.vulcanic.motion

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Streams which way is up.
 *
 * The gravity sensor reports, in the phone's own axes (X right, Y toward
 * the top of the screen, Z out of the screen), the direction that points
 * away from the ground. Marker mode uses it to keep the volcano level
 * instead of guessing the marker's tilt from the camera image.
 *
 * The sensor only runs while Flutter is listening and the app is in the
 * foreground.
 */
class MotionBridge(private val activity: Activity, messenger: BinaryMessenger) :
    EventChannel.StreamHandler, SensorEventListener, DefaultLifecycleObserver {

    private val channel = EventChannel(messenger, "vulcanic/gravity")
    private val sensors = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    // Not every phone has the fused gravity sensor; the accelerometer is
    // the same thing plus hand shake, which the listener smooths out.
    private val sensor: Sensor? =
        sensors.getDefaultSensor(Sensor.TYPE_GRAVITY)
            ?: sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private var sink: EventChannel.EventSink? = null

    init {
        channel.setStreamHandler(this)
        (activity as? LifecycleOwner)?.lifecycle?.addObserver(this)
    }

    fun dispose() {
        (activity as? LifecycleOwner)?.lifecycle?.removeObserver(this)
        channel.setStreamHandler(null)
        sensors.unregisterListener(this)
        sink = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (sensor == null) {
            events?.endOfStream()
            return
        }
        sensors.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
    }

    override fun onCancel(arguments: Any?) {
        sensors.unregisterListener(this)
        sink = null
    }

    // No point measuring gravity for a screen nobody is looking at.
    override fun onPause(owner: LifecycleOwner) {
        sensors.unregisterListener(this)
    }

    override fun onResume(owner: LifecycleOwner) {
        if (sink != null && sensor != null) {
            sensors.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
        }
    }

    override fun onSensorChanged(event: SensorEvent) {
        sink?.success(doubleArrayOf(
            event.values[0].toDouble(),
            event.values[1].toDouble(),
            event.values[2].toDouble(),
        ))
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
