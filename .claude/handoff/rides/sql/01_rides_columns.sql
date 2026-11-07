-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": pauza, auto-pauza, vícedenní cesty, slučování (1/8)
-- Sloupce user_rides + příznak ride_autopause. Jen přidává (IF NOT EXISTS),
-- nic nemaže ani nepřepisuje. Starší appky (4.1.3) nové sloupce nečtou.
--   pause_sec   — čas pauz (noc, delší stání, chůze); NEpatří do idle/gap/moving
--   pause_aware — jízdu vede appka, která se sama pozastavuje (start_user_trip)
--   stats_state — mezistav výpočtu mezi dávkami (nezobrazuje se)
--   stages      — etapy (dny) cesty [{f,t,km,mv,gap,ps,gain,max,a,b}]
--   trip_id / trip_name — sloučení více jízd do jedné cesty (jen zobrazení)
-- Idempotentní; aplikuje se v jedné transakci (deploy-sql --single-transaction).
-- ════════════════════════════════════════════════════════════════════

alter table public.user_rides add column if not exists pause_sec integer not null default 0;
alter table public.user_rides add column if not exists pause_aware boolean not null default false;
alter table public.user_rides add column if not exists stats_state jsonb;
alter table public.user_rides add column if not exists stages jsonb not null default '[]'::jsonb;
alter table public.user_rides add column if not exists trip_id uuid;
alter table public.user_rides add column if not exists trip_name text;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'user_rides_trip_name_len'
                    and conrelid = 'public.user_rides'::regclass) then
    alter table public.user_rides add constraint user_rides_trip_name_len
      check (trip_name is null or char_length(trip_name) <= 120);
  end if;
end $$;

create index if not exists idx_user_rides_trip
  on public.user_rides (user_id, trip_id) where trip_id is not null;

comment on column public.user_rides.pause_sec is
  'Čas pauz v sekundách: ruční/automatická pauza appky (bod s kmh = -1), ticho ≥ 5 min bez projetí (noc, jezero) a u starých appek běh stání/chůze ≥ 5 min. Nepatří do idle_sec, gap_sec, moving_sec ani duration_min.';
comment on column public.user_rides.pause_aware is
  'true = jízdu vede appka, která se sama pozastavuje (založeno přes start_user_trip). Řídí pravidla uzavírání (72 h / 30 dní místo 3 h / 36 h) a vypíná odvozování pauz z „bloudění" polohy.';
comment on column public.user_rides.stats_state is
  'Interní mezistav přírůstkového výpočtu statistik mezi dávkami (vyhlazená výška, rozběhnuté stání, příznak Doppler) + closed_by (kdo jízdu uzavřel: user/return/cron/start) a u přepočtu historie backfill/old. Nezobrazuje se.';
comment on column public.user_rides.stages is
  'Etapy (dny) jedné jízdy: [{f,t (epoch s), km, mv (s v pohybu), gap, ps (pauzy), gain (m), max (km/h), a,b ([lat,lng] začátek/konec)}]. Hranice etapy = pauza ≥ 6 h nebo ≥ 30 min přes 00:00–05:00 (Praha).';
comment on column public.user_rides.trip_id is
  'Sloučení jízd do jedné cesty (jen zobrazení): NULL = výchozí seskupení (podle booking_id), = id = záměrně samostatná, jiná hodnota = člen cesty s tímto klíčem. Bez FK.';
comment on column public.user_rides.trip_name is
  'Název cesty (stejný u všech jejích jízd), max 120 znaků. Nastavuje set_user_rides_trip.';
comment on column public.user_rides.duration_min is
  'Na cestě BEZ pauz (min): start → konec minus pause_sec. U jízd bez pauz stejné jako dřív (celkový čas).';

insert into public.feature_flags (key, enabled, description, conditions)
values ('ride_autopause', true,
        'Automatická pauza záznamu jízdy (appka). Vypnutí = nahrává se bez auto-pauzy; ruční pauza zůstává.',
        '{"stop_min":5,"walk_min":3,"resume_kmh":20,"home_h":3,"long_h":48}'::jsonb)
on conflict (key) do nothing;

notify pgrst, 'reload schema';
