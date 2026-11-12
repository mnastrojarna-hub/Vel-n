-- =============================================================================
-- 20261112a07_guard_customer_booking_pricing.sql — zákazník přímým zápisem nezmění termín,
-- motorku ani cenu ZAPLACENÉ rezervace
--
-- Oprava i4 (2026-11-07, verify:charges), schváleno majitelem 2026-11-08. Živá díra:
-- RLS politika bookings_user_update (user_id = auth.uid(), bez omezení stavu) dovolí
-- zákazníkovi vlastním JWT přímým REST UPDATE změnit termín / motorku / cenu ZAPLACENÉ
-- rezervace (ověřeno na kopii živého schématu: 1 den → 10 dní, total_price beze změny).
-- _guard_customer_booking_status hlídá jen status / payment_status; konečná faktura se
-- počítá z total_price.
--
-- Co dělá: BEFORE UPDATE strážce pro ZÁKAZNICKÝ JWT (current_user anon / authenticated,
-- ne admin Velínu) u rezervace, která není nezaplacená: změna, která by zákazníkovi dala
-- VÍC, než zaplatil — víc dní, motorka / termín s vyšší ceníkovou hodnotou
-- (_moto_dayprice_sum, dny dle data v Praze), motorka bez ceníku nebo přidaný vozík — se
-- přímým zápisem tiše neprovede CELÁ (trigger vrátí původní řádek: nezmění se ani ostatní
-- sloupce téhož zápisu, např. způsob přistavení / adresa / velikosti, takže nevznikne
-- smíšený stav; RAISE LOG do logu Postgres — debug_log zákazník zapsat nesmí). Výjimka
-- „nezaplacená“ platí jen pro rezervaci pending / cancelled s payment_status 'unpaid'
-- (status zákazník z reserved / active zpět na pending nedostane; payment_status 'unpaid'
-- si přepsat může, proto samotné 'unpaid' nestačí). Zaplacenou změnu
-- zapisuje server (webhook / complete_extension / RPC jako service_role nebo SECURITY
-- DEFINER jako vlastník) — toho strážce nevidí.
-- Projde: zkrácení v rámci původního termínu, změny bez vlivu na termín a motorku a posun
-- termínu / výměna motorky, které počet dní ani ceníkovou hodnotu nezvyšují. Appka 4.1.3
-- i současná appka (reservation_edit_screen, větev „effDiff <= 0“) takové úpravy
-- zaplacené rezervace zapisují přímým UPDATE a pak volají process-refund; peníze hlídá
-- process-refund (strop dle Stripe + spodní mez ceny). Upřesnění 2026-11-12 proti verzi
-- z 2026-11-07 (ta vracela každý posun a každou výměnu motorky): bez něj by se bezplatný
-- posun termínu nebo levnější motorka v appce tiše neuložily.
-- Prefix „_trg_“ řadí trigger PŘED ostatní BEFORE triggery (kontrola překryvu / otevřené
-- pobočky už vidí původní hodnoty).
-- Pozor (známé riziko, přijaté majitelem): appka 4.1.3 i web (MG._editRez.
-- _applyPendingAfterPayment v pages-upravit-rezervaci.js — na dnes nasazeném webu po každé
-- zaplacené úpravě, na novém jen při odpovědi client_apply / no_payload) po zaplacené
-- úpravě zapisují změnu i samy přímým UPDATE; běžně ji zapíše webhook z metadat Stripe
-- (zápis klienta je pak tichý no-op), ale změnu, kterou server zapsat nemohl (příliš
-- velká pro metadata, selhání webhooku), už klient sám neuloží — zapíše ji obsluha.
-- Vedlejší účinek: rezervaci reserved / active s payment_status 'unpaid' (např. založenou
-- obsluhou) strážce hlídá jako zaplacenou.
--
-- Výpůjčka jen výbavy (booking_kind 'gear') má vlastní pojistku trg_zz_gear_booking_guard,
-- která přímý zápis termínu / ceny zákazníkem odmítne výjimkou gear_booking_rpc_only. Tento
-- strážce běží dřív: u ZAPLACENÉ výpůjčky výbavy prodloužení zákazníkem tiše vrátí (bez
-- výjimky); zkrácení a posun dál odmítne gear pojistka jako dosud.
-- Práva trigger funkce jako u _guard_customer_booking_status (bez PUBLIC).
-- Idempotentní (CREATE OR REPLACE, DROP TRIGGER IF EXISTS). Bez BEGIN/COMMIT.
-- Záměrně se nemění: RLS politika bookings_user_update, nezaplacené rezervace
-- (cenu před platbou počítá a strhává process-payment).
-- =============================================================================
CREATE OR REPLACE FUNCTION public._guard_customer_booking_pricing()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_old_days int;
  v_new_days int;
  v_old_sum  numeric;
  v_new_sum  numeric;
