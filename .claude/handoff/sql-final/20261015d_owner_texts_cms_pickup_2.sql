-- =============================================================================
-- 20261015d_owner_texts_cms_pickup_2.sql
-- datová migrace (bez změn schématu): Velín CMS – místa převzetí (obě pobočky) na stránkách Jak si půjčit (část 2/3).
--
-- Odpovědi majitele 2026-10-11/12: dvě pobočky – obslužná Mezná u Pelhřimova (odtud i přistavení
-- a odvoz) a samoobslužná Velké Němčice u Brna (převzetí i vrácení jen na pobočce, kódy z aplikace /
-- e-mailu); aplikace MotoGo24 je na Google Play (Android) i v App Store (iPhone).
--
-- Nastavuje na přesné PHP texty (cs + existující překlady):
--   web.jak_pujcit_dokumenty.handover.items.0, web.jak_pujcit_postup.intro_p2,
--   web.jak_pujcit_postup.process.steps.4.text, web.jak_pujcit_vyzvednuti.intro,
--   web.jak_pujcit_pristaveni.intro (přistavení jen u motorek z Mezné)
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
    ('web.jak_pujcit_vyzvednuti.intro', 'cs', 'full', '8638a6e0175c2e0167a6d38f5e4de5c7', $t$V <strong>Motogo24 – půjčovně motorek na Vysočině</strong>&nbsp;je převzetí motorky otázkou pár minut. Půjčujeme bez <strong>kauce, s výbavou pro řidiče v ceně a nonstop provozem</strong>. Přijď osobně do Mezné u Pelhřimova a vyraz na cestu! Na samoobslužné pobočce ve Velkých Němčicích u Brna si motorku vyzvedneš sám přístupovým kódem z aplikace nebo e-mailu.$t$),
    ('web.jak_pujcit_vyzvednuti.intro', 'de', 'full', 'ddff73fc8045c2cae52cedac54d67521', $t$Bei <strong>MotoGo24 – Motorradverleih in der Region Vysočina</strong>&nbsp;dauert die Abholung nur wenige Minuten. Wir vermieten <strong>ohne Kaution, mit Fahrerausrüstung inklusive und mit Abholung und Rückgabe rund um die Uhr</strong>. Komm persönlich nach Mezná bei Pelhřimov und ab auf die Straße! In der Selbstbedienungsfiliale in Velké Němčice bei Brno holst du das Motorrad selbst mit einem Zugangscode aus der App oder der E-Mail ab.$t$),
    ('web.jak_pujcit_vyzvednuti.intro', 'en', 'full', '14c12a79b7da7470f21f0ce933020261', $t$At <strong>MotoGo24 – motorcycle rental in the Vysočina region</strong>,&nbsp;picking up a bike takes just a few minutes. We rent with <strong>no deposit, rider gear included and 24/7 pick-up and return</strong>. Come to Mezná near Pelhřimov in person and hit the road! At the self-service branch in Velké Němčice near Brno you pick up the bike yourself with an access code from the app or e-mail.$t$),
    ('web.jak_pujcit_vyzvednuti.intro', 'es', 'full', '4a19c33423cdd7583c72c4b646d2217c', $t$En <strong>MotoGo24 – alquiler de motos en la región de Vysočina</strong>,&nbsp;recoger la moto es cuestión de pocos minutos. Alquilamos <strong>sin fianza, con el equipamiento del piloto incluido y con recogida y devolución 24/7</strong>. ¡Ven en persona a Mezná, cerca de Pelhřimov, y sal a la carretera! En la sucursal de autoservicio de Velké Němčice, cerca de Brno, recoges la moto tú mismo con un código de acceso de la app o del e-mail.$t$),
    ('web.jak_pujcit_vyzvednuti.intro', 'fr', 'full', 'd033252bf5e0062e6369bba35fa377e2', $t$Chez <strong>MotoGo24 – location de motos dans la région de Vysočina</strong>,&nbsp;la prise en charge de la moto ne prend que quelques minutes. Nous louons <strong>sans caution, avec l'équipement du pilote inclus, et le retrait comme le retour se font 24h/24</strong>. Viens nous voir à Mezná, près de Pelhřimov, et en route ! À l'agence en libre-service de Velké Němčice, près de Brno, tu récupères la moto toi-même avec un code d'accès reçu dans l'appli ou par e-mail.$t$),
    ('web.jak_pujcit_vyzvednuti.intro', 'nl', 'full', '5ff19c2ecdbd323ee54c8ca6c88aa27d', $t$Bij <strong>MotoGo24 – motorverhuur in de regio Vysočina</strong> is het ophalen van de motor in een paar minuten geregeld. We verhuren <strong>zonder borg, met rijuitrusting inbegrepen en met ophalen en inleveren 24/7</strong>. Kom persoonlijk naar Mezná bij Pelhřimov en ga op pad! Bij de zelfbedieningsvestiging in Velké Němčice bij Brno haal je de motor zelf op met een toegangscode uit de app of de e-mail.$t$),
    ('web.jak_pujcit_vyzvednuti.intro', 'pl', 'full', 'b4a4e2ad2619f156e1a4f90da21285c1', $t$W <strong>MotoGo24 – wypożyczalni motocykli w regionie Vysočina</strong> odbiór motocykla to kwestia kilku minut. Wypożyczamy <strong>bez kaucji, z wyposażeniem kierowcy w cenie oraz z odbiorem i zwrotem 24/7</strong>. Przyjedź osobiście do oddziału w Mezná koło Pelhřimova i ruszaj w drogę! W samoobsługowym oddziale Velké Němčice koło Brna odbierzesz motocykl sam za pomocą kodu dostępu z aplikacji lub e-maila.$t$),
    ('web.jak_pujcit_pristaveni.intro', 'cs', 'full', '3df5738779e27d02e8ea5878592fec97', $t$Chceš vyrazit bez zbytečného přesunu do půjčovny? Zajistíme <strong>přistavení motorky na domluvené místo</strong> – domů, do hotelu, k nádraží nebo na start tvého výletu. Motorku přivezeme kamkoliv v České republice – přímo z naší provozovny v Mezné u Pelhřimova. Přistavení nabízíme u motorek z obslužné pobočky v Mezné; motorky ze samoobslužné pobočky ve Velkých Němčicích se přebírají jen přímo na pobočce.$t$),
    ('web.jak_pujcit_pristaveni.intro', 'de', 'full', '64c2c7061a7cd69f2b3c0e2e2c2bc520', $t$Du willst losfahren, ohne erst zum Verleih zu fahren? Wir organisieren die <strong>Lieferung des Motorrads an einen vereinbarten Ort</strong> – nach Hause, ins Hotel, zum Bahnhof oder an den Start deiner Tour. Wir liefern überallhin in Tschechien – direkt aus unserer Filiale in Mezná bei Pelhřimov. Die Lieferung gibt es für Motorräder aus unserer Filiale mit Personal in Mezná; Motorräder der Selbstbedienungsfiliale in Velké Němčice holst du nur direkt dort ab.$t$),
    ('web.jak_pujcit_pristaveni.intro', 'en', 'full', '7e4dd24e7acc6ad1f350a3adda291f57', $t$Want to set off without travelling to the rental first? We'll arrange <strong>delivery of the bike to an agreed place</strong> – your home, a hotel, a train station or the start of your trip. We deliver anywhere in the Czech Republic – straight from our branch in Mezná near Pelhřimov. Delivery is available for bikes from our staffed branch in Mezná; bikes from the self-service branch in Velké Němčice are picked up only at that branch.$t$),
    ('web.jak_pujcit_pristaveni.intro', 'es', 'full', '5e349189fc6977cdb7006f1200f6568e', $t$¿Quieres salir sin tener que desplazarte hasta el alquiler? Te <strong>llevamos la moto al lugar acordado</strong>: a casa, al hotel, a la estación o al punto de salida de tu excursión. Te la llevamos a cualquier lugar de la República Checa, directamente desde nuestra sucursal de Mezná, cerca de Pelhřimov. La entrega está disponible para las motos de nuestra sucursal con personal de Mezná; las motos de la sucursal de autoservicio de Velké Němčice solo se recogen en esa sucursal.$t$),
    ('web.jak_pujcit_pristaveni.intro', 'fr', 'full', 'b6547176030404f9b624199edfdee0dd', $t$Tu veux partir sans passer d'abord par l'agence ? Nous organisons la <strong>livraison de la moto à l'endroit convenu</strong> – chez toi, à l'hôtel, à la gare ou au point de départ de ta balade. Nous livrons partout en Tchéquie – directement depuis notre agence de Mezná, près de Pelhřimov. La livraison est proposée pour les motos de notre agence avec personnel de Mezná ; les motos de l'agence en libre-service de Velké Němčice se récupèrent uniquement sur place.$t$),
    ('web.jak_pujcit_pristaveni.intro', 'nl', 'full', '97d24cec95db2712de9e49173258c992', $t$Wil je vertrekken zonder eerst naar de verhuur te gaan? We zorgen voor <strong>bezorging van de motor op een afgesproken plek</strong> – thuis, bij je hotel, op het station of bij het startpunt van je tocht. We bezorgen overal in Tsjechië – rechtstreeks vanuit onze vestiging in Mezná bij Pelhřimov. Bezorging is mogelijk voor motoren van onze bemande vestiging in Mezná; motoren van de zelfbedieningsvestiging in Velké Němčice haal je alleen daar op.$t$),
    ('web.jak_pujcit_pristaveni.intro', 'pl', 'full', '8c3368b639c3eb6a10bb4e7fb4b016df', $t$Chcesz wyruszyć bez jazdy do wypożyczalni? Zorganizujemy <strong>dostawę motocykla w umówione miejsce</strong> – do domu, do hotelu, na dworzec albo na start twojej wycieczki. Dowieziemy go w dowolne miejsce w Czechach – prosto z naszego oddziału w Mezná koło Pelhřimova. Dostawę oferujemy dla motocykli z oddziału z obsługą w Mezná; motocykle z samoobsługowego oddziału Velké Němčice odbiera się tylko bezpośrednio w tym oddziale.$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
    ('web.jak_pujcit_vyzvednuti.intro', '2055f7b93ba8f00e49c67514ce610fd5'),
    ('web.jak_pujcit_pristaveni.intro', '79a82527ffb9b7b04ea7c5600e12d2d0')
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
        RAISE NOTICE 'cms_pickup: % [%] PŘESKOČENO – česká hodnota není v očekávaném znění, překlad ponechán', f.k, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'cms_pickup: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', f.k, f.lang, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'cms_pickup: cms_variables upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
