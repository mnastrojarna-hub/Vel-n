-- =============================================================================
-- 20261015i_owner_texts_faq_app.sql
-- datová migrace (bez změn schématu): FAQ – aplikace na Google Play i v App Store.
--
-- Odpovědi majitele 2026-10-11/12: dvě pobočky – obslužná Mezná u Pelhřimova (odtud i přistavení
-- a odvoz) a samoobslužná Velké Němčice u Brna (převzetí i vrácení jen na pobočce, kódy z aplikace /
-- e-mailu); aplikace MotoGo24 je na Google Play (Android) i v App Store (iPhone).
--
-- 9eb4103e „Jak si mohu rezervovat motorku?“ (na úvodní stránce) zmiňuje aplikaci bez obchodů → doplněno
-- „zdarma na Google Play pro Android i v App Store pro iPhone“ (cs + všechny překlady).
-- 57912624 „Máte věrnostní program?“ (zmiňuje oba obchody) – doplněna chybějící uk.
-- es všude „el App Store“ (jako Apple, web i e-maily): 9eb4103e, 9d0038c0, bff7565d, 57912624;
-- de 7c27d75f „Treurabatte“ → „Treuerabatte“ (jen ty věty, česká odpověď beze změny).
--
-- Bezpečnost: mění JEN text ve znění ověřeném proti živé DB (stav 2026-10-15); co mezitím
-- někdo upravil ve Velínu, se přeskočí s NOTICE. Idempotentní (2. běh nic nezmění). Bez
-- BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================

