-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Recenze/komentáře k BODŮM ZÁJMU + popis okolí (surroundings)
--
-- 1) Body zájmu (route_pois / user_pois / katalogové points_of_interest)
--    dostávají textové recenze viditelné VŠEM uživatelům — stejně jako
--    trasy (route_reviews). Recenze = jedna řádka poi_ratings (hvězdy +
--    text + fotky), max 1 na uživatele a bod, lze měnit. Admin ve Velíně
--    může nevhodnou skrýt (status='hidden') nebo smazat.
-- 2) Nový sloupec `surroundings` (popis okolí / zajímavosti v místě) u
--    points_of_interest i route_pois; překlady v `translations->lang->>'surroundings'`
--    (plní edge fn backfill-poi-surroundings, viz 20260707_poi_surroundings_cron.sql).
-- Idempotentní.
-- ════════════════════════════════════════════════════════════════════

-- ── 1) poi_ratings → recenze (text + fotky + moderační status) ──────────────
alter table public.poi_ratings
  add column if not exists review_text text,
  add column if not exists photos      text[] not null default '{}',
  add column if not exists status      text   not null default 'approved'
                                        check (status in ('approved','hidden'));
create index if not exists idx_poi_ratings_status on public.poi_ratings(status);

-- Veřejně viditelné jen schválené (skryté vidí jen vlastník + admin).
-- Hvězdy zůstávají veřejné (star-only řádky mají status='approved' default).
drop policy if exists poi_ratings_public_read on public.poi_ratings;
create policy poi_ratings_public_read on public.poi_ratings
  for select to anon, authenticated
  using (status = 'approved' or user_id = auth.uid() or is_admin());

-- Admin smí vše (skrýt/smazat nevhodné komentáře).
drop policy if exists poi_ratings_admin_all on public.poi_ratings;
create policy poi_ratings_admin_all on public.poi_ratings
  for all to authenticated using (is_admin()) with check (is_admin());
-- (poi_ratings_owner_write zůstává z 20260629 — vlastník RW své řádky.)

grant select on public.poi_ratings to anon, authenticated;
grant insert, update, delete on public.poi_ratings to authenticated;

-- ── 2) RPC: vlož/uprav recenzi bodu (hvězdy + text + fotky) ─────────────────
-- Právě jeden cíl (route_poi / user_poi / katalog poi). Upsert = max 1/uživatel/bod.
create or replace function public.submit_poi_review(
  p_route_poi_id uuid default null,
  p_user_poi_id  uuid default null,
  p_poi_id       uuid default null,
  p_rating       int  default null,
  p_review_text  text default null,
  p_photos       text[] default '{}')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_text text; v_photos text[];
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  if num_nonnulls(p_route_poi_id, p_user_poi_id, p_poi_id) <> 1 then
    raise exception 'exactly one poi target required';
  end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'rating must be 1..5';
  end if;
  v_text   := nullif(btrim(coalesce(p_review_text,'')),'');
  v_photos := coalesce(p_photos, '{}');
  if p_route_poi_id is not null then
    insert into poi_ratings(user_id, route_poi_id, rating, review_text, photos)
    values (auth.uid(), p_route_poi_id, p_rating, v_text, v_photos)
    on conflict (user_id, route_poi_id) do update
      set rating=excluded.rating, review_text=excluded.review_text,
          photos=excluded.photos, status='approved', updated_at=now()
    returning id into v_id;
  elsif p_user_poi_id is not null then
    insert into poi_ratings(user_id, user_poi_id, rating, review_text, photos)
    values (auth.uid(), p_user_poi_id, p_rating, v_text, v_photos)
    on conflict (user_id, user_poi_id) do update
      set rating=excluded.rating, review_text=excluded.review_text,
          photos=excluded.photos, status='approved', updated_at=now()
    returning id into v_id;
  else
    insert into poi_ratings(user_id, poi_id, rating, review_text, photos)
    values (auth.uid(), p_poi_id, p_rating, v_text, v_photos)
    on conflict (user_id, poi_id) do update
      set rating=excluded.rating, review_text=excluded.review_text,
          photos=excluded.photos, status='approved', updated_at=now()
    returning id into v_id;
  end if;
  return v_id;
