# Appka 5.0.1 — plán dokončení (předávka, stav 14. 11. 2026 19:05 UTC)

Tento soubor je jen pracovní. **Před založením PR ho smaž** (`git rm -r .claude/handoff`).

## 0. Pravidla, která nesmíš porušit
- Pracuj jen na větvi `claude/moto-go-mobile-conversion-gqg5qo`. `main` = `4d63843b` (appka 5.0.0, živá). **Nic nemerguj.** PR založ až po výslovném „ano“ majitele (AskUserQuestion).
- Dva stromy appky: Android `Motogo-app-main/motogo-app-flutter` (má `test/`), iOS `…-ios`. Každý změněný soubor v `lib/` zkopíruj 1:1 do iOS; `diff -rq <android>/lib <ios>/lib` musí dát **přesně 20 řádků**. V iOS stromu v repu **nikdy** nespouštěj `flutter pub get/test/build` (`git diff --quiet HEAD -- Motogo-app-main/motogo-app-flutter-ios/.dart_tool` musí projít).
- Starý vzhled (kill-switch `app_v2_ui=false`) se nesmí změnit. Žádné nové balíčky. Validátory, ceny, platby a pojistky rezervace se nemění.
- Nástroje: `S=/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad`, Flutter `$S/sdk/flutter/bin/flutter` (vždy `--no-pub`), iOS zkušební kopie `$S/vc_ios`, pracovní složka `W=$S/v501`. V `rm` nepoužívej proměnné (jen doslovné absolutní cesty), jinak ho ochrana zablokuje.
- Stop hook chce čistý strom: na konci každého tahu `git add -A . && git commit` (WIP, „nemergovat“) + `git push -u origin <větev>`. Commit zakonči atribučními řádky z aktuálního system-reminderu.
- Agenty ve workflow pouštěj s `model: 'opus'`, nejvýš 2 souběžně mění soubory a jen v různých složkách. Kontejner se občas restartuje: zastavený workflow obnov `Workflow({scriptPath, resumeFromRunId})`, dlouhé testy pouštěj přes Bash na pozadí.
- Majiteli piš česky, krátce, bez interních zkratek; neslibuj, co není ověřené.

## 1. Co je hotové (commit `c64109ed` a starší)
- Část 1 (`9accacfa`): ikona motorky = Material `two_wheeler`, zářivé spodní menu, listování vždy o jednu, šipka nahoru, štítek pobočky. Výsledky: `$W/core_result.json`.
- Část 2 (`4c18cb85`): Domů bez předvybraného termínu a se všemi motorkami („od X Kč/den“, „Volná od“, střídání), nový filtr, trasy jedna na obrazovku, fotka → video jen na Wi-Fi, štítek pobočky na fotkách; kontroly + opravy. Výsledky: `$W/screens_result.json`. Skutečné fotky pro snímky: `$W/img` (env `MG_SHOT_IMG_DIR=$W/img`), stavy nástroje: `test/v2/journey/README.md`.
- Část 3 (workflow `v501-finish`, běh `wf_0bc29e1d-e18`; skript `/root/.claude/projects/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/workflows/scripts/v501-finish-wf_0bc29e1d-e18.js`, journal `…/subagents/workflows/wf_0bc29e1d-e18/journal.jsonl`; výsledky dosud: `$W/finish_result.json`) — stav 14. 11. 18:00 UTC:
  - HOTOVO `docs`: verze `5.0.1+119` v obou `pubspec.yaml`, `Motogo-app-main/motogo-app-flutter/DESIGN_V22.md`, CLAUDE.md bod 6, STATE_2/STATE_6, jedna věta nápovědy ve Velínu (`velin/src/pages/FleetDetailPhotos.jsx`). Zkontrolováno, v pořádku.
  - HOTOVO `final:sceptic`: 0 závažných, 6 drobných (starý vzhled beze změny, žádná oslabená pojistka).
  - HOTOVO `final:visual`: sada náhledů `$W/gallery` (35 PNG + `manifest.json`: 21 obrazovek 360×780, 6 ve 320×640, 8 snímků „před“); 3 závažné a 5 drobných nálezů (níže).
  - HOTOVO `final:repair` (FV-01..08, FS-01..06) a `final:recheck`: re-check našel 2 závažné a 5 drobných nálezů (FR-01..FR-07, detail v `$W/finish_result.json` pod `final:recheck`).
