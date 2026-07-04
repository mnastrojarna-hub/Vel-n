-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Post-seed úpravy tras (2026-07-04)
-- Aplikováno na živou DB uživatelem; zde pro historii/reprodukovatelnost.
-- 1) countries → ISO  2) publikace  3) přejmenování zavádějících názvů
-- 4) překlad názvů do všech jazyků. Vše idempotentní.
-- ════════════════════════════════════════════════════════════════════

-- 1) countries → ISO kódy
update public.routes r
set countries = (
  select coalesce(array_agg(distinct
    case c
      when 'Česko' then 'CZ'
      when 'Rakousko' then 'AT'
      when 'Itálie' then 'IT'
      when 'Slovensko' then 'SK'
      when 'Německo' then 'DE'
      when 'Polsko' then 'PL'
      when 'Chorvatsko' then 'HR'
      when 'Slovinsko' then 'SI'
      when 'Maďarsko' then 'HU'
      when 'Francie' then 'FR'
      when 'Švýcarsko' then 'CH'
      when 'Rumunsko' then 'RO'
      when 'Španělsko' then 'ES'
      when 'Norsko' then 'NO'
      when 'Černá Hora' then 'ME'
      when 'Andorra' then 'AD'
      when 'Portugalsko' then 'PT'
      when 'Švédsko' then 'SE'
      when 'Finsko' then 'FI'
      when 'Island' then 'IS'
      when 'Dánsko' then 'DK'
      when 'Skotsko' then 'GB'
      when 'Spojené království' then 'GB'
      when 'Wales' then 'GB'
      when 'Anglie' then 'GB'
      when 'Irsko' then 'IE'
      when 'Nizozemsko' then 'NL'
      when 'Belgie' then 'BE'
      when 'Lucembursko' then 'LU'
      when 'Lichtenštejnsko' then 'LI'
      when 'Bulharsko' then 'BG'
      when 'Srbsko' then 'RS'
      when 'Bosna a Hercegovina' then 'BA'
      when 'Severní Makedonie' then 'MK'
      when 'Albánie' then 'AL'
      when 'Řecko' then 'GR'
      when 'Moldavsko' then 'MD'
      when 'Litva' then 'LT'
      when 'Lotyšsko' then 'LV'
      when 'Estonsko' then 'EE'
      else c  -- už ISO / neznámé nech beze změny
    end), '{}'::text[])
  from unnest(r.countries) as c
)
where r.countries <> '{}'::text[];

-- 2) Publikace schválených tras
update public.routes set is_active = true where status = 'approved';

-- 3) Přejmenování zavádějících kategorických názvů
update public.routes set name = 'Přehrady, voda a klášter Vysočiny' where name = 'Přehrady a voda Vysočiny';
update public.routes set name = 'Rozhledny a hrad Kámen (Vysočina)' where name = 'Za rozhlednami Vysočiny';
update public.routes set name = 'Rozhledny a zámek Přibyslav' where name = 'Rozhledny Havlíčkobrodska';
update public.routes set name = 'Rozhledny a zámky Třebíčska (Mařenka a Babylon)' where name = 'Rozhledny Třebíčska – Mařenka a Babylon';
update public.routes set name = 'Hrady a jeskyně kolem Prahy' where name = 'Hrady kolem Prahy';
update public.routes set name = 'Polabí – zámky a skanzen' where name = 'Polabí a jeho zámky';
update public.routes set name = 'Rozhledny a památky Píseckých hor' where name = 'Rozhledny Píseckých hor';

-- 4) Přeložené názvy (translations) do všech jazyků
-- Přepis názvů tras do všech jazyků (translations jsonb), zachová přeložený popis
update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'en', coalesce(translations->'en','{}'::jsonb) || jsonb_build_object('name','Dams, water and a monastery of Vysočina'),
    'de', coalesce(translations->'de','{}'::jsonb) || jsonb_build_object('name','Talsperren, Wasser und Kloster der Vysočina'),
    'es', coalesce(translations->'es','{}'::jsonb) || jsonb_build_object('name','Presas, agua y monasterio de Vysočina'),
    'fr', coalesce(translations->'fr','{}'::jsonb) || jsonb_build_object('name','Barrages, eau et monastère de Vysočina'),
    'nl', coalesce(translations->'nl','{}'::jsonb) || jsonb_build_object('name','Stuwmeren, water en klooster van Vysočina'),
    'pl', coalesce(translations->'pl','{}'::jsonb) || jsonb_build_object('name','Zapory, woda i klasztor Vysočiny')
  ) where name = 'Přehrady, voda a klášter Vysočiny';

update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'en', coalesce(translations->'en','{}'::jsonb) || jsonb_build_object('name','Lookout towers and Kámen Castle (Vysočina)'),
    'de', coalesce(translations->'de','{}'::jsonb) || jsonb_build_object('name','Aussichtstürme und Burg Kámen (Vysočina)'),
    'es', coalesce(translations->'es','{}'::jsonb) || jsonb_build_object('name','Miradores y castillo de Kámen (Vysočina)'),
    'fr', coalesce(translations->'fr','{}'::jsonb) || jsonb_build_object('name','Tours panoramiques et château de Kámen (Vysočina)'),
    'nl', coalesce(translations->'nl','{}'::jsonb) || jsonb_build_object('name','Uitkijktorens en kasteel Kámen (Vysočina)'),
    'pl', coalesce(translations->'pl','{}'::jsonb) || jsonb_build_object('name','Wieże widokowe i zamek Kámen (Vysočina)')
  ) where name = 'Rozhledny a hrad Kámen (Vysočina)';

