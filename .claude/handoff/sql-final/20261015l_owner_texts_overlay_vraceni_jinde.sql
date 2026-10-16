-- =============================================================================
-- 20261015l_owner_texts_overlay_vraceni_jinde.sql
-- datová migrace (bez změn schématu): cizí jazyky stránky Vrácení jinde (odvoz jen u motorek z Mezné).
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
    ('pages_overlay.jak_pujcit_vraceni_jinde.en', '{intro}', 'full', 'f1a54632ced3d7515c1e6eeb7807f15a', $t$Don't want to come back to our branch in Pelhřimov? No problem. We'll collect the bike anywhere in the Czech Republic – at the time you chose in the booking form. You hand it over, we load it up. Simple and hassle-free. Collection is available for bikes from our staffed branch in Mezná; bikes from the self-service branch in Velké Němčice are returned only at that branch.$t$),
    ('pages_overlay.jak_pujcit_vraceni_jinde.de', '{intro}', 'full', '91b9f82d0786f9fb82c347a158485f25', $t$Du willst nicht zurück in unsere Filiale nach Pelhřimov? Kein Problem. Wir holen das Motorrad überall in Tschechien ab – zu der Zeit, die du im Buchungsformular gewählt hast. Du übergibst, wir laden auf. Einfach und unkompliziert. Die Abholung gibt es für Motorräder aus unserer Filiale mit Personal in Mezná; Motorräder der Selbstbedienungsfiliale in Velké Němčice gibst du nur direkt dort zurück.$t$),
    ('pages_overlay.jak_pujcit_vraceni_jinde.es', '{intro}', 'full', 'f11e4c066f482909511e1cc8fdc0c31e', $t$¿No quieres volver a nuestra sucursal de Pelhřimov? Ningún problema. Vamos a recoger la moto a cualquier lugar de la República Checa, a la hora que elegiste en el formulario de reserva. Tú nos la entregas y nosotros la cargamos. Así de fácil y sin complicaciones. La recogida está disponible para las motos de nuestra sucursal con personal de Mezná; las motos de la sucursal de autoservicio de Velké Němčice solo se devuelven en esa sucursal.$t$),
    ('pages_overlay.jak_pujcit_vraceni_jinde.fr', '{intro}', 'full', '6f29e10a7d032bddcc61e5c66ef72f1e', $t$Tu ne veux pas revenir à notre agence de Pelhřimov ? Aucun problème. Nous venons chercher la moto partout en Tchéquie – à l'heure que tu as choisie dans le formulaire de réservation. Tu nous la remets, nous la chargeons. Simple et sans complications. L'enlèvement est proposé pour les motos de notre agence avec personnel de Mezná ; les motos de l'agence en libre-service de Velké Němčice se rendent uniquement sur place.$t$),
    ('pages_overlay.jak_pujcit_vraceni_jinde.nl', '{intro}', 'full', 'bcae0db6c82ce07ab691a5fc2ffd44c1', $t$Wil je niet terug naar onze vestiging in Pelhřimov? Geen probleem. We halen de motor overal in Tsjechië op – op het tijdstip dat je in het reserveringsformulier hebt gekozen. Jij geeft hem af, wij laden hem in. Eenvoudig en zonder gedoe. Ophalen is mogelijk voor motoren van onze bemande vestiging in Mezná; motoren van de zelfbedieningsvestiging in Velké Němčice lever je alleen daar in.$t$),
    ('pages_overlay.jak_pujcit_vraceni_jinde.pl', '{intro}', 'full', '426e6657cbeb509ce203513526ebc268', $t$Nie chcesz wracać do naszego oddziału w Pelhřimovie? Żaden problem. Odbierzemy motocykl z dowolnego miejsca w Czechach – o godzinie, którą wybrałeś w formularzu rezerwacji. Ty przekazujesz, my ładujemy. Prosto i bez komplikacji. Odbiór spod adresu oferujemy dla motocykli z oddziału z obsługą w Mezná; motocykle z samoobsługowego oddziału Velké Němčice zwraca się tylko bezpośrednio w tym oddziale.$t$),
    ('pages_overlay.jak_pujcit_vraceni_jinde.en', '{faq,items,1,a}', 'full', '425e89d1decfb39d66391f2251e1faa3', $t$No. When you return the bike elsewhere, you don't need to wash or refuel it – just make sure the reserve light isn't on.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_jinde.de', '{faq,items,1,a}', 'full', '930f4f0e6b59fc1cd2fccebdac9719bf', $t$Nein. Bei der Rückgabe an einem anderen Ort musst du weder waschen noch tanken – nur die Reserveleuchte sollte nicht leuchten.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_jinde.es', '{faq,items,1,a}', 'full', '6db8d43ca5bf8a6da80ec40d4e4e4cf1', $t$No. Si la devuelves en otro lugar, no tienes que lavarla ni repostar; solo procura que no esté encendido el testigo de reserva.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_jinde.fr', '{faq,items,1,a}', 'full', 'e33777ba3ef02398ff65fef9034485e3', $t$Non. Si tu la rends ailleurs, tu n'as ni à la laver ni à faire le plein – veille seulement à ce que le voyant de réserve ne soit pas allumé.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_jinde.nl', '{faq,items,1,a}', 'full', '03e7153f4be7d73472709e177bcd00b3', $t$Nee. Bij teruggave op een andere plek hoef je niet te wassen of te tanken – zorg alleen dat het reservelampje niet brandt.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_vraceni_jinde.pl', '{faq,items,1,a}', 'full', 'a1fa788f4354b654a366d37338425a57', $t$Nie. Przy zwrocie w innym miejscu nie musisz go myć ani tankować – byle nie świeciła się kontrolka rezerwy.&nbsp;$t$)
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
        RAISE NOTICE 'overlay_vraceni_jinde: % % PŘESKOČENO – text mezitím změněn: %', f.k, f.path, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'overlay_vraceni_jinde: app_settings upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
