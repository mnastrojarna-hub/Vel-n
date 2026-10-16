package com.motogo24.app

import android.app.ActivityManager
import android.content.Context
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

    /** Kanál pro Dart (`RideKeepAlive`). Nedrží odkaz na okno. */
    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "keepAlive") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val on = call.argument<Boolean>("on") == true
                if (on) keepAlive.add(engine) else keepAlive.remove(engine)
                result.success(null)
                if (!on && parked === engine) destroyLaterIfIdle(engine)
            }
    }

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
