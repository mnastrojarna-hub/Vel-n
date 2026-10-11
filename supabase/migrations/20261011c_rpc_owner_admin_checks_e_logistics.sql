-- =============================================================================
-- 2026-10-11 BEZPEČNOST (část _e k 20261011c): Logistika bez kontroly
-- Logistika (Velín Logistika.jsx přes rpcSafe — chyba = null, admin beze změny):
--   check_asset_status / check_document_status (anon i zákazník zjišťovali
--   majetek, přijaté faktury, částky a ID účetních záznamů), record_stock_receipt
--   (anon zakládal doklady a přepínal párování / „chybí DL“ skutečných dokladů).
-- Na začátek těla jen guard _rpc_caller_is_staff() (admin / service_role /
-- pg_cron, postgres); jinak výjimka 42501. Těla = živá definice. Idempotentní.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.check_asset_status(p_asset_type text, p_vin text DEFAULT NULL::text, p_spz text DEFAULT NULL::text, p_name text DEFAULT NULL::text, p_amount numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- 2026-10-11: jen Velín (admin) / server — dřív i anon a zákazník
  if not public._rpc_caller_is_staff() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

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
end $function$;

CREATE OR REPLACE FUNCTION public.check_document_status(p_doc_type text, p_doc_number text DEFAULT NULL::text, p_doc_date date DEFAULT NULL::date, p_variable_symbol text DEFAULT NULL::text, p_supplier_ico text DEFAULT NULL::text, p_supplier_name text DEFAULT NULL::text, p_amount numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_norm text := public._norm_supplier(p_supplier_name);
  v_tol numeric := greatest(coalesce(p_amount, 0) * 0.02, 1);
  v_num text := nullif(lower(trim(coalesce(p_doc_number, ''))), '');
  v_same public.stock_receipts;
  v_in_finance boolean := false;
  v_in_stock boolean := false;
  v_found boolean := false;
  v_cp_stocked boolean := false;
  v_status text;
  v_match jsonb := null;
begin
  -- 2026-10-11: jen Velín (admin) / server — dřív i anon a zákazník
  if not public._rpc_caller_is_staff() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  -- Shoda STEJNÉHO dokladu = klíč „č. dokladu + datum" (100% jistota proti duplicitě).
  -- Bez č. dokladu fallback na dodavatel + částka + blízké datum (±3 dny).
  -- WHERE výraz drží v jedné proměnné, ať se neopakuje (použijeme 2×).
  select * into v_same from public.stock_receipts r
  where r.doc_type = p_doc_type
    and (
      (v_num is not null and lower(trim(coalesce(r.doc_number, ''))) = v_num
        and (p_doc_date is null or r.doc_date is null or r.doc_date = p_doc_date))
      or (v_num is null and v_norm <> '' and public._norm_supplier(r.supplier_name) = v_norm
        and abs(coalesce(r.amount_czk, 0) - coalesce(p_amount, 0)) <= v_tol
        and (p_doc_date is null or r.doc_date is null or abs(r.doc_date - p_doc_date) <= 3))
    )
  order by r.created_at desc
  limit 1;

  if v_same.id is not null then
    v_found := true;
    select bool_or(financial_event_id is not null), bool_or(stocked)
      into v_in_finance, v_in_stock
    from public.stock_receipts r
    where r.doc_type = p_doc_type
      and (
        (v_num is not null and lower(trim(coalesce(r.doc_number, ''))) = v_num
          and (p_doc_date is null or r.doc_date is null or r.doc_date = p_doc_date))
        or (v_num is null and v_norm <> '' and public._norm_supplier(r.supplier_name) = v_norm
          and abs(coalesce(r.amount_czk, 0) - coalesce(p_amount, 0)) <= v_tol
          and (p_doc_date is null or r.doc_date is null or abs(r.doc_date - p_doc_date) <= 3))
      );
    v_match := jsonb_build_object('receipt_id', v_same.id, 'doc_number', v_same.doc_number,
      'doc_date', v_same.doc_date, 'amount_czk', v_same.amount_czk, 'created_at', v_same.created_at,
      'financial_event_id', v_same.financial_event_id);
  end if;

  -- Zboží mohlo být naskladněno protějškem (opačný typ — DL↔faktura)
  select bool_or(stocked) into v_cp_stocked from public.stock_receipts r
  where r.doc_type <> p_doc_type
    and abs(coalesce(r.amount_czk, 0) - coalesce(p_amount, 0)) <= v_tol
    and r.created_at > now() - interval '120 days'
    and ((p_supplier_ico is not null and r.supplier_ico = p_supplier_ico)
      or (coalesce(p_supplier_ico, '') = '' and v_norm <> '' and public._norm_supplier(r.supplier_name) = v_norm));
  if v_cp_stocked then v_in_stock := true; end if;

  -- Faktura už mohla být ve financích i mimo Logistiku (financial_events dle č. faktury + datum)
  if p_doc_type = 'invoice' and v_num is not null and not v_in_finance then
    begin
      select exists(select 1 from public.financial_events fe
        where lower(trim(coalesce(fe.metadata->>'invoice_number', ''))) = v_num
          and (p_doc_date is null or fe.duzp is null or abs(fe.duzp - p_doc_date) <= 5)) into v_in_finance;
    exception when others then null;
    end;
  end if;

  if p_doc_type = 'delivery_note' then
    v_status := case when v_in_stock then 'duplicate_full' else 'new' end;
  else
    if v_in_finance and v_in_stock then v_status := 'duplicate_full';
    elsif v_in_stock and not v_in_finance then v_status := 'need_finance';
    elsif v_in_finance and not v_in_stock then v_status := 'need_stock';
    else v_status := 'new';
    end if;
  end if;

  return jsonb_build_object('found', v_found, 'in_finance', v_in_finance,
    'in_stock', v_in_stock, 'status', v_status, 'match', v_match);
end $function$;

CREATE OR REPLACE FUNCTION public.record_stock_receipt(p_doc_type text, p_doc_number text DEFAULT NULL::text, p_doc_date date DEFAULT NULL::date, p_variable_symbol text DEFAULT NULL::text, p_supplier_ico text DEFAULT NULL::text, p_supplier_name text DEFAULT NULL::text, p_amount numeric DEFAULT 0, p_financial_event_id uuid DEFAULT NULL::uuid, p_will_stock boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_norm text := public._norm_supplier(p_supplier_name);
  v_tol numeric := greatest(coalesce(p_amount, 0) * 0.02, 1);   -- tolerance 2 %, min 1 Kč
  v_cp public.stock_receipts;
  v_duplicate boolean := false;
  v_effective_stock boolean;
  v_needs_dl boolean := false;
  v_id uuid;
begin
  -- 2026-10-11: jen Velín (admin) / server — dřív i anon a zákazník
  if not public._rpc_caller_is_staff() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  -- Najdi nespárovaný protějšek OPAČNÉHO typu od stejného dodavatele s podobnou částkou (posl. 120 dní)
  select * into v_cp from public.stock_receipts r
  where r.doc_type <> p_doc_type
    and r.matched_receipt_id is null
    and abs(coalesce(r.amount_czk, 0) - coalesce(p_amount, 0)) <= v_tol
    and (
      (p_supplier_ico is not null and r.supplier_ico is not null and r.supplier_ico = p_supplier_ico)
      or (coalesce(p_supplier_ico, '') = '' and v_norm <> '' and public._norm_supplier(r.supplier_name) = v_norm)
    )
    and r.created_at > now() - interval '120 days'
  order by r.created_at desc
  limit 1;

  -- Pokud protějšek už zboží naskladnil → tenhle doklad NEnaskladňuje (duplicita)
  if v_cp.id is not null and v_cp.stocked then
    v_duplicate := true;
  end if;

  v_effective_stock := coalesce(p_will_stock, true) and not v_duplicate;

  -- Faktura, ke které se nenašel DL → "chybí DL"
  if p_doc_type = 'invoice' and v_cp.id is null then
    v_needs_dl := true;
  end if;

  insert into public.stock_receipts(
    doc_type, doc_number, doc_date, variable_symbol, supplier_ico, supplier_name,
    amount_czk, financial_event_id, stocked, matched_receipt_id, needs_dl)
  values (
    p_doc_type, p_doc_number, p_doc_date, p_variable_symbol, p_supplier_ico, p_supplier_name,
    p_amount, p_financial_event_id, v_effective_stock, v_cp.id, v_needs_dl)
  returning id into v_id;

  -- Spáruj protějšek zpět; pokud nově přišel DL k faktuře, zruš protějšku "chybí DL"
  if v_cp.id is not null then
    update public.stock_receipts
      set matched_receipt_id = v_id,
          needs_dl = case when p_doc_type = 'delivery_note' then false else needs_dl end
      where id = v_cp.id;
  end if;

  return jsonb_build_object(
    'receipt_id', v_id,
    'duplicate', v_duplicate,
    'will_stock', v_effective_stock,
    'matched_receipt_id', v_cp.id,
    'needs_dl', v_needs_dl
  );
end $function$;
