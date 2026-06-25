-- Fáze 6 — Párování DL ⇄ faktura + ochrana proti duplicitnímu naskladnění
-- ───────────────────────────────────────────────────────────────────────
-- Princip (dle zadání):
--   • Dodací list (DL)  → naskladňuje zboží (sklad)
--   • Faktura           → finance i sklad
--   • Pokud zboží už dorazilo přes DL a později přijde faktura (nebo naopak),
--     NESMÍ se naskladnit znovu — spáruje se a druhý doklad jen eviduje.
--   • Faktura bez dohledaného DL → příznak needs_dl ("chybí DL").

create table if not exists public.stock_receipts (
  id uuid primary key default gen_random_uuid(),
  doc_type text not null check (doc_type in ('invoice', 'delivery_note')),
  doc_number text,
  doc_date date,                                             -- datum dokladu (klíč duplicity: č. dokladu + datum)
  variable_symbol text,
  supplier_ico text,
  supplier_name text,
  amount_czk numeric default 0,
  financial_event_id uuid,
  stocked boolean default false,                              -- zboží skutečně naskladněno z tohoto dokladu
  matched_receipt_id uuid references public.stock_receipts(id),
  needs_dl boolean default false,                            -- faktura bez spárovaného DL
  note text,
  created_at timestamptz default now()
);

-- migrace existující tabulky (pokud už byla nasazená bez doc_date)
alter table public.stock_receipts add column if not exists doc_date date;

create index if not exists idx_stock_receipts_supplier on public.stock_receipts (supplier_ico, supplier_name);
create index if not exists idx_stock_receipts_needs_dl on public.stock_receipts (needs_dl) where needs_dl = true;
create index if not exists idx_stock_receipts_docnum on public.stock_receipts (lower(doc_number), doc_date);

alter table public.stock_receipts enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='stock_receipts' and policyname='stock_receipts_admin_all') then
    create policy stock_receipts_admin_all on public.stock_receipts
      for all to authenticated using (true) with check (true);
  end if;
end $$;

-- Pomocná: normalizace názvu dodavatele (bez diakritiky, malá písmena)
create or replace function public._norm_supplier(p text)
returns text language sql immutable as $$
  select lower(translate(coalesce(p, ''),
    'áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ',
    'acdeeinorstuuyzACDEEINORSTUUYZ'))
$$;

-- Zaeviduje doklad do ledgeru, spáruje s protějškem a rozhodne, zda naskladnit.
-- Vrací: { receipt_id, duplicate (true = NEnaskladňuj, už je), will_stock, matched_receipt_id, needs_dl }
drop function if exists public.record_stock_receipt(text, text, text, text, text, numeric, uuid, boolean);
create or replace function public.record_stock_receipt(
  p_doc_type text,
  p_doc_number text default null,
  p_doc_date date default null,
  p_variable_symbol text default null,
  p_supplier_ico text default null,
  p_supplier_name text default null,
  p_amount numeric default 0,
  p_financial_event_id uuid default null,
  p_will_stock boolean default true
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_norm text := public._norm_supplier(p_supplier_name);
  v_tol numeric := greatest(coalesce(p_amount, 0) * 0.02, 1);   -- tolerance 2 %, min 1 Kč
  v_cp public.stock_receipts;
  v_duplicate boolean := false;
  v_effective_stock boolean;
  v_needs_dl boolean := false;
  v_id uuid;
begin
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
end $$;

grant execute on function public.record_stock_receipt(text, text, date, text, text, text, numeric, uuid, boolean) to authenticated, service_role;

notify pgrst, 'reload schema';
