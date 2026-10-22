# Handoff 2026-10-16 → navázání po resetu týdenního limitu (čt 22. 10. 15:00)

> Pracovní podklady Clauda pro větev `claude/moto-go-mobile-conversion-gqg5qo`.
> **Celou složku `.claude/handoff/` smazat před mergem do `main`.**
> **Větev NEMERGOVAT, dokud nejsou hotové kroky B–E.** Commity „WIP … nemergovat“ nejsou ověřené.

## Proč pauza
Týdenní limit účtu byl ~97 %, dokupování je vypnuté. Úlohy byly zastaveny ručně a vše rozpracované je uložené (STAV níže).


## POZOR — revert plateb v main (2026-10-22)
PR #2212 (merge vývojové větve majitelem 22. 10. 16:43) nasadil neověřené platby; hotfix PR #2213 (větev claude/hotfix-payments-revert-gqg5qo) vrací supabase/functions na 550ad417. Při PŘÍŠTÍM `git merge origin/main` do vývojové větve si git vezme i ten revert a smazal by platby z větve → po merge OBNOV `supabase/functions` z předchozí HEAD větve (`git checkout <HEAD před merge> -- supabase/functions` + smaž soubory, které revert přidal/změnil zpět), ověř deno check/test a teprve pak commit. Při dalším PR do main se platby vrátí naživo — jen po úplném ověření.

## STAV (doplněno při zastavení)
Zastaveno 16. 10. 2026 ~23:15 (Praha) při týdenním limitu ~95 %. Úlohy jsou ZASTAVENÉ, ne dokončené.

**1. Appka v2 Android** (`app-v2-android-impl.js`, run `wf_e1861c88-6ac`)
- Hotovo: Plan, Foundation, všechny obrazovky (home, catalog, booking, reservations, profile, routes, rides), Integrate (router/shell za `appV2UiProvider`, pravidlo 6 v CLAUDE.md, verze 4.2.0), Verify kolo 1 (parity, render 8 jazyků, code, design).
- Opravy kola 1: hotové shared, home, booking. Přerušené uprostřed: catalog, profile (soubory `lib/features/catalog/v2/**` mohou být rozpracované; ověř `flutter analyze` + testy). Nezačaté: reservations, routes, rides (+ položky „shell/navigation/kill-switch“).
- Seznam všech issues kola 1 a reporty oprav: `reports/impl.json` (labely `verify:*:r1`, `fix:*:r1`).
- Pak Verify kolo 2 (+ případně 3).

**2. Návrh v2.2 (plátno)** (`app-design-v22.js`, run `wf_d9683d5a-72e`)
- Hotovo: Understand, Spec (DESIGN_V22.md), build 12 ploch, Verify kolo 1, opravy shared + TrasaDetail, MotoKatalog, SOS, Booking, Profil, MotoDetail, Reservation.
- Přerušené: Stavy, TrasyHub (ostatní plochy s nálezy možná nezačaté — viz `reports/design-v22.json`). Pak Verify kolo 2.
- Publikováno na plátno ve stavu k zastavení (13 ploch, verze 18; lint Stavy + TrasyHub OK).

**3. Platby – doplňky majitele** (`payments-followup-wf_5c9a0341-972.js`, run `wf_5c9a0341-972`)
- Hotovo: implementace (storno pro rata, zaokrouhlení i na webu, „Motorka je mezitím obsazená“ + automatické vrácení), verify ux kola 1–3, fix kola 1–2.
- Přerušené: verify:money kolo 2 a fix kolo 3. Poslední známé nálezy (ux r2): guard.js na webu zapíše nový čas vyzvednutí i při neúspěšné změně (blocker), náhled doplatku na webu skrývá řádek zaokrouhlení (major) — ověř, zda je fix r3 stihl opravit.
- Pozn.: 16. 10. ~19–21 h byl plný disk → implement agent nedoběhl, zbytek doplnily fix kola. Vše znovu ověřit (deno testy, PG s drafty p1–p4 2×, app testy).

