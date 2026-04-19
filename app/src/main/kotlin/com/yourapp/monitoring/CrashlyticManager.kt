package com.yourapp.monitoring

import com.google.firebase.crashlytics.FirebaseCrashlytics
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Crashlytics Integration Manager
 */
@Singleton
class CrashlyticManager @Inject constructor() {

    private val crashlytics = FirebaseCrashlytics.getInstance()

    init {
        setupCrashHandler()
        plant Timber Tree
    }

    private fun setupCrashHandler() {
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, exception ->
            recordException(exception)
            defaultHandler?.uncaughtException(thread, exception)
        }
    }

    fun recordException(exception: Exception) {
        try {
            crashlytics.recordException(exception)
            Timber.e(exception, "Exception recorded in Crashlytics")
        } catch (e: Exception) {
            Timber.e(e, "Error recording exception")
        }
    }

    fun recordMessage(message: String) {
        crashlytics.log(message)
    }

    fun setUserId(userId: String) {
        crashlytics.setUserId(userId)
    }

    fun setCustomKey(key: String, value: String) {
        crashlytics.setCustomKey(key, value)
    }

    fun setCustomKey(key: String, value: Int) {
        crashlytics.setCustomKey(key, value)
    }

    fun setCustomKey(key: String, value: Boolean) {
        crashlytics.setCustomKey(key, value)
    }

    private inner class CrashlyticsTree : Timber.Tree() {
        override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
            if (priority >= Timber.ERROR) {
                crashlytics.log("[$tag] $message")
                t?.let { crashlytics.recordException(it) }
            }
        }
    }
}
