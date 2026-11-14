# MotoGo24 appka · nový vzhled v2 — pravidla majitele (DESIGN_V22)

Krátká verze návrhového dokumentu nového vzhledu (v2). Platí pro OBA stromy appky (`motogo-app-flutter` = Android, `motogo-app-flutter-ios` = iOS) a jen pro nový vzhled za kill-switchem `feature_flags.app_v2_ui`; starý vzhled zůstává beze změny. Obecné pravidlo „v2 = jen upgrade vzhledu“ a synchronizace stromů: kořenový `CLAUDE.md`, bod 6 sekce o dvou stromech appky.

## 0.1 Zpětná vazba majitele 2026-10-16 (R1–R6, doslovně z původního dokumentu)

Tabulka je převzatá beze změny (odkazy „§1“ … „§9“ míří do původního dlouhého dokumentu, viz níže).

### 0.1 Owner feedback 2026-10-16 → where it is answered

| Owner (verbatim gist) | Answer |
|---|---|
| R1 "aby ten člověk měl pocit, že roste … zelené, modré uprostřed, kovy … aby se žádné barvy ranků nepodobaly … 13. stejný jako 20." | §1: one growing 20-level ramp (greens → metals → deepening blues → VIP crimson / gold / pearl → fiery Legenda), ΔE00 ≥ 12.38 for every pair, ≥ 15.60 for neighbours, no pink or purple, prestige of effects rising strictly (flat → metallic → glow → animated foil → fire). Guarded SQL as text. |
| R2 "děkovacích stránek je strašně moc druhů … vždycky musí appka ukázat smysluplnou hlášku, co se pokazilo, proč to nejde, jak to opravit … nikde se to nesmí zaseknout" | §5: new **Stavy** board, ≈ 290 rows in 19 groups (≈ 270 drawn variants, the rest point to a shared one), one template (what · why · how to fix · working action · never hangs), 5 tones, tykání, 8-language rules, hang guards per await (§5.6). |
| "Opravujeme jenom vzhled, ale funkčnost je brutálně odladěná" | The look cannot fix a false message: §5.5–5.6 and §8 list the code requirements that each state needs (error-code mapping, timeouts, idempotent retries, the 15 Kč minimum, honest SOS location). |
| R3 "Nikde jsem tam nenašel zaznamenat moji jízdu, tlačítko." | §4: **ZAZNAMENAT JÍZDU** = primary action of the Trasy tab (record dock on all 3 segments) + first row of Home "Moje zážitky" + full-screen recorder with 18 states. |
| R4 "svítí zeleně jenom první a poslední den, ale měly by být zvýrazněny všechny dny … v jednotné barvě" | §3: one continuous solid `#74FB71` band for start, every day between and end, in every calendar of the app. |
| R5 "aby to nebylo příliš zelený a černý … až moc tmavý, anebo jednolitý … místama bílý pozadí … chybí tam trošku kontrast" | §2: white / canvas pages, one dark hero per phone window, light forms and lists, dark only for photos, live states and the money moment; meta text and input borders raised to AA. |
| R6 "aby tam vždycky bylo dobře viditelné tlačítko zpět a z každé obrazovky se dalo jít zpět" | §6: one back/close standard (44 px, three surface styles, fixed positions, per screen type, system back rules) + per-board audit. |
| "verze 2 nebo 3 asi OK, ale furt je tam ještě hodně co zlepšovat" | §7: concrete detail fixes per board. |
| Earlier points (V2 1–14, V21 2026-10-15) | Unchanged. Level-up celebration stays exactly as shipped ("pozor lvl up video neměň"). |

## Co obsahoval původní dokument (zkráceno)

