-- Fáze 6c — Kontrola duplicity MAJETKU (ne dokladu) + dílčí doplnění
-- ──────────────────────────────────────────────────────────────────
-- Když se naskenuje faktura na dlouhodobý/krátkodobý majetek (typicky motorka),
-- systém prověří, zda daný majetek už existuje:
--   • Vozidlo/motorka → nezaměnitelně dle VIN nebo SPZ (i když byla zanesena přes Flotilu).
--   • Ostatní majetek → dle názvu.
-- Pokud existuje, NEVYTVOŘÍ se duplicita — jen se doplní chybějící (cena, doklad, odpisy).
-- Stavy: new / asset_exists_needs_doc (existuje, chybí doklad/cena → doplnit) / duplicate_full.

create or replace function public.check_asset_status(
  p_asset_type text,
  p_vin text default null,
  p_spz text default null,
  p_name text default null,
  p_amount numeric default 0
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_vin text := nullif(upper(regexp_replace(coalesce(p_vin, ''), '\s', '', 'g')), '');
  v_spz text := nullif(upper(regexp_replace(coalesce(p_spz, ''), '\s', '', 'g')), '');
  v_name text := public._norm_supplier(p_name);
  v_moto record;
  v_asset record;
  v_status text := 'new';
  v_kind text := null;
  v_moto_id uuid := null;
  v_asset_id uuid := null;
  v_label text := null;
begin
  -- 1) Vozidlo/motorka dle VIN nebo SPZ (nezaměnitelné)
  if v_vin is not null or v_spz is not null then
    select * into v_moto from public.motorcycles m
    where (v_vin is not null and upper(regexp_replace(coalesce(m.vin, ''), '\s', '', 'g')) = v_vin)
       or (v_spz is not null and upper(regexp_replace(coalesce(m.spz, ''), '\s', '', 'g')) = v_spz)
    limit 1;
    if v_moto.id is not null then
      v_kind := 'motorcycle'; v_moto_id := v_moto.id;
      v_label := concat_ws(' ', v_moto.model, coalesce(v_moto.spz, v_moto.vin));
      select * into v_asset from public.acc_long_term_assets a where a.motorcycle_id = v_moto.id limit 1;
      if v_asset.id is not null then
        v_asset_id := v_asset.id;
        v_status := case when coalesce(v_asset.missing_purchase_doc, false)
                          or coalesce(v_asset.purchase_price, 0) = 0
                          or v_asset.invoice_number is null
                         then 'asset_exists_needs_doc' else 'duplicate_full' end;
      else
        v_status := 'asset_exists_needs_doc';   -- motorka ve flotile, ještě ne v majetku
      end if;
    end if;
  end if;

  -- 2) Ostatní dlouhodobý majetek dle názvu
  if v_kind is null and p_asset_type = 'dlouhodoby_majetek' and v_name <> '' then
    select * into v_asset from public.acc_long_term_assets a
    where public._norm_supplier(a.name) = v_name
       or (length(v_name) > 4 and public._norm_supplier(a.name) like '%' || v_name || '%')
    order by a.acquired_date desc nulls last limit 1;
    if v_asset.id is not null then
      v_kind := 'long_term'; v_asset_id := v_asset.id; v_label := v_asset.name;
      v_status := case when coalesce(v_asset.missing_purchase_doc, false)
                        or coalesce(v_asset.purchase_price, 0) = 0
                        or v_asset.invoice_number is null
                       then 'asset_exists_needs_doc' else 'duplicate_full' end;
    end if;
  end if;

  -- 3) Krátkodobý majetek dle názvu
  if v_kind is null and p_asset_type = 'kratkodoby_majetek' and v_name <> '' then
    select * into v_asset from public.acc_short_term_assets a
    where public._norm_supplier(a.name) = v_name
    order by a.acquired_date desc nulls last limit 1;
    if v_asset.id is not null then
      v_kind := 'short_term'; v_asset_id := v_asset.id; v_label := v_asset.name;
      v_status := 'duplicate_full';
    end if;
  end if;

  return jsonb_build_object('status', v_status, 'kind', v_kind,
    'motorcycle_id', v_moto_id, 'asset_id', v_asset_id, 'label', v_label);
end $$;

grant execute on function public.check_asset_status(text, text, text, text, numeric) to authenticated, service_role;

notify pgrst, 'reload schema';
