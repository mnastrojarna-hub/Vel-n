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
  - když cesta stojí **20 h a víc** a otevřeš appku (třeba u snídaně), appka jen **připomene** „Cesta stojí od … Jedeš dál? Nic nedělej. Je hotová? Ukonči ji.“ — GPS běží dál a ranní rozjezd se nahraje sám do stejné cesty (upraveno 30. 10. večer: dřív tu appka GPS vypnula a když jsi neklepl Pokračovat, celý další den se ztratil). Noc v hotelu (do 20 h) nic;
  - GPS vypne a zeptá se „Pokračovat v cestě / Ukončit a uložit“ až po **48 h** stání (při otevření appky i bez něj; na Androidu přijde upozornění). Zapomenutý Stop tak nesvítí dny; dojíždění v prvních 48 h po návratu domů se ale ke staré cestě přidá, pokud cestu po připomínce neukončíš.
- Neuložený Stop (bez signálu) se zkouší znovu sám (otevření appky, každé 2 min) — i když systém appku mezitím zavře; ukončená cesta se už nikdy znovu nerozjede. Nová jízda se spustí, až se předchozí uloží — jinak by se obě spojily.
- Když přes noc vypneš polohu, cesta se tím neukončí ani nerozdělí: appka ukáže „poloha nedostupná“ a po zapnutí polohy nahrává dál.
- Výměna motorky (SOS) nebo navazující výpůjčka: stará jízda se uloží a body nové motorky jdou do nové jízdy — i když telefon byl při výměně bez signálu.
- Výpůjčka vrácená, zatímco záznam stojí: appka to do 30 min pozná sama (i na pozadí) a GPS vypne. Noc v boxu samoobsluhy výpůjčku neukončí.
- Motorka zamčená v kóji samoobsluhy, výpůjčka ale běží (přes noc, nebo předčasné vrácení, které kiosk dokončí až den po konci): GPS ještě **16 h** čeká na ranní vyjetí (jízda pak pokračuje sama, pořád jedna), potom se vypne. Dřív svítilo až do dokončení výpůjčky — klidně 4 dny. Vyjede-li motorka později, nahrává se po otevření appky (do stejné jízdy). (upraveno 30. 10., kolo 5)
- Dvě motorky na jednom účtu (kamarád si dnes převezme druhou): tvoje jízda zůstává u tvé výpůjčky a nerozdělí se; dřív se tvoje km od jeho převzetí zapisovaly do jeho výpůjčky. Výjimka: v poslední den tvé výpůjčky se to od navazující výpůjčky rozeznat nedá — tam záznam přejde na novější. (kolo 5)
- Výpůjčka stojí **48 h** bez jízdy a appku jsi celou dobu neotevřel → GPS se kvůli baterii vypne (přijde upozornění „stačí otevřít appku“). Jakmile appku otevřeš, záznam se sám zase zapne a čeká na rozjezd — klepat nic nemusíš. Každé otevření appky počítá 48 h znovu. Jízda během vypnutého GPS se nenahraje (appka to po otevření řekne). (kolo 5)
- Výpůjčka nahraná celá bez dat (cizina bez roamingu) se po návratu signálu uloží celá od převzetí, i když už je motorka vrácená (po nasazení SQL).
- U výpůjčky GPS zůstává zapnuté, aby Velín pořád viděl, kde motorka je (kromě pojistek výše: kóje 16 h, 48 h bez jízdy i bez otevření appky).

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
6. *(volitelné)* **Oprava historie:** u dosavadních uložených jízd se noci, dlouhé zastávky i čas po posledním bodu (pozdě zmáčknutý Stop) přesunou ze „stání“ do „pauz“. Kilometry se nemění.

- Vše je otestované na kopii databáze, ne na živé DB.
- Velín se nasazuje **spolu s SQL**. Jinak by pozastavenou výpůjčku po 3 h ukazoval jako „Záznam visí“.
- Nová appka funguje i před nasazením SQL: pauza jede v telefonu, přes noc se ale jízda rozdělí jako dnes a slučování je skryté. Nic se neztratí ani tiše nezastaví.

## Otevřené volby (výchozí stav navržen, stačí potvrdit nebo změnit)
1. Prahy **5 min stání / 3 min chůze / rozjezd 2× nad 20 km/h**. Jdou měnit z Velína.
2. **Baterie — potřebujeme tvoje rozhodnutí (před vydáním).** GPS zůstává přes noc zapnuté při auto-pauze (odhad 5–15 % baterie za noc) — u výpůjček i vlastní cesty, nejvýš 48 h stání (u výpůjčky 48 h bez otevření appky; otevření appky ho zase zapne; motorka v kóji kiosku nejvýš 16 h). Pojistky: „doma“ po **3 h** jen upozornění; po **20 h** při otevření appky jen připomínka (GPS běží dál); GPS vypnout po **48 h** (vše jde měnit z Velína). Možnosti: (a) nechat takhle; (b) noční pojistka: stojí-li motorka mezi 21:00 a 5:00 aspoň 3 h, GPS se vypne a ráno se nahrává až po otevření appky (riziko ztráty ranní jízdy); (c) přepínač pro jezdce „šetřit baterii v noci“. Výchozí: (a).
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
