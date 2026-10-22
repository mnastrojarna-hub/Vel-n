-- =============================================================================
-- 20261015r_owner_texts_blog_app.sql
-- datová migrace (bez změn schématu): blog – aplikace už je i v App Store (iPhone).
--
-- Odpovědi majitele 2026-10-11/12: dvě pobočky – obslužná Mezná u Pelhřimova (odtud i přistavení
-- a odvoz) a samoobslužná Velké Němčice u Brna (převzetí i vrácení jen na pobočce, kódy z aplikace /
-- e-mailu); aplikace MotoGo24 je na Google Play (Android) i v App Store (iPhone).
--
-- cms_pages 4185202a „Aplikace MotoGo24: půjčovna, navigace i parťák na cesty“ (publikovaný) tvrdil, že verze
-- pro iPhone „se chystá“; c3356f4a „Zavádíme 100% smluvní krytí škod“ odkazoval jen na verzi pro Android.
-- Mění se jen tyto věty (článek, perex, všechny překlady); zbytek článků beze změny. Překlad pole (článek /
-- perex) jen když české TOTÉŽ pole už má novou větu. Navíc dvě staré chyby v dotčených polích:
-- de perex „Treurabatte“ → „Treuerabatte“, pl závěr „Szęść tysięcy szczęśliwych mil…“ → „Szerokiej drogi…“.
-- Jen opravy překladu (čeština beze změny, brána prázdná): 4d86e5bb „…nově i pro iPhone“ es perex „en la App
-- Store … el espera“ → „en el App Store … la espera“; 5ec9affa „Proč je MotoGo24 nejlepší…“ de „Treurabatte“.
--
-- Bezpečnost: mění JEN text ve znění ověřeném proti živé DB (stav 2026-10-15); co mezitím
-- někdo upravil ve Velínu, se přeskočí s NOTICE. Idempotentní (2. běh nic nezmění). Bez
-- BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================

