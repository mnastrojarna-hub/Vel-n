-- =============================================================================
-- 2026-10-23 (f): FAQ 77557a0b „Můžu si u vás půjčit jen výbavu…“
-- — věta z 20261002b_faq_self_service_gear_fix.sql tvrdí, že výpůjčka výbavy bez motorky je jen
-- v Mezné a samoobsluha vydává výbavu jen k motorce. Od 2026-10-23 (booking_kind='gear') to neplatí; nový text nejmenuje pobočky (samoobslužná se zapíná ve Velínu až po kiosku 1.3.0).
-- Nahrazuje se JEN přesná věta z 20261002b (ruční úpravu z Velína nepřepíše); 2. běh = 0 změn.
-- + bump ai_kb_version (AI agenti FAQ hned znovu načtou). Idempotentní, jedna transakce.
-- =============================================================================
DO $$
DECLARE f record; cnt integer; n_upd integer := 0;
BEGIN
  FOR f IN SELECT v.lang, v.old_txt, v.new_txt FROM (VALUES
    ('cs',
     'Samostatnou výpůjčku výbavy (bez motorky), nepromoky i další doplňkovou výbavu nabízíme jen na obslužné pobočce v Mezné u Pelhřimova. Samoobslužná pobočka ve Velkých Němčicích vydává výbavu jen k rezervované motorce, a to jen helmu, bundu s páteřákem, kalhoty, rukavice, kuklu a boty.',
     'Samostatnou výpůjčku výbavy bez motorky (helma, bunda, kalhoty, rukavice, boty) objednáte online v sekci Půjčení výbavy — je tam aktuální ceník i pobočky, na kterých je výpůjčka dostupná. Nepromoky a další doplňkovou výbavu půjčujeme jen na obslužné pobočce v Mezné u Pelhřimova.'),
    ('en',
     'Gear-only rental (without a motorcycle), rain gear and other additional equipment are only available at our staffed branch in Mezná near Pelhřimov. The self-service branch in Velké Němčice only issues gear together with a booked motorcycle — and only a helmet, a jacket with a back protector, trousers, gloves, a balaclava and boots.',
     'Gear-only rental without a motorcycle (helmet, jacket, trousers, gloves, boots) can be booked online in the Gear rental section, which also shows the current prices and the branches where it is available. Rain gear and other additional equipment are only available at our staffed branch in Mezná near Pelhřimov.'),
    ('de',
     'Ausrüstung ohne Motorrad, Regenbekleidung und weiteres Zubehör verleihen wir nur in unserer Filiale mit Personal in Mezná bei Pelhřimov. Die Selbstbedienungs-Filiale in Velké Němčice gibt Ausrüstung nur zu einem reservierten Motorrad aus — und zwar nur Helm, Jacke mit Rückenprotektor, Hose, Handschuhe, Sturmhaube und Stiefel.',
     'Ausrüstung ohne Motorrad (Helm, Jacke, Hose, Handschuhe, Stiefel) buchen Sie online im Bereich Ausrüstung mieten — dort finden Sie die aktuellen Preise und die Filialen, in denen der Verleih verfügbar ist. Regenbekleidung und weiteres Zubehör verleihen wir nur in unserer Filiale mit Personal in Mezná bei Pelhřimov.'),
    ('es',
     'El alquiler de solo equipo (sin moto), el equipo para la lluvia y el resto de accesorios solo los ofrecemos en nuestra sucursal con personal en Mezná, cerca de Pelhřimov. La sucursal de autoservicio de Velké Němčice solo entrega equipo junto con una moto reservada, y únicamente casco, chaqueta con protector de espalda, pantalones, guantes, braga y botas.',
     'El alquiler de solo equipo sin moto (casco, chaqueta, pantalón, guantes, botas) se reserva en línea en la sección Alquiler de equipo, donde también encontrarás los precios actuales y las sucursales en las que está disponible. El equipo para la lluvia y el resto de accesorios solo los ofrecemos en nuestra sucursal con personal en Mezná, cerca de Pelhřimov.'),
    ('fr',
     'La location d''équipement seul (sans moto), l''équipement de pluie et les autres accessoires ne sont proposés que dans notre agence avec personnel à Mezná, près de Pelhřimov. L''agence en libre-service de Velké Němčice ne remet l''équipement qu''avec une moto réservée, et uniquement casque, blouson avec dorsale, pantalon, gants, cagoule et bottes.',
     'La location d''équipement seul, sans moto (casque, blouson, pantalon, gants, bottes), se réserve en ligne dans la rubrique Location d''équipement, où figurent aussi les tarifs actuels et les agences où elle est disponible. L''équipement de pluie et les autres accessoires ne sont proposés que dans notre agence avec personnel à Mezná, près de Pelhřimov.'),
    ('nl',
     'Alleen uitrusting huren (zonder motor), regenkleding en overige extra uitrusting kan alleen in ons bemande filiaal in Mezná bij Pelhřimov. Het selfservicefiliaal in Velké Němčice geeft uitrusting alleen mee bij een gereserveerde motor — en alleen een helm, jas met rugprotector, broek, handschoenen, bivakmuts en laarzen.',
     'Alleen uitrusting huren zonder motor (helm, jas, broek, handschoenen, laarzen) reserveer je online in de rubriek Uitrusting huren, waar ook de actuele prijzen staan en de filialen waar het mogelijk is. Regenkleding en overige extra uitrusting is alleen beschikbaar in ons bemande filiaal in Mezná bij Pelhřimov.'),
    ('pl',
     'Wypożyczenie samego wyposażenia (bez motocykla), odzieży przeciwdeszczowej i innego wyposażenia dodatkowego oferujemy tylko w oddziale z obsługą w Mezná koło Pelhřimova. Oddział samoobsługowy w Velké Němčice wydaje wyposażenie tylko do zarezerwowanego motocykla — i to tylko kask, kurtkę z ochraniaczem pleców, spodnie, rękawice, kominiarkę i buty.',
     'Wypożyczenie samego wyposażenia bez motocykla (kask, kurtka, spodnie, rękawice, buty) rezerwuje się online w sekcji Wypożyczenie odzieży, gdzie jest też aktualny cennik i oddziały, w których jest dostępne. Odzież przeciwdeszczową i inne wyposażenie dodatkowe oferujemy tylko w oddziale z obsługą w Mezná koło Pelhřimova.'),
    ('uk',
     'Оренда лише спорядження (без мотоцикла), дощовий одяг та інше додаткове спорядження доступні лише на філії з персоналом у Mezná біля Pelhřimova. Філія самообслуговування у Velké Němčice видає спорядження лише разом із заброньованим мотоциклом — і тільки шолом, куртку із захистом спини, штани, рукавиці, балаклаву та черевики.',
     'Оренду лише спорядження без мотоцикла (шолом, куртка, штани, рукавиці, черевики) можна забронювати онлайн у розділі «Оренда спорядження» — там актуальні ціни та філії, де вона доступна. Дощовий одяг та інше додаткове спорядження доступні лише на філії з персоналом у Mezná біля Pelhřimova.')
  ) AS v(lang, old_txt, new_txt)
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items SET answer = replace(answer, f.old_txt, f.new_txt)
       WHERE id = '77557a0b-8c40-431e-a966-34848e738b7b' AND strpos(coalesce(answer, ''), f.old_txt) > 0;
    ELSE
      UPDATE public.faq_items
         SET translations = jsonb_set(translations, ARRAY[f.lang, 'answer'],
               to_jsonb(replace(translations -> f.lang ->> 'answer', f.old_txt, f.new_txt)))
       WHERE id = '77557a0b-8c40-431e-a966-34848e738b7b'
         AND strpos(coalesce(translations -> f.lang ->> 'answer', ''), f.old_txt) > 0;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    n_upd := n_upd + cnt;
  END LOOP;
  RAISE NOTICE 'faq 77557a0b výpůjčka výbavy: upraveno % odpovědí', n_upd;
END $$;

DO $$
BEGIN
  INSERT INTO public.app_settings (key, value)
  VALUES ('ai_kb_version', to_jsonb((extract(epoch FROM clock_timestamp()) * 1000)::bigint))
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ai_kb_version: %', SQLERRM;
END $$;
