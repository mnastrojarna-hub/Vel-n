package com.motogo24.app

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15 (SDK 35): zpětně kompatibilní edge-to-edge.
        // Google Play doporučení — zajistí korektní zobrazení bez okrajů
        // (transparentní systémové lišty) i na Androidu < 15 a vyhne se
        // zastaralým Window.set*BarColor API. Volat PŘED super.onCreate().
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine) // registrace pluginů — povinné
        // Dart: PushService.clearDelivered() — otevření appky = zákazník upozornění viděl.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cz.motogo24/notifications")
            .setMethodCallHandler { call, result ->
                if (call.method == "clearAll") {
                    clearDeliveredNotifications()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * Zruší doručené notifikace appky v liště (FCM push) → zmizí i odznak na
     * ikoně (Samsung One UI počítá notifikace v liště). Probíhající notifikace
     * (ongoing / služba na popředí — záznam jízdy) se NEruší.
     */
    private fun clearDeliveredNotifications() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                nm.cancelAll()
                return
            }
            val keep = Notification.FLAG_ONGOING_EVENT or Notification.FLAG_FOREGROUND_SERVICE
            for (sbn in nm.activeNotifications) {
                if ((sbn.notification.flags and keep) != 0) continue
                nm.cancel(sbn.tag, sbn.id)
            }
        } catch (e: Exception) {
            // mazání lišty je jen pohodlí — appku nesmí shodit
        }
    }
}
