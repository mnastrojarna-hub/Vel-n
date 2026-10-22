-- =============================================================================
-- 20261015j_owner_texts_overlay_dokumenty.sql
-- datová migrace (bez změn schématu): cizí jazyky stránky Dokumenty (převzetí, vrácení, Palivo & čištění).
--
-- Pravidlo majitele (2026-10-11 doslova: „Mytí ani tankování není třeba na obslužné pobočce. Na
-- samoobsluze není potřeba tankovat. To důležité je pouze, aby motorka byla umytá a nesvítila
-- rezerva.“; upřesnění 2026-10-12: stav paliva neřešíme, plnou nádrž při převzetí nikdy neslibovat,
-- žádný poplatek za palivo):
--   → Vrácení kdekoli: tankovat netřeba, jen ať nesvítí rezerva. Umytá jen na samoobslužné pobočce
--     Velké Němčice u Brna; v Mezné u Pelhřimova i při vrácení jinde (odvoz z Mezné) bez mytí.
--
-- app_settings pages_overlay.<stránka>.<en|de|es|fr|nl|pl> = automatické překlady PHP stránek (Velín
-- „Přeložit vše naráz“); přebíjí lang/pages_<jazyk>.php a seznamy (faq, kroky, odrážky) bere CELÉ.
-- Každý list se nastaví PŘESNĚ na text z lang/pages_<jazyk>.php (jsonb_set jen toho listu).
-- uk overlay neexistuje (ukrajinština bere rovnou lang/pages_uk.php).
--
-- Bezpečnost: mění JEN text ve znění ověřeném proti živé DB (stav 2026-10-15); co mezitím
-- někdo upravil ve Velínu, se přeskočí s NOTICE. Idempotentní (2. běh nic nezmění). Bez
-- BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================

