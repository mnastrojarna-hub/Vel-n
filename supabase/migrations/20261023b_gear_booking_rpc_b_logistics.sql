-- =============================================================================
-- 2026-10-23 (b/2): Logistika zboží započítává i výpůjčky JEN výbavy
-- Detekce deficitů, kalendář skladu, hledání přebytků a trigger nad rezervací
-- čtou poptávku ze SPOLEČNÉHO _gear_demand (motorky dle pobočky motorky jako
-- dřív + gear dle bookings.branch_id). Změny proti živému tělu (gear 2026-10-23):
--  • LEFT JOIN motorek (gear řádky už nevypadnou), is_test filtr i v kalendáři
--    a přebytcích, deficit per (den, typ, velikost) BEZ dělení audience
--    (audience = bool_or(lic='N'), jak popisuje STATE_3 — živé dělení kolidovalo
--    s UNIQUE klíčem), velikost sklad↔rezervace porovnaná přes _gear_size_key
--    (XXL = 2XL), uložená velikost = zápis z rezervace (jako dřív).
--  • trigger: pobočka gear = branch_id, sloupec branch_id v seznamu, při změně
--    pobočky/termínu přepočet i PŮVODNÍ pobočky/okna (zrušené dny se vyřeší).
-- Pořád jen „hlídá a hlásí“, rezervaci nikdy neblokuje. Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.detect_gear_shortages_for_window(p_branch_id uuid, p_from date, p_to date)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare
  v_from date := greatest(p_from, current_date);
  v_to   date := p_to;
begin
  if p_branch_id is null or v_to is null or v_to < v_from then return; end if;

  with days as (select generate_series(v_from, v_to, interval '1 day')::date d),
  bk as (
    -- gear 2026-10-23: společná poptávka (motorky + výpůjčky výbavy)
    select dm.booking_id id, dm.sd, dm.ed, dm.lic, dm.type, dm.size_key, dm.size
    from public._gear_demand(p_branch_id, v_from, v_to, null) dm
    where exists (select 1 from branch_accessories b2 where b2.type = dm.type)  -- jen skladované typy
  ),
  stock as (
    select ba.type, public._gear_size_key(ba.size) k, sum(ba.quantity)::int qty
    from branch_accessories ba where ba.branch_id = p_branch_id group by 1, 2
  ),
  calc as (
    select d.d shortage_date, bk.type, min(bk.size) size,
           case when bool_or(bk.lic = 'N') then 'child' else 'adult' end audience,
           count(*)::int needed, coalesce(s.qty,0)::int stock_qty,
           greatest(count(*) - coalesce(s.qty,0), 0)::int deficit,
           array_agg(distinct bk.id) booking_ids
    from days d
    join bk on d.d between bk.sd and bk.ed
    left join stock s on s.type = bk.type and s.k = bk.size_key
    group by d.d, bk.type, bk.size_key, coalesce(s.qty,0)
  )
  insert into gear_shortages
    (branch_id, accessory_type, size, audience, shortage_date, needed_qty, stock_qty, deficit_qty, booking_ids, status)
  select p_branch_id, type, size, audience, shortage_date, needed, stock_qty, deficit, booking_ids, 'open'
  from calc where deficit > 0
  on conflict (branch_id, accessory_type, size, shortage_date) do update set
    needed_qty=excluded.needed_qty, stock_qty=excluded.stock_qty, deficit_qty=excluded.deficit_qty,
    booking_ids=excluded.booking_ids, audience=excluded.audience, updated_at=now(),
    status = case when gear_shortages.status in ('resolved','dismissed') then 'open' else gear_shortages.status end,
    resolved_at = case when gear_shortages.status in ('resolved','dismissed') then null else gear_shortages.resolved_at end;

  update gear_shortages gs
  set deficit_qty=0, status='resolved', resolved_at=now(), updated_at=now()
  where gs.branch_id=p_branch_id and gs.shortage_date between v_from and v_to and gs.status='open'
    and not exists (
      select 1 from public._gear_demand(p_branch_id, gs.shortage_date, gs.shortage_date, null) dm
      where dm.type = gs.accessory_type and dm.size_key = public._gear_size_key(gs.size)
      group by dm.type, dm.size_key
      having count(*) > coalesce((select sum(quantity) from branch_accessories
        where branch_id=p_branch_id and type=gs.accessory_type
          and public._gear_size_key(size) = public._gear_size_key(gs.size)),0)
    );
end $$;

