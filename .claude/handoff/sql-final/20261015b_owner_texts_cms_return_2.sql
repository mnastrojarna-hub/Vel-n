-- =============================================================================
-- 20261015b_owner_texts_cms_return_2.sql
-- datová migrace (bez změn schématu): Velín CMS – pravidlo vrácení na stránkách Jak si půjčit (= PHP texty webu) (část 2/2).
--
-- Pravidlo majitele (2026-10-11 doslova: „Mytí ani tankování není třeba na obslužné pobočce. Na
-- samoobsluze není potřeba tankovat. To důležité je pouze, aby motorka byla umytá a nesvítila
-- rezerva.“; upřesnění 2026-10-12: stav paliva neřešíme, plnou nádrž při převzetí nikdy neslibovat,
-- žádný poplatek za palivo):
--   → Vrácení kdekoli: tankovat netřeba, jen ať nesvítí rezerva. Umytá jen na samoobslužné pobočce
--     Velké Němčice u Brna; v Mezné u Pelhřimova i při vrácení jinde (odvoz z Mezné) bez mytí.
--
-- cms_variables (Velín → Texty webu) mají na webu přednost před PHP i lang soubory. Nastavují se
-- PŘESNĚ na texty z data/*-content-*.php (cs) a lang/pages_<jazyk>.php (překlady):
--   web.jak_pujcit_dokumenty.payments.rows.2.1, web.jak_pujcit_postup.process.steps.11.text,
--   web.jak_pujcit_vraceni_pujcovna.intro, web.jak_pujcit_vraceni_pujcovna.cta.text
-- Vaše červencové úpravy (Mezná u Pelhřimova, vrácení výbavy, nabídka i skútrů) jsou zachované –
-- PHP texty byly podle nich upraveny ve všech 8 jazycích.
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
  v_cs text;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  -- x: klíč, jazyk ('cs' = sloupec value, jinak translations.<jazyk>.value), how + old:
  --      'full'   = celý živý text má otisk md5 = old (ověřený stav 2026-10-15) → nahradí se celý
  --      'phrase' = věta old (v živém textu jednou) se nahradí new, zbytek textu zůstává
  --      'fill'   = překlad chybí → doplní se
  -- g: brána – překlad se mění jen když česká hodnota má otisk md5 = gate (nové / ověřené české znění)
  FOR f IN
    SELECT x.*, g.gate FROM (VALUES
    ('web.jak_pujcit_vraceni_pujcovna.intro', 'fr', 'full', '87f465846fe7754e0fba393996747b9d', $t$Ta location se termine aussi simplement qu'elle a commencé. Viens à l'heure de restitution convenue à notre adresse à Mezná, près de Pelhřimov. Rends la moto et l'équipement loué – et c'est terminé. Avant la restitution, pas besoin de laver la moto ni de faire le plein – veille seulement à ce que le voyant de réserve ne soit pas allumé.&nbsp;$t$),
    ('web.jak_pujcit_vraceni_pujcovna.intro', 'nl', 'full', '0194bce6a4daa125e1716c735a96f4a6', $t$Je huur eindigt net zo eenvoudig als hij begon. Kom op de afgesproken inlevertijd naar ons adres in Mezná bij Pelhřimov. Lever de motor en de gehuurde uitrusting in en klaar. Voor het inleveren hoef je de motor niet te wassen of te tanken – zorg alleen dat het reservelampje niet brandt.&nbsp;$t$),
    ('web.jak_pujcit_vraceni_pujcovna.intro', 'pl', 'full', 'ea4ab4e5560780e7c40961e9ebc965dd', $t$Wypożyczenie kończy się tak samo prosto, jak się zaczęło. Przyjedź o umówionej godzinie zwrotu pod nasz adres w Mezná koło Pelhřimova. Oddaj motocykl i wypożyczony sprzęt – i gotowe. Przed zwrotem nie musisz go myć ani tankować – byle nie świeciła się kontrolka rezerwy.&nbsp;$t$),
    ('web.jak_pujcit_vraceni_pujcovna.intro', 'uk', 'full', 'c77e4212409cb9b9ac569e4a071b0e67', $t$Оренда закінчується так само просто, як і почалася. Приїдь у домовлений час повернення за нашою адресою в Mezná біля Пельгржимова. Поверни мотоцикл та орендоване екіпірування – і готово. Перед поверненням мити чи заправляти його не потрібно – лише стеж, щоб не світився індикатор резерву.&nbsp;$t$),
    ('web.jak_pujcit_vraceni_pujcovna.cta.text', 'cs', 'full', '07906eb8c2a7181c6a3a038e0134611a', $t$MotoGo24 je půjčovna motorek na Vysočině s nonstop provozem a jednoduchým vrácením motorky kdykoliv v den výpůjčky. Bez kauce, bez tankování (jen ať nesvítí rezerva), v Mezné i bez mytí. Vyber si z naší široké nabídky motorek (a skútrů) a rezervuj online z pohodlí domova.$t$),
    ('web.jak_pujcit_vraceni_pujcovna.cta.text', 'de', 'full', '1389cfd4d346edc59c21ae767993b046', $t$MotoGo24 ist ein Motorradverleih in der Region Vysočina mit Nonstop-Betrieb und einfacher Rückgabe jederzeit an deinem Miettag. Keine Kaution, kein Tanken (nur die Reserveleuchte sollte nicht leuchten) und in Mezná auch kein Waschen. Wähle aus unserem großen Angebot an Motorrädern (und Rollern) und buche bequem online von zu Hause aus.$t$),
    ('web.jak_pujcit_vraceni_pujcovna.cta.text', 'en', 'full', 'ef2831097fbe80ff91c53247584c03b4', $t$MotoGo24 is a motorcycle rental in the Vysočina region that runs 24/7, with an easy return any time on your rental day. No deposit, no refuelling (just make sure the reserve light isn't on) and, in Mezná, no washing either. Choose from our wide range of motorcycles (and scooters) and book online from the comfort of your home.$t$),
    ('web.jak_pujcit_vraceni_pujcovna.cta.text', 'es', 'full', '736f0aa8ee4f9dd6169bd195640f54e4', $t$MotoGo24 es un alquiler de motos en la región de Vysočina que funciona 24/7, con una devolución sencilla en cualquier momento del día del alquiler. Sin fianza, sin repostar (solo procura que no esté encendido el testigo de reserva) y, en Mezná, también sin lavar. Elige entre nuestra amplia oferta de motos (y scooters) y reserva online desde la comodidad de tu casa.$t$),
    ('web.jak_pujcit_vraceni_pujcovna.cta.text', 'fr', 'full', '66f1041e94de7cd3cc8c37a974345f3f', $t$MotoGo24 est une location de motos dans la région de Vysočina qui fonctionne 24h/24, avec une restitution simple à toute heure le jour de ta location. Pas de caution, pas de plein à faire (veille seulement à ce que le voyant de réserve ne soit pas allumé) et, à Mezná, pas de lavage non plus. Choisis parmi notre large gamme de motos (et de scooters) et réserve en ligne depuis chez toi.$t$),
    ('web.jak_pujcit_vraceni_pujcovna.cta.text', 'nl', 'full', 'a62f7b2dc12896c1d2cdf6104339bf50', $t$MotoGo24 is een motorverhuur in de regio Vysočina die 24/7 werkt, met eenvoudig inleveren op elk moment van je huurdag. Geen borg, niet tanken (zorg alleen dat het reservelampje niet brandt) en in Mezná ook niet wassen. Kies uit ons ruime aanbod aan motoren (en scooters) en reserveer online vanuit je luie stoel.$t$),
    ('web.jak_pujcit_vraceni_pujcovna.cta.text', 'pl', 'full', '9b2ff5e2fb8bb013bac44deaf0e3db5c', $t$MotoGo24 to wypożyczalnia motocykli w regionie Vysočina działająca całodobowo, z prostym zwrotem o dowolnej porze w dniu wynajmu. Bez kaucji, bez tankowania (byle nie świeciła się kontrolka rezerwy), a w oddziale Mezná także bez mycia. Wybierz z naszej szerokiej oferty motocykli (i skuterów) i zarezerwuj online w zaciszu domu.$t$),
    ('web.jak_pujcit_vraceni_pujcovna.cta.text', 'uk', 'full', '6cd62288582c518facabe1a0524f6815', $t$MotoGo24 – це прокат мотоциклів на Височині з цілодобовою роботою та простим поверненням мотоцикла будь-коли в день оренди. Без застави, без заправки (лише щоб не світився індикатор резерву), а в Mezná ще й без миття. Обирай із нашої широкої пропозиції мотоциклів (і скутерів) та бронюй онлайн, не виходячи з дому.$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
    ('web.jak_pujcit_vraceni_pujcovna.intro', 'cfe8d7805eff7a8ca7b1b0116a8034ad'),
    ('web.jak_pujcit_vraceni_pujcovna.cta.text', '116e2d90907390e4f59b0b63afc17a09')
    ) AS g(k, gate) USING (k)
    ORDER BY (x.lang <> 'cs')            -- čeština první
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.cms_variables
         SET value = to_jsonb(CASE WHEN f.how = 'phrase' THEN replace(value #>> '{}', f.old, f.new) ELSE f.new END),
             updated_at = now()
       WHERE key = f.k AND jsonb_typeof(value) = 'string'
         AND CASE f.how WHEN 'full' THEN md5(value #>> '{}') = f.old
                        WHEN 'phrase' THEN strpos(value #>> '{}', f.old) > 0 AND strpos(value #>> '{}', f.new) = 0
                        ELSE false END;
    ELSE
      UPDATE public.cms_variables
         SET translations = jsonb_set(translations, ARRAY[f.lang],
               coalesce(translations -> f.lang, '{}'::jsonb) || jsonb_build_object('value',
                 CASE WHEN f.how = 'phrase' THEN replace(translations -> f.lang ->> 'value', f.old, f.new) ELSE f.new END)),
             updated_at = now()
       WHERE key = f.k AND jsonb_typeof(value) = 'string' AND md5(value #>> '{}') = f.gate
         AND jsonb_typeof(translations) = 'object'
         AND CASE f.how
               WHEN 'fill' THEN (translations -> f.lang IS NULL OR jsonb_typeof(translations -> f.lang) = 'object')
                                AND coalesce(translations -> f.lang ->> 'value', '') = ''
               WHEN 'full' THEN jsonb_typeof(translations -> f.lang) = 'object'
                                AND md5(translations -> f.lang ->> 'value') = f.old
               ELSE jsonb_typeof(translations -> f.lang) = 'object'
                    AND strpos(translations -> f.lang ->> 'value', f.old) > 0
                    AND strpos(translations -> f.lang ->> 'value', f.new) = 0 END;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT value #>> '{}', CASE WHEN f.lang = 'cs' THEN value #>> '{}' ELSE translations -> f.lang ->> 'value' END
        INTO v_cs, v_cur FROM public.cms_variables WHERE key = f.k;
      IF (CASE WHEN f.how = 'phrase' THEN strpos(coalesce(v_cur, ''), f.new) > 0 ELSE v_cur = f.new END) THEN
        n_done := n_done + 1;
      ELSIF f.lang <> 'cs' AND md5(v_cs) IS DISTINCT FROM f.gate THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'cms_return: % [%] PŘESKOČENO – česká hodnota není v očekávaném znění, překlad ponechán', f.k, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'cms_return: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', f.k, f.lang, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'cms_return: cms_variables upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
