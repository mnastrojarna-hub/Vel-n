-- =============================================================================
-- MIGRACE 2026-07-29: Automatická evidence změn rezervace do modification_history
--
-- Problém: změna ČASU vyzvednutí/vrácení i VÝBAVY se do bookings zapisuje
-- přímým UPDATE mimo historii — web /upravit-rezervaci dělá u změny jen času
-- přímý `bookings.update({pickup_time, return_time})`, RPC update_booking_gear
-- mění velikosti výbavy bez záznamu, Velín BookingDetail mění pole napřímo.
-- Výsledek: Velín, appka ani web nezobrazily změnu v historii úprav.
--
-- Řešení: BEFORE UPDATE trigger na bookings, který při změně sledovaných
-- zákaznických polí (termín, časy, motorka, místa vyzvednutí/vrácení, výbava)
-- automaticky připojí záznam do modification_history — ale JEN pokud si volající
-- nezapsal vlastní záznam ve stejném UPDATE (RPC _apply_booking_changes_core,
-- appka i Velín BookingModifyModal si historii píší samy → trigger se nepřidává,
-- žádné duplicity). Formát záznamu je shodný s existujícími: {at, from_start,
-- from_end, to_start, to_end, source} + volitelné from/to_pickup_time,
-- from/to_return_time, from/to_moto (model), from/to_pickup_method|address,
-- from/to_return_method|address, gear_changes {pole:{from,to}}, auto:true.
--
-- Zdroj: auth.uid() = user_id rezervace → 'customer'; is_admin() → 'admin';
-- jinak (service role, crony) → 'system'.
-- Exception-safe: chyba evidence NIKDY neshodí update rezervace (log do
-- debug_log). Idempotentní (CREATE OR REPLACE + DROP TRIGGER IF EXISTS).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.track_booking_content_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry  jsonb;
  v_gear   jsonb := '{}'::jsonb;
  v_uid    uuid;
  v_source text;
  v_from_moto text;
  v_to_moto   text;
  v_changed boolean;
