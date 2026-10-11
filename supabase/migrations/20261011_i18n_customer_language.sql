-- 20261011_i18n_customer_language.sql — jazyk zákazníka pro smlouvy, e-maily, SMS a AI
-- (audit 2026-10-10: web/AI rezervace měly vždy 'cs', ukrajinštinu DB odmítala, SOS/swap
-- rezervace dědily 'cs', otevírací doba poboček v DB odporovala nonstop provozu).
-- Idempotentní. Nic nemaže, nemění ceny ani stavy rezervací. Bez BEGIN/COMMIT — deploy-sql.yml
-- spouští každý soubor v jedné transakci (psql --single-transaction).


-- 1) Ukrajinština v CHECK omezeních (bookings / profiles / shop_orders)
ALTER TABLE public.bookings    DROP CONSTRAINT IF EXISTS bookings_language_check;
ALTER TABLE public.bookings    ADD  CONSTRAINT bookings_language_check
  CHECK (language = ANY (ARRAY['cs','en','de','nl','es','fr','pl','uk']));
ALTER TABLE public.profiles    DROP CONSTRAINT IF EXISTS profiles_language_check;
ALTER TABLE public.profiles    ADD  CONSTRAINT profiles_language_check
  CHECK (language = ANY (ARRAY['cs','en','de','nl','es','fr','pl','uk']));
ALTER TABLE public.shop_orders DROP CONSTRAINT IF EXISTS shop_orders_language_check;
ALTER TABLE public.shop_orders ADD  CONSTRAINT shop_orders_language_check
  CHECK (language = ANY (ARRAY['cs','en','de','nl','es','fr','pl','uk']));

