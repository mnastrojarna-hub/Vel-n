-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": 3. kolo z adversariálního review 2026-09-22.
-- Navazuje na 20260921g (nasazená) a 20260922_ (nasazená, běh #104) —
-- obě se NEEDITUJÍ, tohle je nový soubor řadící se ZA ně.
--
-- 1) _ride_stats: práh stání 50 m → 300 m (R3). Při filtru 20 m + intervalu
--    5 s je první fix po rozjezdu 40–100 m od posledního, takže i 3minutová
--    zastávka (tankování, foto) byla „MEZERA" a km přes ni se zahodily.
--    Práh je ABSOLUTNÍ, ne rychlostní: rychlostní pravidlo by 2 h spánku
--    appky s posunem 5 km (2,5 km/h) vzalo jako stání a 5 km vzdušné čáry
--    přičetlo — přesně to, co g odstraňovala.
-- 2) append_ride_track: okno pro zahození bodů ze staré jízdy 5 min → 1 h.
--    Čas bodu je čas TELEFONU, start jízdy čas SERVERU; telefon o 5 min
--    pozadu by jinak přišel o každou dávku a jízda by se tiše smazala.
-- 3) _ride_track_cap: prořídnutí zachovává body na krajích mezer, aby
--    Velín/appka (dělí uloženou stopu) viděly tytéž mezery jako gap_sec.
-- 4) close_stale_user_rides + start_user_ride: „naposledy živá" =
--    greatest(last_fix_at, updated_at) — updated_at je serverový čas.
-- 5) start_user_ride: se zadaným p_booking_id se páruje podle id, ne podle
--    UTC dne (jízda mezi 0:00–2:00 Praha vznikala bez rezervace).
-- 6) finish_user_ride: konec nejpozději `bookings.returned_at`.
-- 7) Přepočet UZAVŘENÝCH automatických jízd novým prahem (bez mazání —
--    vyšší práh km jen přidává).
-- Idempotentní (create or replace, stejné signatury).
-- ════════════════════════════════════════════════════════════════════

create or replace function public._ride_stats(p_track jsonb)
returns jsonb language plpgsql immutable as $$
declare
  c_gap_sec   constant double precision := 180;   -- nad tímhle už úsek nepovažujeme za souvislou jízdu
  c_still_km  constant double precision := 0.3;   -- posun do 300 m = stál na místě (viz hlavička migrace)
  c_max_kmh   constant double precision := 300;   -- nad tím je to GPS skok, ne rychlost
  c_move_kmh  constant double precision := 3;     -- pod tím se počítá STÁNÍ
  c_inst_sec  constant double precision := 60;    -- jen z tak krátkého úseku věříme dopočtené rychlosti
  c_gain_m    constant double precision := 5;     -- menší změna výšky je šum GPS

  v_pt jsonb;
  v_lat double precision; v_lng double precision;
  v_ts double precision; v_alt double precision; v_kmh double precision;
  v_plat double precision; v_plng double precision;
  v_pts double precision; v_palt double precision;
  v_d double precision; v_dt double precision; v_v double precision;
  -- Vzdálenost od POSLEDNÍHO bodu s časovou značkou. U stopy, kde má čas
  -- každý bod (dnešní klient), se rovná `v_d`. Když ale jeden bod uprostřed
  -- čas nemá, `v_dt` pokrývá dva úseky — a porovnávat ho s délkou jen toho
  -- posledního by rychlost podhodnotilo a úsek chybně označilo za stání.
  v_dseg double precision := 0;
  v_dist double precision := 0; v_move double precision := 0;
  v_idle double precision := 0; v_gap double precision := 0;
  v_gain double precision := 0; v_max double precision := 0;
  v_is_gap boolean; v_bad_time boolean;