update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'en', coalesce(translations->'en','{}'::jsonb) || jsonb_build_object('name','Lookout towers and Přibyslav Chateau'),
    'de', coalesce(translations->'de','{}'::jsonb) || jsonb_build_object('name','Aussichtstürme und Schloss Přibyslav'),
    'es', coalesce(translations->'es','{}'::jsonb) || jsonb_build_object('name','Miradores y palacio de Přibyslav'),
    'fr', coalesce(translations->'fr','{}'::jsonb) || jsonb_build_object('name','Tours panoramiques et château de Přibyslav'),
    'nl', coalesce(translations->'nl','{}'::jsonb) || jsonb_build_object('name','Uitkijktorens en kasteel Přibyslav'),
    'pl', coalesce(translations->'pl','{}'::jsonb) || jsonb_build_object('name','Wieże widokowe i pałac Přibyslav')
  ) where name = 'Rozhledny a zámek Přibyslav';

update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'en', coalesce(translations->'en','{}'::jsonb) || jsonb_build_object('name','Lookout towers and chateaux of the Třebíč region (Mařenka and Babylon)'),
    'de', coalesce(translations->'de','{}'::jsonb) || jsonb_build_object('name','Aussichtstürme und Schlösser der Region Třebíč (Mařenka und Babylon)'),
    'es', coalesce(translations->'es','{}'::jsonb) || jsonb_build_object('name','Miradores y palacios de la región de Třebíč (Mařenka y Babylon)'),
    'fr', coalesce(translations->'fr','{}'::jsonb) || jsonb_build_object('name','Tours panoramiques et châteaux de la région de Třebíč (Mařenka et Babylon)'),
    'nl', coalesce(translations->'nl','{}'::jsonb) || jsonb_build_object('name','Uitkijktorens en kastelen van de regio Třebíč (Mařenka en Babylon)'),
    'pl', coalesce(translations->'pl','{}'::jsonb) || jsonb_build_object('name','Wieże widokowe i pałace regionu Třebíč (Mařenka i Babylon)')
  ) where name = 'Rozhledny a zámky Třebíčska (Mařenka a Babylon)';

update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'en', coalesce(translations->'en','{}'::jsonb) || jsonb_build_object('name','Castles and caves around Prague'),
    'de', coalesce(translations->'de','{}'::jsonb) || jsonb_build_object('name','Burgen und Höhlen rund um Prag'),
    'es', coalesce(translations->'es','{}'::jsonb) || jsonb_build_object('name','Castillos y cuevas alrededor de Praga'),
    'fr', coalesce(translations->'fr','{}'::jsonb) || jsonb_build_object('name','Châteaux et grottes autour de Prague'),
    'nl', coalesce(translations->'nl','{}'::jsonb) || jsonb_build_object('name','Kastelen en grotten rond Praag'),
    'pl', coalesce(translations->'pl','{}'::jsonb) || jsonb_build_object('name','Zamki i jaskinie wokół Pragi')
  ) where name = 'Hrady a jeskyně kolem Prahy';

update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'en', coalesce(translations->'en','{}'::jsonb) || jsonb_build_object('name','The Elbe Lowland – chateaux and an open-air museum'),
    'de', coalesce(translations->'de','{}'::jsonb) || jsonb_build_object('name','Das Elbland – Schlösser und Freilichtmuseum'),
    'es', coalesce(translations->'es','{}'::jsonb) || jsonb_build_object('name','La región del Elba – palacios y museo al aire libre'),
    'fr', coalesce(translations->'fr','{}'::jsonb) || jsonb_build_object('name','La région de l''Elbe – châteaux et musée en plein air'),
    'nl', coalesce(translations->'nl','{}'::jsonb) || jsonb_build_object('name','Het Elbedal – kastelen en openluchtmuseum'),
    'pl', coalesce(translations->'pl','{}'::jsonb) || jsonb_build_object('name','Kraina nad Łabą – pałace i skansen')
  ) where name = 'Polabí – zámky a skanzen';

update public.routes set translations = coalesce(translations,'{}'::jsonb) || jsonb_build_object(
    'en', coalesce(translations->'en','{}'::jsonb) || jsonb_build_object('name','Lookout towers and landmarks of the Písek Hills'),
    'de', coalesce(translations->'de','{}'::jsonb) || jsonb_build_object('name','Aussichtstürme und Sehenswürdigkeiten der Píseker Berge'),
    'es', coalesce(translations->'es','{}'::jsonb) || jsonb_build_object('name','Miradores y monumentos de las montañas de Písek'),
    'fr', coalesce(translations->'fr','{}'::jsonb) || jsonb_build_object('name','Tours panoramiques et monuments des collines de Písek'),
    'nl', coalesce(translations->'nl','{}'::jsonb) || jsonb_build_object('name','Uitkijktorens en bezienswaardigheden van het Písek-gebergte'),
    'pl', coalesce(translations->'pl','{}'::jsonb) || jsonb_build_object('name','Wieże widokowe i zabytki Gór Píseckich')
  ) where name = 'Rozhledny a památky Píseckých hor';
