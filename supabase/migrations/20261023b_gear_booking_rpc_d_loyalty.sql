-- =============================================================================
-- 2026-10-23 (b/4): Věrnostní program BEZ výpůjček jen výbavy
-- Rozhodnutí majitele: výpůjčka výbavy (booking_kind='gear') nesbírá body,
-- nedává % slevy, nepočítá se do dní v měsíčním žebříčku ani do vítěze měsíce.
-- Těla 1:1 ze živého snapshotu; jediná změna = podmínka
-- `b.booking_kind <> 'gear'` vedle filtru is_test (gear 2026-10-23).
-- Podlaha bodů (loyalty_refresh_points_floor) čte _loyalty_raw_points → hotovo
-- touto změnou; trigger podlahy se na gear rezervaci navíc přeskočí.
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._loyalty_raw_points(p_user_id uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(SUM(
    CASE WHEN (end_date::date - start_date::date + 1) >= 7 THEN 2 ELSE 1 END
  ), 0)::int
  FROM bookings
  WHERE user_id = p_user_id
    AND status = 'completed'
    AND booking_kind <> 'gear'   -- gear 2026-10-23: výpůjčka výbavy bez věrnostních bodů
    AND COALESCE(is_test, false) = false;
$$;

CREATE OR REPLACE FUNCTION public.trg_loyalty_floor_on_complete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- gear 2026-10-23: výpůjčka výbavy body nemění
  IF NEW.booking_kind = 'gear' THEN
    RETURN NEW;
  END IF;
  IF NEW.user_id IS NOT NULL AND NEW.status = 'completed' THEN
    PERFORM loyalty_refresh_points_floor(NEW.user_id);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_loyalty_floor_on_complete: %', SQLERRM;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION "public"."get_loyalty_leaderboard"("p_limit" integer DEFAULT 20) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
       AND COALESCE(b.is_test, false) = false AND b.booking_kind <> 'gear'
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
                        AND COALESCE(b.is_test, false) = false AND b.booking_kind <> 'gear'), 0)::int AS pts_now,
           COALESCE((SELECT SUM(CASE WHEN (b.end_date::date - b.start_date::date + 1) >= 7 THEN 2 ELSE 1 END)
                       FROM bookings b
                      WHERE b.user_id = p.id AND b.status = 'completed'
                        AND COALESCE(b.is_test, false) = false AND b.booking_kind <> 'gear'
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




CREATE OR REPLACE FUNCTION "public"."loyalty_award_monthly_winner"("p_month" "date" DEFAULT ("date_trunc"('month'::"text", (CURRENT_DATE - '1 day'::interval)))::"date") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
       AND COALESCE(b.is_test, false) = false AND b.booking_kind <> 'gear' AND b.user_id IS NOT NULL
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
                        AND COALESCE(b.is_test, false) = false AND b.booking_kind <> 'gear'
                        AND b.end_date < v_end), 0)::int AS pts_now,
           COALESCE((SELECT SUM(CASE WHEN (b.end_date::date - b.start_date::date + 1) >= 7 THEN 2 ELSE 1 END)
                       FROM bookings b
                      WHERE b.user_id = p.id AND b.status = 'completed'
                        AND COALESCE(b.is_test, false) = false AND b.booking_kind <> 'gear'
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


