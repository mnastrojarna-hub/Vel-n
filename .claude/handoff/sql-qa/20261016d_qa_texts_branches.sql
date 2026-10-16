-- =============================================================================
-- 20261016d_qa_texts_branches.sql — NÁVRH ke schválení (QA brána 2026-10-16), neaplikováno
-- Pravidla majitele: převzetí na obou pobočkách (Mezná u Pelhřimova + samoobslužné Velké Němčice u Brna),
-- přistavení / vrácení jinde JEN u motorek z Mezné.
--  1) /jak-pujcit/co-v-cene „Nadstandardní služby za příplatek“: přistavení a vrácení jinde → „(u motorek z Mezné)“
--     – CMS cs + překlady en–pl, pages_overlay en–pl (= lang/pages_<jazyk>.php; uk bere PHP).
--  2) /oblasti/jihomoravsky-kraj: úvod + věta o samoobslužné pobočce Velké Němčice (cs + en–pl), oprava
--     „v rámci Jihomoravském kraje“ → „Jihomoravského kraje“ a 4 chyb strojového překladu úvodu
--     (de „Motorradreihe“, es „motocleta“, nl „een betrouwbare … verhuurbedrijf“, pl „przywozie“).
--  3) Osiřelé klíče web.postup.step.5.text (čte je jen CMS nástroj AI copilota): text = živý krok 5
--     web.jak_pujcit_postup.process.steps.4.text (cs + překlady) – místo „osobně v Pelhřimově, nebo přistavení“.
--  4) Blog „12 hlavních výhod MotoGo24“: odkaz motogo24.cz/motorky (404) → /katalog; v bodě 9 nový odstavec
--     o samoobslužné pobočce Velké Němčice (cs + en, es, fr, nl; de/pl/uk článek nepřeložen → zobrazí cs).
--
-- Bezpečnost: každý text se mění jen když má přesně ověřené znění z živé DB (stav 2026-10-16 po návrzích
-- sql/final 20261015*); překlad jen když čeština už má nové znění; co mezitím někdo upravil ve Velínu, se
-- přeskočí s NOTICE. Idempotentní (2. běh nic nezmění). Bez BEGIN/COMMIT.
-- Pořadí: za 20261016c (ta klíče web.postup.* a web.jak_pujcit_cena.gear.services.* vynechává).
-- =============================================================================
DO $$
DECLARE
  r record;
  n integer;
  n1 integer := 0; n2 integer := 0; n3 integer := 0; n4 integer := 0;
  v_cs text;
