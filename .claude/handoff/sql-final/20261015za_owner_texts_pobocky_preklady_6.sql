-- =============================================================================
-- 20261015za_owner_texts_pobocky_preklady_6.sql
-- datová migrace (bez změn schématu): překlady textů poboček pro appku (web.pobocky.*) (část 6/7).
--
-- Odpovědi majitele 2026-10-11/12: dvě pobočky – obslužná Mezná u Pelhřimova (odtud i přistavení
-- a odvoz) a samoobslužná Velké Němčice u Brna (převzetí i vrácení jen na pobočce, kódy z aplikace /
-- e-mailu); aplikace MotoGo24 je na Google Play (Android) i v App Store (iPhone).
--
-- Appka (obrazovka Pobočky, oba stromy) bere texty z cms_variables web.pobocky.* a bez překladu ukazuje
-- ve všech jazycích ČEŠTINU – včetně postupu samoobslužného převzetí ve Velkých Němčicích. Web cizí
-- jazyky bere z lang/v2/<jazyk>/pobocky.php; tytéž texty se sem doplní jako překlady (web se tím
-- nezmění, appka dostane 7 jazyků). Doplňuje jen chybějící překlad a jen když česká hodnota je přesně
-- ta, ze které lang/v2 vychází (data/pobocky.php).
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
    ('web.pobocky.branches.1.text', 'nl', 'fill', NULL, $t$Moderne <strong>zelfbedieningsvestiging</strong> ten zuiden van Brno. Er is geen personeel: je regelt alles zelf op het touchscreen met de <strong>codes uit de app</strong>, die je krijgt na betaling en het aanvullen van je documenten. Motoren van deze vestiging worden alleen bij de vestiging zelf opgehaald en ingeleverd: bezorging of ophalen op een adres bieden we hier niet aan. Bij de vestiging kun je de hele huurperiode <strong>gratis parkeren</strong>.$t$),
    ('web.pobocky.branches.1.text', 'pl', 'fill', NULL, $t$Nowoczesny <strong>oddział samoobsługowy</strong> na południe od Brna. Na miejscu nie ma obsługi: wszystko załatwiasz samodzielnie na ekranie dotykowym za pomocą <strong>kodów z aplikacji</strong>, które dostajesz po opłaceniu rezerwacji i uzupełnieniu dokumentów. Motocykle z tego oddziału odbiera się i zwraca tylko na miejscu: nie oferujemy dostawy ani odbioru spod adresu. Przy oddziale możesz przez cały czas wynajmu <strong>parkować za darmo</strong>.$t$),
    ('web.pobocky.branches.1.text', 'uk', 'fill', NULL, $t$Сучасна <strong>філія самообслуговування</strong> на південь від Брна. Персоналу на місці немає: усе робиш самостійно на сенсорному екрані за допомогою <strong>кодів із застосунку</strong>, які отримаєш після оплати й завантаження документів. Мотоцикли з цієї філії отримують і повертають лише безпосередньо у філії: доставки чи вивезення для них немає. Біля філії можна <strong>безкоштовно паркуватися</strong> весь час оренди.$t$),
    ('web.pobocky.branches.1.title', 'en', 'fill', NULL, $t$Velké Němčice near Brno$t$),
    ('web.pobocky.branches.1.title', 'de', 'fill', NULL, $t$Velké Němčice bei Brno$t$),
    ('web.pobocky.branches.1.title', 'es', 'fill', NULL, $t$Velké Němčice, cerca de Brno$t$),
    ('web.pobocky.branches.1.title', 'fr', 'fill', NULL, $t$Velké Němčice, près de Brno$t$),
    ('web.pobocky.branches.1.title', 'nl', 'fill', NULL, $t$Velké Němčice bij Brno$t$),
    ('web.pobocky.branches.1.title', 'pl', 'fill', NULL, $t$Velké Němčice koło Brna$t$),
    ('web.pobocky.branches.1.title', 'uk', 'fill', NULL, $t$Velké Němčice біля Брна$t$),
    ('web.pobocky.branches.1.video_title', 'en', 'fill', NULL, 'Video: how to use the self-service branch'),
    ('web.pobocky.branches.1.video_title', 'de', 'fill', NULL, 'Video: So nutzt du die Selbstbedienungsfiliale'),
    ('web.pobocky.branches.1.video_title', 'es', 'fill', NULL, $t$Vídeo: cómo usar la sucursal de autoservicio$t$),
    ('web.pobocky.branches.1.video_title', 'fr', 'fill', NULL, $t$Vidéo : comment utiliser l'agence en libre-service$t$),
    ('web.pobocky.branches.1.video_title', 'nl', 'fill', NULL, 'Video: zo gebruik je de zelfbedieningsvestiging'),
    ('web.pobocky.branches.1.video_title', 'pl', 'fill', NULL, $t$Wideo: jak korzystać z oddziału samoobsługowego$t$),
    ('web.pobocky.branches.1.video_title', 'uk', 'fill', NULL, $t$Відео: як користуватися філією самообслуговування$t$),
    ('web.pobocky.cta.button', 'en', 'fill', NULL, 'BOOK ONLINE'),
    ('web.pobocky.cta.button', 'de', 'fill', NULL, 'ONLINE RESERVIEREN'),
    ('web.pobocky.cta.button', 'es', 'fill', NULL, 'RESERVAR ONLINE'),
    ('web.pobocky.cta.button', 'fr', 'fill', NULL, $t$RÉSERVER EN LIGNE$t$),
    ('web.pobocky.cta.button', 'nl', 'fill', NULL, 'ONLINE RESERVEREN'),
    ('web.pobocky.cta.button', 'pl', 'fill', NULL, 'ZAREZERWUJ ONLINE'),
    ('web.pobocky.cta.button', 'uk', 'fill', NULL, $t$ЗАБРОНЮВАТИ ОНЛАЙН$t$),
    ('web.pobocky.cta.text', 'en', 'fill', NULL, $t$In the booking you choose the branch and only the bikes available there are shown.$t$),
    ('web.pobocky.cta.text', 'de', 'fill', NULL, $t$Bei der Reservierung wählst du die Filiale und siehst nur die Motorräder, die dort stehen.$t$),
    ('web.pobocky.cta.text', 'es', 'fill', NULL, 'En la reserva eliges la sucursal y solo te aparecen las motos que hay en ella.'),
    ('web.pobocky.cta.text', 'fr', 'fill', NULL, $t$Dans la réservation, tu choisis l'agence et seules les motos présentes sur place s'affichent.$t$),
    ('web.pobocky.cta.text', 'nl', 'fill', NULL, $t$In de reservering kies je de vestiging en zie je alleen de motoren die daar staan.$t$),
    ('web.pobocky.cta.text', 'pl', 'fill', NULL, $t$W rezerwacji wybierasz oddział i widzisz tylko motocykle, które są w nim dostępne.$t$),
    ('web.pobocky.cta.text', 'uk', 'fill', NULL, $t$У бронюванні обираєш філію — і бачиш лише мотоцикли, які в ній є.$t$),
    ('web.pobocky.cta.title', 'en', 'fill', NULL, 'Choose a bike at your branch'),
    ('web.pobocky.cta.title', 'de', 'fill', NULL, $t$Wähle dein Motorrad in deiner Filiale$t$),
    ('web.pobocky.cta.title', 'es', 'fill', NULL, 'Elige tu moto en tu sucursal'),
    ('web.pobocky.cta.title', 'fr', 'fill', NULL, 'Choisis ta moto dans ton agence'),
    ('web.pobocky.cta.title', 'nl', 'fill', NULL, 'Kies je motor bij jouw vestiging'),
    ('web.pobocky.cta.title', 'pl', 'fill', NULL, 'Wybierz motocykl w swoim oddziale'),
    ('web.pobocky.cta.title', 'uk', 'fill', NULL, $t$Обери мотоцикл у своїй філії$t$),
    ('web.pobocky.detail_button', 'en', 'fill', NULL, 'Branch details'),
    ('web.pobocky.detail_button', 'de', 'fill', NULL, 'Zur Filiale'),
    ('web.pobocky.detail_button', 'es', 'fill', NULL, 'Ver la sucursal'),
    ('web.pobocky.detail_button', 'fr', 'fill', NULL, $t$Voir l'agence$t$),
    ('web.pobocky.detail_button', 'nl', 'fill', NULL, 'Bekijk vestiging'),
    ('web.pobocky.detail_button', 'pl', 'fill', NULL, $t$Szczegóły oddziału$t$),
    ('web.pobocky.detail_button', 'uk', 'fill', NULL, $t$Деталі філії$t$),
    ('web.pobocky.h1', 'en', 'fill', NULL, 'MotoGo24 branches'),
    ('web.pobocky.h1', 'de', 'fill', NULL, 'Filialen von MotoGo24'),
    ('web.pobocky.h1', 'es', 'fill', NULL, 'Sucursales de MotoGo24'),
    ('web.pobocky.h1', 'fr', 'fill', NULL, 'Agences MotoGo24'),
    ('web.pobocky.h1', 'nl', 'fill', NULL, 'Vestigingen van MotoGo24'),
    ('web.pobocky.h1', 'pl', 'fill', NULL, $t$Oddziały MotoGo24$t$),
    ('web.pobocky.h1', 'uk', 'fill', NULL, $t$Філії MotoGo24$t$),
    ('web.pobocky.intro', 'en', 'fill', NULL, $t$You can pick up your bike in <strong>two places</strong>: at the <strong>staffed branch in Mezná near Pelhřimov</strong>, where we welcome you in person, or at the <strong>self-service branch in Velké Němčice near Brno</strong>, where you collect the bike and gear yourself using codes.$t$),
    ('web.pobocky.intro', 'de', 'fill', NULL, $t$Dein Motorrad kannst du an <strong>zwei Orten</strong> abholen: in der <strong>Filiale mit Personal in Mezná bei Pelhřimov</strong>, wo wir dich persönlich empfangen, oder in der <strong>Selbstbedienungsfiliale in Velké Němčice bei Brno</strong>, wo du Motorrad und Ausrüstung selbst per Code übernimmst.$t$),
    ('web.pobocky.intro', 'es', 'fill', NULL, $t$Puedes recoger tu moto en <strong>dos lugares</strong>: en la <strong>sucursal con personal de Mezná, cerca de Pelhřimov</strong>, donde te recibimos en persona, o en la <strong>sucursal de autoservicio de Velké Němčice, cerca de Brno</strong>, donde recoges tú mismo la moto y el equipo con códigos.$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
    ('web.pobocky.branches.1.text', 'bd1e887bcd97f780656e46be4c6baed2'),
    ('web.pobocky.branches.1.title', '2e3b872668cd80c65f5de60080713309'),
    ('web.pobocky.branches.1.video_title', '7000315a4be4884700aa329e47547592'),
    ('web.pobocky.cta.button', '5c54ba7b1baf87bd22eb378813040efe'),
    ('web.pobocky.cta.text', '7b7dac57256dc2af469e2f1a0df75009'),
    ('web.pobocky.cta.title', 'b42afa1dc177ae45cb7cea7d13179e3f'),
    ('web.pobocky.detail_button', 'f22e5ca71ca0c19b2d3aee8349846435'),
    ('web.pobocky.h1', '1a9fdadd8f01b3a87cd2d949fb0da3ca'),
    ('web.pobocky.intro', '7d4bda86bed11402a0947a96cb9d8698')
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
        RAISE NOTICE 'pobocky_preklady: % [%] PŘESKOČENO – česká hodnota není v očekávaném znění, překlad ponechán', f.k, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'pobocky_preklady: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', f.k, f.lang, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'pobocky_preklady: cms_variables upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
