-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": pauza, auto-pauza, vícedenní cesty (5/8)
-- Veřejná RPC příjmu bodů a ukončení. Podpisy, klíče odpovědí i chybové
-- kódy beze změny (appka 4.1.3 funguje dál), žádný nový chybový kód.
--   append_ride_track — deleguje na _ride_append_core; p_max_speed_kmh se
--       ignoruje (max z bodů); dávka jen z bodů po vrácení výpůjčky jízdu
--       uzavře k času vrácení (ride_finished + reason booking_ended).
--   finish_user_ride — poslední dávka přes _ride_append_core, konec = teď,
--       u vrácené výpůjčky nejpozději vrácení; closed_by = user.
--   _ride_append_late (interní) — POZDNÍ body do už uzavřené výpůjčky:
--       telefon byl v den vrácení offline, úklid (nebo vrácení) jízdu mezitím
--       uzavřel. Přijmou se jen body výpůjčky motorky uzavřené vrácením /
--       úklidem / novým startem (closed_by return | cron | start), novější
--       než poslední uložený a nejvýš do vrácení (+30 s / 4.1.3 +2 min),
--       do 7 dní po vrácení; jízda se přepočte k témuž pravidlu konce
--       (min(vrácení, poslední bod + 2 min)). Odpověď append zůstává
--       ride_finished (+ reason booking_ended, když se něco uložilo).
--       Jízdu ukončenou jezdcem (Stop) ani vlastní jízdu to nemění.
--       „Vrácení" = _ride_booking_end (i zaparkování v kóji kiosku před
--       posledním dnem, než ho kiosk_process_returns dokončí).
--   _ride_reopen (interní) — VLASTNÍ cesta nové appky, kterou uzavřel úklid
--       (72 h bez kontaktu se serverem: roaming vypnutý, cizina bez dat),
--       se při dalších bodech znovu otevře a pokračuje — bez rozdělení i bez
--       ztráty bodů z doby offline. Jen pause_aware, closed_by = cron, bez
--       výpůjčky motorky, start ≤ 30 dní, uživatel nemá jinou otevřenou
--       jízdu a dávka nese bod novější než poslední uložený. append vrátí
--       běžný úspěch (+ reopened), finish ji pak uzavře (closed_by = user).
-- Idempotentní (create or replace se stejnými podpisy → práva zůstávají).
-- ════════════════════════════════════════════════════════════════════

