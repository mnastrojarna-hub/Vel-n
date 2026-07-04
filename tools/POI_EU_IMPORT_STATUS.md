# Import bodů zájmu — Evropa (stav a návod na navázání)

> Pro případ přerušení session: tady je přesný stav a jak pokračovat.
> Branch: `claude/motogo-app-filter-fix-0snusn`

## Hotovo (commitnuto + nasazeno)

- [x] Tabulka `points_of_interest` + RPC `get_pois_catalog` + hodnocení (nasazeno v DB)
- [x] 5008 bodů CZ/SK/PL/AT v DB (curated-batch1/2 + wikidata-batch1..10)
- [x] Appka: filtr dle názvu, zdroj „Zajímavá místa", detail s galerií, kredit fotek ©
      (i v galerii detailu trasy), hodnocení katalogových bodů — čeká na build
- [x] Auto-deploy SQL: `.github/workflows/deploy-sql.yml` (baseline hotový;
      merge do main = nasazeno)
- [x] Edge fn `mirror-route-images` zrcadlí i `points_of_interest`
      (nasadí se merge → cron dojede fotky sám)

## Probíhá / zbývá

- [ ] **Evropa 15 000 bodů, 20 zemí** — generace z Wikidata. Příkaz
      (spustit znovu při přerušení; síť musí být povolená — Wikidata):

      python3 tools/generate_poi_batches.py \
        --countries DE,FR,IT,ES,GB,NL,BE,CH,SI,HR,HU,RO,RS,GR,PT,IE,DK,SE,NO,FI \
        --target 15000 --batch-size 1000 \
        --source-prefix wikidata-eu-batch \
        --file-prefix 20260704_poi_catalog_wikidata_eu_batch \
        --sort-offset 10000

      Výstup: `supabase/migrations/20260704_poi_catalog_wikidata_eu_batch{1..15}.sql`
- [ ] Validace výstupu (vzor: scratchpad skript ze session — parsování SQL
      literálů, JSON překladů, souřadnice v BBOX; dedupe proti curated není
      potřeba — jiné země). Kontrola konců souborů `);`.
- [ ] Commit dávek (klidně po částech, každá dávka je samostatný idempotentní
      soubor `delete where source=… + insert`).
- [ ] Merge do main → auto-deploy SQL dávek + edge fn.
- [ ] Po nasazení: kontrola `select source, count(*) from points_of_interest
      group by source;` — očekávané ~15 000 nových řádků wikidata-eu-batch*.
- [ ] Aktualizovat STATE_6 changelog (dávky EU nasazeny) a smazat tento soubor.

## Poznámky

- Dávky EU nekolidují s existujícími (jiné země i source tag).
- Generátor je idempotentní — opakované spuštění soubory prostě přepíše.
- Popisy: Wikidata popis + kategorická věta; názvy zemí s předložkami
  (COUNTRY_NAMES v generátoru) pro správnou gramatiku 8 jazyků.
