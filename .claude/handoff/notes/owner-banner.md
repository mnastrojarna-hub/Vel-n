# Workstream: banner (app_settings.header_banner na webu + překlady)

Zadání majitele: „ten banner, který se zobrazuje v aplikaci, by mohl být i na webu nahoře“.

## Formát hodnoty (rozšíření, staré klíče beze změny)
{ enabled, text (CZ), bg, color,
  translations: { en, de, es, fr, nl, pl, uk },   // jen úspěšně přeložené jazyky
  translations_src: "<sha1 hex CZ text>" }        // SHA-1 nad UTF-8 bajty `text` přesně jak je uložen
Překlad se použije jen když translations_src == sha1(text) (stejná konvence jako translation_src smluv).
Jinak web i appka ukážou češtinu (web s lang="cs").

## Soubory
- motogo-web-php/layout-banner.php (NOVÝ; WIP commit 62421d63, v této session: otisk FNV → SHA-1, guard ne-string text)
- motogo-web-php/layout.php (jen require + `echo renderTopBanner();` hned za <body>, v WIP commitu)
- velin/src/pages/bannerI18n.js (NOVÝ) — překlad přes autoTranslate/translate-content s nosným řádkem
  cms_variables `app.header_banner.text` (category general; mimo prefix web. → web/appka ho nečtou)
- velin/src/pages/DashboardBannerEditor.jsx — uložení CZ hned + purgeWebCache, pak překlad chybějících/
  zastaralých jazyků, druhý zápis (jen pokud se text mezitím nezměnil) + purgeWebCache; stav překladu
  inline (role=status), rozbalovací „Překlady (x/7 aktuálních)“; nadpis „Banner v aplikaci a na webu“
- Motogo-app-main/motogo-app-flutter{,-ios}/lib/core/banner_provider.dart — bannerProvider = Provider<AsyncValue>
  odvozený z localeProvider + _rawBannerProvider (stream beze změny); čistě dartovské SHA-1 (ověřeno 8 vektory)

## Ověření
- web: cs/en/uk × 390/1366, 320 dlouhý text (11 řádků, bez přetečení), off/empty skryje, stale → čeština,
  low contrast → #0f1a14 na bílé, bad colors → výchozí, XSS escapováno, landing v1/v2, katalog/rezervace/
  kontakt/pobočky 8 jazyků 200, 0 PHP warning; hlavička se chová stejně (posun o výšku pruhu), menu kryje vše
- Velín vite build OK; jednotkový test helperu (mock): ok/partial/fail/RLS/stale/uppercase src
- flutter analyze: Android 193 / iOS 184, 0 errors (= baseline), diff -rq lib jen whitelist

## Pro majitele
- Po nasazení: Velín → Dashboard → Banner → „Uložit banner“ (jednou) — vytvoří překlady stávajícího textu.
- Překlad smí jen superadmin/manager (RLS cms_variables); jiná role uloží jen češtinu + varování.
- Předexistující (mimo banner): uk/de na 320 px přetéká horní lišta hlavičky (header-tools) i bez banneru.

## QA (adversarial review, 2026-10-11)
- Opraveno (layout-banner.php): garance kontrastu — u středně šedých pozadí (jas ~0.18–0.22) nedosáhla 4.5:1 ani bílá,
  ani #0f1a14 (např. #777 → 4.48) → nově fallback na #000000; sweep 20 000 náhodných dvojic: min 4.50.
  Výchozí banner (#74fb71 na #1a2e22) beze změny.
- Opraveno: `word-wrap:break-word` před `overflow-wrap:anywhere` (starší Safari < 15.4 zalomí dlouhé slovo).
- Ověřeno: fallbacky (stale/chybějící/prázdný/nevalidní typ překladu, číselný src, velká písmena v src, koncová
  mezera = jiný otisk), off/"false"/prázdný text skryje; 6 stránek × 8 jazyků × (live, fresh, midc) = 144× HTTP 200,
  1 banner, 0 PHP warning; přetečení 320/390/768 = 0 px u banneru (předexistující přetečení stránek beze změny
  s bannerem i bez); CLS banner nepřidává (posuny pochází z header-tools/header-editrez, stejné i bez banneru);
  mobilní menu banner překryje; CS HTML s bannerem = bez banneru + pruh. Dart SHA-1 = Python hashlib (9 vektorů).
  Velín build OK, mock test helperu OK; flutter analyze 193/184, 0 errors; diff -rq lib jen whitelist.
- Zbytkové riziko: dvě souběžná uložení RŮZNÝCH textů (2 karty / 2 admini během ~15 s překladu) sdílí jeden nosný
  řádek → teoreticky překlad jednoho textu s otiskem druhého. STATE_5 §11 header_banner by měl zmínit
  translations/translations_src + nosný klíč cms_variables `app.header_banner.text` (STATE není v povolených souborech).
