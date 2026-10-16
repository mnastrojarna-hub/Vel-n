-- =============================================================================
-- 20261015o_owner_texts_overlay_home_pujcovna.sql
-- datová migrace (bez změn schématu): cizí jazyky úvodní stránky (krok 3, rozcestník) a /pujcovna (FAQ appka).
--
-- Odpovědi majitele 2026-10-11/12: dvě pobočky – obslužná Mezná u Pelhřimova (odtud i přistavení
-- a odvoz) a samoobslužná Velké Němčice u Brna (převzetí i vrácení jen na pobočce, kódy z aplikace /
-- e-mailu); aplikace MotoGo24 je na Google Play (Android) i v App Store (iPhone).
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
    ('pages_overlay.home.en', '{process,steps,2,title}', 'full', 'f1e130064283373655c6ba94e3260d1e', '3. Pick up'),
    ('pages_overlay.home.de', '{process,steps,2,title}', 'full', 'e5ee045094eed7219fd350d23255dfc4', '3. Abholen'),
    ('pages_overlay.home.es', '{process,steps,2,title}', 'full', 'e128d2cf1aae3b75012d35ed92f8bd9d', $t$3. Recógela$t$),
    ('pages_overlay.home.fr', '{process,steps,2,title}', 'full', 'ef2c2df2837d0954647ec44bbd11d973', $t$3. Récupère$t$),
    ('pages_overlay.home.nl', '{process,steps,2,title}', 'full', '37cdb5a0f22c3865d7e488c0888817f2', '3. Ophalen'),
    ('pages_overlay.home.pl', '{process,steps,2,title}', 'full', '2b75b126ad594a15839eb61794f7a4b3', '3. Odbierz'),
    ('pages_overlay.home.en', '{process,steps,2,text}', 'full', 'fbc789211b9084ff46fc4b5cc55382af', $t$Pick up the bike in person in Mezná near Pelhřimov (we can also deliver it anywhere in the Czech Republic from there), or collect it yourself at the self-service branch in Velké Němčice near Brno.$t$),
    ('pages_overlay.home.de', '{process,steps,2,text}', 'full', '3a93ea0ebdf4ed7f08ed4b3bbaaeec7f', $t$Hol das Motorrad persönlich in Mezná bei Pelhřimov ab (von dort liefern wir es auch überallhin in Tschechien) oder selbst an der Selbstbedienungsfiliale in Velké Němčice bei Brno.$t$),
    ('pages_overlay.home.es', '{process,steps,2,text}', 'full', 'c0a145519210d48d58ca94a4b655a418', $t$Recoge la moto en persona en Mezná, cerca de Pelhřimov (desde allí también te la llevamos a cualquier lugar de la República Checa), o tú mismo en la sucursal de autoservicio de Velké Němčice, cerca de Brno.$t$),
    ('pages_overlay.home.fr', '{process,steps,2,text}', 'full', '2af5614935e352fb0276b73fc48041c2', $t$Récupère la moto en personne à Mezná, près de Pelhřimov (d'où nous pouvons aussi la livrer partout en Tchéquie), ou toi-même à l'agence en libre-service de Velké Němčice, près de Brno.$t$),
    ('pages_overlay.home.nl', '{process,steps,2,text}', 'full', '8773af7983d794977e8b10e612503e8f', $t$Haal de motor persoonlijk op in Mezná bij Pelhřimov (van daaruit bezorgen we hem ook overal in Tsjechië) of zelf bij de zelfbedieningsvestiging in Velké Němčice bij Brno.$t$),
    ('pages_overlay.home.pl', '{process,steps,2,text}', 'full', '2bb73e2aab8a29729b896b137cb81bc6', $t$Odbierz motocykl osobiście w oddziale Mezná koło Pelhřimova (stamtąd dowieziemy go też w dowolne miejsce w Czechach) albo sam w samoobsługowym oddziale Velké Němčice koło Brna.$t$),
    ('pages_overlay.home.en', '{signposts,3,text}', 'full', 'd1a7078561d2da1877e5a5d28dfbc739', $t$Visit us in Mezná near Pelhřimov or at the self-service branch in Velké Němčice near Brno – or get in touch.$t$),
    ('pages_overlay.home.de', '{signposts,3,text}', 'full', '4d870631f200a502b2421bb74a731b1e', $t$Besuche uns in Mezná bei Pelhřimov oder an der Selbstbedienungsfiliale in Velké Němčice bei Brno – oder kontaktiere uns.$t$),
    ('pages_overlay.home.es', '{signposts,3,text}', 'full', 'ea51c5817d89702ee1ea142c292c2a8f', $t$Visítanos en Mezná, cerca de Pelhřimov, o en la sucursal de autoservicio de Velké Němčice, cerca de Brno – o ponte en contacto con nosotros.$t$),
    ('pages_overlay.home.fr', '{signposts,3,text}', 'full', '2045bf1bc604aeacface6bfff4764322', $t$Rends-nous visite à Mezná, près de Pelhřimov, ou à l'agence en libre-service de Velké Němčice, près de Brno – ou contacte-nous.$t$),
    ('pages_overlay.home.nl', '{signposts,3,text}', 'full', 'd428b712578fd0ab28b8f25ed350ffcb', $t$Bezoek ons in Mezná bij Pelhřimov of bij de zelfbedieningsvestiging in Velké Němčice bij Brno – of neem contact op.$t$),
    ('pages_overlay.home.pl', '{signposts,3,text}', 'full', 'b3c5fd5e0e59bf32a7076c25fb5d1c19', $t$Odwiedź nas w oddziale Mezná koło Pelhřimova lub w samoobsługowym oddziale Velké Němčice koło Brna – albo skontaktuj się z nami.$t$),
    ('pages_overlay.pujcovna.en', '{faq,items,0,a}', 'full', '516a143422ea446aec1e4c25b7a54d75', $t$You can book a bike through our online booking system right here on the website or in the MotoGo24 app, free on Google Play (Android) and the App Store (iPhone). Or get in touch by e-mail, phone or through our social media.$t$),
    ('pages_overlay.pujcovna.de', '{faq,items,0,a}', 'full', '98bdb1423b02fdbd7ca8049558048014', $t$Über unser Online-Buchungssystem direkt hier auf der Website oder in der MotoGo24-App, kostenlos bei Google Play (Android) und im App Store (iPhone). Oder melde dich per E-Mail, Telefon oder über unsere Social-Media-Kanäle.$t$),
    ('pages_overlay.pujcovna.es', '{faq,items,0,a}', 'full', '6b53724a2cbf570fa3dbf66a30310984', $t$Puedes reservar una moto con nuestro sistema de reserva online, aquí mismo en la web, o desde la app MotoGo24, gratis en Google Play (Android) y en el App Store (iPhone). Si lo prefieres, escríbenos por e-mail, llámanos o contáctanos por redes sociales.$t$),
    ('pages_overlay.pujcovna.fr', '{faq,items,0,a}', 'full', '6c1b6bf5e77a831cd65abd508d81a3e5', $t$Via notre système de réservation en ligne, directement ici sur le site, ou dans l'appli MotoGo24, gratuite sur Google Play (Android) et sur l'App Store (iPhone). Tu peux aussi nous contacter par e-mail, par téléphone ou sur nos réseaux sociaux.$t$),
    ('pages_overlay.pujcovna.nl', '{faq,items,0,a}', 'full', 'baa5d1314a8df471e8ab24cdb9c97dda', $t$Je kunt een motor reserveren via ons online reserveringssysteem direct hier op de site of in de MotoGo24-app, gratis in Google Play (Android) en in de App Store (iPhone). Of neem contact op via e-mail, telefoon of social media.$t$),
    ('pages_overlay.pujcovna.pl', '{faq,items,0,a}', 'full', '53a5f3d13f6d3ba3aaf8c96ef6914819', $t$Motocykl możesz zarezerwować przez nasz system rezerwacji online bezpośrednio na stronie albo w aplikacji MotoGo24 – za darmo w Google Play (Android) i w App Store (iPhone). Lub skontaktuj się z nami e-mailem, telefonicznie lub przez media społecznościowe.$t$)
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
        RAISE NOTICE 'overlay_home_pujcovna: % % PŘESKOČENO – text mezitím změněn: %', f.k, f.path, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'overlay_home_pujcovna: app_settings upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
