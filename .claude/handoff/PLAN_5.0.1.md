# Appka 5.0.1 — plán dokončení (předávka, stav 14. 11. 2026 18:00 UTC)

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
  - BĚŽÍ `final:repair` (opravuje nálezy níže a přefotí dotčené snímky galerie), po něm se sám spustí `final:recheck` (skeptik).
- Upřesnění pravidla od majitele (14. 11., už v CLAUDE.md bod 6): „v2 = jen vzhled“ znamená hlavně zachovat vstupy, rozsah a funkčnost uživatelského zadávání; zdvojené navigační prvky se rušit smí.

Nálezy závěrečné kontroly, které `final:repair` řeší (ověř v jeho hlášení, co opravil a co přeskočil):
  - `FV-01` (major): In winter every day in the Motorky calendar is hatched and struck through, but nothing says why. No 'zavřeno' line, no 'Volná od 25. 3.', no jump button. The legend has only Volno / Tvůj termín / Obsazeno / Čeká na potvrzení, and 
  - `FV-02` (major): At 320x640 the landscape bike photo is letterboxed into the middle of the card. The whole caption sits directly on top of the sharp photo: category pills, a stray 'samoobsluha' pill on its own line, 'Husqvarna 701 SM', '693 ccm', 
  - `FV-03` (major): The owner complained that Home had no photo. The photo is now a strip about 120 px tall at 320 (about 150 px at 360). The bike name block covers its left half and the 'Tvoje cena od / 1 930 Kč/den / 1 990 Kč' block covers its righ
  - `FV-04` (minor): With one filter on, the 'Filtry 1' button gets wider and the sort dropdown 'Od mé polohy' wraps to a second row. The map button is left alone at the right of the first row, so the toolbar jumps from one row to two and looks unbala
  - `FV-05` (minor): A route without photos shows the road sketch pinned to the top-left area (y≈80–250). The rest of the panel down to the title (about 200 px) is empty dark gradient, so the card looks unfinished next to the photo cards.
  - `FV-06` (minor): The branch chip in the hero's top row is cut off to 'Velké Něm…' because it shares the row with the back button and the '2 / 12' pager.
  - `FV-07` (minor): The loud 'Filtry zapnuté (2)' strip shrinks its text to about 11 px at 320 width (about 15 px bold at 360). On small phones the warning becomes quiet again, which is the 'nemastný neslaný' problem the owner raised.
  - `FV-08` (minor): 'Zobrazeno: 4 motorek' is ungrammatical Czech (it should be '4 motorky'). The text is unchanged from the original app, but the 5.0.1 filter card now puts this line right under the loud card where people read it.
  - `FS-01` (minor): SR-03 W-05 is only half solved. On the empty Home list, 'Vybrat jiný termín' (shown when the reason is closed or booked) scrolls to the Home filter card but does not open it. The calendar exists only inside the opened card, so the
  - `FS-02` (minor): The closed-day hatching can block days that are actually bookable. The set of branches leaves out trailers (`!m.isTrailer`) and bikes with no branch (`m.branchId != null`), but the Motorky list shows both: filteredMotorcyclesProvi
  - `FS-03` (minor): The 8 s auto-close of the AI coach (VR-12) marks the coach as seen even when the bubble was never visible. The timer starts when _coachWanted turns true. During those 8 s the bubble can be Offstage (_coachBlocked), or the FAB can 
  - `FS-04` (minor): How the Home offer narrows is inconsistent with the branch. With only a branch set, filterCount is 0, so the offer shows bikes from every branch while the list below shows only that branch. The claim that the pager count matches t
  - `FS-05` (minor): The offer pager's key includes the NUMBER of filters, not which bikes passed them. Changing one filter value for another (category A to B, still 1 filter) keeps the old PageView and its offset. The carousel then stays on index n o
  - `FS-06` (minor): The Home filter card's calendar and the Motorky date card write the same catalogFilterProvider dates. Only the Motorky one now hatches days on which every branch is closed. On Home the customer can still pick a range that Motorky 

## 2. Zbývající kroky (v tomto pořadí)

