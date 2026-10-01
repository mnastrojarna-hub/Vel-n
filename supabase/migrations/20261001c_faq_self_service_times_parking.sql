-- =============================================================================
-- FAQ: samoobslužná pobočka — bez času převzetí/vrácení (smlouva 00:01–24:00),
-- bez přistavení/odvozu, parkování zdarma ve Velkých Němčicích
-- Migrace: 20261001c_faq_self_service_times_parking.sql (DATOVÁ, bez schématu)
--
-- Zadání majitele 2026-10-01: u samoobslužné pobočky web ani appka nechtějí čas
-- převzetí ani vrácení (smlouva 00:01–24:00, skutečný čas převzetí zapíše
-- předávací protokol); přistavení ani odvoz se u ní nenabízí; u pobočky Velké
-- Němčice je parkování po celou dobu výpůjčky zdarma.
--
-- 1) db5d0df7 (parkování) a e7079920 (kde probíhá vyzvednutí) — na konec
--    odpovědi (cs + každý existující překlad) se doplní věta o Velkých
--    Němčicích; řádek/jazyk, který už „Němčic“ obsahuje, se přeskočí
--    (idempotentní, ruční úpravy z Velína zůstanou).
-- 2) Dvě nové otázky (pevná id + ON CONFLICT DO NOTHING).
-- =============================================================================

DO $$
DECLARE
  f   record;
  cnt integer;
  n   integer := 0;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
    ('db5d0df7-143d-4c4e-9a44-2f05f738fc8b', 'cs', $t$ Na samoobslužné pobočce ve Velkých Němčicích můžeš u pobočky parkovat po celou dobu výpůjčky také zdarma.$t$),
    ('db5d0df7-143d-4c4e-9a44-2f05f738fc8b', 'en', $t$ At the self-service branch in Velké Němčice you can also park at the branch free of charge for the entire rental period.$t$),
    ('db5d0df7-143d-4c4e-9a44-2f05f738fc8b', 'de', $t$ An der Selbstbedienungs-Filiale in Velké Němčice kannst du ebenfalls während der gesamten Mietdauer kostenlos direkt an der Filiale parken.$t$),
    ('db5d0df7-143d-4c4e-9a44-2f05f738fc8b', 'es', $t$ En la sucursal de autoservicio de Velké Němčice también puedes aparcar junto a la sucursal gratis durante todo el período de alquiler.$t$),
    ('db5d0df7-143d-4c4e-9a44-2f05f738fc8b', 'fr', $t$ À l'agence en libre-service de Velké Němčice, vous pouvez également vous garer gratuitement près de l'agence pendant toute la durée de la location.$t$),
    ('db5d0df7-143d-4c4e-9a44-2f05f738fc8b', 'nl', $t$ Bij het selfservicefiliaal in Velké Němčice kun je ook de hele huurperiode gratis bij het filiaal parkeren.$t$),
    ('db5d0df7-143d-4c4e-9a44-2f05f738fc8b', 'pl', $t$ Przy oddziale samoobsługowym w Velké Němčice możesz również parkować bezpłatnie przez cały czas wynajmu.$t$),
    ('db5d0df7-143d-4c4e-9a44-2f05f738fc8b', 'uk', $t$ Біля філії самообслуговування у Velké Němčice можна також безкоштовно паркуватися протягом усього часу оренди.$t$),
    ('e7079920-f08c-4b08-b52a-9b8623909035', 'cs', $t$ Motorky ze samoobslužné pobočky Velké Němčice (Boudky, 691 63 Velké Němčice, u Brna) se přebírají i vracejí jen přímo na této pobočce, kdykoliv 24/7 pomocí kódů z aplikace — přistavení ani odvoz u nich nenabízíme.$t$),
    ('e7079920-f08c-4b08-b52a-9b8623909035', 'en', $t$ Motorcycles from the self-service branch in Velké Němčice (Boudky, 691 63 Velké Němčice, near Brno) are picked up and returned only at that branch, any time 24/7 using codes from the app — delivery or collection is not offered for them.$t$),
    ('e7079920-f08c-4b08-b52a-9b8623909035', 'de', $t$ Motorräder der Selbstbedienungs-Filiale Velké Němčice (Boudky, 691 63 Velké Němčice, bei Brno) werden nur direkt in dieser Filiale übernommen und zurückgegeben, jederzeit rund um die Uhr mit Codes aus der App — Zustellung oder Abholung bieten wir für sie nicht an.$t$),
    ('e7079920-f08c-4b08-b52a-9b8623909035', 'es', $t$ Las motos de la sucursal de autoservicio de Velké Němčice (Boudky, 691 63 Velké Němčice, cerca de Brno) se recogen y devuelven solo en esa sucursal, en cualquier momento 24/7 con los códigos de la aplicación; para ellas no ofrecemos entrega ni recogida a domicilio.$t$),
    ('e7079920-f08c-4b08-b52a-9b8623909035', 'fr', $t$ Les motos de l'agence en libre-service de Velké Němčice (Boudky, 691 63 Velké Němčice, près de Brno) se retirent et se restituent uniquement à cette agence, à tout moment 24h/24 et 7j/7 avec les codes de l'application — la livraison et l'enlèvement ne sont pas proposés pour elles.$t$),
    ('e7079920-f08c-4b08-b52a-9b8623909035', 'nl', $t$ Motoren van het selfservicefiliaal Velké Němčice (Boudky, 691 63 Velké Němčice, bij Brno) worden alleen bij dat filiaal opgehaald en teruggebracht, altijd 24/7 met codes uit de app — bezorging of ophalen bieden we voor deze motoren niet aan.$t$),
    ('e7079920-f08c-4b08-b52a-9b8623909035', 'pl', $t$ Motocykle z oddziału samoobsługowego Velké Němčice (Boudky, 691 63 Velké Němčice, koło Brna) odbiera się i zwraca wyłącznie w tym oddziale, o każdej porze 24/7 za pomocą kodów z aplikacji — dostawy ani odbioru dla nich nie oferujemy.$t$)
    ) AS v(id, lang, add_txt)
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items SET answer = answer || f.add_txt
       WHERE id = f.id::uuid AND strpos(answer, 'Němčic') = 0;
    ELSE
      UPDATE public.faq_items
         SET translations = jsonb_set(translations, ARRAY[f.lang, 'answer'],
               to_jsonb((translations -> f.lang ->> 'answer') || f.add_txt))
       WHERE id = f.id::uuid
         AND translations -> f.lang ->> 'answer' IS NOT NULL
         AND strpos(translations -> f.lang ->> 'answer', 'Němčic') = 0;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    n := n + cnt;
  END LOOP;
  RAISE NOTICE 'faq parkování / místo vyzvednutí: doplněno % jazykových verzí', n;
