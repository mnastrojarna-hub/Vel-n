-- MotoGo24 — katalog míst: sloučení duplicit + nástroje pro Velín
-- ---------------------------------------------------------------------------
-- Zadání uživatele (2026-09-20): „v motogo app jsou duplicitní místa jak
-- v mapě tak v seznamu klidně 3x". Příklad z jeho screenshotu (Křemešník):
--   points_of_interest 'Křemešník' 49.4039/15.3278   (Wikidata, cs-batch7)
--   points_of_interest 'Pípalka'   49.40361/15.32704 (Wikidata, cs-batch10) — 64 m
--   route_pois         'Rozhledna Pípalka na Křemešníku' 49.4035/15.32711
-- Jedna rozhledna na jednom vrcholu = tři řádky v seznamu i tři špendlíky
-- na mapě. Vzniklo to tím, že každá seed dávka kontrolovala duplicity JEN
-- proti stavu katalogu PŘED svým vlastním insertem, a navíc přes
-- `p.country = v.country` — což u řádku s country IS NULL vyjde NULL, takže
-- kontrola nezabrala vůbec.
--
-- Tahle migrace:
--   1) `poi_norm_name()` — normalizace názvu (bez diakritiky, bez vedoucího
--      druhového slova), stejná logika jako `_placeName` v appce,
--   2) JEDNORÁZOVÉ sloučení jistých duplicit: shodný normalizovaný název
--      do ~250 m. Vítěz si vezme, co mu chybí (fotka, popis, okolí, galerie,
--      překlady), hodnocení a „navštíveno" se přepojí a poražený se
--      DEAKTIVUJE (ne smaže — mazání by přes ON DELETE CASCADE zahodilo
--      hodnocení zákazníků),
--   3) RPC `admin_poi_duplicate_groups()` / `admin_poi_merge()` — Velín nad
--      nimi má záložku „Duplicity", aby šly dořešit i případy s různým
--      názvem (Křemešník × Pípalka) ručně a bezpečně.
-- Idempotentní: po sloučení už nejsou obě strany dvojice aktivní, takže
-- druhý běh nenajde nic.

create index if not exists idx_poi_catalog_lat on public.points_of_interest(lat);

-- 1) Normalizace názvu -------------------------------------------------------
create or replace function public.poi_norm_name(txt text)
returns text language sql immutable parallel safe as $fn$
  select nullif(
    btrim(
      regexp_replace(
        regexp_replace(
          -- vedoucí druhové slovo pryč: „Zřícenina hradu Kumburk" → „kumburk"
          regexp_replace(
            -- POZOR: obě tabulky MUSÍ být stejně dlouhé. První verze měla
            -- o jedno „s" navíc, takže se od indexu 35 všechno posunulo
            -- a „Krkonošský" se normalizovalo na „krkonossku" („ý"→„u",
            -- „ť"→„s", „ú"→„t", „ž"→„y"). Stejná tabulka je v appce
            -- (places_filter.dart, _foldName).
            lower(translate(coalesce(txt, ''),
              'áäàâãåąăčćçďđéěèêëęėēíìîïīľĺłňñńóöòôõøőřŕšśşșťțúůüûűùūýÿžźż',
              'aaaaaaaacccddeeeeeeeeiiiiilllnnnooooooorrssssttuuuuuuuyyzzz')),
            '^(zricenina hradu |zricenina |zamek |zamecek |hrad |klaster |kostel |kaple |rozhledna |vyhlidka |vez |vrch |hora |kopec |prehrada |rybnik |jezero |vodopad |jeskyne |studanka |pramen |muzeum |burgruine |schloss |burg |chateau |castle |ruine |tower )',
            ''),
          '[^a-z0-9]+', ' ', 'g'),
        ' +', ' ', 'g')
    ), '');
$fn$;
comment on function public.poi_norm_name(text) is
  'Normalizovaný název místa pro hledání duplicit (bez diakritiky, interpunkce a vedoucího druhového slova). Stejná logika jako _placeName v appce (places_filter.dart). POZOR: mění-li se tělo funkce, je nutné přepočítat generovaný sloupec points_of_interest.norm_name (uložené hodnoty se samy neaktualizují).';

-- Uložený generovaný sloupec — bez něj se regulární výrazy počítaly pro KAŽDOU
-- kandidátní dvojici znovu a hledání duplicit nad 40 tis. body trvalo 50 s
-- (PostgREST by ho utnul na statement_timeout). Se sloupcem je to prosté
-- porovnání dvou textů.
alter table public.points_of_interest
  add column if not exists norm_name text
  generated always as (public.poi_norm_name(name)) stored;
create index if not exists idx_poi_catalog_norm_name
  on public.points_of_interest(norm_name);

