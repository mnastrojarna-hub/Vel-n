-- ════════════════════════════════════════════════════════════════════
-- VĚRNOST 2026-09-17 — APLIKOVÁNO v živé DB 2026-09-17 (potvrzeno uživatelem:
-- loyalty_refresh_points_floor → 104 profilů). Soubor je idempotentní,
-- opakovaná aplikace přes deploy-sql.yml nic nerozbije.
--  • body: 1–6 dní = 1 bod, 7 a více dní = 2 body (app i web)
--  • NIKOHO NEDEGRADOVAT — jednorázové dorovnání do loyalty_bonus_points
--  • rank zůstává napořád (strop bodů, který nikdy neklesne)
--  • ruční degradace ranku z Velína (např. po nehodě)
--  • ruční zápis poškození u rezervace z Velína
--  • žebříček: 1. kritérium postup ranků, 2. km bez nehody a škrábnutí
--  • přezdívka nepovinná — default „křestní jméno #číslo"
--  • feature flag `loyalty_leaderboard` = OFF (v appce se zatím nezobrazuje)
-- ════════════════════════════════════════════════════════════════════

-- POZOR: bez explicitniho BEGIN/COMMIT — deploy-sql.yml pousti kazdy soubor
-- pres `psql --single-transaction`, takze transakci uz drzi workflow.

-- ── 1) Sloupce ──────────────────────────────────────────────────────
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS loyalty_points_floor   int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS loyalty_points_penalty int NOT NULL DEFAULT 0;

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS damage_flag       boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS damage_note       text,
  ADD COLUMN IF NOT EXISTS damage_flagged_at timestamptz,
  ADD COLUMN IF NOT EXISTS damage_flagged_by uuid;

CREATE INDEX IF NOT EXISTS idx_bookings_damage_flag
  ON bookings (damage_flag) WHERE damage_flag = true;

ALTER TABLE loyalty_monthly_winners
  ADD COLUMN IF NOT EXISTS km        int,
  ADD COLUMN IF NOT EXISTS rank_gain int;