create or replace function public._ride_append_late(p_ride_id uuid, p_points jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare v_r user_rides; v_ret timestamptz; v_res jsonb; v_n int := 0;
begin
  select * into v_r from user_rides where id = p_ride_id;          -- volající drží FOR UPDATE
  if v_r.id is null or v_r.is_recording or v_r.booking_id is null
     or jsonb_typeof(p_points) is distinct from 'array' or jsonb_array_length(p_points) = 0
     or coalesce(v_r.stats_state->>'closed_by', '') not in ('return', 'cron', 'start') then
    return 0;
  end if;
  v_ret := _ride_booking_end(v_r.booking_id);
  if v_ret is null or now() > v_ret + interval '7 days' then return 0; end if;
  -- Jádro filtruje: duplicity (≤ poslední uložený bod), body po vrácení, vadné.
  v_res := _ride_append_core(p_ride_id, p_points);
  if v_res->>'success' = 'true' then
    v_n := jsonb_array_length(p_points) - coalesce((v_res->>'dropped')::int, 0);
  end if;
  if v_n > 0 then
    -- konec ≤ poslední bod + 2 min; closed_by zůstane (jádro přepsalo stats_state)
    perform _ride_close(p_ride_id, v_ret, v_r.stats_state->>'closed_by', true);
  end if;
  return greatest(v_n, 0);
end;
$$;

create or replace function public._ride_reopen(p_ride_id uuid, p_points jsonb)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_r user_rides; v_last jsonb; v_lim float8; v_now_e float8 := extract(epoch from now()); v_n int;
begin
  select * into v_r from user_rides where id = p_ride_id;          -- volající drží FOR UPDATE
  if v_r.id is null or v_r.is_recording or not v_r.pause_aware
     or coalesce(v_r.stats_state->>'closed_by', '') <> 'cron'
     or v_r.started_at < now() - interval '30 days'
     or jsonb_typeof(p_points) is distinct from 'array' then
    return false;
  end if;
  -- Jen vlastní cesta (výpůjčka jen výbavy = vlastní); výpůjčka motorky → _ride_append_late.
  if v_r.booking_id is not null and not exists (
       select 1 from bookings b where b.id = v_r.booking_id and b.booking_kind = 'gear') then
    return false;
  end if;
  if exists (select 1 from user_rides o where o.user_id = v_r.user_id and o.is_recording and o.id <> v_r.id) then
    return false;                                                   -- mezitím jiná jízda → nová cesta
  end if;
  -- Hranice „nový bod" = poslední uložený bod (věrohodný čas), jinak last_fix_at.
  v_n := case when jsonb_typeof(v_r.track) = 'array' then jsonb_array_length(v_r.track) else 0 end;
  v_last := case when v_n > 0 then v_r.track -> (v_n - 1) end;
  v_lim := case when jsonb_typeof(v_last) is distinct from 'array' then null
                when jsonb_array_length(v_last) < 3 then null
                when not ((v_last->>2) ~ '^[0-9]+(\.[0-9]+)?$') then null
                when (v_last->>2)::float8 <= v_now_e + 600 then (v_last->>2)::float8 end;
  v_lim := coalesce(v_lim, extract(epoch from coalesce(v_r.last_fix_at, v_r.started_at)));
  if not exists (
       select 1 from jsonb_array_elements(p_points) e(pt)
        where case when jsonb_typeof(e.pt) <> 'array' then false
                   when jsonb_array_length(e.pt) < 3 then false
                   when jsonb_typeof(e.pt->0) <> 'number' or jsonb_typeof(e.pt->1) <> 'number' then false
                   when not ((e.pt->>2) ~ '^[0-9]+(\.[0-9]+)?$') then false
                   else (e.pt->>2)::float8 > v_lim and (e.pt->>2)::float8 <= v_now_e + 600 end) then
    return false;                                                   -- jen staré / opakované / vadné body
  end if;
  begin
    update user_rides set is_recording = true, ended_at = null,
           stats_state = coalesce(stats_state, '{}'::jsonb) - 'closed_by',
           -- automatický název (datum / rozsah) se při dalším uzavření sestaví znovu
           name = case when ended_at is not null and name = _ride_auto_name(
                         (started_at at time zone 'Europe/Prague')::date,
                         (ended_at at time zone 'Europe/Prague')::date) then '' else name end
     where id = p_ride_id;
  exception when unique_violation then
    return false;                                                   -- souběžný start jiné jízdy
  end;
  return true;
end;
$$;

create or replace function public.append_ride_track(p_ride_id uuid, p_points jsonb, p_max_speed_kmh numeric default null::numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_r user_rides; v_res jsonb; v_late int;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  if jsonb_typeof(p_points) is distinct from 'array' then
    return jsonb_build_object('success', false, 'error', 'points_required');
  end if;
  select * into v_r from user_rides where id = p_ride_id and user_id = auth.uid() for update;
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;
  -- UZAVŘENÁ jízda: vlastní cestu uzavřenou úklidem (dlouho offline) dávka
  -- znovu otevře a pokračuje se v ní. Jinak klient bere „ride_finished" jako
  -- „doručeno"; pozdní body výpůjčky (offline v den vrácení) se ještě uloží.
  if not v_r.is_recording then
    if _ride_reopen(p_ride_id, p_points) then
      return _ride_append_core(p_ride_id, p_points) || jsonb_build_object('reopened', true);
    end if;
    v_late := _ride_append_late(p_ride_id, p_points);
    return jsonb_build_object('success', false, 'error', 'ride_finished', 'finished', true)
        || case when v_late > 0 then jsonb_build_object('reason', 'booking_ended') else '{}'::jsonb end;
  end if;
  -- p_max_speed_kmh se ignoruje: každý bod nese vlastní rychlost (ověřenou).
  v_res := _ride_append_core(p_ride_id, p_points);
  if v_res ? 'booking_ended' then
    perform _ride_close(p_ride_id, (v_res->>'end_at')::timestamptz, 'return', false);
    return jsonb_build_object('success', false, 'error', 'ride_finished', 'finished', true, 'reason', 'booking_ended');
  end if;
  return v_res;
end;
$$;

create or replace function public.finish_user_ride(p_ride_id uuid, p_points jsonb default null::jsonb, p_name text default null::text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_r user_rides; v_end timestamptz := now(); v_ret timestamptz; v_res jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  select * into v_r from user_rides where id = p_ride_id and user_id = auth.uid() for update;
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;
  if jsonb_typeof(p_points) = 'array' and jsonb_array_length(p_points) > 0 then
    if v_r.is_recording then
      v_res := _ride_append_core(p_ride_id, p_points);
      if v_res ? 'booking_ended' then
        return _ride_close(p_ride_id, (v_res->>'end_at')::timestamptz, 'return', false);
      end if;
    elsif _ride_reopen(p_ride_id, p_points) then
      -- vlastní cesta uzavřená úklidem (offline) → body dovnitř, pak Stop níže
      perform _ride_append_core(p_ride_id, p_points);
      v_r.is_recording := true;
    else
      perform _ride_append_late(p_ride_id, p_points);         -- výpůjčka uzavřená úklidem
    end if;
  end if;
  if coalesce(trim(p_name), '') <> '' then
    update user_rides set name = left(trim(p_name), 120) where id = p_ride_id;
  end if;
  if not v_r.is_recording then return _ride_finalize(p_ride_id, null); end if;   -- already_finished
  -- Konec výpůjčky nesmí být později než vrácení motorky / zaparkování v kóji kiosku
  -- (start mohl posunout „připraveno"; body po něm _ride_close ořízne).
  if v_r.booking_id is not null then
    v_ret := _ride_booking_end(v_r.booking_id);
    if v_ret is not null and v_ret < v_end then
      select greatest(v_ret, started_at) into v_end from user_rides where id = p_ride_id;
    end if;
  end if;
  return _ride_close(p_ride_id, v_end, 'user', false);
end;
$$;

revoke all on function public._ride_append_late(uuid, jsonb) from public, anon, authenticated;
grant execute on function public._ride_append_late(uuid, jsonb) to service_role;
revoke all on function public._ride_reopen(uuid, jsonb) from public, anon, authenticated;
grant execute on function public._ride_reopen(uuid, jsonb) to service_role;

notify pgrst, 'reload schema';
