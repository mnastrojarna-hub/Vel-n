# Analýza systematičnosti tras — 2026-07-28

> Detailní analýza **všech 1374 tras** (`routes.waypoints`) na lokální replice živé DB (repo migrace).
> Měřeno: délka čáry trasy v aktuálním pořadí bodů vs. délka při optimálním pořadí (pevný start;
> pevný cíl u okruhů a bodů s labelem Cíl; exaktní TSP). Rozdíl = zbytečné vracení tam a zpátky.

## Souhrn

| Metrika | Hodnota |
|---|---|
| Tras celkem | 1374 |
| Neoptimální pořadí bodů (jakékoli zlepšení) | 683 |
| **Výrazné kličkování** (>3 % a >3 km navíc) | 401 |
| Přeuspořádáno migrací `20260728_routes_systematize_waypoints.sql` | 709 |
| Přepočtené km/min (odchylka >15 %) | 74 |
| Přečíslované body zájmu (`route_pois.sort_order`) | 3002 |
| Výrazné kličkování PO opravě | **0** |

## Rozložení úspor (o kolik km trasa zbytečně kličkovala)

| Úspora | Počet tras |
|---|---|
| ≥ 50 km | 3 |
| 20–50 km | 73 |
| 10–20 km | 134 |
| 5–10 km | 135 |
| 3–5 km | 56 |

## TOP 60 nejhorších tras (před opravou)

| Úspora km | Čára před → po | Trasa |
|---|---|---|
| 123 | 836 → 713 km | Finské Laponsko |
| 89 | 292 → 203 km | Moldavsko – Orheiul Vechi a Cricova |
| 59 | 258 → 200 km | Vyhlídková jízda: Bolfánek a okolí |
| 46 | 218 → 173 km | Plzeňsko, Český les a Chodsko |
| 44 | 166 → 123 km | Vojenská historie: Museum of the Macedonian Struggle a okolí |
| 43 | 144 → 101 km | Za historií: Bouzov a okolí |
| 43 | 242 → 199 km | Plitvická jezera a Lika |
| 38 | 243 → 205 km | Vyhlídková jízda: Rozhledna Jarník a okolí |
| 38 | 213 → 175 km | Vyhlídková jízda: Rozhledna Zvičina a okolí |
| 36 | 239 → 203 km | Přírodní krásy: Svrčinník a okolí |
| 36 | 188 → 152 km | Vodní krásy: Wolayer See a okolí |
| 36 | 173 → 138 km | Vyhlídková jízda: Cvilín a okolí |
| 35 | 142 → 107 km | To nejlepší v okolí: Rabí |
| 35 | 180 → 145 km | Vyhlídková jízda: Stezka korunami stromů a okolí |
| 33 | 151 → 118 km | Technika a průmysl: Krzemionki a okolí |
| 33 | 181 → 148 km | Za historií: Landštejn a okolí |
| 33 | 164 → 131 km | Lago di Como a průsmyk Splügen |
| 32 | 118 → 86 km | Přírodní krásy: Koněpruské jeskyně a okolí |
| 32 | 157 → 125 km | Přírodní krásy: Hruboskalsko a okolí |
| 32 | 191 → 159 km | Za historií: Uhrovecký hrad a okolí |
| 32 | 145 → 112 km | To nejlepší v okolí: Budatínský hrad |
| 32 | 221 → 189 km | Přírodní krásy: Šarafiový vodopád a okolí |
| 31 | 137 → 106 km | Za historií: Hrad Czocha a okolí |
| 31 | 132 → 101 km | To nejlepší v okolí: Wolayer See |
| 31 | 192 → 161 km | Vodní krásy: Jeziorak a okolí |
| 31 | 149 → 118 km | Za historií: Kostolec a okolí |
| 30 | 172 → 142 km | Přírodní krásy: Čertova pec a okolí |
| 28 | 171 → 142 km | Za historií: Katedrála Nanebevzetí Panny Marie v Gurku a okolí |
| 28 | 161 → 133 km | Přírodní krásy: Národní park Vápencové Alpy a okolí |
| 28 | 144 → 116 km | Za historií: Šášovský hrad a okolí |
| 28 | 210 → 183 km | Vyhlídková jízda: Královka a okolí |
| 27 | 207 → 180 km | Přírodní krásy: Chýnovská jeskyně a okolí |
| 27 | 164 → 138 km | Za historií: Przedbórz Synagogue a okolí |
| 26 | 173 → 147 km | Vojenská historie: Vojenský památník Asiago a okolí |
| 26 | 179 → 153 km | Vodní krásy: přehrada Seč a okolí |
| 26 | 118 → 92 km | Za historií: Vyšebrodský klášter a okolí |
| 26 | 130 → 105 km | Vojenská historie: Oise-Aisne American Cemetery and Memorial a okolí |
| 26 | 92 → 66 km | To nejlepší v okolí: Kufsteinská pevnost |
| 25 | 190 → 165 km | Přírodní krásy: Kozí vrch a okolí |
| 25 | 98 → 73 km | Vodní krásy: vodní nádrž České údolí a okolí |
| 25 | 122 → 97 km | To nejlepší v okolí: Milada |
| 25 | 127 → 102 km | To nejlepší v okolí: Čachtický hrad |
| 25 | 136 → 111 km | Za historií: Beckov a okolí |
| 25 | 134 → 109 km | Vodní krásy: Vodní nádrž Křimov a okolí |
| 24 | 106 → 82 km | Technika a průmysl: Maritime Museum a okolí |
| 24 | 164 → 139 km | Za historií: Orlík a okolí |
| 24 | 171 → 147 km | Vyhlídková jízda: Drägerovka a okolí |
| 24 | 163 → 139 km | Rychlost a legendy: Misano World Circuit Marco Simoncelli a okolí |
| 24 | 180 → 157 km | Vodní krásy: Brněnská přehrada a okolí |
| 23 | 153 → 130 km | Za historií: Niepokalanów a okolí |
| 23 | 137 → 114 km | Vyhlídková jízda: Rozhledna Diana a okolí |
| 23 | 63 → 41 km | To nejlepší v okolí: Hrubý Rohozec |
| 23 | 164 → 141 km | Vojenská historie: Sant'Anna di Stazzema a okolí |
| 23 | 135 → 112 km | Za historií: Čachtický hrad a okolí |
| 23 | 218 → 195 km | Vyhlídková jízda: Rozhledna Bára a okolí |
| 23 | 99 → 77 km | Malá Fatra a Terchová |
| 22 | 117 → 95 km | To nejlepší v okolí: Národní park Vápencové Alpy |
| 22 | 117 → 94 km | To nejlepší v okolí: Hasištejn |
| 22 | 144 → 121 km | Za historií: Tolštejn a okolí |
| 22 | 128 → 106 km | Vojenská historie: Muzeum Marynarki Wojennej a okolí |

*Čára = součet přímých úseků mezi waypointy (ekvirektangulárně, km). Skutečná silniční délka je cca 1.35×.*
*Opravu aplikuje idempotentní migrace na živou DB automaticky po merge do main (`deploy-sql.yml`).*