**Stav repa:** Android `flutter analyze` při zastavení: 147 issues, 0 errors. Vše commitnuté na větvi (WIP). Diff od vydané appky: Android 4.2.0 (v2 za přepínačem), iOS jen ne-v2 změny (chybové stavy, platby, recenze).

## Kde co je
| Co | Kde |
|---|---|
| SQL texty majitele (32 souborů + PREHLED) | `sql-final/` |
| SQL z QA brány (b..m, w1, w2; **g jen se souhlasem majitele, a vynechat**) | `sql-qa/` |
| SQL recenze (velin_rating_handled, booking_rating_guard, messages_bump_thread, OPTIONAL d) | `sql-reviews/` |
| SQL platby p1–p4 (+ případné další z follow-upu), DESIGN.md, understand.md | `sql-paydec/` |
| Barvy ranků (rampa, nahrazuje 20261015_no_purple) | `appdesign-v22/sql/20261016_loyalty_colors_ramp.sql` |
| Specifikace návrhu v2.2 + v2/v2.1 + appdesign_spec | `appdesign-v22/*.md` |
| Plochy návrhu (.dc.html, canvas.json) | `appdesign-v22/project-boards.tgz` |
| Sdílené snippety, research (rank_ramp, states, balance, profil, trasy) | `appdesign-v22/shared`, `appdesign-v22/research` |
| Skripty workflow | `workflows/` |
| Výsledky agentů (issues, reporty oprav) | `reports/{impl,design-v22,payments-followup}.json` |
| Náhled appky (plátno) | https://claude.ai/artifact/MgsmxxUXfJkqW3M4xM1GuA |

## Obnova prostředí (nový kontejner)
1. `S` = scratchpad nové session. Rozbal/zkopíruj: `appdesign-v22/*` → `S/appdesign/` (+ `appdesign_spec.md` → `S/`), `tar xzf project-boards.tgz -C S/appdesign`, SQL složky → `S/sql/final`, `S/qa-final/sql`, `S/reviews/sql`, `S/paydec/sql`.
2. Ve skriptech `workflows/*.js` přepiš `const S = '…'` na nový scratchpad.
3. Nástroje: Flutter SDK → `S/sdk/flutter` (verze dle `codemagic.yaml`), Deno → `S/denobin` (`DENO_DIR=S/denocache`), PG16 clustery jen pod `/var/tmp`, Playwright Chromium předinstalovaný. Lint plátna: `dclint/` → `S/dclint/` (`lint.py`, `fuzz.js`, `canvas_sync.py` = výšky/pořadí desek v canvas.json). Publikace plátna: Artifact publish, `url` výše, `root` = snapshot složka s `project/`, `file_path` = `project/canvas.json`.
4. Disk: allowance ~39 GB; pracovní složky dokončených úloh průběžně mazat (16. 10. se disk zaplnil a shodil agenty).
5. Začátek session dle CLAUDE.md: STATE_1–6, issues `sql-deploy-failed`/`backup-failed`, `git fetch && git merge origin/main`.
6. Limit: sonda (workflow s 1 agentem „Reply ok“), pak hlídat `rate_limit_event` (claude-code-remote `list_events`).

