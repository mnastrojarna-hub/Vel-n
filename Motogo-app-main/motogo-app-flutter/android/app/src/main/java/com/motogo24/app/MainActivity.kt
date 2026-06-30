package com.motogo24.app

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15 (SDK 35): zpětně kompatibilní edge-to-edge.
        // Google Play doporučení — zajistí korektní zobrazení bez okrajů
        // (transparentní systémové lišty) i na Androidu < 15 a vyhne se
        // zastaralým Window.set*BarColor API. Volat PŘED super.onCreate().
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }
}