Původní `DESIGN_V22.md` (iterace 2.2, rozšíření `DESIGN_V21.md` → `DESIGN_V2.md` → `appdesign_spec.md`; ~150 kB, z repa odešel při úklidu) popisoval návrhové tabule a port do Flutteru: rampu 20 barev hodností (R1, SQL `20261016_loyalty_colors_ramp` dosud nenasazené), systém ploch „bílé sekce, tmavé hero“ a barevné tokeny (R5), jednotný zelený pás termínu v kalendářích (R4), tlačítko „Zaznamenat jízdu“ a nahrávání jízdy (R3), tabuli Stavy se ~290 stavy výsledků, poděkování a chyb s pravidlem „co · proč · jak opravit · funkční akce · nikdy se nezasekne“ (R2), standard tlačítka zpět/zavřít 44 px (R6), opravy detailů po tabulích, poznámky k portu, otevřené otázky majitele (§9) a kontrolní seznam. Oslava level-upu zůstává beze změny. Podrobnosti jsou v historii gitu (soubor existoval do úklidu repa).

## 5.0.1 — rozhodnutí majitele 2026-11-14

Majitel po instalaci 5.0.0 výslovně požádal o tyto změny nového vzhledu (verze appky 5.0.1+119, Android i iOS). Jsou to **výslovné výjimky** z pravidla „v2 = jen upgrade vzhledu“; vše ostatní ze staré appky musí fungovat dál beze změny. Backend se nemění (čte se jen existující `get_motos_availability_status`, `branch_closures`, `check_moto_availability`, `get_moto_booked_dates`).

### Domů
- **Žádný předvybraný termín.** Bez zadaných dat není zaškrtnutý žádný víkend (čipy zůstávají jako zkratky; druhé klepnutí na zaškrtnutý čip termín zruší).
- **Nabídka ukazuje všechny motorky**, na které zákazník smí (otevřená pobočka, bez vozíků, pravidlo dětské motorky, skupiny ŘP), s fotkou; limit 5 motorek zrušen. S termínem jen motorky volné v termínu (kontrola po dávkách, počítadlo s točícím se kroužkem, dokud se nedopočítá).
- **Cena „Tvoje cena od X Kč/den“** (se slevou hodnosti a přeškrtnutou ceníkovou), detail motorky bez termínu ukáže stejnou „od“ cenu.
- **„Volná dnes“ / „Volná od <datum>“** z `get_motos_availability_status` (jedno volání pro celou flotilu; chyba = bez odznaku); totéž na kartě Motorky a v hero detailu. S termínem, kdy je vše obsazené, jantarový odznak „Obsazená v termínu“.
- **Tlačítko „Vybrat termín“** otevře kalendář TÉ motorky (její obsazené dny a ceny, nic předvybraného); po výběru je volná motorka v nabídce první. Když je v termínu vše obsazené nebo zavřené, karta nikdy neukáže prázdné místo: dál fotky motorek, banner „V tyhle dny máme zavřeno“ (všechny pobočky mají v termínu `branch_closures`) nebo „V tyhle dny je vše obsazené“ a tlačítko „Vybrat jiný termín“. Selhaná kontrola = chybový stav se „Zkusit znovu“, ne „vše obsazené“.
- **Pořadí se míchá při každé návštěvě** (přepnutí záložky, návrat do appky po pauze); návrat zpět z detailu ukáže stejnou motorku.
- **Motorka z poslední výpůjčky se už nedává dopředu** — má jen štítek „Znovu“, kde ji míchání zrovna umístí.
- **Bez tlačítka profilu nahoře** (Domů i Motorky): zdvojovalo záložku Profil spodního menu, která dál ukazuje počet nepřečtených zpráv; logo má celou šířku.
- **Tři řádky na Domů** („Žádná aktivní rezervace“, „Spočítat přesnou cenu“, „Zaznamenat jízdu“) mají stejné tmavé neonové dlaždice 40 px; „Spočítat přesnou cenu“ bez termínu předvyplní kalkulačku jen motorkou.

