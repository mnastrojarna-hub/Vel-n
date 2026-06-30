-- ============================================================================
-- 20260628_app_installations.sql
-- Přesná evidence instalací mobilní appky (zdroj pravdy pro počítání instalací
-- / aktivních zařízení / uživatelů) — nezávislé na souhlasu s push pushy.
--
-- Appka (InstallationService, oba Flutter balíky) generuje stabilní náhodné
-- UUID per instalaci (NE hardwarový identifikátor — Google Play safe), ukládá
-- ho v secure storage a throttlovaně upsertuje „heartbeat" do app_installations.
--
-- POZN.: Spuštěno ručně v SQL editoru, ověřeno uživatelem (2026-06-28).
-- ============================================================================

create table if not exists public.app_installations (
  device_id     text primary key,                 -- náhodné UUID z appky (NE hardware ID)
  user_id       uuid not null references auth.users(id) on delete cascade,
  platform      text,                              -- 'android' | 'ios'
  app_version   text,
  push_enabled  boolean not null default false,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_app_installations_user      on public.app_installations (user_id);
create index if not exists idx_app_installations_last_seen on public.app_installations (last_seen_at desc);
create index if not exists idx_app_installations_platform  on public.app_installations (lower(platform));

-- updated_at touch
create or replace function public.app_installations_touch()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists trg_app_installations_touch on public.app_installations;
create trigger trg_app_installations_touch
  before update on public.app_installations
  for each row execute function public.app_installations_touch();

-- RLS: uživatel zapisuje/čte JEN svůj řádek; admin čte vše
alter table public.app_installations enable row level security;

drop policy if exists app_installations_owner_rw on public.app_installations;
create policy app_installations_owner_rw on public.app_installations
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists app_installations_admin_read on public.app_installations;
create policy app_installations_admin_read on public.app_installations
  for select to authenticated
  using (is_admin());

-- ============================================================================
-- get_app_install_stats() — přepis na app_installations (+ legacy push proxy)
-- ============================================================================
create or replace function public.get_app_install_stats()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  result json;
begin
  if not is_admin() then
    raise exception 'admin only';
  end if;

  select json_build_object(
    -- === Přesná data z app_installations (build s heartbeatem) ===
    'installs_total',       (select count(*) from app_installations),
    'app_users',            (select count(distinct user_id) from app_installations),
    'dau',                  (select count(*) from app_installations where last_seen_at > now() - interval '1 day'),
    'wau',                  (select count(*) from app_installations where last_seen_at > now() - interval '7 days'),
    'mau',                  (select count(*) from app_installations where last_seen_at > now() - interval '30 days'),
    -- „Aktivní zařízení" = MAU (zařízení viděné za posl. 30 dní)
    'active_devices',       (select count(*) from app_installations where last_seen_at > now() - interval '30 days'),
    'android',              (select count(*) from app_installations where last_seen_at > now() - interval '30 days' and lower(platform) = 'android'),
    'ios',                  (select count(*) from app_installations where last_seen_at > now() - interval '30 days' and lower(platform) = 'ios'),
    'push_enabled_devices', (select count(*) from app_installations where last_seen_at > now() - interval '30 days' and push_enabled is true),
    'total_devices',        (select count(*) from app_installations),

    -- === Rezervace přes appku ===
    'app_bookings',         (select count(*) from bookings where booking_source = 'app'),

    -- === Legacy proxy z push_tokens (přechodné období) ===
    'push_active_devices',  (select count(*) from (
                                select distinct user_id, lower(platform)
                                from push_tokens
                                where active is true and user_id is not null
                             ) d)
  ) into result;

  return result;
end;
$$;

grant execute on function public.get_app_install_stats() to authenticated;
