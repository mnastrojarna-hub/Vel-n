-- =============================================================================
-- MIGRACE 2026-07-11: get_web_booking_resume — povolit i ZAPLACENÉ (krok dokladů)
-- =============================================================================
-- NOVÝ FLOW (platba PŘED doklady): po platbě se zákazník vrací na /rezervace?resume=<id>
-- na KROK DOKLADŮ. Resume RPC dosud vracela data JEN pro pending+unpaid → po platbě
-- selhala. Nově vrací i pro web reserved/active + paid a přidává `payment_status`,
-- `booking_status`, `docs_status` (NULL = doklady OK) — frontend podle nich pozná,
-- že má zobrazit fázi dokladů, a zda jsou už hotové. POUZE WEB. Ostatní pole beze změny.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_web_booking_resume(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    'date_of_birth',        p.date_of_birth,
    'id_number',            p.id_number,
    'license_number',       p.license_number,
    'has_id_number',        (p.id_number IS NOT NULL AND p.id_number <> ''),
    'has_license_number',   (p.license_number IS NOT NULL AND p.license_number <> ''),
    'has_password',         (p.password_last4_bcrypt IS NOT NULL),
    -- NOVÝ FLOW: stav platby + dokladů pro rozhodnutí kroku na frontendu
    'payment_status',       b.payment_status,
    'booking_status',       b.status,
    'pay_channel',          b.pay_channel,
    'docs_status',          check_booking_docs_status(b.user_id, b.end_date::date, b.moto_id),
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
    AND (
      -- před platbou: rozpracovaná rezervace (krok 2 = platba)
      (b.status = 'pending' AND b.payment_status = 'unpaid')
      -- po platbě: krok dokladů (krok 3)
      OR (b.status IN ('reserved','active') AND b.payment_status IN ('paid','partial_refund','refund_pending'))
    );

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nebyla nalezena.');
  END IF;

  RETURN v_result;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Zvolená platební metoda (Velín funnel — poznat volbu i u NEZAPLACENÝCH web rezervací).
-- QR má pay_channel='qr'; tohle doplní i 'card' volbu (jinak Velín u nezaplacené karty
-- vidí jen „dosáhl brány", ne zvolenou metodu). POUZE WEB.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_web_booking_chosen_method(p_booking_id uuid, p_method text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE bookings
     SET chosen_payment_method = LEFT(COALESCE(p_method, ''), 20)
   WHERE id = p_booking_id
     AND booking_source = 'web';
  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.set_web_booking_chosen_method(uuid, text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
