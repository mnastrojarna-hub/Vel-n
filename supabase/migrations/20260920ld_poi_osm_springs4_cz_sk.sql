-- MotoGo24 — katalog míst: studánky, prameny a vyhlídky z OpenStreetMap
-- (CZ/SK, dávka 4 z 4, staženo 2026-09-20)
-- ---------------------------------------------------------------------------
-- Zadání uživatele (2026-09-20): „chybí studánky … málo zajímavých míst
-- v ČR a SR".
--
-- PROČ Z OSM A NE Z WIKIDAT: Wikidata mají v celém Česku a na Slovensku
-- dohromady SEDM pojmenovaných studánek se souřadnicemi (dávka 20260920j) —
-- chip „Studánky a prameny" by zůstal prakticky prázdný. OpenStreetMap jich
-- má pod `natural=spring` + `name` tisíce. Data jsou © přispěvatelé
-- OpenStreetMap, licence ODbL; appka uvádí atribuci u mapy.
--
-- Jak se to stahovalo (kdyby to někdo potřeboval zopakovat): Overpass API,
-- `node/way["natural"="spring"]["name"]` a `["tourism"="viewpoint"]["name"]`
-- nad obdélníkem ČR a SR. POZOR na zrcadla: overpass.osm.ch odpovídá pod
-- sekundu, ale drží jen Švýcarsko — na české dotazy vrací prázdný, formálně
-- platný výsledek. Planetární zrcadlo, které přes proxy dojede, je
-- maps.mail.ru. Příslušnost k zemi se určuje až doma proti hraničnímu
-- polygonu z Nominatimu, protože obdélník přesahuje do Bavorska i Polska
-- (4 635 bodů takhle vypadlo).
--
-- Guard je stejný jako u wikidatových dávek:
--   * přeskočí bod, u kterého je v katalogu něco se STEJNÝM normalizovaným
--     názvem (public.poi_norm_name) do 1 200 m,
--   * přeskočí bod bez vlastního názvu (holá „Studánka", „Pramen",
--     „Vyhlídka") — takový špendlík je na mapě k ničemu,
--   * body v rámci dávky jsou odduplikované už při generování.
-- Popis a překlady se NEOPAKUJÍ po řádcích — jsou to čtyři konstanty
-- (studánka/vyhlídka × CZ/SK), takže dávka je čtvrtinová oproti tomu, kdyby
-- se JSON psal ke každému bodu.
-- Idempotentní: `delete from … where source like '<dávka>%'` + vložení znovu.

delete from public.points_of_interest p
 where p.source like 'osm-springs-cz-sk-b4-%'
   and p.is_active
   and p.source not like '%merged-into:%'
   and not exists (select 1 from public.poi_ratings r where r.poi_id = p.id)
   and not exists (select 1 from public.user_visited_places v where v.poi_id = p.id);

insert into public.points_of_interest
  (category, name, description, lat, lng, country, source, sort_order,
   image_url, wikidata_id, translations)
select case when v.kind = 'spring' then 'spring' else 'lookout' end,
       v.name,
       case when v.kind = 'spring' and v.country = 'CZ' then 'Pramen / studánka v Česku.'
            when v.kind = 'spring'                      then 'Pramen / studánka na Slovensku.'
            when v.country = 'CZ'                       then 'Vyhlídka v Česku.'
            else                                             'Vyhlídka na Slovensku.' end,
       v.lat, v.lng, v.country, 'osm-springs-cz-sk-b4-' || v.kind, 10000,
       nullif(v.image_url, ''), nullif(v.wikidata_id, ''),
       (case when v.kind = 'spring' and v.country = 'CZ' then '{"en": {"description": "Spring / well in Czechia."}, "de": {"description": "Quelle / Brunnen in Tschechien."}, "pl": {"description": "Źródło / studzienka w Czechach."}, "nl": {"description": "Bron in Tsjechië."}, "es": {"description": "Manantial en Chequia."}, "fr": {"description": "Source en Tchéquie."}, "uk": {"description": "Джерело у Чехії."}}'
             when v.kind = 'spring'                      then '{"en": {"description": "Spring / well in Slovakia."}, "de": {"description": "Quelle / Brunnen in der Slowakei."}, "pl": {"description": "Źródło / studzienka w Słowacji."}, "nl": {"description": "Bron in Slowakije."}, "es": {"description": "Manantial en Eslovaquia."}, "fr": {"description": "Source en Slovaquie."}, "uk": {"description": "Джерело у Словаччині."}}'
             when v.country = 'CZ'                       then '{"en": {"description": "Viewpoint in Czechia."}, "de": {"description": "Aussichtspunkt in Tschechien."}, "pl": {"description": "Punkt widokowy w Czechach."}, "nl": {"description": "Uitzichtpunt in Tsjechië."}, "es": {"description": "Mirador en Chequia."}, "fr": {"description": "Point de vue en Tchéquie."}, "uk": {"description": "Оглядовий майданчик у Чехії."}}'
             else                                             '{"en": {"description": "Viewpoint in Slovakia."}, "de": {"description": "Aussichtspunkt in der Slowakei."}, "pl": {"description": "Punkt widokowy w Słowacji."}, "nl": {"description": "Uitzichtpunt in Slowakije."}, "es": {"description": "Mirador en Eslovaquia."}, "fr": {"description": "Point de vue en Slovaquie."}, "uk": {"description": "Оглядовий майданчик у Словаччині."}}' end)::jsonb
from (values
('viewpoint', 'Tichá dolina', 49.23514, 19.92484, 'SK', '', ''),
('viewpoint', 'Tiché', 48.97902, 19.2827, 'SK', '', ''),
('viewpoint', 'Titanic', 48.74418, 18.99772, 'SK', '', ''),
('viewpoint', 'Tomanová', 49.22191, 19.94901, 'SK', '', ''),
('viewpoint', 'Tomášovský výhľad', 48.94499, 20.45961, 'SK', '', ''),
('viewpoint', 'Tonka', 49.25604, 19.61845, 'SK', '', ''),
('viewpoint', 'Tri lavičky', 49.00943, 20.1648, 'SK', '', ''),
('viewpoint', 'Tri sosny', 48.43593, 19.65386, 'SK', '', ''),
('viewpoint', 'Trnovecké háje', 49.15233, 19.57985, 'SK', '', ''),
('viewpoint', 'Trnác', 49.18166, 19.67657, 'SK', '', ''),
('viewpoint', 'Turek', 48.68515, 20.47888, 'SK', '', ''),
('viewpoint', 'Turánske', 48.93582, 19.39088, 'SK', '', ''),
('viewpoint', 'Turícka dolina', 49.1142, 19.36856, 'SK', '', ''),
('viewpoint', 'Túreň', 49.19202, 19.67373, 'SK', '', ''),
('viewpoint', 'UFO', 48.13686, 17.10458, 'SK', '', ''),
('viewpoint', 'Urpín, vyhliadka', 48.72565, 19.14029, 'SK', '', ''),
('viewpoint', 'Veles', 48.87654, 21.0289, 'SK', '', ''),
('viewpoint', 'Veľká Lomnická veža', 49.18581, 20.21789, 'SK', '', ''),
('viewpoint', 'Veľká skala', 48.51505, 18.39773, 'SK', '', ''),
('viewpoint', 'Veľká skala', 49.05962, 20.88368, 'SK', '', ''),
('viewpoint', 'Veľká skala', 49.09252, 19.2859, 'SK', '', ''),
('viewpoint', 'Veľké Zelezné', 48.96379, 19.39611, 'SK', '', ''),
('viewpoint', 'Veľký Autobus', 48.61923, 17.55734, 'SK', '', ''),
('viewpoint', 'Veľký Grúň', 49.25327, 20.23232, 'SK', '', 'Q11798448'),
('viewpoint', 'Via ferrata Sokolie skaly', 48.55391, 19.08351, 'SK', '', ''),
('viewpoint', 'Villa Betula', 49.13669, 19.50872, 'SK', '', ''),
('viewpoint', 'Vlaková vyhliadka', 48.67628, 21.43281, 'SK', '', ''),
('viewpoint', 'Vlkolínec od Pulčíkova', 49.01672, 19.24824, 'SK', '', ''),
('viewpoint', 'Vlčí trh', 48.38628, 18.87006, 'SK', '', ''),
('viewpoint', 'Vodopád na Bukovine', 49.00298, 19.28564, 'SK', '', ''),
('viewpoint', 'Vodárenská veža', 48.99946, 21.24668, 'SK', '', 'Q121742543'),
('viewpoint', 'Vrakunská rozhľadňa v lesoparku', 48.14552, 17.19891, 'SK', '', ''),
('viewpoint', 'Vršatecká ferrata', 49.06818, 18.1469, 'SK', '', ''),
('viewpoint', 'Vtáčia pozorovateľňa', 48.72669, 17.03232, 'SK', '', ''),
('viewpoint', 'Vyhliadka', 48.30033, 17.24256, 'SK', '', ''),
('viewpoint', 'Vyhliadka', 48.41972, 18.94348, 'SK', '', ''),
('viewpoint', 'Vyhliadka Demian', 48.56735, 18.97709, 'SK', '', ''),
('viewpoint', 'Vyhliadka Dielková', 48.66404, 20.28625, 'SK', '', ''),
('viewpoint', 'Vyhliadka Sady pod Dedovcom', 48.91493, 18.1643, 'SK', '', ''),
('viewpoint', 'Vyhliadka Srdiečko', 49.06792, 20.93953, 'SK', '', ''),
('viewpoint', 'Vyhliadka Višňovská skala', 48.83639, 17.73481, 'SK', '', ''),
('viewpoint', 'Vyhliadka Vršok', 48.8943, 18.22579, 'SK', '', ''),
('viewpoint', 'Vyhliadka na stredný Liptov', 49.02385, 19.5541, 'SK', '', ''),
('viewpoint', 'Vyhliadka na vlaky', 49.073, 20.06765, 'SK', 'https://bit.ly/3XiHWlc', ''),
('viewpoint', 'Vyhliadka pri hruške', 48.71016, 17.44218, 'SK', '', ''),
('viewpoint', 'Vyhliadka u Stegosaura', 48.78932, 21.20667, 'SK', '', ''),
('viewpoint', 'Vyhliadka vo vinici Dangl/Drotáre', 48.25375, 17.20096, 'SK', '', ''),
('viewpoint', 'Vyhliadkova plošina', 48.52293, 21.96463, 'SK', '', ''),
('viewpoint', 'Vyhliadková plošina', 48.28594, 18.50666, 'SK', '', ''),
('viewpoint', 'Vyhliadková plošina', 48.35717, 18.8556, 'SK', '', ''),
('viewpoint', 'Vyhliadková plošina Vínny vrch', 48.37181, 19.52962, 'SK', '', ''),
('viewpoint', 'Vyhliadková veža', 48.76137, 21.23686, 'SK', '', 'Q12778892'),
('viewpoint', 'Vyhliadková veža - chodník v korunách stromov', 49.28613, 20.31441, 'SK', '', ''),
('viewpoint', 'Vyhliadková veža Devínska Kobyla', 48.18929, 16.99547, 'SK', '', 'Q114959375'),
('viewpoint', 'Vyhliadková veža Hôrka', 48.37109, 18.12251, 'SK', '', ''),
('viewpoint', 'Vyhliadková veža Tokaj', 48.44306, 21.69142, 'SK', '', ''),
('viewpoint', 'Vyhliadková veža Trenčianska závada', 48.97357, 18.06272, 'SK', '', ''),
('viewpoint', 'Vyhliadková veža kostola', 49.05491, 20.30131, 'SK', '', ''),
('viewpoint', 'Vyhliadková veža v Poloninách', 49.02922, 22.49654, 'SK', '', ''),
('viewpoint', 'Vyhliadkový mostík', 48.7603, 21.23884, 'SK', '', ''),
('viewpoint', 'Vysoka', 48.8052, 18.27243, 'SK', '', ''),
('viewpoint', 'Vyšná Roveň', 49.16477, 19.69156, 'SK', '', ''),
('viewpoint', 'Vyšný Nefcerský vodopád', 49.17401, 19.99096, 'SK', '', ''),
('viewpoint', 'Vápenica – skala', 48.78999, 21.07454, 'SK', '', ''),
('viewpoint', 'Vápenný nižný úplaz', 49.17787, 19.58322, 'SK', '', ''),
('viewpoint', 'Výhliadka Na kríži', 49.07121, 19.02354, 'SK', '', ''),
('viewpoint', 'Výhliadka Podurviská', 49.32964, 19.24534, 'SK', '', ''),
('viewpoint', 'Výhliadková veža Zákamené', 49.39916, 19.27974, 'SK', '', ''),
('viewpoint', 'Výhľad', 48.40971, 18.85156, 'SK', '', ''),
('viewpoint', 'Výhľad', 48.88867, 19.16604, 'SK', '', ''),
('viewpoint', 'Výhľad Slepý vrch', 48.45818, 17.41253, 'SK', '', ''),
('viewpoint', 'Výhľad na Alpy', 49.0673, 18.48181, 'SK', '', ''),
('viewpoint', 'Výhľad na Hrhov', 48.58178, 20.74872, 'SK', '', ''),
('viewpoint', 'Výhľad na Humenné', 48.89315, 21.86013, 'SK', '', ''),
('viewpoint', 'Výhľad na Lietavský hrad', 49.14297, 18.68459, 'SK', '', ''),
('viewpoint', 'Výhľad na Maníny', 49.06189, 18.49157, 'SK', '', ''),
('viewpoint', 'Výhľad na Poprad', 49.01383, 20.26894, 'SK', '', ''),
('viewpoint', 'Výhľad na Vysoké Tatry, Mengusovce, Štôlu a Poprad', 49.0792, 20.13317, 'SK', '', ''),
('viewpoint', 'Výhľad na juh', 48.89345, 21.85366, 'SK', '', ''),
('viewpoint', 'Výhľad na nápis Szabóová skala', 48.53545, 18.80544, 'SK', '', ''),
('viewpoint', 'Výhľad na sever', 48.89355, 21.85522, 'SK', '', ''),
('viewpoint', 'Výhľad z cintorína', 48.93992, 21.89665, 'SK', '', ''),
('viewpoint', 'Výhľadňa pod Čarnu kopu', 49.18801, 20.78676, 'SK', '', ''),
('viewpoint', 'Výhľadňa Žobrák', 49.23606, 21.17293, 'SK', 'https://img.hiking.dennikn.sk/article/201703/large_x/nova_rozhladna_a.jpg', ''),
('viewpoint', 'Vŕšok', 48.45009, 16.96818, 'SK', '', ''),
('viewpoint', 'Widok na Tatry', 49.47841, 19.22594, 'SK', '', ''),
('viewpoint', 'Widok pod Bugajem', 49.39531, 19.0187, 'SK', '', ''),
('viewpoint', 'Woodlandia', 49.13969, 19.46025, 'SK', '', ''),
('viewpoint', 'Yukon', 49.15101, 19.74434, 'SK', '', ''),
('viewpoint', 'Z Banišťa', 48.43141, 18.80552, 'SK', '', ''),
('viewpoint', 'Z Dolnej ružovej', 48.45894, 18.89534, 'SK', '', ''),
('viewpoint', 'Z Fándlyho', 48.44961, 18.91672, 'SK', '', ''),
('viewpoint', 'Z Gumanín', 48.421, 18.84874, 'SK', '', ''),
('viewpoint', 'Z Hornej Rovni', 48.44683, 18.87893, 'SK', '', ''),
('viewpoint', 'Z Hornej ružovej', 48.45949, 18.89507, 'SK', '', ''),
('viewpoint', 'Z Katovej', 48.45688, 18.89634, 'SK', '', ''),
('viewpoint', 'Z Lichardovej', 48.46087, 18.89299, 'SK', '', ''),
('viewpoint', 'Z Medveďovej', 48.44117, 18.96413, 'SK', '', ''),
('viewpoint', 'Z Vodárenskej', 48.46317, 18.89172, 'SK', '', ''),
('viewpoint', 'Z cesty na Jergištôlňu', 48.4723, 18.9065, 'SK', '', ''),
('viewpoint', 'Z cesty na Sitno', 48.40148, 18.8898, 'SK', '', ''),
('viewpoint', 'Z panskej cesty', 48.42004, 18.94206, 'SK', '', ''),
('viewpoint', 'Zadné Rosniarky', 48.4626, 18.87253, 'SK', '', ''),
('viewpoint', 'Zadný Šíp', 49.16296, 19.16823, 'SK', '', ''),
('viewpoint', 'Zajačková', 49.17115, 19.67835, 'SK', '', ''),
('viewpoint', 'Zaťkova jama', 49.13922, 19.24197, 'SK', '', ''),
('viewpoint', 'Zbojnícka bašta', 49.34661, 18.93741, 'SK', '', ''),
('viewpoint', 'Zbojnícky tanec', 48.64222, 19.48407, 'SK', '', ''),
('viewpoint', 'Zlatý vrch', 48.35493, 18.9144, 'SK', '', ''),
('viewpoint', 'Zobor', 48.13487, 18.34131, 'SK', '', ''),
('viewpoint', 'Záhradné sady', 49.01174, 21.24481, 'SK', '', ''),
('viewpoint', 'Záleský maják', 48.16099, 17.2802, 'SK', '', ''),
('viewpoint', 'Západná veža - vyhliadková veža', 49.0549, 21.32008, 'SK', '', ''),
('viewpoint', 'Západné skaly', 48.40144, 18.8751, 'SK', '', ''),
('viewpoint', 'Zúzovo', 48.78453, 19.4224, 'SK', '', ''),
('viewpoint', 'lavička lásky', 49.12036, 20.61037, 'SK', '', ''),
('viewpoint', 'meteo Malý Javorník', 48.25481, 17.15322, 'SK', '', ''),
('viewpoint', 'na Choč', 49.15207, 19.4304, 'SK', '', ''),
('viewpoint', 'na Gombáš', 49.11861, 19.20127, 'SK', '', ''),
('viewpoint', 'na Ludrovskú dolinu', 48.98006, 19.32277, 'SK', '', ''),
('viewpoint', 'na Okno', 48.98116, 19.69894, 'SK', '', ''),
('viewpoint', 'na Pavčinu Lehotu', 49.03096, 19.57973, 'SK', '', ''),
('viewpoint', 'na Ružomberok', 49.07217, 19.28578, 'SK', '', ''),
('viewpoint', 'na Salatín od Klina', 48.966, 19.35867, 'SK', '', ''),
('viewpoint', 'na Vlkolínec', 49.03558, 19.27633, 'SK', '', ''),
('viewpoint', 'na Vtáčnik', 49.03491, 19.24949, 'SK', '', ''),
('viewpoint', 'na Černovú', 49.09736, 19.25891, 'SK', '', ''),
('viewpoint', 'pod Holubou horou', 48.77021, 21.52515, 'SK', '', ''),
('viewpoint', 'rozhľadňa Bačka', 48.4387, 22.05268, 'SK', '', ''),
('viewpoint', 'sedlo Váha', 49.17602, 20.08987, 'SK', '', 'Q720651'),
('viewpoint', 'v Slemä', 48.99306, 19.6851, 'SK', '', ''),
('viewpoint', 'vyhliadkové kreslo', 48.87457, 20.90291, 'SK', '', ''),
('viewpoint', 'výhlad na Haliny', 49.0499, 19.27545, 'SK', '', ''),
('viewpoint', 'výhliadka pri Bielej skale', 48.4348, 17.2639, 'SK', '', ''),
('viewpoint', 'Čajka v oblakoch', 48.7856, 18.56519, 'SK', '', ''),
('viewpoint', 'Čerešenka', 48.79155, 21.37407, 'SK', '', ''),
('viewpoint', 'Čertov hrad', 48.66059, 20.65225, 'SK', '', ''),
('viewpoint', 'Čertov kameň', 49.2527, 21.90406, 'SK', '', ''),
('viewpoint', 'Čertova Skala', 49.35815, 20.65322, 'SK', '', ''),
('viewpoint', 'Čertove zuby', 48.38092, 17.31172, 'SK', '', ''),
('viewpoint', 'Červená skala', 48.42208, 18.6493, 'SK', '', ''),
('viewpoint', 'Červená skala', 48.97192, 18.39679, 'SK', '', ''),
('viewpoint', 'Červená skala', 48.88054, 20.75804, 'SK', '', ''),
('viewpoint', 'Červená skala', 49.31342, 19.48191, 'SK', '', ''),
('viewpoint', 'Čiapka', 49.13027, 19.40045, 'SK', '', ''),
('viewpoint', 'Čierne pleso', 49.23918, 19.5254, 'SK', '', ''),
('viewpoint', 'Čierno', 49.15832, 19.70865, 'SK', '', ''),
('viewpoint', 'Čierny vrch', 48.92553, 19.30603, 'SK', '', ''),
('viewpoint', 'Člnok', 48.45242, 18.34061, 'SK', '', ''),
('viewpoint', 'Človečia', 49.16099, 19.42034, 'SK', '', ''),
('viewpoint', 'Čutkovo', 49.07526, 19.24741, 'SK', '', ''),
('viewpoint', 'Ďulíkova spomienka', 48.46988, 19.61714, 'SK', '', ''),
('viewpoint', 'Ľubochnianka', 49.10972, 19.15114, 'SK', '', ''),
('viewpoint', 'Šibeničný vrch', 48.59316, 18.87299, 'SK', '', ''),
('viewpoint', 'Šibená hora', 49.01221, 21.24236, 'SK', '', ''),
('viewpoint', 'Školská veža', 48.98786, 19.59604, 'SK', '', ''),
('viewpoint', 'Šlosberg', 48.39833, 18.68571, 'SK', '', ''),
('viewpoint', 'Štefanová', 48.97965, 19.12759, 'SK', '', ''),
('viewpoint', 'Štefánikova vyhliadka', 49.18391, 18.59667, 'SK', '', ''),
('viewpoint', 'Štefánikova vyhliadka', 48.88874, 18.05567, 'SK', '', ''),
('viewpoint', 'Števkovka', 48.4325, 18.95757, 'SK', '', ''),
('viewpoint', 'Štiavnica z nadhľadu', 48.46393, 18.88477, 'SK', '', ''),
('viewpoint', 'Štrbský rybník', 49.07265, 20.07533, 'SK', '', ''),
('viewpoint', 'Šugovská vyhliadka', 48.66035, 20.88704, 'SK', '', ''),
('viewpoint', 'Šváb', 48.39998, 19.00882, 'SK', '', ''),
('viewpoint', 'Švábovie skaly', 49.18245, 19.6133, 'SK', '', ''),
('viewpoint', 'Šíp, medzivrchol', 49.16516, 19.17473, 'SK', '', ''),
('viewpoint', 'Ščob', 49.16332, 20.81145, 'SK', '', ''),
('viewpoint', 'Žeravica', 49.19899, 18.43943, 'SK', '', ''),
('viewpoint', 'Žiar', 48.95191, 19.29517, 'SK', '', ''),
('viewpoint', 'Žiarska dolina', 49.17732, 19.72598, 'SK', '', '')
) as v(kind, name, lat, lng, country, image_url, wikidata_id)
where not exists (
  select 1 from public.points_of_interest p
   where p.lat between v.lat - 0.0108 and v.lat + 0.0108
     and p.lng between v.lng - 0.0168 and v.lng + 0.0168
     and p.norm_name = public.poi_norm_name(v.name)
     and 111320.0 * sqrt(power(p.lat - v.lat, 2)
           + power((p.lng - v.lng) * cos(radians(v.lat)), 2)) <= 1200
);