BEGIN
  -- jen zákaznický JWT přes PostgREST; server (service_role, SECURITY DEFINER funkce jako vlastník) a admin Velínu beze změny
  IF current_user NOT IN ('anon', 'authenticated') OR public.is_admin() THEN RETURN NEW; END IF;
  -- nezaplacená rezervace: cenu před platbou počítá a strhává process-payment
  -- (jen pending / cancelled: payment_status 'unpaid' si zákazník zapsat může, status zpět ne)
  IF OLD.payment_status = 'unpaid' AND OLD.status IN ('pending', 'cancelled') THEN RETURN NEW; END IF;
  -- zkrácení / beze změny termínu a motorky → projde
  IF NEW.start_date >= OLD.start_date AND NEW.end_date <= OLD.end_date
     AND NEW.moto_id IS NOT DISTINCT FROM OLD.moto_id AND NEW.trailer_moto_id IS NOT DISTINCT FROM OLD.trailer_moto_id THEN
    RETURN NEW;
  END IF;
  -- posun / výměna motorky bez navýšení: ne víc dní, nepřidaný vozík, ceníková hodnota nového
  -- termínu a motorky ≤ původní (motorka bez ceníku = nelze ověřit → vrátit)
  -- dny dle data v Praze (jako kiosk, aktivace, doklady), ne dle časové zóny relace
  v_old_days := (OLD.end_date AT TIME ZONE 'Europe/Prague')::date - (OLD.start_date AT TIME ZONE 'Europe/Prague')::date;
  v_new_days := (NEW.end_date AT TIME ZONE 'Europe/Prague')::date - (NEW.start_date AT TIME ZONE 'Europe/Prague')::date;
  IF v_new_days <= v_old_days
     AND (NEW.trailer_moto_id IS NULL OR NEW.trailer_moto_id IS NOT DISTINCT FROM OLD.trailer_moto_id) THEN
    v_old_sum := COALESCE(public._moto_dayprice_sum(OLD.moto_id, (OLD.start_date AT TIME ZONE 'Europe/Prague')::date,
                                                    (OLD.end_date AT TIME ZONE 'Europe/Prague')::date), 0);
    v_new_sum := COALESCE(public._moto_dayprice_sum(NEW.moto_id, (NEW.start_date AT TIME ZONE 'Europe/Prague')::date,
                                                    (NEW.end_date AT TIME ZONE 'Europe/Prague')::date), 0);
    IF v_new_sum <= v_old_sum + 0.5
       AND (NEW.moto_id IS NOT DISTINCT FROM OLD.moto_id OR v_new_sum > 0) THEN
      RETURN NEW;
    END IF;
  END IF;
  -- debug_log zákazník zapsat nesmí (RLS debug_log_admin) → jen log serveru (Supabase → Logs → Postgres)
  RAISE LOG 'customer_booking_pricing_pinned booking=% user=% old=[% % % %] new=[% % % %]', OLD.id, auth.uid(),
    OLD.start_date, OLD.end_date, OLD.moto_id, OLD.total_price, NEW.start_date, NEW.end_date, NEW.moto_id, NEW.total_price;
  -- celý zápis se neprovede (trigger je první BEFORE trigger dle názvu → OLD je
  -- dosud nezměněný řádek); žádný smíšený stav (např. zrušené přistavení s ponechaným poplatkem)
  RETURN OLD;
END $$;

REVOKE ALL ON FUNCTION public._guard_customer_booking_pricing() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._guard_customer_booking_pricing() TO anon, authenticated, service_role;

DROP TRIGGER IF EXISTS _trg_guard_customer_booking_pricing ON public.bookings;
CREATE TRIGGER _trg_guard_customer_booking_pricing
  BEFORE UPDATE OF start_date, end_date, moto_id, trailer_moto_id, pickup_time, total_price, extras_price,
                   delivery_fee, discount_amount, loyalty_discount_amount, late_pickup_discount_amount
  ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._guard_customer_booking_pricing();
