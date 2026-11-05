# Handoff 2026-11-05 — pokyn majitele: „ok pokračuj a kompletně dodělej motogo 2 app pro obě platformy hlídej případný limit a stopni to až bude 90%“

> Větev `claude/moto-go-mobile-conversion-gqg5qo`, PR #2214 je KONCEPT (draft) — nemergovat (majitel merguje bez čtení → až po „ověřeno, můžete mergovat“). Složku `.claude/handoff/` smazat před mergem.
> **Nové rozhodnutí majitele:** v2 vzhled jde do OBOU stromů (iOS port schválen — ruší dočasnou výjimku v CLAUDE.md bod 6; po portu bod 6 přepsat: v2 soubory byte-identické v obou stromech, záměrné rozdíly jen dle seznamu v bodu 2). Zastavit čistě při 90 % týdenního limitu (reset ~12. 11. 13:00 UTC; kontrola: `list_events` kinds `rate_limit_event`, session `session_01PU5jSPfdERrqgjPcVD71WB`). Stav 18:32 UTC: 26 %.

## Stav 2026-11-05 (~21:40 UTC) — ZASTAVENO na 86 % týdenního limitu (pravidlo majitele 90 %; reset ~12. 11. 13:00 UTC)
- **v2 follow-upy HOTOVO + ověřeno** (run wf_8406be17-378): stavová lišta (nový `core/v2/chrome/mg_status_bar.dart` + `core/v2/widgets/mg_v1_pass.dart` — ikony tmavé nad světlými a světlé nad tmavými v2 plochami, pinned bar, hero, shell, stavové obrazovky; opravné kolo doplnilo staré obrazovky v rámu v2: navigace trasy, e-shop, výběr na mapě, galerie, skener dokladů, slučování jízd, login/reset/registrace; iOS odraz přes `extendAbove`), spodní odsazení stavových obrazovek, kill-switch jen na čistém kořenu záložky, `DateDropdownField` rozsah let + `address_picker` dispose. Oba stromy shodné (`diff -rq lib` = 20 záměrných řádků), Android analyze 147/0, iOS kopie 142/0, celá Android sada 6281 passed, testy `test/v2/statusbar_test.dart`, `state_inset_test.dart`, `flag_test.dart`, `test/fix_dates_test.dart`. Neověřeno nezávisle: `verify:checks:r1` agent skončil bez výstupu (nahradil ho orchestrátor: analyze + testy + parita ručně OK). Minor otevřené: po runtime flipu v2→starý vzhled na odscrollované záložce zůstane poslední styl lišty do další obrazovky; mrtvý `DocumentCameraScreen`.
- **Příští session (po resetu limitu), pořadí:** (1) platby verify i3 → resume `wf_79d20dcc-a4f` (skript v `workflows/`; cache do fix:i2) + fix i3; (2) prodejní texty `app-v2-sales-copy.js`; (3) UX revize `app-v2-ux-review.js`; (4) `functional-diff-audit.js` (oba stromy, BASE 70a94933); (5) SQL migrace + STATE_1–6 (jízdy `rides/sql/01–06` → `_a…_h`, platby `sql-paydec/` p1–p4 + 20261105a, barvy ranků `appdesign-v22/sql/20261016_loyalty_colors_ramp.sql`, texty majitele `sql-final/` 32 souborů — POZOR: před aplikací porovnat živá CMS data s verzí z 15. 10. (majitel mohl mezitím editovat ve Velínu), `sql-qa/` bez „a“ a „g“, `sql-reviews/` 3 soubory; názvy za `20261023f_*`, test 2× na PG16 nad `origin/supabase-live-snapshot` (9caacfb9, 5. 11.), `rides/sql/run_tests.sh`, cluster `/var/tmp/pg-rides`); (6) finální commit/PR text, smazat `.claude/handoff/`, „ověřeno, můžete mergovat“ + „můžete buildit“ (Codemagic Android Build + iOS Release nad větví) → vydání 4.2.0 obě platformy. Max. 2 úlohy souběžně (4 CPU); limit hlídat přes `list_events` (okno `seven_day_overage_included` je to varovné).

