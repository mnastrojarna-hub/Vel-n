-- MotoGo24 — katalog míst: jednorázové sloučení jistých duplicit
-- ---------------------------------------------------------------------------
-- Běží AŽ TADY, za seed dávkami h–l. Soubory se aplikují v bytovém pořadí
-- názvu (e < f < g < h < i < j < k < l < m), a kdyby se slučovalo už v `f`,
-- proběhlo by to PŘED vložením nových míst — nově vložené dvojice by zůstaly
-- nesloučené (změřeno: 32 čerstvých dvojic se stejným normalizovaným názvem
-- do 600 m od staršího bodu).
--
-- Co se slučuje: AKTIVNÍ body se SHODNÝM normalizovaným názvem (`norm_name`,
-- viz `20260920f`), do 250 m skutečné vzdálenosti a ve STEJNÉ kategorii.
-- Kategorie je podmínka, ne detail: bez ní se „rozhledna Velký Blaník"
-- (lookout) slila do „Velký Blaník" (přírodní rezervace, nature) a rozhledna
-- z chipu „Rozhledny a vrcholy" zmizela — přesný opak toho, co je potřeba.
--
-- Vítěz: má fotku > má popis > nižší sort_order > menší id. Vezme si, co mu
-- chybí (fotka, popis, okolí, galerie, překlady), hodnocení a „navštíveno" se
-- přepojí a poražený se DEAKTIVUJE — nikdy nemaže, protože `poi_ratings`
-- i `user_visited_places` na něj visí přes FK s ON DELETE CASCADE a smazání
-- by zahodilo recenze a fotky zákazníků.
--
-- Průchod se opakuje, dokud něco slučuje: u řetězce A–B–C (A nejlepší) se
-- v prvním kole sloučí B do A, ale C mělo jako jediného kandidáta B, které
-- je mezitím skryté — druhé kolo ho doslučuje. Díky tomu je migrace zároveň
-- IDEMPOTENTNÍ (druhé spuštění celé migrace nenajde už nic).

do $do$
declare
  r       record;
  merged  int;
  total   int := 0;
  rounds  int := 0;
begin
  loop
    merged := 0;
    rounds := rounds + 1;
    for r in
      -- Ke každému poraženému právě JEDEN — ten NEJLEPŠÍ — vítěz. Rozsahové
      -- podmínky `b.lat between …` jsou schválně psané takhle (ne přes abs()),
      -- aby je nested loop uměl vzít z indexu; přes abs() by to byl seq scan.
      select distinct on (b.id)
             b.id as drop_id, a.id as keep_id
        from public.points_of_interest a
        join public.points_of_interest b
          on b.lat between a.lat - 0.00225 and a.lat + 0.00225
         and b.lng between a.lng - 0.00225 / greatest(cos(radians(a.lat)), 0.2)
                       and a.lng + 0.00225 / greatest(cos(radians(a.lat)), 0.2)
         and b.is_active
       where a.is_active
         and b.id <> a.id
         and b.norm_name = a.norm_name
         and a.norm_name is not null
         and b.category = a.category
         -- Okno výš je ČTVEREC, takže v rozích sahá až na 354 m; skutečná
         -- vzdálenost musí být do 250 m.
         and 111320.0 * sqrt(power(a.lat - b.lat, 2)
               + power((a.lng - b.lng) * cos(radians(a.lat)), 2)) <= 250
         -- vítěz musí být OSTŘE lepší; pořadí je úplné (id je unikátní),
         -- takže z každé dvojice je vítězem právě jeden
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
      -- vítěz i poražený mohli být mezitím sloučeni jinam → přeskoč
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
        wikidata_id  = coalesce(k.wikidata_id, d.wikidata_id),
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
    total := total + merged;
    exit when merged = 0 or rounds >= 10;
  end loop;
  raise notice 'poi dedupe: slouceno % duplicitnich mist v % kolech', total, rounds;
end $do$;
