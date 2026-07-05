-- ============================================================================
-- Odlehčení katalogu bodů zájmu pro appku (výkon prvního načtení)
-- ----------------------------------------------------------------------------
-- Appka volá get_pois_catalog() při otevření katalogu POI a načte VŠECHNY
-- aktivní katalogové body naráz (desítky tisíc). Původní RPC vracela u každého
-- bodu i dlouhý popis, popis okolí, celou galerii fotek a překlady popisů/okolí
-- do 7-8 jazyků → payload o velikosti jednotek MB, který se dlouho stahoval
-- a parsoval na telefonu.
--
-- Řešení (beze změny toho, co uživatel vidí):
--   1) get_pois_catalog() posílá do SEZNAMU jen lehká pole: id, název + NÁZVY
--      překladů (kvůli zobrazení a hledání ve všech jazycích), kategorie, GPS,
--      náhledovou fotku (image_url, případně první z galerie), zemi a hodnocení.
--      Popis, okolí, celá galerie a překlady popisů/okolí se do seznamu už
--      neposílají (v kartě seznamu se stejně nezobrazují).
--   2) Nové get_poi_detail(uuid) dotáhne PLNÝ detail jednoho bodu (popis, okolí,
--      galerie, kompletní překlady) — appka ho volá až při otevření detailu bodu.
--
-- get_pois_catalog používá jen mobilní appka; Velín čte tabulku points_of_interest
-- přímo, takže tato změna se ho netýká.
-- ============================================================================

-- 1) Odlehčený katalog pro seznam --------------------------------------------
create or replace function public.get_pois_catalog()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', p.name,
    -- Jen NÁZVY překladů (kvůli lokalizaci názvu v seznamu + hledání napříč
    -- jazyky). Popisy/okolí překladů se do seznamu neposílají — payload.
    'translations', (
      select coalesce(
               jsonb_object_agg(tr.k, jsonb_build_object('name', tr.v->'name')),
               '{}'::jsonb)
      from jsonb_each(
             case when jsonb_typeof(p.translations) = 'object'
                  then p.translations else '{}'::jsonb end
           ) as tr(k, v)
      where jsonb_typeof(tr.v) = 'object' and tr.v ? 'name'
    ),
    'lat', p.lat, 'lng', p.lng,
    -- Náhled: vlastní image_url, jinak první fotka z galerie (bez posílání
    -- celé galerie — ta se dotáhne až v detailu).
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

-- 2) Plný detail jednoho katalogového bodu (dotáhne appka při otevření detailu)
create or replace function public.get_poi_detail(p_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(
    (select jsonb_build_object(
      'id', p.id, 'name', p.name, 'description', p.description,
      'surroundings', p.surroundings,
      'lat', p.lat, 'lng', p.lng,
      'image_url', p.image_url, 'images', to_jsonb(p.images),
      'translations', p.translations, 'category', p.category,
      'country', p.country, 'is_catalog', true,
      'avg_rating',   (select round(avg(rating)::numeric, 1) from poi_ratings r where r.poi_id = p.id),
      'rating_count', (select count(*) from poi_ratings r where r.poi_id = p.id)
    )
    from public.points_of_interest p
    where p.id = p_id and p.is_active = true),
    'null'::jsonb
  );
$$;
grant execute on function public.get_poi_detail(uuid) to anon, authenticated;
