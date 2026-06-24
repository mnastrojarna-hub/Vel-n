-- =====================================================================
-- 20260623_gear_logistics.sql — Logistika zboží (evidence výbavy)
-- Konsolidovaná migrace Fází 0–4. Nasazeno + ověřeno 2026-06-23.
--
-- Záchyt deficitu výbavy z rezervací (vždy pustí, jen flagne) →
-- kalendář dostupnosti → fronta „chybí kus" → doplnit ze skladu /
-- přesun mezi pobočkami / poloautomatická objednávka → naskladnění z dokladu.
-- Hlídají se JEN typy, které jsou aspoň někde v branch_accessories
-- (bunda `jacket` se začne hlídat až po zavedení jako skladová položka).
-- Pickup-at-branch; delivery pool je mimo (TODO Fáze 2b).
-- =====================================================================

-- 1) WORKLIST TABULKA --------------------------------------------------
create table if not exists public.gear_shortages (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  accessory_type text not null,
  size text not null,
  audience text not null default 'adult',          -- adult | child
  shortage_date date not null,
  needed_qty int not null default 0,
  stock_qty  int not null default 0,
  deficit_qty int not null default 0,
  status text not null default 'open',             -- open|warehouse_filled|transfer_requested|order_created|resolved|dismissed
  resolution text,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  transfer_from_branch_id uuid references public.branches(id) on delete set null,
  booking_ids uuid[] not null default '{}',
  assigned_to uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint uq_gear_shortages_cell unique (branch_id, accessory_type, size, shortage_date)
);
create index if not exists idx_gear_shortages_open on public.gear_shortages (status, shortage_date) where status = 'open';

alter table public.gear_shortages enable row level security;
drop policy if exists gear_shortages_admin_all on public.gear_shortages;
create policy gear_shortages_admin_all on public.gear_shortages for all using (is_admin()) with check (is_admin());

do $$ begin
  alter publication supabase_realtime add table public.gear_shortages;
exception when duplicate_object then null; end $$;

-- 2) DETEKCE PRO OKNO POBOČKY (per den, guard na skladované typy) -------
create or replace function public.detect_gear_shortages_for_window(
  p_branch_id uuid, p_from date, p_to date
) returns void
language plpgsql security definer set search_path = public as $$
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
      and coalesce(b.pickup_method,'') <> 'delivery'
      and x.size is not null and x.size <> ''
      and exists (select 1 from branch_accessories b2 where b2.type = x.type)
  ),
  calc as (
    select d.d shortage_date, bk.type, bk.size,
           case when bool_or(bk.lic = 'N') then 'child' else 'adult' end audience,
           count(*)::int needed, coalesce(ba.quantity,0)::int stock_qty,
           greatest(count(*) - coalesce(ba.quantity,0), 0)::int deficit,
           array_agg(distinct bk.id) booking_ids
    from days d
    join bk on d.d between bk.sd and bk.ed
    left join branch_accessories ba
      on ba.branch_id = p_branch_id and ba.type = bk.type and ba.size = bk.size
    group by d.d, bk.type, bk.size, coalesce(ba.quantity,0)
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
      select 1 from bookings b join motorcycles m on m.id=b.moto_id
      cross join lateral (values
        ('helmet',b.helmet_size),('jacket',b.jacket_size),('pants',b.pants_size),
        ('boots',b.boots_size),('gloves',b.gloves_size),
        ('helmet',b.passenger_helmet_size),('jacket',b.passenger_jacket_size),
        ('pants',b.passenger_pants_size),('boots',b.passenger_boots_size),('gloves',b.passenger_gloves_size)
      ) x(type,size)
      where m.branch_id=p_branch_id and b.status in ('pending','reserved','active')
        and coalesce(b.pickup_method,'')<>'delivery'
        and x.type=gs.accessory_type and x.size=gs.size
        and gs.shortage_date between b.start_date::date and b.end_date::date
      group by x.type,x.size
      having count(*) > coalesce((select quantity from branch_accessories
        where branch_id=p_branch_id and type=gs.accessory_type and size=gs.size),0)
    );
end $$;
revoke all on function public.detect_gear_shortages_for_window(uuid,date,date) from public, anon;
grant execute on function public.detect_gear_shortages_for_window(uuid,date,date) to authenticated, service_role;

-- 3) TRIGGER NA bookings — vždy pustí, jen flagne -----------------------
create or replace function public.trg_gear_shortage_on_booking() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_branch uuid;
begin
  begin
    select m.branch_id into v_branch from motorcycles m where m.id = new.moto_id;
    if v_branch is not null then
      perform public.detect_gear_shortages_for_window(v_branch, new.start_date::date, new.end_date::date);
    end if;
  exception when others then
    null;  -- NIKDY neblokovat rezervaci
  end;
  return new;