END
$$;

INSERT INTO public.faq_items (id, category_key, category_label, question, answer, sort_order, featured_home, published, translations)
SELECT v.id::uuid, v.cat,
  coalesce((SELECT category_label FROM public.faq_items WHERE category_key = v.cat LIMIT 1), v.cat_fallback),
  v.q, v.a, v.sort, false, true, v.tr::jsonb
FROM (VALUES
  ('5b1e0c7a-3f2d-4c8e-9a61-2d7f4e8b1c02', 'borrowing', 'Půjčení', 135,
   $t$Musím u samoobslužné pobočky zadávat čas převzetí a vrácení?$t$,
   $t$Ne. U samoobslužné pobočky ve Velkých Němčicích web ani aplikace čas převzetí ani vrácení nechtějí — motorku si vyzvedneš kdykoliv během prvního dne výpůjčky a vrátíš kdykoliv během posledního dne, 24/7 pomocí kódů z aplikace. Ve smlouvě je proto výpůjčka vždy <strong>od 00:01 do 24:00</strong> a skutečný čas převzetí se zapíše do předávacího protokolu, který podepíšeš na displeji pobočky.$t$,
   $j${
    "en": {"question": "Do I have to enter a pickup and return time at the self-service branch?", "answer": "No. For the self-service branch in Velké Němčice, neither the website nor the app asks for a pickup or return time — you pick up the motorcycle any time on the first day of the rental and return it any time on the last day, 24/7 using codes from the app. The contract therefore always states the rental <strong>from 00:01 to 24:00</strong>, and the actual pickup time is recorded in the handover protocol you sign on the branch display."},
    "de": {"question": "Muss ich an der Selbstbedienungs-Filiale eine Übernahme- und Rückgabezeit angeben?", "answer": "Nein. Bei der Selbstbedienungs-Filiale in Velké Němčice fragen weder Website noch App nach einer Übernahme- oder Rückgabezeit — du holst das Motorrad jederzeit am ersten Miettag ab und gibst es jederzeit am letzten Tag zurück, rund um die Uhr mit Codes aus der App. Im Vertrag steht deshalb immer <strong>von 00:01 bis 24:00</strong>, und die tatsächliche Übernahmezeit wird im Übergabeprotokoll festgehalten, das du am Display der Filiale unterschreibst."},
    "es": {"question": "¿Tengo que indicar la hora de recogida y devolución en la sucursal de autoservicio?", "answer": "No. En la sucursal de autoservicio de Velké Němčice ni la web ni la aplicación piden hora de recogida ni de devolución: recoges la moto en cualquier momento del primer día del alquiler y la devuelves en cualquier momento del último día, 24/7 con los códigos de la aplicación. Por eso el contrato indica siempre el alquiler <strong>de 00:01 a 24:00</strong> y la hora real de recogida queda registrada en el protocolo de entrega que firmas en la pantalla de la sucursal."},
    "fr": {"question": "Dois-je indiquer une heure de retrait et de restitution à l'agence en libre-service ?", "answer": "Non. Pour l'agence en libre-service de Velké Němčice, ni le site ni l'application ne demandent d'heure de retrait ou de restitution : tu récupères la moto à tout moment le premier jour de la location et tu la rends à tout moment le dernier jour, 24h/24 et 7j/7 avec les codes de l'application. Le contrat indique donc toujours la location <strong>de 00:01 à 24:00</strong>, et l'heure réelle du retrait est inscrite dans le protocole de remise que tu signes sur l'écran de l'agence."},
    "nl": {"question": "Moet ik bij het selfservicefiliaal een ophaal- en inlevertijd opgeven?", "answer": "Nee. Voor het selfservicefiliaal in Velké Němčice vragen de website en de app geen ophaal- of inlevertijd — je haalt de motor op elk moment van de eerste huurdag op en brengt hem op elk moment van de laatste dag terug, 24/7 met codes uit de app. In het contract staat daarom altijd <strong>van 00:01 tot 24:00</strong>, en de werkelijke ophaaltijd wordt vastgelegd in het overdrachtsprotocol dat je op het scherm van het filiaal ondertekent."},
    "pl": {"question": "Czy w oddziale samoobsługowym muszę podawać godzinę odbioru i zwrotu?", "answer": "Nie. W oddziale samoobsługowym w Velké Němčice ani strona, ani aplikacja nie wymagają godziny odbioru ani zwrotu — motocykl odbierzesz o dowolnej porze pierwszego dnia wynajmu i zwrócisz o dowolnej porze ostatniego dnia, 24/7 za pomocą kodów z aplikacji. W umowie jest więc zawsze wynajem <strong>od 00:01 do 24:00</strong>, a rzeczywista godzina odbioru zostaje zapisana w protokole wydania, który podpisujesz na wyświetlaczu oddziału."},
    "uk": {"question": "Чи потрібно на філії самообслуговування вказувати час отримання та повернення?", "answer": "Ні. Для філії самообслуговування у Velké Němčice ні сайт, ні застосунок не запитують час отримання чи повернення — мотоцикл можна забрати будь-коли в перший день оренди й повернути будь-коли в останній день, 24/7 за кодами із застосунку. Тому в договорі завжди вказано оренду <strong>з 00:01 до 24:00</strong>, а фактичний час отримання записується в протокол передачі, який ви підписуєте на дисплеї філії."}
   }$j$),
  ('5b1e0c7a-3f2d-4c8e-9a61-2d7f4e8b1c03', 'delivery', 'Přistavení', 5,
   $t$Nabízíte přistavení nebo odvoz motorky i u samoobslužné pobočky?$t$,
   $t$Ne. Motorky ze samoobslužné pobočky ve Velkých Němčicích se přebírají i vracejí jen přímo na pobočce — přistavení ani odvoz u nich nenabízíme, a proto je web ani aplikace v rezervaci nechtějí. Přistavení a odvoz na adresu nabízíme u motorek z obslužné pobočky v Mezné u Pelhřimova.$t$,
   $j${
    "en": {"question": "Do you offer delivery or collection of the motorcycle for the self-service branch too?", "answer": "No. Motorcycles from the self-service branch in Velké Němčice are picked up and returned only at the branch — we do not offer delivery or collection for them, so neither the website nor the app asks for it in the booking. Delivery and collection at an address are offered for motorcycles from our staffed branch in Mezná near Pelhřimov."},
    "de": {"question": "Bieten Sie Zustellung oder Abholung des Motorrads auch bei der Selbstbedienungs-Filiale an?", "answer": "Nein. Motorräder der Selbstbedienungs-Filiale in Velké Němčice werden nur direkt in der Filiale übernommen und zurückgegeben — Zustellung oder Abholung bieten wir für sie nicht an, deshalb fragen Website und App in der Reservierung auch nicht danach. Zustellung und Abholung an einer Adresse bieten wir für Motorräder unserer Filiale mit Personal in Mezná bei Pelhřimov an."},
    "es": {"question": "¿Ofrecéis entrega o recogida de la moto también en la sucursal de autoservicio?", "answer": "No. Las motos de la sucursal de autoservicio de Velké Němčice se recogen y devuelven solo en la sucursal: no ofrecemos entrega ni recogida para ellas, por lo que ni la web ni la aplicación lo piden en la reserva. La entrega y recogida en una dirección la ofrecemos para las motos de nuestra sucursal con personal en Mezná, cerca de Pelhřimov."},
    "fr": {"question": "Proposez-vous la livraison ou l'enlèvement de la moto aussi pour l'agence en libre-service ?", "answer": "Non. Les motos de l'agence en libre-service de Velké Němčice se retirent et se restituent uniquement à l'agence — nous ne proposons ni livraison ni enlèvement pour elles, c'est pourquoi ni le site ni l'application ne le demandent lors de la réservation. La livraison et l'enlèvement à une adresse sont proposés pour les motos de notre agence avec personnel à Mezná, près de Pelhřimov."},
    "nl": {"question": "Bieden jullie ook bezorging of ophalen van de motor aan bij het selfservicefiliaal?", "answer": "Nee. Motoren van het selfservicefiliaal in Velké Němčice worden alleen bij het filiaal opgehaald en teruggebracht — bezorging of ophalen bieden we voor deze motoren niet aan, daarom vragen de website en de app er bij de reservering ook niet naar. Bezorging en ophalen op een adres bieden we aan voor motoren van ons bemande filiaal in Mezná bij Pelhřimov."},
    "pl": {"question": "Czy oferujecie dostawę lub odbiór motocykla także w przypadku oddziału samoobsługowego?", "answer": "Nie. Motocykle z oddziału samoobsługowego w Velké Němčice odbiera się i zwraca wyłącznie w oddziale — dostawy ani odbioru dla nich nie oferujemy, dlatego ani strona, ani aplikacja nie pytają o to przy rezerwacji. Dostawę i odbiór pod adres oferujemy dla motocykli z naszego oddziału z obsługą w Mezná koło Pelhřimova."},
    "uk": {"question": "Чи пропонуєте доставку або вивезення мотоцикла і для філії самообслуговування?", "answer": "Ні. Мотоцикли з філії самообслуговування у Velké Němčice отримують і повертають лише безпосередньо на філії — доставку чи вивезення для них не пропонуємо, тому ні сайт, ні застосунок під час бронювання цього не вимагають. Доставку та вивезення за адресою пропонуємо для мотоциклів з нашої філії з персоналом у Mezná біля Pelhřimova."}
   }$j$)
) AS v(id, cat, cat_fallback, sort, q, a, tr)
ON CONFLICT (id) DO NOTHING;
