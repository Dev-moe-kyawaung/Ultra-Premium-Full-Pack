package com.yourapp.monitoring

import android.content.Context
import com.google.firebase.analytics.FirebaseAnalytics
import com.yourapp.analytics.EventLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * COMPREHENSIVE Analytics Manager
 */
@Singleton
class AnalyticsManager @Inject constructor(
    private val context: Context,
    private val firebaseAnalytics: FirebaseAnalytics,
    private val performanceMonitor: PerformanceMonitor
) : EventLogger {

    private val _analyticsEvents = MutableStateFlow<AnalyticsEvent?>(null)
    val analyticsEvents: Flow<AnalyticsEvent?> = _analyticsEvents

    data class AnalyticsEvent(
        val eventName: String,
        val parameters: Map<String, Any>,
        val timestamp: Long = System.currentTimeMillis(),
        val eventId: String = "event_${System.nanoTime()}"
    )

    data class UserSessionData(
        val sessionId: String,
        val userId: String,
        val startTime: Long,
        val endTime: Long? = null,
        val duration: Long? = null,
        val screenViews: List<String> = emptyList(),
        val crashes: List<String> = emptyList(),
        val customEvents: List<String> = emptyList()
    )

    // ==================== EVENT LOGGING ====================

    override fun logEvent(eventName: String, params: Map<String, Any>) {
        try {
            val bundle = android.os.Bundle().apply {
                params.forEach { (key, value) ->
                    when (value) {
                        is String -> putString(key, value)
                        is Int -> putInt(key, value)
                        is Long -> putLong(key, value)
                        is Float -> putFloat(key, value)
                        is Double -> putDouble(key, value)
                        is Boolean -> putBoolean(key, value)
                        else -> putString(key, value.toString())
                    }
                }
            }

            firebaseAnalytics.logEvent(eventName, bundle)
            
            val event = AnalyticsEvent(eventName, params)
            _analyticsEvents.value = event
            
            Timber.d("Event logged: $eventName with params: $params")
        } catch (e: Exception) {
            Timber.e(e, "Error logging event: $eventName")
        }
    }

    // ==================== USER TRACKING ====================

    override fun setUserId(userId: String) {
        firebaseAnalytics.setUserId(userId)
        logEvent("user_identified", mapOf("user_id" to userId))
    }

    override fun setUserProperty(name: String, value: String) {
        firebaseAnalytics.setUserProperty(name, value)
    }

    // ==================== SCREEN TRACKING ====================

    fun trackScreenView(screenName: String, screenClass: String) {
        logEvent("screen_view", mapOf(
            "screen_name" to screenName,
            "screen_class" to screenClass
        ))
    }

    // ==================== SESSION TRACKING ====================

    private var sessionStartTime = System.currentTimeMillis()
    private var sessionScreenViews = mutableListOf<String>()

    fun startSession() {
        sessionStartTime = System.currentTimeMillis()
        sessionScreenViews.clear()
        logEvent("session_start", mapOf(
            "timestamp" to sessionStartTime
        ))
    }

    fun endSession() {
        val sessionEndTime = System.currentTimeMillis()
        val sessionDuration = sessionEndTime - sessionStartTime

        logEvent("session_end", mapOf(
            "session_duration_ms" to sessionDuration,
            "screen_views" to sessionScreenViews.size,
            "timestamp" to sessionEndTime
        ))
    }

    // ==================== PURCHASE TRACKING ====================

    fun trackPurchase(
        itemId: String,
        itemName: String,
        price: Double,
        currency: String = "USD",
        quantity: Int = 1
    ) {
        logEvent("purchase", mapOf(
            "item_id" to itemId,
            "item_name" to itemName,
            "price" to price,
            "currency" to currency,
            "quantity" to quantity,
            "value" to (price * quantity)
        ))
    }

    fun trackSubscription(
        tier: String,
        price: Double,
        billingCycle: String
    ) {
        logEvent("subscription", mapOf(
            "tier" to tier,
            "price" to price,
            "billing_cycle" to billingCycle,
            "timestamp" to System.currentTimeMillis()
        ))
    }

    // ==================== ERROR TRACKING ====================

    fun trackError(
        errorType: String,
        errorMessage: String,
        errorCode: Int? = null,
        stackTrace: String? = null
    ) {
        logEvent("error", mapOf(
            "error_type" to errorType,
            "error_message" to errorMessage,
            "error_code" to (errorCode?.toString() ?: ""),
            "stack_trace" to (stackTrace?.take(500) ?: "")
        ))
    }

    // ==================== PERFORMANCE TRACKING ====================

    fun trackPerformanceMetric(
        metricName: String,
        value: Long,
        unit: String = "ms"
    ) {
        logEvent("performance_metric", mapOf(
            "metric_name" to metricName,
            "value" to value,
            "unit" to unit,
            "timestamp" to System.currentTimeMillis()
        ))
    }

    // ==================== FUNNEL TRACKING ====================

    fun trackFunnelStep(
        funnelName: String,
        stepNumber: Int,
        stepName: String
    ) {
        logEvent("funnel_step", mapOf(
            "funnel_name" to funnelName,
            "step_number" to stepNumber,
            "step_name" to stepName,
            "timestamp" to System.currentTimeMillis()
        ))
    }

    fun trackFunnelAbandonment(
        funnelName: String,
        lastStep: Int
    ) {
        logEvent("funnel_abandoned", mapOf(
            "funnel_name" to funnelName,
            "last_step" to lastStep,
            "timestamp" to System.currentTimeMillis()
        ))
    }

    // ==================== CUSTOM METRICS ====================

    fun trackCustomMetric(
        metricName: String,
        value: Double,
        tags: Map<String, String> = emptyMap()
    ) {
        val params = mutableMapOf<String, Any>(
            "metric_value" to value,
            "timestamp" to System.currentTimeMillis()
        )
        params.putAll(tags)

        logEvent("custom_metric_$metricName", params)
    }

    // ==================== CRASH ANALYTICS ====================

    fun trackCrash(
        exceptionType: String,
        message: String,
        stackTrace: String
    ) {
        logEvent("crash_reported", mapOf(
            "exception_type" to exceptionType,
            "message" to message,
            "stack_trace" to stackTrace.take(1000),
            "timestamp" to System.currentTimeMillis()
        ))
    }

    // ==================== FEATURE FLAG TRACKING ====================

    fun trackFeatureUsage(featureName: String, enabled: Boolean) {
        logEvent("feature_usage", mapOf(
            "feature_name" to featureName,
            "enabled" to enabled,
            "timestamp" to System.currentTimeMillis()
        ))
    }

    // ==================== CONSENT TRACKING ====================

    fun trackConsentUpdate(consentType: String, granted: Boolean) {
        logEvent("consent_update", mapOf(
            "consent_type" to consentType,
            "granted" to granted,
            "timestamp" to System.currentTimeMillis()
        ))
    }
}
