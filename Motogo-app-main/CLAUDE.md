# MotoGo24 Flutter – CLAUDE.md

## ⚠️ ZLATÁ PRAVIDLA

1. **VŽDY SE ZEPTEJ** při sebemenší nejasnosti. Nepředpokládej, nedoplňuj.
2. **NIKDY nepushuj změny, které po tobě nebyly vyžádány.** Opravuj POUZE to, co je zadáno.
3. **Před opravou screenu → najdi jeho screenshoty** ve složce `původní UI vzor screen/` (viz níže).
4. **Maximální velikost souborů: 5000 tokenů.** Rozděl větší soubory.
5. **Nečti zbytečně moc kódu** – přečti jen to, co potřebuješ k aktuální úloze.
6. pokud je úkol příliš obsáhlý, tak že ho neuhrdžíš v paměti, nebo to hrozí, rozděl ho hned na části, tak aby jsi vždy úkol 100% dokončit a udržel kontext.

### CÍL PROJEKTU
Vytváříš **100% vizuální a funkční kopii** původní Capacitor/Cordova aplikace MotoGo24 ve Flutteru. Každý screen, každý detail, každá animace musí být identická s originálem. Originál = `motogo-app-frontend/`, screenshoty = `původní UI vzor screen/`.

---

## STRUKTURA REPOZITÁŘE

```
kořen git/
├── motogo-app-frontend/     ← původní Capacitor/Cordova app (REFERENCE, needituj)
├── motogo-app-flutter/      ← vyvíjená Flutter app (EDITUJ TUTO)
├── původní UI vzor screen/  ← screenshoty původní aplikace (VIZUÁLNÍ REFERENCE)
├── SUPABASE_BACKEND_STATE.md      ← dokumentace backendu (6 částí)
├── SUPABASE_BACKEND_STATE_1..6.md
├── codemagic.yaml
├── .gitignore
└── CLAUDE.md                ← tento soubor
```

---

## 📱 PRÁCE SE SCREENSHOTY (původní UI vzor screen/)

### Jak to funguje
- Každá stránka appky je **scrollovatelná** → jeden screen má typicky **2–5 screenshotů** navazujících pod sebou.
- Screenshoty je nutné **identifikovat, které k sobě patří** (navazují vizuálně).
- **Před prací na jakémkoli screenu:**
  1. Projdi složku `původní UI vzor screen/`
  2. Najdi VŠECHNY screenshoty odpovídající dané stránce
  3. Pokud jsou špatně pojmenované → **přejmenuj a přeuspořádej** pro jasnou identifikaci:
     - Formát: `[screen-name]_01.png`, `[screen-name]_02.png`, ...
     - Např: `home_01.png`, `home_02.png`, `home_03.png`
  4. Pokud screenshot **chybí** → **VYŽÁDEJ SI HO** od uživatele. Nepracuj naslepo.

### Pravidlo čtení referenčního kódu
- Pro pochopení **jak funguje** konkrétní stránka → přečti odpovídající soubor v `motogo-app-frontend/`
- Čti **jen relevantní soubor**, ne celou app. Nezasírej si kontext.

---

## ARCHITEKTURA

- **Backend:** Supabase (Frankfurt, projekt `vnwnqteskbykeucanlhk`) – VŠE už běží
- **Tato app je POUZE pro zákazníky** – jen zobrazuje data
- **Veškerá nastavení, správa, konfigurace** → admin app Velín (jiný projekt)
- **MotoGo app = read-only klient** – zobrazuje motorky, rezervace, zprávy, faktury atd.
- Máš přístup k **přehledu Supabase** a k souborům `SUPABASE_BACKEND_STATE*.md`

### Supabase

```
URL:  https://vnwnqteskbykeucanlhk.supabase.co
ANON_KEY: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZud25xdGVza2J5a2V1Y2FubGhrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI0OTEzNjMsImV4cCI6MjA4ODA2NzM2M30.AiHfmfEQK5KD9TvxX5XLWVGaOhEV7kiMwwMwMWp0Ruo
```

### Test credentials

```
Email: test@motogo24.cz
Heslo: Test1234
```

---

## DESIGN SYSTÉM (zkrácená reference)

- **Font:** Montserrat (google_fonts), weights: 500, 700, 800, 900
- **Hlavní barvy:** bg `#DFF0EC`, dark `#1A2E22`, green `#74FB71`, gd `#3DBA3A`, red `#EF4444`
- **Detailní barvy a styly** → viz `lib/core/theme/app_colors.dart` (už v kódu)
- **Border-radius:** karty 18px, inputy 12px, buttony 50px (pill), header 24px, home header 28px
- **Stíny:** cardShadow `0 4px 20px rgba(15,26,20,.1)`, greenShadow, redShadow → viz `app_theme.dart`
- **Animace:** slide zprava, 320ms, `CubicBezier(0.77, 0, 0.18, 1)`
- **Green = přesně #74FB71** (NE material green!)

---

## NAVIGACE (36 screenů)

### Bottom Nav (4 taby)
Domů (`s-home`) | Rezervovat (`s-search`) | Rezervace (`s-res`) | Shop (`s-merch`)

BNav se NEZOBRAZUJE na: s-login, s-success, s-docs, s-register, s-doc-scan.

### Screen map
- **Auth:** login, register (3 kroky), docs-upload, doc-scan
- **Home:** home (sticky header, filtry, moto grid)
- **Booking flow:** search → detail → booking-form → payment → success
- **Rezervace:** list → detail → edit, done-detail, contracts, protocol, ai-agent
- **SOS:** menu → nehoda/nepojízdá/porucha/combined/servis/krádež → replacement → payment → done
- **Shop:** merch → detail → cart → checkout, voucher
- **Profile:** profile, messages, message-thread, invoices (z hamburger menu)

### Auth guard
Většina screenů vyžaduje přihlášení → redirect na s-login.

---

## WORKFLOW

1. **Dostaneš úkol** → oprav POUZE zadaný screen/problém
2. **Najdi screenshoty** v `původní UI vzor screen/` → identifikuj navazující screeny
3. **Přečti relevantní kód** v `motogo-app-frontend/` (jen ten soubor, ne víc)
4. **Pokud něco není jasné → ZEPTEJ SE.** Nepředpokládej. Nedoplňuj.
5. **Implementuj ve Flutter** v `motogo-app-flutter/`
6. **Commit** jen zadané změny: `fix: [Screen] – [co přesně]`
7. **Push** jen když je to vyžádáno nebo potvrzeno

### Commit convention
```
feat: [Screen] – [implementováno]
fix: [Screen] – [opraveno]
refactor: [Component] – [přepracováno]
```

---

## VIZUÁLNÍ CHECKLIST (po každé úpravě)

- Barvy = přesné HEX (ne přibližné)
- Topbar radius: `0 0 24px 24px`
- BNav výška: 120px logická
- Karty: shadow `0 4px 20px rgba(15,26,20,.1)` (ne generic elevation)
- Buttony: pill shape radius 50px
- Font weight: 800/900 pro headingy
- Screen transition: slide zprava
- Calendar: 7-column grid, buňky 1:1

---

## FLUTTER PROJEKT

Struktura je v `motogo-app-flutter/lib/` – core/theme, core/widgets, features/[modul]/screens/, services/.
Packages a detailní struktura → viz aktuální `pubspec.yaml` a adresářový strom.

---

*Vše ostatní (detailní komponenty, přesné CSS hodnoty) → čti přímo zdrojový kód v motogo-app-frontend/ podle potřeby.*