-- updated_at nastaví trigger cms_pages_updated_at.
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
  -- x: id článku, pole (content/excerpt), jazyk ('cs' = sloupec, jinak translations.<jazyk>),
  --    ověřená věta (v živém textu přesně jednou), nová věta
  -- g: brána – překlad pole se mění jen když TOTÉŽ české pole (článek / perex) už obsahuje novou českou větu
  FOR f IN
    SELECT x.*, g.gate FROM (VALUES
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'content', 'cs', $t$Máš "Jabko"? Nezoufej a vydrž, <strong>verze pro iOS se chystá</strong> a bude brzy k dispozici. Sleduj nás na sítích, dozvíš se to mezi prvními.$t$, $t$Máš "Jabko"? Čekání skončilo – od září 2026 je aplikace <strong>i v App Store</strong> pro iPhone. Stačí v obchodě vyhledat „MotoGo24“.$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'excerpt', 'cs', $t$Aplikace MotoGo24 je ke stažení na Google Play a verze pro iPhone je na cestě.$t$, $t$Aplikace MotoGo24 je ke stažení na Google Play i v App Store.$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'content', 'en', $t$Have an Apple? Don't worry, <strong>the iOS version is coming</strong> and will be available soon. Follow us on social media and you'll be among the first to know.$t$, $t$Have an iPhone? The wait is over – since September 2026 the app is <strong>also on the App Store</strong>. Just search for “MotoGo24”.$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'excerpt', 'en', $t$The MotoGo24 app is available for download on Google Play, and the iPhone version is on its way.$t$, 'The MotoGo24 app is available for download on Google Play and the App Store.'),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'content', 'de', $t$Du hast einen "Apfel"? Keine Sorge, <strong>die iOS-Version ist in Vorbereitung</strong> und wird bald verfügbar sein. Folge uns in den sozialen Netzwerken, um es als einer der Ersten zu erfahren.$t$, $t$Du hast ein iPhone? Das Warten hat ein Ende – seit September 2026 gibt es die App <strong>auch im App Store</strong>. Such im Store einfach nach „MotoGo24“.$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'excerpt', 'de', $t$Die MotoGo24-App ist im Google Play Store verfügbar und die iPhone-Version ist unterwegs.$t$, $t$Die MotoGo24-App ist bei Google Play und im App Store verfügbar.$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'excerpt', 'de', 'Treurabatte', 'Treuerabatte'),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'content', 'es', $t$¿Tienes "Apple"? No desesperes, <strong>la versión para iOS está en preparación</strong> y pronto estará disponible. Síguenos en redes sociales, lo sabrás entre los primeros.$t$, $t$¿Tienes iPhone? Se acabó la espera: desde septiembre de 2026 la aplicación está <strong>también en el App Store</strong>. Solo tienes que buscar «MotoGo24» en la tienda.$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'excerpt', 'es', $t$La aplicación MotoGo24 está disponible en Google Play y la versión para iPhone está en camino.$t$, $t$La aplicación MotoGo24 está disponible en Google Play y en el App Store.$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'content', 'fr', $t$Tu as un « Jabko » ? Ne désespère pas et sois patient, <strong>la version iOS se prépare</strong> et sera bientôt disponible. Suis-nous sur les réseaux sociaux, tu l'apprendras parmi les premiers.$t$, $t$Tu as un iPhone ? L'attente est terminée : depuis septembre 2026, l'application est <strong>aussi sur l'App Store</strong>. Il suffit de chercher « MotoGo24 ».$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'excerpt', 'fr', $t$L'application MotoGo24 est à télécharger sur Google Play et la version iPhone est en chemin.$t$, $t$L'application MotoGo24 est à télécharger sur Google Play et sur l'App Store.$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'content', 'nl', $t$Heb je een „appel"? Wanhoop niet en wacht even, de <strong>iOS-versie is in voorbereiding</strong> en komt binnenkort. Volg ons op sociale netwerken, dan weet je het als eerste.$t$, $t$Heb je een iPhone? Het wachten is voorbij – sinds september 2026 staat de app <strong>ook in de App Store</strong>. Zoek gewoon op „MotoGo24".$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'excerpt', 'nl', 'De MotoGo24-app is beschikbaar op Google Play en de iPhone-versie is onderweg.', 'De MotoGo24-app is beschikbaar op Google Play en in de App Store.'),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'content', 'pl', $t$Masz "Jabłko"? Nie rozpaczaj, <strong>wersja na iOS jest w przygotowaniu</strong> i wkrótce będzie dostępna. Śledź nas w mediach społecznościowych, dowiesz się tego jako jeden z pierwszych.$t$, $t$Masz iPhone'a? Koniec czekania – od września 2026 aplikacja jest <strong>także w App Store</strong>. Wystarczy wyszukać w sklepie „MotoGo24".$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'excerpt', 'pl', $t$Aplikacja MotoGo24 jest dostępna do pobrania na Google Play, a wersja na iPhone'a jest w drodze.$t$, $t$Aplikacja MotoGo24 jest dostępna do pobrania na Google Play i w App Store.$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'content', 'pl', $t$Szęść tysięcy szczęśliwych mil, motocykliści, widzimy się na drogach! 🏍️$t$, $t$Szerokiej drogi, motocykliści, do zobaczenia na trasie! 🏍️$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'content', 'uk', $t$Маєш «Яблуко»? Не відчайся й почекай, <strong>версія для iOS готується</strong> і незабаром буде доступна. Стежи за нами в соцмережах, ти дізнаєшся про це першим.$t$, $t$Маєш iPhone? Чекання закінчилося – з вересня 2026 застосунок є <strong>і в App Store</strong>. Просто знайди «MotoGo24» у магазині.$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'excerpt', 'uk', $t$Додаток MotoGo24 можна завантажити на Google Play, а версія для iPhone вже в розробці.$t$, $t$Додаток MotoGo24 можна завантажити з Google Play і App Store.$t$),
    ('c3356f4a-e608-4bca-b16d-dcee9dc6c101', 'content', 'cs', 'MotoGo24 (verze pro Android).', 'MotoGo24 (Google Play pro Android i App Store pro iPhone).'),
    ('c3356f4a-e608-4bca-b16d-dcee9dc6c101', 'content', 'en', 'MotoGo24 app (Android version).', 'MotoGo24 app (Google Play for Android, App Store for iPhone).'),
    ('4d86e5bb-fa8d-49b6-bcce-be8f5efa7679', 'excerpt', 'es', $t$en la App Store desde septiembre de 2026. Amigos de Apple, el espera se acabó.$t$, $t$en el App Store desde septiembre de 2026. Amigos de Apple, la espera se acabó.$t$),
    ('5ec9affa-b1e6-48c4-8d3f-a3ee1be22acc', 'content', 'de', $t$Übersicht über deine Miete, Treurabatte und Kommunikation$t$, $t$Übersicht über deine Miete, Treuerabatte und Kommunikation$t$)
    ) AS x(id, field, lang, old_txt, new_txt)
    JOIN (VALUES
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'content', $t$Máš "Jabko"? Čekání skončilo – od září 2026 je aplikace <strong>i v App Store</strong> pro iPhone. Stačí v obchodě vyhledat „MotoGo24“.$t$),
    ('4185202a-9c04-4101-a098-423b7cd3ade7', 'excerpt', $t$Aplikace MotoGo24 je ke stažení na Google Play i v App Store.$t$),
    ('c3356f4a-e608-4bca-b16d-dcee9dc6c101', 'content', 'MotoGo24 (Google Play pro Android i App Store pro iPhone).'),
    ('4d86e5bb-fa8d-49b6-bcce-be8f5efa7679', 'excerpt', ''),
    ('5ec9affa-b1e6-48c4-8d3f-a3ee1be22acc', 'content', '')
    ) AS g(id, field, gate) USING (id, field)
    ORDER BY (x.lang <> 'cs')            -- čeština první
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.cms_pages
         SET content = CASE WHEN f.field = 'content' THEN replace(content, f.old_txt, f.new_txt) ELSE content END,
             excerpt = CASE WHEN f.field = 'excerpt' THEN replace(excerpt, f.old_txt, f.new_txt) ELSE excerpt END
       WHERE id = f.id::uuid
         AND strpos(CASE WHEN f.field = 'content' THEN content ELSE excerpt END, f.old_txt) > 0
         AND strpos(CASE WHEN f.field = 'content' THEN content ELSE excerpt END, f.new_txt) = 0;
    ELSE
      UPDATE public.cms_pages
         SET translations = jsonb_set(translations, ARRAY[f.lang, f.field],
               to_jsonb(replace(translations -> f.lang ->> f.field, f.old_txt, f.new_txt)))
       WHERE id = f.id::uuid
         AND strpos(CASE WHEN f.field = 'content' THEN content ELSE excerpt END, f.gate) > 0
         AND jsonb_typeof(translations -> f.lang) = 'object'
         AND strpos(translations -> f.lang ->> f.field, f.old_txt) > 0
         AND strpos(translations -> f.lang ->> f.field, f.new_txt) = 0;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT CASE WHEN f.lang = 'cs' THEN (CASE WHEN f.field = 'content' THEN content ELSE excerpt END)
                  ELSE translations -> f.lang ->> f.field END,
             CASE WHEN f.field = 'content' THEN content ELSE excerpt END
        INTO v_cur, v_cs FROM public.cms_pages WHERE id = f.id::uuid;
      IF strpos(coalesce(v_cur, ''), f.new_txt) > 0 THEN
        n_done := n_done + 1;
      ELSIF f.lang <> 'cs' AND strpos(coalesce(v_cs, ''), f.gate) = 0 THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'blog_app: cms_pages % % [%] PŘESKOČENO – české pole „%“ nemá nové znění (upraveno ve Velínu?), překlad ponechán', f.id, f.field, f.lang, f.field;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'blog_app: cms_pages % % [%] PŘESKOČENO – původní věta v textu není (upraveno ve Velínu?)', f.id, f.field, f.lang;
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'blog_app: cms_pages upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
