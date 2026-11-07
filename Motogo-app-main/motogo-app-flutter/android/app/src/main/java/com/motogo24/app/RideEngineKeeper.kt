package com.motogo24.app

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Collections
import java.util.WeakHashMap

/**
 * Záznam jízdy běží v Dartu a GPS službu na popředí drží plugin geolocator
 * NAVÁZANÝ NA FLUTTER ENGINE. Výchozí Flutter engine ruší se zavřením okna
 * appky (odsunutí z posledních aplikací, Zpět na Androidu 11 a starším) —
 * a s ním i GPS službu: stopa skončila uprostřed vyjížďky (ve Velíně „45 min
 * bez signálu", body až po dalším otevření appky).
 *
 * Proto: dokud Dart hlásí běžící záznam (`cz.motogo24/ride` → keepAlive),
 * zavřené okno engine NEZNIČÍ, ale „zaparkuje" — Dart, GPS služba i odesílání
 * bodů běží dál (proces drží služba na popředí s notifikací). Další otevřené
 * okno si zaparkovaný engine převezme. Bez záznamu jízdy se chová přesně jako
 * dřív: každé okno vlastní engine a při zavření ho zničí.
 */
internal object RideEngineKeeper {
    private const val CHANNEL = "cz.motogo24/ride"
    /** Po skončení záznamu bez otevřeného okna: chvíli nechat Dart dokončit
     *  uklízení (SharedPreferences, poslední odeslání), pak engine zničit. */
    private const val IDLE_DESTROY_MS = 15_000L

    private val keepAlive: MutableSet<FlutterEngine> =
        Collections.newSetFromMap(WeakHashMap())
    private val destroyed: MutableSet<FlutterEngine> =
        Collections.newSetFromMap(WeakHashMap())
    private var parked: FlutterEngine? = null
    private val main = Handler(Looper.getMainLooper())

    /** Je zaparkovaný engine (okno zavřené během jízdy)? */
    fun hasParked(): Boolean = parked != null

    /** Engine pro nové okno: zaparkovaný (true = převzatý), jinak nový. */
    fun obtain(context: Context): Pair<FlutterEngine, Boolean> {
        parked?.let {
            parked = null
            return it to true
        }
        // Stejně jako výchozí engine FlutterFragmentu: pluginy registruje
        // konstruktor, obnova stavu čeká na data od okna.
        val engine = FlutterEngine(context.applicationContext, null, true, true)
        engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {}
            override fun onEngineWillDestroy() {
                destroyed.add(engine)
                keepAlive.remove(engine)
                if (parked === engine) parked = null
            }
        })
        return engine to false
    }

    /** Kanál pro Dart (`RideKeepAlive`). Drží jen aplikační kontext, ne okno. */
    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAlive" -> {
                        val on = call.argument<Boolean>("on") == true
                        if (on) keepAlive.add(engine) else keepAlive.remove(engine)
                        result.success(null)
                        if (!on && parked === engine) destroyLaterIfIdle(engine)
                        // Služba už neběží → případná přepsaná notifikace nesmí zůstat viset.
                        if (!on && !gpsServiceInForeground(app)) cancel(app, NOTIF_ID)
                    }
                    "notify" -> try {
                        result.success(postServiceText(app, call.argument("title"), call.argument("text")))
                    } catch (e: Exception) {
                        result.error("notify_failed", e.toString(), null)
                    }
                    "notifyIdle" -> try {
                        postIdle(app, call.argument("title"), call.argument("text"))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("notify_failed", e.toString(), null)
                    }
                    "cancelIdle" -> {
                        cancel(app, IDLE_ID)
                        result.success(null)
                    }
                    "battery" -> result.success(battery(app))
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Text trvalé notifikace GPS služby podle stavu záznamu (nahrávám /
     * připraveno / pozastaveno). geolocator text za běhu měnit neumí (jen
     * novým spuštěním streamu, což z pozadí nejde) — přepíšeme proto jeho
     * notifikaci (stejné id 75415 a kanál) a jen když jeho služba běží na
     * popředí; jinak false (zůstává statický text).
     */
    private fun postServiceText(ctx: Context, title: String?, text: String?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (title == null || text == null || !gpsServiceInForeground(ctx)) return false
        val n = Notification.Builder(ctx, GEOLOCATOR_CHANNEL)
            .setSmallIcon(icon(ctx))
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(launch(ctx))
            .build()
        manager(ctx).notify(NOTIF_ID, n)
        return true
    }

    /** „Záznam cesty čeká" — pojistka vypnula GPS; klepnutí otevře appku. */
    private fun postIdle(ctx: Context, title: String?, text: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (title == null || text == null) return
        val n = Notification.Builder(ctx, GEOLOCATOR_CHANNEL)
            .setSmallIcon(icon(ctx))
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setContentIntent(launch(ctx))
            .build()
        manager(ctx).notify(IDLE_ID, n)
    }

    private fun cancel(ctx: Context, id: Int) {
        try {
            manager(ctx).cancel(id)
        } catch (e: Exception) {
        }
    }

    private fun battery(ctx: Context): Map<String, Any>? = try {
        val bm = ctx.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val charging = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && bm.isCharging
        mapOf("pct" to pct, "charging" to charging)
    } catch (e: Exception) {
        null
    }

    private fun manager(ctx: Context) =
        ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun icon(ctx: Context): Int {
        val id = ctx.resources.getIdentifier("ic_launcher", "mipmap", ctx.packageName)
        return if (id != 0) id else android.R.drawable.ic_menu_mylocation
    }

    private fun launch(ctx: Context): PendingIntent? {
        val intent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: return null
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getActivity(ctx, 0, intent, flags)
    }

    /** Notifikace GPS služby geolocatoru (id a kanál z GeolocatorLocationService). */
    private const val NOTIF_ID = 75415
    private const val IDLE_ID = 75416
    private const val GEOLOCATOR_CHANNEL = "geolocator_channel_01"

    /** Okno se zavírá: engine s běžícím záznamem zaparkovat, jinak zničit. */
    fun release(engine: FlutterEngine, context: Context) {
        if (engine in destroyed) return
        if (engine in keepAlive && parked == null && gpsServiceInForeground(context)) {
            parked = engine
            return
        }
        engine.destroy()
    }

    /**
     * Běží GPS služba geolocatoru na popředí? Jen ta po zavření okna přežije
     * (stream bez ní — třeba převzatý od navigace — geolocator s oknem
     * odpojí natrvalo) a jen ta drží proces naživu. Bez ní by zaparkovaný
     * engine už nikdy polohu nedostal, tak ho radši zničíme jako dřív.
     */
    @Suppress("DEPRECATION") // vlastní služby appky API pořád vrací
    private fun gpsServiceInForeground(context: Context): Boolean = try {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        am.getRunningServices(Int.MAX_VALUE).any {
            it.foreground && it.service.className == GEOLOCATOR_SERVICE
        }
    } catch (e: Exception) {
        false
    }

    private const val GEOLOCATOR_SERVICE = "com.baseflow.geolocator.GeolocatorLocationService"

    private fun destroyLaterIfIdle(engine: FlutterEngine) {
        main.postDelayed({
            if (parked === engine && engine !in keepAlive && engine !in destroyed) {
                parked = null
                engine.destroy()
            }
        }, IDLE_DESTROY_MS)
    }
}
