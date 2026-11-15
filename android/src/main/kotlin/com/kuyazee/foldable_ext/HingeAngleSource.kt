package com.kuyazee.foldable_ext

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import io.flutter.plugin.common.EventChannel

/**
 * Reads `Sensor.TYPE_HINGE_ANGLE` and forwards each reading to one event sink.
 *
 * The sensor listener is registered only between `onListen` and `onCancel`,
 * so an app that never listens costs no sensor power.
 *
 * `sdkInt` is a parameter so the unit tests can stand in for an API level.
 */
internal class HingeAngleSource(
    private val sensorManager: SensorManager?,
    sdkInt: Int = Build.VERSION.SDK_INT,
) : EventChannel.StreamHandler,
    SensorEventListener {
    // TYPE_HINGE_ANGLE arrived in API 30 (Android 11). Older devices have no
    // standard hinge sensor, so they report none.
    private val sensor: Sensor? =
        if (sdkInt >= Build.VERSION_CODES.R) {
            sensorManager?.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE)
        } else {
            null
        }

    private var sink: EventChannel.EventSink? = null
    private var registered = false
    private var lastAngle: Double? = null

    val hasHingeSensor: Boolean
        get() = sensor != null

    /** The reply to the `getHingeInfo` method call. */
    fun info(): Map<String, Any?> =
        mapOf(
            "hasHingeSensor" to hasHingeSensor,
            "angle" to lastAngle,
        )

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink,
    ) {
        val hingeSensor = sensor
        if (hingeSensor == null || sensorManager == null) {
            events.endOfStream()
            return
        }
        sink = events
        if (!registered) {
            // The three-argument overload delivers on the main thread, which
            // is the thread an EventSink has to be called on.
            registered =
                sensorManager.registerListener(
                    this,
                    hingeSensor,
                    SensorManager.SENSOR_DELAY_UI,
                )
        }
    }

    override fun onCancel(arguments: Any?) {
        stop()
    }

    /** Unregisters the sensor listener. Safe to call more than once. */
    fun stop() {
        sink = null
        if (registered) {
            sensorManager?.unregisterListener(this)
            registered = false
        }
        // A reading goes stale once nobody listens, so do not keep it.
        lastAngle = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        val values = event.values
        if (event.sensor.type == Sensor.TYPE_HINGE_ANGLE && values != null && values.isNotEmpty()) {
            onAngle(values[0])
        }
    }

    /** Takes one reading in degrees: 0 closed, 180 flat. */
    fun onAngle(degrees: Float) {
        if (degrees.isNaN()) return
        val angle = degrees.toDouble()
        lastAngle = angle
        sink?.success(angle)
    }

    override fun onAccuracyChanged(
        sensor: Sensor?,
        accuracy: Int,
    ) = Unit
}
