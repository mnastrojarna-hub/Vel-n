-- ════════════════════════════════════════════════════════════════════════
--  RPC get_app_install_timeseries() — časová řada instalací appky (2026-07-28)
--  ─────────────────────────────────────────────────────────────────────────
--  Pro Velín → Analýza → Aplikace: graf instalací (uživatelů appky) v čase,
--  rozpad Android / iOS, volitelné časové úseky (agregaci den/týden/měsíc
--  dělá frontend nad denními řádky).
--
--  Zdroje:
--   • installs      — app_installations.first_seen_at::date × lower(platform).
--                     PŘESNÁ evidence od 2026-06-28 (build s InstallationService);
--                     instalace starší než tracking se objeví v den prvního
--                     heartbeatu — dřívější per-platform historie neexistuje
--                     (Play Developer API / App Store Connect napojené není).
--   • registrations — profiles.created_at::date (kompletní historie růstu
--                     uživatelských účtů od spuštění — historická křivka).
--
--  Denních řádků jsou max stovky → vrací se vše, frontend filtruje/kumuluje.
--  SECURITY DEFINER, gate is_admin() (vzor get_app_install_stats).
-- ════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.get_app_install_timeseries()
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_installs jsonb;
  v_regs     jsonb;
  v_since    date;
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'd', to_char(d, 'YYYY-MM-DD'),
           'android', android,
           'ios', ios,
           'other', other) order by d), '[]'::jsonb),
         min(d)
    into v_installs, v_since
  from (
    select first_seen_at::date as d,
           count(*) filter (where lower(coalesce(platform,'')) = 'android') as android,
           count(*) filter (where lower(coalesce(platform,'')) = 'ios')     as ios,
           count(*) filter (where lower(coalesce(platform,''))
                            not in ('android','ios'))                        as other
    from public.app_installations
    where first_seen_at is not null
    group by 1
  ) t;

  select coalesce(jsonb_agg(jsonb_build_object(
           'd', to_char(d, 'YYYY-MM-DD'),
           'n', n) order by d), '[]'::jsonb)
    into v_regs
  from (
    select created_at::date as d, count(*) as n
    from public.profiles
    where created_at is not null
    group by 1
  ) t;

  return jsonb_build_object(
    'installs', v_installs,
    'registrations', v_regs,
    'tracking_since', coalesce(to_char(v_since, 'YYYY-MM-DD'), null)
  );
end;
$$;

revoke all on function public.get_app_install_timeseries() from public;
revoke all on function public.get_app_install_timeseries() from anon;
grant execute on function public.get_app_install_timeseries() to authenticated;
grant execute on function public.get_app_install_timeseries() to service_role;

commit;