## Stav 2026-11-05 (~20:30 UTC, po restartu kontejneru — úlohy padly, stav ověřen a commitnut)
- **Limit:** 20:16 UTC = 78 % (okno `seven_day_overage_included`, hlásí varování od 75 %; `seven_day` 40 %). Při 90 % zastavit.
- **iOS port v2 HOTOVO** (commit a4c9c7ac). CLAUDE.md bod 6 přepsán.
- **v2 follow-upy** (run wf_8406be17-378, skript `workflows/app-v2-followups-wf_8406be17-378.js`): HOTOVO `fix:state` (spodní odsazení stavových obrazovek, test `test/v2/state_inset_test.dart`) a `fix:killswitch` (bezpečný okamžik: kořen záložky jen bez query a bez pushnuté stránky — `feature_flags.dart`, `v2/flag/v2_gate.dart`, `test/v2/flag_test.dart`; oba stromy shodné, testy prošly). ZBÝVÁ: `fix:statusbar` (ikony stavové lišty tmavé nad světlými v2 plochami — AnnotatedRegion v MgPage/AppShellV2/MgStateScreen, oba stromy), `fix:dates` (DateDropdownField rozsah let + address_picker TextPainter.dispose) a ověření (checks / device / func). Pokračovat: `Workflow({scriptPath, resumeFromRunId: 'wf_8406be17-378'})` — fix:state se vezme z cache; prompt killswitch upravit na „ověř hotovou opravu“.
- **Platby** (run wf_79d20dcc-a4f, skript v projektu Clauda `workflows/scripts/payments-reconcile-verify-wf_79d20dcc-a4f.js` — KOPIE v `workflows/`): HOTOVO integrate, verify i1+i2, fix i1+i2 (dedup čerstvého dobropisu jen když nic nedlužíme; karta + bankovní doplatek při plném stornu; manuální vratky stropem paid−CN; souběh → dobropisy = vratky; obnova po pádu u druhé vratky; refund `pending` ve webhooku; pojistný mail z charge.refunded; shop_orders `total`; testy `storno_i2_flow_test.ts`, `storno_multi_*`). Deno: check beze změny, `_tests` 213 passed, storno flow (import map) 42 passed. ZBÝVÁ: verify i3 (refunds, charges) a případný fix i3 → resume stejným skriptem (cache do fix:i2). Otevřené z verify:charges:i2 (pre-existing v main, neopraveno): 0 Kč rezervace přes setup session věří klientsky zapisovaným sloupcům (`floor-check.ts`, webhook `verify_free_booking`); z verify:ux:i2: pozdní platba auto-zrušené rezervace → appka/web ukazují „čeká na banku“ místo „vráceno“ (`payment_verify*`, `pages-potvrzeni.js`); zkrácení v appce volá process-refund samo bez retry (`reservation_edit_screen` ~1190–1240).
- **Dál (v tomto pořadí):** dokončit follow-upy → platby verify i3 → prodejní texty → UX revize → functional audit → SQL migrace + STATE → finální PR text → „můžete buildit“.

