-- =============================================================================
-- Testovací rezervace (is_test) NESMÍ do statistik ani Logistiky zboží
-- (zadání uživatele, navazuje na seed obsazenosti kalendářů 20260821).
--
-- 1) snapshot_daily_stats() — denní statistiky (cron 02:00): všechny subdotazy
--    na bookings nově vylučují is_test. (Seedy jsou trvale `reserved`, takže
--    do počtů active/completed stejně nepadaly; vyloučení je pojistka
--    do budoucna + čistí revenue subdotaz.)
-- 2) detect_gear_shortages_for_window() — Logistika zboží: oba průchody
--    bookings nově vylučují is_test. (Seedy mají všechny velikosti NULL,
--    deficit tedy nevytvářely; pojistka pro případné budoucí testovací
--    rezervace s výbavou.)
--
-- Těla 1:1 dle živého snapshotu 2026-08-19 (větev supabase-live-snapshot),
-- pouze doplněné filtry is_test. Idempotentní (CREATE OR REPLACE).
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."snapshot_daily_stats"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    yesterday DATE := CURRENT_DATE - 1;
    branch RECORD;
BEGIN
    FOR branch IN SELECT id FROM branches LOOP
        INSERT INTO daily_stats (date, branch_id, total_bookings, revenue, active_motos, utilization_pct, new_customers, sos_incidents)
        VALUES (
            yesterday,
            branch.id,
            (SELECT COUNT(*) FROM bookings WHERE branch_id = branch.id AND is_test IS NOT TRUE AND start_date::DATE <= yesterday AND end_date::DATE >= yesterday AND status IN ('active', 'completed')),
            (SELECT COALESCE(SUM(total_price), 0) FROM bookings WHERE branch_id = branch.id AND is_test IS NOT TRUE AND start_date::DATE = yesterday AND payment_status = 'paid'),
            (SELECT COUNT(*) FROM motorcycles WHERE branch_id = branch.id AND status = 'active'),
            (SELECT ROUND(
                COUNT(DISTINCT b.moto_id)::NUMERIC /
                NULLIF((SELECT COUNT(*) FROM motorcycles WHERE branch_id = branch.id AND status = 'active'), 0) * 100, 2
            ) FROM bookings b WHERE b.branch_id = branch.id AND b.is_test IS NOT TRUE AND b.start_date::DATE <= yesterday AND b.end_date::DATE >= yesterday AND b.status IN ('active', 'completed')),
            (SELECT COUNT(*) FROM profiles WHERE created_at::DATE = yesterday AND preferred_branch = branch.id),
            (SELECT COUNT(*) FROM sos_incidents si JOIN bookings bk ON si.booking_id = bk.id WHERE bk.branch_id = branch.id AND bk.is_test IS NOT TRUE AND si.created_at::DATE = yesterday)
        )
        ON CONFLICT (date, branch_id) DO UPDATE SET
            total_bookings = EXCLUDED.total_bookings,
            revenue = EXCLUDED.revenue,
            active_motos = EXCLUDED.active_motos,
            utilization_pct = EXCLUDED.utilization_pct,
            new_customers = EXCLUDED.new_customers,
            sos_incidents = EXCLUDED.sos_incidents;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."detect_gear_shortages_for_window"("p_branch_id" "uuid", "p_from" "date", "p_to" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_from date := greatest(p_from, current_date);
  v_to   date := p_to;
begin
  if p_branch_id is null or v_to is null or v_to < v_from then return; end if;

  with days as (select generate_series(v_from, v_to, interval '1 day')::date d),
  bk as (
    select b.id, b.start_date::date sd, b.end_date::date ed,
           coalesce(m.license_required,'A') lic, x.type, x.size
    from bookings b
    join motorcycles m on m.id = b.moto_id
    cross join lateral (values
      ('helmet', b.helmet_size), ('jacket', b.jacket_size), ('pants', b.pants_size),
      ('boots', b.boots_size),   ('gloves', b.gloves_size),
      ('helmet', b.passenger_helmet_size), ('jacket', b.passenger_jacket_size),
      ('pants', b.passenger_pants_size),   ('boots', b.passenger_boots_size),
      ('gloves', b.passenger_gloves_size)
    ) as x(type, size)
    where m.branch_id = p_branch_id
      and b.status in ('pending','reserved','active')
      and b.is_test is not true  -- testovací rezervace do logistiky zboží nepatří (NEW 2026-08-21)
      and coalesce(b.pickup_method,'') <> 'delivery'
      and x.size is not null and x.size <> ''
      and exists (select 1 from branch_accessories b2 where b2.type = x.type)  -- jen skladované typy
  ),
  calc as (
    select d.d shortage_date, bk.type, bk.size,
           case when bk.lic = 'N' then 'child' else 'adult' end audience,
           count(*)::int needed, coalesce(ba.quantity,0)::int stock_qty,
           greatest(count(*) - coalesce(ba.quantity,0), 0)::int deficit,
           array_agg(distinct bk.id) booking_ids
    from days d
    join bk on d.d between bk.sd and bk.ed
    left join branch_accessories ba
      on ba.branch_id = p_branch_id and ba.type = bk.type and ba.size = bk.size
    group by d.d, bk.type, bk.size, case when bk.lic='N' then 'child' else 'adult' end, coalesce(ba.quantity,0)
  )
  insert into gear_shortages
    (branch_id, accessory_type, size, audience, shortage_date, needed_qty, stock_qty, deficit_qty, booking_ids, status)
  select p_branch_id, type, size, audience, shortage_date, needed, stock_qty, deficit, booking_ids, 'open'
  from calc where deficit > 0
  on conflict (branch_id, accessory_type, size, shortage_date) do update set
    needed_qty=excluded.needed_qty, stock_qty=excluded.stock_qty, deficit_qty=excluded.deficit_qty,
    booking_ids=excluded.booking_ids, updated_at=now(),
    status = case when gear_shortages.status in ('resolved','dismissed') then 'open' else gear_shortages.status end,
    resolved_at = case when gear_shortages.status in ('resolved','dismissed') then null else gear_shortages.resolved_at end;

  update gear_shortages gs
  set deficit_qty=0, status='resolved', resolved_at=now(), updated_at=now()
  where gs.branch_id=p_branch_id and gs.shortage_date between v_from and v_to and gs.status='open'
    and not exists (
      select 1 from bookings b join motorcycles m on m.id=b.moto_id
      cross join lateral (values
        ('helmet',b.helmet_size),('jacket',b.jacket_size),('pants',b.pants_size),
        ('boots',b.boots_size),('gloves',b.gloves_size),
        ('helmet',b.passenger_helmet_size),('jacket',b.passenger_jacket_size),
        ('pants',b.passenger_pants_size),('boots',b.passenger_boots_size),('gloves',b.passenger_gloves_size)
      ) x(type,size)
      where m.branch_id=p_branch_id and b.status in ('pending','reserved','active')
        and b.is_test is not true  -- testovací rezervace do logistiky zboží nepatří (NEW 2026-08-21)
        and coalesce(b.pickup_method,'')<>'delivery'
        and x.type=gs.accessory_type and x.size=gs.size
        and gs.shortage_date between b.start_date::date and b.end_date::date
      group by x.type,x.size
      having count(*) > coalesce((select quantity from branch_accessories
        where branch_id=p_branch_id and type=gs.accessory_type and size=gs.size),0)
    );
end $$;
