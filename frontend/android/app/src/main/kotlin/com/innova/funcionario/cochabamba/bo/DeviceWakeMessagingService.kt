package com.innova.funcionario.cochabamba.bo

import android.content.Context
import android.content.Intent
import android.os.PowerManager
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class DeviceWakeMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        val data = message.data
        if (
            data["source"] != "innovafuncionario" ||
            data["type"] != "device_login" ||
            data["action"] != "open_app"
        ) {
            return
        }

        openApp()
    }

    private fun openApp() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val wakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
            "$packageName:DeviceLoginWake"
        )
        wakeLock.setReferenceCounted(false)
        wakeLock.acquire(10000L)

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)

        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        )

        try {
            startActivity(launchIntent)
        } catch (_: RuntimeException) {
            // Android puede bloquear aperturas desde segundo plano en algunos equipos.
        }
    }
}
