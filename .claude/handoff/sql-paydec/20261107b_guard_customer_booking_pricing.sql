-- ===== 20261107b_guard_customer_booking_pricing.sql (NÁVRH — ROZHODNUTÍ MAJITELE, necommitovat bez něj) =====
-- Oprava i4 (2026-11-07, verify:charges; ŽIVÁ díra, ne z přepracování plateb): RLS politika bookings_user_update
-- (user_id = auth.uid(), PERMISSIVE, bez omezení stavu) dovolí zákazníkovi vlastním JWT přímým REST UPDATE změnit
-- termín / motorku / cenu ZAPLACENÉ rezervace (ověřeno na kopii živého schématu: 1 den → 10 dní, total_price 2000
-- beze změny). _guard_customer_booking_status hlídá jen status / payment_status; ceny nekontroluje nic a konečná faktura
-- se počítá z total_price.
-- Návrh: BEFORE UPDATE strážce pro ZÁKAZNICKÝ JWT (current_user anon / authenticated, ne admin Velínu) u rezervace,
-- která není nezaplacená: PRODLOUŽENÍ / posun mimo původní termín / jiná motorka nebo vozík přímým zápisem se tiše
-- neprovede (ponechají se původní hodnoty termínu, motorky, času vyzvednutí, ceny a slev; RAISE LOG do logu Postgres).
-- Zaplacenou změnu zapisuje server (webhook / complete_extension / RPC jako service_role nebo SECURITY DEFINER jako
-- vlastník) — ten strážce nevidí. ZKRÁCENÍ v rámci původního termínu projde (appka 4.1.3 zkracuje přímým zápisem
-- a vratku hlídá process-refund: strop ze Stripe + spodní mez ceny), stejně jako změny bez vlivu na cenu.
-- POZOR před zapnutím (rozhodnutí majitele): appka 4.1.3 po zaplacené úpravě zapisuje změnu i sama; běžně ji zapíše
-- webhook z metadat (zápis appky je pak tichý no-op), ALE změna příliš velká pro metadata (no_payload) by se už
-- nezapsala vůbec → nejdřív ověřit / doplnit serverovou cestu. Idempotentní; bez sloupců se nic nevytvoří.
DO $do$
DECLARE
  v_cols text[] := ARRAY['start_date','end_date','moto_id','trailer_moto_id','pickup_time','total_price','extras_price',
                         'delivery_fee','discount_amount','loyalty_discount_amount','late_pickup_discount_amount','payment_status'];
  v_missing int;
BEGIN
  SELECT count(*) INTO v_missing FROM unnest(v_cols) c
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = 'bookings' AND column_name = c);
  IF v_missing > 0 OR to_regprocedure('public.is_admin()') IS NULL THEN
    RAISE NOTICE '_guard_customer_booking_pricing: chybí % sloupců / is_admin() — přeskočeno', v_missing;
    RETURN;
  END IF;

  EXECUTE $fn$
CREATE OR REPLACE FUNCTION public._guard_customer_booking_pricing() RETURNS trigger
  LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  -- jen zákaznický JWT přes PostgREST; server (service_role, SECURITY DEFINER funkce jako vlastník) a admin Velínu beze změny
  IF current_user NOT IN ('anon', 'authenticated') OR public.is_admin() THEN RETURN NEW; END IF;
  -- nezaplacená rezervace: cenu před platbou počítá a strhává process-payment
  IF OLD.payment_status = 'unpaid' THEN RETURN NEW; END IF;
  -- zkrácení / beze změny termínu a motorky → projde
  IF NEW.start_date >= OLD.start_date AND NEW.end_date <= OLD.end_date
     AND NEW.moto_id IS NOT DISTINCT FROM OLD.moto_id AND NEW.trailer_moto_id IS NOT DISTINCT FROM OLD.trailer_moto_id THEN
    RETURN NEW;
  END IF;
  -- debug_log zákazník zapsat nesmí (RLS debug_log_admin) → jen log serveru (Supabase → Logs → Postgres)
  RAISE LOG 'customer_booking_pricing_pinned booking=% user=% old=[% % % %] new=[% % % %]', OLD.id, auth.uid(),
    OLD.start_date, OLD.end_date, OLD.moto_id, OLD.total_price, NEW.start_date, NEW.end_date, NEW.moto_id, NEW.total_price;
  NEW.start_date := OLD.start_date;
  NEW.end_date := OLD.end_date;
  NEW.moto_id := OLD.moto_id;
  NEW.trailer_moto_id := OLD.trailer_moto_id;
  NEW.pickup_time := OLD.pickup_time;
  NEW.total_price := OLD.total_price;
  NEW.extras_price := OLD.extras_price;
  NEW.delivery_fee := OLD.delivery_fee;
  NEW.discount_amount := OLD.discount_amount;
  NEW.loyalty_discount_amount := OLD.loyalty_discount_amount;
  NEW.late_pickup_discount_amount := OLD.late_pickup_discount_amount;
  RETURN NEW;
END $$
  $fn$;

  -- „_trg_“ prefix: běží PŘED ostatními BEFORE triggery (abecedně) — kontrola překryvu / otevřené pobočky vidí už původní hodnoty
  EXECUTE 'DROP TRIGGER IF EXISTS _trg_guard_customer_booking_pricing ON public.bookings';
  EXECUTE 'CREATE TRIGGER _trg_guard_customer_booking_pricing BEFORE UPDATE OF start_date, end_date, moto_id, trailer_moto_id, '
       || 'pickup_time, total_price, extras_price, delivery_fee, discount_amount, loyalty_discount_amount, late_pickup_discount_amount '
       || 'ON public.bookings FOR EACH ROW EXECUTE FUNCTION public._guard_customer_booking_pricing()';
END $do$;