## Stav 2026-11-05 (~19:00 UTC)
- **Appka v2 Android — HOTOVO vč. ověření** (run wf_13a7a4b2-0f3 doběhl: opravy kola 1b, audit „nic dvakrát“, verify/fix kola 2–4; poslední opravy commit 887793cb). Zbylé minor nálezy z kola 4 (neopravené, k posouzení): kill-switch „bezpečný okamžik“ počítá `/profile?edit=personal` otevřený z rezervace jako kořen záložky (přepnutí uprostřed rezervace — `feature_flags.dart:153`, `v2_gate.dart`); starý vzhled: `DateDropdownField` s `firstYear: DateTime.now().year` spadne na uloženém dřívějším roce (`profile_screen.dart:433`, oba stromy, pre-existing); skener „missing_*“ bez textu/retry při zaseknutém RPC; `my_experiences_provider.dart:114` nepředvyplní popis trasy; `address_picker.dart` neuvolňuje TextPainter; „Kč“ samo na řádku (uk 320) ve funnelu; `res_edit_header_v2` láme datum (fr 320); payment_result title / home record row lámou slova (nl/fr 320); `booking_ui_helpers.dart` ~10k tokenů (pravidlo 5000); mrtvé `pfWordWidth`/`resWordWidth`; AI chat nezná motorku/termín z obrazovky (odloženo — backend `ai-moto-agent`).
- **iOS port v2 — BĚŽÍ** (run wf_67920b88-2d6, skript `workflows/app-v2-ios-port-wf_67920b88-2d6.js`): port (kopie v2 + švy, ruční merge main.dart, UA map souborů, iOS verze 4.2.0+117) → verify (analyze s iOS piny, celá Android testovací sada nad kopií iOS, parita diff -rq, adversariální iOS revize) → fix kola ≤3. Po doběhnutí: commit obou stromů, přepsat CLAUDE.md bod 6, `diff -rq` obou `lib/` = jen záměrné rozdíly + apple_pay_failure.dart.
- **Platby — BĚŽÍ** (run wf_79d20dcc-a4f, skript `workflows/scripts/payments-reconcile-verify-wf_79d20dcc-a4f.js` v projektu Clauda; rozpracované soubory v `supabase/functions/**` jsou necommitnuté, dokud úloha nedoběhne — NEcommitovat je dřív).
- **Skripty „4. důležité“ přepsány na OBA stromy** (`app-v2-sales-copy.js`, `app-v2-ux-review.js`, `functional-diff-audit.js` — BASE appky 70a94933 = 4.1.3; seznam vyžádaných změn doplněn o jízdy, 12:00 info, nic dvakrát, SOS náhrada jen volné motorky). Spouštět až po portu iOS, max. 2 úlohy souběžně (4 CPU).
- **Pořadí dál:** iOS port → sales copy → UX revize → functional audit → SQL migrace (jízdy 01–06 z `rides/sql/`, platby p1–p4 ze `scratchpad/paydec/sql/` po doběhnutí plateb, barvy ranků `appdesign-v22/sql/20261016_loyalty_colors_ramp.sql`, starší balík bez „a“ a „g“; názvy za `20261023f_*`, test 2× na PG16 nad `origin/supabase-live-snapshot`) + STATE_1–6 → finální commit/PR text → „můžete buildit“ (Codemagic Android Build nad větví; iOS „MotoGo24 iOS Release (App Store)“) → vydání 4.2.0 obě platformy. Otevřená volba majitele: baterie přes noc (výchozí (a)).

---
# Handoff 2026-10-30 05:35 UTC → pokračování po obnovení limitu (majitel: „Pozastav a pushni co jde, pokračování příště po načtení limitu“)

> Větev `claude/moto-go-mobile-conversion-gqg5qo`, PR #2214 je KONCEPT (draft) — nemergovat. Složku `.claude/handoff/` smazat před mergem do main.
> **UPDATE 05:50 UTC: PR #2221 majitel mergnul, deploy edge funkcí (run 258) zelený.** `main` sloučen do vývojové větve (commit 20140d72; konflikt jen process-refund/index.ts — ponechány storedPi/storedRefunds i piRefunds; storno flow 24/24, sada 196 ok + 2 známé f1/3). Krok payments integrate tedy už NEslučuje — jen dosladí platby (víc plateb na rezervaci vs. cancel-once; podklad `paydec/integrate_partial/`), opraví f1/3 a jede verify kola.