- Upřesnění pravidla od majitele (14. 11., už v CLAUDE.md bod 6): „v2 = jen vzhled“ znamená hlavně zachovat vstupy, rozsah a funkčnost uživatelského zadávání; zdvojené navigační prvky se rušit smí.
- **BĚŽÍ (spuštěno 14. 11. 18:15 UTC): workflow `v501-last`, běh `wf_4f018613-c58`** (skript `/root/.claude/projects/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/workflows/scripts/v501-last-wf_4f018613-c58.js`, journal `…/subagents/workflows/wf_4f018613-c58/journal.jsonl`). Dělá **kroky A i B najednou**: opravuje FR-01 (hlavní tlačítko nabídky na Domů pod spodním menu při 360×640 v nl/pl/uk – padá `home_fold_test`), FR-02 („Přejít na“ v zimním kalendáři Motorek nefunguje, když už je vybraný termín), drobné FR-03..07, **ruší horní tlačítko profilu v hlavičce Domů** (L8) a přefotí dotčené snímky galerie; opravář na konci sám pouští celou Android sadu. Pak skeptik; při závažném nálezu ještě jedno kolo oprava → skeptik.

## 2. Zbývající kroky (pořadí: A+B → F → C → D → E; krok G až po dodání 5.0.1)

### A + B. Poslední oprava a zrušení horního tlačítka profilu (běží jako workflow `wf_4f018613-c58`)
1. Počkej na doběhnutí (po restartu kontejneru obnov: `Workflow({scriptPath, resumeFromRunId: 'wf_4f018613-c58'})`). Výsledek čti z journalu (řádky `type=result`; `agentId → label` z řádků `started`): `last:repair` (pole `fixed`, `skipped`, `suite` = poslední řádek celé Android sady), `last:sceptic:1`, případně `last:repair2` a `last:sceptic:2`.
2. Hotovo je, když poslední skeptik nehlásí žádný **major** a v `last:repair` jsou vyřešené L1 (FR-01), L2 (FR-02) a L8 (tlačítko profilu pryč, badge nepřečtených zpráv zůstává na záložce Profil, `test/v2/ux/lookonly_core_test.dart` upravený bez oslabení). Když major zůstal: pusť další kolo „jeden opravář → jeden skeptik“ podle stejného skriptu; opakuj do 0 major. Minor: jen malé a bezpečné, zbytek vypiš majiteli.
3. Sám si prohlédni přefocené snímky v `$W/gallery` (hlavička Domů bez tlačítka profilu, fotka v nabídce na Domů, zimní kalendář Motorek, pruh filtru na 320 px).
4. Commit + push.

### F. Pojistka: kódy na samoobslužné pobočce až po nahrání dokladů (zadání majitele 14. 11. — udělej PŘED krokem C)
Majitel: „když někdo jde na samoobslužnou pobočku, tak nesmí dostat kódy, dokud nenahraje občanku a řidičák nebo pas a řidičák. Ani v aplikaci. Jsou tam obecně trošku jiný flow.“
- **Prověrka HOTOVÁ** (workflow `codes-docs-audit`, běh `wf_26e8b5bd-d54`; celý výsledek `$W/codes_audit.json`, klíč `verdict`). Výsledek:
  - **U motorek pravidlo platí ve všech kanálech a drží ho server** (ne jen appka): RLS na `branch_door_codes` (zákazník čte jen `sent_to_customer = true`), RPC `get_my_door_codes`, vznik kódů `auto_generate_door_codes`, pojistka `_door_codes_docs_guard`, uvolnění `release_my_door_codes` + automatické po nahrání dokladů, e-mail / SMS / WhatsApp / push / faktura, web, kiosk online i offline. Brána `booking_docs_gate` → `_docs_gate_checklist` chce: (OP z obou stran NEBO pas) A ŘP z obou stran, 18+, platnost ŘP do konce pronájmu, skupinu ŘP na motorku. Platí pro všechny pobočky, ne jen samoobslužné. Cesta, jak kód získat bez dokladů, se nenašla. Úpravy 5.0.1 na kódy ani bránu dokladů nesáhly.
  - Nálezy (vše v SQL, nic v appce): **S2** zákazník si umí sám zapsat `bookings.picked_up_at` (sloupec není chráněný) → oslabuje pojistku `_door_codes_docs_guard` a vypíná výdej od 12:00 (`_kiosk_release_at`); oprava = chránit `picked_up_at` (a `returned_at`, pokud také není chráněný) pro zákaznický JWT v `_protect_handover_columns`. **S1** výpůjčka jen výbavy chce jen doklad totožnosti + 18+ (rozhodnutí majitele 23. 10.), ne ŘP. **S3** stačí „nahráno“, pas a ŘP může být tentýž soubor. **S4/S5** po prvním vydání se doklady znovu nekontrolují a po smazání dokladů kódy zůstávají (rozhodnutí majitele 10. 10.). **S6** obsluha ve Velínu smí kódy uvolnit bez dokladů (`admin_release_door_codes`, zapisuje se do auditu); dětské motorky nevyžadují doklady.
