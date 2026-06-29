package com.motogo24.motogo_locker_kiosk

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Kiosk MainActivity — lock task (screen pinning) + platform channel pro odemčení.
// Tento soubor CI (codemagic) zkopíruje přes vygenerovaný MainActivity.kt.
class MainActivity : FlutterActivity() {
    private val channelName = "motogo24.kiosk/lock"
    private var kioskUnlocked = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "lockKiosk" -> { kioskUnlocked = false; tryLock(); result.success(true) }
                    "unlockKiosk" -> { kioskUnlocked = true; tryUnlock(); result.success(true) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun tryLock() { try { startLockTask() } catch (e: Exception) {} }
    private fun tryUnlock() { try { stopLockTask() } catch (e: Exception) {} }

    override fun onResume() {
        super.onResume()
        // Po zadání servisního hesla může technik kiosk odemknout; jinak drží lock task.
        if (!kioskUnlocked) tryLock()
    }
}
