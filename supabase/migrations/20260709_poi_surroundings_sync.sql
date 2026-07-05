-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Popis okolí: cron volá edge fn SYNCHRONNĚ (fix „0 zápisů")
--
-- ZJIŠTĚNÍ: na tomto projektu `EdgeRuntime.waitUntil` NEUDRŽÍ background práci —
-- Supabase zabije worker hned po odpovědi 202, takže cron zapsal 0 bodů
-- (ověřeno: `?wait=1` synchronně zpracuje bez chyby, cron s 202 ne).
--
-- OPRAVA: trigger volá funkci s `?wait=1` (funkce POČKÁ na dokončení dávky a
-- vrátí výsledek) a s DELŠÍM pg_net timeoutem (28 s), aby spojení zůstalo
-- otevřené a worker žil, dokud dávka nedoběhne. Dávka je malá (budget 20 s),
-- ať pohodlně doběhne v rámci životnosti workeru (ověřeno ~27 s OK).
-- Cron každou minutu (krátké synchronní dávky se nepřekrývají). Idempotentní.
-- ════════════════════════════════════════════════════════════════════

create or replace function public.trigger_poi_surroundings_backfill()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_key text;
  v_missing int;
begin
  select
    (select count(*) from public.points_of_interest where surroundings is null and is_active = true)
  + (select count(*) from public.route_pois where surroundings is null)
  into v_missing;

  if coalesce(v_missing, 0) = 0 then
    begin
      perform cron.unschedule('backfill-poi-surroundings');
    exception when others then null;
    end;
    return;
  end if;

  select value #>> '{}' into v_url from public.app_settings where key = 'supabase_url';
  select value #>> '{}' into v_key from public.app_settings where key = 'service_role_key';
  if v_url is null or v_url = '' or v_key is null or v_key = '' then
    raise warning 'trigger_poi_surroundings_backfill: app_settings supabase_url/service_role_key chybí';
    return;
  end if;

  -- SYNCHRONNĚ: `?wait=1` → funkce počká na dokončení dávky; timeout 28 s drží
  -- spojení otevřené (worker žije), budget 20 s = dávka doběhne s rezervou.
  perform net.http_post(
    url := v_url || '/functions/v1/backfill-poi-surroundings?wait=1',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := jsonb_build_object('scope', 'all', 'limit', 12, 'concurrency', 6, 'budget_ms', 20000),
    timeout_milliseconds := 28000
  );
end $$;

grant execute on function public.trigger_poi_surroundings_backfill() to service_role;

-- Cron každou minutu (krátké synchronní dávky, bez překryvu).
do $$
begin
  begin
    perform cron.unschedule('backfill-poi-surroundings');
  exception when others then null;
  end;
  perform cron.schedule(
    'backfill-poi-surroundings',
    '* * * * *',
    $cron$ select public.trigger_poi_surroundings_backfill(); $cron$
  );
exception when others then
  raise warning 'cron.schedule selhalo (pg_cron nedostupné?): %', sqlerrm;
end $$;
