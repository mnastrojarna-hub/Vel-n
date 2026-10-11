-- =============================================================================
-- 2026-10-11 BEZPEČNOST (dokončení 20261011d): pohledy a úložiště `media`
--
-- 1) Pohledy v_recent_crashes / v_user_debug_timeline / v_api_performance /
--    v_screen_error_rate patří postgres a běžely s jeho právy → obcházely RLS:
--    anon přes REST četl jména, e-maily a ladicí logy zákazníků. Nově
--    security_invoker (platí RLS podkladových tabulek = jen admin) a bez anon.
--    Velín ani appka je přes REST nečtou.
-- 2) storage `media`: „Auth update/delete/upload media“ dovolovaly KAŽDÉMU
--    přihlášenému zákazníkovi přepsat / smazat / nahrát cokoli (fotky motorek,
--    manuály, videa, cizí fotky recenzí). Nově zápis do `media` smí admin
--    (Velín) a zákazník jen do svých složek, které appka používá:
--    user-pois/<uid>/ (nové), poi-reviews/, rides/, route-reviews/ (stávající
--    politiky beze změny). Veřejné čtení beze změny. Edge (service role) RLS
--    neobchází nic jiného.
-- Idempotentní.
-- =============================================================================

DO $$
DECLARE v text;
BEGIN
  FOREACH v IN ARRAY ARRAY['v_recent_crashes', 'v_user_debug_timeline',
                           'v_api_performance', 'v_screen_error_rate'] LOOP
    IF to_regclass('public.' || v) IS NOT NULL THEN
      EXECUTE format('ALTER VIEW public.%I SET (security_invoker = true)', v);
      EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon', v);
    ELSE
      RAISE NOTICE 'view % neexistuje, přeskakuji', v;
    END IF;
  END LOOP;
END $$;

DO $$
BEGIN
  DROP POLICY IF EXISTS "Auth update media" ON storage.objects;
  DROP POLICY IF EXISTS "Auth delete media" ON storage.objects;
  DROP POLICY IF EXISTS "Auth upload media" ON storage.objects;

  DROP POLICY IF EXISTS media_admin_all ON storage.objects;
  CREATE POLICY media_admin_all ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'media' AND public.is_admin())
    WITH CHECK (bucket_id = 'media' AND public.is_admin());

  DROP POLICY IF EXISTS media_user_poi_upload ON storage.objects;
  CREATE POLICY media_user_poi_upload ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'media'
                AND (storage.foldername(name))[1] = 'user-pois'
                AND (storage.foldername(name))[2] = auth.uid()::text);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'media storage policies: % (doplňte ručně v Dashboardu → Storage → Policies)', SQLERRM;
END $$;