end;
$$;
grant execute on function public.submit_poi_review(uuid,uuid,uuid,int,text,text[]) to authenticated;

-- ── RPC: smaž vlastní recenzi bodu ─────────────────────────────────────────
create or replace function public.delete_poi_review(
  p_route_poi_id uuid default null,
  p_user_poi_id  uuid default null,
  p_poi_id       uuid default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  delete from poi_ratings where user_id = auth.uid()
    and route_poi_id is not distinct from p_route_poi_id
    and user_poi_id  is not distinct from p_user_poi_id
    and poi_id       is not distinct from p_poi_id;
end;
$$;
grant execute on function public.delete_poi_review(uuid,uuid,uuid) to authenticated;

-- ── RPC: recenze bodu (seznam + moje) — jako get_route_reviews ─────────────
-- Vrací { avg, count, my:{...}|null, reviews:[{...}] }. avg/count ze VŠECH
-- schválených hodnocení; reviews[] jen řádky S textem nebo fotkou (komentáře).
create or replace function public.get_poi_reviews(
  p_route_poi_id uuid default null,
  p_user_poi_id  uuid default null,
  p_poi_id       uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with vis as (
    select r.* from poi_ratings r
    where r.route_poi_id is not distinct from p_route_poi_id
      and r.user_poi_id  is not distinct from p_user_poi_id
      and r.poi_id       is not distinct from p_poi_id
      and (r.status = 'approved' or r.user_id = auth.uid() or is_admin())
  )
  select jsonb_build_object(
    'avg',   (select round(avg(rating)::numeric,1) from vis where status='approved'),
    'count', (select count(*) from vis where status='approved'),
    'my', (
      select to_jsonb(m) from (
        select rating, review_text, photos from vis where user_id = auth.uid() limit 1
      ) m
    ),
    'reviews', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'rating', v.rating, 'review_text', v.review_text, 'photos', v.photos,
        'status', v.status, 'is_mine', (v.user_id = auth.uid()),
        'author', coalesce(nullif(btrim(p.loyalty_nickname),''),
                           nullif(btrim(p.full_name),''), 'Motorkář'),
        'created_at', v.created_at
      ) order by (v.user_id = auth.uid()) desc, v.created_at desc)
      from vis v left join profiles p on p.id = v.user_id
      where v.review_text is not null or coalesce(array_length(v.photos,1),0) > 0
    ), '[]'::jsonb)
  );
$$;
grant execute on function public.get_poi_reviews(uuid,uuid,uuid) to anon, authenticated;

-- ── 3) Popis okolí (surroundings) u bodů ───────────────────────────────────
alter table public.points_of_interest add column if not exists surroundings text;
alter table public.route_pois         add column if not exists surroundings text;
-- Překlady jdou do stávajícího translations->lang->>'surroundings' (jsonb).

-- get_pois_catalog: doplň surroundings (route_pois surroundings jde přes
-- to_jsonb(p) v get_branch_routes automaticky — nový sloupec se přidá sám).
create or replace function public.get_pois_catalog()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'name', p.name, 'description', p.description,
    'surroundings', p.surroundings,
    'lat', p.lat, 'lng', p.lng,
    'image_url', p.image_url, 'images', to_jsonb(p.images),
    'translations', p.translations, 'category', p.category,
    'country', p.country, 'is_catalog', true,
    'avg_rating',   (select round(avg(rating)::numeric,1) from poi_ratings r where r.poi_id = p.id),
    'rating_count', (select count(*) from poi_ratings r where r.poi_id = p.id)
  ) order by p.sort_order, p.name), '[]'::jsonb)
  from public.points_of_interest p
  where p.is_active = true;
$$;
grant execute on function public.get_pois_catalog() to anon, authenticated;

-- ── 4) STORAGE: foto recenzí bodů → bucket `media` prefix `poi-reviews/` ────
drop policy if exists media_poi_review_upload on storage.objects;
create policy media_poi_review_upload on storage.objects
  for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = 'poi-reviews');