- **ODPOVĚDI MAJITELE (14. 11. 19:00 UTC):** na čtyři otázky neodpověděl výběrem; napsal jen k výbavě: „pro kódy budou nutný OP nebo pas“ → **S1 uzavřeno: u samotné výbavy stačí doklad totožnosti, ŘP ne (beze změny)**. K S2 (zamknout „převzato“), S5 (smazání dokladů) a S3 (různé soubory) se nevyjádřil → **žádné SQL**; v závěrečné zprávě mu je jednou krátce připomeň jako otevřená rozhodnutí (doporučení: S2 ano, S5 zakázat mazání před vyzvednutím, S3 jen různé soubory), neptej se dialogem znovu.
- **Rozhodnutí majitele k nálezům: viz řádek „ODPOVĚDI MAJITELE“ níže** (pokud tam není, zeptej se ho znovu těmi samými otázkami: zamknout „převzato“ S2? ŘP i u samotné výbavy S1? po smazání dokladů kódy odebrat S5? vyžadovat různé soubory pro pas/OP a ŘP S3?). Bez jeho „ano“ **žádné SQL**.
- Jak provést schválené SQL změny: jedna nová migrace `supabase/migrations/20261114a_<slug>.sql` (finální, idempotentní, `create or replace` aktuální definice funkce převzaté z nejnovější migrace / živého snapshotu `origin/supabase-live-snapshot`), zkouška na zkušební PG (`$S/sqlb/pg`, README: `newdb.sh`, `apply.sh`, `deploy_sim.sh`), test: zákaznický JWT nezmění `picked_up_at`; kiosk / obsluha (service_role, security definer RPC) ano; aktualizace `SUPABASE_BACKEND_STATE_3/4/6.md`. Sloučení do `main` migraci nasadí samo → v PR to majiteli výslovně napiš a po sloučení zkontroluj log „Deploy SQL migrations“.
- Majiteli na závěr přepiš `for_owner_cs` z verdiktu (jak to dnes funguje) a co se změnilo.

