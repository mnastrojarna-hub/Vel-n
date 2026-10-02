-- =============================================================================
-- FAQ: výbava k zapůjčení na samoobslužné pobočce (nepromoky jen v Mezné)
-- Migrace: 20261002_faq_self_service_gear.sql (DATOVÁ, bez změn schématu)
--
-- Zadání majitele 2026-10-02: na samoobslužné pobočce (Velké Němčice) se
-- půjčuje JEN helma, bunda s páteřákem, kalhoty, rukavice, kukla a boty;
-- nepromoky a ostatní doplňková výbava jen na obslužné pobočce (Mezná).
-- Čte web, appka i AI agenti (get_faq).
--
-- 1) 16fde840 „Půjčujete také nepromoky?“ a 77557a0b „Můžu si u vás půjčit jen
--    výbavu…?“ — na konec odpovědi (cs + každý existující překlad) se připojí
--    věta o samoobsluze. Připojuje se jen, když tam ještě není (2. běh = 0
--    změn); zbytek textu i ruční úpravy z Velína zůstávají.
-- 2) Nová otázka (conditions, sort 244, před 5b1e0c7a…c01 o výměně velikosti)
--    s překlady do 7 jazyků; pevné id + ON CONFLICT DO NOTHING = idempotentní.
-- =============================================================================

DO $$
DECLARE
  f     record;
  cnt   integer;
  n_upd integer := 0;
BEGIN
  FOR f IN
    SELECT v.fid::uuid AS fid, v.lang, '<div><br></div><div>' || v.txt || '</div>' AS add_txt FROM (VALUES
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'cs', 'Nepromoky půjčujeme jen na obslužné pobočce v Mezné u Pelhřimova. Na samoobslužné pobočce ve Velkých Němčicích k dispozici nejsou — tam si půjčíš jen helmu, bundu s páteřákem, kalhoty, rukavice, kuklu a boty.'),
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'en', 'Rain gear is only available at our staffed branch in Mezná near Pelhřimov. It is not available at the self-service branch in Velké Němčice — there you can only rent a helmet, a jacket with a back protector, trousers, gloves, a balaclava and boots.'),
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'de', 'Regenbekleidung verleihen wir nur in unserer Filiale mit Personal in Mezná bei Pelhřimov. In der Selbstbedienungs-Filiale in Velké Němčice ist sie nicht erhältlich — dort leihst du nur Helm, Jacke mit Rückenprotektor, Hose, Handschuhe, Sturmhaube und Stiefel.'),
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'es', 'El equipo para la lluvia solo lo prestamos en nuestra sucursal con personal en Mezná, cerca de Pelhřimov. En la sucursal de autoservicio de Velké Němčice no está disponible: allí solo puedes alquilar casco, chaqueta con protector de espalda, pantalones, guantes, braga y botas.'),
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'fr', 'L''équipement de pluie n''est prêté que dans notre agence avec personnel à Mezná, près de Pelhřimov. Il n''est pas disponible à l''agence en libre-service de Velké Němčice : on y loue uniquement casque, blouson avec dorsale, pantalon, gants, cagoule et bottes.'),
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'nl', 'Regenkleding lenen we alleen uit in ons bemande filiaal in Mezná bij Pelhřimov. Bij de selfservicefiliaal in Velké Němčice is die niet beschikbaar — daar huur je alleen een helm, jas met rugprotector, broek, handschoenen, bivakmuts en laarzen.'),
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'pl', 'Odzież przeciwdeszczową wypożyczamy tylko w oddziale z obsługą w Mezná koło Pelhřimova. W oddziale samoobsługowym w Velké Němčice nie jest dostępna — tam wypożyczysz tylko kask, kurtkę z ochraniaczem pleców, spodnie, rękawice, kominiarkę i buty.'),
    ('16fde840-124b-4d9b-9b28-8fef51f6cd63', 'uk', 'Дощовий одяг ми видаємо лише на філії з персоналом у Mezná біля Pelhřimova. На філії самообслуговування у Velké Němčice його немає — там можна взяти лише шолом, куртку із захистом спини, штани, рукавиці, балаклаву та черевики.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'cs', 'Nepromoky a další doplňkovou výbavu půjčujeme jen na obslužné pobočce v Mezné u Pelhřimova; na samoobslužné pobočce ve Velkých Němčicích je k dispozici jen helma, bunda s páteřákem, kalhoty, rukavice, kukla a boty.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'en', 'Rain gear and other additional equipment are only available at our staffed branch in Mezná near Pelhřimov; the self-service branch in Velké Němčice only offers a helmet, a jacket with a back protector, trousers, gloves, a balaclava and boots.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'de', 'Regenbekleidung und weiteres Zubehör verleihen wir nur in unserer Filiale mit Personal in Mezná bei Pelhřimov; in der Selbstbedienungs-Filiale in Velké Němčice gibt es nur Helm, Jacke mit Rückenprotektor, Hose, Handschuhe, Sturmhaube und Stiefel.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'es', 'El equipo para la lluvia y el resto de accesorios solo los prestamos en nuestra sucursal con personal en Mezná, cerca de Pelhřimov; en la sucursal de autoservicio de Velké Němčice solo hay casco, chaqueta con protector de espalda, pantalones, guantes, braga y botas.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'fr', 'L''équipement de pluie et les autres accessoires ne sont prêtés que dans notre agence avec personnel à Mezná, près de Pelhřimov ; l''agence en libre-service de Velké Němčice ne propose que casque, blouson avec dorsale, pantalon, gants, cagoule et bottes.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'nl', 'Regenkleding en overige extra uitrusting lenen we alleen uit in ons bemande filiaal in Mezná bij Pelhřimov; bij de selfservicefiliaal in Velké Němčice zijn alleen een helm, jas met rugprotector, broek, handschoenen, bivakmuts en laarzen beschikbaar.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'pl', 'Odzież przeciwdeszczową i pozostałe wyposażenie dodatkowe wypożyczamy tylko w oddziale z obsługą w Mezná koło Pelhřimova; w oddziale samoobsługowym w Velké Němčice dostępne są tylko kask, kurtka z ochraniaczem pleców, spodnie, rękawice, kominiarka i buty.'),
    ('77557a0b-8c40-431e-a966-34848e738b7b', 'uk', 'Дощовий одяг та інше додаткове спорядження ми видаємо лише на філії з персоналом у Mezná біля Pelhřimova; на філії самообслуговування у Velké Němčice доступні лише шолом, куртка із захистом спини, штани, рукавиці, балаклава та черевики.')
    ) AS v(fid, lang, txt)
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items SET answer = answer || f.add_txt
       WHERE id = f.fid AND strpos(coalesce(answer, ''), f.add_txt) = 0;
    ELSE
      UPDATE public.faq_items
         SET translations = jsonb_set(translations, ARRAY[f.lang, 'answer'],
               to_jsonb((translations -> f.lang ->> 'answer') || f.add_txt))
       WHERE id = f.fid
         AND translations -> f.lang ->> 'answer' IS NOT NULL
         AND strpos(translations -> f.lang ->> 'answer', f.add_txt) = 0;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    n_upd := n_upd + cnt;
    IF cnt = 0 THEN
      RAISE NOTICE 'faq % [%]: bez změny (už doplněno / překlad chybí) — přeskočeno', f.fid, f.lang;
    END IF;
  END LOOP;
  RAISE NOTICE 'faq nepromoky/samoobsluha: doplněno % odpovědí', n_upd;
