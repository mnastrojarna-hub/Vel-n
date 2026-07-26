-- ============================================================================
-- Trasy v appce: tab se otevíral ~20 s a RPC padaly na statement timeout
-- ----------------------------------------------------------------------------
-- Zjištěno měřením na živé DB (2026-07-25):
--   * get_branch_routes i get_pois_catalog vrací HTTP 500 „57014 canceling
--     statement due to statement timeout" — skládají obří jsonb: plný payload
--     tras + POI má ~59 MB (překlady popisů/okolí do ~10 jazyků u 8 456
--     route_pois + 1 174 tras), get_pois_catalog per-row rozbaluje velké
--     translations 37 220 katalogových bodů.
--   * Appka po pádu RPC jela fallback přímým selectem (59 MB) → dlouhé
--     stahování a parsování na telefonu.
-- Řešení (UX beze změny):
--   1) jsonb_name_translations() — extrakce {lang:{name}} z translations.
--   2) points_of_interest.translations_names — malý GENERATED sloupec, ať
--      katalog nečte/nerozbaluje velké translations (příčina timeoutu).
--   3) get_pois_catalog — čte translations_names (jinak beze změny výstupu).
--   4) get_branch_routes_lite() — odlehčený SEZNAM tras pro appku (bez popisů,
--      geometry, galerií a překladů popisů; jen názvy ve všech jazycích).
--   5) get_route_detail(uuid) + get_route_poi_detail(uuid) — plný detail jedné
--      trasy / jednoho bodu, dotahuje se až při otevření detailu.
--   6) Indexy pro agregace hodnocení/recenzí.
-- Původní get_branch_routes zůstává beze změny (starší verze appky mají
-- fallback na přímý select). Velín čte tabulky přímo — netýká se ho to.
-- ============================================================================

-- 1) Extrakce názvů z translations (IMMUTABLE kvůli generated sloupci)
create or replace function public.jsonb_name_translations(t jsonb)
returns jsonb language sql immutable as $$
  select coalesce(
           jsonb_object_agg(e.k, jsonb_build_object('name', e.v->'name')),
           '{}'::jsonb)
  from jsonb_each(case when jsonb_typeof(t) = 'object'
                       then t else '{}'::jsonb end) as e(k, v)
  where jsonb_typeof(e.v) = 'object' and e.v ? 'name';
$$;

-- 2) Malý sloupec s názvy překladů (samoúdržba — přepočítá se při UPDATE
--    translations, např. překladovými crony). Jednorázový rewrite tabulky.
alter table public.points_of_interest
  add column if not exists translations_names jsonb
  generated always as (public.jsonb_name_translations(translations)) stored;

-- 3) Katalog POI — stejný výstup jako dřív, ale bez rozbalování velkých
--    translations (jen hotový translations_names) → žádný timeout.
create or replace function public.get_pois_catalog()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'translations', coalesce(p.translations_names, '{}'::jsonb),
    'lat', p.lat, 'lng', p.lng,
    'image_url', coalesce(p.image_url, p.images[1]),
    'category', p.category,
    'country', p.country,
    'is_catalog', true,
    'avg_rating', r.avg_rating,
    'rating_count', coalesce(r.rating_count, 0)
  )), '[]'::jsonb)
  from public.points_of_interest p
  left join (
    select poi_id,
           round(avg(rating)::numeric, 1) as avg_rating,
           count(*)                        as rating_count
    from public.poi_ratings
    where poi_id is not null
    group by poi_id
  ) r on r.poi_id = p.id
  where p.is_active = true;
$$;
grant execute on function public.get_pois_catalog() to anon, authenticated;