### C. Závěrečné kontroly (Bash na pozadí, ~40 min, sám, ne přes agenta)
```
S=/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad; A=/home/user/Vel-n/Motogo-app-main/motogo-app-flutter; I=/home/user/Vel-n/Motogo-app-main/motogo-app-flutter-ios; F=$S/v501/final; T=$S/efinish/f/ft; FL=$S/sdk/flutter/bin/flutter; mkdir -p $F
cd /home/user/Vel-n && git rev-parse --short HEAD > $F/final_head.txt && git diff --name-only 4d63843b HEAD -- Motogo-app-main/motogo-app-flutter/test | grep "_test.dart$" | sed 's#^Motogo-app-main/motogo-app-flutter/##' > $F/files.txt
cd $A && for X in 129600 242100 343500 366300 475200 581700 43200; do MG_FAKE_OFFSET=$X LD_PRELOAD=$T/shim.so $FL test --no-pub --reporter compact $(cat $F/files.txt) > $F/wd_$X.log 2>&1; echo "weekday $X rc=$?"; done
$FL analyze --no-pub > $F/an_android.log 2>&1; grep -a -E 'issues? found' $F/an_android.log
$FL test --no-pub --reporter compact > $F/suite_android.log 2>&1; echo "rc=$?" > $F/suite_android.rc
rm -rf /tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/vc_ios/lib /tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/vc_ios/test
cd $S/vc_ios && cp -r $I/lib lib && cp -r $A/test test
$FL analyze --no-pub > $F/an_ios.log 2>&1; grep -a -E 'issues? found' $F/an_ios.log
$FL test --no-pub --reporter compact > $F/suite_ios.log 2>&1; echo "rc=$?" > $F/suite_ios.rc
diff -rq $A/lib $I/lib | wc -l
```
Musí vyjít: všech 7 běhů „weekday“ rc=0 (testy nesmí záviset na dni/hodině — když některý spadne, oprav test, ne appku, pokud appka počítá správně); analyze Android **142 / 0 chyb**, iOS **137 / 0 chyb**; obě sady `rc=0` a 0 selhání (počet prošlých bude vyšší než 7 055); `diff -rq` = 20; iOS `.dart_tool` beze změny; `git status` čistý a HEAD = testovaný commit. Po restartu kontejneru přečti `.rc` soubory a dopusť jen chybějící část. Cokoli po testech změníš v `lib/` nebo `test/` = testy znovu.

### D. Náhledy pro majitele
`$W/gallery/manifest.json` + PNG → publikuj jako soukromý Artifact (nejdřív načti skill `artifact-design`; obrázky jako supporting files; česky, u každého snímku krátký nadpis a jedna věta, kde existuje i snímek „před“). Pošli majiteli odkaz. Každý snímek si předtím sám prohlédni; co vypadá špatně, vrať do kroku A/B.

### E. Uzavření
1. `git rm -r .claude/handoff`, čistý commit, push.
2. Zeptej se majitele, jestli založit PR. Tělo PR česky a srozumitelně: co se mění (11 bodů zadání + zrušené tlačítko profilu), jak ověřeno (čísla z kroku C, kontroly, snímky), **co ověřené není** (skutečný telefon, přehrání videa na zařízení, Wi-Fi/data), otevřené body níže. Patička PR podle system-reminderu.
3. V PR není žádné SQL ani edge funkce → po sloučení se nic nenasazuje do databáze; Velín (jedna věta nápovědy) nasadí Vercel. Pak build v Codemagicu („MotoGo24 Android Release“, „MotoGo24 iOS Release (App Store)“), Flutter je tam připnutý na 3.47.7.

