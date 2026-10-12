-- =============================================================================
-- m3a_owner_texts.sql — DATOVÁ migrace (bez změn schématu). NÁVRH, NEAPLIKOVÁNO.
--
-- Zadání majitele 2026-10-11 (doslova): „Mytí ani tankování není třeba na obslužné
-- pobočce. Na samoobsluze není potřeba tankovat. Důležité je pouze, aby motorka byla
-- umytá a nesvítila rezerva.“
--   Mezná u Pelhřimova (obslužná, i vrácení na sjednaném místě) = bez mytí, bez tankování.
--   Velké Němčice u Brna (samoobslužná) = plná nádrž netřeba, ALE umytá + nesvítí rezerva.
-- Dále schválené texty: aplikace i v App Store (iPhone), krok 3 na úvodní stránce
-- (Mezná / samoobsluha Velké Němčice, přistavení z Mezné) a překlady banneru.
--
-- Co mění (jen texty pro zákazníky; cs + en de es fr nl pl uk):
--  1) cms_variables (Velín CMS — má na webu přednost před PHP i lang soubory):
--     web.pujcovna.faq.items.0.a, web.home.process.steps.2.text/.title,
--     web.jak_pujcit_dokumenty.payments.rows.2.1, web.jak_pujcit_postup.process.steps.11.text,
--     web.jak_pujcit_vraceni_pujcovna.cta.text
--  2) faq_items e6df7d9f (Musím vracet s plnou nádrží a čistou?) a 02b6cfc8 (Jaké palivo
--     mám tankovat?) — čte je i AI (get_faq); uk doplněno
--  3) app_settings pages_overlay.<stránka>.<jazyk> — auto-překlady PHP textů, které mají
--     přednost před lang/pages_<jazyk>.php: list se nastaví na nový text z lang souborů
--  4) app_settings header_banner — translations {lang: text} + translations_src
--     (sha1 hex českého textu; web i appka překlad použijí jen když sedí)
--
-- Bezpečnost: mění se JEN text, který je ve stavu ověřeném proti živým datům 2026-10-11
-- (celá věta / přesná fráze). Co mezitím někdo upravil ve Velíně, se přeskočí s NOTICE.
-- Překlady se mění jen když česká hodnota řádku už obsahuje nový text (žádný nesoulad cs×překlad).
-- Idempotentní (druhý běh nic nezmění). Bez BEGIN/COMMIT — deploy běží v jedné transakci.
-- Web: cache dat 30 min + stránek 10 min → projeví se nejpozději do ~40 min.
-- =============================================================================

-- 1) cms_variables ------------------------------------------------------------
DO $$
DECLARE
  f record;
  cnt integer;
  v_cur text;
  v_nogate boolean;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