-- 4) Odlehčený seznam tras pro appku: ~59 MB → jednotky MB. Bez description,
--    geometry, images[] a překladů popisů; POI jen id/název/GPS/foto/hodnocení.
--    Hodnocení předagregovaná JOINem (žádné korelované poddotazy).
create or replace function public.get_branch_routes_lite()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(t.j order by t.sort_order, t.distance_km nulls last),
                  '[]'::jsonb)
  from (
    select r.sort_order, r.distance_km,
      jsonb_build_object(
        'id', r.id,
        'branch_id', r.branch_id,
        'name', r.name,
        'route_type', r.route_type,
        'distance_km', r.distance_km,
        'duration_min', r.duration_min,
        'difficulty', r.difficulty,
        'waypoints', r.waypoints,
        'mapy_url', r.mapy_url,
        'cover_image', coalesce(r.cover_image, r.images[1]),
        'countries', to_jsonb(r.countries),
        'translations', public.jsonb_name_translations(r.translations),
        'review_avg', rv.avg_rating,
        'review_count', coalesce(rv.review_count, 0),
        'pois', coalesce(ps.pois, '[]'::jsonb)
      ) as j
    from public.routes r
    left join (
      select route_id,
             round(avg(rating)::numeric, 1) as avg_rating,
             count(*)                        as review_count
      from public.route_reviews
      where status = 'approved'
      group by route_id
    ) rv on rv.route_id = r.id
    left join (
      select p.route_id,
             jsonb_agg(jsonb_build_object(
               'id', p.id,
               'name', p.name,
               'lat', p.lat, 'lng', p.lng,
               'image_url', coalesce(p.image_url, p.images[1]),
               'translations', public.jsonb_name_translations(p.translations),
               'avg_rating', pr.avg_rating,
               'rating_count', coalesce(pr.rating_count, 0)
             ) order by p.sort_order) as pois
      from public.route_pois p
      left join (
        select route_poi_id,
               round(avg(rating)::numeric, 1) as avg_rating,
               count(*)                        as rating_count
        from public.poi_ratings
        where route_poi_id is not null
        group by route_poi_id
      ) pr on pr.route_poi_id = p.id
      group by p.route_id
    ) ps on ps.route_id = r.id
    where r.is_active = true and r.status = 'approved'
  ) t;
$$;
grant execute on function public.get_branch_routes_lite() to anon, authenticated;

-- 5a) Plný detail JEDNÉ trasy (stejný tvar jako prvek get_branch_routes) —
--     dotahuje appka při otevření detailu trasy.
create or replace function public.get_route_detail(p_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((
    select to_jsonb(r) || jsonb_build_object(
      'review_avg',   (select round(avg(rating)::numeric, 1)
                         from public.route_reviews rr
                        where rr.route_id = r.id and rr.status = 'approved'),
      'review_count', (select count(*)
                         from public.route_reviews rr
                        where rr.route_id = r.id and rr.status = 'approved'),
      'pois', coalesce((
        select jsonb_agg(to_jsonb(p) || jsonb_build_object(
                 'avg_rating',   (select round(avg(rating)::numeric, 1)
                                    from public.poi_ratings pr
                                   where pr.route_poi_id = p.id),
                 'rating_count', (select count(*)
                                    from public.poi_ratings pr
                                   where pr.route_poi_id = p.id)
               ) order by p.sort_order)
        from public.route_pois p where p.route_id = r.id), '[]'::jsonb)
    )
    from public.routes r
    where r.id = p_id and r.is_active = true and r.status = 'approved'
  ), 'null'::jsonb);
$$;
grant execute on function public.get_route_detail(uuid) to anon, authenticated;

-- 5b) Plný detail JEDNOHO trasového bodu (popis, okolí, galerie, překlady) —
--     dotahuje appka při otevření bodu z odlehčeného seznamu.
create or replace function public.get_route_poi_detail(p_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((
    select to_jsonb(p) || jsonb_build_object(
      'avg_rating',   (select round(avg(rating)::numeric, 1)
                         from public.poi_ratings pr where pr.route_poi_id = p.id),
      'rating_count', (select count(*)
                         from public.poi_ratings pr where pr.route_poi_id = p.id)
    )
    from public.route_pois p
    join public.routes r on r.id = p.route_id
    where p.id = p_id and r.is_active = true
  ), 'null'::jsonb);
$$;
grant execute on function public.get_route_poi_detail(uuid) to anon, authenticated;

-- 6) Indexy pro agregace hodnocení/recenzí (idempotentní)
create index if not exists idx_poi_ratings_route_poi on public.poi_ratings(route_poi_id);
create index if not exists idx_poi_ratings_poi       on public.poi_ratings(poi_id);
create index if not exists idx_poi_ratings_user_poi  on public.poi_ratings(user_poi_id);
create index if not exists idx_route_reviews_route   on public.route_reviews(route_id);