DO $$
DECLARE
  f record;
  cnt integer;
  v_cur text;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  -- klíč app_settings, cesta k textovému listu JSON, how + old:
  --   'full'   = celý živý list má otisk md5 = old (ověřený stav 2026-10-15) → nahradí se celý
  --   'phrase' = věta old (v listu jednou) se nahradí new, zbytek listu zůstává
  FOR f IN
    SELECT * FROM (VALUES
    ('pages_overlay.jak_pujcit_dokumenty.en', '{handover,items,0}', 'full', '777b090de276ce5d8e1169bd0f9c1dfe', $t$<strong>Pick-up</strong>&nbsp;is in Pelhřimov (Mezná 9) or at the self-service branch in Velké Němčice near Brno; from Mezná you can also use&nbsp;<a href="/jak-pujcit/pristaveni">delivery</a>.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.de', '{handover,items,0}', 'full', '5eebb553a9fada61b290a4281d7a0fae', $t$Die <strong>Abholung</strong>&nbsp;ist in Pelhřimov (Mezná 9) oder an der Selbstbedienungsfiliale in Velké Němčice bei Brno – von Mezná aus kannst du auch unsere&nbsp;<a href="/jak-pujcit/pristaveni">Lieferung</a> nutzen.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.es', '{handover,items,0}', 'full', 'f2faba1d59bbde61e71c8cd1b319f0a1', $t$La&nbsp;<strong>recogida</strong>&nbsp;es en Pelhřimov (Mezná 9) o en la sucursal de autoservicio de Velké Němčice, cerca de Brno; desde Mezná también puedes pedir la&nbsp;<a href="/jak-pujcit/pristaveni">entrega de la moto</a>.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.fr', '{handover,items,0}', 'full', 'bd6ccb7a61654cf0a387ec1aa75ae95f', $t$La <strong>prise en charge</strong>&nbsp;se fait à Pelhřimov (Mezná 9) ou à l'agence en libre-service de Velké Němčice, près de Brno – depuis Mezná, profite aussi de notre&nbsp;<a href="/jak-pujcit/pristaveni">livraison</a>.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.nl', '{handover,items,0}', 'full', '787d633d86d27274dcdce0024aa1d715', $t$Het&nbsp;<strong>ophalen</strong>&nbsp;gebeurt in Pelhřimov (Mezná 9) of bij de zelfbedieningsvestiging in Velké Němčice bij Brno; vanuit Mezná kun je ook&nbsp;<a href="/jak-pujcit/pristaveni">bezorging</a> gebruiken.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.pl', '{handover,items,0}', 'full', 'ffeac06b7d9d33dd3c8ac50ac3dd1c0c', $t$<strong>Odbiór</strong>&nbsp;odbywa się w Pelhřimovie (Mezná 9) lub w samoobsługowym oddziale Velké Němčice koło Brna; z oddziału Mezná możesz też skorzystać z&nbsp;<a href="/jak-pujcit/pristaveni">podstawienia</a>.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.en', '{handover,items,2}', 'full', '641d63dbdba5d63b0516a84207bcec69', $t$<strong>Return</strong>&nbsp;any time on the last day of your rental (even at midnight). No need to refuel – just make sure the reserve light isn't on; the bike only needs to be returned washed at the self-service branch in Velké Němčice.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.de', '{handover,items,2}', 'full', 'cf051d86de589c7020633839c38d5132', $t$Die <strong>Rückgabe</strong>&nbsp;ist jederzeit am letzten Miettag möglich (auch um Mitternacht). Tanken musst du nicht – nur die Reserveleuchte sollte nicht leuchten; gewaschen zurückgeben musst du das Motorrad nur an der Selbstbedienungsfiliale in Velké Němčice.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.es', '{handover,items,2}', 'full', '7c360279d2804a8cac15349e3cfdb957', $t$<strong>Devolución</strong>&nbsp;en cualquier momento del último día del alquiler (incluso a medianoche). No hace falta repostar; solo procura que no esté encendido el testigo de reserva. Solo hay que devolver la moto lavada en la sucursal de autoservicio de Velké Němčice.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.fr', '{handover,items,2}', 'full', '2c8769ad707497ac499dd33035ab11b1', $t$La <strong>restitution</strong>&nbsp;est possible à toute heure le dernier jour de la location (même à minuit). Pas besoin de faire le plein – veille seulement à ce que le voyant de réserve ne soit pas allumé ; la moto ne doit être rendue lavée qu'à l'agence en libre-service de Velké Němčice.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.nl', '{handover,items,2}', 'full', 'd77f1f7b254b7aea58676513871c28c8', $t$<strong>Teruggave</strong>&nbsp;op elk moment van de laatste huurdag (ook om middernacht). Tanken is niet nodig – zorg alleen dat het reservelampje niet brandt; alleen bij de zelfbedieningsvestiging in Velké Němčice moet de motor gewassen worden ingeleverd.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.pl', '{handover,items,2}', 'full', '4ea2552938b304b326b2bdaf530ae19b', $t$<strong>Zwrot</strong>&nbsp;o dowolnej porze w ostatnim dniu wynajmu (nawet o północy). Tankować nie trzeba – byle nie świeciła się kontrolka rezerwy; umyty motocykl trzeba oddać tylko w samoobsługowym oddziale Velké Němčice.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.en', '{payments,rows,2,1}', 'full', '13ed47bc398ee6049baa33bf9bc76345', $t$Return without having to refuel – just make sure the reserve light isn't on. The bike only needs to be returned washed at the self-service branch in Velké Němčice. Excessive dirt is dealt with individually.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.de', '{payments,rows,2,1}', 'full', '3b01f1d57840f78942e0463e0926b049', $t$Rückgabe ohne Tankpflicht – nur die Reserveleuchte sollte nicht leuchten. Gewaschen zurückgeben musst du das Motorrad nur an der Selbstbedienungsfiliale in Velké Němčice. Starke Verschmutzung klären wir individuell.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.es', '{payments,rows,2,1}', 'full', '6c9c04e03258bd7f110c7b30f124cfa5', $t$Devolución sin obligación de repostar; solo procura que no esté encendido el testigo de reserva. Solo hay que devolver la moto lavada en la sucursal de autoservicio de Velké Němčice. La suciedad excesiva se resuelve de forma individual.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.fr', '{payments,rows,2,1}', 'full', '2a02d75d1d369e4ed2a10457592ffbde', $t$Restitution sans obligation de faire le plein – veille seulement à ce que le voyant de réserve ne soit pas allumé. La moto ne doit être rendue lavée qu'à l'agence en libre-service de Velké Němčice. Une saleté excessive est réglée au cas par cas.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.nl', '{payments,rows,2,1}', 'full', '8735437c381340e4f9a2a91d9baf2ea6', $t$Terugbrengen zonder tankplicht – zorg alleen dat het reservelampje niet brandt. Alleen bij de zelfbedieningsvestiging in Velké Němčice moet de motor gewassen worden ingeleverd. Overmatig vuil wordt individueel afgehandeld.$t$),
    ('pages_overlay.jak_pujcit_dokumenty.pl', '{payments,rows,2,1}', 'full', '632ad9e02ddf882888c80407b08e037b', $t$Zwrot bez obowiązku tankowania – byle nie świeciła się kontrolka rezerwy. Umyty motocykl trzeba oddać tylko w samoobsługowym oddziale Velké Němčice. Nadmierne zabrudzenie rozpatrujemy indywidualnie.$t$)
    ) AS x(k, path, how, old, new)
  LOOP
    UPDATE public.app_settings
       SET value = jsonb_set(value, f.path::text[], to_jsonb(CASE WHEN f.how = 'phrase'
                     THEN replace(value #>> f.path::text[], f.old, f.new) ELSE f.new END), false),
           updated_at = now()
     WHERE key = f.k AND jsonb_typeof(value) = 'object'
       AND jsonb_typeof(value #> f.path::text[]) = 'string'
       AND CASE WHEN f.how = 'phrase' THEN strpos(value #>> f.path::text[], f.old) > 0
                                       AND strpos(value #>> f.path::text[], f.new) = 0
                ELSE md5(value #>> f.path::text[]) = f.old END;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT value #>> f.path::text[] INTO v_cur FROM public.app_settings WHERE key = f.k;
      IF (CASE WHEN f.how = 'phrase' THEN strpos(coalesce(v_cur, ''), f.new) > 0 ELSE v_cur = f.new END) THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'overlay_dokumenty: % % PŘESKOČENO – text mezitím změněn: %', f.k, f.path, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'overlay_dokumenty: app_settings upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
