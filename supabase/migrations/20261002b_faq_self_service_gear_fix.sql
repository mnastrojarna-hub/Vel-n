-- =============================================================================
-- FAQ: oprava vět o samoobslužné pobočce z 20261002_faq_self_service_gear.sql
-- Migrace: 20261002b_faq_self_service_gear_fix.sql (DATOVÁ, bez změn schématu)
--
-- Nálezy kontroly po nasazení 20261002 (2026-10-02):
-- 1) 77557a0b „Můžu si u vás půjčit jen výbavu, když mám motorku svoji?“ —
--    připojená věta „na samoobslužné pobočce … je k dispozici jen helma…“
--    v odpovědi o samostatné výpůjčce výbavy působila, že si výbavu bez
--    motorky lze vyzvednout i ve Velkých Němčicích (kód šatny vzniká jen
--    k rezervaci motorky a na pobočce není obsluha pro platbu na místě).
--    Nové znění: samostatná výpůjčka výbavy, nepromoky a doplňky jen v Mezné;
--    samoobsluha vydává výbavu jen k rezervované motorce (cs + 7 překladů).
-- 2) 16fde840 „Půjčujete také nepromoky?“ — odpověď vyká, připojená věta
--    tykala → vykání (cs, de, es, nl, pl; en/fr neutrální, uk překlad nemá).
-- Nahrazuje se JEN přesný text připojený migrací 20261002 (ověřeno proti
-- živým datům REST 2026-10-02) — ruční úpravu z Velína nepřepíše; 2. běh =
-- 0 změn.
-- =============================================================================

DO $$
DECLARE
  f     record;
  cnt   integer;
  n_upd integer := 0;
