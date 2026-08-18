-- ============================================================
-- Firemní údaje z web rezervačního formuláře (krok 3 — checkbox
-- „Firemní údaje"). Web sbírá název firmy, IČO, DIČ a adresu
-- sídla; ukládá je post-create helperem set_web_booking_company
-- (stejný vzor jako set_web_booking_docs / set_booking_language).
-- profiles.ico a profiles.dic už existují — doplňují se jen
-- company_name a company_address.
-- Idempotentní: ADD COLUMN IF NOT EXISTS + CREATE OR REPLACE.
-- ============================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS company_name text,
  ADD COLUMN IF NOT EXISTS company_address text;

CREATE OR REPLACE FUNCTION public.set_web_booking_company(
  p_booking_id uuid,
  p_company_name text DEFAULT NULL,
  p_ico text DEFAULT NULL,
  p_dic text DEFAULT NULL,
  p_company_address text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  -- Klíčováno přes booking_id, jen web rezervace (vzor set_web_booking_docs)
  SELECT user_id INTO v_user_id
    FROM bookings
   WHERE id = p_booking_id
     AND booking_source = 'web';

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'booking_not_found');
  END IF;

  -- COALESCE(NULLIF(trim(...))) — prázdné hodnoty nepřepíší existující
  UPDATE profiles SET
    company_name    = COALESCE(NULLIF(trim(p_company_name), ''), company_name),
    ico             = COALESCE(NULLIF(trim(p_ico), ''), ico),
    dic             = COALESCE(NULLIF(trim(p_dic), ''), dic),
    company_address = COALESCE(NULLIF(trim(p_company_address), ''), company_address)
  WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_web_booking_company(uuid, text, text, text, text) TO anon, authenticated;
