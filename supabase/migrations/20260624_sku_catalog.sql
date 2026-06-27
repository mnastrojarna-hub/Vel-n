-- =====================================================================
-- 20260624_sku_catalog.sql — číselník SKU + učení z korekcí
-- Nasazeno + ověřeno uživatelem 2026-06-24.
-- =====================================================================
create table if not exists public.sku_catalog (
  id uuid primary key default gen_random_uuid(),
  sku text unique not null,
  name text not null,
  category text not null,                 -- prislusenstvi/dily/material/zbozi/spotrebni
  type text, size text,                   -- u gearu (helmet/jacket/... + velikost)
  aliases text[] not null default '{}',   -- klíčová/cizojazyčná slova pro AI matching (učí se)
  is_consumable boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.sku_catalog enable row level security;
drop policy if exists sku_catalog_admin_all on public.sku_catalog;
create policy sku_catalog_admin_all on public.sku_catalog for all using (is_admin()) with check (is_admin());
drop policy if exists sku_catalog_read on public.sku_catalog;
create policy sku_catalog_read on public.sku_catalog for select using (true);

-- seed: gear (fyzické typy × velikosti)
insert into public.sku_catalog (sku, name, category, type, size, is_consumable)
select 'prislusenstvi-'||at.key||'-'||s.size, at.label||' '||s.size, 'prislusenstvi', at.key, s.size, coalesce(at.is_consumable,false)
from accessory_types at cross join lateral unnest(coalesce(at.sizes,'{}'::text[])) s(size)
where at.is_active and at.key in ('helmet','jacket','pants','boots','gloves','balaclava')
on conflict (sku) do nothing;

-- seed: existující skladové položky
insert into public.sku_catalog (sku, name, category)
select i.sku, coalesce(i.name, i.sku),
  case when i.sku like 'prislusenstvi-%' then 'prislusenstvi'
       when i.sku like 'dily-%' then 'dily'
       when i.sku like 'material-%' then 'material'
       when i.sku like 'spotrebni-%' then 'spotrebni'
       else 'zbozi' end
from inventory i where i.sku is not null and i.sku <> ''
on conflict (sku) do nothing;

-- Učení číselníku z ručních korekcí při naskladnění (Logistika → Naskladnění).
create or replace function public.learn_sku(p_sku text, p_name text, p_category text, p_type text, p_size text, p_alias text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not is_admin() then return; end if;
  insert into sku_catalog(sku, name, category, type, size, aliases)
    values(p_sku, coalesce(nullif(p_name,''), p_sku), coalesce(nullif(p_category,''),'zbozi'),
           nullif(p_type,''), nullif(p_size,''),
           case when nullif(p_alias,'') is not null then array[lower(p_alias)] else '{}'::text[] end)
  on conflict (sku) do update set
    name    = coalesce(nullif(excluded.name,''), sku_catalog.name),
    type    = coalesce(sku_catalog.type, excluded.type),
    size    = coalesce(sku_catalog.size, excluded.size),
    aliases = case when nullif(p_alias,'') is not null and not (lower(p_alias) = any(sku_catalog.aliases))
                   then array_append(sku_catalog.aliases, lower(p_alias)) else sku_catalog.aliases end,
    updated_at = now();
end $$;
revoke all on function public.learn_sku(text,text,text,text,text,text) from public, anon;
grant execute on function public.learn_sku(text,text,text,text,text,text) to authenticated, service_role;
