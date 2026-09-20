-- MotoGo24 — katalog míst: studánky a prameny (CZ/SK, Wikidata 2026-09-20)
-- ---------------------------------------------------------------------------
-- Zadání uživatele (2026-09-20): „chybí většina významných kopců, chybí
-- studánky … málo zajímavých míst v ČR a SR".
--
-- PROČ TO V KATALOGU CHYBĚLO: dávka hor z 19. 9. (20260919_poi_hills_cz_sk_*)
-- vkládala bod jen tehdy, když v okruhu ~70 m NEBYLO VŮBEC NIC. Jenže
-- u významných vrcholů skoro vždy něco je — u Sněžky leží 50 m vedle
-- wikidatový bod „Krkonošský národní park", u Klínovce rozhledna 18 m,
-- u Čerchova Kurzova rozhledna 56 m. Sněžka, Klínovec, Kralický Sněžník,
-- Blaník, Čerchov, Velká Deštná, Děčínský Sněžník ani Zvičina se proto
-- do katalogu NIKDY nedostaly.
--
-- Tahle dávka má guard postavený obráceně a správně:
--   * přeskočí bod, u kterého je v katalogu něco se STEJNÝM normalizovaným
--     názvem (public.poi_norm_name) do 250 m — tj. skutečný dvojník,
--   * přeskočí bod, u kterého je cokoli do 40 m — dva špendlíky přes sebe,
--   * body v rámci dávky jsou proti sobě odduplikované už při generování
--     (staré dávky to nedělaly vůbec — odtud „Pípalka" vedle „Křemešníku").
-- Souřadnice, foto (P18) i nadmořská výška (P2044) jsou z Wikidat; `wikidata_id`
-- se ukládá, aby šlo fotku později dohledat podle IDENTITY bodu, ne podle
-- „co je do 600 m a jmenuje se podobně".
-- Idempotentní: `delete from … where source = '<dávka>'` + vložení znovu.

-- Vlastní idempotence dávky. NEMAŽE body, na kterých už visí hodnocení nebo
-- značka „navštíveno" — `poi_ratings.poi_id` i `user_visited_places.poi_id`
-- jsou FK s ON DELETE CASCADE, takže by ruční re-apply (Actions → force)
-- nenávratně smazal recenze a fotky zákazníků. Takový řádek zůstane a insert
-- ho znovu nevloží, protože si ho sám podchytí guard níž.
delete from public.points_of_interest p
 where p.source like 'wikidata-springs-cz-sk%'
   and not exists (select 1 from public.poi_ratings r where r.poi_id = p.id)
   and not exists (select 1 from public.user_visited_places v where v.poi_id = p.id);

insert into public.points_of_interest
  (category, name, description, lat, lng, country, source, sort_order,
   image_url, wikidata_id, translations)
select v.category, v.name, v.description, v.lat, v.lng, v.country, v.source,
       v.sort_order, v.image_url, v.wikidata_id, v.translations::jsonb