## Stav 2026-10-30
- **Main sloučen do větve** 29. 10. (výpůjčka výbavy jako rezervace, sjednocená vratka; commit 4ee110c1). Platby větve + gear spojené ručně, deno check beze změny.
- **Záznam jízdy — HOTOVO** (5 kol ověření, run wf_ace31e66-1f7). Podklady `rides/` (SPEC.md, SPEC_OWNER_CS.md = shrnutí pro majitele vč. otevřených voleb, LOGIC_API.md, STATE_PATCH.md, sql/01–06 + test_rides.sql + run_tests.sh). Otevřená volba majitele: baterie přes noc (výchozí (a) GPS zapnuté s pojistkami 48 h / 16 h kóje). SQL jde do `supabase/migrations` až do finálního PR (názvy řadit ZA nejnovější soubor v main, nyní 20261023f_*; NE `20261023_…`), s STATE dle `rides/STATE_PATCH.md`; Velín nasadit spolu s SQL.
- **Appka v2** (run wf_13a7a4b2-0f3, args `scratchpad/v2cont/resume_args.json`): hotovo kolo 1–3 (vč. majitelových „12:00 jen info“ a „nic dvakrát“), kolo 4 verify přerušeno (parity:r4, render:r4 běžely). Pokračovat resume stejným skriptem + args (cache vezme hotové).
- **Platby** (run wf_2d8d72a7-4b3, skript `workflows/payments-integrate-verify-wf_2d8d72a7-4b3.js`): přerušeno v kroku integrate (sloučení hotfixu #2221 do větve). Rozpracovaný stav v `paydec/integrate_partial/` (README + files.tgz), merge zrušen, strom čistý. Spustit skript znovu (nový běh). Pokud mezitím #2221 v main → stačí merge origin/main.
- **Zbývá potom:** prodejní texty (`app-v2-sales-copy.js`), UX revize (`app-v2-ux-review.js`), pojistka funkčnosti (`functional-diff-audit.js`), SQL (platby p1–p4, jízdy 01–06, barvy ranků, starší balík) rovnou do migrací + STATE, finální PR, „můžete buildit“ (Codemagic „MotoGo24 Android Build“ nad větví), vydání 4.2.0.
- Limity hlídat: 2 workflow ≈ 0,25–0,5 %/min pětihodinového okna; týden byl při zastavení ~53 %.

---
# Handoff 2026-10-22 → pokračování „za týden“ (majitel: „pozastav to dokončíme to za týden“)

> Pracovní podklady Clauda pro větev `claude/moto-go-mobile-conversion-gqg5qo`. **Složku `.claude/handoff/` smazat před dalším mergem do `main`** (už v main je její starší verze z #2212 — v dalším PR ji smazat).
> **PR #2214 (z této větve) je převedený na KONCEPT (draft) se souhlasem majitele — nechat jako koncept, dokud není vše ověřené.** Majitel merguje bez čtení → mergovat jen po zprávě „ověřeno, můžete mergovat“.

## Rozhodnutí majitele 2026-10-22 (doslova shrnuto)
- Záznam jízdy (R1–R6, doslovné zadání v `workflows/rides-pause-trips-wf_ace31e66-1f7.js`, konstanta OWNER): ruční PAUZA, AUTOMATICKÁ pauza/pokračování podle pohybu (stání, chůze, noc), vícedenní cesta = JEDEN záznam (vlastní i výpůjčka), SLOUČENÍ jízd do tripu (+ zpět), smysluplné statistiky.
- Kalkulačka: přepínač „vyzvednutí od 12:00“ PRYČ, jen informace (+ úspora); čas se volí jen v rezervaci. **Zákazník nikdy nevyplňuje nic dvakrát.** (hotovo, čeká na ověření)
- E-mail zákazníkovi při nezapsané placené změně: **NE** (odstraněno, commit 1d57d742; obsluze e-mail zůstává).
- „4. důležité“ = prodejní texty (`app-v2-sales-copy.js`), UX kontrola (`app-v2-ux-review.js`), pojistka funkčnosti (`functional-diff-audit.js`) — udělat PŘED vydáním (ride změny jsou teď vyžádané majitelem → povolené).
- „5. ani neposílej“ = SQL majiteli NEposílat ke schválení; po ověření dát rovnou jako migrace do `supabase/migrations/` (názvy řadit ZA nejnovější soubor v main — main má už `20261022_gear_rental.sql`, `20261022b_live_viewers.sql`) + STATE_1–6 ve stejném commitu. Merge = aplikace na živou DB → jen 100% ověřené, idempotentní.
- „7. ne“ = ostatní otevřené otázky (VOP čl. 5 l), PREHLED.md) teď neřešit.
- „1., 2., 3. dotáhni a jdeme zkusit android app novou verzi buildnout“ → po dokončení 1–3 testovací build v Codemagic („MotoGo24 Android Build“, větev `claude/moto-go-mobile-conversion-gqg5qo`, bez merge).

## ⚠️ ŽIVÁ CHYBA (neopravená, majitel ví) — storno z Velínu s částečnou / žádnou vratkou
DB trigger `trg_notify_booking_cancelled_email` po `status→cancelled` volá `send-cancellation-email` BEZ částky; funkce si dopočte vratku podle storno tabulky, zavolá `process-refund` a získá `claim_email_send` dřív než Velín → volba obsluhy (0 % / 50 %) se přebije (≥ 7 dní před začátkem → 100 %). Nezávisle zopakováno: `stornofix/REPRO.md`. Oprava NEZAČATA (worktree byl bez změn). Další krok: workflow `workflows/storno-refund-hotfix-wf_d7459438-494.js` (worktree z origin/main na samostatné větvi `claude/hotfix-storno-refund-gqg5qo`) — **před pushnutím té větve požádat majitele o souhlas** (jako u #2213). Dočasně: majitel po stornu s částečnou vratkou kontroluje Stripe. Harness: `paydec/vrf/` (README.txt).

## Stav main (živé)
- Edge funkce plateb = `550ad417` (hotfix #2213 vrátil neověřené platby z #2212). Vývojová větev drží svou verzi plateb (merge 5200139c zachoval `supabase/functions` větve) — při dalším `merge origin/main` znovu ohlídat, aby revert nepřepsal platby ve větvi.
- Žádné SQL z této větve v main není.

## STAV úloh při zastavení (22. 10. ~21:00 Praha)
1. **Jízdy** (run `wf_ace31e66-1f7`, výsledky `reports/rides.json`): hotovo understand ×3, 2 návrhy, `rides/SPEC.md` (+ `SPEC_OWNER_CS.md`), impl logika (oba stromy, `rides/LOGIC_API.md`), SQL koncepty `rides/sql/` (+ test, `STATE_PATCH.md`, `rides/setup.sh` pro PG16), obrazovky starý vzhled (oba stromy) i v2 (Android). **Přerušeno: impl:velin.** Nezačato: verify (scenarios, sql, ui, code) + opravy.
2. **Appka v2** (run `wf_13a7a4b2-0f3`, `reports/v2-continue.json`): hotovo opravy kola 1 (catalog, profile, reservations, routes), 12:00 jako informace, audit + opravy „nic dvakrát“ (home, catalog, booking, shared, reservations, profile, routes). **Přerušeno: verify r2** (parity, render). Pak verify/fix kola.
3. **Platby** (`reports/payments-finish.json` — dokončeno; `reports/payments-verify-final.json` — g1: refunds + charges hotové, ux přerušené). **Otevřené blockery** (verify:refunds:g1): (a) webhook charge.refunded → pojistný storno e-mail volá process-refund s částkou → druhá vratka (oprava: `skip_refund: true` v tom volání); (b) vratka storna není „právě jednou“ (zámek claim_email_send 'refund_cancellation' + cílová částka minus už vrácené dle metadat Stripe); (c) = živá chyba výše; + majory (refund_pending navždy po pending vratce, živá rezervace „refunded“ po vyčerpání doplatku, Velín 100 % „částečné vrácení“ nic nevrátí, plné storno ignoruje QR část). verify:charges:g1: major — měna z klienta (`currency || 'czk'`) a webhook nekontroluje měnu. Další krok: fix:g1 se všemi, pak verify kola (skript `workflows/payments-verify-final-wf_3128b0af-700.js`).
4. **Build Androidu nanečisto** (`build/`): **debug APK se úspěšně sestavil** (snapshot cab35677, 18,5 min, Flutter 3.47.7, AGP 8.11.1, Kotlin 2.2.20, JDK 17) → konfigurace sestavení je v pořádku. Release (R8) build nedoběhl (zastaveno). V novém kontejneru SDK znovu instalovat (~9 GB s Gradle cache — hlídat disk) nebo nechat rovnou Codemagic.

## Jak navázat
- **Stejný kontejner (journály v `~/.claude/projects/.../subagents/workflows/<run>/journal.jsonl` existují):** `Workflow({scriptPath: <skript>, resumeFromRunId: <run>})` — hotoví agenti se vezmou z cache. Skripty: `~/.claude/projects/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/workflows/scripts/` (kopie v `workflows/`).
- **Nový kontejner:** skripty z `workflows/`, přepsat `const S = '…'` na nový scratchpad, obnovit podklady (`rides/*` → `S/rides/`, `paydec/*` → `S/paydec/`, `reports/r1_area_issues.json` → `S/v2cont/`), a napsat POKRAČOVACÍ skripty (ne od začátku!): jízdy = impl:velin → verify/fix; v2 = verify r2 → fix; platby = fix:g1 (issues z `reports/payments-verify-final.json`) → verify; storno hotfix = fix → verify. Vstupy z `reports/*.json`.
- **Pořadí:** (0) začátek session dle CLAUDE.md (STATE, issues, `git fetch && merge origin/main` + ohlídat revert plateb), (1) storno hotfix (živá chyba), (2) jízdy + v2 souběžně, (3) platby, (4) „4. důležité“ (texty, UX, pojistka), (5) SQL jako migrace + STATE, (6) „můžete buildit“ → Codemagic, (7) vydání.
- **Limity:** 4 workflow souběžně ≈ 9,5 %/h týdne a ~1 %/min pětihodinového okna → nejvýš 2 workflow současně. Disk ~39 GB allowance: mazat `/tmp/flutter_tools.*` starší 20 min, goldeny, staré PG clustery.

---
# (Historie) 
## Handoff 2026-10-16 → navázání po resetu týdenního limitu (čt 22. 10. 15:00)

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