-- 2) Jednorázové sloučení jistých duplicit -----------------------------------
do $do$
declare
  r      record;
  merged int := 0;
begin
  for r in
    -- Ke každému poraženému právě JEDEN — ten NEJLEPŠÍ — vítěz. Rozsahové
    -- podmínky `b.lat between …` jsou schválně psané takhle (ne přes abs()),
    -- aby je nested loop uměl vzít z indexu idx_poi_catalog_lat; přes abs()
    -- by to byl seq scan 40k × 40k.
    select distinct on (b.id)
           b.id as drop_id, a.id as keep_id
      from public.points_of_interest a
      join public.points_of_interest b
        on b.id <> a.id
       and b.lat between a.lat - 0.00225 and a.lat + 0.00225       -- ~250 m
       and b.lng between a.lng - 0.00225 / greatest(cos(radians(a.lat)), 0.2)
                     and a.lng + 0.00225 / greatest(cos(radians(a.lat)), 0.2)
       and b.is_active
       and b.norm_name = a.norm_name
     where a.is_active
       and a.norm_name is not null
       -- vítěz musí být OSTŘE lepší: má fotku > má popis > nižší sort_order > menší id.
       -- Pořadí je úplné (id je unikátní), takže z každé dvojice je vítězem
       -- právě jeden — nikdy se nesloučí „oba do sebe".
       and case
             when (a.image_url is not null) <> (b.image_url is not null)
               then (a.image_url is not null)
             when (a.description is not null) <> (b.description is not null)
               then (a.description is not null)
             when a.sort_order <> b.sort_order then a.sort_order < b.sort_order
             else a.id < b.id
           end
     order by b.id,
              (a.image_url is not null) desc,
              (a.description is not null) desc,
              a.sort_order, a.id
  loop
    -- poražený mohl být mezitím sám sloučen jako vítěz jiné dvojice → přeskoč
    continue when not exists (select 1 from public.points_of_interest
                               where id = r.keep_id and is_active);
    continue when not exists (select 1 from public.points_of_interest
                               where id = r.drop_id and is_active);

    update public.points_of_interest k set
      image_url    = coalesce(k.image_url, d.image_url),
      description  = coalesce(k.description, d.description),
      surroundings = coalesce(k.surroundings, d.surroundings),
      country      = coalesce(k.country, d.country),
      region       = coalesce(k.region, d.region),
      images       = case when coalesce(array_length(k.images, 1), 0) = 0
                          then d.images else k.images end,
      image_alts   = case when coalesce(array_length(k.image_alts, 1), 0) = 0
                          then d.image_alts else k.image_alts end,
      translations = coalesce(k.translations, '{}'::jsonb) || coalesce(d.translations, '{}'::jsonb),
      updated_at   = now()
      from public.points_of_interest d
     where k.id = r.keep_id and d.id = r.drop_id;

    -- hodnocení a „navštíveno" přenést tam, kde to neporuší UNIQUE(user, poi)
    update public.poi_ratings x set poi_id = r.keep_id
     where x.poi_id = r.drop_id
       and not exists (select 1 from public.poi_ratings y
                        where y.user_id = x.user_id and y.poi_id = r.keep_id);
    delete from public.poi_ratings where poi_id = r.drop_id;

    update public.user_visited_places x set poi_id = r.keep_id
     where x.poi_id = r.drop_id
       and not exists (select 1 from public.user_visited_places y
                        where y.user_id = x.user_id and y.poi_id = r.keep_id);
    delete from public.user_visited_places where poi_id = r.drop_id;

    update public.points_of_interest
       set is_active  = false,
           source     = coalesce(source, '') || ' merged-into:' || r.keep_id,
           updated_at = now()
     where id = r.drop_id;
    merged := merged + 1;
  end loop;
  raise notice 'poi dedupe: slouceno % duplicitnich mist', merged;
end $do$;

-- 3) Nástroje pro Velín ------------------------------------------------------
-- Skupiny podezřelých duplicit: aktivní body do `p_radius_m` metrů od sebe,
-- u kterých je buď shodný normalizovaný název, nebo shodná kategorie.
-- (Křemešník × Pípalka: 64 m, oba `lookout`, jiný název → chytne pravidlo
--  na kategorii a admin rozhodne, co je vítěz.)
-- Pozn. k výkonu: nad 40 tis. body trvá průchod všemi zeměmi ~7 s, jedna země
-- ~2 s. Supabase má pro roli `authenticated` statement_timeout 8 s, proto si
-- funkce zvedá limit sama (platí jen po dobu jejího běhu) a Velín standardně
-- posílá konkrétní zemi.
create or replace function public.admin_poi_duplicate_groups(
  p_radius_m int default 150,
  p_country  text default 'CZ',
  p_limit    int default 200
) returns jsonb language plpgsql stable security definer
  set search_path = public
  set statement_timeout to '55s' as $fn$
