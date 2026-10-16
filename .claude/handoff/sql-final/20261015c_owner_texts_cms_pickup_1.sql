-- =============================================================================
-- 20261015c_owner_texts_cms_pickup_1.sql
-- datová migrace (bez změn schématu): Velín CMS – místa převzetí (obě pobočky) na stránkách Jak si půjčit (část 1/3).
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
    ('web.jak_pujcit_dokumenty.handover.items.0', 'cs', 'full', 'f005050f8900a494b6d68c09ad69dc86', $t$<strong>Převzetí</strong>&nbsp;probíhá v Pelhřimově (Mezná 9) nebo na samoobslužné pobočce ve Velkých Němčicích u Brna; z Mezné je možné i&nbsp;<a href="/jak-pujcit/pristaveni">přistavení</a>.$t$),
    ('web.jak_pujcit_dokumenty.handover.items.0', 'de', 'full', 'b55191c87fd912ef0f4c862a5922ceb9', $t$Die <strong>Abholung</strong>&nbsp;ist in Pelhřimov (Mezná 9) oder an der Selbstbedienungsfiliale in Velké Němčice bei Brno – von Mezná aus kannst du auch unsere&nbsp;<a href="/jak-pujcit/pristaveni">Lieferung</a> nutzen.$t$),
    ('web.jak_pujcit_dokumenty.handover.items.0', 'en', 'full', '777b090de276ce5d8e1169bd0f9c1dfe', $t$<strong>Pick-up</strong>&nbsp;is in Pelhřimov (Mezná 9) or at the self-service branch in Velké Němčice near Brno; from Mezná you can also use&nbsp;<a href="/jak-pujcit/pristaveni">delivery</a>.$t$),
    ('web.jak_pujcit_dokumenty.handover.items.0', 'es', 'full', 'e274d41584a634e82558a482ca3d3212', $t$La&nbsp;<strong>recogida</strong>&nbsp;es en Pelhřimov (Mezná 9) o en la sucursal de autoservicio de Velké Němčice, cerca de Brno; desde Mezná también puedes pedir la&nbsp;<a href="/jak-pujcit/pristaveni">entrega de la moto</a>.$t$),
    ('web.jak_pujcit_dokumenty.handover.items.0', 'fr', 'full', '68671f0eea19ec32b28146051025fdc9', $t$La <strong>prise en charge</strong>&nbsp;se fait à Pelhřimov (Mezná 9) ou à l'agence en libre-service de Velké Němčice, près de Brno – depuis Mezná, profite aussi de notre&nbsp;<a href="/jak-pujcit/pristaveni">livraison</a>.$t$),
    ('web.jak_pujcit_dokumenty.handover.items.0', 'nl', 'full', 'ab6f286a0e35353eaab6fbcf00945bbc', $t$Het&nbsp;<strong>ophalen</strong>&nbsp;gebeurt in Pelhřimov (Mezná 9) of bij de zelfbedieningsvestiging in Velké Němčice bij Brno; vanuit Mezná kun je ook&nbsp;<a href="/jak-pujcit/pristaveni">bezorging</a> gebruiken.$t$),
    ('web.jak_pujcit_dokumenty.handover.items.0', 'pl', 'full', '22b98e829fd22de95a52de8ff08d93db', $t$<strong>Odbiór</strong>&nbsp;odbywa się w Pelhřimovie (Mezná 9) lub w samoobsługowym oddziale Velké Němčice koło Brna; z oddziału Mezná możesz też skorzystać z&nbsp;<a href="/jak-pujcit/pristaveni">podstawienia</a>.$t$),
    ('web.jak_pujcit_postup.intro_p2', 'cs', 'full', 'a7f4d4cca8a0b2df87cb8dac04ffa09f', $t$V naší <strong>motopůjčovně </strong>zvládneš vše online: vyber motorku, zvol termín a vyplň rezervační formulář – včetně výbavy a způsobu předání. Motorku si vyzvedni v Mezné u Pelhřimova (odtud ti ji můžeme i přistavit kamkoliv v ČR), nebo samoobslužně ve Velkých Němčicích u Brna. Platbu provedeš online při dokončení rezervace.$t$),
    ('web.jak_pujcit_postup.intro_p2', 'de', 'full', '32acd14a68879e0af63e70dbb227ef95', $t$In unserem <strong>Motorradverleih</strong> erledigst du alles online: Motorrad wählen, Termin festlegen und Buchungsformular ausfüllen – inklusive Ausrüstung und Art der Übergabe. Hol das Motorrad in Mezná bei Pelhřimov ab (von dort liefern wir es dir auch überallhin in Tschechien) oder per Selbstbedienung in Velké Němčice bei Brno. Bezahlt wird online beim Abschluss der Buchung.$t$),
    ('web.jak_pujcit_postup.intro_p2', 'en', 'full', '31b9b72db851e8983e0000b909256c75', $t$At our <strong>motorcycle rental</strong> you do everything online: choose a bike, pick your dates and fill in the booking form – including gear and how you want to receive the bike. Pick it up in Mezná near Pelhřimov (from there we can also deliver it anywhere in the Czech Republic) or at the self-service branch in Velké Němčice near Brno. You pay online when you complete your booking.$t$),
    ('web.jak_pujcit_postup.intro_p2', 'es', 'full', '4c43cb93feb22d8737aae1b934920631', $t$En nuestro <strong>alquiler de motos</strong> lo haces todo online: eliges la moto, escoges las fechas y rellenas el formulario de reserva, incluido el equipamiento y la forma de entrega. Recoge la moto en Mezná, cerca de Pelhřimov (desde allí también te la llevamos a cualquier lugar de la República Checa), o en el autoservicio de Velké Němčice, cerca de Brno. Pagas online al completar la reserva.$t$),
    ('web.jak_pujcit_postup.intro_p2', 'fr', 'full', 'eb6fbf7b156583819634faa986c92829', $t$Dans notre <strong>location de motos</strong>, tu fais tout en ligne : tu choisis la moto, tu fixes tes dates et tu remplis le formulaire de réservation – équipement et mode de remise compris. Récupère la moto à Mezná, près de Pelhřimov (d'où nous pouvons aussi te la livrer n'importe où en Tchéquie), ou en libre-service à Velké Němčice, près de Brno. Tu paies en ligne en finalisant la réservation.$t$),
    ('web.jak_pujcit_postup.intro_p2', 'nl', 'full', '01e8a06de5979ad10d51af57e7f3f2f1', $t$Bij onze <strong>motorverhuur</strong> doe je alles online: kies een motor, kies een datum en vul het reserveringsformulier in – inclusief uitrusting en overdrachtsmethode. Haal de motor op in Mezná bij Pelhřimov (vanaf daar bezorgen we ook overal in Tsjechië) of via zelfbediening in Velké Němčice bij Brno. Je betaalt online bij het voltooien van de reservering.$t$),
    ('web.jak_pujcit_postup.intro_p2', 'pl', 'full', '449bd5cf7bc76bca0bf94dd134e95a2f', $t$W naszej <strong>wypożyczalni motocykli</strong> wszystko załatwisz online: wybierz motocykl, wybierz termin i wypełnij formularz rezerwacji – wraz z wyposażeniem i sposobem przekazania. Odbierz motocykl w oddziale Mezná koło Pelhřimova (stamtąd możemy go też podstawić w dowolne miejsce w Czechach) albo samoobsługowo w Velké Němčice koło Brna. Płacisz online przy finalizacji rezerwacji.$t$),
    ('web.jak_pujcit_postup.process.steps.4.text', 'cs', 'full', 'a89d691f3229e007eba118490a24d614', $t$Vyber místo převzetí – osobně v Mezné u Pelhřimova, samoobslužně ve Velkých Němčicích u Brna, nebo přistavení z Mezné kamkoliv v ČR.&nbsp;$t$),
    ('web.jak_pujcit_postup.process.steps.4.text', 'de', 'full', 'f2134f282ebdc13ef488d8cbffc6efe1', $t$Wähle, wie du das Motorrad bekommst – persönlich in Mezná bei Pelhřimov, per Selbstbedienung in Velké Němčice bei Brno oder per Lieferung ab Mezná überallhin in Tschechien.&nbsp;$t$),
    ('web.jak_pujcit_postup.process.steps.4.text', 'en', 'full', '2e6a300b44846b98731f4c79da973959', $t$Choose how you get the bike – in person in Mezná near Pelhřimov, self-service in Velké Němčice near Brno, or delivered from Mezná anywhere in the Czech Republic.&nbsp;$t$),
    ('web.jak_pujcit_postup.process.steps.4.text', 'es', 'full', '914cca5b92c55a3a97315a1892568d8e', $t$Elige dónde recibes la moto: en persona en nuestra sucursal de Mezná, cerca de Pelhřimov; en el autoservicio de Velké Němčice, cerca de Brno; o con entrega desde Mezná en cualquier lugar de la República Checa.&nbsp;$t$),
    ('web.jak_pujcit_postup.process.steps.4.text', 'fr', 'full', 'c822259258a6a43279c43d6315741ce4', $t$Choisis comment tu récupères la moto – en personne à Mezná, près de Pelhřimov, en libre-service à Velké Němčice, près de Brno, ou par livraison depuis Mezná n'importe où en Tchéquie.&nbsp;$t$),
    ('web.jak_pujcit_postup.process.steps.4.text', 'nl', 'full', 'eb7a61e68f3493f40dd148c9adb4e6c3', $t$Selecteer de ophaalmethode – persoonlijk in Mezná bij Pelhřimov, via zelfbediening in Velké Němčice bij Brno, of bezorging vanuit Mezná overal in Tsjechië.&nbsp;$t$),
    ('web.jak_pujcit_postup.process.steps.4.text', 'pl', 'full', '8a2bb297485e83f7627cf6c9f44e039c', $t$Wybierz sposób odbioru – osobiście w oddziale Mezná koło Pelhřimova, samoobsługowo w Velké Němčice koło Brna albo podstawienie z oddziału Mezná w dowolne miejsce w Czechach.&nbsp;$t$),
    ('web.jak_pujcit_postup.process.steps.4.text', 'uk', 'full', '0d9040a9bd9b76d5d76cab337016b394', $t$Вибери спосіб отримання – особисто в Mezná біля Пельгржимова, самостійно у філії самообслуговування Velké Němčice біля Брна або доставку з Mezná будь-куди в ЧР.&nbsp;$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
    ('web.jak_pujcit_dokumenty.handover.items.0', 'c4e76203f298206bc4cd70b3305cd304'),
    ('web.jak_pujcit_postup.intro_p2', '89ccfc230ca2adc86144b09543abe663'),
    ('web.jak_pujcit_postup.process.steps.4.text', 'cefc474680aa19ccad9080c5ba815990')
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
