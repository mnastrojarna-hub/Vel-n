-- ============================================================
-- MotoGo24: app_crash_reports table
-- Run this in Supabase SQL Editor to create the crash reports table.
-- The Flutter app pushes error data here; Velín reads and displays it.
-- ============================================================

CREATE TABLE IF NOT EXISTS app_crash_reports (
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at    timestamptz DEFAULT now() NOT NULL,

  -- Who
  user_id       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  app_version   text,
  platform      text,                   -- 'android' | 'ios'

  -- Where
  screen        text,                   -- current screen/route name
  action        text,                   -- button/flow that triggered it

  -- What
  error_type    text NOT NULL,          -- exception class name
  error_message text NOT NULL,          -- error.toString()
  stack_trace   text,                   -- trimmed to 4000 chars
  severity      text DEFAULT 'error',   -- 'info' | 'warning' | 'error' | 'critical'

  -- Extra context (JSON)
  extra_data    jsonb
);

-- Index for Velín dashboard queries
CREATE INDEX IF NOT EXISTS idx_crash_reports_created
  ON app_crash_reports (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_crash_reports_severity
  ON app_crash_reports (severity, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_crash_reports_user
  ON app_crash_reports (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_crash_reports_screen
  ON app_crash_reports (screen, created_at DESC);

-- RLS: customers can only INSERT their own reports, admins can read all
ALTER TABLE app_crash_reports ENABLE ROW LEVEL SECURITY;

-- Customers: can insert reports (user_id must match or be null for anonymous)
CREATE POLICY crash_reports_insert_own ON app_crash_reports
  FOR INSERT
  WITH CHECK (
    user_id IS NULL OR user_id = auth.uid()
  );

-- Customers: cannot read crash reports
-- (no SELECT policy for anon/authenticated role)

-- Admins: full access (uses is_admin() function from existing setup)
CREATE POLICY crash_reports_admin_all ON app_crash_reports
  FOR ALL
  USING (
    EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
  );

-- Auto-update timestamp trigger (optional, created_at is already DEFAULT now())
-- Useful if you want an updated_at column later.

COMMENT ON TABLE app_crash_reports IS
  'Flutter app crash reports — automatically pushed from the mobile app. '
  'Read by Velín admin dashboard for monitoring and debugging.';


-- ============================================================
-- MotoGo24: app_debug_logs table
-- High-volume debug logs — EVERY action, screen, API call, tap.
-- ============================================================

CREATE TABLE IF NOT EXISTS app_debug_logs (
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at    timestamptz DEFAULT now() NOT NULL,

  -- Who
  user_id       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  app_version   text,
  platform      text,                   -- 'android' | 'ios'

  -- What
  category      text NOT NULL,          -- 'navigation' | 'api' | 'auth' | 'payment' | 'booking' | 'sos' | 'shop' | 'push' | 'network' | 'permission' | 'document' | 'ui' | 'lifecycle' | 'error'
  action        text NOT NULL,          -- specific action name
  detail        text,                   -- human-readable detail
  data          jsonb,                  -- structured data (params, response, etc.)
  duration_ms   integer                 -- timing for API calls
);

-- Indexes for Velín queries
CREATE INDEX IF NOT EXISTS idx_debug_logs_created
  ON app_debug_logs (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_debug_logs_category
  ON app_debug_logs (category, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_debug_logs_user
  ON app_debug_logs (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_debug_logs_user_category
  ON app_debug_logs (user_id, category, created_at DESC);

-- RLS
ALTER TABLE app_debug_logs ENABLE ROW LEVEL SECURITY;

-- Customers: can only INSERT their own logs
CREATE POLICY debug_logs_insert_own ON app_debug_logs
  FOR INSERT
  WITH CHECK (
    user_id IS NULL OR user_id = auth.uid()
  );

-- Admins: full access
CREATE POLICY debug_logs_admin_all ON app_debug_logs
  FOR ALL
  USING (
    EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
  );

-- Auto-cleanup: delete logs older than 30 days (run as cron job)
-- SELECT cron.schedule('cleanup_debug_logs', '0 3 * * *',
--   $$DELETE FROM app_debug_logs WHERE created_at < now() - interval '30 days'$$);

COMMENT ON TABLE app_debug_logs IS
  'High-volume debug logs from Flutter app. Every screen, API call, button tap, '
  'payment step, auth event, etc. Auto-cleanup after 30 days recommended.';

-- ============================================================
-- Velín views for easy querying
-- ============================================================

-- Recent crashes (last 24h)
CREATE OR REPLACE VIEW v_recent_crashes AS
SELECT
  cr.id,
  cr.created_at,
  cr.severity,
  cr.error_type,
  cr.error_message,
  cr.screen,
  cr.action,
  cr.platform,
  cr.app_version,
  p.full_name AS user_name,
  p.email AS user_email
FROM app_crash_reports cr
LEFT JOIN profiles p ON p.id = cr.user_id
WHERE cr.created_at > now() - interval '24 hours'
ORDER BY cr.created_at DESC;

-- User session timeline (for debugging specific user)
CREATE OR REPLACE VIEW v_user_debug_timeline AS
SELECT
  dl.id,
  dl.created_at,
  dl.category,
  dl.action,
  dl.detail,
  dl.data,
  dl.duration_ms,
  dl.platform,
  dl.app_version,
  dl.user_id
FROM app_debug_logs dl
WHERE dl.created_at > now() - interval '7 days'
ORDER BY dl.created_at DESC;

-- API performance stats (last 24h)
CREATE OR REPLACE VIEW v_api_performance AS
SELECT
  action,
  count(*) AS call_count,
  avg(duration_ms)::int AS avg_ms,
  max(duration_ms) AS max_ms,
  count(*) FILTER (WHERE detail LIKE 'error%') AS error_count
FROM app_debug_logs
WHERE category = 'api'
  AND created_at > now() - interval '24 hours'
GROUP BY action
ORDER BY error_count DESC, avg_ms DESC;

-- Error rate per screen (last 24h)
CREATE OR REPLACE VIEW v_screen_error_rate AS
SELECT
  screen,
  count(*) AS total_crashes,
  count(DISTINCT user_id) AS affected_users,
  max(created_at) AS last_crash
FROM app_crash_reports
WHERE created_at > now() - interval '24 hours'
GROUP BY screen
ORDER BY total_crashes DESC;
