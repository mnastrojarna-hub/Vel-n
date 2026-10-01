-- =============================================================================
-- FAQ: velikosti bund/kalhot podle pobočky + výměna velikosti na samoobsluze
-- Migrace: 20261001b_faq_branch_gear_sizes.sql (DATOVÁ, bez změn schématu)
--
-- Zadání majitele 2026-10-01: samoobslužná pobočka (Velké Němčice) nabízí
-- bundy a kalhoty max. do 4XL, obslužná (Mezná) až do 6XL; velikost výbavy
-- lze vyměnit i na samoobslužné pobočce (v šatně vyzkouší, v předávacím
-- protokolu na displeji kiosku označí skutečnou velikost). Čte web, appka
-- i AI agenti (get_faq).
--
-- 1) ee1a5c2f „Jaké velikosti výbavy nabízíte?“ — k řádkům Bunda/Kalhoty se
--    doplní poznámka o 4XL na samoobsluze (cs + de/en/es/fr/nl/pl; uk řádek
--    nemá). Nahrazuje se JEN přesný původní řádek (ověřeno proti živým datům
--    REST 2026-10-01) — ruční úpravu z Velína nepřepíše, 2. běh = 0 změn.
-- 2) Nová otázka (conditions, sort 245, hned za ee1a5c2f) s překlady do 7
--    jazyků; pevné id + ON CONFLICT DO NOTHING = idempotentní.
-- =============================================================================

DO $$
DECLARE
  f     record;
  cnt   integer;
  n_upd integer := 0;
  fid   constant uuid := 'ee1a5c2f-6eea-4db3-b012-b4d3d01ce0b6';
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
    ('cs', '<div>Bunda - S-6XL</div>', '<div>Bunda - S-6XL (samoobslužná pobočka Velké Němčice: do 4XL)</div>'),
    ('cs', '<div>Kalhoty - M-6XL</div>', '<div>Kalhoty - M-6XL (samoobslužná pobočka Velké Němčice: do 4XL)</div>'),
    ('en', '<div>Jacket - S-6XL</div>', '<div>Jacket - S-6XL (self-service branch Velké Němčice: up to 4XL)</div>'),
    ('en', '<div>Pants - M-6XL</div>', '<div>Pants - M-6XL (self-service branch Velké Němčice: up to 4XL)</div>'),
    ('de', '<div>Jacke - S-6XL</div>', '<div>Jacke - S-6XL (Selbstbedienungs-Filiale Velké Němčice: bis 4XL)</div>'),
    ('de', '<div>Hose - M-6XL</div>', '<div>Hose - M-6XL (Selbstbedienungs-Filiale Velké Němčice: bis 4XL)</div>'),
    ('es', '<div>Chaqueta - S-6XL</div>', '<div>Chaqueta - S-6XL (sucursal de autoservicio Velké Němčice: hasta 4XL)</div>'),
    ('es', '<div>Pantalones - M-6XL</div>', '<div>Pantalones - M-6XL (sucursal de autoservicio Velké Němčice: hasta 4XL)</div>'),
    ('fr', '<div>Blouson - S-6XL</div>', '<div>Blouson - S-6XL (agence en libre-service Velké Němčice : jusqu''au 4XL)</div>'),
    ('fr', '<div>Pantalon - M-6XL</div>', '<div>Pantalon - M-6XL (agence en libre-service Velké Němčice : jusqu''au 4XL)</div>'),
    ('nl', '<div>Jas - S-6XL</div>', '<div>Jas - S-6XL (selfservicefiliaal Velké Němčice: tot 4XL)</div>'),
    ('nl', '<div>Broek - M-6XL</div>', '<div>Broek - M-6XL (selfservicefiliaal Velké Němčice: tot 4XL)</div>'),
    ('pl', '<div>Kurtka - S-6XL</div>', '<div>Kurtka - S-6XL (oddział samoobsługowy Velké Němčice: do 4XL)</div>'),
    ('pl', '<div>Spodnie - M-6XL</div>', '<div>Spodnie - M-6XL (oddział samoobsługowy Velké Němčice: do 4XL)</div>')
    ) AS v(lang, old_txt, new_txt)
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items SET answer = replace(answer, f.old_txt, f.new_txt)
       WHERE id = fid AND strpos(answer, f.old_txt) > 0;
    ELSE
      UPDATE public.faq_items
         SET translations = jsonb_set(translations, ARRAY[f.lang, 'answer'],
               to_jsonb(replace(translations -> f.lang ->> 'answer', f.old_txt, f.new_txt)))
       WHERE id = fid
         AND strpos(coalesce(translations -> f.lang ->> 'answer', ''), f.old_txt) > 0;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    n_upd := n_upd + cnt;
    IF cnt = 0 THEN
      RAISE NOTICE 'faq ee1a5c2f [%]: „%“ nenalezeno (už upraveno) — přeskočeno', f.lang, f.old_txt;
    END IF;
  END LOOP;
  RAISE NOTICE 'faq ee1a5c2f: upraveno % řádků velikostí', n_upd;
END
$$;