end $$;

drop trigger if exists gear_shortage_on_booking on public.bookings;
create trigger gear_shortage_on_booking
after insert or update of start_date, end_date, moto_id, status,
  helmet_size, jacket_size, pants_size, boots_size, gloves_size,
  passenger_helmet_size, passenger_jacket_size, passenger_pants_size,
  passenger_boots_size, passenger_gloves_size
on public.bookings
for each row execute function public.trg_gear_shortage_on_booking();

-- 4) PLOŠNÝ PŘEPOČET (cron + backfill) ---------------------------------
create or replace function public.detect_gear_shortages(p_horizon_days int default 120)
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select id from branches loop
    perform public.detect_gear_shortages_for_window(r.id, current_date, current_date + p_horizon_days);
  end loop;
end $$;
revoke all on function public.detect_gear_shortages(int) from public, anon;
grant execute on function public.detect_gear_shortages(int) to authenticated, service_role;

-- 5) KALENDÁŘ DOSTUPNOSTI (per den) — VŠECHNY aktivní typy×velikosti
--    + příznak is_consumable (spotřební/nespotřební, jako karta pobočky)
drop function if exists public.get_branch_gear_calendar(uuid,date,date);
create or replace function public.get_branch_gear_calendar(p_branch_id uuid, p_from date, p_to date)
returns table(shortage_date date, accessory_type text, size text, is_consumable boolean, stock int, booked int, free int, deficit int)
language sql stable security definer set search_path = public as $$
  with days as (select generate_series(p_from, p_to, interval '1 day')::date d),
  types as (
    select at.key type, s.size, coalesce(at.is_consumable,false) is_consumable, coalesce(at.sort_order,0) so
    from accessory_types at
    cross join lateral unnest(coalesce(at.sizes,'{}'::text[])) s(size)
    where at.is_active = true
  ),
  stock as (select type, size, quantity from branch_accessories where branch_id = p_branch_id),
  universe as (
    select type, size, is_consumable, so from types
    union
    select s.type, s.size,
      coalesce((select bool_or(t.is_consumable) from types t where t.type=s.type), false),
      coalesce((select min(t.so) from types t where t.type=s.type), 999)
    from stock s
    where not exists (select 1 from types t where t.type=s.type and t.size=s.size)
  ),
  bk as (
    select b.start_date::date sd, b.end_date::date ed, x.type, x.size
    from bookings b join motorcycles m on m.id = b.moto_id
    cross join lateral (values
      ('helmet',b.helmet_size),('jacket',b.jacket_size),('pants',b.pants_size),
      ('boots',b.boots_size),('gloves',b.gloves_size),
      ('helmet',b.passenger_helmet_size),('jacket',b.passenger_jacket_size),
      ('pants',b.passenger_pants_size),('boots',b.passenger_boots_size),('gloves',b.passenger_gloves_size)
    ) x(type,size)
    where m.branch_id=p_branch_id and b.status in ('pending','reserved','active')
      and coalesce(b.pickup_method,'')<>'delivery' and x.size is not null and x.size<>''
  ),
  booked as (
    select d.d, bk.type, bk.size, count(*)::int n
    from days d join bk on d.d between bk.sd and bk.ed group by d.d, bk.type, bk.size
  )
  select d.d, u.type, u.size, u.is_consumable,
    coalesce(s.quantity,0)::int, coalesce(bo.n,0)::int,
    greatest(coalesce(s.quantity,0)-coalesce(bo.n,0),0)::int,
    greatest(coalesce(bo.n,0)-coalesce(s.quantity,0),0)::int
  from days d cross join universe u
  left join stock s on s.type=u.type and s.size=u.size
  left join booked bo on bo.d=d.d and bo.type=u.type and bo.size=u.size
  order by u.is_consumable, u.so, u.type, u.size, d.d
$$;
revoke all on function public.get_branch_gear_calendar(uuid,date,date) from public, anon;
grant execute on function public.get_branch_gear_calendar(uuid,date,date) to authenticated, service_role;