-- 2) set_booking_language — volá web (pages-rezervace-steps.js) a AI agent hned po vytvoření
--    rezervace; v živé DB funkce chyběla (PGRST202) → web/AI rezervace zůstávaly 'cs'.
--    Ochrana: jen podporovaný jazyk; anonym smí měnit jen čerstvou (< 2 h) rezervaci z webu/AI,
--    přihlášený jen vlastní, service_role vše. Mění jen sloupec language (trigger e-mailu
--    „rezervace změněna“ na language nereaguje).
CREATE OR REPLACE FUNCTION public.set_booking_language(p_booking_id uuid, p_language text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_lang text := lower(left(coalesce(p_language, ''), 2));
  v_n int;
BEGIN
  IF v_lang NOT IN ('cs','en','de','nl','es','fr','pl','uk') THEN RETURN false; END IF;
  UPDATE public.bookings b SET language = v_lang
   WHERE b.id = p_booking_id
     AND b.language IS DISTINCT FROM v_lang
     AND (
       coalesce(auth.role(), '') = 'service_role'
       OR (auth.uid() IS NOT NULL AND b.user_id = auth.uid())
       OR (b.created_at > now() - interval '2 hours' AND coalesce(b.booking_source::text, 'web') IN ('web', 'ai', 'ai_agent'))
     );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  -- Nově založený profil (web zakládá účet při rezervaci, jazyk profilu zůstal výchozí 'cs'):
  -- převezme jazyk rezervace, aby i cron e-maily čtoucí profiles.language (připomínky dokladů,
  -- opuštěná rezervace) šly ve správném jazyce. Existující profily s vlastním jazykem se nemění.
  IF v_n > 0 AND v_lang <> 'cs' THEN
    UPDATE public.profiles p SET language = v_lang
      FROM public.bookings b
     WHERE b.id = p_booking_id AND p.id = b.user_id
       AND coalesce(p.language, 'cs') = 'cs'
       AND p.created_at > now() - interval '2 hours';
  END IF;
  RETURN v_n > 0;
END $$;
REVOKE ALL ON FUNCTION public.set_booking_language(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_booking_language(uuid, text) TO anon, authenticated, service_role;

-- 3) set_shop_order_language — volá web checkout.js a appka shop_provider po vytvoření objednávky
CREATE OR REPLACE FUNCTION public.set_shop_order_language(p_order_id uuid, p_language text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_lang text := lower(left(coalesce(p_language, ''), 2));
  v_n int;
BEGIN
  IF v_lang NOT IN ('cs','en','de','nl','es','fr','pl','uk') THEN RETURN false; END IF;
  UPDATE public.shop_orders o SET language = v_lang
   WHERE o.id = p_order_id
     AND o.language IS DISTINCT FROM v_lang
     AND (
       coalesce(auth.role(), '') = 'service_role'
       OR (auth.uid() IS NOT NULL AND o.customer_id = auth.uid())
       OR o.created_at > now() - interval '2 hours'
     );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END $$;
REVOKE ALL ON FUNCTION public.set_shop_order_language(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_shop_order_language(uuid, text) TO anon, authenticated, service_role;

-- 4) Navazující rezervace (výměna motorky split_booking_moto_swap → continues_booking_id,
--    SOS náhrada sos_swap_bookings → replacement_for_booking_id) přebírají jazyk původní
--    rezervace — obě funkce sloupec language nevyplňují (default 'cs').
CREATE OR REPLACE FUNCTION public._booking_inherit_language()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_lang text;
BEGIN
  IF coalesce(NEW.language, 'cs') = 'cs' THEN
    SELECT b.language INTO v_lang FROM public.bookings b
     WHERE b.id = coalesce(NEW.continues_booking_id, NEW.replacement_for_booking_id);
    IF v_lang IS NOT NULL AND v_lang <> 'cs' THEN NEW.language := v_lang; END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public._booking_inherit_language() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_booking_inherit_language ON public.bookings;
CREATE TRIGGER trg_booking_inherit_language
  BEFORE INSERT ON public.bookings
  FOR EACH ROW
  WHEN (NEW.continues_booking_id IS NOT NULL OR NEW.replacement_for_booking_id IS NOT NULL)
  EXECUTE FUNCTION public._booking_inherit_language();

-- 5) Otevírací doba poboček = nonstop (potvrzeno majitelem 2026-10-10). Čtou ji AI agenti
--    (get_branches / snapshots) — dosud tvrdila Po–Pá 8–18, So 9–14, Ne zavřeno.
UPDATE public.branches
   SET opening_hours = '{"mo":"00:00-24:00","tu":"00:00-24:00","we":"00:00-24:00","th":"00:00-24:00","fr":"00:00-24:00","sa":"00:00-24:00","su":"00:00-24:00"}'::jsonb
 WHERE id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');

-- 6) Čerstvost překladů smluvních dokumentů. translation_src = {"<lang>": "<sha1 hex zdrojového
--    českého textu, ze kterého překlad vznikl>"}; plní translate-document (a generate-document při
--    automatickém překladu). document_templates: sha1(content_html); custom_documents:
--    sha1(coalesce(content_html,'') || '|' || coalesce(pdf_path,'')). Překlad bez shodného otisku
--    je ZASTARALÝ a nikde se nepoužije (web, appka, PDF, AI) — místo něj závazná česká verze.
--    Stávající překlady otisk nemají → okamžitě přestanou platit (VOP/smlouva v cizích jazycích
--    jsou stará verze se spoluúčastí 30 000 Kč) — znovu se přeloží tlačítkem ve Velíně.
ALTER TABLE public.document_templates ADD COLUMN IF NOT EXISTS translation_src jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.custom_documents   ADD COLUMN IF NOT EXISTS translation_src jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.get_document_translation(p_template_slug text, p_language text DEFAULT 'cs')
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_row document_templates%ROWTYPE;
  v_lang text := lower(coalesce(p_language, 'cs'));
BEGIN
  SELECT * INTO v_row FROM document_templates WHERE type = p_template_slug AND active = true LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF v_lang = 'cs' THEN RETURN v_row.content_html; END IF;
  IF coalesce(v_row.content_translations->>v_lang, '') = '' THEN RETURN NULL; END IF;
  IF v_row.translation_src->>v_lang IS DISTINCT FROM
     encode(extensions.digest(convert_to(v_row.content_html, 'UTF8'), 'sha1'), 'hex') THEN
    RETURN NULL;  -- zastaralý překlad (česká verze se od překladu změnila) → volající ukáže češtinu
  END IF;
  RETURN v_row.content_translations->>v_lang;
