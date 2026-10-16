# Handoff 2026-10-16 → navázání po resetu týdenního limitu (čt 22. 10. 15:00)

> Pracovní podklady Clauda pro větev `claude/moto-go-mobile-conversion-gqg5qo`.
> **Celou složku `.claude/handoff/` smazat před mergem do `main`.**
> **Větev NEMERGOVAT, dokud nejsou hotové kroky B–E.** Commity „WIP … nemergovat“ nejsou ověřené.

## Proč pauza
Týdenní limit účtu byl ~97 %, dokupování je vypnuté. Úlohy byly zastaveny ručně a vše rozpracované je uložené (STAV níže).

## STAV (doplněno při zastavení)
<!--STAV-->

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
**E. Vydání Android 4.2.0** (iOS čeká na schválení majitele): ne-WIP commit, publikovat plochy, návod majiteli: Codemagic „MotoGo24 Android Build“ (debug APK + QR) → test → „MotoGo24 Android Release“; `min_app_version` NEnastavovat; nouzově `feature_flags.app_v2_ui = false` (návrat ke starému vzhledu bez vydání).
**F. SQL balík ke schválení** (jako text, CLAUDE.md pravidlo 3): `sql-final` + `sql-qa` (bez a; g jen se souhlasem) + `sql-reviews` + `sql-paydec` p1–p4 (+ follow-up) + barvy ranků. Po schválení → `supabase/migrations/` (názvy musí řadit za nejnovější soubor v main) + STATE_1–6 ve stejném PR. Platby: zaokrouhlení na 15 Kč se projeví až po p1 (kód to detekuje).
**G. Před mergem:** smazat `.claude/handoff/`, ZIP webu `git archive <merge> motogo-web-php`.

## Otevřené otázky majitele
1. VOP čl. 5 l) + smlouva podle pravidla vracení (soubor `sql-qa/…g…`) — závazné dokumenty, souhlas nutný.
2. Barvy ranků (rampa zelená → modrá → kovy → ohnivá zlatá 20) — schválit SQL.
3. Z PREHLED.md: vrácení na domluveném místě; poplatek za špinavou motorku / svítící rezervu na samoobsluze; helmy VN; ceny přistavení; názvy měsíců v banneru.
4. BMW R 1200 GS Adventure: nádrž 32 l vs. 30 l v popisu (sjednotit ve Velínu).

## Akce majitele po nasazení
Velín → „Přeložit chybějící a zastaralé“; znovu uložit blogové články; zkontrolovat e-mailové šablony; Velín → „Uložit banner“.