@@CMS@@
    ) AS x(k, lang, old_txt, new_txt, gate)
    ORDER BY (x.lang <> 'cs')            -- čeština první (překlady se řídí branou gate)
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.cms_variables
         SET value = to_jsonb(replace(value #>> '{}', f.old_txt, f.new_txt)), updated_at = now()
       WHERE key = f.k AND jsonb_typeof(value) = 'string'
         AND strpos(value #>> '{}', f.old_txt) > 0
         AND strpos(value #>> '{}', f.new_txt) = 0;
    ELSIF f.old_txt IS NULL THEN         -- jazyk chybí → doplnit
      UPDATE public.cms_variables
         SET translations = jsonb_set(coalesce(translations, '{}'::jsonb), ARRAY[f.lang],
                                      jsonb_build_object('value', f.new_txt)),
             updated_at = now()
       WHERE key = f.k AND jsonb_typeof(value) = 'string'
         AND strpos(value #>> '{}', f.gate) > 0
         AND coalesce(translations -> f.lang ->> 'value', '') = '';
    ELSE
      UPDATE public.cms_variables
         SET translations = jsonb_set(translations, ARRAY[f.lang, 'value'],
                                      to_jsonb(replace(translations -> f.lang ->> 'value', f.old_txt, f.new_txt))),
             updated_at = now()
       WHERE key = f.k AND jsonb_typeof(value) = 'string'
         AND strpos(value #>> '{}', f.gate) > 0
         AND strpos(translations -> f.lang ->> 'value', f.old_txt) > 0
         AND strpos(translations -> f.lang ->> 'value', f.new_txt) = 0;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT CASE WHEN f.lang = 'cs' THEN value #>> '{}' ELSE translations -> f.lang ->> 'value' END,
             f.lang <> 'cs' AND strpos(coalesce(value #>> '{}', ''), f.gate) = 0
        INTO v_cur, v_nogate FROM public.cms_variables WHERE key = f.k;
      IF strpos(coalesce(v_cur, ''), f.new_txt) > 0 THEN
        n_done := n_done + 1;
      ELSIF v_nogate THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'm3a cms_variables % [%] PŘESKOČENO — česká hodnota řádku nebyla změněna, překlad ponechán', f.k, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'm3a cms_variables % [%] PŘESKOČENO — text ve Velíně mezitím změněn: %', f.k, f.lang, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'm3a cms_variables: upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;

-- 2) faq_items ------------------------------------------------------------------
-- updated_at nastaví trigger faq_items_set_updated_at.
DO $$
DECLARE
  f record;
  cnt integer;
  v_cur text;
  v_nogate boolean;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
@@FAQ@@
    ) AS x(id, field, lang, old_txt, new_txt, gate)
    ORDER BY (x.lang <> 'cs')
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items
         SET answer   = CASE WHEN f.field = 'answer'   THEN replace(answer,   f.old_txt, f.new_txt) ELSE answer END,
             question = CASE WHEN f.field = 'question' THEN replace(question, f.old_txt, f.new_txt) ELSE question END
       WHERE id = f.id::uuid
         AND strpos(CASE f.field WHEN 'answer' THEN answer ELSE question END, f.old_txt) > 0
         AND strpos(CASE f.field WHEN 'answer' THEN answer ELSE question END, f.new_txt) = 0;
    ELSIF f.old_txt IS NULL THEN         -- jazyk chybí → doplnit
      UPDATE public.faq_items
         SET translations = jsonb_set(coalesce(translations, '{}'::jsonb), ARRAY[f.lang],
                                      coalesce(translations -> f.lang, '{}'::jsonb) || jsonb_build_object(f.field, f.new_txt))
       WHERE id = f.id::uuid
         AND strpos(answer, f.gate) > 0
         AND coalesce(translations -> f.lang ->> f.field, '') = '';
    ELSE
      UPDATE public.faq_items
         SET translations = jsonb_set(translations, ARRAY[f.lang, f.field],
                                      to_jsonb(replace(translations -> f.lang ->> f.field, f.old_txt, f.new_txt)))
       WHERE id = f.id::uuid
         AND strpos(answer, f.gate) > 0
         AND strpos(translations -> f.lang ->> f.field, f.old_txt) > 0
         AND strpos(translations -> f.lang ->> f.field, f.new_txt) = 0;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT CASE WHEN f.lang = 'cs' THEN (CASE f.field WHEN 'answer' THEN answer ELSE question END)
                  ELSE translations -> f.lang ->> f.field END,
             f.lang <> 'cs' AND strpos(answer, f.gate) = 0
        INTO v_cur, v_nogate FROM public.faq_items WHERE id = f.id::uuid;
      IF strpos(coalesce(v_cur, ''), f.new_txt) > 0 THEN
        n_done := n_done + 1;
      ELSIF v_nogate THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'm3a faq_items % % [%] PŘESKOČENO — česká odpověď nebyla změněna, překlad ponechán', f.id, f.field, f.lang;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'm3a faq_items % % [%] PŘESKOČENO — text ve Velíně mezitím změněn: %', f.id, f.field, f.lang, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'm3a faq_items: upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;

-- 3) app_settings pages_overlay (cizí jazyky stránek Jak si půjčit) -------------
-- Listy jsou v polích (seznamech), která web přebírá celá → mění se jen daný list.
DO $$
DECLARE
  f record;
  cnt integer;
  v_cur text;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
@@OVERLAY@@
    ) AS x(page, lang, path, old_txt, new_txt)
  LOOP
    UPDATE public.app_settings
       SET value = jsonb_set(value, f.path::text[], to_jsonb(f.new_txt), false), updated_at = now()
     WHERE key = 'pages_overlay.' || f.page || '.' || f.lang
       AND jsonb_typeof(value) = 'object'
       AND value #>> f.path::text[] = f.old_txt;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT value #>> f.path::text[] INTO v_cur FROM public.app_settings
       WHERE key = 'pages_overlay.' || f.page || '.' || f.lang;
      IF v_cur = f.new_txt THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'm3a pages_overlay.%.% % PŘESKOČENO — text mezitím změněn: %', f.page, f.lang, f.path, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'm3a pages_overlay: upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;

-- 4) app_settings header_banner — překlady stávajícího českého textu ---------------
-- Přidá jen klíče translations + translations_src (enabled/text/bg/color zůstávají).
-- Jen když je text pořád tento a překlady k němu ještě nejsou (jinak NOTICE).
DO $$
DECLARE
  c_text constant text := @@BANNER_CS@@;
  v_tr constant jsonb := jsonb_build_object(
      @@BANNER_TR@@);
  v_val jsonb;
  cnt integer;
BEGIN
  UPDATE public.app_settings
     SET value = value || jsonb_build_object(
           'translations', v_tr,
           'translations_src', encode(extensions.digest(convert_to(value ->> 'text', 'UTF8'), 'sha1'), 'hex')),
         updated_at = now()
   WHERE key = 'header_banner'
     AND jsonb_typeof(value) = 'object'
     AND value ->> 'text' = c_text
     AND (value ->> 'translations_src') IS DISTINCT FROM
         encode(extensions.digest(convert_to(value ->> 'text', 'UTF8'), 'sha1'), 'hex');
  GET DIAGNOSTICS cnt = ROW_COUNT;
  IF cnt > 0 THEN
    RAISE NOTICE 'm3a header_banner: doplněny překlady (% jazyků)', (SELECT count(*) FROM jsonb_object_keys(v_tr));
  ELSE
    SELECT value INTO v_val FROM public.app_settings WHERE key = 'header_banner';
    RAISE NOTICE 'm3a header_banner: beze změny (text: %, translations_src: %)',
      left(coalesce(v_val ->> 'text', '∅'), 80), coalesce(v_val ->> 'translations_src', '∅');
  END IF;
END $$;
