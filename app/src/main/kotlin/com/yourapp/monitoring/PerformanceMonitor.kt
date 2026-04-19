package com.yourapp.monitoring

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import android.os.Process
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import com.yourapp.analytics.EventLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import timber.log.Timber
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * ADVANCED Performance Monitoring System
 */
@Singleton
class PerformanceMonitor @Inject constructor(
    private val context: Context,
    private val eventLogger: EventLogger,
    private val dataStore: DataStore<Preferences>
) {

    data class PerformanceMetrics(
        val cpuUsage: Float,
        val memoryUsage: Long,
        val nativeMemory: Long,
        val totalMemory: Long,
        val frameRate: Float,
        val batteryLevel: Int,
        val networkLatency: Long,
        val appStartTime: Long,
        val timestamp: Long = System.currentTimeMillis()
    )

    data class CrashReport(
        val exceptionType: String,
        val message: String,
        val stackTrace: String,
        val threadName: String,
        val timestamp: Long = System.currentTimeMillis()
    )

    data class ANRReport(
        val applicationNotResponding: Boolean,
        val duration: Long,
        val lastFrameTime: Long,
        val timestamp: Long = System.currentTimeMillis()
    )

    // ==================== CPU MONITORING ====================

    fun getCPUUsage(): Float {
        return try {
            val proc = Runtime.getRuntime().exec("top -n 1")
            val lines = proc.inputStream.bufferedReader().readLines()
            
            val cpuLine = lines.find { it.contains(context.packageName) }
            if (cpuLine != null) {
                val cpu = cpuLine.split("\\s+".toRegex())[0].toFloatOrNull() ?: 0f
                Timber.d("CPU Usage: $cpu%")
                return cpu
            }
            0f
        } catch (e: Exception) {
            Timber.e(e, "Error getting CPU usage")
            0f
        }
    }

    // ==================== MEMORY MONITORING ====================

    fun getMemoryUsage(): PerformanceMetrics.MemoryMetrics {
        val runtime = Runtime.getRuntime()
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)

        val nativeHeap = Debug.getNativeHeap()
        val nativeHeapSize = nativeHeap.totalNativeHeap

        return PerformanceMetrics.MemoryMetrics(
            usedMemory = runtime.totalMemory() - runtime.freeMemory(),
            maxMemory = runtime.maxMemory(),
            nativeMemory = nativeHeapSize,
            totalDeviceMemory = memInfo.totalMem,
            availableDeviceMemory = memInfo.availMem,
            isLowMemory = memInfo.lowMemory
        )
    }

    fun monitorMemoryLeaks(): Flow<MemoryLeakReport> {
        return dataStore.data.map { preferences ->
            val previousMemory = preferences[PreferencesKeys.PREVIOUS_MEMORY] ?: 0L
            val currentMemory = Runtime.getRuntime().totalMemory()
            val leakThreshold = 100 * 1024 * 1024 // 100MB

            if (currentMemory - previousMemory > leakThreshold) {
                eventLogger.logEvent("memory_leak_detected", mapOf(
                    "previous_memory" to previousMemory,
                    "current_memory" to currentMemory,
                    "increase" to (currentMemory - previousMemory)
                ))
            }

            MemoryLeakReport(
                leakDetected = currentMemory - previousMemory > leakThreshold,
                memoryIncrease = currentMemory - previousMemory,
                currentMemory = currentMemory
            )
        }
    }

    // ==================== FRAME RATE MONITORING ====================

    var frameCount = 0
    var lastFrameTime = System.nanoTime()

    fun recordFrame() {
        val currentTime = System.nanoTime()
        frameCount++

        val elapsedTime = (currentTime - lastFrameTime) / 1_000_000_000f // Convert to seconds
        if (elapsedTime >= 1.0f) {
            val fps = frameCount / elapsedTime
            Timber.d("FPS: $fps")
            
            // Alert if FPS drops below 30
            if (fps < 30) {
                eventLogger.logEvent("low_frame_rate", mapOf(
                    "fps" to fps.toInt(),
                    "timestamp" to System.currentTimeMillis()
                ))
            }

            frameCount = 0
            lastFrameTime = currentTime
        }
    }

    // ==================== CRASH MONITORING ====================

    fun setupCrashHandler() {
        val defaultUncaughtExceptionHandler = Thread.getDefaultUncaughtExceptionHandler()
        
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            handleUncaughtException(thread, throwable)
            defaultUncaughtExceptionHandler?.uncaughtException(thread, throwable)
        }
    }

    private fun handleUncaughtException(thread: Thread, throwable: Throwable) {
        val crashReport = CrashReport(
            exceptionType = throwable.javaClass.simpleName,
            message = throwable.message ?: "No message",
            stackTrace = throwable.stackTraceToString(),
            threadName = thread.name
        )

        eventLogger.logEvent("app_crash", mapOf(
            "exception_type" to crashReport.exceptionType,
            "message" to crashReport.message,
            "thread" to crashReport.threadName
        ))

        Timber.e(throwable, "Uncaught exception")
    }

    // ==================== ANR MONITORING ====================

    fun setupANRDetection() {
        Thread {
            while (true) {
                val watchdogDelay = TimeUnit.SECONDS.toMillis(5)
                val lastActivityTime = System.currentTimeMillis()
                
                Thread.sleep(watchdogDelay)
                
                val currentTime = System.currentTimeMillis()
                if (currentTime - lastActivityTime > watchdogDelay) {
                    val anrReport = ANRReport(
                        applicationNotResponding = true,
                        duration = currentTime - lastActivityTime,
                        lastFrameTime = System.nanoTime()
                    )
                    
                    eventLogger.logEvent("anr_detected", mapOf(
                        "duration" to anrReport.duration,
                        "timestamp" to anrReport.timestamp
                    ))
                    
                    Timber.e("ANR detected: ${anrReport.duration}ms")
                }
            }
        }.start()
    }

    // ==================== NETWORK MONITORING ====================

    suspend fun measureNetworkLatency(url: String = "https://www.google.com"): Long {
        return try {
            val startTime = System.currentTimeMillis()
            val process = Runtime.getRuntime().exec(arrayOf("ping", "-c", "1", url))
            process.waitFor()
            val endTime = System.currentTimeMillis()
            
            val latency = endTime - startTime
            
            eventLogger.logEvent("network_latency", mapOf(
                "url" to url,
                "latency_ms" to latency
            ))
            
            latency
        } catch (e: Exception) {
            Timber.e(e, "Error measuring network latency")
            -1
        }
    }

    // ==================== BATTERY MONITORING ====================

    fun monitorBattery(): Flow<Int> {
        return dataStore.data.map { preferences ->
            val batteryLevel = preferences[PreferencesKeys.BATTERY_LEVEL] ?: 0
            
            if (batteryLevel < 20) {
                eventLogger.logEvent("low_battery", mapOf(
                    "battery_level" to batteryLevel
                ))
            }
            
            batteryLevel
        }
    }

    // ==================== APP STARTUP TIME ====================

    private var appStartTime = System.currentTimeMillis()

    fun recordAppStartTime() {
        appStartTime = System.currentTimeMillis()
    }

    fun getAppStartupTime(): Long {
        return System.currentTimeMillis() - appStartTime
    }

    // ==================== PREFERENCES ====================

    object PreferencesKeys {
        val PREVIOUS_MEMORY = longPreferencesKey("previous_memory")
        val BATTERY_LEVEL = intPreferencesKey("battery_level")
        val LAST_CRASH_TIME = longPreferencesKey("last_crash_time")
    }
}

data class MemoryMetrics(
    val usedMemory: Long,
    val maxMemory: Long,
    val nativeMemory: Long,
    val totalDeviceMemory: Long,
    val availableDeviceMemory: Long,
    val isLowMemory: Boolean
)

data class MemoryLeakReport(
    val leakDetected: Boolean,
    val memoryIncrease: Long,
    val currentMemory: Long
)
