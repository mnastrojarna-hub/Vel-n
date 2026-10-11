# Handoff 2026-10-11 → pokračování po resetu týdenního limitu

> Pracovní podklady Clauda pro větev `claude/moto-go-mobile-conversion-gqg5qo`.
> **Celou složku `.claude/handoff/` smazat před mergem do `main`.**
> **Větev do té doby NEMERGOVAT.** Commity `e8b63003…00df3f5d` jsou WIP a nejsou ověřené.

## Stav k 11. 10. 2026 večer

**Už je v `main` a živě** (PR #2199, mergnul majitel):
- SQL M1 `20261011_i18n_customer_language.sql` (deploy-sql run #147 zelený)
- edge funkce (run #248 zelený)
- první WIP verze banneru na webu (`layout-banner.php`)
- PHP web se nasazuje ručně ZIPem, takže na webu zatím není.

**Na větvi navíc (WIP, neověřeno):**

Odpovědi majitele:
- banner z Velínu nahoře na webu (+ překlady, Velín editor, appka)
- pravidlo vracení na webu, v AI, v e-mailu a v appce
- FAQ zmiňuje App Store
- krok 3 Domů obsahuje obě pobočky

Tlačítko „Správa rezervace“ v hlavičce webu.

Dílčí opravy z přerušeného workflow `owner-answers-finish`, výstup v `reports/repo-fixes.md`:
- `webTextsPobocky.js`, `.well-known/agent.json`, `blog_fallback.php`, `branch-facts.ts`
- STATE_5 + STATE_6 (E)
- `handover.items.0` „Převzetí…“ doplněno o Velké Němčice v `lang/pages_*.php` + `dokumenty-content-2.php` + `master_cs.ts`

**Pravidlo majitele** (doslova): „Mytí ani tankování není třeba na obslužné pobočce. Na samoobsluze není potřeba tankovat. To důležité je pouze, aby motorka byla umytá a nesvítila rezerva.“
- Mezná (i vrácení jinde): bez mytí, bez tankování.
- Velké Němčice: plná nádrž netřeba, ale musí být umytá a nesmí svítit rezerva.

**Návrh appky (plátno):** https://claude.ai/artifact/MgsmxxUXfJkqW3M4xM1GuA
- Obsahuje verzi 1: Domů, Motorky (fotka přes celý displej), Detail + kalkulačka, Rezervace, Správa rezervace.
- Kopie ploch je v `appdesign/`.
- Majitel je s v1 spokojen. Zpětná vazba pro v2 je v `workflows/app-design-v2-rank.js`, konstanta `OWNER`:
  1. rank řídí záři a vzhled tlačítek a Domů
  2. AI jako plovoucí tlačítko vpravo dole
  3. záložka PROFIL, popisky v 8 jazycích bez překrývání
  4. Domů ve stylu „Sultán“: SOS + moje jízdy (s MotoGo i soukromé), trasy, zážitky
  5. katalog nechat
  6. detail zpřehlednit
  7. zbytek nechat
  8. tlačítko REZERVOVAT v detailu výraznější

## Co zbývá (pořadí)

### A. Dokončit odpovědi majitele (workflow `workflows/owner-answers-finish.js`)
Přerušeno ve fázi Build. Hotové je jen `repo-fixes`.

Workflow udělá:
1. finální SQL migrace do `S/sql/final/` (NE do repa)
2. opravy v repu
3. přetékání mobilního webu na 320 px (uk/de hlavička se `header-editrez`, `.lp-cat`, tabulka poboček, v1 `.gbox`)
4. 3× kontrolu úplnosti
5. ověření a opravy

Vstupy:
- `sql/*.sql` (drafty)
- `notes/owner-dbsql.md` (popis, VOP návrhy, otevřené otázky)
- `dbsql-tools/` (generátor: `spec.py`, `gen.py`, `template.sql`, `leafdiff.py`)

Známé mezery v SQL:
- overlay pl krok 11 „oddaj go umytego“
- typo „stažein“?
- `web.pobocky.branches.*.steps` (draft `owner_return_rule_pobocky_steps.sql`)
- e-mailové šablony (draft `owner_return_rule_email_templates.sql`)
- `handover.items.0` v CMS + overlay (PHP už hotové)

Potom:
- SQL dát majiteli **jako text** ke schválení (CLAUDE.md pravidlo 3)
- po schválení commitnout do `supabase/migrations/` (názvy `20261011g…` a dál, musí řadit za nejnovější soubor)
- aktualizovat STATE_6

### B. Návrh appky v2 (workflow `workflows/app-design-v2-rank.js`)
Fáze:
1. Understand (rank / osobní data / navigace + měření popisků v 8 jazycích)
2. 3 koncepty Domů + 2 porotci + syntéza `DESIGN_V2.md` a sdílené snippety
3. build ploch: Main, MotoDetail, ostatní, nová RankStyly
4. ověření a opravy

Potom publikovat na plátno:
- Volání: `Artifact publish`, `url` = odkaz výše, `root` = `S/appdesign`, `file_path` = `project/canvas.json`, `files` = `project/*.dc.html`.
- Do `canvas.json` přidat desku `RankStyly.dc.html` (x=2350) a upravit výšky.
- Formát `.dc.html` je popsaný v `DCRULES` ve skriptu.
- Kontrola: `dclint/lint.py` + `dclint/fuzz.js`.

### C. Závěr
- Ne-WIP commit (zprávy bez „nemergovat“), push.
- ZIP webu pro ruční nasazení.
- Shrnutí majiteli.
- Smazat `.claude/handoff/`.
- Vytvořit PR, jen pokud o to majitel požádá.

## Jak obnovit prostředí (nová session / nový kontejner)

1. `S` = scratchpad nové session. Zkopíruj z handoffu:

   | Z handoffu | Kam |
   |---|---|
   | `sql/*` | `S/sql/` |
   | `notes/*` | `S/notes/` |
   | `dbsql-tools/*` | `S/dbsql/tools/` |
   | `appdesign/appdesign_spec.md` | `S/appdesign_spec.md` |
   | `appdesign/*.dc.html` + `canvas.json` | `S/appdesign/project/` |
   | `dclint/*` | `S/dclint/` |

2. Ve skriptech `workflows/*.js` přepiš konstantu `const S = '…'` na novou cestu scratchpadu.
3. Pomocné nástroje, které agenti očekávají:
   - `S/q.sh` (anon REST čtení: `curl "$URL/rest/v1/$1" -H "apikey: $K" -H "Authorization: Bearer $K"`; anon klíč je v konfiguraci webu `motogo-web-php`, necommitovat jinam)
   - `S/anon.key`
   - `S/router.php` (PHP dev router s `$root` = `/home/user/Vel-n/motogo-web-php`)
   - Flutter SDK do `S/sdk/flutter`
   - Deno do `S/denobin` (`DENO_DIR=S/denocache`)
   - kopie Velínu pro build do `S/velin-build` (`npm ci`)
   - Postgres 16: clustery jen pod `/var/tmp/...`
   - Playwright Chromium je předinstalovaný.
4. Spuštění: `Workflow({scriptPath: "<cesta ke zkopírovanému skriptu>"})`.
   - Nejdřív A, potom B. Mohou běžet i souběžně, sahají na jiné soubory.
   - Před spuštěním ověř limit sondou: workflow s jedním agentem „Reply ok“.
5. Na začátku session podle CLAUDE.md:
   - přečíst STATE_1–6
   - zkontrolovat issues `sql-deploy-failed` / `backup-failed`
   - `git fetch` a `git merge origin/main`

## Otevřené otázky pro majitele
1. Mezná: nevadí ani svítící rezerva? (VOP čl. 5 l) a smlouva dnes rezervu vyžadují všude.)
2. Změnit VOP čl. 5 l) a smlouvu podle pravidla? Návrhy textu jsou v `notes/owner-dbsql.md`.
   - Jde o závazné dokumenty.
   - Změna zneplatní překlady, dokud se ve Velínu znovu nepřeloží.
3. Poplatek, když se na samoobsluze motorka vrátí špinavá nebo se svítící rezervou?
4. Nosná řádka banneru `cms_variables` `app.header_banner.text`: ponechat? Banner na webu přilepit při scrollu?
5. Návrh appky:
   - fotka s rozmazaným pozadím vs. ořez
   - tykání v celé appce
   - vozík v appce zdarma vs. na webu 400 Kč/den
   - velikosti bot 36–46 vs. 39–48
   - obsah výbavy spolujezdce (vesta vs. bunda + kalhoty)
   - zavedení za přepínačem `app_v2_ui`
6. BMW R 1200 GS Adventure: nádrž v parametrech 32 l vs. v popisu 30 l (sjednotit ve Velínu).

## Akce majitele (mimo kód)
- Velín → „Přeložit chybějící a zastaralé“ (po M1, překlady smluv).
- Velín → „Uložit banner“ jednou, aby vznikly překlady banneru (pokud je nedoplní SQL z bodu A).
- Právní kontrola, rollout kiosku 1.2.12, buildy appek.