BEGIN
  -- 1a) CMS: čeština, pak překlady (jen když je čeština nová)
  FOR r IN SELECT * FROM (VALUES
    ($q$web.jak_pujcit_cena.gear.services.items.0$q$, 'cs', $q$- přistavení motorky na domluvené místo kamkoliv v ČR,$q$, $q$- přistavení motorky na domluvené místo kamkoliv v ČR (u motorek z obslužné pobočky v Mezné),$q$, $q$- přistavení motorky na domluvené místo kamkoliv v ČR (u motorek z obslužné pobočky v Mezné),$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.0$q$, 'en', $q$- motorcycle delivery to an agreed location anywhere in the Czech Republic,$q$, $q$- delivery of the bike to an agreed place anywhere in the Czech Republic (bikes from the staffed branch in Mezná),$q$, $q$- přistavení motorky na domluvené místo kamkoliv v ČR (u motorek z obslužné pobočky v Mezné),$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.0$q$, 'de', $q$- Bereitstellung des Motorrads an einem vereinbarten Ort überall in der Tschechischen Republik,$q$, $q$- Lieferung des Motorrads an einen vereinbarten Ort überall in Tschechien (Motorräder der Filiale mit Personal in Mezná),$q$, $q$- přistavení motorky na domluvené místo kamkoliv v ČR (u motorek z obslužné pobočky v Mezné),$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.0$q$, 'es', $q$- entrega de la motocicleta en el lugar acordado en cualquier parte de la República Checa,$q$, $q$- entrega de la moto en el lugar acordado, en cualquier punto de la República Checa (motos de la sucursal con personal de Mezná),$q$, $q$- přistavení motorky na domluvené místo kamkoliv v ČR (u motorek z obslužné pobočky v Mezné),$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.0$q$, 'fr', $q$- livraison de la moto au lieu convenu n'importe où en République tchèque,$q$, $q$- livraison de la moto à un endroit convenu, partout en Tchéquie (motos de l'agence avec personnel de Mezná),$q$, $q$- přistavení motorky na domluvené místo kamkoliv v ČR (u motorek z obslužné pobočky v Mezné),$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.0$q$, 'nl', $q$- bezorging van de motorfiets op een afgesproken locatie ergens in de Tsjechische Republiek,$q$, $q$- bezorging van de motor op een afgesproken plek overal in Tsjechië (motoren van de bemande vestiging in Mezná),$q$, $q$- přistavení motorky na domluvené místo kamkoliv v ČR (u motorek z obslužné pobočky v Mezné),$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.0$q$, 'pl', $q$- dostarczenie motocykla w uzgodnione miejsce w dowolnym miejscu w ČR,$q$, $q$- podstawienie motocykla w umówione miejsce w dowolnym punkcie Czech (motocykle z oddziału z obsługą w Mezná),$q$, $q$- přistavení motorky na domluvené místo kamkoliv v ČR (u motorek z obslužné pobočky v Mezné),$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.1$q$, 'cs', $q$- vrácení motorky jinam než na adresu půjčovny.$q$, $q$- vrácení motorky jinam než na pobočku (u motorek z Mezné).$q$, $q$- vrácení motorky jinam než na pobočku (u motorek z Mezné).$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.1$q$, 'en', $q$- returning the motorcycle at a different location than the rental address.$q$, $q$- returning the bike somewhere other than the branch (bikes from Mezná).$q$, $q$- vrácení motorky jinam než na pobočku (u motorek z Mezné).$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.1$q$, 'de', $q$- Rückgabe des Motorrads an einer anderen Adresse als der Mietstation.$q$, $q$- Rückgabe des Motorrads an einem anderen Ort als der Filiale (Motorräder aus Mezná).$q$, $q$- vrácení motorky jinam než na pobočku (u motorek z Mezné).$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.1$q$, 'es', $q$- devolver la motocicleta en un lugar diferente a la dirección del alquiler.$q$, $q$- devolución de la moto en un lugar distinto de la sucursal (motos de Mezná).$q$, $q$- vrácení motorky jinam než na pobočku (u motorek z Mezné).$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.1$q$, 'fr', $q$- retour de la moto à une adresse différente de celle de l'agence de location.$q$, $q$- restitution de la moto ailleurs qu'à l'agence (motos de Mezná).$q$, $q$- vrácení motorky jinam než na pobočku (u motorek z Mezné).$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.1$q$, 'nl', $q$- retournering van de motor op een ander adres dan het verhuuradres.$q$, $q$- de motor elders terugbrengen dan bij de vestiging (motoren uit Mezná).$q$, $q$- vrácení motorky jinam než na pobočku (u motorek z Mezné).$q$),
    ($q$web.jak_pujcit_cena.gear.services.items.1$q$, 'pl', $q$- zwrot motoroweru w innym miejscu niż adres wypożyczalni.$q$, $q$- zwrot motocykla w innym miejscu niż oddział (motocykle z Mezná).$q$, $q$- vrácení motorky jinam než na pobočku (u motorek z Mezné).$q$)
  ) AS v(key, lang, old, new, new_cs) LOOP
    IF r.lang = 'cs' THEN
      UPDATE public.cms_variables SET value = to_jsonb(r.new), updated_at = now()
       WHERE key = r.key AND value #>> '{}' = r.old;
    ELSE
      UPDATE public.cms_variables SET translations = jsonb_set(translations, ARRAY[r.lang, 'value'], to_jsonb(r.new)), updated_at = now()
       WHERE key = r.key AND value #>> '{}' = r.new_cs AND translations -> r.lang ->> 'value' = r.old;
    END IF;
    GET DIAGNOSTICS n = ROW_COUNT; n1 := n1 + n;
    IF n = 0 THEN RAISE NOTICE 'co-v-cene: beze změny % %', r.key, r.lang; END IF;
  END LOOP;
  -- 1b) pages_overlay (cizí jazyky, položky bez odrážky)
  FOR r IN SELECT * FROM (VALUES
    ($q$pages_overlay.jak_pujcit_cena.en$q$, 0, $q$motorcycle delivery to agreed location anywhere in the Czech Republic$q$, $q$delivery of the bike to an agreed place anywhere in the Czech Republic (bikes from the staffed branch in Mezná)$q$),
    ($q$pages_overlay.jak_pujcit_cena.en$q$, 1, $q$motorcycle return to a different location than the rental office$q$, $q$returning the bike somewhere other than the branch (bikes from Mezná)$q$),
    ($q$pages_overlay.jak_pujcit_cena.de$q$, 0, $q$Anlieferung des Motorrads an einem vereinbarten Ort überall in der Tschechischen Republik$q$, $q$Lieferung des Motorrads an einen vereinbarten Ort überall in Tschechien (Motorräder der Filiale mit Personal in Mezná)$q$),
    ($q$pages_overlay.jak_pujcit_cena.de$q$, 1, $q$Rückgabe des Motorrads an einem anderen Ort als der Adresse des Verleihs$q$, $q$Rückgabe des Motorrads an einem anderen Ort als der Filiale (Motorräder aus Mezná)$q$),
    ($q$pages_overlay.jak_pujcit_cena.es$q$, 0, $q$entrega de la moto en el lugar acordado en cualquier parte de la República Checa$q$, $q$entrega de la moto en el lugar acordado, en cualquier punto de la República Checa (motos de la sucursal con personal de Mezná)$q$),
    ($q$pages_overlay.jak_pujcit_cena.es$q$, 1, $q$devolución de la moto en un lugar diferente al de la agencia de alquiler$q$, $q$devolución de la moto en un lugar distinto de la sucursal (motos de Mezná)$q$),
    ($q$pages_overlay.jak_pujcit_cena.fr$q$, 0, $q$livraison de la moto à l'endroit convenu n'importe où en République Tchèque$q$, $q$livraison de la moto à un endroit convenu, partout en Tchéquie (motos de l'agence avec personnel de Mezná)$q$),
    ($q$pages_overlay.jak_pujcit_cena.fr$q$, 1, $q$retour de la moto à un autre endroit que l'adresse de la location$q$, $q$restitution de la moto ailleurs qu'à l'agence (motos de Mezná)$q$),
    ($q$pages_overlay.jak_pujcit_cena.nl$q$, 0, $q$levering van de motorfiets op een afgesproken locatie overal in Tsjechië$q$, $q$bezorging van de motor op een afgesproken plek overal in Tsjechië (motoren van de bemande vestiging in Mezná)$q$),
    ($q$pages_overlay.jak_pujcit_cena.nl$q$, 1, $q$retournering van de motorfiets op een ander adres dan het adres van de verhuurkantoor$q$, $q$de motor elders terugbrengen dan bij de vestiging (motoren uit Mezná)$q$),
    ($q$pages_overlay.jak_pujcit_cena.pl$q$, 0, $q$dostarczenie motocykla na uzgodnione miejsce w dowolnym miejscu w Czechach$q$, $q$podstawienie motocykla w umówione miejsce w dowolnym punkcie Czech (motocykle z oddziału z obsługą w Mezná)$q$),
    ($q$pages_overlay.jak_pujcit_cena.pl$q$, 1, $q$zwrot motocykla w innym miejscu niż adres wypożyczalni$q$, $q$zwrot motocykla w innym miejscu niż oddział (motocykle z Mezná)$q$)
  ) AS v(key, idx, old, new) LOOP
    UPDATE public.app_settings SET value = jsonb_set(value, ARRAY['gear', 'services', 'items', r.idx::text], to_jsonb(r.new))
     WHERE key = r.key AND value -> 'gear' -> 'services' -> 'items' ->> r.idx = r.old;
    GET DIAGNOSTICS n = ROW_COUNT; n1 := n1 + n;
    IF n = 0 THEN RAISE NOTICE 'co-v-cene overlay: beze změny % %', r.key, r.idx; END IF;
  END LOOP;

  -- 2) Jihomoravský kraj
  UPDATE public.cms_variables SET value = to_jsonb(replace(value #>> '{}', 'v rámci Jihomoravském kraje', 'v rámci Jihomoravského kraje')), updated_at = now()
   WHERE key = 'web.oblasti.region.jihomoravsky_kraj.citiesIntro' AND strpos(value #>> '{}', 'v rámci Jihomoravském kraje') > 0;
  GET DIAGNOSTICS n = ROW_COUNT; n2 := n2 + n;
  FOR r IN SELECT * FROM (VALUES
    ('de', $q$<strong>Motorradreihe in der Region Südmähren</strong>$q$, $q$<strong>Motorradvermietung in der Region Südmähren</strong>$q$),
    ('es', $q$<strong>motocleta de alquiler confiable en la región de Moravia del Sur</strong>$q$, $q$<strong>alquiler de motos fiable en la región de Moravia del Sur</strong>$q$),
    ('nl', $q$een betrouwbare <strong>motorfietsverhuurbedrijf in de regio Zuid-Moravië</strong>$q$, $q$een betrouwbaar <strong>motorverhuurbedrijf in de regio Zuid-Moravië</strong>$q$),
    ('pl', $q$MotoGo24 przywozie i postawi$q$, $q$MotoGo24 przywiezie i podstawi$q$)
  ) AS v(lang, old, new) LOOP
    UPDATE public.cms_variables SET translations = jsonb_set(translations, ARRAY[r.lang, 'value'], to_jsonb(replace(translations -> r.lang ->> 'value', r.old, r.new))), updated_at = now()
     WHERE key = 'web.oblasti.region.jihomoravsky_kraj.intro' AND strpos(translations -> r.lang ->> 'value', r.old) > 0;
    GET DIAGNOSTICS n = ROW_COUNT; n2 := n2 + n;
  END LOOP;
  UPDATE public.cms_variables
     SET value = to_jsonb(regexp_replace(value #>> '{}', '(\s|&nbsp;)+$', '') || ' ' || $q$V Jihomoravském kraji si motorku můžeš vyzvednout i sám na naší samoobslužné pobočce ve Velkých Němčicích u Brna (nonstop, kódem z aplikace nebo e-mailu); přistavení nabízíme u motorek z Mezné.$q$), updated_at = now()
   WHERE key = 'web.oblasti.region.jihomoravsky_kraj.intro' AND jsonb_typeof(value) = 'string'
     AND strpos(value #>> '{}', 'Němčic') = 0;
  GET DIAGNOSTICS n = ROW_COUNT; n2 := n2 + n;
  SELECT value #>> '{}' INTO v_cs FROM public.cms_variables WHERE key = 'web.oblasti.region.jihomoravsky_kraj.intro';
  IF strpos(coalesce(v_cs, ''), $q$V Jihomoravském kraji si motorku můžeš vyzvednout i sám na naší samoobslužné pobočce ve Velkých Němčicích u Brna (nonstop, kódem z aplikace nebo e-mailu); přistavení nabízíme u motorek z Mezné.$q$) > 0 THEN
    FOR r IN SELECT * FROM (VALUES
    ('en', $q$In the South Moravian Region you can also pick up a bike yourself at our self-service branch in Velké Němčice near Brno (24/7, with a code from the app or e-mail); delivery is available for bikes from Mezná.$q$),
    ('de', $q$In der Region Südmähren kannst du ein Motorrad auch selbst in unserer Selbstbedienungsfiliale in Velké Němčice bei Brno abholen (rund um die Uhr, mit einem Code aus der App oder E-Mail); die Lieferung bieten wir für Motorräder aus Mezná an.$q$),
    ('es', $q$En la región de Moravia del Sur también puedes recoger la moto tú mismo en nuestra sucursal de autoservicio de Velké Němčice, cerca de Brno (24/7, con un código de la app o del correo electrónico); la entrega la ofrecemos para las motos de Mezná.$q$),
    ('fr', $q$En Moravie-du-Sud, tu peux aussi retirer une moto toi-même dans notre agence en libre-service de Velké Němčice près de Brno (24h/24, avec un code de l'application ou de l'e-mail) ; la livraison est proposée pour les motos de Mezná.$q$),
    ('nl', $q$In de regio Zuid-Moravië kun je een motor ook zelf ophalen bij onze zelfbedieningsvestiging in Velké Němčice bij Brno (24/7, met een code uit de app of de e-mail); bezorging bieden we aan voor motoren uit Mezná.$q$),
    ('pl', $q$W kraju południowomorawskim możesz też sam odebrać motocykl w naszym samoobsługowym oddziale w Velké Němčice koło Brna (całodobowo, z kodem z aplikacji lub e-maila); podstawienie oferujemy dla motocykli z Mezná.$q$)
    ) AS v(lang, sent) LOOP
      UPDATE public.cms_variables
         SET translations = jsonb_set(translations, ARRAY[r.lang, 'value'],
               to_jsonb(regexp_replace(translations -> r.lang ->> 'value', '(\s|&nbsp;)+$', '') || ' ' || r.sent)), updated_at = now()
       WHERE key = 'web.oblasti.region.jihomoravsky_kraj.intro'
         AND jsonb_typeof(translations -> r.lang -> 'value') = 'string'
         AND strpos(translations -> r.lang ->> 'value', 'Němčic') = 0;
      GET DIAGNOSTICS n = ROW_COUNT; n2 := n2 + n;
    END LOOP;
  ELSE
    RAISE NOTICE 'jihomoravsky_kraj.intro: čeština bez věty o Velkých Němčicích (upravena ve Velínu?) – překlady beze změny';
  END IF;

  -- 3) web.postup.step.5.text = živý krok 5 (web.jak_pujcit_postup.process.steps.4.text)
  UPDATE public.cms_variables o
     SET value = s.value, translations = s.translations, updated_at = now()
    FROM public.cms_variables s
   WHERE o.key = 'web.postup.step.5.text' AND s.key = 'web.jak_pujcit_postup.process.steps.4.text'
     AND o.value #>> '{}' = 'Vyber způsob převzetí - osobně v Pelhřimově, nebo přistavení kamkoliv v ČR.'
     AND strpos(s.value #>> '{}', 'Němčic') > 0;
  GET DIAGNOSTICS n3 = ROW_COUNT;

  -- 4) Blog „12 hlavních výhod MotoGo24“
  UPDATE public.cms_pages SET content = replace(content, 'https://www.motogo24.cz/motorky', 'https://www.motogo24.cz/katalog')
   WHERE slug = '12-hlavnich-vyhod-motogo24' AND strpos(content, 'https://www.motogo24.cz/motorky') > 0;
  GET DIAGNOSTICS n = ROW_COUNT; n4 := n4 + n;
  UPDATE public.cms_pages p
     SET translations = (SELECT jsonb_object_agg(l, CASE WHEN jsonb_typeof(v -> 'content') = 'string'
                                   THEN jsonb_set(v, '{content}', to_jsonb(replace(v ->> 'content', 'https://www.motogo24.cz/motorky', 'https://www.motogo24.cz/katalog')))
                                   ELSE v END)
                           FROM jsonb_each(p.translations) AS e(l, v))
   WHERE slug = '12-hlavnich-vyhod-motogo24' AND strpos(translations::text, 'https://www.motogo24.cz/motorky') > 0;
  GET DIAGNOSTICS n = ROW_COUNT; n4 := n4 + n;
  FOR r IN SELECT * FROM (VALUES
    ('cs', $q$A od září 2026 si motorku můžeš vyzvednout i sám, nonstop, na naší samoobslužné pobočce ve Velkých Němčicích u Brna.$q$),
    ('en', $q$And since September 2026 you can also pick up a bike yourself, 24/7, at our self-service branch in Velké Němčice near Brno.$q$),
    ('es', $q$Y desde septiembre de 2026 también puedes recoger la moto tú mismo, las 24 horas, en nuestra sucursal de autoservicio de Velké Němčice, cerca de Brno.$q$),
    ('fr', $q$Et depuis septembre 2026, tu peux aussi retirer une moto toi-même, 24h/24, dans notre agence en libre-service de Velké Němčice près de Brno.$q$),
    ('nl', $q$En sinds september 2026 kun je een motor ook zelf ophalen, 24/7, bij onze zelfbedieningsvestiging in Velké Němčice bij Brno.$q$)
  ) AS v(lang, sent) LOOP
    IF r.lang = 'cs' THEN
      UPDATE public.cms_pages
         SET content = replace(content, '</h2><h2><span style="font-size: medium;">10.',
               '<p style="margin-bottom: 8.0pt; line-height: 133%"><span style="font-size: small; font-weight: normal;">' || r.sent || E'</span></p>\n\n</h2><h2><span style="font-size: medium;">10.')
       WHERE slug = '12-hlavnich-vyhod-motogo24' AND strpos(content, 'Němčic') = 0
         AND (length(content) - length(replace(content, '</h2><h2><span style="font-size: medium;">10.', ''))) = length('</h2><h2><span style="font-size: medium;">10.');
    ELSE
      UPDATE public.cms_pages
         SET translations = jsonb_set(translations, ARRAY[r.lang, 'content'], to_jsonb(replace(translations -> r.lang ->> 'content',
               '</h2><h2><span style="font-size: medium;">10.',
               '<p style="margin-bottom: 8.0pt; line-height: 133%"><span style="font-size: small; font-weight: normal;">' || r.sent || E'</span></p>\n\n</h2><h2><span style="font-size: medium;">10.')))
       WHERE slug = '12-hlavnich-vyhod-motogo24' AND strpos(content, 'Němčic') > 0
         AND jsonb_typeof(translations -> r.lang -> 'content') = 'string'
         AND strpos(translations -> r.lang ->> 'content', 'Němčic') = 0
         AND (length(translations -> r.lang ->> 'content') - length(replace(translations -> r.lang ->> 'content', '</h2><h2><span style="font-size: medium;">10.', '')))
             = length('</h2><h2><span style="font-size: medium;">10.');
    END IF;
    GET DIAGNOSTICS n = ROW_COUNT; n4 := n4 + n;
    IF n = 0 THEN RAISE NOTICE 'blog 12 výhod: odstavec Velké Němčice beze změny (%)', r.lang; END IF;
  END LOOP;

  RAISE NOTICE 'qa_texts_branches: co-v-cene %, jihomoravský kraj %, web.postup %, blog %', n1, n2, n3, n4;
END $$;
