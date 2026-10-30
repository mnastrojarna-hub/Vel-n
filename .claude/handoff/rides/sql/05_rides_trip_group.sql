-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": slučování jízd do cest (7/8)
--   set_user_rides_trip(p_items) — NOVÉ RPC (bez DEFAULT, žádné přetížení):
--   hloupý zapisovač trip_id / trip_name pro VLASTNÍ jízdy volajícího.
--   p_items = [{id, trip_id|null, trip_name|null}, …] (1–300 položek).
--   Sloučení, rozdělení, přejmenování, vyjmutí i „Zpět" skládá appka;
--   jízdy, body, fotky ani statistiky se nemění (jen seskupení).
--   Cizí / neexistující id se tiše přeskočí → appka porovná `updated`.
-- Idempotentní (create or replace).
-- ════════════════════════════════════════════════════════════════════

create or replace function public.set_user_rides_trip(p_items jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_bad boolean; v_n int;
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
begin
  if v_uid is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  if jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 300 then
    return jsonb_build_object('success', false, 'error', 'bad_items');
  end if;
  select exists (
    select 1 from jsonb_array_elements(p_items) e
     where case
       when jsonb_typeof(e) <> 'object' then true
       when jsonb_typeof(e->'id') is distinct from 'string' then true
       when not ((e->>'id') ~* c_uuid) then true
       when coalesce(jsonb_typeof(e->'trip_id'), 'null') not in ('null', 'string') then true
       when jsonb_typeof(e->'trip_id') = 'string' and not ((e->>'trip_id') ~* c_uuid) then true
       when coalesce(jsonb_typeof(e->'trip_name'), 'null') not in ('null', 'string') then true
       else false end) into v_bad;
  if v_bad then return jsonb_build_object('success', false, 'error', 'bad_items'); end if;

  with items as (
    select distinct on ((e->>'id')::uuid) (e->>'id')::uuid as id,
           (e->>'trip_id')::uuid as trip_id,
           nullif(left(btrim(e->>'trip_name'), 120), '') as trip_name
      from jsonb_array_elements(p_items) with ordinality x(e, ord)
     order by (e->>'id')::uuid, x.ord desc),
  upd as (
    update user_rides r set trip_id = i.trip_id, trip_name = i.trip_name
      from items i
     where r.id = i.id and r.user_id = v_uid
    returning 1)
  select count(*) into v_n from upd;
  return jsonb_build_object('success', true, 'updated', v_n);
end;
$$;

comment on function public.set_user_rides_trip(jsonb) is
  'Appka: sloučení / rozdělení / přejmenování cesty = zápis trip_id a trip_name u vlastních jízd. [{id, trip_id, trip_name}] 1–300; vrací {success, updated}.';

revoke all on function public.set_user_rides_trip(jsonb) from public, anon;
grant execute on function public.set_user_rides_trip(jsonb) to authenticated, service_role;

notify pgrst, 'reload schema';
