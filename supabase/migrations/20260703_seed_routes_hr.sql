-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — SEED doporučených tras — CHORVATSKO (10 tras)
-- NEAPLIKOVÁNO na živou DB — přehled a spuštění je na adminovi.
-- Trasy: is_active=false (Skryto) + status='approved' → ve Velíně zkontroluj a Publikuj.
-- Idempotence: každá trasa se před vložením smaže dle (name, branch_id).
-- ════════════════════════════════════════════════════════════════════
alter table public.routes add column if not exists countries text[] not null default '{}'::text[];

do $$
declare
  v_branch uuid;
  v_route  uuid;
begin
  select id into v_branch from public.branches
    order by (power(coalesce(gps_lat,0)-49.3464,2) + power(coalesce(gps_lng,0)-15.2119,2)) asc
    limit 1;
  if v_branch is null then
    raise exception 'Nenalezena žádná pobočka v public.branches — nelze nasadit trasy.';
  end if;

  -- Chorvatské Zagorje a hrady
  delete from public.routes where name = 'Chorvatské Zagorje a hrady' and branch_id = v_branch;
  v_route := gen_random_uuid();
  insert into public.routes
    (id, branch_id, name, description, route_type, distance_km, duration_min, difficulty,
     waypoints, geometry, mapy_url, cover_image, images, image_alts, countries, is_active, sort_order, status)
  values (v_route, v_branch, 'Chorvatské Zagorje a hrady', 'Okruh zvlněným Chorvatským Zagorjem severně od Záhřebu, krajem pohádkových hradů a vinic. Trakošćan nad jezerem, Veliki Tabor a rodný dům Tita nabízí historii i pohodovou jízdu vinařskými kopci. Nejlepší od jara do podzimu; pozor na úzké silnice mezi vinicemi.', 'loop', 160, 210, 'easy',
     '[{"lat": 46.1622, "lng": 15.87, "label": "Start: Krapina"}, {"lat": 46.2606, "lng": 15.9436, "label": "Trakošćan"}, {"lat": 46.14, "lng": 15.66, "label": "Veliki Tabor"}, {"lat": 46.1622, "lng": 15.87, "label": "Cíl: Krapina"}]'::jsonb, null, 'https://www.google.com/maps/dir/?api=1&origin=46.1622,15.87&destination=46.1622,15.87&travelmode=driving&waypoints=46.2606,15.9436%7C46.14,15.66', 'https://commons.wikimedia.org/wiki/Special:FilePath/Trako%C5%A1%C4%87an.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Trako%C5%A1%C4%87an.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Veliki_Tabor.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Kumrovec.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Krapina_Neanderthal_Museum.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Marija_Bistrica.jpg"}'::text[], '{"Zámek Trakošćan","Hrad Veliki Tabor","Kumrovec","Krapina – muzeum neandertálců","Marija Bistrica"}'::text[], '{"HR"}'::text[], false, 4110, 'approved');
  insert into public.route_pois (route_id, name, description, lat, lng, image_url, images, sort_order) values
    (v_route, 'Zámek Trakošćan', 'Pohádkový bílý zámek zrcadlící se v jezeře obklopeném lesy, jeden z nejkrásnějších v Chorvatsku. Ikona Zagorje.', 46.2606, 15.9436, 'https://commons.wikimedia.org/wiki/Special:FilePath/Trako%C5%A1%C4%87an.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Trako%C5%A1%C4%87an.jpg"}'::text[], 0),
    (v_route, 'Hrad Veliki Tabor', 'Mohutný středověký hrad s věžemi na kopci nad vinicemi, opředený romantickou legendou. Dominanta kraje.', 46.1394, 15.66, 'https://commons.wikimedia.org/wiki/Special:FilePath/Veliki_Tabor.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Veliki_Tabor.jpg"}'::text[], 1),
    (v_route, 'Kumrovec', 'Skanzen a rodná vesnice Josipa Broze Tita s dochovanou lidovou architekturou. Cesta do minulosti.', 46.07, 15.68, 'https://commons.wikimedia.org/wiki/Special:FilePath/Kumrovec.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Kumrovec.jpg"}'::text[], 2),
    (v_route, 'Krapina – muzeum neandertálců', 'Moderní muzeum na místě nálezu pravěkých lidí, zabudované do svahu. Fascinující výlet do pravěku.', 46.1622, 15.87, 'https://commons.wikimedia.org/wiki/Special:FilePath/Krapina_Neanderthal_Museum.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Krapina_Neanderthal_Museum.jpg"}'::text[], 3),
    (v_route, 'Marija Bistrica', 'Nejvýznamnější poutní místo Chorvatska s bazilikou Černé Madony. Duchovní zastávka v kopcích.', 46.0, 16.11, 'https://commons.wikimedia.org/wiki/Special:FilePath/Marija_Bistrica.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Marija_Bistrica.jpg"}'::text[], 4);

  -- Papuk a Slavonie
  delete from public.routes where name = 'Papuk a Slavonie' and branch_id = v_branch;
  v_route := gen_random_uuid();
  insert into public.routes
    (id, branch_id, name, description, route_type, distance_km, duration_min, difficulty,
     waypoints, geometry, mapy_url, cover_image, images, image_alts, countries, is_active, sort_order, status)
  values (v_route, v_branch, 'Papuk a Slavonie', 'Okruh lesnatým pohořím Papuk uprostřed rovinaté Slavonie. Geopark, hrady a vinařské kopce Kutjeva nabízí zeleň a klid daleko od pobřežních davů. Nejlepší od jara do podzimu; pozor na lesní úseky a řidší zázemí.', 'loop', 190, 240, 'medium',
     '[{"lat": 45.3402, "lng": 17.6852, "label": "Start: Požega"}, {"lat": 45.4622, "lng": 17.66, "label": "Velika"}, {"lat": 45.4231, "lng": 17.88, "label": "Kutjevo"}, {"lat": 45.3402, "lng": 17.6852, "label": "Cíl: Požega"}]'::jsonb, null, 'https://www.google.com/maps/dir/?api=1&origin=45.3402,17.6852&destination=45.3402,17.6852&travelmode=driving&waypoints=45.4622,17.66%7C45.4231,17.88', 'https://commons.wikimedia.org/wiki/Special:FilePath/Papuk.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Papuk.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Po%C5%BEega.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Kutjevo.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Ru%C5%BEica_grad.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Jankovac.jpg"}'::text[], '{"Geopark Papuk","Požega","Kutjevo – vinařství","Zřícenina Ružica grad","Jezero Jankovac"}'::text[], '{"HR"}'::text[], false, 4120, 'approved');
  insert into public.route_pois (route_id, name, description, lat, lng, image_url, images, sort_order) values
    (v_route, 'Geopark Papuk', 'Zalesněné pohoří s geologickými zajímavostmi, hrady a horskými silnicemi, UNESCO geopark. Zelené srdce Slavonie.', 45.53, 17.68, 'https://commons.wikimedia.org/wiki/Special:FilePath/Papuk.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Papuk.jpg"}'::text[], 0),
    (v_route, 'Požega', 'Barokní město s pěkným náměstím uprostřed slavonské kotliny. Klidná výchozí zastávka.', 45.3402, 17.6852, 'https://commons.wikimedia.org/wiki/Special:FilePath/Po%C5%BEega.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Po%C5%BEega.jpg"}'::text[], 1),
    (v_route, 'Kutjevo – vinařství', 'Vinařské městečko se starobylým sklepem cisterciáků, srdce slavonského vína. Zastávka na graševinu.', 45.4231, 17.88, 'https://commons.wikimedia.org/wiki/Special:FilePath/Kutjevo.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Kutjevo.jpg"}'::text[], 2),
    (v_route, 'Zřícenina Ružica grad', 'Největší hradní zřícenina Slavonie ukrytá v lesích Papuku. Romantická zastávka mezi stromy.', 45.52, 17.72, 'https://commons.wikimedia.org/wiki/Special:FilePath/Ru%C5%BEica_grad.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Ru%C5%BEica_grad.jpg"}'::text[], 3),
    (v_route, 'Jezero Jankovac', 'Idylické lesní jezírko s vodopádem uprostřed Papuku. Osvěžující zastávka v přírodě.', 45.53, 17.69, 'https://commons.wikimedia.org/wiki/Special:FilePath/Jankovac.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Jankovac.jpg"}'::text[], 4);

  -- Žumberak a Samoborské hory
  delete from public.routes where name = 'Žumberak a Samoborské hory' and branch_id = v_branch;
  v_route := gen_random_uuid();
  insert into public.routes
    (id, branch_id, name, description, route_type, distance_km, duration_min, difficulty,
     waypoints, geometry, mapy_url, cover_image, images, image_alts, countries, is_active, sort_order, status)
  values (v_route, v_branch, 'Žumberak a Samoborské hory', 'Okruh zelenými kopci Žumberku a Samoborského gorja jihozápadně od Záhřebu. Lesní silnice, vodopády Slapnice a půvabný Samobor nabízí klid a chuť kremšnity kousek od metropole. Nejlepší od jara do podzimu; pozor na úzké lesní silnice.', 'loop', 140, 195, 'medium',
     '[{"lat": 45.8018, "lng": 15.7113, "label": "Start: Samobor"}, {"lat": 45.73, "lng": 15.53, "label": "Žumberak"}, {"lat": 45.72, "lng": 15.61, "label": "Sošice"}, {"lat": 45.8018, "lng": 15.7113, "label": "Cíl: Samobor"}]'::jsonb, null, 'https://www.google.com/maps/dir/?api=1&origin=45.8018,15.7113&destination=45.8018,15.7113&travelmode=driving&waypoints=45.73,15.53%7C45.72,15.61', 'https://commons.wikimedia.org/wiki/Special:FilePath/Samobor.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Samobor.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/%C5%BDumberak.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/%C5%BDumberak.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/%C5%BDumberak.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/%C5%BDumberak.jpg"}'::text[], '{"Samobor","Žumberak – přírodní park","Vodopády Slapnice","Stará Vas – kostel","Zřícenina Žumberak grad"}'::text[], '{"HR"}'::text[], false, 4130, 'approved');
  insert into public.route_pois (route_id, name, description, lat, lng, image_url, images, sort_order) values
    (v_route, 'Samobor', 'Půvabné městečko s náměstím a potokem, proslulé krémovým dortem kremšnita. Oblíbený výletní cíl u Záhřebu.', 45.8018, 15.7113, 'https://commons.wikimedia.org/wiki/Special:FilePath/Samobor.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Samobor.jpg"}'::text[], 0),
    (v_route, 'Žumberak – přírodní park', 'Zvlněná zelená krajina s loukami, lesy a řeckokatolickými kostelíky. Klidný kout daleko od ruchu.', 45.73, 15.53, 'https://commons.wikimedia.org/wiki/Special:FilePath/%C5%BDumberak.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/%C5%BDumberak.jpg"}'::text[], 1),
    (v_route, 'Vodopády Slapnice', 'Kaskády potoka v soutěsce Žumberku obklopené lesem. Osvěžující zastávka na stezce.', 45.71, 15.6, 'https://commons.wikimedia.org/wiki/Special:FilePath/%C5%BDumberak.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/%C5%BDumberak.jpg"}'::text[], 2),
    (v_route, 'Stará Vas – kostel', 'Řeckokatolický kostel v srdci Žumberku, připomínka zdejších Uskoků. Klidná zastávka mezi kopci.', 45.72, 15.55, 'https://commons.wikimedia.org/wiki/Special:FilePath/%C5%BDumberak.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/%C5%BDumberak.jpg"}'::text[], 3),
    (v_route, 'Zřícenina Žumberak grad', 'Zbytky středověkého hradu na kopci nad krajem s výhledem do údolí. Romantická zastávka.', 45.74, 15.52, 'https://commons.wikimedia.org/wiki/Special:FilePath/%C5%BDumberak.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/%C5%BDumberak.jpg"}'::text[], 4);

  -- Ostrovy Cres a Lošinj
  delete from public.routes where name = 'Ostrovy Cres a Lošinj' and branch_id = v_branch;
  v_route := gen_random_uuid();
  insert into public.routes
    (id, branch_id, name, description, route_type, distance_km, duration_min, difficulty,
     waypoints, geometry, mapy_url, cover_image, images, image_alts, countries, is_active, sort_order, status)
  values (v_route, v_branch, 'Ostrovy Cres a Lošinj', 'Trasa dvojicí severojaderských ostrovů spojených mostem. Horské silnice nad zálivy, městečko Cres a lázeňský Mali Lošinj nabízí vůni borovic a moře na obou stranách silnice. Nejlepší od května do září; pozor na trajekt a úzké silnice.', 'poi', 130, 210, 'medium',
     '[{"lat": 44.96, "lng": 14.4083, "label": "Start: Cres"}, {"lat": 44.6931, "lng": 14.3931, "label": "Osor"}, {"lat": 44.5306, "lng": 14.47, "label": "Mali Lošinj"}, {"lat": 44.96, "lng": 14.4083, "label": "Cíl: Cres"}]'::jsonb, null, 'https://www.google.com/maps/dir/?api=1&origin=44.96,14.4083&destination=44.96,14.4083&travelmode=driving&waypoints=44.6931,14.3931%7C44.5306,14.47', 'https://commons.wikimedia.org/wiki/Special:FilePath/Cres.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Cres.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Vrana_Lake_Cres.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Osor.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Mali_Lo%C5%A1inj.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Beli_Cres.jpg"}'::text[], '{"Město Cres","Jezero Vransko","Osor","Mali Lošinj","Beli"}'::text[], '{"HR"}'::text[], false, 4140, 'approved');
  insert into public.route_pois (route_id, name, description, lat, lng, image_url, images, sort_order) values
    (v_route, 'Město Cres', 'Půvabné přístavní městečko s benátskými domy kolem zálivu. Srdce divokého ostrova ovcí a supů.', 44.96, 14.4083, 'https://commons.wikimedia.org/wiki/Special:FilePath/Cres.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Cres.jpg"}'::text[], 0),
    (v_route, 'Jezero Vransko', 'Sladkovodní jezero uprostřed ostrova Cres, zdroj pitné vody s tajemnou hloubkou. Neobvyklý úkaz v moři.', 44.83, 14.4, 'https://commons.wikimedia.org/wiki/Special:FilePath/Vrana_Lake_Cres.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Vrana_Lake_Cres.jpg"}'::text[], 1),
    (v_route, 'Osor', 'Starobylé městečko na úzké šíji mezi ostrovy s otočným mostem a sochami. Klenot dějin plný soch.', 44.6931, 14.3931, 'https://commons.wikimedia.org/wiki/Special:FilePath/Osor.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Osor.jpg"}'::text[], 2),
    (v_route, 'Mali Lošinj', 'Největší a nejživější město ostrovů, lázeňský přístav vonící pinií. Cíl cesty u moře.', 44.5306, 14.47, 'https://commons.wikimedia.org/wiki/Special:FilePath/Mali_Lo%C5%A1inj.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Mali_Lo%C5%A1inj.jpg"}'::text[], 3),
    (v_route, 'Beli', 'Malá horská vesnice na severu Cresu s centrem záchrany supů. Klidná zastávka s výhledem na moře.', 45.06, 14.36, 'https://commons.wikimedia.org/wiki/Special:FilePath/Beli_Cres.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Beli_Cres.jpg"}'::text[], 4);

  -- Poloostrov Pelješac
  delete from public.routes where name = 'Poloostrov Pelješac' and branch_id = v_branch;
  v_route := gen_random_uuid();
  insert into public.routes
    (id, branch_id, name, description, route_type, distance_km, duration_min, difficulty,
     waypoints, geometry, mapy_url, cover_image, images, image_alts, countries, is_active, sort_order, status)
  values (v_route, v_branch, 'Poloostrov Pelješac', 'Trasa vinařským poloostrovem Pelješac severně od Dubrovníku. Hradby Stonu, klikaté silnice nad zálivy a vinice Dingače nabízí moře, sůl a špičkové víno. Nejlepší od května do září; pozor na úzké silnice a horko.', 'poi', 140, 195, 'medium',
     '[{"lat": 42.8378, "lng": 17.6975, "label": "Start: Ston"}, {"lat": 42.9744, "lng": 17.1758, "label": "Orebić"}, {"lat": 42.98, "lng": 17.13, "label": "Viganj"}, {"lat": 42.8378, "lng": 17.6975, "label": "Cíl: Ston"}]'::jsonb, null, 'https://www.google.com/maps/dir/?api=1&origin=42.8378,17.6975&destination=42.8378,17.6975&travelmode=driving&waypoints=42.9744,17.1758%7C42.98,17.13', 'https://commons.wikimedia.org/wiki/Special:FilePath/Ston_walls.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Ston_walls.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Orebi%C4%87.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Dinga%C4%8D.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Ston_salt_pans.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Pelje%C5%A1ac.jpg"}'::text[], '{"Hradby Stonu","Orebić","Vinice Dingač","Solné pánve Ston","Sveti Ilija – vyhlídka"}'::text[], '{"HR"}'::text[], false, 4150, 'approved');
  insert into public.route_pois (route_id, name, description, lat, lng, image_url, images, sort_order) values
    (v_route, 'Hradby Stonu', 'Nejdelší dochovaná pevnostní zeď v Evropě chránící solné pánve u vstupu na poloostrov. Chorvatská čínská zeď.', 42.8378, 17.6975, 'https://commons.wikimedia.org/wiki/Special:FilePath/Ston_walls.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Ston_walls.jpg"}'::text[], 0),
    (v_route, 'Orebić', 'Přímořské městečko pod horou Sveti Ilija naproti ostrovu Korčula. Zastávka s výhledem na moře.', 42.9744, 17.1758, 'https://commons.wikimedia.org/wiki/Special:FilePath/Orebi%C4%87.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Orebi%C4%87.jpg"}'::text[], 1),
    (v_route, 'Vinice Dingač', 'Strmé vinice na jižních svazích nad mořem, kolébka slavného červeného vína. Ikonická scenérie Pelješce.', 42.92, 17.35, 'https://commons.wikimedia.org/wiki/Special:FilePath/Dinga%C4%8D.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Dinga%C4%8D.jpg"}'::text[], 2),
    (v_route, 'Solné pánve Ston', 'Nejstarší dochované solné pánve Středomoří, dodnes činné. Ojedinělá památka řemesla.', 42.8378, 17.6975, 'https://commons.wikimedia.org/wiki/Special:FilePath/Ston_salt_pans.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Ston_salt_pans.jpg"}'::text[], 3),
    (v_route, 'Sveti Ilija – vyhlídka', 'Nejvyšší vrchol poloostrova s výhledem na okolní ostrovy a moře. Odměna za výjezd.', 42.96, 17.2, 'https://commons.wikimedia.org/wiki/Special:FilePath/Pelje%C5%A1ac.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Pelje%C5%A1ac.jpg"}'::text[], 4);

  -- Biokovo a Makarská riviéra
  delete from public.routes where name = 'Biokovo a Makarská riviéra' and branch_id = v_branch;
  v_route := gen_random_uuid();
  insert into public.routes
    (id, branch_id, name, description, route_type, distance_km, duration_min, difficulty,
     waypoints, geometry, mapy_url, cover_image, images, image_alts, countries, is_active, sort_order, status)
  values (v_route, v_branch, 'Biokovo a Makarská riviéra', 'Náročný okruh horou Biokovo tyčící se přímo nad Makarskou riviérou. Serpentiny nad Jadranem, prosklená vyhlídka Skywalk a horské výhledy nabízí adrenalin a panorama až k ostrovům. Nejlepší od května do října; pozor na úzkou horskou silnici a vítr.', 'loop', 120, 195, 'hard',
     '[{"lat": 43.2969, "lng": 17.0178, "label": "Start: Makarska"}, {"lat": 43.35, "lng": 17.05, "label": "Sveti Jure"}, {"lat": 43.31, "lng": 17.04, "label": "Skywalk Biokovo"}, {"lat": 43.2969, "lng": 17.0178, "label": "Cíl: Makarska"}]'::jsonb, null, 'https://www.google.com/maps/dir/?api=1&origin=43.2969,17.0178&destination=43.2969,17.0178&travelmode=driving&waypoints=43.35,17.05%7C43.31,17.04', 'https://commons.wikimedia.org/wiki/Special:FilePath/Sveti_Jure.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Sveti_Jure.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Makarska.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Biokovo_Skywalk.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Brela.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Biokovo.jpg"}'::text[], '{"Vrchol Sveti Jure","Makarska","Skywalk Biokovo","Brela","Národní park Biokovo"}'::text[], '{"HR"}'::text[], false, 4160, 'approved');
  insert into public.route_pois (route_id, name, description, lat, lng, image_url, images, sort_order) values
    (v_route, 'Vrchol Sveti Jure', 'Druhý nejvyšší vrchol Chorvatska (1762 m) s dramatickým výhledem na Jadran a ostrovy. Cíl náročného výjezdu.', 43.3494, 17.0525, 'https://commons.wikimedia.org/wiki/Special:FilePath/Sveti_Jure.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Sveti_Jure.jpg"}'::text[], 0),
    (v_route, 'Makarska', 'Živé přímořské město pod strmou stěnou Biokova s promenádou a plážemi. Brána k horské silnici.', 43.2969, 17.0178, 'https://commons.wikimedia.org/wiki/Special:FilePath/Makarska.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Makarska.jpg"}'::text[], 1),
    (v_route, 'Skywalk Biokovo', 'Prosklená vyhlídková plošina zavěšená nad srázem s pohledem přímo dolů na moře. Adrenalinová atrakce.', 43.31, 17.04, 'https://commons.wikimedia.org/wiki/Special:FilePath/Biokovo_Skywalk.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Biokovo_Skywalk.jpg"}'::text[], 2),
    (v_route, 'Brela', 'Půvabné letovisko s proslulou pláží Punta Rata a skálou v moři. Zastávka na koupání pod horami.', 43.37, 16.93, 'https://commons.wikimedia.org/wiki/Special:FilePath/Brela.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Brela.jpg"}'::text[], 3),
    (v_route, 'Národní park Biokovo', 'Divoký kras s propastmi, endemity a botanickou zahradou nad mořem. Ráj horské přírody.', 43.32, 17.03, 'https://commons.wikimedia.org/wiki/Special:FilePath/Biokovo.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Biokovo.jpg"}'::text[], 4);

  -- Lika a hrad Sokolac
  delete from public.routes where name = 'Lika a hrad Sokolac' and branch_id = v_branch;
  v_route := gen_random_uuid();
  insert into public.routes
    (id, branch_id, name, description, route_type, distance_km, duration_min, difficulty,
     waypoints, geometry, mapy_url, cover_image, images, image_alts, countries, is_active, sort_order, status)
  values (v_route, v_branch, 'Lika a hrad Sokolac', 'Okruh drsnou vnitrozemskou krajinou Liky pod pohořím Velebit. Prameny Gacky, hrady a národní park Sjeverni Velebit nabízí divokou přírodu a prázdné silnice daleko od pobřeží. Nejlepší od jara do podzimu; pozor na dobytek a řidší zázemí.', 'loop', 180, 225, 'medium',
     '[{"lat": 44.8697, "lng": 15.24, "label": "Start: Otočac"}, {"lat": 44.81, "lng": 14.97, "label": "Sjeverni Velebit"}, {"lat": 44.5464, "lng": 15.3736, "label": "Gospić"}, {"lat": 44.8697, "lng": 15.24, "label": "Cíl: Otočac"}]'::jsonb, null, 'https://www.google.com/maps/dir/?api=1&origin=44.8697,15.24&destination=44.8697,15.24&travelmode=driving&waypoints=44.81,14.97%7C44.5464,15.3736', 'https://commons.wikimedia.org/wiki/Special:FilePath/Gacka.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Gacka.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Sjeverni_Velebit.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Oto%C4%8Dac.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Sokolac_Brinje.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Gospi%C4%87.jpg"}'::text[], '{"Prameny Gacke","Národní park Sjeverni Velebit","Otočac – kostel na ostrově","Hrad Sokolac","Gospić"}'::text[], '{"HR"}'::text[], false, 4170, 'approved');
  insert into public.route_pois (route_id, name, description, lat, lng, image_url, images, sort_order) values
    (v_route, 'Prameny Gacke', 'Křišťálově čisté prameny jedné z nejrychlejších ponorných řek Evropy s mlýny. Idylická zastávka v Lice.', 44.85, 15.3, 'https://commons.wikimedia.org/wiki/Special:FilePath/Gacka.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Gacka.jpg"}'::text[], 0),
    (v_route, 'Národní park Sjeverni Velebit', 'Divoká krasová horská krajina s botanickou zahradou a stezkami, biosférická rezervace. Ryzí příroda Velebitu.', 44.81, 14.97, 'https://commons.wikimedia.org/wiki/Special:FilePath/Sjeverni_Velebit.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Sjeverni_Velebit.jpg"}'::text[], 1),
    (v_route, 'Otočac – kostel na ostrově', 'Městečko proslulé kostelem stojícím na ostrůvku uprostřed řeky Gacky. Ojedinělá scenérie.', 44.8697, 15.24, 'https://commons.wikimedia.org/wiki/Special:FilePath/Oto%C4%8Dac.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Oto%C4%8Dac.jpg"}'::text[], 2),
    (v_route, 'Hrad Sokolac', 'Zřícenina středověkého hradu nad Brinje s dochovanou kaplí. Historická zastávka v Lice.', 45.0, 15.13, 'https://commons.wikimedia.org/wiki/Special:FilePath/Sokolac_Brinje.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Sokolac_Brinje.jpg"}'::text[], 3),
    (v_route, 'Gospić', 'Hlavní město Liky, výchozí bod do Velebitu a k parku Paklenica. Klidná zastávka ve vnitrozemí.', 44.5464, 15.3736, 'https://commons.wikimedia.org/wiki/Special:FilePath/Gospi%C4%87.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Gospi%C4%87.jpg"}'::text[], 4);

  -- Učka a Kvarnerský záliv
  delete from public.routes where name = 'Učka a Kvarnerský záliv' and branch_id = v_branch;
  v_route := gen_random_uuid();
  insert into public.routes
    (id, branch_id, name, description, route_type, distance_km, duration_min, difficulty,
     waypoints, geometry, mapy_url, cover_image, images, image_alts, countries, is_active, sort_order, status)
  values (v_route, v_branch, 'Učka a Kvarnerský záliv', 'Okruh horou Učka nad Kvarnerským zálivem u istrijské hranice. Serpentiny k vrcholu Vojak, lázeňský Opatija a městečka nad mořem nabízí panorama Jadranu a svěží horský vzduch. Nejlepší od jara do podzimu; pozor na úzkou horskou silnici.', 'loop', 130, 195, 'medium',
     '[{"lat": 45.3378, "lng": 14.31, "label": "Start: Opatija"}, {"lat": 45.2894, "lng": 14.2, "label": "Vojak – Učka"}, {"lat": 45.29, "lng": 14.27, "label": "Lovran"}, {"lat": 45.3378, "lng": 14.31, "label": "Cíl: Opatija"}]'::jsonb, null, 'https://www.google.com/maps/dir/?api=1&origin=45.3378,14.31&destination=45.3378,14.31&travelmode=driving&waypoints=45.2894,14.2%7C45.29,14.27', 'https://commons.wikimedia.org/wiki/Special:FilePath/Vojak_U%C4%8Dka.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Vojak_U%C4%8Dka.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Opatija.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Lovran.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Vela_Draga.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Mo%C5%A1%C4%87eni%C4%8Dka_Draga.jpg"}'::text[], '{"Vrchol Vojak (Učka)","Opatija","Lovran","Vela Draga","Mošćenička Draga"}'::text[], '{"HR"}'::text[], false, 4180, 'approved');
  insert into public.route_pois (route_id, name, description, lat, lng, image_url, images, sort_order) values
    (v_route, 'Vrchol Vojak (Učka)', 'Nejvyšší bod Učky s kamennou věží a kruhovým výhledem na Kvarner, Istrii i Alpy. Cíl oblíbeného výjezdu.', 45.2894, 14.2003, 'https://commons.wikimedia.org/wiki/Special:FilePath/Vojak_U%C4%8Dka.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Vojak_U%C4%8Dka.jpg"}'::text[], 0),
    (v_route, 'Opatija', 'Elegantní lázeňské město s promenádou Lungomare a rakousko-uherskými vilami. Perla Kvarneru.', 45.3378, 14.3061, 'https://commons.wikimedia.org/wiki/Special:FilePath/Opatija.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Opatija.jpg"}'::text[], 1),
    (v_route, 'Lovran', 'Půvabné historické městečko pod Učkou proslulé jedlými kaštany. Klidná zastávka u moře.', 45.2906, 14.2739, 'https://commons.wikimedia.org/wiki/Special:FilePath/Lovran.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Lovran.jpg"}'::text[], 2),
    (v_route, 'Vela Draga', 'Impozantní kaňon s vápencovými věžemi v přírodním parku Učka. Působivá skalní scenérie.', 45.31, 14.25, 'https://commons.wikimedia.org/wiki/Special:FilePath/Vela_Draga.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Vela_Draga.jpg"}'::text[], 3),
    (v_route, 'Mošćenička Draga', 'Malebné rybářské městečko s oblázkovou pláží pod horou. Zastávka na koupání.', 45.25, 14.25, 'https://commons.wikimedia.org/wiki/Special:FilePath/Mo%C5%A1%C4%87eni%C4%8Dka_Draga.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Mo%C5%A1%C4%87eni%C4%8Dka_Draga.jpg"}'::text[], 4);

  -- Slunj a Rastoke
  delete from public.routes where name = 'Slunj a Rastoke' and branch_id = v_branch;
  v_route := gen_random_uuid();
  insert into public.routes
    (id, branch_id, name, description, route_type, distance_km, duration_min, difficulty,
     waypoints, geometry, mapy_url, cover_image, images, image_alts, countries, is_active, sort_order, status)
  values (v_route, v_branch, 'Slunj a Rastoke', 'Okruh vnitrozemím střední Chorvatska kolem vodního městečka Rastoke. Vodopády mezi mlýny, řeka Korana a klidné silnice nabízí zelenou idylu na cestě k Plitvicím. Nejlepší od jara do podzimu; pozor na turisty v sezoně.', 'loop', 150, 195, 'easy',
     '[{"lat": 45.11, "lng": 15.58, "label": "Start: Slunj"}, {"lat": 45.12, "lng": 15.58, "label": "Rastoke"}, {"lat": 45.04, "lng": 15.63, "label": "Barać jeskyně"}, {"lat": 45.11, "lng": 15.58, "label": "Cíl: Slunj"}]'::jsonb, null, 'https://www.google.com/maps/dir/?api=1&origin=45.11,15.58&destination=45.11,15.58&travelmode=driving&waypoints=45.12,15.58%7C45.04,15.63', 'https://commons.wikimedia.org/wiki/Special:FilePath/Rastoke.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Rastoke.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Slunj.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Bara%C4%87_Caves.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Korana.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Slunj.jpg"}'::text[], '{"Rastoke","Slunj","Baráčovy jeskyně","Řeka Korana","Zřícenina Frankopanského hradu"}'::text[], '{"HR"}'::text[], false, 4190, 'approved');
  insert into public.route_pois (route_id, name, description, lat, lng, image_url, images, sort_order) values
    (v_route, 'Rastoke', 'Pohádkové vodní městečko s mlýny a vodopády v místě soutoku dvou řek. Zvané malé Plitvice.', 45.1178, 15.5836, 'https://commons.wikimedia.org/wiki/Special:FilePath/Rastoke.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Rastoke.jpg"}'::text[], 0),
    (v_route, 'Slunj', 'Městečko nad soutěskou řeky Korany s hradem a výhledem na Rastoke. Klidná zastávka na cestě k jezerům.', 45.1114, 15.5867, 'https://commons.wikimedia.org/wiki/Special:FilePath/Slunj.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Slunj.jpg"}'::text[], 1),
    (v_route, 'Baráčovy jeskyně', 'Krápníkové jeskyně v přírodní krajině mezi Slunjem a Plitvicemi. Osvěžující podzemní zastávka.', 45.04, 15.63, 'https://commons.wikimedia.org/wiki/Special:FilePath/Bara%C4%87_Caves.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Bara%C4%87_Caves.jpg"}'::text[], 2),
    (v_route, 'Řeka Korana', 'Křišťálová řeka meandrující zelenou krajinou s možností koupání. Idylická zastávka u vody.', 45.1, 15.59, 'https://commons.wikimedia.org/wiki/Special:FilePath/Korana.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Korana.jpg"}'::text[], 3),
    (v_route, 'Zřícenina Frankopanského hradu', 'Zbytky středověkého hradu Frankopanů nad Slunjem. Historická zastávka s výhledem.', 45.1114, 15.5867, 'https://commons.wikimedia.org/wiki/Special:FilePath/Slunj.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Slunj.jpg"}'::text[], 4);

  -- Ilok a slavonské vinice
  delete from public.routes where name = 'Ilok a slavonské vinice' and branch_id = v_branch;
  v_route := gen_random_uuid();
  insert into public.routes
    (id, branch_id, name, description, route_type, distance_km, duration_min, difficulty,
     waypoints, geometry, mapy_url, cover_image, images, image_alts, countries, is_active, sort_order, status)
  values (v_route, v_branch, 'Ilok a slavonské vinice', 'Trasa nejvýchodnějším cípem Chorvatska podél Dunaje k vinařskému Iloku. Barokní Vukovar, vinice Fruškogorska a hraniční řeka nabízí historii, víno a rovinaté silnice. Nejlepší od jara do podzimu; pozor na řidší zázemí.', 'poi', 170, 210, 'easy',
     '[{"lat": 45.3517, "lng": 18.9983, "label": "Start: Vukovar"}, {"lat": 45.22, "lng": 19.38, "label": "Ilok"}, {"lat": 45.23, "lng": 19.27, "label": "Šarengrad"}, {"lat": 45.3517, "lng": 18.9983, "label": "Cíl: Vukovar"}]'::jsonb, null, 'https://www.google.com/maps/dir/?api=1&origin=45.3517,18.9983&destination=45.3517,18.9983&travelmode=driving&waypoints=45.22,19.38%7C45.23,19.27', 'https://commons.wikimedia.org/wiki/Special:FilePath/Ilok.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Ilok.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Vukovar.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/%C5%A0arengrad.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Vu%C4%8Dedol.jpg","https://commons.wikimedia.org/wiki/Special:FilePath/Ilok.jpg"}'::text[], '{"Ilok – vinice a zámek","Vukovar","Šarengrad","Vučedol","Sklep Ilok"}'::text[], '{"HR"}'::text[], false, 4200, 'approved');
  insert into public.route_pois (route_id, name, description, lat, lng, image_url, images, sort_order) values
    (v_route, 'Ilok – vinice a zámek', 'Nejvýchodnější město Chorvatska nad Dunajem s vinným sklepem a zámkem Odescalchi. Srdce slavonského vína.', 45.22, 19.38, 'https://commons.wikimedia.org/wiki/Special:FilePath/Ilok.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Ilok.jpg"}'::text[], 0),
    (v_route, 'Vukovar', 'Barokní město na Dunaji s vodárenskou věží jako symbolem obnovy. Místo dějin a odvahy.', 45.3517, 18.9983, 'https://commons.wikimedia.org/wiki/Special:FilePath/Vukovar.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Vukovar.jpg"}'::text[], 1),
    (v_route, 'Šarengrad', 'Vesnice s klášterem a vinicemi na břehu Dunaje. Klidná zastávka mezi révou.', 45.23, 19.27, 'https://commons.wikimedia.org/wiki/Special:FilePath/%C5%A0arengrad.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/%C5%A0arengrad.jpg"}'::text[], 2),
    (v_route, 'Vučedol', 'Archeologické naleziště pravěké kultury s moderním muzeem nad Dunajem. Cesta do pravěku.', 45.3517, 18.95, 'https://commons.wikimedia.org/wiki/Special:FilePath/Vu%C4%8Dedol.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Vu%C4%8Dedol.jpg"}'::text[], 3),
    (v_route, 'Sklep Ilok', 'Historický vinný sklep s dubovými sudy, kde zrálo víno pro královské dvory. Zastávka pro milovníky vína.', 45.22, 19.38, 'https://commons.wikimedia.org/wiki/Special:FilePath/Ilok.jpg', '{"https://commons.wikimedia.org/wiki/Special:FilePath/Ilok.jpg"}'::text[], 4);

end $$;
