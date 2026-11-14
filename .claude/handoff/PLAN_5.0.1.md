# Appka 5.0.1 — plán dokončení (předávka, stav 14. 11. 2026 18:15 UTC)

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

## 2. Zbývající kroky (v tomto pořadí)

### A + B. Poslední oprava a zrušení horního tlačítka profilu (běží jako workflow `wf_4f018613-c58`)
1. Počkej na doběhnutí (po restartu kontejneru obnov: `Workflow({scriptPath, resumeFromRunId: 'wf_4f018613-c58'})`). Výsledek čti z journalu (řádky `type=result`; `agentId → label` z řádků `started`): `last:repair` (pole `fixed`, `skipped`, `suite` = poslední řádek celé Android sady), `last:sceptic:1`, případně `last:repair2` a `last:sceptic:2`.
2. Hotovo je, když poslední skeptik nehlásí žádný **major** a v `last:repair` jsou vyřešené L1 (FR-01), L2 (FR-02) a L8 (tlačítko profilu pryč, badge nepřečtených zpráv zůstává na záložce Profil, `test/v2/ux/lookonly_core_test.dart` upravený bez oslabení). Když major zůstal: pusť další kolo „jeden opravář → jeden skeptik“ podle stejného skriptu; opakuj do 0 major. Minor: jen malé a bezpečné, zbytek vypiš majiteli.
3. Sám si prohlédni přefocené snímky v `$W/gallery` (hlavička Domů bez tlačítka profilu, fotka v nabídce na Domů, zimní kalendář Motorek, pruh filtru na 320 px).
4. Commit + push.

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