-- 6) PŘEBYTKY NA JINÝCH POBOČKÁCH (pro přesun) -------------------------
create or replace function public.find_gear_surplus_branches(
  p_type text, p_size text, p_from date, p_to date, p_exclude_branch uuid
) returns table(branch_id uuid, branch_name text, free_qty int)
language sql stable security definer set search_path=public as $$
  with days as (select generate_series(greatest(p_from,current_date), p_to, interval '1 day')::date d),
  stock as (select ba.branch_id, ba.quantity from branch_accessories ba
            where ba.type=p_type and ba.size=p_size and ba.quantity>0 and ba.branch_id<>p_exclude_branch),
  booked as (
    select m.branch_id, d.d, count(*)::int n
    from days d
    join bookings b on b.status in ('pending','reserved','active')
      and coalesce(b.pickup_method,'')<>'delivery' and d.d between b.start_date::date and b.end_date::date
    join motorcycles m on m.id=b.moto_id
    cross join lateral (values
      ('helmet',b.helmet_size),('jacket',b.jacket_size),('pants',b.pants_size),
      ('boots',b.boots_size),('gloves',b.gloves_size),
      ('helmet',b.passenger_helmet_size),('jacket',b.passenger_jacket_size),
      ('pants',b.passenger_pants_size),('boots',b.passenger_boots_size),('gloves',b.passenger_gloves_size)
    ) x(type,size)
    where x.type=p_type and x.size=p_size
    group by m.branch_id, d.d
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
revoke all on function public.find_gear_surplus_branches(text,text,date,date,uuid) from public, anon;
grant execute on function public.find_gear_surplus_branches(text,text,date,date,uuid) to authenticated, service_role;

-- 7) PŘESUN VÝBAVY MEZI POBOČKAMI (atomický + přepočet) ----------------
create or replace function public.transfer_branch_gear(
  p_from_branch uuid, p_to_branch uuid, p_type text, p_size text, p_qty int, p_shortage_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_src record;
begin
  if not is_admin() then return jsonb_build_object('success',false,'error','not_authorized'); end if;
  if p_qty is null or p_qty<=0 then return jsonb_build_object('success',false,'error','bad_qty'); end if;
  select id, quantity into v_src from branch_accessories
    where branch_id=p_from_branch and type=p_type and size=p_size for update;
  if not found or v_src.quantity < p_qty then
    return jsonb_build_object('success',false,'error','insufficient_source'); end if;

  update branch_accessories set quantity=quantity-p_qty, updated_at=now() where id=v_src.id;
  insert into branch_accessories(branch_id,type,size,quantity) values(p_to_branch,p_type,p_size,p_qty)
    on conflict (branch_id,type,size) do update set quantity=branch_accessories.quantity+excluded.quantity, updated_at=now();

  if p_shortage_id is not null then
    update gear_shortages set status='transfer_requested', transfer_from_branch_id=p_from_branch, updated_at=now()
      where id=p_shortage_id; end if;

  perform detect_gear_shortages_for_window(p_to_branch, current_date, current_date+120);
  perform detect_gear_shortages_for_window(p_from_branch, current_date, current_date+120);
  return jsonb_build_object('success',true);
end $$;
revoke all on function public.transfer_branch_gear(uuid,uuid,text,text,int,uuid) from public, anon;
grant execute on function public.transfer_branch_gear(uuid,uuid,text,text,int,uuid) to authenticated, service_role;

-- 8) JÁDRO tvorby PO (bez auth guardu — volá wrapper i auto-funkce) -----
create or replace function public._create_gear_po(p_shortage_id uuid, p_qty int default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_sh record; v_inv record; v_qty int; v_order uuid; v_num text;
begin
  select * into v_sh from gear_shortages where id=p_shortage_id;
  if not found then return jsonb_build_object('success',false,'error','not_found'); end if;
  v_qty := coalesce(p_qty, v_sh.deficit_qty);
  if v_qty <= 0 then return jsonb_build_object('success',false,'error','no_deficit'); end if;
  select * into v_inv from inventory where sku='prislusenstvi-'||v_sh.accessory_type||'-'||v_sh.size limit 1;
  if not found then return jsonb_build_object('success',false,'error','no_inventory_item',
    'sku','prislusenstvi-'||v_sh.accessory_type||'-'||v_sh.size); end if;
  if v_inv.supplier_id is null then return jsonb_build_object('success',false,'error','no_supplier',
    'inventory_item_id',v_inv.id); end if;

  v_num := 'PO-'||to_char(now(),'YYYYMMDD-HH24MISS')||'-'||substr(md5(random()::text),1,4);
  insert into purchase_orders(supplier_id, order_number, status, total_amount, notes)
    values(v_inv.supplier_id, v_num, 'draft', v_qty*coalesce(v_inv.unit_price,0),
      'Auto z deficitu výbavy: '||v_sh.accessory_type||' '||v_sh.size) returning id into v_order;
  insert into purchase_order_items(order_id, item_id, quantity, unit_price)
    values(v_order, v_inv.id, v_qty, coalesce(v_inv.unit_price,0));
  update gear_shortages set status='order_created', purchase_order_id=v_order, updated_at=now() where id=p_shortage_id;
  return jsonb_build_object('success',true,'order_id',v_order,'order_number',v_num);
end $$;
revoke all on function public._create_gear_po(uuid,int) from public, anon, authenticated;
grant execute on function public._create_gear_po(uuid,int) to service_role;

-- 9) WRAPPER pro ruční tlačítko (is_admin) -----------------------------
create or replace function public.create_gear_purchase_order(p_shortage_id uuid, p_qty int default null)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not is_admin() then return jsonb_build_object('success',false,'error','not_authorized'); end if;
  return public._create_gear_po(p_shortage_id, p_qty);
