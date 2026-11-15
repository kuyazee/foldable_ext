package com.kuyazee.foldable_ext

import android.content.Context
import android.hardware.SensorManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Reports the hinge angle of an Android foldable to Dart.
 *
 * The fold bounds and posture never pass through here. Dart reads those from
 * the `dart:ui` display features, so this plugin has no dependencies.
 */
class FoldableExtPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var hinge: HingeAngleSource? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val sensorManager =
            binding.applicationContext.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val source = HingeAngleSource(sensorManager)
        hinge = source

        methodChannel =
            MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
                it.setMethodCallHandler(this)
            }
        eventChannel =
            EventChannel(binding.binaryMessenger, HINGE_ANGLE_CHANNEL).also {
                it.setStreamHandler(source)
            }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        val source = hinge
        if (call.method == "getHingeInfo" && source != null) {
            result.success(source.info())
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        // Clearing the stream handler does not call onCancel, so stop the
        // sensor here as well.
        hinge?.stop()
        hinge = null
    }

    companion object {
        const val METHOD_CHANNEL = "com.kuyazee.foldable_ext/methods"
        const val HINGE_ANGLE_CHANNEL = "com.kuyazee.foldable_ext/hinge_angle"
    }
}
