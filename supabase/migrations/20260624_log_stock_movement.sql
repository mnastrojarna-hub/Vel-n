-- Naskladnění/výdej skladu — odolný helper proti rozdílným schématům inventory_movements
-- ────────────────────────────────────────────────────────────────────────────────────
-- Důvod: živá tabulka `inventory_movements` nemá vždy sloupec `item_id` (může být
-- `inventory_id` / `inventory_item_id`) ani `note` (může být `notes`). Frontend i
-- `receive_stock_from_document` proto zapisují pohyby přes tento helper, který cílové
-- sloupce detekuje přes information_schema a zápis obaluje do EXCEPTION (nikdy neshodí tok).

create or replace function public.log_stock_movement(p_item uuid, p_type text, p_qty int, p_note text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_fk text; v_note text; v_user uuid := auth.uid();
begin
  select column_name into v_fk from information_schema.columns
    where table_schema='public' and table_name='inventory_movements'
      and column_name in ('item_id','inventory_id','inventory_item_id') limit 1;
  if v_fk is null then return; end if;
  select column_name into v_note from information_schema.columns
    where table_schema='public' and table_name='inventory_movements'
      and column_name in ('note','notes') limit 1;
  begin
    if v_note is not null then
      execute format('insert into inventory_movements(%I, type, quantity, performed_by, %I) values($1,$2,$3,$4,$5)', v_fk, v_note)
        using p_item, p_type, p_qty, v_user, p_note;
    else
      execute format('insert into inventory_movements(%I, type, quantity, performed_by) values($1,$2,$3,$4)', v_fk)
        using p_item, p_type, p_qty, v_user;
    end if;
  exception when others then
    begin
      execute format('insert into inventory_movements(%I, type, quantity) values($1,$2,$3)', v_fk) using p_item, p_type, p_qty;
    exception when others then null; end;
  end;
end $$;

grant execute on function public.log_stock_movement(uuid, text, int, text) to authenticated, service_role;

-- Naskladnění z dokladu — přepsáno na log_stock_movement (dříve zapisovalo přímo do
-- inventory_movements(item_id,...) a padalo na „column item_id does not exist").
create or replace function public.receive_stock_from_document(p_lines jsonb, p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare ln jsonb; v_inv record; v_qty int; v_sku text; v_name text; v_price numeric; v_cat text;
  v_stocked int:=0; v_item_id uuid;
begin
  if not is_admin() then return jsonb_build_object('success',false,'error','not_authorized'); end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' then return jsonb_build_object('success',false,'error','bad_input'); end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    v_sku := nullif(trim(ln->>'sku'),''); v_qty := coalesce((ln->>'qty')::int,0);
    if v_sku is null or v_qty<=0 then continue; end if;
    v_name := coalesce(nullif(trim(ln->>'name'),''), v_sku);
    v_price := coalesce((ln->>'unit_price')::numeric,0);
    v_cat := coalesce(nullif(trim(ln->>'category'),''), case when v_sku like 'prislusenstvi-%' then 'prislusenstvi' else 'inventory' end);
    select * into v_inv from inventory where sku=v_sku limit 1;
    if found then
      update inventory set stock=coalesce(stock,0)+v_qty,
        unit_price=case when coalesce(unit_price,0)=0 and v_price>0 then v_price else unit_price end where id=v_inv.id;
      v_item_id := v_inv.id;
    else
      insert into inventory(sku,name,category,stock,min_stock,unit_price) values(v_sku,v_name,v_cat,v_qty,0,v_price) returning id into v_item_id;
    end if;
    perform public.log_stock_movement(v_item_id, 'receipt', v_qty, coalesce(p_note,'Naskladnění z dokladu'));
    v_stocked := v_stocked+1;
  end loop;
  return jsonb_build_object('success',true,'stocked',v_stocked);
end $$;

grant execute on function public.receive_stock_from_document(jsonb, text) to authenticated, service_role;

notify pgrst, 'reload schema';