### Spodní menu a ovládání
- **Aktivní záložka = plná neonová „pilulka“ se svatozáří** jako v původní appce (po přechodu 3× zvolna „dýchá“, pak klid; bez animací při omezení pohybu). Pilulka už nebere barvu hodnosti — **hodnost jen na prstenci Profilu** (aktivní Profil: prstenec na tmavém kotouči).
- **Motorka = Material ikona `two_wheeler`** (rounded) všude v novém vzhledu (menu, dlaždice, zástupné obrázky, jízdy, SOS).
- **Jedna položka na jedno švihnutí** ve všech přichytávacích seznamech (Domů, Motorky, Trasy, nabídka na Domů, pager detailu motorky), i rychlé švihnutí posune jen o jednu; platí i při omezení pohybu.
- **Šipka nahoru** (neonový kotouč 44 px „Nahoru“) se ukáže po opuštění první položky; na Domů vedle AI tlačítka, jinde v rohu; klepnutí = návrat nahoru.
- **Štítek pobočky vpravo nahoře na fotce motorky** (neonový čip „pobočka · samoobsluha / s obsluhou“, při nedostatku místa jen název a režim se přesune do štítků karty) — Domů, Motorky, hero detailu.

### Filtr motorek
- **Termín a pobočka nejsou filtr** — nepočítají se do počtu ani do „Zrušit vše“ (starý vzhled počítá jako dřív).
- **Klidný stav:** „Filtr motorek“, „Všechny motorky“, tlačítko „Filtrovat“. **Zapnuté filtry nahlas:** zelená karta „Filtry zapnuté (n)“, „Nevidíš všechny motorky“, každý filtr jako čip s ✕ (✕ zruší jen ten filtr), „Zrušit vše“; na Motorkách navíc zelený proužek nahoře. Prázdný výsledek: „Filtrům nic neodpovídá“ + „Zrušit filtry (n)“.
- **Nabídka na Domů se řídí filtry** (jen zobrazení; dostupnost, ceny a rezervace beze změny) a ukazuje pilulku „FILTRY ZAPNUTÉ (n)“; když filtrům nic neodpovídá, ukáže všechny motorky bez pilulky.

### Trasy
- **Jedna trasa na obrazovku** (celoobrazovková tmavá karta), Zpět vrátí na naposledy viděnou trasu.
- **Do strany = fotky téže trasy:** titulní fotka s malým náčrtem, velký náhled trasy po silnicích, pak fotky míst trasy; trasa bez fotek ukáže jen velký náhled.
- **Štítek „Okruh“ na kartě v seznamu není** (v detailu trasy zůstává).
- Nový panel nástrojů (Filtry, Řadit, Mapa tras) a hlasitá karta „Filtry zapnuté (n)“ jako u motorek; hledání, řazení, mapa, segmenty, záznam jízdy a detail beze změny funkce.

### Fotka a video motorky
- **Nejdřív fotka, po cca 5 s bez posouvání video — jen na Wi‑Fi** (ztlumené, nepřeruší hudbu zákazníka, v appce vždy jen jeden přehrávač). **Na mobilních datech zůstane fotka s tlačítkem „Pustit video“.** Platí pro kartu v seznamu i hero detailu.
- **Samostatná sekce „Video“ v detailu nového vzhledu je odstraněná** (žádný druhý přehrávač ani dvojí stahování). Starý vzhled beze změny.

### Kalendáře
- **Zavřené dny mají vlastní šedomodrý odstín** (nedají se vybrat; obsazené dny zůstávají šrafované a přeškrtnuté, kalendář filtru bez rezervací nemá v legendě „Obsazeno“): kalendář motorky na Domů i kalendář Motorek v novém vzhledu ukazují dny, kdy jsou zavřené všechny pobočky, kde zákazník může půjčit (s vybranou pobočkou jen ta), z `branch_closures`. Kalendář motorky má legendu a při volném dni až v pozdějším měsíci tlačítko „Přejít na <datum>“.

### Otevřené body (rozhodne majitel)
- „Dýchání“ svatozáře menu je omezené na 3 nádechy (nekonečná smyčka by stále běžela).
- Zvýraznění záložky v rezervačním formuláři/platbě a ořez fotky v hero platby nejsou součástí 5.0.1.