begin
  if jsonb_typeof(p_track) is distinct from 'array' then
    return jsonb_build_object('dist_km', 0, 'moving_sec', 0, 'idle_sec', 0,
                              'gap_sec', 0, 'gain_m', 0, 'max_kmh', 0);
  end if;

  for v_pt in select * from jsonb_array_elements(p_track) loop
    if jsonb_typeof(v_pt) <> 'array' or jsonb_array_length(v_pt) < 2 then continue; end if;
    v_lat := (v_pt->>0)::double precision;
    v_lng := (v_pt->>1)::double precision;
    if v_lat is null or v_lng is null then continue; end if;
    v_ts  := case when jsonb_array_length(v_pt) > 2 then (v_pt->>2)::double precision end;
    v_kmh := case when jsonb_array_length(v_pt) > 3 then (v_pt->>3)::double precision end;
    v_alt := case when jsonb_array_length(v_pt) > 4 then (v_pt->>4)::double precision end;
    -- Rychlost změřená přijímačem. 0 = „stál nebo neumí", ne maximum.
    if v_kmh is not null and v_kmh > v_max and v_kmh < c_max_kmh then v_max := v_kmh; end if;

    v_is_gap := false; v_bad_time := false;

    if v_plat is not null then
      v_d := 6371 * 2 * asin(sqrt(
        power(sin(radians(v_lat - v_plat) / 2), 2) +
        cos(radians(v_plat)) * cos(radians(v_lat)) *
        power(sin(radians(v_lng - v_plng) / 2), 2)));
      v_dseg := v_dseg + v_d;

      v_dt := case when v_ts is not null and v_pts is not null then v_ts - v_pts end;
      -- Body přeházené v čase / přenastavené hodiny na telefonu. Takovému
      -- úseku nevěříme ANI vzdálenost — dřív se km přičetly, ale čas ne,
      -- takže průměrná rychlost vyskočila nad maximum.
      -- dt = 0 (dva fixy v téže zaokrouhlené sekundě — při 100 km/h a 20m filtru
      -- běžné) NENÍ vadný čas: kilometry se počítají, jen se z toho nedá
      -- odvodit rychlost. Vadný je jen záporný nebo absurdní skok.
      v_bad_time := v_dt is not null and (v_dt < 0 or v_dt >= 86400);
      if v_bad_time then v_dt := null; end if;

      v_v := case when v_dt is not null and v_dt > 0 then v_dseg / (v_dt / 3600) end;

      -- MEZERA: dlouhá pauza, po které se motorkář objevil jinde.
      v_is_gap := v_dt is not null and v_dt > c_gap_sec and v_dseg > c_still_km;

      if v_bad_time then
        -- Nic nepřičítáme: ani km, ani čas. (Stopa bez časových značek je
        -- něco jiného — tam dt vůbec nevznikne a km se počítají dál.)
        null;
      elsif v_is_gap then
        -- Trasu mezi body NEZNÁME → vzdušnou čáru nezapočítáme ani do km,
        -- ani do času jízdy. Jen si poznamenáme, jak dlouho jsme byli slepí.
        v_gap := v_gap + v_dt;
      else
        -- GPS skok (teleport) se do vzdálenosti nepočítá.
        if v_v is null or v_v < c_max_kmh then
          v_dist := v_dist + v_d;
        end if;

        if v_dt is not null then
          if v_v >= c_move_kmh and v_v < c_max_kmh then
            v_move := v_move + v_dt;
          else
            v_idle := v_idle + v_dt;   -- semafor, foto, pauza i „stál a nepřišel fix"
          end if;
          -- Maximum i z DOPOČTENÉ rychlosti, ale jen z krátkého úseku, kde
          -- odpovídá okamžité rychlosti. (Dřív se počítalo jen když klient
          -- rychlost neposlal — proto mohlo max vyjít menší než průměr.)
          if v_dt <= c_inst_sec and v_v > v_max and v_v < c_max_kmh then
            v_max := v_v;
          end if;
        end if;

        -- Nastoupáno: jen přes souvislý úsek a jen změny nad 5 m.
        if v_alt is not null and v_palt is not null and v_alt - v_palt >= c_gain_m then
          v_gain := v_gain + (v_alt - v_palt);
        end if;
      end if;
    end if;

    v_plat := v_lat; v_plng := v_lng;
    -- Časovou kotvu (a s ní i nasčítanou vzdálenost) posouváme jen na bodu,
    -- který čas opravdu má.
    if v_ts is not null then v_pts := v_ts; v_dseg := 0; end if;
    -- Přes mezeru (ani přes nedůvěryhodný úsek) výšku neporovnáváme.
    if v_is_gap or v_bad_time then v_palt := null;
    elsif v_alt is not null then v_palt := v_alt; end if;
  end loop;

  return jsonb_build_object(
    'dist_km', round(v_dist::numeric, 3),
    'moving_sec', round(v_move)::int,
    'idle_sec', round(v_idle)::int,
    'gap_sec', round(v_gap)::int,
    'gain_m', round(v_gain)::int,
    'max_kmh', round(v_max::numeric, 1));
