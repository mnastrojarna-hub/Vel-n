-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Recenze tras (hvězdičkové hodnocení + textová recenze + foto).
-- Každý přihlášený uživatel může jednu trasu ohodnotit (1 recenze / trasa /
-- uživatel, lze měnit). Recenze jsou viditelné hned; admin ve Velíně může
-- nevhodnou recenzi skrýt (status='hidden') nebo smazat.
-- ════════════════════════════════════════════════════════════════════

create table if not exists public.route_reviews (
  id          uuid primary key default gen_random_uuid(),
  route_id    uuid not null references public.routes(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  rating      int not null check (rating between 1 and 5),
  review_text text,
  photos      text[] not null default '{}',
  status      text not null default 'approved'
              check (status in ('approved','hidden')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint route_reviews_uniq unique (user_id, route_id)
);
create index if not exists idx_route_reviews_route on public.route_reviews(route_id);
create index if not exists idx_route_reviews_status on public.route_reviews(status);

alter table public.route_reviews enable row level security;

-- Veřejně viditelné jen schválené (admin + vlastník vidí i skryté vlastní).
drop policy if exists route_reviews_public_read on public.route_reviews;
create policy route_reviews_public_read on public.route_reviews
  for select to anon, authenticated
  using (status = 'approved' or user_id = auth.uid() or is_admin());

-- Vlastník smí vložit/upravit/smazat svou recenzi.
drop policy if exists route_reviews_owner_write on public.route_reviews;
create policy route_reviews_owner_write on public.route_reviews
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Admin smí vše (skrýt/smazat nevhodné).
drop policy if exists route_reviews_admin_all on public.route_reviews;
create policy route_reviews_admin_all on public.route_reviews
  for all to authenticated using (is_admin()) with check (is_admin());

drop trigger if exists trg_route_reviews_updated on public.route_reviews;
create trigger trg_route_reviews_updated before update on public.route_reviews
  for each row execute function public.set_updated_at();

grant select, insert, update, delete on public.route_reviews to authenticated;
grant select on public.route_reviews to anon;

-- ── RPC: vlož/uprav recenzi (upsert, max 1 na uživatele a trasu) ────────────
create or replace function public.submit_route_review(
  p_route_id uuid, p_rating int, p_review_text text default null,
  p_photos text[] default '{}')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  if p_rating < 1 or p_rating > 5 then raise exception 'rating must be 1..5'; end if;
  insert into route_reviews(user_id, route_id, rating, review_text, photos)
  values (auth.uid(), p_route_id, p_rating,
          nullif(btrim(coalesce(p_review_text,'')),''),
          coalesce(p_photos, '{}'))
  on conflict (user_id, route_id) do update
    set rating = excluded.rating,
        review_text = excluded.review_text,
        photos = excluded.photos,
        status = 'approved',
        updated_at = now()
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on function public.submit_route_review(uuid, int, text, text[]) to authenticated;

-- ── RPC: smaž vlastní recenzi ──────────────────────────────────────────────
create or replace function public.delete_route_review(p_route_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  delete from route_reviews where user_id = auth.uid() and route_id = p_route_id;
end;
$$;
grant execute on function public.delete_route_review(uuid) to authenticated;

-- ── RPC: recenze trasy (seznam + moje recenze) ─────────────────────────────
-- Vrací jsonb { avg, count, my: {...}|null, reviews: [{...}] }. Jméno recenzenta
-- z profiles.loyalty_nickname → full_name → „Motorkář".
create or replace function public.get_route_reviews(p_route_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with vis as (
    select r.* from route_reviews r
    where r.route_id = p_route_id
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
        'id', v.id,
        'rating', v.rating,
        'review_text', v.review_text,
        'photos', v.photos,
        'status', v.status,
        'is_mine', (v.user_id = auth.uid()),
        'author', coalesce(nullif(btrim(p.loyalty_nickname),''),
                           nullif(btrim(p.full_name),''), 'Motorkář'),
        'created_at', v.created_at
      ) order by (v.user_id = auth.uid()) desc, v.created_at desc)
      from vis v left join profiles p on p.id = v.user_id
    ), '[]'::jsonb)
  );
$$;
grant execute on function public.get_route_reviews(uuid) to anon, authenticated;

-- ── get_branch_routes: doplň průměr + počet recenzí trasy ──────────────────
create or replace function public.get_branch_routes(p_branch_id uuid default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(t order by t.sort_order, t.distance_km nulls last), '[]'::jsonb)
  from (
    select r.*,
      (select round(avg(rating)::numeric,1) from public.route_reviews rr
         where rr.route_id = r.id and rr.status='approved') as review_avg,
      (select count(*) from public.route_reviews rr
         where rr.route_id = r.id and rr.status='approved') as review_count,
      coalesce(
        (select jsonb_agg(
           to_jsonb(p) || jsonb_build_object(
             'avg_rating',   (select round(avg(rating)::numeric,1) from public.poi_ratings pr where pr.route_poi_id = p.id),
             'rating_count', (select count(*) from public.poi_ratings pr where pr.route_poi_id = p.id)
           ) order by p.sort_order)
         from public.route_pois p where p.route_id = r.id),
        '[]'::jsonb
      ) as pois
    from public.routes r
    where r.is_active = true and r.status = 'approved'
      and (p_branch_id is null or r.branch_id = p_branch_id)
  ) t;
$$;
grant execute on function public.get_branch_routes(uuid) to anon, authenticated;

-- ── STORAGE: foto recenzí → bucket `media` pod prefixem `route-reviews/` ────
drop policy if exists media_route_review_upload on storage.objects;
create policy media_route_review_upload on storage.objects
  for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = 'route-reviews');