INSERT INTO public.faq_items (id, category_key, category_label, question, answer, sort_order, featured_home, published, translations)
SELECT '5b1e0c7a-3f2d-4c8e-9a61-2d7f4e8b1c01'::uuid, c.category_key, c.category_label,
  $t$Můžu si na samoobslužné pobočce vyměnit velikost výbavy?$t$,
  $t$Ano. Na samoobslužné pobočce ve Velkých Němčicích si výbavu vyzkoušíš přímo v šatně, kterou otevřeš kódem z aplikace. Když ti zarezervovaná velikost nesedí, vezmi si jinou dostupnou velikost a na displeji ji v předávacím protokolu jen označíš — nic dalšího řešit nemusíš. Bundy a kalhoty jsou na samoobslužné pobočce k dispozici do velikosti <strong>4XL</strong>, větší velikosti (až <strong>6XL</strong>) nabízíme na obslužné pobočce v Mezné u Pelhřimova.$t$,
  245, false, true,
  jsonb_build_object(
    'en', jsonb_build_object('question', $t$Can I swap my gear size at the self-service branch?$t$,
      'answer', $t$Yes. At the self-service branch in Velké Němčice you can try on the gear right in the locker room, which you open with a code from the app. If the size you booked doesn't fit, take another available size and simply mark it in the handover protocol on the display — nothing else to sort out. Jackets and pants at the self-service branch are available up to size <strong>4XL</strong>; larger sizes (up to <strong>6XL</strong>) are offered at our staffed branch in Mezná near Pelhřimov.$t$),
    'de', jsonb_build_object('question', $t$Kann ich die Größe der Ausrüstung in der Selbstbedienungs-Filiale tauschen?$t$,
      'answer', $t$Ja. In der Selbstbedienungs-Filiale in Velké Němčice probierst du die Ausrüstung direkt in der Umkleide an, die du mit einem Code aus der App öffnest. Passt die gebuchte Größe nicht, nimm eine andere verfügbare Größe und markiere sie einfach im Übergabeprotokoll auf dem Display — mehr musst du nicht tun. Jacken und Hosen gibt es in der Selbstbedienungs-Filiale bis Größe <strong>4XL</strong>; größere Größen (bis <strong>6XL</strong>) bieten wir in unserer Filiale mit Personal in Mezná bei Pelhřimov an.$t$),
    'es', jsonb_build_object('question', $t$¿Puedo cambiar la talla del equipo en la sucursal de autoservicio?$t$,
      'answer', $t$Sí. En la sucursal de autoservicio de Velké Němčice te pruebas el equipo directamente en el vestuario, que abres con un código de la aplicación. Si la talla reservada no te queda bien, coge otra talla disponible y simplemente márcala en el protocolo de entrega en la pantalla; no tienes que hacer nada más. Las chaquetas y los pantalones en la sucursal de autoservicio están disponibles hasta la talla <strong>4XL</strong>; las tallas más grandes (hasta <strong>6XL</strong>) las ofrecemos en nuestra sucursal con personal en Mezná, cerca de Pelhřimov.$t$),
    'fr', jsonb_build_object('question', $t$Puis-je changer la taille de l'équipement à l'agence en libre-service ?$t$,
      'answer', $t$Oui. À l'agence en libre-service de Velké Němčice, tu essaies l'équipement directement dans le vestiaire, que tu ouvres avec un code de l'application. Si la taille réservée ne te va pas, prends une autre taille disponible et indique-la simplement dans le protocole de remise à l'écran — rien d'autre à faire. Les blousons et pantalons sont disponibles à l'agence en libre-service jusqu'au <strong>4XL</strong> ; les tailles plus grandes (jusqu'au <strong>6XL</strong>) sont proposées dans notre agence avec personnel à Mezná, près de Pelhřimov.$t$),
    'nl', jsonb_build_object('question', $t$Kan ik de maat van de uitrusting ruilen bij de selfservicefiliaal?$t$,
      'answer', $t$Ja. Bij de selfservicefiliaal in Velké Němčice pas je de uitrusting direct in de kleedruimte, die je opent met een code uit de app. Past de gereserveerde maat niet, neem dan een andere beschikbare maat en vink die gewoon aan in het overdrachtsprotocol op het scherm — verder hoef je niets te regelen. Jassen en broeken zijn bij de selfservicefiliaal verkrijgbaar tot maat <strong>4XL</strong>; grotere maten (tot <strong>6XL</strong>) bieden we aan in ons bemande filiaal in Mezná bij Pelhřimov.$t$),
    'pl', jsonb_build_object('question', $t$Czy w oddziale samoobsługowym mogę wymienić rozmiar wyposażenia?$t$,
      'answer', $t$Tak. W oddziale samoobsługowym w Velké Němčice przymierzysz wyposażenie bezpośrednio w szatni, którą otworzysz kodem z aplikacji. Jeśli zarezerwowany rozmiar nie pasuje, weź inny dostępny rozmiar i po prostu zaznacz go w protokole wydania na wyświetlaczu — nic więcej nie musisz załatwiać. Kurtki i spodnie są w oddziale samoobsługowym dostępne do rozmiaru <strong>4XL</strong>; większe rozmiary (do <strong>6XL</strong>) oferujemy w naszym oddziale z obsługą w Mezná koło Pelhřimova.$t$),
    'uk', jsonb_build_object('question', $t$Чи можу я поміняти розмір екіпірування на філії самообслуговування?$t$,
      'answer', $t$Так. На філії самообслуговування у Velké Němčice ви приміряєте екіпірування просто в гардеробі, який відкриваєте кодом із застосунку. Якщо заброньований розмір не підходить, візьміть інший доступний розмір і просто позначте його в протоколі передачі на дисплеї — більше нічого робити не потрібно. Куртки та штани на філії самообслуговування доступні до розміру <strong>4XL</strong>; більші розміри (до <strong>6XL</strong>) пропонуємо на нашій філії з персоналом у Mezná біля Pelhřimova.$t$)
  )
FROM (
  SELECT coalesce((SELECT category_label FROM public.faq_items WHERE category_key = 'conditions' LIMIT 1), 'Podmínky') AS category_label,
         'conditions'::text AS category_key
) c
ON CONFLICT (id) DO NOTHING;
