-- =====================================================================
-- 2026-05-08 — Resume RPC vrací skutečné hodnoty dokladů (ne jen booleany)
--
-- Zákazník reportoval: vyplnil na PC číslo dokladu (id_number / license_number)
-- + skupinu a platnost ŘP, naskenoval QR kód a na mobilu místo vyplněných
-- údajů viděl placeholder „(vyplněno)" — musel vyplňovat znovu.
--
-- Důvod: `get_web_booking_resume` (verze z 2026-05-07) vracela jen booleany
-- `has_id_number` / `has_license_number` a chyběla úplně `license_expiry`.
-- Frontend (`pages-rezervace.js`) z toho neměl jak doplnit reálné hodnoty
-- do polí kroku 2.
--
-- Fix: RPC vrátí navíc `id_number`, `license_number` a `license_expiry`.
-- RPC zůstává omezena na `pending+unpaid+booking_source='web'` rezervace
-- (ochrana proti enumeraci jiných typů rezervací).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_web_booking_resume(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'booking_id',           b.id,
    'user_id',              b.user_id,
    'moto_id',              b.moto_id,
    'moto_model',           m.model,
    'start_date',           b.start_date,
    'end_date',             b.end_date,
    'total_price',          b.total_price,
    'extras_price',         b.extras_price,
    'discount_amount',      b.discount_amount,
    'discount_code',        b.discount_code,
    'promo_code',           pc.code,
    'voucher_id',           b.voucher_id,
    'voucher_code',         vc.code,
    'voucher_amount',       vc.amount,
    'pickup_time',          b.pickup_time,
    'return_time',          b.return_time,
    'delivery_address',     b.pickup_address,
    'return_address',       b.return_address,
    'notes',                b.notes,
    'helmet_size',          b.helmet_size,
    'jacket_size',          b.jacket_size,
    'pants_size',           b.pants_size,
    'boots_size',           b.boots_size,
    'gloves_size',          b.gloves_size,
    'passenger_helmet_size', b.passenger_helmet_size,
    'passenger_jacket_size', b.passenger_jacket_size,
    'passenger_gloves_size', b.passenger_gloves_size,
    'passenger_boots_size',  b.passenger_boots_size,
    'customer_name',        p.full_name,
    'customer_email',       p.email,
    'customer_phone',       p.phone,
    'customer_street',      p.street,
    'customer_city',        p.city,
    'customer_zip',         p.zip,
    'customer_country',     p.country,
    'license_group',        p.license_group,
    'license_expiry',       p.license_expiry,
    'id_number',            p.id_number,
    'license_number',       p.license_number,
    'has_id_number',        (p.id_number IS NOT NULL AND p.id_number <> ''),
    'has_license_number',   (p.license_number IS NOT NULL AND p.license_number <> ''),
    'extras',               COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'name',       be.name,
          'unit_price', be.unit_price,
          'quantity',   be.quantity
        )
        ORDER BY be.id
      )
      FROM booking_extras be
      WHERE be.booking_id = b.id
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM bookings b
  LEFT JOIN motorcycles m ON m.id = b.moto_id
  LEFT JOIN profiles    p ON p.id = b.user_id
  LEFT JOIN promo_codes pc ON pc.id = b.promo_code_id
  LEFT JOIN vouchers    vc ON vc.id = b.voucher_id
  WHERE b.id = p_booking_id
    AND b.booking_source = 'web'
    AND b.status = 'pending'
    AND b.payment_status = 'unpaid';

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nebyla nalezena nebo je již zaplacena.');
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_web_booking_resume(uuid) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