-- Audit ručních zásahů do ranku (+ značka jednorázového dorovnání).
CREATE TABLE IF NOT EXISTS loyalty_rank_adjustments (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid REFERENCES profiles(id) ON DELETE CASCADE,
  ranks        int  NOT NULL DEFAULT 0,   -- záporné = degradace, kladné = vrácení
  points_delta int  NOT NULL DEFAULT 0,   -- 2 body = 1 rank
  reason       text,
  admin_id     uuid,
  created_at   timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE loyalty_rank_adjustments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin all" ON loyalty_rank_adjustments;
CREATE POLICY "Admin all" ON loyalty_rank_adjustments FOR ALL USING (is_admin());

-- ── 2) Hrubé body podle NOVÉHO pravidla ─────────────────────────────
-- 1–6 dní = 1 bod, 7 a více dní = 2 body. Rezervace z appky I z webu
-- (sleva se ale nadále uplatňuje jen v appce — to řeší jiný trigger).
CREATE OR REPLACE FUNCTION _loyalty_raw_points(p_user_id uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(SUM(
    CASE WHEN (end_date::date - start_date::date + 1) >= 7 THEN 2 ELSE 1 END
  ), 0)::int
  FROM bookings
  WHERE user_id = p_user_id
    AND status = 'completed'
    AND COALESCE(is_test, false) = false;
$$;
REVOKE ALL ON FUNCTION _loyalty_raw_points(uuid) FROM PUBLIC, anon, authenticated;

-- ── 3) Kvalifikační body = hrubé, ale NIKDY pod dosažené maximum ────
-- (rank navždy) mínus ruční degradace z Velína. Tím se floor/penalizace
-- propíše i do get_loyalty_status a do serverového guardu slevy —
-- žádná další funkce se kvůli tomu nemusí měnit.
CREATE OR REPLACE FUNCTION _loyalty_qualifying_count(p_user_id uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT GREATEST(0,
      GREATEST(
        _loyalty_raw_points(p_user_id),
        COALESCE((SELECT loyalty_points_floor   FROM profiles WHERE id = p_user_id), 0)
      )
      - COALESCE((SELECT loyalty_points_penalty FROM profiles WHERE id = p_user_id), 0)
  )::int;
$$;
REVOKE ALL ON FUNCTION _loyalty_qualifying_count(uuid) FROM PUBLIC, anon, authenticated;

-- ── 4) Údržba stropu „rank navždy" ──────────────────────────────────
CREATE OR REPLACE FUNCTION loyalty_refresh_points_floor(p_user_id uuid DEFAULT NULL)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  UPDATE profiles p
     SET loyalty_points_floor = _loyalty_raw_points(p.id)
   WHERE (p_user_id IS NULL OR p.id = p_user_id)
     AND COALESCE(p.loyalty_points_floor, 0) < _loyalty_raw_points(p.id);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION loyalty_refresh_points_floor(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION trg_loyalty_floor_on_complete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.user_id IS NOT NULL AND NEW.status = 'completed' THEN
    PERFORM loyalty_refresh_points_floor(NEW.user_id);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_loyalty_floor_on_complete: %', SQLERRM;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_loyalty_floor ON bookings;
CREATE TRIGGER trg_loyalty_floor
  AFTER INSERT OR UPDATE OF status ON bookings
  FOR EACH ROW EXECUTE FUNCTION trg_loyalty_floor_on_complete();

-- ── 5) JEDNORÁZOVÉ DOROVNÁNÍ — nikoho nedegradovat ──────────────────
-- Staré pravidlo: > 7 dní = 4 body, jinak 1. Nové: >= 7 dní = 2, jinak 1.
-- Komu by body klesly, dostane rozdíl trvale do loyalty_bonus_points.
DO $$
DECLARE v_cnt int := 0;
BEGIN
  IF EXISTS (SELECT 1 FROM loyalty_rank_adjustments WHERE reason = 'grandfather-2026-09') THEN
    RAISE NOTICE 'Dorovnání grandfather-2026-09 už proběhlo — přeskakuji.';
  ELSE
    WITH old_new AS (
      SELECT b.user_id,
             SUM(CASE WHEN (b.end_date::date - b.start_date::date + 1) >  7 THEN 4 ELSE 1 END)::int AS old_pts,
             SUM(CASE WHEN (b.end_date::date - b.start_date::date + 1) >= 7 THEN 2 ELSE 1 END)::int AS new_pts
        FROM bookings b
       WHERE b.status = 'completed'
         AND COALESCE(b.is_test, false) = false
         AND b.user_id IS NOT NULL
       GROUP BY b.user_id
    ), diff AS (
      SELECT user_id, (old_pts - new_pts) AS bonus
        FROM old_new WHERE old_pts > new_pts
    ), upd AS (
      UPDATE profiles p
         SET loyalty_bonus_points = COALESCE(p.loyalty_bonus_points, 0) + d.bonus
        FROM diff d WHERE p.id = d.user_id
      RETURNING p.id, d.bonus
    ), ins AS (
      INSERT INTO loyalty_rank_adjustments (user_id, ranks, points_delta, reason)
      SELECT id, 0, bonus, 'grandfather-2026-09' FROM upd
      RETURNING 1
    )
    SELECT COUNT(*) INTO v_cnt FROM ins;

    -- Značka, že dorovnání proběhlo (i když nikoho nebylo třeba dorovnat).
    INSERT INTO loyalty_rank_adjustments (user_id, ranks, points_delta, reason)
    VALUES (NULL, 0, 0, 'grandfather-2026-09');
    RAISE NOTICE 'Dorovnáno zákazníků: %', v_cnt;
  END IF;
END $$;

-- Strop „rank navždy" nastavit všem na aktuální hrubé body.
SELECT loyalty_refresh_points_floor(NULL);