BEGIN
  FOR f IN
    SELECT v.fid::uuid AS fid, v.lang, v.old_txt, v.new_txt FROM (VALUES
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'cs',
     'Nepromoky půjčujeme jen na obslužné pobočce v Mezné u Pelhřimova. Na samoobslužné pobočce ve Velkých Němčicích k dispozici nejsou — tam si půjčíš jen helmu, bundu s páteřákem, kalhoty, rukavice, kuklu a boty.',
     'Nepromoky půjčujeme jen na obslužné pobočce v Mezné u Pelhřimova. Na samoobslužné pobočce ve Velkých Němčicích k dispozici nejsou — tam si můžete půjčit jen helmu, bundu s páteřákem, kalhoty, rukavice, kuklu a boty.'),
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'de',
     'Regenbekleidung verleihen wir nur in unserer Filiale mit Personal in Mezná bei Pelhřimov. In der Selbstbedienungs-Filiale in Velké Němčice ist sie nicht erhältlich — dort leihst du nur Helm, Jacke mit Rückenprotektor, Hose, Handschuhe, Sturmhaube und Stiefel.',
     'Regenbekleidung verleihen wir nur in unserer Filiale mit Personal in Mezná bei Pelhřimov. In der Selbstbedienungs-Filiale in Velké Němčice ist sie nicht erhältlich — dort können Sie nur Helm, Jacke mit Rückenprotektor, Hose, Handschuhe, Sturmhaube und Stiefel leihen.'),
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'es',
     'El equipo para la lluvia solo lo prestamos en nuestra sucursal con personal en Mezná, cerca de Pelhřimov. En la sucursal de autoservicio de Velké Němčice no está disponible: allí solo puedes alquilar casco, chaqueta con protector de espalda, pantalones, guantes, braga y botas.',
     'El equipo para la lluvia solo lo prestamos en nuestra sucursal con personal en Mezná, cerca de Pelhřimov. En la sucursal de autoservicio de Velké Němčice no está disponible: allí solo puede alquilar casco, chaqueta con protector de espalda, pantalones, guantes, braga y botas.'),
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'nl',
     'Regenkleding lenen we alleen uit in ons bemande filiaal in Mezná bij Pelhřimov. Bij de selfservicefiliaal in Velké Němčice is die niet beschikbaar — daar huur je alleen een helm, jas met rugprotector, broek, handschoenen, bivakmuts en laarzen.',
     'Regenkleding lenen we alleen uit in ons bemande filiaal in Mezná bij Pelhřimov. Bij de selfservicefiliaal in Velké Němčice is die niet beschikbaar — daar kunt u alleen een helm, jas met rugprotector, broek, handschoenen, bivakmuts en laarzen huren.'),
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'pl',
     'Odzież przeciwdeszczową wypożyczamy tylko w oddziale z obsługą w Mezná koło Pelhřimova. W oddziale samoobsługowym w Velké Němčice nie jest dostępna — tam wypożyczysz tylko kask, kurtkę z ochraniaczem pleców, spodnie, rękawice, kominiarkę i buty.',
     'Odzież przeciwdeszczową wypożyczamy tylko w oddziale z obsługą w Mezná koło Pelhřimova. W oddziale samoobsługowym w Velké Němčice nie jest dostępna — tam można wypożyczyć tylko kask, kurtkę z ochraniaczem pleców, spodnie, rękawice, kominiarkę i buty.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'cs',
     'Nepromoky a další doplňkovou výbavu půjčujeme jen na obslužné pobočce v Mezné u Pelhřimova; na samoobslužné pobočce ve Velkých Němčicích je k dispozici jen helma, bunda s páteřákem, kalhoty, rukavice, kukla a boty.',
     'Samostatnou výpůjčku výbavy (bez motorky), nepromoky i další doplňkovou výbavu nabízíme jen na obslužné pobočce v Mezné u Pelhřimova. Samoobslužná pobočka ve Velkých Němčicích vydává výbavu jen k rezervované motorce, a to jen helmu, bundu s páteřákem, kalhoty, rukavice, kuklu a boty.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'en',
     'Rain gear and other additional equipment are only available at our staffed branch in Mezná near Pelhřimov; the self-service branch in Velké Němčice only offers a helmet, a jacket with a back protector, trousers, gloves, a balaclava and boots.',
     'Gear-only rental (without a motorcycle), rain gear and other additional equipment are only available at our staffed branch in Mezná near Pelhřimov. The self-service branch in Velké Němčice only issues gear together with a booked motorcycle — and only a helmet, a jacket with a back protector, trousers, gloves, a balaclava and boots.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'de',
     'Regenbekleidung und weiteres Zubehör verleihen wir nur in unserer Filiale mit Personal in Mezná bei Pelhřimov; in der Selbstbedienungs-Filiale in Velké Němčice gibt es nur Helm, Jacke mit Rückenprotektor, Hose, Handschuhe, Sturmhaube und Stiefel.',
     'Ausrüstung ohne Motorrad, Regenbekleidung und weiteres Zubehör verleihen wir nur in unserer Filiale mit Personal in Mezná bei Pelhřimov. Die Selbstbedienungs-Filiale in Velké Němčice gibt Ausrüstung nur zu einem reservierten Motorrad aus — und zwar nur Helm, Jacke mit Rückenprotektor, Hose, Handschuhe, Sturmhaube und Stiefel.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'es',
     'El equipo para la lluvia y el resto de accesorios solo los prestamos en nuestra sucursal con personal en Mezná, cerca de Pelhřimov; en la sucursal de autoservicio de Velké Němčice solo hay casco, chaqueta con protector de espalda, pantalones, guantes, braga y botas.',
     'El alquiler de solo equipo (sin moto), el equipo para la lluvia y el resto de accesorios solo los ofrecemos en nuestra sucursal con personal en Mezná, cerca de Pelhřimov. La sucursal de autoservicio de Velké Němčice solo entrega equipo junto con una moto reservada, y únicamente casco, chaqueta con protector de espalda, pantalones, guantes, braga y botas.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'fr',
     'L''équipement de pluie et les autres accessoires ne sont prêtés que dans notre agence avec personnel à Mezná, près de Pelhřimov ; l''agence en libre-service de Velké Němčice ne propose que casque, blouson avec dorsale, pantalon, gants, cagoule et bottes.',
     'La location d''équipement seul (sans moto), l''équipement de pluie et les autres accessoires ne sont proposés que dans notre agence avec personnel à Mezná, près de Pelhřimov. L''agence en libre-service de Velké Němčice ne remet l''équipement qu''avec une moto réservée, et uniquement casque, blouson avec dorsale, pantalon, gants, cagoule et bottes.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'nl',
     'Regenkleding en overige extra uitrusting lenen we alleen uit in ons bemande filiaal in Mezná bij Pelhřimov; bij de selfservicefiliaal in Velké Němčice zijn alleen een helm, jas met rugprotector, broek, handschoenen, bivakmuts en laarzen beschikbaar.',
     'Alleen uitrusting huren (zonder motor), regenkleding en overige extra uitrusting kan alleen in ons bemande filiaal in Mezná bij Pelhřimov. Het selfservicefiliaal in Velké Němčice geeft uitrusting alleen mee bij een gereserveerde motor — en alleen een helm, jas met rugprotector, broek, handschoenen, bivakmuts en laarzen.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'pl',
     'Odzież przeciwdeszczową i pozostałe wyposażenie dodatkowe wypożyczamy tylko w oddziale z obsługą w Mezná koło Pelhřimova; w oddziale samoobsługowym w Velké Němčice dostępne są tylko kask, kurtka z ochraniaczem pleców, spodnie, rękawice, kominiarka i buty.',
     'Wypożyczenie samego wyposażenia (bez motocykla), odzieży przeciwdeszczowej i innego wyposażenia dodatkowego oferujemy tylko w oddziale z obsługą w Mezná koło Pelhřimova. Oddział samoobsługowy w Velké Němčice wydaje wyposażenie tylko do zarezerwowanego motocykla — i to tylko kask, kurtkę z ochraniaczem pleców, spodnie, rękawice, kominiarkę i buty.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'uk',
     'Дощовий одяг та інше додаткове спорядження ми видаємо лише на філії з персоналом у Mezná біля Pelhřimova; на філії самообслуговування у Velké Němčice доступні лише шолом, куртка із захистом спини, штани, рукавиці, балаклава та черевики.',
     'Оренда лише спорядження (без мотоцикла), дощовий одяг та інше додаткове спорядження доступні лише на філії з персоналом у Mezná біля Pelhřimova. Філія самообслуговування у Velké Němčice видає спорядження лише разом із заброньованим мотоциклом — і тільки шолом, куртку із захистом спини, штани, рукавиці, балаклаву та черевики.')
    ) AS v(fid, lang, old_txt, new_txt)
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items SET answer = replace(answer, f.old_txt, f.new_txt)
       WHERE id = f.fid AND strpos(coalesce(answer, ''), f.old_txt) > 0;
    ELSE
      UPDATE public.faq_items
         SET translations = jsonb_set(translations, ARRAY[f.lang, 'answer'],
               to_jsonb(replace(translations -> f.lang ->> 'answer', f.old_txt, f.new_txt)))
       WHERE id = f.fid
         AND strpos(coalesce(translations -> f.lang ->> 'answer', ''), f.old_txt) > 0;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    n_upd := n_upd + cnt;
    IF cnt = 0 THEN
      RAISE NOTICE 'faq % [%]: původní věta nenalezena (už opraveno / ručně upraveno) — přeskočeno', f.fid, f.lang;
    END IF;
  END LOOP;
  RAISE NOTICE 'faq oprava vět o samoobsluze: upraveno % odpovědí', n_upd;
END
$$;
