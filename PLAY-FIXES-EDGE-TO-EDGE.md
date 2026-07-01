# PLAY-FIXES — Android 15 edge-to-edge (com.motogo24.app)

Reakce na 2 doporučené akce v Google Play Console (Produkce, vydání 50 / 2.0.9):

1. **„Zobrazení bez okrajů nemusí fungovat u všech uživatelů"** — od Androidu 15
   (target SDK 35) je edge-to-edge výchozí.
2. **„Aplikace používá k zobrazení bez okrajů zastaralá rozhraní API nebo
   parametry"** — `android.view.Window.setStatusBarColor` /
   `setNavigationBarColor` / `getStatusBarColor`.

## Co je opraveno (větev `claude/google-app-nuances-01bv23`)

| Soubor | Změna |
|--------|-------|
| `Motogo-app-main/motogo-app-flutter/lib/main.dart` | Explicitně zapnut `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)`. `SystemUiOverlayStyle` má teď **průhledné** status i navigation lišty (`systemNavigationBarColor: Colors.transparent` místo `Colors.black`) + vypnutý contrast enforcement. Tím se appka přestane dovolávat zastaralého `Window.setNavigationBarColor` (neprůhledná černá nav lišta ho volala). |
| `…/android/app/src/main/java/com/motogo24/app/MainActivity.kt` | `override onCreate` → `enableEdgeToEdge()` **před** `super.onCreate()`. Přesně to, co Play doporučuje pro zpětnou kompatibilitu (pokryje i Android < 15). |
| `…/android/app/build.gradle` | Přidána závislost `androidx.activity:activity-ktx:1.9.3`, která `enableEdgeToEdge()` poskytuje (FlutterFragmentActivity → FragmentActivity → ComponentActivity). |

Vizuálně beze změny: appka je tmavá (window background černá), takže obsah za
průhlednou lištou vypadá stejně jako dřív černá lišta — jen už nepoužívá
zastaralé API.

## Co zůstává mimo dosah app kódu

Část hlášených volání `set*BarColor` / `configureStatusBarForFullscreenFlutterExperience`
pochází z **Flutter engine** a pluginů (`flutter_stripe`/`com.stripe.android`,
`image_picker`, `webview_flutter`, `camerax`, `firebase_messaging`,
`in_app_update`). Ty zmizí až s upgradem Flutter SDK / pluginů na verze, které
už používají nové AndroidX windowing API — není to změna v naší kódové bázi.
Naše appka po této opravě sama žádné zastaralé API nevolá a do edge-to-edge se
hlásí korektně.

## Co zbývá na člověka

1. **Nový build** (Codemagic Android workflow) → AAB do Play Console
   (versionCode auto přes `--build-number`).
2. Na zařízení s Androidem 15 ověřit, že obsah není schovaný pod systémovými
   lištami (Scaffold/SafeArea to řeší) a že platba (Stripe Payment Sheet),
   kamera a webview vypadají správně.
3. Případně naplánovat upgrade Flutter SDK kvůli zbylým plugin/engine voláním.