-- updated_at nastaví trigger faq_items_set_updated_at.
DO $$
DECLARE
  f record;
  cnt integer;
  v_cur text;
  v_ans text;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  -- x: id, pole (question/answer), jazyk ('cs' = sloupec, jinak translations.<jazyk>), how + old:
  --      'full'   = celý živý text má otisk md5 = old (ověřený stav 2026-10-15) → nahradí se celý
  --      'phrase' = věta old (v živém textu jednou) se nahradí new, zbytek textu zůstává
  --      'fill'   = překlad chybí → doplní se
  -- g: brána – překlad se mění jen když česká odpověď má otisk md5 = gate (nové / ověřené české znění)
  FOR f IN
    SELECT x.*, g.gate FROM (VALUES
    ('9eb4103e-9c51-4813-bc5e-73e5d2ba990d', 'answer', 'cs', 'phrase', $t$nebo v naší aplikaci</span>.$t$, $t$nebo v naší aplikaci</span> (zdarma na Google Play pro Android i v App Store pro iPhone).$t$),
    ('9eb4103e-9c51-4813-bc5e-73e5d2ba990d', 'answer', 'de', 'phrase', 'oder in unserer App</span>.', $t$oder in unserer App</span> (kostenlos bei Google Play für Android und im App Store für iPhone).$t$),
    ('9eb4103e-9c51-4813-bc5e-73e5d2ba990d', 'answer', 'en', 'phrase', 'or in our app</span>.', $t$or in our app</span> (free on Google Play for Android and the App Store for iPhone).$t$),
    ('9eb4103e-9c51-4813-bc5e-73e5d2ba990d', 'answer', 'es', 'phrase', $t$o en nuestra aplicación</span>.$t$, $t$o en nuestra aplicación</span> (gratis en Google Play para Android y en el App Store para iPhone).$t$),
    ('9eb4103e-9c51-4813-bc5e-73e5d2ba990d', 'answer', 'fr', 'phrase', 'ou dans notre application</span>.', $t$ou dans notre application</span> (gratuite sur Google Play pour Android et sur l'App Store pour iPhone).$t$),
    ('9eb4103e-9c51-4813-bc5e-73e5d2ba990d', 'answer', 'nl', 'phrase', 'of in onze app</span>.', $t$of in onze app</span> (gratis via Google Play voor Android en in de App Store voor iPhone).$t$),
    ('9eb4103e-9c51-4813-bc5e-73e5d2ba990d', 'answer', 'pl', 'phrase', 'lub w naszej aplikacji</span>.', $t$lub w naszej aplikacji</span> (bezpłatnie w Google Play na Androida i w App Store na iPhone'a).$t$),
    ('9eb4103e-9c51-4813-bc5e-73e5d2ba990d', 'answer', 'uk', 'phrase', $t$або в нашій програмі</span>.$t$, $t$або в нашій програмі</span> (безкоштовно в Google Play для Android і в App Store для iPhone).$t$),
    ('57912624-b5dd-4412-bbcc-e20d9c7a5938', 'question', 'uk', 'fill', NULL, $t$У вас є програма лояльності?$t$),
    ('57912624-b5dd-4412-bbcc-e20d9c7a5938', 'answer', 'uk', 'fill', NULL, $t$<p>Так! Програма лояльності є частиною нашого нового мобільного застосунку — збираєш у ньому винагороди за свої бронювання й поступово отримуєш переваги для наступних поїздок. Застосунок знайдеш у Google Play (Android) і в App Store (iPhone), тож обов’язково його спробуй.</p>
<p>І думаємо про тебе й поза застосунком — як подяку за бронювання надсилаємо тобі знижку 200 Kč на наступну оренду.</p>$t$),
    ('9d0038c0-0839-4485-a900-123c816b98af', 'answer', 'es', 'phrase', 'y en la App Store (iPhone)', 'y en el App Store (iPhone)'),
    ('bff7565d-63c4-44ab-9b3f-54274af813bc', 'answer', 'es', 'phrase', 'o en la App Store (iPhone)', 'o en el App Store (iPhone)'),
    ('57912624-b5dd-4412-bbcc-e20d9c7a5938', 'answer', 'es', 'phrase', 'y en la App Store (iPhone)', 'y en el App Store (iPhone)'),
    ('7c27d75f-25f8-45ff-a2ea-34c6a176ad55', 'answer', 'de', 'phrase', 'Wir bieten Treurabatte an.', 'Wir bieten Treuerabatte an.')
    ) AS x(id, field, lang, how, old, new)
    JOIN (VALUES
    ('9eb4103e-9c51-4813-bc5e-73e5d2ba990d', '41d888ffd1cb74a2ac0377e642c352a5'),
    ('57912624-b5dd-4412-bbcc-e20d9c7a5938', 'c6706b102d5aee6114f62023f621d475'),
    ('9d0038c0-0839-4485-a900-123c816b98af', '99b28f08e01d88b8069e098ecace5eb9'),
    ('bff7565d-63c4-44ab-9b3f-54274af813bc', 'e3fa91536f96a41a9b2f81eaa0c4eaba'),
    ('7c27d75f-25f8-45ff-a2ea-34c6a176ad55', '5ba9d5c0febd68f0fe5c304b99d4dbcc')
    ) AS g(id, gate) USING (id)
    ORDER BY (x.lang <> 'cs')            -- čeština první
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items
         SET answer = CASE WHEN f.field <> 'answer' THEN answer
                           WHEN f.how = 'phrase' THEN replace(answer, f.old, f.new) ELSE f.new END,
             question = CASE WHEN f.field <> 'question' THEN question
                             WHEN f.how = 'phrase' THEN replace(question, f.old, f.new) ELSE f.new END
       WHERE id = f.id::uuid
         AND CASE f.how WHEN 'full' THEN md5(CASE WHEN f.field = 'answer' THEN answer ELSE question END) = f.old
                        WHEN 'phrase' THEN strpos(CASE WHEN f.field = 'answer' THEN answer ELSE question END, f.old) > 0
                                       AND strpos(CASE WHEN f.field = 'answer' THEN answer ELSE question END, f.new) = 0
                        ELSE false END;
    ELSE
      UPDATE public.faq_items
         SET translations = jsonb_set(translations, ARRAY[f.lang],
               coalesce(translations -> f.lang, '{}'::jsonb) || jsonb_build_object(f.field,
                 CASE WHEN f.how = 'phrase' THEN replace(translations -> f.lang ->> f.field, f.old, f.new) ELSE f.new END))
       WHERE id = f.id::uuid
         AND md5(answer) = f.gate
         AND jsonb_typeof(translations) = 'object'
         AND (translations -> f.lang IS NULL OR jsonb_typeof(translations -> f.lang) = 'object')
         AND CASE f.how WHEN 'fill' THEN coalesce(translations -> f.lang ->> f.field, '') = ''
                        WHEN 'full' THEN md5(translations -> f.lang ->> f.field) = f.old
                        ELSE strpos(translations -> f.lang ->> f.field, f.old) > 0
                         AND strpos(translations -> f.lang ->> f.field, f.new) = 0 END;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT answer, CASE WHEN f.lang = 'cs' THEN (CASE WHEN f.field = 'answer' THEN answer ELSE question END)
                          ELSE translations -> f.lang ->> f.field END
        INTO v_ans, v_cur FROM public.faq_items WHERE id = f.id::uuid;
      IF (CASE WHEN f.how = 'phrase' THEN strpos(coalesce(v_cur, ''), f.new) > 0 ELSE v_cur = f.new END) THEN
        n_done := n_done + 1;
      ELSIF f.lang <> 'cs' AND md5(v_ans) IS DISTINCT FROM f.gate THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'faq_app: faq % % [%] PŘESKOČENO – česká odpověď není v očekávaném znění, překlad ponechán', f.id, f.field, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'faq_app: faq % % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', f.id, f.field, f.lang, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'faq_app: faq_items upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
