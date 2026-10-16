-- =============================================================================
-- 20261015zb_owner_texts_pobocky_preklady_7.sql
-- datová migrace (bez změn schématu): překlady textů poboček pro appku (web.pobocky.*) (část 7/7).
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
    ('web.pobocky.intro', 'fr', 'fill', NULL, $t$Tu peux récupérer ta moto à <strong>deux endroits</strong> : à l'<strong>agence avec personnel de Mezná, près de Pelhřimov</strong>, où nous t'accueillons en personne, ou à l'<strong>agence en libre-service de Velké Němčice, près de Brno</strong>, où tu récupères toi-même la moto et l'équipement grâce à des codes.$t$),
    ('web.pobocky.intro', 'nl', 'fill', NULL, $t$Je kunt je motor op <strong>twee plekken</strong> ophalen: bij de <strong>bemande vestiging in Mezná bij Pelhřimov</strong>, waar we je persoonlijk ontvangen, of bij de <strong>zelfbedieningsvestiging in Velké Němčice bij Brno</strong>, waar je de motor en de uitrusting zelf ophaalt met codes.$t$),
    ('web.pobocky.intro', 'pl', 'fill', NULL, $t$Motocykl odbierzesz w <strong>dwóch miejscach</strong>: w <strong>oddziale z obsługą Mezná koło Pelhřimova</strong>, gdzie przywitamy cię osobiście, lub w <strong>oddziale samoobsługowym Velké Němčice koło Brna</strong>, gdzie motocykl i wyposażenie odbierasz samodzielnie za pomocą kodów.$t$),
    ('web.pobocky.intro', 'uk', 'fill', NULL, $t$Мотоцикл можна забрати у <strong>двох місцях</strong>: у <strong>філії з персоналом у Mezná біля Пельгржимова</strong>, де ми зустрінемо тебе особисто, або у <strong>філії самообслуговування Velké Němčice біля Брна</strong>, де мотоцикл і екіпірування ти забираєш самостійно за кодами.$t$)
    ) AS x(k, lang, how, old, new)
    JOIN (VALUES
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