BEGIN
  -- Volající už zapsal vlastní záznam v tomto UPDATE → nic nepřidávat
  IF NEW.modification_history IS DISTINCT FROM OLD.modification_history THEN
    RETURN NEW;
  END IF;

  BEGIN
    -- Výbava (jen změněná pole)
    IF NEW.helmet_size IS DISTINCT FROM OLD.helmet_size THEN
      v_gear := v_gear || jsonb_build_object('helmet', jsonb_build_object('from', OLD.helmet_size, 'to', NEW.helmet_size));
    END IF;
    IF NEW.jacket_size IS DISTINCT FROM OLD.jacket_size THEN
      v_gear := v_gear || jsonb_build_object('jacket', jsonb_build_object('from', OLD.jacket_size, 'to', NEW.jacket_size));
    END IF;
    IF NEW.pants_size IS DISTINCT FROM OLD.pants_size THEN
      v_gear := v_gear || jsonb_build_object('pants', jsonb_build_object('from', OLD.pants_size, 'to', NEW.pants_size));
    END IF;
    IF NEW.boots_size IS DISTINCT FROM OLD.boots_size THEN
      v_gear := v_gear || jsonb_build_object('boots', jsonb_build_object('from', OLD.boots_size, 'to', NEW.boots_size));
    END IF;
    IF NEW.gloves_size IS DISTINCT FROM OLD.gloves_size THEN
      v_gear := v_gear || jsonb_build_object('gloves', jsonb_build_object('from', OLD.gloves_size, 'to', NEW.gloves_size));
    END IF;
    IF NEW.passenger_helmet_size IS DISTINCT FROM OLD.passenger_helmet_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_helmet', jsonb_build_object('from', OLD.passenger_helmet_size, 'to', NEW.passenger_helmet_size));
    END IF;
    IF NEW.passenger_jacket_size IS DISTINCT FROM OLD.passenger_jacket_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_jacket', jsonb_build_object('from', OLD.passenger_jacket_size, 'to', NEW.passenger_jacket_size));
    END IF;
    IF NEW.passenger_pants_size IS DISTINCT FROM OLD.passenger_pants_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_pants', jsonb_build_object('from', OLD.passenger_pants_size, 'to', NEW.passenger_pants_size));
    END IF;
    IF NEW.passenger_boots_size IS DISTINCT FROM OLD.passenger_boots_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_boots', jsonb_build_object('from', OLD.passenger_boots_size, 'to', NEW.passenger_boots_size));
    END IF;
    IF NEW.passenger_gloves_size IS DISTINCT FROM OLD.passenger_gloves_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_gloves', jsonb_build_object('from', OLD.passenger_gloves_size, 'to', NEW.passenger_gloves_size));
    END IF;

    v_changed := (
      NEW.start_date      IS DISTINCT FROM OLD.start_date
      OR NEW.end_date     IS DISTINCT FROM OLD.end_date
      OR NEW.pickup_time  IS DISTINCT FROM OLD.pickup_time
      OR NEW.return_time  IS DISTINCT FROM OLD.return_time
      OR NEW.moto_id      IS DISTINCT FROM OLD.moto_id
      OR NEW.pickup_method  IS DISTINCT FROM OLD.pickup_method
      OR NEW.pickup_address IS DISTINCT FROM OLD.pickup_address
      OR NEW.return_method  IS DISTINCT FROM OLD.return_method
      OR NEW.return_address IS DISTINCT FROM OLD.return_address
      OR v_gear <> '{}'::jsonb
    );
    IF NOT v_changed THEN
      RETURN NEW;
    END IF;

    v_uid := auth.uid();
    IF v_uid IS NULL THEN
      v_source := 'system';
    ELSIF v_uid = COALESCE(NEW.user_id, OLD.user_id) THEN
      v_source := 'customer';
    ELSIF public.is_admin() THEN
      v_source := 'admin';
    ELSE
      v_source := 'system';
    END IF;

    v_entry := jsonb_build_object(
      'at', now(), 'auto', true, 'source', v_source,
      'from_start', OLD.start_date, 'from_end', OLD.end_date,
      'to_start',   NEW.start_date, 'to_end',   NEW.end_date
    );

    IF NEW.pickup_time IS DISTINCT FROM OLD.pickup_time THEN
      v_entry := v_entry || jsonb_build_object(
        'from_pickup_time', OLD.pickup_time::text, 'to_pickup_time', NEW.pickup_time::text);
    END IF;
    IF NEW.return_time IS DISTINCT FROM OLD.return_time THEN
      v_entry := v_entry || jsonb_build_object(
        'from_return_time', OLD.return_time::text, 'to_return_time', NEW.return_time::text);
    END IF;

    IF NEW.moto_id IS DISTINCT FROM OLD.moto_id THEN
      SELECT model INTO v_from_moto FROM motorcycles WHERE id = OLD.moto_id;
      SELECT model INTO v_to_moto   FROM motorcycles WHERE id = NEW.moto_id;
      v_entry := v_entry || jsonb_build_object(
        'from_moto', COALESCE(v_from_moto, OLD.moto_id::text),
        'to_moto',   COALESCE(v_to_moto,   NEW.moto_id::text));
    END IF;

    IF NEW.pickup_method IS DISTINCT FROM OLD.pickup_method THEN
      v_entry := v_entry || jsonb_build_object(
        'from_pickup_method', OLD.pickup_method, 'to_pickup_method', NEW.pickup_method);
    END IF;
    IF NEW.pickup_address IS DISTINCT FROM OLD.pickup_address THEN
      v_entry := v_entry || jsonb_build_object(
        'from_pickup_address', OLD.pickup_address, 'to_pickup_address', NEW.pickup_address);
    END IF;
    IF NEW.return_method IS DISTINCT FROM OLD.return_method THEN
      v_entry := v_entry || jsonb_build_object(
        'from_return_method', OLD.return_method, 'to_return_method', NEW.return_method);
    END IF;
    IF NEW.return_address IS DISTINCT FROM OLD.return_address THEN
      v_entry := v_entry || jsonb_build_object(
        'from_return_address', OLD.return_address, 'to_return_address', NEW.return_address);
    END IF;

    IF v_gear <> '{}'::jsonb THEN
      v_entry := v_entry || jsonb_build_object('gear_changes', v_gear);
    END IF;

    NEW.modification_history := COALESCE(OLD.modification_history, '[]'::jsonb) || v_entry;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      INSERT INTO debug_log(source, action, status, error_message)
      VALUES ('track_booking_content_changes', 'append_history', 'error', SQLERRM);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_track_booking_content_changes ON public.bookings;
CREATE TRIGGER trg_track_booking_content_changes
  BEFORE UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.track_booking_content_changes();