## Co zbývá (pořadí)
**A. Dokončit rozpracované úlohy.** Pokud journály `subagents/workflows/<run>/journal.jsonl` ještě existují (stejná session), stačí `Workflow({scriptPath, resumeFromRunId})`. Jinak **NEspouštět `app-v2-android-impl.js` od začátku** (přepsal by hotové obrazovky) — napiš pokračovací skript: jen smyčka Verify→Fix (parity, render 8 jazyků, code, design) nad současným kódem, vstup = poslední issues z `reports/impl.json`. Stejně design v2.2 (jen Verify→Fix ploch) a platby (jen Verify money+ux → Fix).
**B. `app-v2-sales-copy.js`** (prodejní texty „dezert“, 8 jazyků).
**C. `app-v2-ux-review.js`** (6 skupin scénářů zákazníka vč. tras, VOP/smluv, poboček, filtrů, děkovacích stránek; pravidlo rozbalení: klíčové info a klíčová nabídka rozbalené, doplňky zabalené).
**D. `functional-diff-audit.js`** — POVINNÁ pojistka: každá funkční změna vs. vydaná 4.1.3 musí mít požadavek majitele, jinak revert; pak všechny testy.
Pravidlo majitele (16. 10., doslova): „ale pozor jinak nic co se týká funkčnosti nic neměň, to bylo celkem odladěný, tak ne že to rozbiješ“ → v B–D jen vzhled/texty/rozbalení; funkční chyby hlásit, neopravovat.
**E. SQL balík ke schválení** (jako text, CLAUDE.md pravidlo 3): `sql-final` + `sql-qa` (bez a; g jen se souhlasem) + `sql-reviews` + `sql-paydec` p1–p4 (+ follow-up) + barvy ranků. Po schválení → `supabase/migrations/` (názvy musí řadit za nejnovější soubor v main) + STATE_1–6 ve stejném PR. **Platby: p1–p4 VŽDY spolu a spolu s edge funkcemi, PŘED vydáním appky (F)** — appka 4.2.0 (a iOS) ukazuje „Minimální platba kartou je 15 Kč – zaplatíš 15 Kč“ / „Zaplatit 15 Kč“ bez detekce; bez p1–p4 by server odmítal `rounding_unavailable`. Web dorovnání detekuje sám (sloupec `card_rounding` = p1), výměna potřebuje p3 a výbava p4 → nasazovat jako jeden balík. Ověřit zelený `deploy-sql.yml` (žádné issue `sql-deploy-failed`) a teprve pak F.
**F. Vydání Android 4.2.0** (iOS čeká na schválení majitele; až po E — viz výše). **Platby i na iOS (f1 2026-10-22):** po nasazení E stará 4.1.3 u 1–15 Kč dostane `below_minimum` — text už aktualizaci neslibuje (jen „když ti obchod nabídne“) a u úpravy odkáže na web (`below_minimum_legacy_edit`), ale rezervace / e-shop 1–15 Kč ve 4.1.3 cestu nemá. Doporučení majiteli: vydat SPOLU s Android 4.2.0 i iOS build s platebními změnami (iOS strom je má hotové BEZ v2 vzhledu — v2 na iOS dál čeká na schválení), jinak iPhone zůstane do vydání na 4.1.3: ne-WIP commit, publikovat plochy, návod majiteli: Codemagic „MotoGo24 Android Build“ (debug APK + QR) → test → „MotoGo24 Android Release“; `min_app_version` NEnastavovat; nouzově `feature_flags.app_v2_ui = false` (návrat ke starému vzhledu bez vydání).
**G. Před mergem:** smazat `.claude/handoff/`, ZIP webu `git archive <merge> motogo-web-php`.

## Otevřené otázky majitele
1. VOP čl. 5 l) + smlouva podle pravidla vracení (soubor `sql-qa/…g…`) — závazné dokumenty, souhlas nutný.
2. Barvy ranků (rampa zelená → modrá → kovy → ohnivá zlatá 20) — schválit SQL.
3. Z PREHLED.md: vrácení na domluveném místě; poplatek za špinavou motorku / svítící rezervu na samoobsluze; helmy VN; ceny přistavení; názvy měsíců v banneru.
4. BMW R 1200 GS Adventure: nádrž 32 l vs. 30 l v popisu (sjednotit ve Velínu).

## Akce majitele po nasazení
Velín → „Přeložit chybějící a zastaralé“; znovu uložit blogové články; zkontrolovat e-mailové šablony; Velín → „Uložit banner“.
