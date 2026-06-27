-- Fáze 6b — Kontrola duplicity dokladu + dílčí doplnění (sklad vs. finance)
-- ─────────────────────────────────────────────────────────────────────────
-- Při naskenování dokladu (OCR i výběr z DL/faktur) se zjistí, zda už je ten
-- SAMÝ doklad zaevidovaný a v jakém rozsahu:
--   • delivery_note → potřebuje jen sklad
--   • invoice       → potřebuje finance i sklad
-- Stavy:
--   new            – doklad není evidovaný → zavést normálně
--   duplicate_full – už je kompletní (faktura: sklad+finance; DL: sklad) → duplicita
--   need_stock     – faktura už ve financích, chybí naskladnit → doplnit jen sklad
--   need_finance   – zboží už naskladněno (i protějškem DL), chybí ve financích → doplnit jen finance

drop function if exists public.check_document_status(text, text, text, text, text, numeric);
create or replace function public.check_document_status(
  p_doc_type text,
  p_doc_number text default null,
  p_doc_date date default null,
  p_variable_symbol text default null,
  p_supplier_ico text default null,
  p_supplier_name text default null,
  p_amount numeric default 0
) returns jsonb
language plpgsql security definer set search_path = public as $$
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
end $$;

grant execute on function public.check_document_status(text, text, date, text, text, text, numeric) to authenticated, service_role;

notify pgrst, 'reload schema';
