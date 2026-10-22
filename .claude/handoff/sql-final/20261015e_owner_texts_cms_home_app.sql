-- =============================================================================
-- 20261015e_owner_texts_cms_home_app.sql
-- datová migrace (bez změn schématu): Velín CMS – úvodní stránka (krok 3, rozcestník) a FAQ /pujcovna (appka v obou obchodech).
--
-- Odpovědi majitele 2026-10-11/12: dvě pobočky – obslužná Mezná u Pelhřimova (odtud i přistavení
-- a odvoz) a samoobslužná Velké Němčice u Brna (převzetí i vrácení jen na pobočce, kódy z aplikace /
-- e-mailu); aplikace MotoGo24 je na Google Play (Android) i v App Store (iPhone).
--
-- web.home.process.steps.2.text/.title, web.home.signposts.3.text, web.pujcovna.faq.items.0.a.
-- Překlady = lang/pages_<jazyk>.php. Česká úvodní stránka je ve Velínu psaná tykáním, proto česká
-- hodnota = tykací znění PHP textu (home.php má vykání); nadpis „3. Převezmi“ zůstává, opravují se
-- jen chybné překlady („3. I'll take it“, „3. Ich werde abholen“ …).
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
    ('web.home.process.steps.2.text', 'cs', 'full', '1beea6434848bcc3277b5861fff99650', $t$Převezmi si motorku osobně v Mezné u Pelhřimova (odtud ti ji můžeme i přistavit kamkoli v ČR), nebo si ji vyzvedni sám na samoobslužné pobočce ve Velkých Němčicích u Brna.$t$),
    ('web.home.process.steps.2.text', 'de', 'full', '622d354e2ac8be6daac51cbe0d520f67', $t$Hol das Motorrad persönlich in Mezná bei Pelhřimov ab (von dort liefern wir es auch überallhin in Tschechien) oder selbst an der Selbstbedienungsfiliale in Velké Němčice bei Brno.$t$),
    ('web.home.process.steps.2.text', 'en', 'full', 'cbd77887593d998ec86768ea57c02034', $t$Pick up the bike in person in Mezná near Pelhřimov (we can also deliver it anywhere in the Czech Republic from there), or collect it yourself at the self-service branch in Velké Němčice near Brno.$t$),
    ('web.home.process.steps.2.text', 'es', 'full', '1debbdb722876b9350fb1e6e39c02e5d', $t$Recoge la moto en persona en Mezná, cerca de Pelhřimov (desde allí también te la llevamos a cualquier lugar de la República Checa), o tú mismo en la sucursal de autoservicio de Velké Němčice, cerca de Brno.$t$),
    ('web.home.process.steps.2.text', 'fr', 'full', '26f8396daf20758d121575fb98537ce9', $t$Récupère la moto en personne à Mezná, près de Pelhřimov (d'où nous pouvons aussi la livrer partout en Tchéquie), ou toi-même à l'agence en libre-service de Velké Němčice, près de Brno.$t$),
    ('web.home.process.steps.2.text', 'nl', 'full', '33e8f5dcaafa7e4c5879646ef4843d89', $t$Haal de motor persoonlijk op in Mezná bij Pelhřimov (van daaruit bezorgen we hem ook overal in Tsjechië) of zelf bij de zelfbedieningsvestiging in Velké Němčice bij Brno.$t$),
    ('web.home.process.steps.2.text', 'pl', 'full', '1215fe1f83900ffa32af157c9b2d378f', $t$Odbierz motocykl osobiście w oddziale Mezná koło Pelhřimova (stamtąd dowieziemy go też w dowolne miejsce w Czechach) albo sam w samoobsługowym oddziale Velké Němčice koło Brna.$t$),
    ('web.home.process.steps.2.title', 'de', 'full', 'f9696471ad97e88ce1e4763b1f55b0c8', '3. Abholen'),
    ('web.home.process.steps.2.title', 'en', 'full', 'f5e77cc4a5c9c58ce4f9077977935bb2', '3. Pick up'),
    ('web.home.process.steps.2.title', 'es', 'full', '39a3946eee33eb73d04d997a1fffe2be', $t$3. Recógela$t$),
    ('web.home.process.steps.2.title', 'fr', 'full', 'f440dd1b7cc2f232afc0b7d6e7429e35', $t$3. Récupère$t$),
    ('web.home.process.steps.2.title', 'nl', 'full', '5c50562dd5d6440b0f9efeabbf67bd45', '3. Ophalen'),
    ('web.home.process.steps.2.title', 'pl', 'full', 'd51cd60563f4eed3eb0a6d6997fe0d7b', '3. Odbierz'),
    ('web.home.signposts.3.text', 'cs', 'full', '3be4b2abadfb1e122c2e8d634217fa59', $t$Navštiv nás v Mezné u Pelhřimova nebo na samoobslužné pobočce ve Velkých Němčicích u Brna – případně nás kontaktuj.$t$),
    ('web.home.signposts.3.text', 'de', 'full', '4a30c38cccdd1e7948c353065e72b400', $t$Besuche uns in Mezná bei Pelhřimov oder an der Selbstbedienungsfiliale in Velké Němčice bei Brno – oder kontaktiere uns.$t$),
    ('web.home.signposts.3.text', 'en', 'full', 'dc0cfd8a6e8953f4a16f203600c41d1b', $t$Visit us in Mezná near Pelhřimov or at the self-service branch in Velké Němčice near Brno – or get in touch.$t$),
    ('web.home.signposts.3.text', 'es', 'full', '45becf857c7c41cddd878170c24067ec', $t$Visítanos en Mezná, cerca de Pelhřimov, o en la sucursal de autoservicio de Velké Němčice, cerca de Brno – o ponte en contacto con nosotros.$t$),
    ('web.home.signposts.3.text', 'fr', 'full', 'b8f99ef3d6f8465b83e865b902912e9b', $t$Rends-nous visite à Mezná, près de Pelhřimov, ou à l'agence en libre-service de Velké Němčice, près de Brno – ou contacte-nous.$t$),
    ('web.home.signposts.3.text', 'nl', 'full', '0a3026e287f39b1600575a37550b9627', $t$Bezoek ons in Mezná bij Pelhřimov of bij de zelfbedieningsvestiging in Velké Němčice bij Brno – of neem contact op.$t$),
    ('web.home.signposts.3.text', 'pl', 'full', '35e71ecd0f433c5dc3837576e8e30e54', $t$Odwiedź nas w oddziale Mezná koło Pelhřimova lub w samoobsługowym oddziale Velké Němčice koło Brna – albo skontaktuj się z nami.$t$),
    ('web.home.signposts.3.text', 'uk', 'full', '3553761a68093a0836ac9bb6fcd0bd5c', $t$Завітайте до нас у Mezná біля Пельгржимова або у філію самообслуговування Velké Němčice біля Брна – чи зв’яжіться з нами.$t$),
    ('web.pujcovna.faq.items.0.a', 'cs', 'full', 'a876898df6b7ff32129640ca74addcfc', $t$Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu nebo v aplikaci MotoGo24, která je zdarma na Google Play (Android) i v App Store (iPhone). Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.$t$),
    ('web.pujcovna.faq.items.0.a', 'de', 'full', '061c87fc7f3fd323ee0dddda612d57e5', $t$Über unser Online-Buchungssystem direkt hier auf der Website oder in der MotoGo24-App, kostenlos bei Google Play (Android) und im App Store (iPhone). Oder melde dich per E-Mail, Telefon oder über unsere Social-Media-Kanäle.$t$),
    ('web.pujcovna.faq.items.0.a', 'en', 'full', '19ff33e36a361858ca5c686165108efa', $t$You can book a bike through our online booking system right here on the website or in the MotoGo24 app, free on Google Play (Android) and the App Store (iPhone). Or get in touch by e-mail, phone or through our social media.$t$),
    ('web.pujcovna.faq.items.0.a', 'es', 'full', '63852021539cb7a4b120f843d3a469f2', $t$Puedes reservar una moto con nuestro sistema de reserva online, aquí mismo en la web, o desde la app MotoGo24, gratis en Google Play (Android) y en el App Store (iPhone). Si lo prefieres, escríbenos por e-mail, llámanos o contáctanos por redes sociales.$t$),
    ('web.pujcovna.faq.items.0.a', 'fr', 'full', 'c6eaf73bfac71f78172d582e235acd34', $t$Via notre système de réservation en ligne, directement ici sur le site, ou dans l'appli MotoGo24, gratuite sur Google Play (Android) et sur l'App Store (iPhone). Tu peux aussi nous contacter par e-mail, par téléphone ou sur nos réseaux sociaux.$t$),
    ('web.pujcovna.faq.items.0.a', 'nl', 'full', '58fbce6c789be1220e1355973c8244ac', $t$Je kunt een motor reserveren via ons online reserveringssysteem direct hier op de site of in de MotoGo24-app, gratis in Google Play (Android) en in de App Store (iPhone). Of neem contact op via e-mail, telefoon of social media.$t$),
    ('web.pujcovna.faq.items.0.a', 'pl', 'full', '9d2eb37caa758d6454da76726c5fdaa5', $t$Motocykl możesz zarezerwować przez nasz system rezerwacji online bezpośrednio na stronie albo w aplikacji MotoGo24 – za darmo w Google Play (Android) i w App Store (iPhone). Lub skontaktuj się z nami e-mailem, telefonicznie lub przez media społecznościowe.$t$),
    ('web.pujcovna.faq.items.0.a', 'uk', 'full', 'c8932bfab04be92e4a32973177dfb610', $t$Мотоцикл можеш забронювати через нашу онлайн-систему бронювання прямо тут, на сайті, або в застосунку MotoGo24 – безкоштовно в Google Play (Android) і в App Store (iPhone). Або ж можеш зв’язатися з нами e-mailом, телефоном чи через наші соціальні мережі.$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
    ('web.home.process.steps.2.text', 'b52b2a35bb052f09b13bd08cacb4b17a'),
    ('web.home.process.steps.2.title', '9952c42365b9f46b1acec4df3ae37104'),
    ('web.home.signposts.3.text', '2cc626d8fb3da7fec66a2e2a82393792'),
    ('web.pujcovna.faq.items.0.a', '29db9d44e72217192ba96728d359a265')
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
        RAISE NOTICE 'cms_home_app: % [%] PŘESKOČENO – česká hodnota není v očekávaném znění, překlad ponechán', f.k, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'cms_home_app: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', f.k, f.lang, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'cms_home_app: cms_variables upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