### G. Půjčení jen oblečení/výbavy v appce (zadání majitele 14. 11.) — SAMOSTATNĚ, až po dodání 5.0.1 (vlastní větev práce a vlastní PR; číslo verze potvrď s majitelem)
Majitel doslova: „ještě zadej do plánu, aby na stránce Domů bylo možné, pokud je pobočka otevřená, zapůjčit i oblečení; pro kódy budou nutný OP nebo pas; to víceméně vše funguje už na webu, jen doplň do app UX i pro tuto službu.“ a „bude to vidět v rezervacích, jen ten [záznam] bude oblečení, ne motorka; oblečení a motorka lze udělat současně, ale pokud to zákazník udělá obráceně, nedostane slevu; ale v app by to mohl mít od ranku 15 zdarma pouze oblečení; oblečení může mít více kusů na jedno jméno, asi vybere velikosti, případně klikne ‚další sada oblečení‘; prostě na webu to funguje, přidej to nějak citlivě do záložky Domů, je to okrajová služba.“
- Backend je hotový od 23. 10. (`bookings.booking_kind='gear'`, `moto_id` NULL, `branch_id`, `gear_lines`, `gear_per_day`; RPC, RLS, kódy šatny, kiosk 1.3.0) — viz odstavec „Výpůjčka JEN výbavy“ v `CLAUDE.md` a STATE_1–6 (2026-10-23). **Závazné zadání pro appku už existuje:** `Motogo-app-main/motogo-app-flutter/GEAR_RENTAL_APP.md` (část 1: pravidla, `app_visible`, RPC kontrakty, model, UI) a `GEAR_RENTAL_APP_EDIT.md` (část 2: úpravy, vratka, objednání v appce, AI agent, testy). Vzor chování = web: `motogo-web-php/pages/pujceni-obleceni.php`, `js/gear-rental*.js`, `js/pages-upravit-rezervaci-gear*.js`.
- Co majitel chce navíc / upřesnil:
  1. **Vstup na Domů, citlivě — je to okrajová služba:** jeden nenápadný řádek ve stylu ostatních řádků na Domů (tmavý čtvereček se svítící ikonou, text typu „Půjčit jen výbavu“ = klíč `gearRentCta`), ne v hlavní nabídce motorek. Ukázat **jen když je pobočka otevřená** (není v `branch_closures`, `branches.is_open`) a služba je zapnutá (`app_settings.gear_rental…`; samoobslužná pobočka jen při `self_service_enabled`).
  2. **Objednání v appce jako na webu:** pobočka, termín a čas, kusy výbavy s velikostmi, víc kusů na jedno jméno + tlačítko „Další sada“ (víc sad), cena za den, souhrn, platba stávající platební cestou. Co nejméně psaní; využij uložené velikosti.
  3. **Doklady:** stačí OP (líc + rub) nebo pas a 18+; ŘP se nevyžaduje (kódy šatny se bez dokladu nevydají — drží server).
  4. **Rezervace:** výpůjčka se ukáže v seznamu i detailu jako „Výpůjčka výbavy“ (ne motorka), s kódem šatny (+ schránka s klíčem od brány), postupem a úpravami přes RPC. Rozlišovat **výhradně podle `booking_kind`**.
  5. **Ceny:** výbava objednaná spolu s motorkou zůstává jako dnes; samostatná výpůjčka výbavy slevu nemá (dnešní pravidlo: bez věrnosti a promo). **Nově: od věrnostního ranku 15 by samotná výbava v appce mohla být zdarma** — to je změna cenotvorby na serveru (SQL + STATE, případně web), ne vzhledu. **Před implementací si u majitele potvrď přesné pravidlo** (od ranku 15 včetně? 100 %? kolik kusů / dní? jen appka, nebo i web? co poukazy) a navrhni ji tak, aby cenu počítal server, rezervace za 0 Kč bezpečně přeskočila platbu (bez Stripe intentu) a brána dokladů platila dál. SQL až po jeho „ano“, zkouška na zkušební PG, STATE.
  6. **Pořadí vydání** (zadání §2): appka v obou obchodech → zvýšit minimální verzi → teprve pak ve Velínu zapnout „Zobrazit v aplikaci“. Nová appka na `app_visible` nesmí záviset (čte RPC `get_my_gear_bookings()`).
- Postup: (1) čtecí mapování (co z `GEAR_RENTAL_APP*.md` už appka má — dnes jen zmínky v `reservation_models.dart`), (2) návrh obrazovek ve starém i novém vzhledu, (3) stavba v obou stromech po oblastech s nesouvisejícími soubory, (4) vizuální kritik + skeptik + proklikání v nástroji (stavy: pobočka otevřená/zavřená, obslužná/samoobslužná, bez dokladů, rank 15+), (5) obě kompletní sady testů, (6) náhledy majiteli, (7) dotaz na PR. Stejná pravidla jako v oddílu 0.

## 3. Otevřené body, které majiteli v závěru řekni
- Kalkulačka nemá žádný seznam/karusel po položkách, takže „listování po jedné“ tam nebylo co měnit — zeptej se, která část se posouvá nepříjemně.
- V detailu motorky zůstal pod názvem celý řádek s pobočkou vedle nového štítku.
- Trasy: třetí tlačítko „Mapa tras“ je na 360 px zčásti mimo lištu (jako v 5.0.0).
- Zvýraznění záložky při rezervaci a platbě (svítí „Motorky“) není součástí 5.0.1.
- Záře spodního menu „zadýchá“ třikrát po přepnutí, ne nekonečně (baterie).
- Navíc oproti zadání: nabídka nahoře na Domů se řídí zapnutými filtry; bublina AI asistenta se po 8 s sama zavře; karta motorky neopakuje kategorii a výkon.
- Šipka nahoru se na Domů objeví až po první motorce v seznamu.
