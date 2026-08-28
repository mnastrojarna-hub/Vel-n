# MotoGo24 — Claude Code Instructions

## POVINNÉ: Přečti backend state na začátku každé session

**VŽDY na začátku KAŽDÉ konverzace / session přečti soubory:**

```
/SUPABASE_BACKEND_STATE_1.md  — Tabulky
/SUPABASE_BACKEND_STATE_2.md  — Klíčové sloupce
/SUPABASE_BACKEND_STATE_3.md  — RPC funkce
/SUPABASE_BACKEND_STATE_4.md  — Triggery
/SUPABASE_BACKEND_STATE_5.md  — RLS, Realtime, Edge, Storage, Secrets, Cron, FK
/SUPABASE_BACKEND_STATE_6.md  — Changelog
```

Tyto soubory obsahují kompletní stav Supabase backendu — všechny tabulky, sloupce, RLS politiky, edge funkce, secrets, triggery a RPC funkce. BEZ tohoto kontextu NESMÍŠ provádět žádné frontendové ani backendové změny.

## Architektura projektu

Toto je soustava propojených aplikací pro MotoGo24 (půjčovna motorek):

- **Motogo-app-main/motogo-app-flutter/** — Mobilní appka pro zákazníky, Android MASTER (codemagic build)
- **Motogo-app-main/motogo-app-flutter-ios/** — iOS kopie appky pro App Store (codemagic build) — viz pravidla synchronizace níže
- **velin/** — Velín = superadmin dashboard (React 18 + Vite + TailwindCSS)
- **supabase/** — Backend: Edge Functions + SQL migrace
- **doc-scanner/** - Mobilní capacitor vstup pro účetní přijaté dokumenty všeho druhu do velínu

## Appka: dva stromy (Android + iOS) — POVINNÁ synchronizace

Flutter appka existuje ve DVOU kopiích se stejnou sadou souborů: `motogo-app-flutter` (Android, master) a `motogo-app-flutter-ios` (iOS). Historicky tu vznikal drift (např. vozík zdarma chyběl v iOS → zákazníci na iPhonu ho neviděli). Pravidla:

1. **Každou změnu sdíleného kódu appky proveď VŽDY v OBOU stromech ve stejném commitu.** Po změně ověř `diff -rq` obou `lib/` — lišit se smí POUZE soubory ze seznamu záměrných rozdílů níže.
2. **Záměrné platformní rozdíly (NEsjednocovat slepě):** `main.dart` (edge-to-edge vs. App Store onboarding + iOS merchant `merchant.cz.motogo24.rental`), `core/overlays/onboarding_overlays.dart` (App Store 5.1.1(iv) — bez „Povolit vše/Přeskočit"), `core/update_check_provider.dart` (App Store vs. Play URL), `core/offline_guard.dart` (iOS drží starší API connectivity_plus 5), `features/payment/payment_methods_screen.dart` (iOS BEZ ručního zadání karty — App Store 5.1.1/PCI), `features/payment/widgets/card_payment_sheet.dart` (Apple Pay vs. Google Pay), `features/payment/payment_error_mapper.dart` (substituce Apple Pay), `core/i18n/translations_*` hlavní soubory (iOS-only klíč `cardsSavedAtCheckout`), `userAgentPackageName` v mapových souborech (`features/booking/widgets/map_picker.dart`, `features/routes/route_navigation_screen.dart`, `route_builder_screen.dart`, `route_map.dart`, `community_submit.dart`, `route_submit_screen.dart` — iOS `com.motogo24.rental`, Android `com.motogo24.app`).

**iOS identifikátory (firemní Apple účet Mnástrojárna s.r.o., od 8/2026):** Team ID `YP7TF3APAV`, Bundle ID `com.motogo24.rental` (Android applicationId zůstává `com.motogo24.app` — NEměnit), Apple Pay merchant `merchant.cz.motogo24.rental`, App Store Connect Apple ID `6806045151` (SKU `motogo24-ios`). Detail: `Motogo-app-main/motogo-app-flutter-ios/APPLE_RELEASE_SETUP.md`.
3. **iOS pubspec pinuje STARŠÍ verze balíčků** (connectivity_plus ^5, flutter_stripe ^11, firebase 15/3.x kvůli Xcode, permission_handler ^11, secure_storage ^9, geolocator ^10…). Kód portovaný z Androidu MUSÍ používat API kompatibilní s těmito piny — nikdy nebumpuj iOS závislosti jen kvůli portu.
4. **Ostrý rezervační formulář je JEN `core/booking_form_widget.dart`** (route `/booking`, sekce 1–6). Starší generace (`booking_form_screen`, `booking_form_body` + widgety) byly smazané jako mrtvý kód — neobnovovat, nové soubory formuláře nezakládat.
5. Assety: oba stromy používají **webp** (`logo.webp`, `darkovy-poukaz.webp`).

## Nasazení (autodeploy přes git — NIC se nenasazuje ručně)

**Merge do `main` = živé nasazení.** Supabase se nasazuje přes GitHub Actions pomocí tokenů uložených v repo secrets (Settings → Secrets and variables → Actions). Project ref: `vnwnqteskbykeucanlhk`.

| Co | Workflow | Trigger | Secret |
|---|---|---|---|
| Velín (React) | Vercel | push do `main` | — (spravuje Vercel) |
| Edge funkce | `.github/workflows/deploy-functions.yml` | push do `main` v `supabase/functions/**` nebo `config.toml` | `ACCESS_TOKEN` = Supabase personal access token (CLI ho čte jako `SUPABASE_ACCESS_TOKEN`) |
| SQL migrace | `.github/workflows/deploy-sql.yml` | push do `main` v `supabase/migrations/**.sql` | `SUPABASE_DB_URL` = postgres connection string |

**Jak funguje SQL autodeploy (`deploy-sql.yml`):**
- Evidence aplikovaných souborů drží DB tabulka `public._git_migrations` (filename PK). Workflow projde `supabase/migrations/*.sql` abecedně a aplikuje JEN soubory, které v evidenci nejsou — každý v jedné transakci (`ON_ERROR_STOP`), při chybě se nic zpola neaplikuje a workflow spadne.
- Chybující migrace **blokuje všechny další** — opakuje se při každém dalším pushi do migrations, dokud se neopraví. Proto: migrace commitovaná do main MUSÍ být finální, validní a idempotentní; název souboru po aplikaci neměnit (evidence je dle filename).
- Ruční běh (Actions → Run workflow) má vstupy `baseline` (jen zaevidovat bez spuštění), `only` (filtr na název) a `force` (re-aplikace souborů vyhovujících `only`).

**Edge funkce (`deploy-functions.yml`):** nasazuje VŠECHNY funkce z repa přes Supabase CLI, `verify_jwt` bere z `supabase/config.toml` (žádný fallback na true). Funkce existující jen v dashboardu (cron-*, …) se netknou.

**Ostatní workflows:** `snapshot-supabase.yml` (ruční snapshot živého stavu do větve `supabase-live-snapshot` pro diff s main), `daily-backup.yml` (denně 6:00 kompletní šifrovaná záloha DB + Storage + git).

**Kontrola/rotace tokenů:** platnost se ověřuje podle výsledků běhů v Actions (zelený deploy = token platí). Nový Supabase PAT: https://supabase.com/dashboard/account/tokens → vložit do repo secretu `ACCESS_TOKEN`; DB heslo → `SUPABASE_DB_URL`.

**Zpětná vazba při selhání SQL deploye (POVINNÁ kontrola):** když `deploy-sql.yml` spadne, workflow sám založí GitHub issue s labelem **`sql-deploy-failed`** (log chyby + padající soubor + pokyny) a při opakovaném selhání do něj přidává komentáře; po prvním zeleném běhu se issue zavře samo. **Claude MUSÍ na začátku každé session zkontrolovat otevřená issues s labelem `sql-deploy-failed`** (GitHub MCP `list_issues`, label `sql-deploy-failed`) — pokud nějaké existuje, oprava zablokovaného autodeploye má přednost před veškerou další prací (vadná migrace blokuje aplikaci všech následujících).

## Pravidla

1. **NIKDY neměň UX, UI ani flow** pokud to uživatel výslovně nepožaduje
2. **pro celý repozitář:** Maximálně 5000 tokenů na soubor pokud je to technicky možné a neomezí to funkčnost.
3. **SQL změny:** Vždy dej SQL příkazy jako text do chatu, NIKDY rovnou do gitu. Až po implementaci a ověření commitni. POZOR: merge migrace do `main` ji přes `deploy-sql.yml` automaticky aplikuje na živou DB (viz Nasazení)
4. **SUPABASE_BACKEND_STATE_*.md:** Po každé SQL změně MUSÍŠ aktualizovat příslušný soubor (1-6)
5. **Backend first:** Před každou frontendovou změnou ověř, že backend (tabulky, RLS, funkce) podporuje požadovanou funkcionalitu

## Supabase kontext

- Projekt: MotoGo24
- Region: (ověřit v dashboardu)
- Email služba: Resend (noreply@motogo24.cz)
- Platby: real stripe funkční
- Firma: Bc. Petra Semorádová, IČO: 21874263
- Kontakt: +420 774 256 271, info@motogo24.cz

## SKU konvence skladu (POVINNÁ — i pro AI při naskladňování)

Jednotný formát SKU pro celý sklad (`inventory.sku`). Zdroj pravdy: `velin/src/lib/sku.js`.
Formát: `kategorie-typ-varianta` — malá písmena, číslice, pomlčky, bez mezer a diakritiky.

- **Příslušenství:** `prislusenstvi-{typ}-{velikost}` — typ ∈ helmet/jacket/pants/boots/gloves/balaclava; velikost VŽDY poslední a přesně jako v číselníku (`43`, `XL`, `2XL`, `UNI`). Např. `prislusenstvi-boots-43`. Skládá se přes `accessorySku(type,size)` / `accSku` — NIKDY ručně jinak (jinak se rozbije párování se skladem a pobočkami).
- **Náhradní díly (servis):** `dily-{slug}` — např. `dily-olej-10w40`
- **Materiál:** `material-{slug}` — např. `material-cistic-retezu`
- **Zboží / e-shop:** `zbozi-{slug}` — např. `zbozi-tricko-logo`
- **Spotřební (provoz):** `spotrebni-{slug}` — např. `spotrebni-ubrousky`

Pravidlo: `slug` = krátký výstižný název (značka-typ-parametr). Při zanášení na sklad (ručně i přes AI/OCR z faktury) VŽDY použij tuto konvenci a validuj přes `validateSku()`.

## Git workflow

- Vždy pracuj na větvi začínající `claude/`
- Commit message česky nebo anglicky dle kontextu
- Před pushem ověř, že branch name odpovídá session
