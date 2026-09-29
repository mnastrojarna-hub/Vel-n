package com.motogo24.app

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val pdfExecutor = Executors.newSingleThreadExecutor()

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
        // Dart: PdfPagesScreen — PDF smlouvy/protokolu v appce (WebView na Androidu PDF neumí).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cz.motogo24/pdf")
            .setMethodCallHandler { call, result ->
                val bytes = call.argument<ByteArray>("bytes")
                if (call.method != "render" || bytes == null) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val width = (call.argument<Int>("width") ?: 1200).coerceIn(400, 2000)
                val main = Handler(Looper.getMainLooper())
                pdfExecutor.execute {
                    try {
                        val pages = renderPdf(bytes, width)
                        main.post { result.success(pages) }
                    } catch (e: Throwable) {
                        main.post { result.error("render", e.message, null) }
                    }
                }
            }
    }

    /** PDF → PNG stránky přes nativní PdfRenderer (API 21+), max [MAX_PDF_PAGES] stran. */
    private fun renderPdf(bytes: ByteArray, width: Int): List<ByteArray> {
        val out = ArrayList<ByteArray>()
        val file = File.createTempFile("mg_doc", ".pdf", cacheDir)
        try {
            file.writeBytes(bytes)
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                PdfRenderer(pfd).use { renderer ->
                    for (i in 0 until minOf(renderer.pageCount, MAX_PDF_PAGES)) {
                        renderer.openPage(i).use { page ->
                            val h = (width.toLong() * page.height / page.width.coerceAtLeast(1)).toInt().coerceAtLeast(1)
                            val bmp = Bitmap.createBitmap(width, h, Bitmap.Config.ARGB_8888)
                            bmp.eraseColor(Color.WHITE) // PdfRenderer kreslí na průhledné pozadí
                            page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            val bos = ByteArrayOutputStream()
                            bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
                            bmp.recycle()
                            out.add(bos.toByteArray())
                        }
                    }
                }
            }
        } finally {
            file.delete()
        }
        return out
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

    companion object {
        private const val MAX_PDF_PAGES = 40
    }
}
