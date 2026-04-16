-- =====================================================
-- FIX: Missing RPCs for marking thread messages as read
-- Problem: Frontend calls mark_thread_messages_read() and
--          get_unread_thread_message_count() but they don't exist.
--          Messages never get read_at set → unread badges persist forever.
-- =====================================================

-- 1) RPC: Mark all admin messages in a thread as read
--    Called when customer opens a thread in the app.
--    SECURITY DEFINER so customer can UPDATE messages (RLS only allows SELECT/INSERT).
CREATE OR REPLACE FUNCTION mark_thread_messages_read(p_thread_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
BEGIN
  -- Verify the thread belongs to the calling user
  SELECT customer_id INTO v_customer_id
  FROM message_threads
  WHERE id = p_thread_id;

  IF v_customer_id IS NULL OR v_customer_id != auth.uid() THEN
    RETURN; -- not their thread, silently ignore
  END IF;

  -- Mark all admin messages in this thread as read
  UPDATE messages
  SET read_at = now()
  WHERE thread_id = p_thread_id
    AND direction = 'admin'
    AND read_at IS NULL;
END;
$$;

-- 2) RPC: Count unread admin messages across all customer's threads
--    Used for the badge count in the mobile app.
--    SECURITY DEFINER to bypass RLS for counting.
CREATE OR REPLACE FUNCTION get_unread_thread_message_count(p_customer_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  -- Only allow querying own count
  IF p_customer_id != auth.uid() THEN
    RETURN 0;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM messages m
  JOIN message_threads t ON t.id = m.thread_id
  WHERE t.customer_id = p_customer_id
    AND m.direction = 'admin'
    AND m.read_at IS NULL;

  RETURN COALESCE(v_count, 0);
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION mark_thread_messages_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_unread_thread_message_count(uuid) TO authenticated;
