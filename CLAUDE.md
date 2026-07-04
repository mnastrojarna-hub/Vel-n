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

- **motogo-app-flutter/** — Mobilní appka pro zákazníky (codemagic build)
- **velin/** — Velín = superadmin dashboard (React 18 + Vite + TailwindCSS)
- **supabase/** — Backend: Edge Functions + SQL migrace
- **doc-scanner/** - Mobilní capacitor vstup pro účetní přijaté dokumenty všeho druhu do velínu

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