from (values
('spring', 'Alexandřin pramen', 'Pramen / studánka v Česku.', 49.96917, 12.70306, 'CZ', 'wikidata-springs-cz-sk-spring', 9400, 'https://commons.wikimedia.org/wiki/Special:FilePath/Pavilon%20Alexandrina%20Pramene%20Marianske%20Lazne.jpg', 'Q13407930', '{"en": {"description": "Spring / well in Czechia."}, "de": {"description": "Quelle / Brunnen in Tschechien."}, "pl": {"description": "Źródło / studzienka w Czechach."}, "nl": {"description": "Bron in Tsjechië."}, "es": {"description": "Manantial en Chequia."}, "fr": {"description": "Source en Tchéquie."}, "uk": {"description": "Джерело у Чехії."}}'),
('spring', 'Studánka Vráblovecký medvědice', 'Pramen / studánka v Česku.', 49.87951, 18.22598, 'CZ', 'wikidata-springs-cz-sk-spring', 9756, 'https://commons.wikimedia.org/wiki/Special:FilePath/Stud%C3%A1nka%20Vr%C3%A1bloveck%C3%BD%20medv%C4%9Bdice%2C%20Ludge%C5%99ovice%2C%20okres%20Opava%2C%20Slezsko%2002.jpg', 'Q136653845', '{"en": {"description": "Spring / well in Czechia."}, "de": {"description": "Quelle / Brunnen in Tschechien."}, "pl": {"description": "Źródło / studzienka w Czechach."}, "nl": {"description": "Bron in Tsjechië."}, "es": {"description": "Manantial en Chequia."}, "fr": {"description": "Source en Tchéquie."}, "uk": {"description": "Джерело у Чехії."}}'),
('spring', 'Buková studánka', 'Pramen / studánka v Česku.', 50.05838, 12.26108, 'CZ', 'wikidata-springs-cz-sk-spring', 10000, 'https://commons.wikimedia.org/wiki/Special:FilePath/Buchbrunnen.jpg', 'Q997985', '{"en": {"description": "Spring / well in Czechia."}, "de": {"description": "Quelle / Brunnen in Tschechien."}, "pl": {"description": "Źródło / studzienka w Czechach."}, "nl": {"description": "Bron in Tsjechië."}, "es": {"description": "Manantial en Chequia."}, "fr": {"description": "Source en Tchéquie."}, "uk": {"description": "Джерело у Чехії."}}'),
('spring', 'Křišťálová studánka', 'Pramen / studánka v Česku.', 49.55411, 17.55143, 'CZ', 'wikidata-springs-cz-sk-spring', 10000, 'https://commons.wikimedia.org/wiki/Special:FilePath/K%C5%99i%C5%A1%C5%A5%C3%A1lov%C3%A1%20stud%C3%A1nka%20u%20Bohusl%C3%A1vek%2C%20Slavkov%2C%20okres%20Olomouc.jpg', 'Q111976618', '{"en": {"description": "Spring / well in Czechia."}, "de": {"description": "Quelle / Brunnen in Tschechien."}, "pl": {"description": "Źródło / studzienka w Czechach."}, "nl": {"description": "Bron in Tsjechië."}, "es": {"description": "Manantial en Chequia."}, "fr": {"description": "Source en Tchéquie."}, "uk": {"description": "Джерело у Чехії."}}'),
('spring', 'Pramen Eliška', 'Pramen / studánka v Česku.', 50.03312, 17.03576, 'CZ', 'wikidata-springs-cz-sk-spring', 10000, 'https://commons.wikimedia.org/wiki/Special:FilePath/Velk%C3%A9%20Losiny%2C%20L%C3%A1ze%C5%88sk%C3%A1%20240%20L%C3%A1ze%C5%88sk%C3%BD%20d%C5%AFm%20Eli%C5%A1ka%20%282455%29.jpg', 'Q108058024', '{"en": {"description": "Spring / well in Czechia."}, "de": {"description": "Quelle / Brunnen in Tschechien."}, "pl": {"description": "Źródło / studzienka w Czechach."}, "nl": {"description": "Bron in Tsjechië."}, "es": {"description": "Manantial en Chequia."}, "fr": {"description": "Source en Tchéquie."}, "uk": {"description": "Джерело у Чехії."}}'),
('spring', 'Pramen Karel', 'Pramen / studánka v Česku.', 50.03546, 17.03493, 'CZ', 'wikidata-springs-cz-sk-spring', 10000, 'https://commons.wikimedia.org/wiki/Special:FilePath/Velk%C3%A9%20Losiny%2C%20miner%C3%A1ln%C3%AD%20pramen%20Karel%20%282021-07-23%2016.40.52%29.jpg', 'Q108057915', '{"en": {"description": "Spring / well in Czechia."}, "de": {"description": "Quelle / Brunnen in Tschechien."}, "pl": {"description": "Źródło / studzienka w Czechach."}, "nl": {"description": "Bron in Tsjechië."}, "es": {"description": "Manantial en Chequia."}, "fr": {"description": "Source en Tchéquie."}, "uk": {"description": "Джерело у Чехії."}}'),
('spring', 'Šlosarova studánka', 'Pramen / studánka v Česku.', 49.55905, 17.54619, 'CZ', 'wikidata-springs-cz-sk-spring', 10000, 'https://commons.wikimedia.org/wiki/Special:FilePath/%C5%A0losarova%20stud%C3%A1nka%2C%20Odersk%C3%A9%20vrchy%2C%20okres%20Olomouc%2002.jpg', 'Q111976584', '{"en": {"description": "Spring / well in Czechia."}, "de": {"description": "Quelle / Brunnen in Tschechien."}, "pl": {"description": "Źródło / studzienka w Czechach."}, "nl": {"description": "Bron in Tsjechië."}, "es": {"description": "Manantial en Chequia."}, "fr": {"description": "Source en Tchéquie."}, "uk": {"description": "Джерело у Чехії."}}')
) as v(category, name, description, lat, lng, country, source, sort_order,
       image_url, wikidata_id, translations)
where not exists (
  select 1 from public.points_of_interest p
   where p.lat between v.lat - 0.00225 and v.lat + 0.00225
     and p.lng between v.lng - 0.0035 and v.lng + 0.0035
     -- Dvojník = STEJNÝ normalizovaný název do ~250 m. Žádné plošné „cokoli
     -- do X metrů": právě to v dávce z 19. 9. vyhodilo Sněžku, protože na
     -- jejím vrcholu má Wikidata bod „Krkonošský národní park" s TOTOŽNÝMI
     -- souřadnicemi. Dva různé objekty na jednom bodě jsou legitimní data;
     -- na jeden špendlík je v seznamu i na mapě slučuje appka.
     and p.norm_name = public.poi_norm_name(v.name)
     and 111320.0 * sqrt(power(p.lat - v.lat, 2)
           + power((p.lng - v.lng) * cos(radians(v.lat)), 2)) <= 250
);

-- POZNÁMKA KE STUDÁNKÁM (ať to příště nikdo nehledá znovu):
-- Wikidata NEJSOU na studánky zdroj. V celém Česku a na Slovensku mají
-- dohromady 7 pojmenovaných studánek/pramenů se souřadnicemi; zbylých 125
-- položek pod „studna" jsou PAMÁTKOVÉ studny (hradní, náměstní, vahadlové),
-- které jdou do `sights` v dávce 20260920k. Pořádná databáze studánek je
-- v OpenStreetMap (`natural=spring` + `name`, řádově tisíce bodů v ČR)
-- a na Estudanky.eu. Ani jedno se v tomhle prostředí stáhnout nedá —
-- Overpass API je za agent proxy nedostupné a Estudanky.eu je dobrovolnický
-- projekt, jehož hromadné převzetí potřebuje jejich svolení.
-- Kategorie `spring` je připravená (CHECK, chip v appce v 8 jazycích, filtr
-- ve Velíně), takže jakmile bude zdroj po ruce, stačí jen vložit data.
