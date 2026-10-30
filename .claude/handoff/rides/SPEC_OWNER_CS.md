# Záznam jízd: pauza, auto-pauza, vícedenní cesty, slučování — shrnutí pro majitele

Stav 2026-10-22. Návrh, nic zatím nasazeno. Technické zadání pro implementaci je v `SPEC.md` (stejná složka).

## Co se změní pro jezdce

**Tlačítko Pauza**
- Vedle „Ukončit“ přibude **Pozastavit / Pokračovat**.
- Najdeš ho všude, kde se záznam ovládá:
  - Moje zážitky,
  - menu „Přidat“,
  - navigace (starý i nový vzhled),
  - nový vzhled: nahrávač, spodní lišta, řádek na Domů.
- Ruční pauza vypne GPS, takže nežere baterii. Pokračuje se klepnutím.
- Funguje i u výpůjčky. Výpůjčka se dál ukončuje sama vrácením motorky.

**Automatická pauza (nic se nemačká)**
- Záznam se sám pozastaví, když motorka stojí déle než **5 minut** nebo když po zastavení jdeš **3 minuty pěšky**.
- Sám pokračuje, jakmile jedeš **2× po sobě přes 20 km/h**. Pěšky se to stát nemůže.
- Večer dojedeš, jdeš spát a nic neřešíš. Ráno vyjedeš a nahrává se dál do **stejné cesty**.
- Chůze po benzínce, k jezeru nebo po hotelu se do jízdy nepočítá. Kus prošlý pěšky se ze stopy odřízne.
- Nic se neztratí: po rozjezdu appka doplní i posledních pár desítek vteřin před tím, než se pauza ukončila.

**Jedna cesta = jeden záznam**
- Vícedenní cesta na vlastní motorce i celá výpůjčka zůstane **jedním záznamem** přes všechny noci.
- Konec nastane, když:
  - ji ukončíš ty,
  - vrátíš výpůjčku,
  - nebo se u vlastní cesty 3 dny nic neděje (pak se sama uloží).
- V detailu jsou **etapy po dnech**: km, čas v sedle, průměr, maximum a nastoupáno za každý den.
- Výpůjčka se nahrává od chvíle, kdy se rozjedeš, ne od podpisu protokolu. Velín přesto vidí polohu hned po převzetí.

**Slučování jízd do jedné cesty**
- Libovolné jízdy jdou **sloučit do jedné cesty** se součty a etapami. Jízdy se nemažou, jen se zobrazí spolu.
- Hned je k dispozici **„Zpět“**, později **„Rozdělit cestu“**.
- Starší výpůjčky, které se rozpadly na víc jízd, se v appce ukážou jako jedna cesta automaticky.

**Statistiky, které dávají smysl**

| Údaj | Jak se počítá nově |
|---|---|
| ujeto, čas v sedle | jen opravdová jízda; chůze a „vlnění“ GPS v pokoji se nepočítají |
| zastávky | jen krátké stání do 5 minut |
| pauzy | delší stání a noci zvlášť, např. „3× · 31 h“ |
| na cestě | čas bez pauz, takže už žádných „167 h“ |
| Ø | počítaný z času v sedle |
| max | jen rychlost změřená GPS, ne ze skoků polohy |
| nastoupáno | vyhlazené: stoupání se už neztrácí a šum na rovině se nepřičítá |
| dny / etapy | počet dní a etap cesty |

- Za jízdy uvidíš živě km a čas v sedle místo dnešního „N bodů“.
- Cesta autem po vrácení motorky se do výpůjčky už nezapíše.
- Pozdě zmáčknuté „Ukončit“ nepřidá hodiny stání.

**Baterie**
- Při automatické pauze musí GPS zůstat zapnuté. Android ani iOS nedovolí appce GPS znovu zapnout na pozadí, takže jinak by se ráno nepoznal rozjezd.
- Odhad spotřeby je **5–15 % baterie za noc**. Ověříme měřením na telefonu.
- Pojistky u vlastní cesty (zapomenutý Stop — upraveno 30. 10.):
  - když stojíš **3 h na místě, kde cesta začala** (typicky doma, i po vícedenní cestě), přijde jen upozornění „Jsi zpátky tam, kde cesta začala“ — GPS běží dál a ráno se rozjezd nahraje sám;
  - když cesta stojí **20 h a víc** a otevřeš appku (nebo ji systém mezitím zavřel), appka ještě minutu poslouchá GPS — když se zrovna rozjíždíš, nic se neptá a nahrává dál; jinak vypne GPS a zeptá se „Pokračovat v cestě / Ukončit a uložit“. Noc v hotelu (do 20 h) se neptá. Bez odpovědi se nic nenahrává — další jízda se tak tiše nepřilepí ke staré cestě;
  - když appku vůbec neotevřeš, vypne se GPS po **48 h** stání (na Androidu přijde upozornění, pak stačí klepnout Pokračovat).