end $$;
revoke all on function public.create_gear_purchase_order(uuid,int) from public, anon;
grant execute on function public.create_gear_purchase_order(uuid,int) to authenticated, service_role;

-- 10) AUTO-OBJEDNÁVKA všech otevřených deficitů (dedup na otevřené PO) --
create or replace function public.auto_order_gear_shortages()
returns jsonb language plpgsql security definer set search_path=public as $$
declare r record; res jsonb; v_sku text; v_dup_order uuid;
  v_created int:=0; v_no_item int:=0; v_no_supplier int:=0; v_dup int:=0;
begin
  for r in select gs.* from gear_shortages gs
           where gs.status='open' and gs.deficit_qty>0 order by gs.shortage_date loop
    v_sku := 'prislusenstvi-'||r.accessory_type||'-'||r.size;
    select po.id into v_dup_order
      from purchase_order_items poi
      join purchase_orders po on po.id=poi.order_id
      join inventory inv on inv.id=poi.item_id
      where inv.sku=v_sku and po.status in ('draft','sent') limit 1;
    if v_dup_order is not null then
      update gear_shortages set status='order_created', purchase_order_id=v_dup_order, updated_at=now() where id=r.id;
      v_dup:=v_dup+1; continue;
    end if;
    res := public._create_gear_po(r.id, null);
    if (res->>'success')::boolean then v_created:=v_created+1;
    elsif res->>'error'='no_inventory_item' then v_no_item:=v_no_item+1;
    elsif res->>'error'='no_supplier' then v_no_supplier:=v_no_supplier+1;
    end if;
  end loop;
  return jsonb_build_object('created',v_created,'skipped_dup',v_dup,
    'skipped_no_item',v_no_item,'skipped_no_supplier',v_no_supplier);
end $$;
revoke all on function public.auto_order_gear_shortages() from public, anon;
grant execute on function public.auto_order_gear_shortages() to authenticated, service_role;

-- 11) NASKLADNĚNÍ Z DOKLADU (faktura / dodací list / ručně) ------------
create or replace function public.receive_stock_from_document(p_lines jsonb, p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare ln jsonb; v_inv record; v_qty int; v_sku text; v_name text; v_price numeric; v_cat text;
  v_stocked int:=0; v_item_id uuid; v_user uuid:=auth.uid();
begin
  if not is_admin() then return jsonb_build_object('success',false,'error','not_authorized'); end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' then return jsonb_build_object('success',false,'error','bad_input'); end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    v_sku := nullif(trim(ln->>'sku'),'');
    v_qty := coalesce((ln->>'qty')::int,0);
    if v_sku is null or v_qty<=0 then continue; end if;
    v_name := coalesce(nullif(trim(ln->>'name'),''), v_sku);
    v_price := coalesce((ln->>'unit_price')::numeric,0);
    v_cat := coalesce(nullif(trim(ln->>'category'),''),
              case when v_sku like 'prislusenstvi-%' then 'prislusenstvi' else 'inventory' end);
    select * into v_inv from inventory where sku=v_sku limit 1;
    if found then
      update inventory set stock=coalesce(stock,0)+v_qty,
        unit_price=case when coalesce(unit_price,0)=0 and v_price>0 then v_price else unit_price end
        where id=v_inv.id;
      v_item_id := v_inv.id;
    else
      insert into inventory(sku,name,category,stock,min_stock,unit_price)
        values(v_sku,v_name,v_cat,v_qty,0,v_price) returning id into v_item_id;
    end if;
    insert into inventory_movements(item_id,type,quantity,note,performed_by)
      values(v_item_id,'receipt',v_qty, coalesce(p_note,'Naskladnění z dokladu'), v_user);
    v_stocked := v_stocked+1;
  end loop;
  return jsonb_build_object('success',true,'stocked',v_stocked);
end $$;
revoke all on function public.receive_stock_from_document(jsonb,text) from public, anon;
grant execute on function public.receive_stock_from_document(jsonb,text) to authenticated, service_role;

-- 12) ÚKLID netrackovaných typů + úvodní backfill ----------------------
delete from gear_shortages
where accessory_type not in (select distinct type from branch_accessories);
select public.detect_gear_shortages(120);

-- Volitelný cron (plná automatika bez kliknutí) — zapni dle potřeby:
-- select cron.schedule('detect-gear-shortages','*/30 * * * *', $$select public.detect_gear_shortages(120)$$);
-- select cron.schedule('auto-order-gear','0 6 * * *', $$select public.auto_order_gear_shortages()$$);