-- ── 6) Poškození — ruční zápis z Velína ─────────────────────────────
CREATE OR REPLACE FUNCTION admin_set_booking_damage(
  p_booking_id uuid, p_damage boolean, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_dmg boolean := COALESCE(p_damage, false);
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  UPDATE bookings
     SET damage_flag       = v_dmg,
         damage_note       = CASE WHEN v_dmg THEN NULLIF(btrim(COALESCE(p_note,'')), '') ELSE NULL END,
         damage_flagged_at = CASE WHEN v_dmg THEN now() ELSE NULL END,
         damage_flagged_by = CASE WHEN v_dmg THEN v_uid ELSE NULL END
   WHERE id = p_booking_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'booking not found'; END IF;
  RETURN jsonb_build_object('status', 'ok', 'booking_id', p_booking_id, 'damage', v_dmg);
END; $$;
REVOKE ALL ON FUNCTION admin_set_booking_damage(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_set_booking_damage(uuid, boolean, text) TO authenticated;

-- ── 7) Ruční degradace / vrácení ranku z Velína ─────────────────────
-- p_ranks < 0 = degradace (např. −1 po nehodě), p_ranks > 0 = vrácení.
-- 1 rank = 2 body; penalizace nikdy neklesne pod 0.
CREATE OR REPLACE FUNCTION admin_loyalty_adjust_rank(
  p_user_id uuid, p_ranks int, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_pen int; v_cnt int; v_lvl int;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF COALESCE(p_ranks, 0) = 0 THEN RAISE EXCEPTION 'p_ranks nesmí být 0'; END IF;

  UPDATE profiles
     SET loyalty_points_penalty = GREATEST(0, COALESCE(loyalty_points_penalty, 0) - (p_ranks * 2))
   WHERE id = p_user_id
  RETURNING loyalty_points_penalty INTO v_pen;
  IF v_pen IS NULL THEN RAISE EXCEPTION 'profil nenalezen'; END IF;

  INSERT INTO loyalty_rank_adjustments (user_id, ranks, points_delta, reason, admin_id)
  VALUES (p_user_id, p_ranks, p_ranks * 2, NULLIF(btrim(COALESCE(p_reason,'')), ''), auth.uid());

  v_cnt := _loyalty_effective_count(p_user_id);
  v_lvl := LEAST(20, CEIL((v_cnt + 1) / 2.0))::int;
  RETURN jsonb_build_object('status','ok','penalty_points', v_pen,
                            'points', v_cnt, 'level', v_lvl);
END; $$;
REVOKE ALL ON FUNCTION admin_loyalty_adjust_rank(uuid, int, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_loyalty_adjust_rank(uuid, int, text) TO authenticated;

-- Rank zákazníka pro Velín (jeden zdroj pravdy místo počítání v JS).
CREATE OR REPLACE FUNCTION admin_loyalty_status(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cnt int; v_lvl int; v_row loyalty_levels%ROWTYPE; v_p profiles%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  SELECT * INTO v_p FROM profiles WHERE id = p_user_id;
  IF v_p.id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
  v_cnt := _loyalty_effective_count(p_user_id);
  v_lvl := LEAST(20, CEIL((v_cnt + 1) / 2.0))::int;
  SELECT * INTO v_row FROM loyalty_levels WHERE level = v_lvl;
  RETURN jsonb_build_object(
    'level', v_lvl,
    'rank_name', COALESCE(v_row.name, 'Startér'),
    'percent', COALESCE(v_row.discount_percent, v_lvl),
    'color_hex', COALESCE(v_row.color_hex, '#9CA3AF'),
    'points', v_cnt,
    'raw_points', _loyalty_raw_points(p_user_id),
    'floor_points', COALESCE(v_p.loyalty_points_floor, 0),
    'penalty_points', COALESCE(v_p.loyalty_points_penalty, 0),
    'bonus_points', COALESCE(v_p.loyalty_bonus_points, 0)
  );
END; $$;
REVOKE ALL ON FUNCTION admin_loyalty_status(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_loyalty_status(uuid) TO authenticated;

-- ── 8) Žebříček — postup ranků, při shodě km bez nehody ─────────────
CREATE OR REPLACE FUNCTION get_loyalty_leaderboard(p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ms date := date_trunc('month', CURRENT_DATE)::date;
  v_me date := (date_trunc('month', CURRENT_DATE) + interval '1 month')::date;
  v_rows jsonb; v_win jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','unauthenticated'); END IF;

  WITH month_days AS (
    SELECT b.user_id,
           SUM((b.end_date::date - b.start_date::date) + 1)::int AS days
      FROM bookings b
     WHERE b.status IN ('active','completed')
       AND COALESCE(b.is_test, false) = false
       AND b.user_id IS NOT NULL
       AND b.start_date >= v_ms AND b.start_date < v_me
     GROUP BY b.user_id
  ),
  clean_km AS (
    -- Km se berou z předávacích protokolů: rozdíl po sobě jdoucích
    -- `mileage_start` téže motorky (stav při převzetí je stav PŘED jízdou),
    -- takže km patří té výpůjčce, která je najela. Rezervace s ručně
    -- zapsaným poškozením se do „km bez nehody a škrábnutí" nepočítají.
    SELECT k.user_id, COALESCE(SUM(k.km_driven), 0)::int AS km
      FROM analytics_moto_rental_km() k
      JOIN bookings b ON b.id = k.booking_id
     WHERE k.user_id IS NOT NULL
       AND k.next_reading IS NOT NULL
       AND k.start_date >= v_ms AND k.start_date < v_me
       AND COALESCE(b.damage_flag, false) = false
     GROUP BY k.user_id
  ),
  base AS (
    SELECT p.id,
           btrim(COALESCE(p.loyalty_nickname, '')) AS nick_set,
           btrim(COALESCE(p.full_name, ''))        AS full_name,
           COALESCE(p.loyalty_bonus_points, 0)     AS bonus,
           COALESCE(p.loyalty_points_penalty, 0)   AS penalty,
           COALESCE(p.loyalty_points_floor, 0)     AS floor_pts,
           COALESCE((SELECT SUM(CASE WHEN (b.end_date::date - b.start_date::date + 1) >= 7 THEN 2 ELSE 1 END)
                       FROM bookings b
                      WHERE b.user_id = p.id AND b.status = 'completed'
                        AND COALESCE(b.is_test, false) = false), 0)::int AS pts_now,
           COALESCE((SELECT SUM(CASE WHEN (b.end_date::date - b.start_date::date + 1) >= 7 THEN 2 ELSE 1 END)
                       FROM bookings b
                      WHERE b.user_id = p.id AND b.status = 'completed'
                        AND COALESCE(b.is_test, false) = false
                        AND b.end_date < v_ms), 0)::int AS pts_before
      FROM profiles p
     WHERE COALESCE(p.loyalty_leaderboard_opt_in, true) = true
  ),
  ranked AS (
    SELECT bs.id,
           COALESCE(
             NULLIF(bs.nick_set, ''),
             NULLIF(split_part(bs.full_name, ' ', 1), '') || ' #' ||
               (100 + (abs(hashtext(bs.id::text)::bigint) % 900))::text,
             'Pilot #' || (100 + (abs(hashtext(bs.id::text)::bigint) % 900))::text
           ) AS nick,
           COALESCE(md.days, 0) AS days,
           COALESCE(ck.km, 0)   AS km,
           LEAST(20, CEIL((GREATEST(0, GREATEST(bs.pts_now, bs.floor_pts) - bs.penalty)
                           + bs.bonus + 1) / 2.0))::int AS lvl_now,
           LEAST(20, CEIL((GREATEST(0, bs.pts_before - bs.penalty)
                           + bs.bonus + 1) / 2.0))::int AS lvl_before
      FROM base bs
      LEFT JOIN month_days md ON md.user_id = bs.id
      LEFT JOIN clean_km  ck ON ck.user_id = bs.id
     WHERE COALESCE(md.days, 0) > 0 OR COALESCE(ck.km, 0) > 0
  ),
  numbered AS (
    SELECT r.*,
           GREATEST(0, r.lvl_now - r.lvl_before) AS rank_gain,
           ROW_NUMBER() OVER (
             ORDER BY GREATEST(0, r.lvl_now - r.lvl_before) DESC,
                      r.km DESC, r.lvl_now DESC, r.days DESC, r.id
           ) AS rn
      FROM ranked r
  )
  SELECT jsonb_agg(jsonb_build_object(
    'rank_pos', n.rn, 'nickname', n.nick,
    'days', n.days, 'km', n.km, 'rank_gain', n.rank_gain,
    'level', n.lvl_now, 'percent', n.lvl_now,
    'rank_name', ll.name, 'color_hex', ll.color_hex,
    'is_me', (n.id = v_uid)
  ) ORDER BY n.rn)
  INTO v_rows
  FROM numbered n LEFT JOIN loyalty_levels ll ON ll.level = n.lvl_now
  WHERE n.rn <= p_limit;

  SELECT jsonb_build_object('nickname', w.nickname, 'days', w.days,
                            'km', w.km, 'rank_gain', w.rank_gain,
                            'month', to_char(w.month, 'YYYY-MM'))
    INTO v_win
  FROM loyalty_monthly_winners w
  WHERE w.user_id IS NOT NULL
  ORDER BY w.month DESC LIMIT 1;

  RETURN jsonb_build_object(
    'month', to_char(v_ms, 'YYYY-MM'),
    'entries', COALESCE(v_rows, '[]'::jsonb),
    'last_winner', v_win
  );
END; $$;
REVOKE ALL ON FUNCTION get_loyalty_leaderboard(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_loyalty_leaderboard(integer) TO authenticated;

-- ── 9) Měsíční vítěz — stejná kritéria jako žebříček ────────────────
CREATE OR REPLACE FUNCTION loyalty_award_monthly_winner(
  p_month date DEFAULT (date_trunc('month'::text, (CURRENT_DATE - '1 day'::interval)))::date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_start date := date_trunc('month', p_month)::date;
  v_end   date := (date_trunc('month', p_month) + interval '1 month')::date;
  v_winner uuid; v_nick text; v_days int; v_km int; v_gain int; v_lvl int;
BEGIN
  IF EXISTS (SELECT 1 FROM loyalty_monthly_winners WHERE month = v_start) THEN
    RETURN jsonb_build_object('status','already_awarded','month',to_char(v_start,'YYYY-MM'));
  END IF;

  WITH month_days AS (
    SELECT b.user_id, SUM((b.end_date::date - b.start_date::date) + 1)::int AS days
      FROM bookings b
     WHERE b.status IN ('active','completed')
       AND COALESCE(b.is_test, false) = false AND b.user_id IS NOT NULL
       AND b.start_date >= v_start AND b.start_date < v_end
     GROUP BY b.user_id
  ),
  clean_km AS (
    SELECT k.user_id, COALESCE(SUM(k.km_driven), 0)::int AS km
      FROM analytics_moto_rental_km() k
      JOIN bookings b ON b.id = k.booking_id
     WHERE k.user_id IS NOT NULL AND k.next_reading IS NOT NULL
       AND k.start_date >= v_start AND k.start_date < v_end
       AND COALESCE(b.damage_flag, false) = false
     GROUP BY k.user_id
  ),
  base AS (
    SELECT p.id,
           COALESCE(
             NULLIF(btrim(COALESCE(p.loyalty_nickname,'')), ''),
             NULLIF(split_part(btrim(COALESCE(p.full_name,'')), ' ', 1), '') || ' #' ||
               (100 + (abs(hashtext(p.id::text)::bigint) % 900))::text,
             'Pilot #' || (100 + (abs(hashtext(p.id::text)::bigint) % 900))::text
           ) AS nick,
           COALESCE(p.loyalty_bonus_points, 0)   AS bonus,
           COALESCE(p.loyalty_points_penalty, 0) AS penalty,
           COALESCE(p.loyalty_points_floor, 0)   AS floor_pts,
           COALESCE((SELECT SUM(CASE WHEN (b.end_date::date - b.start_date::date + 1) >= 7 THEN 2 ELSE 1 END)
                       FROM bookings b
                      WHERE b.user_id = p.id AND b.status = 'completed'
                        AND COALESCE(b.is_test, false) = false
                        AND b.end_date < v_end), 0)::int AS pts_now,
           COALESCE((SELECT SUM(CASE WHEN (b.end_date::date - b.start_date::date + 1) >= 7 THEN 2 ELSE 1 END)
                       FROM bookings b
                      WHERE b.user_id = p.id AND b.status = 'completed'
                        AND COALESCE(b.is_test, false) = false
                        AND b.end_date < v_start), 0)::int AS pts_before
      FROM profiles p
     WHERE COALESCE(p.loyalty_leaderboard_opt_in, true) = true
  )
  SELECT bs.id, bs.nick, COALESCE(md.days,0), COALESCE(ck.km,0),
         GREATEST(0,
           LEAST(20, CEIL((GREATEST(0, GREATEST(bs.pts_now, bs.floor_pts) - bs.penalty) + bs.bonus + 1)/2.0))::int
           - LEAST(20, CEIL((GREATEST(0, bs.pts_before - bs.penalty) + bs.bonus + 1)/2.0))::int)
    INTO v_winner, v_nick, v_days, v_km, v_gain
    FROM base bs
    LEFT JOIN month_days md ON md.user_id = bs.id
    LEFT JOIN clean_km  ck ON ck.user_id = bs.id
   WHERE COALESCE(md.days,0) > 0 OR COALESCE(ck.km,0) > 0
   ORDER BY GREATEST(0,
              LEAST(20, CEIL((GREATEST(0, GREATEST(bs.pts_now, bs.floor_pts) - bs.penalty) + bs.bonus + 1)/2.0))::int
              - LEAST(20, CEIL((GREATEST(0, bs.pts_before - bs.penalty) + bs.bonus + 1)/2.0))::int) DESC,
            COALESCE(ck.km,0) DESC, COALESCE(md.days,0) DESC, bs.id ASC
   LIMIT 1;

  IF v_winner IS NULL THEN
    INSERT INTO loyalty_monthly_winners(month, days, km, rank_gain) VALUES (v_start, 0, 0, 0);
    RETURN jsonb_build_object('status','no_participants','month',to_char(v_start,'YYYY-MM'));
  END IF;

  v_lvl := LEAST(20, CEIL((_loyalty_effective_count(v_winner) + 1) / 2.0))::int;
  UPDATE profiles SET loyalty_bonus_points = COALESCE(loyalty_bonus_points, 0) + 4
   WHERE id = v_winner;
  INSERT INTO loyalty_monthly_winners(month, user_id, nickname, days, km, rank_gain, awarded_level_before)
  VALUES (v_start, v_winner, v_nick, v_days, v_km, v_gain, v_lvl);

  RETURN jsonb_build_object('status','awarded','month',to_char(v_start,'YYYY-MM'),
    'winner', v_nick, 'days', v_days, 'km', v_km, 'rank_gain', v_gain, 'bonus_points', 4);
END; $$;

-- ── 10) Feature flag — v appce zatím NEzobrazovat ───────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM feature_flags WHERE key = 'loyalty_leaderboard') THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='feature_flags' AND column_name='name') THEN
      INSERT INTO feature_flags (key, name, enabled)
      VALUES ('loyalty_leaderboard', 'Žebříček jezdců v appce', false);
    ELSE
      INSERT INTO feature_flags (key, enabled) VALUES ('loyalty_leaderboard', false);
    END IF;
  END IF;
END $$;

