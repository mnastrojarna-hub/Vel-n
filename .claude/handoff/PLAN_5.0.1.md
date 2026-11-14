# Appka 5.0.1 — plán dokončení (předávka, stav 14. 11. 2026 17:45 UTC)

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
- Část 3 běží: workflow `v501-finish`, běh `wf_0bc29e1d-e18` (skript `/root/.claude/projects/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/workflows/scripts/v501-finish-wf_0bc29e1d-e18.js`, journal `…/subagents/workflows/wf_0bc29e1d-e18/journal.jsonl`). Agent `docs` už doběhl: verze `5.0.1+119` v obou `pubspec.yaml`, `DESIGN_V22.md` u Android appky, CLAUDE.md bod 6, STATE_2/STATE_6, jedna věta ve Velínu (zkontrolováno, v pořádku). Zbývá v něm: `final:sceptic`, `final:visual` (vyrobí `$W/gallery/*.png` + `manifest.json`), případně `final:repair` a `final:recheck`.

## 2. Zbývající kroky (v tomto pořadí)

### A. Dokončit část 3
1. Až workflow doběhne (nebo ho po restartu obnov), přečti výsledek z journalu (řádky `type=result`; mapuj `agentId → label` z řádků `started`).
2. Když `final:recheck` (nebo `final:sceptic`/`final:visual` bez následné opravy) hlásí **major**: pusť malý workflow „jeden opravář (jen on mění soubory) → jeden skeptik“ se stejnými pravidly jako ve skriptu části 3; opakuj, dokud skeptik nenajde 0 major. Minor: oprav jen malé a bezpečné, zbytek vypiš majiteli.
3. Commit.

### B. Zrušit duplicitní tlačítko profilu nahoře (zadání majitele 14. 11.)
Majitel: „Nahoře mi vadí duplicitní tlačítko profilu… dole je v pohodě, nahoře bych ho zrušil.“
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
