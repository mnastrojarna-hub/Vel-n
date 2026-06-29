package com.motogo24.motogo_locker_kiosk

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Kiosk MainActivity — lock task (screen pinning) + platform channel:
//   lockKiosk / unlockKiosk  (zámek kiosku, odemčení servisním heslem)
//   installApk(path)         (OTA instalace APK)
//   restartApp               (vzdálený restart)
// CI (codemagic) tento soubor zkopíruje přes vygenerovaný MainActivity.kt.
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
                    "installApk" -> { installApk(call.argument<String>("path")); result.success(true) }
                    "restartApp" -> { result.success(true); restartApp() }
                    else -> result.notImplemented()
                }
            }
    }

    private fun tryLock() { try { startLockTask() } catch (e: Exception) {} }
    private fun tryUnlock() { try { stopLockTask() } catch (e: Exception) {} }

    private fun installApk(path: String?) {
        if (path == null) return
        try {
            val file = File(path)
            val uri: Uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (e: Exception) {}
    }

    private fun restartApp() {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            intent?.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK or Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            Runtime.getRuntime().exit(0)
        } catch (e: Exception) {}
    }

    override fun onResume() {
        super.onResume()
        if (!kioskUnlocked) tryLock()
    }
}
