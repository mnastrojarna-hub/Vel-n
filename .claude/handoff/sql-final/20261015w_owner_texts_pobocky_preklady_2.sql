-- =============================================================================
-- 20261015w_owner_texts_pobocky_preklady_2.sql
-- datová migrace (bez změn schématu): překlady textů poboček pro appku (web.pobocky.*) (část 2/7).
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
    ('web.pobocky.branches.0.steps', 'pl', 'fill', NULL, $t$1. Rezerwujesz i płacisz online (strona lub aplikacja) i przesyłasz dokumenty (dowód osobisty/paszport + prawo jazdy); prosimy o to również w oddziale z obsługą: jeśli ich nie prześlesz, sprawdzimy je przy odbiorze na miejscu.<br>2. O wybranej godzinie przyjeżdżasz do oddziału, gdzie na ciebie czekamy.<br>3. Przekazujemy ci motocykl i wyposażenie, a następnie podpisujemy protokół przekazania.<br>4. Po jeździe oddajesz motocykl w oddziale (albo odbierzemy go pod umówionym adresem); nie musisz go myć ani tankować, byle nie świeciła się kontrolka rezerwy.$t$),
    ('web.pobocky.branches.0.steps', 'uk', 'fill', NULL, $t$1. Бронюєш і оплачуєш онлайн (сайт або застосунок) і завантажуєш документи (ID-картка/паспорт + посвідчення водія) — просимо про це й у філії з персоналом: якщо не завантажиш, перевіримо їх на місці під час отримання.<br>2. У вибраний час приїжджаєш до філії, де ми на тебе чекаємо.<br>3. Передаємо мотоцикл і екіпірування та підписуємо протокол передачі.<br>4. Після поїздки повертаєш мотоцикл до філії (або ми заберемо його за домовленою адресою); мити чи заправляти його не потрібно, лише щоб не світився індикатор резерву.$t$),
    ('web.pobocky.branches.0.steps_title', 'en', 'fill', NULL, 'How it works'),
    ('web.pobocky.branches.0.steps_title', 'de', 'fill', NULL, $t$So läuft es ab$t$),
    ('web.pobocky.branches.0.steps_title', 'es', 'fill', NULL, $t$Cómo funciona$t$),
    ('web.pobocky.branches.0.steps_title', 'fr', 'fill', NULL, $t$Comment ça se passe$t$),
    ('web.pobocky.branches.0.steps_title', 'nl', 'fill', NULL, 'Zo werkt het'),
    ('web.pobocky.branches.0.steps_title', 'pl', 'fill', NULL, 'Jak to przebiega'),
    ('web.pobocky.branches.0.steps_title', 'uk', 'fill', NULL, $t$Як це відбувається$t$),
    ('web.pobocky.branches.0.text', 'en', 'fill', NULL, $t$Our main branch in Vysočina. We <strong>hand over the bike in person</strong>: we explain everything, help you with the set-up and choosing gear, and go through the handover protocol together. Rider gear is included in the price. From here we also offer <strong>delivery of the bike</strong> to an address of your choice.$t$),
    ('web.pobocky.branches.0.text', 'de', 'fill', NULL, $t$Unsere Hauptfiliale in Vysočina. Wir <strong>übergeben dir das Motorrad persönlich</strong>: Wir erklären dir alles, helfen beim Einstellen und bei der Wahl der Ausrüstung und gehen gemeinsam das Übergabeprotokoll durch. Die Fahrerausrüstung ist im Preis inbegriffen. Von hier aus bieten wir auch die <strong>Lieferung des Motorrads</strong> an eine Adresse deiner Wahl an.$t$),
    ('web.pobocky.branches.0.text', 'es', 'fill', NULL, $t$Nuestra sucursal principal en Vysočina. Te <strong>entregamos la moto en persona</strong>: te lo explicamos todo, te ayudamos con el ajuste y a elegir el equipo, y revisamos juntos el protocolo de entrega. El equipo de piloto está incluido en el precio. Desde aquí también ofrecemos la <strong>entrega de la moto</strong> en la dirección que elijas.$t$),
    ('web.pobocky.branches.0.text', 'fr', 'fill', NULL, $t$Notre agence principale en Vysočina. Nous te <strong>remettons la moto en personne</strong> : on t'explique tout, on t'aide pour les réglages et le choix de l'équipement, et on passe ensemble le procès-verbal de remise. L'équipement pilote est inclus dans le prix. D'ici, nous proposons aussi la <strong>livraison de la moto</strong> à l'adresse de ton choix.$t$),
    ('web.pobocky.branches.0.text', 'nl', 'fill', NULL, $t$Onze hoofdvestiging in Vysočina. We <strong>overhandigen je de motor persoonlijk</strong>: we leggen alles uit, helpen je met het afstellen en het kiezen van je uitrusting en lopen samen het overdrachtsprotocol door. De rijuitrusting is bij de prijs inbegrepen. Vanaf hier bieden we ook <strong>bezorging van de motor</strong> op een adres naar keuze.$t$),
    ('web.pobocky.branches.0.text', 'pl', 'fill', NULL, $t$Nasz główny oddział w regionie Wysoczyna. Motocykl <strong>przekażemy ci osobiście</strong>: wszystko wyjaśnimy, pomożemy ustawić motocykl i dobrać wyposażenie, a protokół przekazania omówimy razem. Wyposażenie kierowcy jest w cenie. Stąd oferujemy też <strong>dostawę motocykla</strong> pod wybrany przez ciebie adres.$t$),
    ('web.pobocky.branches.0.text', 'uk', 'fill', NULL, $t$Наша головна філія у Височині. Мотоцикл тобі <strong>передамо особисто</strong>: усе пояснимо, допоможемо з налаштуванням і вибором екіпірування та разом пройдемо протокол передачі. Екіпірування водія входить у ціну. Звідси ми також пропонуємо <strong>доставку мотоцикла</strong> за вибраною тобою адресою.$t$),
    ('web.pobocky.branches.0.title', 'en', 'fill', NULL, $t$Mezná near Pelhřimov$t$),
    ('web.pobocky.branches.0.title', 'de', 'fill', NULL, $t$Mezná bei Pelhřimov$t$),
    ('web.pobocky.branches.0.title', 'es', 'fill', NULL, $t$Mezná, cerca de Pelhřimov$t$),
    ('web.pobocky.branches.0.title', 'fr', 'fill', NULL, $t$Mezná, près de Pelhřimov$t$),
    ('web.pobocky.branches.0.title', 'nl', 'fill', NULL, $t$Mezná bij Pelhřimov$t$),
    ('web.pobocky.branches.0.title', 'pl', 'fill', NULL, $t$Mezná koło Pelhřimova$t$),
    ('web.pobocky.branches.0.title', 'uk', 'fill', NULL, $t$Mezná біля Пельгржимова$t$),
    ('web.pobocky.branches.0.video_title', 'en', 'fill', NULL, 'Video: how it works at the branch'),
    ('web.pobocky.branches.0.video_title', 'de', 'fill', NULL, $t$Video: So läuft es in der Filiale ab$t$),
    ('web.pobocky.branches.0.video_title', 'es', 'fill', NULL, $t$Vídeo: así funciona la sucursal$t$),
    ('web.pobocky.branches.0.video_title', 'fr', 'fill', NULL, $t$Vidéo : comment ça se passe à l'agence$t$),
    ('web.pobocky.branches.0.video_title', 'nl', 'fill', NULL, 'Video: zo werkt het bij de vestiging'),
    ('web.pobocky.branches.0.video_title', 'pl', 'fill', NULL, 'Wideo: jak to przebiega w oddziale'),
    ('web.pobocky.branches.0.video_title', 'uk', 'fill', NULL, $t$Відео: як усе відбувається у філії$t$),
    ('web.pobocky.branches.1.address', 'en', 'fill', NULL, $t$Boudky, 691 63 Velké Němčice$t$),
    ('web.pobocky.branches.1.address', 'de', 'fill', NULL, $t$Boudky, 691 63 Velké Němčice$t$),
    ('web.pobocky.branches.1.address', 'es', 'fill', NULL, $t$Boudky, 691 63 Velké Němčice$t$),
    ('web.pobocky.branches.1.address', 'fr', 'fill', NULL, $t$Boudky, 691 63 Velké Němčice$t$),
    ('web.pobocky.branches.1.address', 'nl', 'fill', NULL, $t$Boudky, 691 63 Velké Němčice$t$),
    ('web.pobocky.branches.1.address', 'pl', 'fill', NULL, $t$Boudky, 691 63 Velké Němčice$t$),
    ('web.pobocky.branches.1.address', 'uk', 'fill', NULL, $t$Boudky, 691 63 Velké Němčice$t$),
    ('web.pobocky.branches.1.badge', 'en', 'fill', NULL, 'Self-service branch'),
    ('web.pobocky.branches.1.badge', 'de', 'fill', NULL, 'Selbstbedienungsfiliale'),
    ('web.pobocky.branches.1.badge', 'es', 'fill', NULL, 'Sucursal de autoservicio'),
    ('web.pobocky.branches.1.badge', 'fr', 'fill', NULL, 'Agence en libre-service'),
    ('web.pobocky.branches.1.badge', 'nl', 'fill', NULL, 'Zelfbedieningsvestiging')
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
    ('web.pobocky.branches.0.steps', '79176a8fcb0144ea9ecff2e4e9a0e904'),
    ('web.pobocky.branches.0.steps_title', '2b604146d19ca968abcf9824fd9b57b1'),
    ('web.pobocky.branches.0.text', 'f147a07a86c7688e292c7294b8711200'),
    ('web.pobocky.branches.0.title', '6fa464987affbff96cda15cd3116ea07'),
    ('web.pobocky.branches.0.video_title', '5652a18c906544a4be33999c5c4ef372'),
    ('web.pobocky.branches.1.address', '28343f4ec1d2b9cedbc305fa4a9e685b'),
    ('web.pobocky.branches.1.badge', 'bf8cdf78b8f55a709868faee09eaf66e')
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