CREATE OR REPLACE FUNCTION public.get_branch_gear_calendar(p_branch_id uuid, p_from date, p_to date)
RETURNS TABLE(shortage_date date, accessory_type text, size text, is_consumable boolean,
              stock integer, booked integer, free integer, deficit integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  with days as (select generate_series(p_from,p_to,interval '1 day')::date d),
  types as (
    select at.key type, s.size, public._gear_size_key(s.size) k,
           coalesce(at.is_consumable,false) is_consumable, coalesce(at.sort_order,0) so
    from accessory_types at
    cross join lateral unnest(coalesce(at.sizes,'{}'::text[])) s(size)
    where at.is_active = true
      and ( at.key in ('helmet','jacket','pants','boots','gloves')   -- fyzické typy z rezervací
            or coalesce(at.is_consumable,false) = true )             -- + spotřební (kukla…)
  ),
  -- gear 2026-10-23: sklad sečtený přes zápis velikosti (XXL = 2XL)
  stock as (select type, public._gear_size_key(size) k, min(size) size, sum(quantity)::int quantity
            from branch_accessories where branch_id=p_branch_id group by 1, 2),
  universe as (
    select type, size, k, is_consumable, so from types
    union
    select s.type, s.size, s.k,
      coalesce((select bool_or(t.is_consumable) from types t where t.type=s.type), false),
      coalesce((select min(t.so) from types t where t.type=s.type), 999)
    from stock s
    where not exists (select 1 from types t where t.type=s.type and t.k=s.k)
  ),
  -- gear 2026-10-23: společná poptávka (i výpůjčky výbavy, bez testovacích)
  booked as (select d.d, dm.type, dm.size_key k, count(*)::int n
             from days d join public._gear_demand(p_branch_id, p_from, p_to, null) dm on d.d between dm.sd and dm.ed
             group by 1,2,3)
  select d.d, u.type, u.size, u.is_consumable,
    coalesce(s.quantity,0)::int, coalesce(bo.n,0)::int,
    greatest(coalesce(s.quantity,0)-coalesce(bo.n,0),0)::int,
    greatest(coalesce(bo.n,0)-coalesce(s.quantity,0),0)::int
  from days d cross join universe u
  left join stock s on s.type=u.type and s.k=u.k
  left join booked bo on bo.d=d.d and bo.type=u.type and bo.k=u.k
  order by u.is_consumable, u.so, u.type, u.size, d.d
$$;

CREATE OR REPLACE FUNCTION public.find_gear_surplus_branches(p_type text, p_size text, p_from date, p_to date,
                                                             p_exclude_branch uuid)
RETURNS TABLE(branch_id uuid, branch_name text, free_qty integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  with days as (select generate_series(greatest(p_from,current_date), p_to, interval '1 day')::date d),
  -- gear 2026-10-23: sklad sečtený přes zápis velikosti (XXL = 2XL)
  stock as (select ba.branch_id, sum(ba.quantity)::int quantity from branch_accessories ba
            where ba.type=p_type and public._gear_size_key(ba.size)=public._gear_size_key(p_size)
              and ba.quantity>0 and ba.branch_id<>p_exclude_branch
            group by ba.branch_id),
  -- gear 2026-10-23: společná poptávka všech poboček (i výpůjčky výbavy, bez testovacích)
  booked as (
    select dm.branch_id, d.d, count(*)::int n
    from days d
    join public._gear_demand(null, greatest(p_from,current_date), p_to, null) dm on d.d between dm.sd and dm.ed
    where dm.type=p_type and dm.size_key=public._gear_size_key(p_size)
    group by dm.branch_id, d.d
  ),
  perday as (
    select s.branch_id, d.d, s.quantity - coalesce(bo.n,0) free
    from stock s cross join days d
    left join booked bo on bo.branch_id=s.branch_id and bo.d=d.d
  )
  select pd.branch_id, br.name, min(pd.free)::int
  from perday pd join branches br on br.id=pd.branch_id
  group by pd.branch_id, br.name having min(pd.free)>0 order by 3 desc
$$;

CREATE OR REPLACE FUNCTION public.trg_gear_shortage_on_booking()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare v_branch uuid; v_old uuid;
begin
  begin
    -- gear 2026-10-23: výpůjčka výbavy = pobočka rezervace, motorka = pobočka motorky
    v_branch := case when new.booking_kind = 'gear' then new.branch_id
                     else (select m.branch_id from motorcycles m where m.id = new.moto_id) end;
    if v_branch is not null then
      perform public.detect_gear_shortages_for_window(v_branch, new.start_date::date, new.end_date::date);
    end if;
    -- gear 2026-10-23: přesun pobočky / změna termínu → přepočet i původního okna
    if tg_op = 'UPDATE' then
      v_old := case when old.booking_kind = 'gear' then old.branch_id
                    else (select m.branch_id from motorcycles m where m.id = old.moto_id) end;
      if v_old is not null and (v_old is distinct from v_branch
           or old.start_date::date <> new.start_date::date or old.end_date::date <> new.end_date::date) then
        perform public.detect_gear_shortages_for_window(v_old, old.start_date::date, old.end_date::date);
      end if;
    end if;
  exception when others then
    null;  -- NIKDY neblokovat rezervaci
  end;
  return new;
end $$;

-- gear 2026-10-23: + branch_id (přesun výpůjčky výbavy na jinou pobočku)
DROP TRIGGER IF EXISTS gear_shortage_on_booking ON public.bookings;
CREATE TRIGGER gear_shortage_on_booking AFTER INSERT OR UPDATE OF start_date, end_date, moto_id, status,
  helmet_size, jacket_size, pants_size, boots_size, gloves_size, passenger_helmet_size, passenger_jacket_size,
  passenger_pants_size, passenger_boots_size, passenger_gloves_size, branch_id
  ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.trg_gear_shortage_on_booking();
