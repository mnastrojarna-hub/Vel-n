# PLAY-FIXES-REPORT — com.motogo24.app 1.1.1 (větev `claude/play-fixes`)

Stav k 2026-06-11. Prostředí bez Flutter SDK → vše, co vyžaduje `flutter` CLI
nebo Android build, je připraveno + popsáno níže v „Co zbývá na člověka".

---

## 1. CO JE OPRAVENO (v tomto branchi)

### PRIORITA 1 — App Links pro motogo24.cz

| Soubor | Změna |
|--------|-------|
| `motogo-web-php/.well-known/assetlinks.json` | **NOVÝ** — Digital Asset Links pro `com.motogo24.app`, oba SHA-256 otisky (upload + Play App Signing). Apache ho servíruje přímo (200). |
| `motogo-web-php/index.php` | **NOVÁ routa** `/.well-known/assetlinks.json` úplně na začátku (před i18n, Supabase, page cache i jazykovými redirecty — stejný vzor jako robots.txt). Vrací `Content-Type: application/json`, žádný redirect, inline JSON fallback kdyby fyzický soubor na hostingu chyběl. |
| `motogo-web-php/.htaccess` | Všechna tři kanonická redirect pravidla (IP→www, holá doména→www, HTTP→HTTPS) mají novou podmínku `RewriteCond %{REQUEST_URI} !^/\.well-known/` → celý `/.well-known/` odpovídá **200 přímo, bez 30x**. Navíc sekce 5b: explicitní `AddType application/json .json` (Google kontroluje přesný Content-Type). |
| `Motogo-app-main/motogo-app-flutter/android/.../AndroidManifest.xml` | App Links intent-filter rozšířen o host `www.motogo24.cz` (vedle `motogo24.cz`), scheme https, pathPrefix `/app` beze změny. |

