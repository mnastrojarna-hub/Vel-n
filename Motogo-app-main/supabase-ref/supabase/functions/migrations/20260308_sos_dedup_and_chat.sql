-- ═══════════════════════════════════════════════════════
-- 1. SOS TRIGGER DEDUPLICATION
--    Prevent duplicate admin_messages within 2 minutes
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION sos_notify_user_on_create()
RETURNS trigger AS $$
DECLARE
  v_type_label text;
  v_message text;
  v_title text;
  v_is_light boolean;
  v_exists boolean;
BEGIN
  -- Check if we already sent a message for this user in last 2 minutes
  SELECT EXISTS(
    SELECT 1 FROM admin_messages
    WHERE user_id = NEW.user_id
      AND type IN ('sos_response', 'sos_auto')
      AND created_at > now() - interval '2 minutes'
  ) INTO v_exists;

  IF v_exists THEN
    RETURN NEW;  -- Skip duplicate
  END IF;

  CASE NEW.type
    WHEN 'theft' THEN v_type_label := 'Krádež motorky';
    WHEN 'accident_minor' THEN v_type_label := 'Lehká nehoda';
    WHEN 'accident_major' THEN v_type_label := 'Závažná nehoda';
    WHEN 'breakdown_minor' THEN v_type_label := 'Drobná porucha';
    WHEN 'breakdown_major' THEN v_type_label := 'Vážná porucha';
    ELSE v_type_label := 'SOS hlášení';
  END CASE;

  v_is_light := NEW.type IN ('accident_minor', 'breakdown_minor', 'defect_question', 'location_share', 'other');

  IF v_is_light THEN
    v_title := 'Děkujeme za nahlášení';
    v_message := 'Děkujeme za nahlášení incidentu (' || v_type_label || '). Šťastnou cestu!';
  ELSE
    v_title := 'SOS přijato: ' || v_type_label;
    v_message := 'Vaše hlášení bylo přijato centrálou MotoGo24. ' ||
      COALESCE(NEW.description, '') ||
      ' Asistent vás bude kontaktovat.';
  END IF;

  INSERT INTO admin_messages (user_id, title, message, type)
  VALUES (
    NEW.user_id,
    v_title,
    v_message,
    CASE WHEN v_is_light THEN 'sos_auto' ELSE 'sos_response' END
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════
-- 2. BRIDGE TRIGGER DEDUP
--    Prevent duplicate bridge messages within 30 seconds
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION bridge_admin_message_to_app()
RETURNS trigger AS $$
DECLARE
  v_thread message_threads%ROWTYPE;
  v_customer_id uuid;
  v_title text;
  v_type text;
  v_exists boolean;
BEGIN
  IF NEW.direction != 'admin' THEN RETURN NEW; END IF;

  SELECT * INTO v_thread FROM message_threads WHERE id = NEW.thread_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  v_customer_id := v_thread.customer_id;
  IF v_customer_id IS NULL THEN RETURN NEW; END IF;

  -- Dedup: check if identical message was sent in last 30 seconds
  SELECT EXISTS(
    SELECT 1 FROM admin_messages
    WHERE user_id = v_customer_id
      AND message = NEW.content
      AND created_at > now() - interval '30 seconds'
  ) INTO v_exists;

  IF v_exists THEN RETURN NEW; END IF;

  IF v_thread.subject IS NOT NULL AND v_thread.subject LIKE 'SOS:%' THEN
    v_title := v_thread.subject;
    v_type := 'sos_response';
  ELSE
    v_title := COALESCE(v_thread.subject, 'Zpráva z MotoGo24');
    v_type := 'info';
  END IF;

  INSERT INTO admin_messages (user_id, title, message, type)
  VALUES (v_customer_id, v_title, NEW.content, v_type);

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════
-- 3. MESSAGING RLS — allow customers to read their threads
--    and send messages in their own threads
-- ═══════════════════════════════════════════════════════

-- message_threads: customer can read own threads
DROP POLICY IF EXISTS threads_customer_read ON message_threads;
CREATE POLICY threads_customer_read ON message_threads
  FOR SELECT USING (customer_id = auth.uid());

-- messages: customer can read messages in own threads
DROP POLICY IF EXISTS messages_customer_read ON messages;
CREATE POLICY messages_customer_read ON messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM message_threads
      WHERE message_threads.id = messages.thread_id
        AND message_threads.customer_id = auth.uid()
    )
  );

-- messages: customer can insert messages in own threads (direction='customer')
DROP POLICY IF EXISTS messages_customer_insert ON messages;
CREATE POLICY messages_customer_insert ON messages
  FOR INSERT WITH CHECK (
    direction = 'customer' AND
    EXISTS (
      SELECT 1 FROM message_threads
      WHERE message_threads.id = messages.thread_id
        AND message_threads.customer_id = auth.uid()
    )
  );

-- message_threads: customer can update own threads (last_message_at, status)
DROP POLICY IF EXISTS threads_customer_update ON message_threads;
CREATE POLICY threads_customer_update ON message_threads
  FOR UPDATE USING (customer_id = auth.uid());

-- message_threads: customer can create threads for themselves
DROP POLICY IF EXISTS threads_customer_insert ON message_threads;
CREATE POLICY threads_customer_insert ON message_threads
  FOR INSERT WITH CHECK (customer_id = auth.uid());
