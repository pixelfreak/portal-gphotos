package com.ramnat.portalgphotos

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            ScreensaverGuard.applyNow(context)
            ScreensaverGuard.scheduleBootReassert(context)
            ScreensaverGuard.ensureScheduled(context)
        }
    }
}