end;
$$;

create or replace function public.append_ride_track(
  p_ride_id uuid, p_points jsonb,
  p_max_speed_kmh numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_r user_rides; v_track jsonb; v_last jsonb; v_seg jsonb; v_st jsonb;
  v_dist numeric; v_move int; v_idle int; v_gap int; v_fix timestamptz;
  v_avg numeric;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  if jsonb_typeof(p_points) is distinct from 'array' then
    return jsonb_build_object('success', false, 'error', 'points_required');
  end if;

  select * into v_r from user_rides
   where id = p_ride_id and user_id = auth.uid() for update;
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;

  -- Do UZAVŘENÉ jízdy se už nepřidává. Telefon, který byl při vracení
  -- motorky offline, se ozve klidně druhý den — a dávka ze starého bufferu
  -- by hotové jízdě přepsala statistiky i konec. Klient tenhle stav bere
  -- jako „doručeno" a dávku zahodí (viz `appendRideTrack` v appce).
  if not v_r.is_recording then
    return jsonb_build_object('success', false, 'error', 'ride_finished',
                              'finished', true);
  end if;

  -- Body z PŘEDCHOZÍ jízdy do téhle nepatří. Když vracení proběhlo offline,
  -- appka si nechala neodeslanou dávku; cron starou jízdu uzavřel a další
  -- den vznikla nová — a ta stará dávka by se do ní přilepila jako
  -- „15 h bez signálu" přes noc. Bod s časem starším než start jízdy
  -- proto tiše vynecháme; body bez času necháme. Rezerva 1 HODINA, ne
  -- 5 minut: čas bodu je čas TELEFONU a start jízdy čas SERVERU — telefon
  -- s hodinami o pár minut pozadu by jinak přišel o každou dávku a jízda
  -- by se jako prázdná tiše smazala.
  -- CASE místo OR: SQL nezaručuje zkrácené vyhodnocení a jsonb_array_length
  -- na ne-poli by shodila celou dávku. `with ordinality` drží pořadí bodů.
  select coalesce(jsonb_agg(e.pt order by e.ord), '[]'::jsonb) into p_points
    from jsonb_array_elements(p_points) with ordinality as e(pt, ord)
   where case
           when jsonb_typeof(e.pt) <> 'array' then true
           when jsonb_array_length(e.pt) < 3 then true
           when not ((e.pt->>2) ~ '^[0-9]+(\.[0-9]+)?$') then true
           else to_timestamp((e.pt->>2)::double precision) >= v_r.started_at - interval '1 hour'
         end;
  if jsonb_array_length(p_points) = 0 then
    -- Celá dávka byla ze staré jízdy: nic k uložení, pro klienta „doručeno".
    return jsonb_build_object('success', true, 'points', jsonb_array_length(coalesce(v_r.track, '[]'::jsonb)),
                              'distance_km', round(coalesce(v_r.distance_km, 0), 1),
                              'moving_sec', v_r.moving_sec, 'idle_sec', v_r.idle_sec, 'gap_sec', v_r.gap_sec,
                              'dropped_stale', true);
  end if;

  -- Statistiky ÚSEKU: nové body + poslední už uložený bod (aby se nezahodil
  -- kousek mezi dávkami). Přičtou se k dosavadním součtům.
  if jsonb_array_length(coalesce(v_r.track, '[]'::jsonb)) > 0 then
    v_seg := jsonb_build_array(v_r.track -> (jsonb_array_length(v_r.track) - 1)) || p_points;
  else
    v_seg := p_points;
  end if;
  v_st := _ride_stats(v_seg);

  v_dist := coalesce(v_r.distance_km, 0) + (v_st->>'dist_km')::numeric;
  v_move := coalesce(v_r.moving_sec, 0) + (v_st->>'moving_sec')::int;
  v_idle := coalesce(v_r.idle_sec, 0) + (v_st->>'idle_sec')::int;
  v_gap  := coalesce(v_r.gap_sec, 0) + (v_st->>'gap_sec')::int;

  v_track := _ride_track_cap(coalesce(v_r.track, '[]'::jsonb) || p_points);
  if jsonb_array_length(v_track) > 0 then
    v_last := v_track -> (jsonb_array_length(v_track) - 1);
  end if;

  -- Čas posledního fixu bereme z bodu; starý klient ho neposílá → now().
  v_fix := case
    when v_last is not null and jsonb_typeof(v_last) = 'array'
      and jsonb_array_length(v_last) > 2
      and (v_last->>2) ~ '^[0-9]+(\.[0-9]+)?$'
    then to_timestamp((v_last->>2)::double precision)
    else now() end;
  if v_fix > now() + interval '1 hour' or v_fix < now() - interval '30 days' then
    v_fix := now();   -- přenastavené hodiny na telefonu
  end if;

  v_avg := case when v_move > 0
                then least(round((v_dist / (v_move::numeric / 3600)), 1), 200.0) end;

  update user_rides set
    track = v_track,
    distance_km = v_dist,
    moving_sec = v_move,
    idle_sec = v_idle,
    gap_sec = v_gap,
    last_fix_at = v_fix,
    avg_speed_kmh = v_avg,
    elevation_gain_m = coalesce(elevation_gain_m, 0) + (v_st->>'gain_m')::int,
    end_lat = coalesce((v_last->>0)::double precision, end_lat),
    end_lng = coalesce((v_last->>1)::double precision, end_lng),
    start_lat = coalesce(start_lat, (v_track->0->>0)::double precision),
    start_lng = coalesce(start_lng, (v_track->0->>1)::double precision),
    -- Celkový čas se počítá k POSLEDNÍMU FIXU, ne k `now()`. Dřív rostl
    -- dál i po tom, co appka přestala posílat body — tak vznikl „celkový
    -- čas 33 h 18 min" u vyjížďky, která dávno skončila.
    duration_min = greatest(0, (extract(epoch from (v_fix - started_at)) / 60)::int),
    -- Kdo má průměr X, musel někde jet aspoň X. Pojistka proti tomu, aby
    -- Velín zase ukázal „Ø 4 km/h · max 3 km/h".
    max_speed_kmh = greatest(coalesce(max_speed_kmh, 0),
                             coalesce(p_max_speed_kmh, 0),
                             coalesce((v_st->>'max_kmh')::numeric, 0),
                             coalesce(v_avg, 0))
  where id = p_ride_id;

  return jsonb_build_object('success', true, 'points', jsonb_array_length(v_track),
                            'distance_km', round(v_dist, 1),
                            'moving_sec', v_move, 'idle_sec', v_idle, 'gap_sec', v_gap);
end;
$$;

create or replace function public._ride_track_cap(p_track jsonb, p_max int default 4000)
returns jsonb language sql immutable as $$
  select case
    when jsonb_typeof(p_track) is distinct from 'array' then '[]'::jsonb
    when jsonb_array_length(p_track) <= p_max then p_track
    else (
      -- Každý k-tý bod + poslední + KAŽDÝ bod, u kterého je k sousedovi časový
      -- skok přes 180 s. Dřív prořídnutí smazalo právě body na krajích mezery
      -- a Velín i appka (dělí ULOŽENOU stopu) pak mezeru neviděly, zatímco
      -- server (počítá ze surových dávek) ji do gap_sec započítal — čísla
      -- a mapa si neodpovídaly.
      select coalesce(jsonb_agg(w.pt order by w.ord), '[]'::jsonb)
      from (
        select e.pt, e.ord, e.ts,
               lag(e.ts)  over (order by e.ord) as ts_prev,
               lead(e.ts) over (order by e.ord) as ts_next
        from (
          select e0.pt, e0.ord,
                 case when jsonb_typeof(e0.pt) = 'array' and jsonb_array_length(e0.pt) > 2
                       and (e0.pt->>2) ~ '^[0-9]+(\.[0-9]+)?$'
                      then (e0.pt->>2)::double precision end as ts
          from jsonb_array_elements(p_track) with ordinality as e0(pt, ord)
        ) e
      ) w
      where (w.ord - 1) % ceil(jsonb_array_length(p_track)::numeric / p_max)::int = 0
         or w.ord = jsonb_array_length(p_track)
         or (w.ts is not null and w.ts_prev is not null and w.ts - w.ts_prev > 180)
         or (w.ts is not null and w.ts_next is not null and w.ts_next - w.ts > 180)
    )
  end;
$$;

create or replace function public.close_stale_user_rides()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_at timestamptz; v_res jsonb; v_closed int := 0; v_dropped int := 0;
begin
  for v_id, v_at in
    select r.id, greatest(coalesce(r.last_fix_at, r.started_at), r.updated_at)
      from user_rides r
      left join bookings b on b.id = r.booking_id
     where r.is_recording
       and (
         -- 3 h bez jediného GPS bodu = vyjížďka dávno skončila. `updated_at`
         -- (serverový čas, bumpne se každou dávkou) kryje telefon s hodinami
         -- pozadu — jinak by cron uzavřel i živě nahrávanou jízdu.
         greatest(coalesce(r.last_fix_at, r.started_at), r.updated_at) < now() - interval '3 hours'
         -- pojistka i pro nahrávku, do které něco kape, ale běží nesmyslně dlouho
         or r.started_at < now() - interval '36 hours'
         -- výpůjčka skončila / byla zrušena
         or (b.id is not null and (b.end_date::date < current_date
                                   or b.status in ('completed','cancelled')))
       )
     order by r.started_at
     limit 500
  loop
    begin
      v_res := _ride_finalize(v_id, v_at);
      if v_res->>'discarded' = 'true' then v_dropped := v_dropped + 1;
      else v_closed := v_closed + 1; end if;
    exception when others then
      -- Jedna vadná jízda nesmí shodit úklid ostatních.
      raise warning 'close_stale_user_rides: jízda % selhala: %', v_id, sqlerrm;
    end;
  end loop;
  return jsonb_build_object('closed', v_closed, 'discarded', v_dropped);
end;
$$;

create or replace function public.start_user_ride(
  p_booking_id uuid default null,
  p_lat double precision default null,
  p_lng double precision default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_booking uuid; v_moto uuid; v_moto_name text; v_track jsonb := '[]'::jsonb;
  v_stale timestamptz;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;

  -- Už něco běží? Rozjetou nahrávku obnovíme (idempotentní start po
  -- restartu appky) — ALE jen když je čerstvá. Nahrávka, do které už
  -- hodiny nic nepřiteklo, patří k dávno skončené vyjížďce; kdybychom ji
  -- vrátili, unikátní index `uq_user_rides_recording` by zákazníkovi
  -- zablokoval každou další jízdu.
  select id, greatest(coalesce(last_fix_at, started_at), updated_at) into v_id, v_stale
    from user_rides where user_id = auth.uid() and is_recording limit 1;
  if v_id is not null then
    if v_stale > now() - interval '3 hours' then
      return jsonb_build_object('success', true, 'id', v_id, 'resumed', true);
    end if;
    perform _ride_finalize(v_id, v_stale);   -- dojetá / zapomenutá → uzavřít
    v_id := null;
  end if;

  -- Když appka rezervaci POJMENUJE (hlídač ji spouští až po převzetí motorky),
  -- páruje se podle id — ne podle kalendářního dne v UTC. Jinak jízda
  -- rozjetá v Praze mezi půlnocí a 2:00 vznikla BEZ rezervace a operátor ji
  -- v „Mapa a poloha" nikdy neviděl. Bez id (ruční start) zůstává dnešní den.
  select b.id, b.moto_id into v_booking, v_moto
  from bookings b
  where b.user_id = auth.uid()
    and b.status in ('reserved','active')
    and (b.id = p_booking_id
         or (p_booking_id is null
             and b.start_date::date <= current_date and b.end_date::date >= current_date))
  order by b.start_date desc limit 1;

  if v_moto is not null then
    select nullif(trim(coalesce(m.brand,'') || ' ' || coalesce(m.model,'')), '')
      into v_moto_name from motorcycles m where m.id = v_moto;
  end if;

  -- První bod nese i ČAS — bez něj by se úsek k dalšímu bodu nedal
  -- posoudit (jízda × stání × mezera) a rovnou by se počítal jako jízda.
  if p_lat is not null and p_lng is not null then
    v_track := jsonb_build_array(jsonb_build_array(
      p_lat, p_lng, round(extract(epoch from now()))));
  end if;

  -- `end_*` = POSLEDNÍ známá poloha; na startu je to ten první bod. Velín
  -- z něj kreslí živou polohu, takže nesmí zůstat prázdná do první dávky.
  insert into user_rides (user_id, booking_id, moto_id, moto_name, source,
                          track, start_lat, start_lng, end_lat, end_lng,
                          is_recording, last_fix_at)
  values (auth.uid(), v_booking, v_moto, v_moto_name, 'auto',
          v_track, p_lat, p_lng, p_lat, p_lng, true,
          case when p_lat is not null then now() end)
  returning id into v_id;

  return jsonb_build_object('success', true, 'id', v_id, 'resumed', false,
                            'booking_id', v_booking, 'moto_name', v_moto_name);
end;
$$;

create or replace function public.finish_user_ride(
  p_ride_id uuid, p_points jsonb default null, p_name text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_r user_rides; v_end timestamptz := now(); v_ret timestamptz; v_fix timestamptz;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;

  select * into v_r from user_rides where id = p_ride_id and user_id = auth.uid();
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;

  -- Poslední dávka bodů projde stejnou cestou jako každá jiná (statistiky
  -- i mezery se tak počítají na JEDNOM místě).
  if jsonb_typeof(p_points) = 'array' and jsonb_array_length(p_points) > 0 then
    perform append_ride_track(p_ride_id, p_points, null);
  end if;

  if coalesce(trim(p_name), '') <> '' then
    update user_rides set name = left(trim(p_name), 120) where id = p_ride_id;
  end if;

  -- Konec jízdy s výpůjčkou nesmí být později než VRÁCENÍ motorky. Když
  -- zákazník otevře appku až po vrácení (cron ještě nestihl), hlídač zavolá
  -- finish — a `now()` by k jízdě přičetlo hodiny stání po vrácení.
  if v_r.booking_id is not null then
    select returned_at into v_ret from bookings where id = v_r.booking_id;
    if v_ret is not null and v_ret < v_end then
      -- last_fix_at čerstvě — poslední dávka výš ho mohla posunout.
      select last_fix_at into v_fix from user_rides where id = p_ride_id;
      v_end := greatest(v_ret, coalesce(v_fix, v_r.last_fix_at, v_r.started_at));
    end if;
  end if;
  return _ride_finalize(p_ride_id, v_end);
end;
$$;

-- ══ 7) PŘEPOČET UZAVŘENÝCH AUTO-JÍZD NOVÝM PRAHEM ═══════════════════
-- Jen statistiky z uložené stopy; is_recording/ended_at se nemění, nic se
-- nemaže (vyšší práh stání kilometry jen PŘIDÁVÁ — dřívější „mezery" se
-- stanou stáním). Ručně poskládané jízdy se netýkají.
do $$
declare v_r record; v_st jsonb; v_km numeric; v_move int; v_idle int; v_gap int;
        v_dur int; v_active int; v_avg numeric; v_n int := 0;
begin
  for v_r in select * from user_rides where source = 'auto' and not is_recording loop
    v_st := _ride_stats(coalesce(v_r.track, '[]'::jsonb));
    v_km := (v_st->>'dist_km')::numeric;
    if v_km < 1.0 then continue; end if;   -- stará prořídlá data: nesahat
    v_move := (v_st->>'moving_sec')::int; v_idle := (v_st->>'idle_sec')::int;
    v_gap := (v_st->>'gap_sec')::int;
    v_dur := greatest(1, coalesce(v_r.duration_min, 0), ceil((v_move + v_idle + v_gap)::numeric / 60)::int);
    if v_move + v_idle + v_gap < v_dur * 60 then v_idle := v_dur * 60 - v_move - v_gap; end if;
    if v_idle < 0 then v_idle := 0; end if;
    v_active := greatest(v_dur * 60 - v_gap, 60);
    v_avg := nullif(least(case when v_move > 0 then round((v_km / (v_move::numeric / 3600)), 1)
                               else round((v_km / (v_active::numeric / 3600)), 1) end, 200.1), 200.1);
    update user_rides set
      distance_km = greatest(distance_km, v_km),
      duration_min = v_dur, moving_sec = v_move, idle_sec = v_idle, gap_sec = v_gap,
      avg_speed_kmh = v_avg,
      max_speed_kmh = nullif(greatest(coalesce(max_speed_kmh, 0), coalesce((v_st->>'max_kmh')::numeric, 0), coalesce(v_avg, 0)), 0)
    where id = v_r.id;
    v_n := v_n + 1;
  end loop;
  raise notice 'user_rides: přepočítáno novým prahem stání %', v_n;
end $$;
