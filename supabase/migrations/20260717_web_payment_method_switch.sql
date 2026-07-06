-- =============================================================================
-- MIGRACE 2026-07-17: Web rezervace — přepnutí platební metody + odolný resume
-- POUZE WEB (booking_source='web'). APP/Velín/e-shop se NEMĚNÍ.
-- =============================================================================
-- Kontext (bug report): „Jsem v kroku platby (Stripe / QR), dám Zpět na MotoGo,
-- chci zvolit jinou metodu → napíše to ‚Rezervace nenalezena‘." + „z kroku dokladů
-- už zpět nelze, ale do kroku platby musí jít tam a zpátky bez ztráty dat."
--
-- Tato migrace řeší DB stranu:
--   1) get_web_booking_resume — výpočet docs_status izolovat do BEGIN/EXCEPTION,
--      aby výjimka v check_booking_docs_status NIKDY neshodila celý resume
--      (dosud inline v jsonb_build_object → chyba = RPC vrátí error = frontend
--      ukáže „Rezervace nenalezena" i pro naprosto validní nezaplacený draft,
--      na který se zákazník vrací z platební brány).
--   2) set_web_booking_chosen_method — při volbě „card" smazat pay_channel
--      (jinak by po pozdější Stripe platbě trigger trg_qr_payment_receipt poslal
--      duplicitní/chybný doklad, protože pay_channel zůstal 'qr' z předchozí QR
--      volby). Zaplacené rezervace se metody netýkají (guard payment_status).
-- Frontend (pages-rezervace-scan.js) přidává tlačítko „Zpět" na QR obrazovce.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) get_web_booking_resume — docs_status v izolovaném bloku (nikdy neshodí resume)
--    WHERE i vrácená pole 1:1 s 20260711 (pending+unpaid → krok platby;
--    paid/partial_refund/refund_pending → krok dokladů).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_web_booking_resume(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_uid    uuid;
  v_end    date;
  v_moto   uuid;
  v_docs   text;
BEGIN
  -- Nejprve ověř, že rezervace odpovídá povoleným stavům (jinak = not found).
  SELECT b.user_id, b.end_date::date, b.moto_id
    INTO v_uid, v_end, v_moto
    FROM bookings b
   WHERE b.id = p_booking_id
     AND b.booking_source = 'web'
     AND (
       (b.status = 'pending' AND b.payment_status = 'unpaid')
       OR (b.status IN ('reserved','active') AND b.payment_status IN ('paid','partial_refund','refund_pending'))
     );

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Rezervace nebyla nalezena.');
  END IF;

  -- docs_status v izolovaném bloku — případná výjimka NESMÍ shodit celý resume
  -- (jinak by se návrat z platební brány jevil jako „Rezervace nenalezena").
  BEGIN
    v_docs := check_booking_docs_status(v_uid, v_end, v_moto);
  EXCEPTION WHEN OTHERS THEN
    v_docs := NULL;
  END;

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
    'payment_status',       b.payment_status,
    'booking_status',       b.status,
    'pay_channel',          b.pay_channel,
    'docs_status',          v_docs,
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
  WHERE b.id = p_booking_id;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nebyla nalezena.');
  END IF;

  RETURN v_result;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 2) set_web_booking_chosen_method — volba „card" smaže QR kanál.
--    Frontend (_rezSubmitPayment) tuto RPC volá při KAŽDÉM kliknutí na platbu
--    s p_method 'card'/'qr'. Když zákazník přepne z QR na kartu, musí se pay_channel
--    vynulovat, jinak by po Stripe platbě naskočil QR-receipt trigger (duplicitní
--    doklad). Zaplacené rezervace metodu už nemění (guard).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_web_booking_chosen_method(p_booking_id uuid, p_method text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE bookings
     SET chosen_payment_method = LEFT(COALESCE(p_method, ''), 20),
         pay_channel = CASE WHEN p_method = 'card' THEN NULL ELSE pay_channel END
   WHERE id = p_booking_id
     AND booking_source = 'web'
     AND payment_status <> 'paid';
  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.set_web_booking_chosen_method(uuid, text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