### A. Dokončit část 3 (zbývá jen oprava a její kontrola)
1. Počkej na doběhnutí `final:repair` a `final:recheck` (po restartu kontejneru workflow obnov: `Workflow({scriptPath, resumeFromRunId: 'wf_0bc29e1d-e18'})` — hotové kroky se přehrají z paměti). Výsledek čti z journalu (řádky `type=result`; `agentId → label` z řádků `started`).
2. V hlášení `final:repair` zkontroluj, že jsou vyřešené všechny tři závažné nálezy `FV-01..03` (seznam v oddílu 1). Co přeskočil, posuď: závažné nesmí zůstat.
3. Když `final:recheck` hlásí **major** (nebo zůstal neopravený závažný nález): pusť malý workflow „jeden opravář (jen on mění soubory) → jeden skeptik“ se stejnými pravidly jako ve skriptu části 3; opakuj, dokud skeptik nenajde 0 major. Minor: oprav jen malé a bezpečné, zbytek vypiš majiteli.
4. Commit + push.

### B. Zrušit duplicitní tlačítko profilu nahoře (zadání majitele 14. 11.)
Majitel: „Nahoře mi vadí duplicitní tlačítko profilu… dole je v pohodě, nahoře bych ho zrušil.“ Upřesnil i pravidlo „v2 = jen vzhled“: „to pravidlo bylo hlavně o zachování vstupů a rozsahu a funkčnosti uživatelského zadávání“ — tedy zdvojené navigační prvky se rušit smí, formuláře, zadávané údaje a to, co zákazník může udělat, se nemění (už zapsáno v CLAUDE.md, bod 6).
- `lib/features/home/v2/home_header_v2.dart`: odstraň `MgIconButton(key: ValueKey('home-menu'), icon: MgIcons.user, badge: unread, … onTap: router.go(Routes.profile))` i `SizedBox(width: 8)` před ním; logo dostane celou šířku (zkontroluj `_LogoRow(narrow: …)`); odstraň `unread`/`adminUnreadCountProvider` a import, pokud zůstanou nevyužité; oprav komentář třídy.
- Počet nepřečtených zpráv zůstává na záložce Profil ve spodním menu (`lib/core/v2/chrome/v2_nav_bar.dart`) — ověř testem, že tam badge je.
- Projdi hlavičky ostatních kořenových stránek nového vzhledu (Motorky, Rezervace, Trasy): `grep -rn "Routes.profile" lib/features/*/v2 lib/core/v2 lib/core/shell_*.dart`. Odstraň jen tlačítka v hlavičce, která pouze otevírají profil; kontextové odkazy („Doplnit v profilu“ apod.) nech.
- Testy: `grep -rn "home-menu" test` → uprav na nový stav (nikdy neoslabuj jiné kontroly); přidej test „hlavička Domů nemá tlačítko profilu, záložka Profil má badge“. Doplň jednu větu do sekce 5.0.1 v `Motogo-app-main/motogo-app-flutter/DESIGN_V22.md`.
- Zkopíruj do iOS, `diff -rq` = 20. Přefoť snímky galerie, na kterých je hlavička Domů (stejné názvy souborů v `$W/gallery`, `MG_SHOT_IMG_DIR=$W/img`), a **podívej se na ně**.
- Je to malé: udělej přímo, nebo jedním agentem + jedním skeptikem. Commit.

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

## 3. Otevřené body, které majiteli v závěru řekni
- Kalkulačka nemá žádný seznam/karusel po položkách, takže „listování po jedné“ tam nebylo co měnit — zeptej se, která část se posouvá nepříjemně.
- V detailu motorky zůstal pod názvem celý řádek s pobočkou vedle nového štítku.
- Trasy: třetí tlačítko „Mapa tras“ je na 360 px zčásti mimo lištu (jako v 5.0.0).
- Zvýraznění záložky při rezervaci a platbě (svítí „Motorky“) není součástí 5.0.1.
- Záře spodního menu „zadýchá“ třikrát po přepnutí, ne nekonečně (baterie).
- Navíc oproti zadání: nabídka nahoře na Domů se řídí zapnutými filtry; bublina AI asistenta se po 8 s sama zavře; karta motorky neopakuje kategorii a výkon.
- Šipka nahoru se na Domů objeví až po první motorce v seznamu.
