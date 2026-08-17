package com.ramnat.portalgphotos

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Portal's launcher repoints `screensaver_components` at its own HomeDreamService on every boot.
 * Waking from that Dream lands on the Portal home screen instead of resuming the app that was in
 * front. Neither `screensaver_enabled=0` nor `screensaver_activate_on_sleep=0` suppresses it —
 * repointing the component is the only thing that restores wake-to-last-app.
 *
 * This does not register a Dream of our own; it only steers the setting away from the launcher.
 *
 * Needs WRITE_SECURE_SETTINGS, granted once over adb (survives reboot and in-place updates):
 *   adb shell pm grant com.ramnat.portalgphotos android.permission.WRITE_SECURE_SETTINGS
 */
object ScreensaverGuard {
    private const val KEY = "screensaver_components"
    private const val LAUNCHER_PKG = "com.facebook.alohaapps.launcher"
    private const val WORK_NAME = "screensaver_guard"
    private const val BOOT_WORK_NAME = "screensaver_guard_boot"

    /** Repoint the Dream away from the launcher. No-op when it already points elsewhere. */
    fun applyNow(context: Context) {
        val current = runCatching {
            Settings.Secure.getString(context.contentResolver, KEY)
        }.getOrNull().orEmpty()

        if (!current.startsWith("$LAUNCHER_PKG/")) {
            debugLog("ScreensaverGuard") { "component is '$current' — nothing to do" }
            return
        }
        val replacement = pickNonLauncherDream(context)
        if (replacement == null) {
            debugLog("ScreensaverGuard") { "no non-launcher Dream available; leaving '$current'" }
            return
        }
        // Throws SecurityException when WRITE_SECURE_SETTINGS was never granted over adb.
        val ok = runCatching {
            Settings.Secure.putString(context.contentResolver, KEY, replacement)
        }.isSuccess
        debugLog("ScreensaverGuard") { "repoint '$current' -> '$replacement' ok=$ok" }
    }

    /**
     * Prefer the system's recorded default, but only if it resolves and isn't the launcher —
     * the recorded value can name a class that no longer exists.
     */
    private fun pickNonLauncherDream(context: Context): String? {
        val dreams = context.packageManager
            .queryIntentServices(Intent("android.service.dreams.DreamService"), 0)
            .mapNotNull { it.serviceInfo }
            .filter { it.packageName != LAUNCHER_PKG }
            .map { "${it.packageName}/${it.name}" }
        if (dreams.isEmpty()) return null

        val recorded = runCatching {
            Settings.Secure.getString(context.contentResolver, "screensaver_default_component")
        }.getOrNull()
        return dreams.firstOrNull { it == recorded }
            ?: dreams.firstOrNull { recorded?.startsWith("${it.substringBefore('/')}/") == true }
            ?: dreams.first()
    }

    /**
     * The launcher re-asserts its Dream via WorkManager around the same time we do, so a single
     * boot pass loses the race. Retry on a delay, then keep a periodic backstop that also
     * re-seeds itself if the process is killed.
     */
    fun scheduleBootReassert(context: Context) {
        val wm = WorkManager.getInstance(context)
        listOf(30L, 120L, 300L).forEachIndexed { i, delay ->
            wm.enqueueUniqueWork(
                "$BOOT_WORK_NAME$i",
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<ScreensaverWorker>()
                    .setInitialDelay(delay, TimeUnit.SECONDS)
                    .build(),
            )
        }
    }

    fun ensureScheduled(context: Context) {
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<ScreensaverWorker>(15, TimeUnit.MINUTES).build(),
        )
    }
}

class ScreensaverWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        ScreensaverGuard.applyNow(applicationContext)
        return Result.success()
    }
}