END
$$;

INSERT INTO public.faq_items (id, category_key, category_label, question, answer, sort_order, featured_home, published, translations)
SELECT '5b1e0c7a-3f2d-4c8e-9a61-2d7f4e8b1c04'::uuid, c.category_key, c.category_label,
  $t$Jakou výbavu si můžu půjčit na samoobslužné pobočce?$t$,
  $t$Na samoobslužné pobočce ve Velkých Němčicích si v šatně vyzvedneš <strong>helmu, bundu s páteřákem, kalhoty, rukavice, kuklu a boty</strong> — podle toho, co sis objednal/a v rezervaci. <strong>Nepromoky</strong> ani další doplňkovou výbavu tady nepůjčujeme — ty jsou k dispozici jen na obslužné pobočce v Mezné u Pelhřimova. V motorce pak najdeš reflexní vestu, lékárničku, záznam o dopravní nehodě, kotoučový zámek a klíček k držáku telefonu.$t$,
  244, false, true,
  jsonb_build_object(
    'en', jsonb_build_object('question', $t$What gear can I rent at the self-service branch?$t$,
      'answer', $t$At the self-service branch in Velké Němčice you collect a <strong>helmet, a jacket with a back protector, trousers, gloves, a balaclava and boots</strong> from the locker room — according to what you ordered in your booking. <strong>Rain gear</strong> and other additional equipment are not rented out here — they are only available at our staffed branch in Mezná near Pelhřimov. On the motorcycle you will find a reflective vest, a first-aid kit, an accident report form, a disc lock and the key to the phone holder.$t$),
    'de', jsonb_build_object('question', $t$Welche Ausrüstung kann ich in der Selbstbedienungs-Filiale leihen?$t$,
      'answer', $t$In der Selbstbedienungs-Filiale in Velké Němčice holst du dir in der Umkleide <strong>Helm, Jacke mit Rückenprotektor, Hose, Handschuhe, Sturmhaube und Stiefel</strong> ab — je nachdem, was du in der Reservierung bestellt hast. <strong>Regenbekleidung</strong> und weiteres Zubehör verleihen wir hier nicht — das gibt es nur in unserer Filiale mit Personal in Mezná bei Pelhřimov. Am Motorrad findest du eine Warnweste, einen Verbandskasten, einen Unfallbericht, ein Bremsscheibenschloss und den Schlüssel zur Handyhalterung.$t$),
    'es', jsonb_build_object('question', $t$¿Qué equipo puedo alquilar en la sucursal de autoservicio?$t$,
      'answer', $t$En la sucursal de autoservicio de Velké Němčice recoges en el vestuario el <strong>casco, la chaqueta con protector de espalda, los pantalones, los guantes, la braga y las botas</strong>, según lo que hayas pedido en la reserva. El <strong>equipo para la lluvia</strong> y otros accesorios no se prestan aquí: solo están disponibles en nuestra sucursal con personal en Mezná, cerca de Pelhřimov. En la moto encontrarás un chaleco reflectante, un botiquín, un parte de accidente, un candado de disco y la llave del soporte del móvil.$t$),
    'fr', jsonb_build_object('question', $t$Quel équipement puis-je louer à l'agence en libre-service ?$t$,
      'answer', $t$À l'agence en libre-service de Velké Němčice, tu récupères au vestiaire <strong>casque, blouson avec dorsale, pantalon, gants, cagoule et bottes</strong>, selon ce que tu as commandé dans ta réservation. L'<strong>équipement de pluie</strong> et les autres accessoires n'y sont pas prêtés : ils ne sont disponibles que dans notre agence avec personnel à Mezná, près de Pelhřimov. Sur la moto, tu trouveras un gilet réfléchissant, une trousse de premiers secours, un constat d'accident, un bloque-disque et la clé du support de téléphone.$t$),
    'nl', jsonb_build_object('question', $t$Welke uitrusting kan ik huren bij de selfservicefiliaal?$t$,
      'answer', $t$Bij de selfservicefiliaal in Velké Němčice haal je in de kleedruimte een <strong>helm, jas met rugprotector, broek, handschoenen, bivakmuts en laarzen</strong> op — afhankelijk van wat je in je reservering hebt besteld. <strong>Regenkleding</strong> en overige extra uitrusting lenen we hier niet uit — die zijn alleen verkrijgbaar in ons bemande filiaal in Mezná bij Pelhřimov. Op de motor vind je een reflecterend hesje, een EHBO-kit, een schadeformulier, een schijfremslot en het sleuteltje van de telefoonhouder.$t$),
    'pl', jsonb_build_object('question', $t$Jakie wyposażenie mogę wypożyczyć w oddziale samoobsługowym?$t$,
      'answer', $t$W oddziale samoobsługowym w Velké Němčice odbierzesz w szatni <strong>kask, kurtkę z ochraniaczem pleców, spodnie, rękawice, kominiarkę i buty</strong> — zgodnie z tym, co zamówiłeś/aś w rezerwacji. <strong>Odzieży przeciwdeszczowej</strong> ani innego wyposażenia dodatkowego tu nie wypożyczamy — są dostępne tylko w oddziale z obsługą w Mezná koło Pelhřimova. W motocyklu znajdziesz kamizelkę odblaskową, apteczkę, formularz zgłoszenia wypadku, blokadę tarczy i kluczyk do uchwytu na telefon.$t$),
    'uk', jsonb_build_object('question', $t$Яке спорядження можна взяти на філії самообслуговування?$t$,
      'answer', $t$На філії самообслуговування у Velké Němčice ви забираєте в гардеробі <strong>шолом, куртку із захистом спини, штани, рукавиці, балаклаву та черевики</strong> — відповідно до того, що ви замовили в бронюванні. <strong>Дощовий одяг</strong> та інше додаткове спорядження тут не видаємо — воно доступне лише на філії з персоналом у Mezná біля Pelhřimova. У мотоциклі ви знайдете світловідбивний жилет, аптечку, бланк повідомлення про ДТП, замок на гальмівний диск і ключ від тримача телефону.$t$)
  )
FROM (
  SELECT coalesce((SELECT category_label FROM public.faq_items WHERE category_key = 'conditions' LIMIT 1), 'Podmínky') AS category_label,
         'conditions'::text AS category_key
) c
ON CONFLICT (id) DO NOTHING;
