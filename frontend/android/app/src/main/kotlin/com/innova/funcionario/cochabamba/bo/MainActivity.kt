package com.innova.funcionario.cochabamba.bo

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.BatteryManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val kioskChannelName = "com.innova.funcionario.cochabamba.bo/kiosk"
    private val deviceStatusChannelName = "com.innova.funcionario.cochabamba.bo/device_status"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            kioskChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableLunchKiosk" -> result.success(enableLunchKiosk())
                "disableLunchKiosk" -> {
                    disableLunchKiosk()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deviceStatusChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "readDeviceStatus" -> result.success(readDeviceStatus())
                else -> result.notImplemented()
            }
        }
    }

    private fun enableLunchKiosk(): Boolean {
        val devicePolicyManager =
            getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

        if (!devicePolicyManager.isDeviceOwnerApp(packageName)) {
            return false
        }

        val admin = ComponentName(this, KioskDeviceAdminReceiver::class.java)
        devicePolicyManager.setLockTaskPackages(admin, arrayOf(packageName))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            devicePolicyManager.setKeyguardDisabled(admin, true)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            devicePolicyManager.setLockTaskFeatures(
                admin,
                DevicePolicyManager.LOCK_TASK_FEATURE_NONE
            )
        }

        applyLunchKioskDisplayPolicy()
        startLockTask()
        return true
    }

    private fun disableLunchKiosk() {
        try {
            stopLockTask()
        } catch (_: IllegalStateException) {
            // La app puede no estar en lock task si Android aun no lo inicio.
        }
        clearLunchKioskDevicePolicy()
        clearLunchKioskDisplayPolicy()
    }

    private fun clearLunchKioskDevicePolicy() {
        val devicePolicyManager =
            getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

        if (!devicePolicyManager.isDeviceOwnerApp(packageName)) {
            return
        }

        val admin = ComponentName(this, KioskDeviceAdminReceiver::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            devicePolicyManager.setKeyguardDisabled(admin, false)
        }
    }

    private fun applyLunchKioskDisplayPolicy() {
        runOnUiThread {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            val attributes = window.attributes
            attributes.screenBrightness = 0.8f
            window.attributes = attributes
        }
    }

    private fun clearLunchKioskDisplayPolicy() {
        runOnUiThread {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            val attributes = window.attributes
            attributes.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
            window.attributes = attributes
        }
    }

    private fun readDeviceStatus(): Map<String, Any?> {
        val batteryIntent = registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val batteryLevel = if (level >= 0 && scale > 0) {
            (level * 100) / scale
        } else {
            null
        }
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        val brightness = try {
            val rawBrightness = Settings.System.getInt(
                contentResolver,
                Settings.System.SCREEN_BRIGHTNESS
            )
            (rawBrightness * 100) / 255
        } catch (_: Settings.SettingNotFoundException) {
            null
        }

        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "androidSdk" to Build.VERSION.SDK_INT,
            "batteryLevel" to batteryLevel,
            "isCharging" to isCharging,
            "brightness" to brightness
        )
    }
}
