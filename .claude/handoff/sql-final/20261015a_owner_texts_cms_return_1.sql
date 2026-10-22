-- =============================================================================
-- 20261015a_owner_texts_cms_return_1.sql
-- datová migrace (bez změn schématu): Velín CMS – pravidlo vrácení na stránkách Jak si půjčit (= PHP texty webu) (část 1/2).
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
    ('web.jak_pujcit_dokumenty.payments.rows.2.1', 'cs', 'full', '3997e98e83eb05f3ac0b1ed601a303ea', $t$Vrácení bez povinnosti tankovat – jen ať nesvítí rezerva. Umytou je potřeba motorku vrátit jen na samoobslužné pobočce ve Velkých Němčicích. Případné nadměrné znečištění řešíme individuálně.$t$),
    ('web.jak_pujcit_dokumenty.payments.rows.2.1', 'de', 'full', '5a60659e5346ed9d5ed523adde50b539', $t$Rückgabe ohne Tankpflicht – nur die Reserveleuchte sollte nicht leuchten. Gewaschen zurückgeben musst du das Motorrad nur an der Selbstbedienungsfiliale in Velké Němčice. Starke Verschmutzung klären wir individuell.$t$),
    ('web.jak_pujcit_dokumenty.payments.rows.2.1', 'en', 'full', 'ef68b07aa209417b7c63e82e2a55af53', $t$Return without having to refuel – just make sure the reserve light isn't on. The bike only needs to be returned washed at the self-service branch in Velké Němčice. Excessive dirt is dealt with individually.$t$),
    ('web.jak_pujcit_dokumenty.payments.rows.2.1', 'es', 'full', 'eff2d339901af941997a66917266ecc2', $t$Devolución sin obligación de repostar; solo procura que no esté encendido el testigo de reserva. Solo hay que devolver la moto lavada en la sucursal de autoservicio de Velké Němčice. La suciedad excesiva se resuelve de forma individual.$t$),
    ('web.jak_pujcit_dokumenty.payments.rows.2.1', 'fr', 'full', 'd8cef6b75d78afaa4067831c81c528fe', $t$Restitution sans obligation de faire le plein – veille seulement à ce que le voyant de réserve ne soit pas allumé. La moto ne doit être rendue lavée qu'à l'agence en libre-service de Velké Němčice. Une saleté excessive est réglée au cas par cas.$t$),
    ('web.jak_pujcit_dokumenty.payments.rows.2.1', 'nl', 'full', '81283cc171b4fd6b516a481714b97c08', $t$Terugbrengen zonder tankplicht – zorg alleen dat het reservelampje niet brandt. Alleen bij de zelfbedieningsvestiging in Velké Němčice moet de motor gewassen worden ingeleverd. Overmatig vuil wordt individueel afgehandeld.$t$),
    ('web.jak_pujcit_dokumenty.payments.rows.2.1', 'pl', 'full', '7f6306087eba80116a95a1ee1532baab', $t$Zwrot bez obowiązku tankowania – byle nie świeciła się kontrolka rezerwy. Umyty motocykl trzeba oddać tylko w samoobsługowym oddziale Velké Němčice. Nadmierne zabrudzenie rozpatrujemy indywidualnie.$t$),
    ('web.jak_pujcit_postup.process.steps.11.text', 'cs', 'full', 'fddf262875df0f985f55357e38d23e65', $t$Motorku vrať včas – osobně na pobočku, kde sis ji půjčil (Mezná u Pelhřimova, nebo samoobslužné Velké Němčice u Brna), u motorek z Mezné i na předem sjednané místo. Tankovat nemusíš – jen ať nesvítí rezerva. Umytou ji vracej jen na samoobslužné pobočce ve Velkých Němčicích.$t$),
    ('web.jak_pujcit_postup.process.steps.11.text', 'de', 'full', 'b2eff727660dfd22e19b413e7dbe19ec', $t$Bring das Motorrad pünktlich zurück – persönlich in die Filiale, in der du es gemietet hast (Mezná bei Pelhřimov oder die Selbstbedienungsfiliale in Velké Němčice bei Brno), Motorräder aus Mezná auch an einen vorher vereinbarten Ort. Tanken musst du nicht – nur die Reserveleuchte sollte nicht leuchten. Gewaschen zurückbringen musst du es nur an der Selbstbedienungsfiliale in Velké Němčice.$t$),
    ('web.jak_pujcit_postup.process.steps.11.text', 'en', 'full', '00f47e67c49d35a91f231547e9bc80e5', $t$Return the bike on time – in person at the branch you rented it from (Mezná near Pelhřimov or the self-service branch in Velké Němčice near Brno), or, for bikes from Mezná, at a place agreed in advance. No need to refuel – just make sure the reserve light isn't on. It only needs to be returned washed at the self-service branch in Velké Němčice.$t$),
    ('web.jak_pujcit_postup.process.steps.11.text', 'es', 'full', '5e9b8ae1cbeff282a91afcdd67362644', $t$Devuelve la moto a tiempo: en persona en la sucursal donde la alquilaste (Mezná, cerca de Pelhřimov, o el autoservicio de Velké Němčice, cerca de Brno) o, si es de Mezná, también en el lugar acordado previamente. No tienes que repostar; solo procura que no esté encendido el testigo de reserva. Solo en la sucursal de autoservicio de Velké Němčice hay que devolverla lavada.$t$),
    ('web.jak_pujcit_postup.process.steps.11.text', 'fr', 'full', '4068e84bf4244c7095d6f76397023e6a', $t$Rends la moto à l'heure – en personne à l'agence où tu l'as louée (Mezná, près de Pelhřimov, ou l'agence en libre-service de Velké Němčice, près de Brno) ou, pour les motos de Mezná, à un endroit convenu à l'avance. Pas besoin de faire le plein – veille seulement à ce que le voyant de réserve ne soit pas allumé. Tu ne dois la rendre lavée qu'à l'agence en libre-service de Velké Němčice.$t$),
    ('web.jak_pujcit_postup.process.steps.11.text', 'nl', 'full', '3bf31f957632989cb6951e1f7502d25f', $t$Breng de motor op tijd terug – persoonlijk naar de vestiging waar je hem huurde (Mezná bij Pelhřimov of de zelfbedieningsvestiging in Velké Němčice bij Brno), motoren uit Mezná ook op de afgesproken plek. Tanken is niet nodig – zorg alleen dat het reservelampje niet brandt. Alleen bij de zelfbedieningsvestiging in Velké Němčice lever je hem gewassen in.$t$),
    ('web.jak_pujcit_postup.process.steps.11.text', 'pl', 'full', 'ed3830fbdf8ff626af2bfc8a473b0d0b', $t$Zwróć motocykl na czas – osobiście w oddziale, w którym go wypożyczyłeś (Mezná koło Pelhřimova albo samoobsługowy oddział Velké Němčice koło Brna), a motocykle z oddziału Mezná także w umówionym miejscu. Tankować nie musisz – byle nie świeciła się kontrolka rezerwy. Umyty motocykl oddajesz tylko w samoobsługowym oddziale Velké Němčice.$t$),
    ('web.jak_pujcit_postup.process.steps.11.text', 'uk', 'full', '79b14ea890e45fd521302692080789a8', $t$Поверни мотоцикл вчасно – особисто у філію, де ти його взяв (Mezná біля Пельгржимова або філія самообслуговування Velké Němčice біля Брна), а мотоцикли з Mezná й у заздалегідь узгоджене місце. Заправляти не потрібно – лише стеж, щоб не світився індикатор резерву. Вимитим повертай його лише у філії самообслуговування Velké Němčice.$t$),
    ('web.jak_pujcit_vraceni_pujcovna.intro', 'cs', 'full', 'e209cf8cac0dcb94a66b8eac1750455b', $t$Výpůjčka končí stejně jednoduše jako začala. Přijeď v domluvený čas vrácení na naši adresu v Mezné u Pelhřimova. Vrať motorku a zapůjčenou výbavu a je hotovo. Před vrácením nemusíš mýt ani tankovat – jen ať nesvítí rezerva.&nbsp;$t$),
    ('web.jak_pujcit_vraceni_pujcovna.intro', 'de', 'full', '95d3e312ba728d070e7328efe4a21549', $t$Deine Miete endet genauso einfach, wie sie begonnen hat. Komm zur vereinbarten Rückgabezeit an unsere Adresse in Mezná bei Pelhřimov. Gib das Motorrad und die geliehene Ausrüstung zurück – fertig. Vor der Rückgabe musst du es weder waschen noch tanken – nur die Reserveleuchte sollte nicht leuchten.&nbsp;$t$),
    ('web.jak_pujcit_vraceni_pujcovna.intro', 'en', 'full', '6ed81514f481d59036b1e58f3a30b72a', $t$Your rental ends just as easily as it began. Come to our address in Mezná near Pelhřimov at the agreed return time. Return the bike and the rented gear and you're done. Before returning, you don't need to wash or refuel it – just make sure the reserve light isn't on.&nbsp;$t$),
    ('web.jak_pujcit_vraceni_pujcovna.intro', 'es', 'full', 'b4aa8bcb050e39dc0e37c216f78e61c3', $t$El alquiler termina tan fácil como empezó. Ven a la hora de devolución acordada a nuestra dirección en Mezná, cerca de Pelhřimov. Devuelve la moto y el equipamiento alquilado, y listo. Antes de devolverla no tienes que lavarla ni repostar; solo procura que no esté encendido el testigo de reserva.&nbsp;$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
    ('web.jak_pujcit_dokumenty.payments.rows.2.1', 'dd4eece0db15d935cd8ded844043317e'),
    ('web.jak_pujcit_postup.process.steps.11.text', '6641d6eadd93f027423528251cca5078'),
    ('web.jak_pujcit_vraceni_pujcovna.intro', 'cfe8d7805eff7a8ca7b1b0116a8034ad')
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