- Neuložený Stop (bez signálu) se zkouší znovu sám (otevření appky, každé 2 min). Nová jízda se spustí, až se předchozí uloží — jinak by se obě spojily.
- Výpůjčka nahraná celá bez dat (cizina bez roamingu) se po návratu signálu uloží celá od převzetí, i když už je motorka vrácená (po nasazení SQL).
- U výpůjčky GPS zůstává zapnuté, aby Velín pořád viděl, kde motorka je.

## Co se nemění
- Automatický záznam při výpůjčce (když je povolená poloha) a přepínač.
- Ruční „Zaznamenat jízdu“.
- Body a fotky na jízdě, názvy, sdílení, mazání.
- Velín „Mapa a poloha“ a diagnostika.
- Navigace.
- Jízdy pod 1 km se dál zahazují.
- Kiosk, rezervace a platby se nedotýkají.

## Co dělá SQL (k tvému schválení, 5 + 1 souborů)
1. **Nové sloupce u jízd:** pauzy, etapy, příznak „appka umí pauzu“, cesta (id a název). Nový přepínač `ride_autopause` ve Velínu (Feature flags) umí auto-pauzu kdykoli vypnout bez vydání appky; ruční pauza zůstane.
2. **Nový výpočet statistik:** viz tabulka výše; řídší, ale rovnoměrná stopa i u týdenních cest.
3. **Ukládání bodů a ukončení:**
   - stejné funkce jako dnes, takže stará appka 4.1.3 funguje beze změny;
   - body po vrácení motorky se zahodí a jízda se uzavře k času vrácení.
4. **Start a noční úklid:**
   - **výpůjčka se už nikdy nedělí** po 3 h ani 36 h, a to ani u staré appky;
   - vlastní cesta nové appky vydrží do „Ukončit“ nebo 3 dny bez jízdy;
   - vlastní jízdy staré appky 4.1.3 zůstávají jako dnes.
5. **Jedna nová funkce na slučování a rozdělování jízd.**
6. *(volitelné)* **Oprava historie:** u dosavadních uložených jízd se noci a dlouhé zastávky přesunou ze „stání“ do „pauz“. Kilometry se nemění.

- Vše je otestované na kopii databáze, ne na živé DB.
- Velín se nasazuje **spolu s SQL**. Jinak by pozastavenou výpůjčku po 3 h ukazoval jako „Záznam visí“.
- Nová appka funguje i před nasazením SQL: pauza jede v telefonu, přes noc se ale jízda rozdělí jako dnes a slučování je skryté. Nic se neztratí ani tiše nezastaví.

## Otevřené volby (výchozí stav navržen, stačí potvrdit nebo změnit)
1. Prahy **5 min stání / 3 min chůze / rozjezd 2× nad 20 km/h**. Jdou měnit z Velína.
2. GPS zapnuté přes noc při auto-pauze (odhad 5–15 % baterie). Pojistky: „doma“ po **3 h** jen upozornění; otázka při otevření appky po **20 h** stání; bez otevření GPS vypnout po **48 h** (vše jde měnit z Velína).
3. Vlastní cesta se sama uloží po **3 dnech** bez jízdy (strop 30 dní).
4. Stará appka 4.1.3: vlastní jízdy se dál dělí přes noc (jako dnes), výpůjčky už ne.
5. „Na cestě“ nově **bez pauz**, v appce i ve Velínu.
6. Opravit historii jízd (noci → pauzy)? Návrh: **ano**.
7. Přepnutí „cestu vidí i ostatní“ platí pro všechny jízdy v cestě.
8. Obrazovka slučování a detail cesty jsou zatím ve starém vzhledu (v novém vzhledu jako rámeček, stejně jako platby). Detail cesty v novém vzhledu skládáme z existujících dílů. Připomínkuješ, až to bude hotové.

## Známá omezení
- Taxi, autobus, trajekt nebo kolo nad 20 km/h appka bez dalšího oprávnění od motorky nerozezná a nahraje je jako jízdu. Pomůže ruční pauza.
- Kolona pod 7 km/h se do km nepočítá; jde nejvýš o stovky metrů.
- Když systém appku v noci zabije, ráno se nahrává až po otevření appky. Cesta ale zůstane jedna.