END $$;
GRANT EXECUTE ON FUNCTION public.get_document_translation(text, text) TO anon, authenticated, service_role;

-- 7) document_templates nemělo trigger updated_at (custom_documents ho má) — Velín i AI
--    podle updated_at poznají, kdy se česká šablona změnila.
CREATE OR REPLACE TRIGGER trg_document_templates_updated
  BEFORE UPDATE ON public.document_templates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- 8) Připomínkové e-maily z cronu (nedokončená rezervace, chybějící doklady, potvrzení
--    s chybějícími doklady) braly jazyk z profilu — u webové rezervace v cizím jazyce
--    (profil zůstal 'cs') šly česky, zatímco smlouva a potvrzení podle bookings.language.
--    Nově: jazyk rezervace, pak profil. Těla funkcí = živý stav 2026-10-10, změněn jen
--    výběr jazyka (p.language → COALESCE(NULLIF(b.language, ''), p.language)).

CREATE OR REPLACE FUNCTION "public"."send_abandoned_booking_emails"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_url         text;
  v_key         text;
  v_row         record;
  v_sent_ab     int := 0;
  v_sent_docs   int := 0;
  v_pay_url     text;
  v_docs_url    text;
  v_site_url    text := 'https://www.motogo24.cz';
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_abandoned_booking_emails: app_settings missing — abort';
    RETURN jsonb_build_object('error', 'app_settings_missing');
  END IF;

  -- PATH AB: pending + unpaid (web) — 15 min od created_at. Obnovené rezervace
  -- (restored_at) se přeskakují — obnovil je admin, „nedokončená" nejsou.
  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.total_price,
           b.stripe_checkout_url, b.checkout_started_at, b.created_at,
           p.email AS customer_email, p.full_name AS customer_name,
           COALESCE(NULLIF(b.language, ''), p.language) AS customer_language,
           m.model AS motorcycle_model
      FROM bookings b
      LEFT JOIN profiles    p ON p.id = b.user_id
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.booking_source        = 'web'
       AND b.status                = 'pending'
       AND b.payment_status        = 'unpaid'
       AND b.restored_at           IS NULL
       AND b.abandoned_email_sent_at IS NULL
       AND b.created_at < now() - interval '15 minutes'
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    v_pay_url := COALESCE(NULLIF(v_row.stripe_checkout_url, ''), v_site_url || '/rezervace?resume=' || v_row.id::text);

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object(
          'type','booking_abandoned','source','web','booking_id',v_row.id,
          'customer_email',v_row.customer_email,'customer_name',COALESCE(v_row.customer_name,''),
          'motorcycle',COALESCE(v_row.motorcycle_model,''),'start_date',v_row.start_date,
          'end_date',v_row.end_date,'total_price',v_row.total_price,
          'pay_url',v_pay_url,'resume_link',v_pay_url,'language',COALESCE(v_row.customer_language,'cs')
        )
      );
      UPDATE bookings SET abandoned_email_sent_at = now() WHERE id = v_row.id;
      v_sent_ab := v_sent_ab + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails AB: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  -- PATH C: paid + reserved/active + NEDOKONČIL krok dokladů (docs_completed_at IS NULL),
  -- 30 min od confirmed_at. Jen samoobslužné vyzvednutí (obslužná/delivery = doklady
  -- nepovinné, ověří obsluha → žádná připomínka). Dětská motorka: docs_completed_at
  -- se stejně nastaví při „Hotovo", takže nezacyklí.
  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.confirmed_at,
           p.email AS customer_email, p.full_name AS customer_name,
           COALESCE(NULLIF(b.language, ''), p.language) AS customer_language,
           m.model AS motorcycle_model
      FROM bookings b
      LEFT JOIN profiles    p  ON p.id  = b.user_id
      LEFT JOIN motorcycles m  ON m.id  = b.moto_id
      LEFT JOIN branches    br ON br.id = m.branch_id
     WHERE b.booking_source             = 'web'
       AND b.status                     IN ('reserved','active')
       AND b.payment_status             = 'paid'
       AND b.docs_completed_at          IS NULL
       AND b.docs_reminder_sent_at      IS NULL
       AND b.confirmed_at < now() - interval '30 minutes'
       AND COALESCE(br.type, '')         <> 'obslužná'
       AND COALESCE(b.pickup_method, '') <> 'delivery'
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    v_docs_url := v_site_url || '/rezervace?resume=' || v_row.id::text;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object(
          'type','booking_missing_docs','source','web','booking_id',v_row.id,
          'customer_email',v_row.customer_email,'customer_name',COALESCE(v_row.customer_name,''),
          'motorcycle',COALESCE(v_row.motorcycle_model,''),'start_date',v_row.start_date,
          'end_date',v_row.end_date,'docs_url',v_docs_url,'language',COALESCE(v_row.customer_language,'cs')
        )
      );
      UPDATE bookings SET docs_reminder_sent_at = now() WHERE id = v_row.id;
      v_sent_docs := v_sent_docs + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails C: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('sent_abandoned', v_sent_ab, 'sent_missing_docs', v_sent_docs);
