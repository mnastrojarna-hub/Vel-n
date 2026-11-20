-- Povinná aktualizace appky na 5.0.1 (Android i iOS) — zadání majitele 2026-11-19
-- („vynucovat verzi 5.0.1 … obě dvě schválené a obě jdou stáhnout … dej mi na to pull request, ať se to nasadí samo“).
-- Appka (`lib/core/update_check_provider.dart`, oba stromy) při verzi < min_app_version ukáže nezavíratelné
-- okno „Vyžadována aktualizace“. Prostý řetězec = platí pro obě platformy a rozumí mu i staré verze appky.
-- Jen ZVYŠUJE: když je už nastaveno 5.0.1 nebo vyšší (např. ručně v SQL editoru), nic nemění.
INSERT INTO public.app_settings (key, value)
VALUES ('min_app_version', '"5.0.1"'::jsonb)
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value, updated_at = now()
  WHERE CASE
    WHEN jsonb_typeof(public.app_settings.value) = 'string'
     AND (public.app_settings.value #>> '{}') ~ '^[0-9]+(\.[0-9]+)*$'
    THEN string_to_array(public.app_settings.value #>> '{}', '.')::int[] < ARRAY[5, 0, 1]
    ELSE true
  END;

DO $$
BEGIN
  RAISE NOTICE 'min_app_version = %', (SELECT value FROM public.app_settings WHERE key = 'min_app_version');
END $$;
