# Appka — chyby nahlášené majitelem 15. 11. 2026 (po buildu 5.0.1), oprava po resetu limitu

Pracovní soubor. **Před sloučením PR ho smaž** (`git rm -r .claude/handoff`). Pokyn majitele: „Zatím si to jenom ulož a pokračovat budem po resetu limitu.“ Majitel chce postup **logicky a úsporně** („není třeba vždy vše překopat, mé zadání je často drobná korekce nebo ctrl+c ctrl+v“) → malé cílené opravy, žádné velké workflow, testy jen dotčené + na konci celá sada obou stromů.

Stav: 5.0.1 je v `main` (#2225, #2226; `main` = testovaný `33915f84`). Otevřený PR #2227 (tato větev) = úklid; další opravy pokračují na téže větvi `claude/moto-go-mobile-conversion-gqg5qo` (číslo verze, např. 5.0.2+120, potvrdit s majitelem). Pravidla oddílu 0 z minulého plánu platí dál (oba stromy 1:1, `diff -rq` = 20, iOS `.dart_tool` beze změny, starý vzhled beze změny, PR jen po „ano“, nic nemergovat).

## 1. Android tlačítko Zpět zavře appku (VYSOKÁ priorita)
Majitel: „když dám androidácký tlačítko zpět … a jsem třeba v Domů, tak místo toho, aby mě to hodilo nahoru na stránku Domů, tak mi to zavře aplikaci, což je chyba. **Nikdy**, když kliknu na tlačítko zpět, mi to v Androidu nesmí zavřít aplikaci. Vždycky mě to vrátí jen o krok zpátky, nebo při nejhorším na horní stranu stránky Domů.“
- Požadované chování systémového Zpět (i gesto zpět): otevřený list/dialog → zavřít; vnořená stránka → o krok zpět; kořen jiné záložky → na Domů; Domů posunuté dolů → nahoru na začátek Domů; Domů nahoře → **nic** (appka se nezavře).
- Kde hledat: v2 shell (`lib/core/v2/shell/app_shell_v2.dart`, `core/app_shell.dart`, `core/router.dart` — `PopScope`/`canPop`, ShellRoute záložek). Ověř i starý vzhled (pravidlo „nikdy“ platí v obou). Test: widget test se systémovým zpět (`tester.binding.handlePopRoute()`) pro kořen Domů, Domů posunuté, kořen Trasy/Motorky, vnořená stránka.

## 2. Trasy → Místa: „Místa se nepodařilo načíst“
Snímek majitele (Android, nový vzhled, 12:00, banner z Velínu nahoře): záložka Trasy → přepínač **Místa** → karta „Místa se nepodařilo načíst — Nastala neočekávaná chyba. Zkus to prosím znovu…“ + „Zkusit znovu“; mapa pod tím se načte. Zjisti skutečnou chybu (provider míst / RPC nebo dotaz na POI tabulku — čtení živé DB jen REST GET s anon klíčem, nic nezapisovat; porovnej se starým vzhledem a s 5.0.0), oprav příčinu, ne jen hlášku.

## 3. Sloučené jízdy („cesta“): mapa se kreslí špatně
Snímek majitele (Android, 12:03): detail cesty „Balkán 2026“, 17.–19. 10. 2026, „CESTA · 3 dny“, 3 jízdy v této cestě, Soukromá/Sdíleno. V mapě se **překrývá mnoho štítků „Odhad trasy · bez GPS“** (naskládané přes sebe, nečitelné), u vlajky cíle je vrstvená obrysová čára (jakoby stejná trasa nakreslená mnohokrát s posunem), mapové podklady působí šedě/vybledle; dole zelená čára okruhu s pohárem.
- Cíl: u sloučené cesty jedna čitelná mapa — každá jízda jednou, štítek „Odhad trasy · bez GPS“ nejvýš jednou (nebo u úseku bez GPS, bez překryvu), podklad mapy normálně.
- K ověření (majitel si nestěžoval, jen poznámka): statistiky vypadají podezřele — max. rychlost 290 km/h, Ø 83 km/h, 1 178 km za 14 h 8 min v sedle, „38× · 44 h 29 min pauzy“ při 3 dnech; zkontroluj, jestli sloučení nepočítá úseky „odhad bez GPS“ (přímé spojnice) do rychlosti/vzdálenosti. Pokud ano, navrhni majiteli opravu, neměň bez dotazu.
- Kde hledat: `features/routes/**` (detail jízdy/cesty, `ride_map.dart`, sloučení jízd), pravidlo „trasy vždy po silnicích“ (2026-11-08) platí dál.

## 4. iOS build 5.0.1 (jen informace)
Codemagic iOS spadl na Apple 403 „A required agreement is missing or has expired“ → majitel (Account Holder) musí přijmout novou smlouvu na developer.apple.com a zkontrolovat App Store Connect → Firma/Smlouvy; pak build znovu. V kódu nic.