**⚠️ KRITICKÉ — mimo dosah tohoto repa:** holou doménu `motogo24.cz` u `.cz`
řeší **Forpsi proxy** (viz komentář v .htaccess, sekce 1 — „.cz je na Forpsi,
tam www řeší proxy"). Pokud Forpsi dělá redirect holé domény na www **před**
tím, než request dorazí na Hosting90, .htaccess to nespraví a ověření pro host
`motogo24.cz` selže dál. Nutno ověřit/nastavit u Forpsi (viz §4).

### PRIORITA 2 — manifest

Ověřeno ve zdrojovém manifestu (`android/app/src/main/AndroidManifest.xml`):

- ✅ `<uses-feature android:name="android.hardware.telephony" android:required="true"/>` — phone-only, řádek 41
- ✅ `READ_MEDIA_IMAGES` + `READ_MEDIA_VIDEO` s `tools:node="remove"` (odstraní je i z manifestů mergnutých z pluginů)
- ✅ **NOVĚ přidáno:** `com.google.android.gms.permission.AD_ID` s `tools:node="remove"` — appka nemá reklamy/analytics (jen firebase-messaging, ten AD_ID netahá), remove je pojistka proti transitivnímu úniku vs. Data safety deklarace
- ✅ `READ/WRITE_EXTERNAL_STORAGE` zůstávají jen s `maxSdkVersion` 32/29 (legacy Android ≤12) — Play je na 13+ nevidí

**Photo Picker:** `image_picker: ^1.0.5` bez commitnutého `pubspec.lock` →
Codemagic resolvuje aktuální `image_picker_android` (≥0.8.12), který na
Androidu 13+ používá systémový Photo Picker **automaticky** (bez oprávnění).
Kód nikde nenastavuje `useAndroidPhotoPicker` ani nečte galerii jinak.

**Navazující oprava (nutná!):** `lib/core/native/permission_service.dart`
žádal `Permission.photos`, které se na Androidu 13+ mapuje na právě odstraněné
`READ_MEDIA_IMAGES` → systém by request tiše zamítl a v profilu/nastavení by
viselo věčně červené „neuděleno". Opraveno platformově: Android photos nežádá
ani nezobrazuje (Photo Picker oprávnění nepotřebuje), iOS beze změny.
Onboarding overlay (UI) je beze změny.

### PRIORITA 3 — kvalita (co šlo udělat staticky)

- **Oprávnění (princip minima):** v manifestu zůstává INTERNET, NETWORK_STATE,
  FINE/COARSE_LOCATION (SOS + mapa), CAMERA (sken dokladů, SOS foto),
  BIOMETRIC/FINGERPRINT (local_auth), VIBRATE, POST_NOTIFICATIONS +
  BOOT_COMPLETED + WAKE_LOCK (FCM). Vše má reálné použití v kódu. Nic navíc.
- **ACCESS_FINE_LOCATION — rationale/disclosure:** ✅ v pořádku.
  `PermissionOverlay` (onboarding) zobrazuje PŘED systémovým dialogem
  vysvětlení per oprávnění („Navigace, sdílení pozice při poruše"), tlačítko
  „Povolit vše" + možnost přeskočit. SOS (`sos_provider._getGps`) pak
  oprávnění jen kontroluje, nežádá; bez grantu se poloha prostě nesdílí.
  Lokace jen foreground (žádné ACCESS_BACKGROUND_LOCATION) → prominentní
  disclosure splněna overlayem.
  - 💡 Drobnost k uvážení (NEMĚNĚNO — UX): overlay zobrazuje i řádek
    🎤 mikrofon, ale RECORD_AUDIO v manifestu není a nikde se nežádá.
    Kosmeticky matoucí, Play to neblokuje.
- **proguard-rules.pro:** ✅ Stripe (`com.stripe.android.**` keep+dontwarn),
  Firebase keep, OkHttp/Okio dontwarn, Flutter keep, Play Core dontwarn/keep.
  webview_flutter si keep rules nese v pluginu (consumer rules) — netřeba nic.
- **Deep linky (statická verifikace kódu):**
  - `https://motogo24.cz/app` + nově `https://www.motogo24.cz/app` — autoVerify intent-filter ✅
  - `motogo24://payment` — vlastní scheme intent-filter ✅, odpovídá
    `stripe_service.dart:195` (`returnURL: 'motogo24://payment'`) ✅
  - `link-popup://complete/...` — **v celém repu se nevyskytuje** (žádný kód,
    žádný intent-filter). Pochází zřejmě ze starého Capacitor buildu; ve
    Flutter appce není co opravovat. Pokud ho něco reálně volá, dej vědět kde.
- **Pomlčky:** žádné `--` v žádném stringu v `lib/` ✅. Typografické pomlčky
  („2–7 dní", „Ověřeno – přihlašuji…") v překladech jsou záměrné lidské texty
  (495 výskytů) — hromadná náhrada by porušila pravidlo „neměň UX texty",
  takže NEMĚNĚNO.
- **Verze:** `pubspec.yaml` = `1.1.1+1`; versionCode dodá Codemagic
  (`--build-number=$BUILD_NUMBER`), takže nový build bude 1.1.1 s versionCode > 19.

### Co NEŠLO spustit (chybí Flutter SDK v prostředí)

`flutter analyze`, `dart format .`, `flutter test`, `flutter pub outdated`,
`flutter build appbundle` + kontrola merged manifestu. Příkazy viz §4.

---

## 2. CO NASADIT NA WEB (Hosting90)

Nahrát z `motogo-web-php/`: **`.htaccess`**, **`index.php`**,
**`.well-known/assetlinks.json`**. Pak ověřit (obě domény, http i https):

```bash
curl -sI https://motogo24.cz/.well-known/assetlinks.json      # → HTTP/2 200, content-type: application/json
curl -sI https://www.motogo24.cz/.well-known/assetlinks.json  # → HTTP/2 200, content-type: application/json
curl -sI http://motogo24.cz/.well-known/assetlinks.json       # → 200 (NE 301!)
curl -s  https://motogo24.cz/.well-known/assetlinks.json | python3 -m json.tool   # validní JSON s oběma otisky
# Google ověřovač:
curl -s "https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://motogo24.cz&relation=delegate_permission/common.handle_all_urls"
```

Pokud `https://motogo24.cz/...` vrací 301 → redirect dělá **Forpsi proxy**,
ne náš .htaccess → viz §4 bod 2.

---

## 3. CO CHCE NOVÝ BUILD (Codemagic)

Manifest se změnil (www host + AD_ID remove) a permission_service.dart také →
**nový AAB** přes Codemagic Android workflow (versionName 1.1.1, versionCode
auto). Po buildu zkontrolovat merged manifest:

```bash
java -jar bundletool.jar dump manifest --bundle app-release.aab > merged.xml
grep -E "READ_MEDIA_IMAGES|READ_MEDIA_VIDEO|AD_ID" merged.xml   # → NESMÍ nic najít
grep -E "telephony|www\.motogo24\.cz" merged.xml                # → required=true + oba hosty
```

---

## 4. CO ZBÝVÁ NA ČLOVĚKA

1. **Deploy webu** (§2) + curl ověření.
2. **Forpsi (.cz DNS/proxy):** ověřit, že požadavek na holou
   `https://motogo24.cz/.well-known/assetlinks.json` doteče na Hosting90 s 200
   a neredirectuje na www už na proxy. Pokud redirectuje → u Forpsi vyjmout
   `/.well-known/` z redirectu, nebo nasměrovat holou doménu přímo na hosting.
3. **Codemagic build** (§3) + nahrát AAB do Play Console.
4. **Play Console → Nastavení → Přímé odkazy (App Links) → „Znovu ověřit"**
   až bude web nasazený (ověření může trvat i pár hodin; nový AAB pro samotné
   ověření domény nutný není, pro www host ano).
5. **Lokálně / v CI spustit:** `flutter analyze` (opravit případné nové
   warnings), `dart format .`, `flutter test`, `flutter pub outdated`
   (bezpečné = patch/minor v rámci `^` constraints; `app_links` držet <7.0.0
   — viz dependency_overrides v pubspec).
6. **Runtime test deep linků** na zařízení s nainstalovaným buildem:
   ```bash
   adb shell pm get-app-links com.motogo24.app    # → motogo24.cz i www: verified
   adb shell am start -a android.intent.action.VIEW -d "https://motogo24.cz/app"
   adb shell am start -a android.intent.action.VIEW -d "https://www.motogo24.cz/app"
   adb shell am start -a android.intent.action.VIEW -d "motogo24://payment"
   ```
   Stripe Payment Sheet end-to-end: testovací platba → návrat do appky.
7. (Volitelné) odstranit 🎤 mikrofon z onboarding overlaye — viz §1/P3.