declare
  res jsonb;
  d   double precision := greatest(p_radius_m, 10) / 111320.0;
begin
  if not is_admin() then
    raise exception 'Jen pro administrátory';
  end if;
  with pairs as (
    select a.id as a_id, b.id as b_id,
           round((111320.0 * sqrt(
             power(a.lat - b.lat, 2) +
             power((a.lng - b.lng) * cos(radians((a.lat + b.lat) / 2)), 2)))::numeric, 0) as m
      from public.points_of_interest a
      join public.points_of_interest b
        on b.id > a.id
       -- rozsahové podmínky (ne abs()) kvůli indexu idx_poi_catalog_lat
       and b.lat between a.lat - d and a.lat + d
       and b.lng between a.lng - d / greatest(cos(radians(a.lat)), 0.2)
                     and a.lng + d / greatest(cos(radians(a.lat)), 0.2)
       and b.is_active
       and (b.norm_name = a.norm_name or b.category = a.category)
     where a.is_active
       and (p_country is null or a.country = p_country)
  ), lim as (
    select * from pairs where m <= p_radius_m order by m limit greatest(p_limit, 1)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'distance_m', l.m,
           'a', to_jsonb(pa) - 'translations' - 'images' - 'image_alts' - 'norm_name',
           'b', to_jsonb(pb) - 'translations' - 'images' - 'image_alts' - 'norm_name')
         order by l.m), '[]'::jsonb)
    into res
    from lim l
    join public.points_of_interest pa on pa.id = l.a_id
    join public.points_of_interest pb on pb.id = l.b_id;
  return res;
end $fn$;
grant execute on function public.admin_poi_duplicate_groups(int, text, int) to authenticated;

-- Sloučení dvou míst z Velína: vítěz si vezme, co mu chybí; hodnocení
-- a „navštíveno" se přepojí; poražený se deaktivuje (nikdy nemaže).
create or replace function public.admin_poi_merge(p_keep uuid, p_drop uuid)
returns jsonb language plpgsql security definer set search_path = public as $fn$
begin
  if not is_admin() then
    raise exception 'Jen pro administrátory';
  end if;
  if p_keep = p_drop then
    raise exception 'Vítěz a poražený nemohou být tentýž bod';
  end if;
  -- Seznam duplicit ve Velíně je jen snímek; mezitím mohl někdo (nebo druhá
  -- záložka) jednu stranu sloučit jinam. Bez téhle kontroly by šlo sloučit
  -- do už SKRYTÉHO bodu a místo by z appky zmizelo úplně.
  if not exists (select 1 from public.points_of_interest
                  where id = p_keep and is_active) then
    raise exception 'Ponechávaný bod už není aktivní — obnov seznam duplicit';
  end if;
  if not exists (select 1 from public.points_of_interest
                  where id = p_drop and is_active) then
    return jsonb_build_object('ok', true, 'keep', p_keep, 'dropped', p_drop,
                              'noop', true);
  end if;

  update public.points_of_interest k set
    image_url    = coalesce(k.image_url, d.image_url),
    description  = coalesce(k.description, d.description),
    surroundings = coalesce(k.surroundings, d.surroundings),
    country      = coalesce(k.country, d.country),
    region       = coalesce(k.region, d.region),
    images       = case when coalesce(array_length(k.images, 1), 0) = 0
                        then d.images else k.images end,
    image_alts   = case when coalesce(array_length(k.image_alts, 1), 0) = 0
                        then d.image_alts else k.image_alts end,
    translations = coalesce(k.translations, '{}'::jsonb) || coalesce(d.translations, '{}'::jsonb),
    updated_at   = now()
    from public.points_of_interest d
   where k.id = p_keep and d.id = p_drop;

  update public.poi_ratings x set poi_id = p_keep
   where x.poi_id = p_drop
     and not exists (select 1 from public.poi_ratings y
                      where y.user_id = x.user_id and y.poi_id = p_keep);
  delete from public.poi_ratings where poi_id = p_drop;

  update public.user_visited_places x set poi_id = p_keep
   where x.poi_id = p_drop
     and not exists (select 1 from public.user_visited_places y
                      where y.user_id = x.user_id and y.poi_id = p_keep);
  delete from public.user_visited_places where poi_id = p_drop;

  update public.points_of_interest
     set is_active  = false,
         source     = coalesce(source, '') || ' merged-into:' || p_keep,
         updated_at = now()
   where id = p_drop;

  return jsonb_build_object('ok', true, 'keep', p_keep, 'dropped', p_drop);
end $fn$;
grant execute on function public.admin_poi_merge(uuid, uuid) to authenticated;
