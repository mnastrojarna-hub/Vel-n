-- =============================================================================
-- 20261015k_owner_texts_overlay_vraceni_pujcovna.sql
-- datová migrace (bez změn schématu): cizí jazyky stránky Vrácení v půjčovně.
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
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.en', '{intro}', 'full', 'b4ea93f527652c5a5400ecfcb4405f66', $t$Your rental ends just as easily as it began. Come to our address in Mezná near Pelhřimov at the agreed return time. Return the bike and the rented gear and you're done. Before returning, you don't need to wash or refuel it – just make sure the reserve light isn't on.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.de', '{intro}', 'full', '278fcb62e67abd574331c10b57852665', $t$Deine Miete endet genauso einfach, wie sie begonnen hat. Komm zur vereinbarten Rückgabezeit an unsere Adresse in Mezná bei Pelhřimov. Gib das Motorrad und die geliehene Ausrüstung zurück – fertig. Vor der Rückgabe musst du es weder waschen noch tanken – nur die Reserveleuchte sollte nicht leuchten.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.es', '{intro}', 'full', '5874b1d88e41adcf6c372968552c8a3b', $t$El alquiler termina tan fácil como empezó. Ven a la hora de devolución acordada a nuestra dirección en Mezná, cerca de Pelhřimov. Devuelve la moto y el equipamiento alquilado, y listo. Antes de devolverla no tienes que lavarla ni repostar; solo procura que no esté encendido el testigo de reserva.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.fr', '{intro}', 'full', '38aad9a755ed07d0a1ec2a51ca9685e9', $t$Ta location se termine aussi simplement qu'elle a commencé. Viens à l'heure de restitution convenue à notre adresse à Mezná, près de Pelhřimov. Rends la moto et l'équipement loué – et c'est terminé. Avant la restitution, pas besoin de laver la moto ni de faire le plein – veille seulement à ce que le voyant de réserve ne soit pas allumé.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.nl', '{intro}', 'full', 'ff21de6092e00cd7b4ede560a4e39e8e', $t$Je huur eindigt net zo eenvoudig als hij begon. Kom op de afgesproken inlevertijd naar ons adres in Mezná bij Pelhřimov. Lever de motor en de gehuurde uitrusting in en klaar. Voor het inleveren hoef je de motor niet te wassen of te tanken – zorg alleen dat het reservelampje niet brandt.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.pl', '{intro}', 'full', '88971854fac476a5e3cb23a05d59fe1a', $t$Wypożyczenie kończy się tak samo prosto, jak się zaczęło. Przyjedź o umówionej godzinie zwrotu pod nasz adres w Mezná koło Pelhřimova. Oddaj motocykl i wypożyczony sprzęt – i gotowe. Przed zwrotem nie musisz go myć ani tankować – byle nie świeciła się kontrolka rezerwy.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.en', '{faq,items,1,a}', 'full', '15e44a95bee06a749cf11193d199c347', $t$No. You don't need to refuel when returning the bike – just make sure the reserve light isn't on. It only needs to be returned washed at the self-service branch in Velké Němčice.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.de', '{faq,items,1,a}', 'full', '0e1908fabb2dc075e8a8a7b02392edae', $t$Nein. Tanken musst du bei der Rückgabe nicht – nur die Reserveleuchte sollte nicht leuchten. Gewaschen zurückbringen musst du das Motorrad nur an der Selbstbedienungsfiliale in Velké Němčice.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.es', '{faq,items,1,a}', 'full', '5853ebc5ce1da0a97675da28efcf6059', $t$No. Al devolverla no tienes que repostar; solo procura que no esté encendido el testigo de reserva. Solo en la sucursal de autoservicio de Velké Němčice hay que devolverla lavada.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.fr', '{faq,items,1,a}', 'full', '43dbf898116315f0330100390ea72e89', $t$Non. Au retour, pas besoin de faire le plein – veille seulement à ce que le voyant de réserve ne soit pas allumé. Tu ne dois rendre la moto lavée qu'à l'agence en libre-service de Velké Němčice.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.nl', '{faq,items,1,a}', 'full', '7cc5ce61226dfc83a5cbddd16390014d', $t$Nee. Tanken bij het terugbrengen is niet nodig – zorg alleen dat het reservelampje niet brandt. Alleen bij de zelfbedieningsvestiging in Velké Němčice lever je de motor gewassen in.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.pl', '{faq,items,1,a}', 'full', '986623dc9c2f4915a5ff31d38f6841b7', $t$Nie. Przy zwrocie nie musisz tankować – byle nie świeciła się kontrolka rezerwy. Umyty motocykl oddajesz tylko w samoobsługowym oddziale Velké Němčice.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.en', '{cta,text}', 'full', '48a3152737ceb1c7816d46aaf4e3a58a', $t$MotoGo24 is a motorcycle rental in the Vysočina region that runs 24/7, with an easy return any time on your rental day. No deposit, no refuelling (just make sure the reserve light isn't on) and, in Mezná, no washing either. Choose from our wide range of motorcycles (and scooters) and book online from the comfort of your home.$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.de', '{cta,text}', 'full', 'dda3a4dacc02904ab7f46a7881c4301f', $t$MotoGo24 ist ein Motorradverleih in der Region Vysočina mit Nonstop-Betrieb und einfacher Rückgabe jederzeit an deinem Miettag. Keine Kaution, kein Tanken (nur die Reserveleuchte sollte nicht leuchten) und in Mezná auch kein Waschen. Wähle aus unserem großen Angebot an Motorrädern (und Rollern) und buche bequem online von zu Hause aus.$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.es', '{cta,text}', 'full', '5cf535486ab19f15015e5988b14c5a15', $t$MotoGo24 es un alquiler de motos en la región de Vysočina que funciona 24/7, con una devolución sencilla en cualquier momento del día del alquiler. Sin fianza, sin repostar (solo procura que no esté encendido el testigo de reserva) y, en Mezná, también sin lavar. Elige entre nuestra amplia oferta de motos (y scooters) y reserva online desde la comodidad de tu casa.$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.fr', '{cta,text}', 'full', '20d5bdd5759e1d624c18479b98049983', $t$MotoGo24 est une location de motos dans la région de Vysočina qui fonctionne 24h/24, avec une restitution simple à toute heure le jour de ta location. Pas de caution, pas de plein à faire (veille seulement à ce que le voyant de réserve ne soit pas allumé) et, à Mezná, pas de lavage non plus. Choisis parmi notre large gamme de motos (et de scooters) et réserve en ligne depuis chez toi.$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.nl', '{cta,text}', 'full', 'e5edff6d8a4fe90f06b3ef467849dbeb', $t$MotoGo24 is een motorverhuur in de regio Vysočina die 24/7 werkt, met eenvoudig inleveren op elk moment van je huurdag. Geen borg, niet tanken (zorg alleen dat het reservelampje niet brandt) en in Mezná ook niet wassen. Kies uit ons ruime aanbod aan motoren (en scooters) en reserveer online vanuit je luie stoel.$t$),
    ('pages_overlay.jak_pujcit_vraceni_pujcovna.pl', '{cta,text}', 'full', '13569bd5f44e5ca5ef2418fa6e456dbc', $t$MotoGo24 to wypożyczalnia motocykli w regionie Vysočina działająca całodobowo, z prostym zwrotem o dowolnej porze w dniu wynajmu. Bez kaucji, bez tankowania (byle nie świeciła się kontrolka rezerwy), a w oddziale Mezná także bez mycia. Wybierz z naszej szerokiej oferty motocykli (i skuterów) i zarezerwuj online w zaciszu domu.$t$)
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
        RAISE NOTICE 'overlay_vraceni_pujcovna: % % PŘESKOČENO – text mezitím změněn: %', f.k, f.path, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'overlay_vraceni_pujcovna: app_settings upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