END;
$$;

CREATE OR REPLACE FUNCTION "public"."send_missing_booking_reserved_emails"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_url   text;
  v_key   text;
  v_row   record;
  v_docs  text;
  v_sent  int := 0;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_missing_booking_reserved_emails: app_settings missing — abort';
    RETURN jsonb_build_object('error', 'app_settings_missing');
  END IF;

  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.total_price,
           b.booking_source, b.docs_completed_at,
           p.email AS customer_email, p.full_name AS customer_name,
           COALESCE(NULLIF(b.language, ''), p.language) AS customer_language,
           m.model AS motorcycle_model, m.manual_url AS manual_url
      FROM bookings b
      LEFT JOIN profiles    p ON p.id = b.user_id
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.status                 IN ('reserved','active')
       AND b.payment_status         = 'paid'
       AND b.confirmed_at IS NOT NULL
       AND b.confirmed_at           < now() - interval '3 minutes'
       AND b.reserved_email_sent_at IS NULL
       AND NOT EXISTS (
         SELECT 1 FROM message_log ml
          WHERE ml.booking_id    = b.id
            AND ml.channel       = 'email'
            AND ml.template_slug IN ('web_booking_reserved','booking_reserved')
       )
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    -- WEB: reserved až když dokončený krok dokladů (čísla) NEBO doklady už ověřené.
    IF COALESCE(v_row.booking_source, 'web') = 'web' AND v_row.docs_completed_at IS NULL THEN
      v_docs := NULL;
      BEGIN
        v_docs := check_booking_docs_status(v_row.user_id, v_row.end_date::date, v_row.moto_id);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'send_missing_booking_reserved_emails: docs check failed for %: %', v_row.id, SQLERRM;
        CONTINUE;
      END;
      IF v_docs IS NOT NULL THEN CONTINUE; END IF;  -- ani nedokončené, ani ověřené → ještě ne
    END IF;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object(
          'type','booking_reserved','source',COALESCE(v_row.booking_source,'web'),
          'booking_id',v_row.id,'customer_email',v_row.customer_email,
          'customer_name',COALESCE(v_row.customer_name,''),'motorcycle',COALESCE(v_row.motorcycle_model,''),
          'start_date',v_row.start_date,'end_date',v_row.end_date,'total_price',v_row.total_price,
          'manual_url',COALESCE(v_row.manual_url,''),'language',COALESCE(v_row.customer_language,'cs')
        )
      );
      UPDATE bookings SET reserved_email_sent_at = now() WHERE id = v_row.id;
      v_sent := v_sent + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_missing_booking_reserved_emails: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('sent_reserved', v_sent);
END;
$$;
