-- =============================================================================
-- MIGRACE: DROP staré 30-param overload `create_web_booking`
-- Datum: 2026-04-25
-- Popis: Po přidání p_return_time text DEFAULT NULL (31 parametrů celkem)
--        zůstala v DB vedle nové verze i původní 30-param verze (bez
--        p_return_time). Frontend (motogo-web-php/js/pages-rezervace-steps.js)
--        posílá p_return_time podmíněně — když chyběl, PostgREST vyhodil
--        PGRST203 "Could not choose the best candidate function", protože
--        volání odpovídalo OBĚMA overloadům (30-param exact match i 31-param
--        přes default).
--
-- Řešení: explicitně dropneme starou 30-param signaturu. V DB zůstává jediná
--        verze s 31 parametry (poslední je p_return_time text DEFAULT NULL).
-- =============================================================================

DROP FUNCTION IF EXISTS public.create_web_booking(
  uuid,         -- p_moto_id
  timestamptz,  -- p_start_date
  timestamptz,  -- p_end_date
  text,         -- p_name
  text,         -- p_email
  text,         -- p_phone
  text,         -- p_street
  text,         -- p_city
  text,         -- p_zip
  text,         -- p_country
  text,         -- p_note
  time,         -- p_pickup_time
  text,         -- p_delivery_address
  text,         -- p_return_address
  jsonb,        -- p_extras
  numeric,      -- p_discount_amount
  text,         -- p_discount_code
  text,         -- p_promo_code
  uuid,         -- p_voucher_id
  text,         -- p_license_group
  text,         -- p_password
  text,         -- p_helmet_size
  text,         -- p_jacket_size
  text,         -- p_pants_size
  text,         -- p_boots_size
  text,         -- p_gloves_size
  text,         -- p_passenger_helmet_size
  text,         -- p_passenger_jacket_size
  text,         -- p_passenger_gloves_size
  text          -- p_passenger_boots_size
);

NOTIFY pgrst, 'reload schema';
