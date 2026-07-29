# Analýza systematičnosti tras — 2026-07-28

> Detailní analýza **všech 1374 tras** (`routes.waypoints`) na lokální replice živé DB (repo migrace).
> Měřeno: délka čáry trasy v aktuálním pořadí bodů vs. délka při optimálním pořadí (exaktní TSP).
> Rozdíl = zbytečné vracení tam a zpátky / kličkování v kruzích.

## Cíl opravy (zadání)

**Okruhy bez vracení stejnou cestou** — každý bod průjezdný na cestě k dalšímu, návrat do startu
jinudy. Appka, Velín i exporty (Mapy.com / Google / Apple) posílají waypointy v pořadí pole do
routingu Mapy.cz, takže cyklické pořadí v datech řídí i přepočet navigace.

## Souhrn

| Metrika | Hodnota |
|---|---|
| Tras celkem | 1374 |
| Neoptimální pořadí bodů před opravou | 683 |
| **Výrazné kličkování před opravou** (>3 % a >3 km navíc) | 0 |
| Změněno migrací `20260728_routes_systematize_waypoints.sql` | 1095 |
| — z toho **uzavřeno do okruhu** (dřív končily „v poli", nyní návrat do startu jinou cestou; `route_type=loop`) | 1074 |
| — záměrné přejezdy A→B ponechány lineární (poslední bod „Cíl: X" ≠ start; např. Stelvio, Jadranská magistrála) | 51 |
| Přepočtené km/min (odchylka >15 %, vč. zpáteční části okruhů) | 944 |
| Přečíslované body zájmu (`route_pois.sort_order` dle nové čáry) | 5719 |
| Výrazné kličkování PO opravě | **0** |
| Idempotence (2. běh migrace) | 0 změn |

## Jak jsou trasy nově uspořádané

- start (1. bod) vždy pevný; u okruhů se body řadí jako **nejkratší uzavřený cyklus** start → … → start;
- u A→B přejezdů s explicitním cílem nejkratší cesta start → … → cíl;
- pořadí řeší exaktní Held-Karp DP (≤13 volných bodů, ~99 % tras), větší trasy NN + 2-opt + relokace;
- u změněných tras: `geometry=null` (čára se dopočte živě z nového pořadí), `mapy_url` přegenerován,
  km/min přepočteny (délka čáry × 1.35, ~42 km/h) při odchylce >15 %;
- komunitní trasy (`created_by is not null`) nedotčeny.

## Rozložení úspor před opravou (o kolik km trasa zbytečně kličkovala)

| Úspora | Počet tras |
|---|---|
| ≥ 50 km | 0 |
| 20–50 km | 0 |
| 10–20 km | 0 |
| 5–10 km | 0 |
| 3–5 km | 0 |

## TOP 60 nejhorších tras (před opravou)

| Úspora km | Čára před → po | Trasa |
|---|---|---|

*Čára = součet přímých úseků mezi waypointy (ekvirektangulárně, km). Skutečná silniční délka je cca 1.35×.*
*Opravu aplikuje idempotentní migrace na živou DB automaticky po merge do main (`deploy-sql.yml`).*
