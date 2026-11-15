package com.kuyazee.foldable_ext

import android.hardware.Sensor
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals

/*
 * Unit tests for the hinge sensor lifecycle behind the two channels.
 *
 * Run them from `example/android/` with `./gradlew :foldable_ext:testDebugUnitTest`
 * after the example app has been built once.
 */
internal class HingeAngleSourceTest {
    private val hingeSdk = 30

    private fun managerWithSensor(): Pair<SensorManager, Sensor> {
        val sensor = Mockito.mock(Sensor::class.java)
        val manager = Mockito.mock(SensorManager::class.java)
        Mockito.`when`(manager.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE)).thenReturn(sensor)
        Mockito
            .`when`(manager.registerListener(anyListener(), Mockito.eq(sensor), Mockito.anyInt()))
            .thenReturn(true)
        return manager to sensor
    }

    private fun anyListener(): SensorEventListener? = Mockito.any(SensorEventListener::class.java)

    private fun anySensor(): Sensor? = Mockito.any(Sensor::class.java)

    private fun sink(): EventChannel.EventSink = Mockito.mock(EventChannel.EventSink::class.java)

    @Test
    fun noSensor_endsTheStreamAtOnce() {
        val manager = Mockito.mock(SensorManager::class.java)
        val source = HingeAngleSource(manager, hingeSdk)
        val events = sink()

        source.onListen(null, events)

        Mockito.verify(events).endOfStream()
        Mockito.verify(manager, Mockito.never()).registerListener(anyListener(), anySensor(), Mockito.anyInt())
        assertEquals(mapOf("hasHingeSensor" to false, "angle" to null), source.info())
    }

    @Test
    fun belowApi30_neverAsksForTheSensor() {
        val (manager, _) = managerWithSensor()
        val source = HingeAngleSource(manager, 29)
        val events = sink()

        source.onListen(null, events)

        Mockito.verify(manager, Mockito.never()).getDefaultSensor(Mockito.anyInt())
        Mockito.verify(events).endOfStream()
        assertEquals(false, source.hasHingeSensor)
    }

    @Test
    fun missingSensorManager_endsTheStream() {
        val source = HingeAngleSource(null, hingeSdk)
        val events = sink()

        source.onListen(null, events)

        Mockito.verify(events).endOfStream()
    }

    @Test
    fun registersOnlyWhileListening() {
        val (manager, sensor) = managerWithSensor()
        val source = HingeAngleSource(manager, hingeSdk)

        Mockito.verify(manager, Mockito.never()).registerListener(anyListener(), anySensor(), Mockito.anyInt())

        source.onListen(null, sink())
        Mockito.verify(manager).registerListener(source, sensor, SensorManager.SENSOR_DELAY_UI)

        source.onCancel(null)
        Mockito.verify(manager).unregisterListener(source)
    }

    @Test
    fun stopWithoutListener_doesNothing() {
        val (manager, _) = managerWithSensor()
        val source = HingeAngleSource(manager, hingeSdk)

        source.stop()

        Mockito.verify(manager, Mockito.never()).unregisterListener(source)
    }

    @Test
    fun readingsReachTheSinkAndTheInfoMap() {
        val (manager, _) = managerWithSensor()
        val source = HingeAngleSource(manager, hingeSdk)
        val events = sink()
        source.onListen(null, events)

        source.onAngle(92.5f)

        Mockito.verify(events).success(92.5)
        assertEquals(mapOf("hasHingeSensor" to true, "angle" to 92.5), source.info())
    }

    @Test
    fun cancelStopsEventsAndDropsTheLastReading() {
        val (manager, _) = managerWithSensor()
        val source = HingeAngleSource(manager, hingeSdk)
        val events = sink()
        source.onListen(null, events)
        source.onAngle(180f)

        source.onCancel(null)
        assertEquals(mapOf("hasHingeSensor" to true, "angle" to null), source.info())

        source.onAngle(90f)
        Mockito.verify(events, Mockito.never()).success(90.0)
    }
}
