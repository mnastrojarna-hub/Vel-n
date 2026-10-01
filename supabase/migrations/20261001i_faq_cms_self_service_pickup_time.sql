-- =============================================================================
-- FAQ + CMS: samoobslužná pobočka — čas VYZVEDNUTÍ se zase volí (sleva 50 % na
-- 1. den od 12:00 → kiosk vydá až od 12:00), čas vrácení ne (do 24:00)
-- Migrace: 20261001i_faq_cms_self_service_pickup_time.sql (DATOVÁ, bez schématu)
--
-- Zadání majitele 2026-10-01 večer (ruší dopolední pravidlo z 20261001c „bez
-- času převzetí i vrácení“): zákazník volí čas vyzvednutí, který řídí slevu
-- 50 % na 1. den (vyzvednutí od 12:00, výpůjčka 2+ dny); rezervaci se slevou
-- vydá kiosk (šatna i motorka) až od 12:00 dne začátku (20261001h). Čas vrácení
-- se nevolí — vrácení kdykoliv poslední den do 24:00. Smlouva 00:01–24:00, se
-- slevou za vyzvednutí od 12:00 12:00–24:00.
--
-- 1) FAQ 5b1e0c7a…c02 (vložena 20261001c): otázka + odpověď cs a každý překlad.
--    Každé pole se přepíše JEN, pokud je přesně text z 20261001c (md5 = otisk
--    toho textu) — úpravy z Velína zůstanou, opakovaný běh nic nezmění.
-- 2) e7079920 (věta doplněná 20261001c „… kdykoliv 24/7 pomocí kódů …“):
--    hlídaný REPLACE po jazycích (jen kde stará fráze ještě je).
-- 3) cms_variables web.pobocky.branches.1.{hours,seo_description,steps}: nový
--    text + překlady JEN tam, kde uložená hodnota = výchozí text Velína před
--    touto změnou (md5 defaultu z velin/src/pages/cms/webTextsPobocky.js).
-- Idempotentní.
-- =============================================================================

DO $$
DECLARE
  f   record;
  cnt integer;
  n   integer := 0;
  c_faq constant uuid := '5b1e0c7a-3f2d-4c8e-9a61-2d7f4e8b1c02';
BEGIN
  -- ── 1) FAQ: čas převzetí / vrácení na samoobslužné pobočce ────────────────
  FOR f IN
    SELECT * FROM (VALUES
    ('cs', '564f6286470b110e670ec1288f7ab930', 'b8c2976542de8b544f04ee731b7ee9e1',
     $t$Jak je to u samoobslužné pobočky s časem převzetí a vrácení?$t$,
     $t$U samoobslužné pobočky ve Velkých Němčicích si v rezervaci (na webu i v aplikaci) volíš jen <strong>čas vyzvednutí</strong>. Ten rozhoduje o slevě: při vyzvednutí od 12:00 a výpůjčce na 2 a více dní máš <strong>1. den za polovinu</strong> — kiosk pobočky ti pak výbavu ze šatny i motorku vydá až od 12:00 v den vyzvednutí. Potřebuješ motorku dřív? V rezervaci změň čas vyzvednutí na dřívější — sleva zanikne, rozdíl doplatíš a kódy platí hned. Čas vrácení nevolíš: motorku vrátíš kdykoliv poslední den výpůjčky do 24:00, 24/7 pomocí kódů z aplikace. Ve smlouvě je výpůjčka <strong>od 00:01 do 24:00</strong>, u rezervace se slevou za vyzvednutí od 12:00 <strong>od 12:00 do 24:00</strong>; skutečný čas převzetí se zapíše do předávacího protokolu, který podepíšeš na displeji pobočky.$t$),
    ('en', '69ce81523303dff2f04c07cf27d44015', 'c70218f6b3352905f758d60381c4d155',
     $t$How do pickup and return times work at the self-service branch?$t$,
     $t$At the self-service branch in Velké Němčice you only choose the <strong>pickup time</strong> in your booking (on the website or in the app). It determines the discount: if you pick up from 12:00 and rent for 2 or more days, <strong>the 1st day is half price</strong> — the branch kiosk then releases your gear from the locker and the motorcycle only from 12:00 on the pickup day. Need the motorcycle earlier? Change the pickup time in your booking to an earlier one — the discount is cancelled, you pay the difference and the codes work immediately. You don't choose a return time: you return the motorcycle any time on the last day of the rental until 24:00, 24/7 using codes from the app. The contract states the rental <strong>from 00:01 to 24:00</strong>, or <strong>from 12:00 to 24:00</strong> for a booking with the pickup-from-12:00 discount; the actual pickup time is recorded in the handover protocol you sign on the branch display.$t$),
    ('de', '845884c6aaa2a62b454f54d94e7c07a3', '89344be24f423845999dfe36d773f74d',
     $t$Wie ist das mit der Übernahme- und Rückgabezeit an der Selbstbedienungs-Filiale?$t$,
     $t$An der Selbstbedienungs-Filiale in Velké Němčice wählst du in der Reservierung (auf der Website oder in der App) nur die <strong>Abholzeit</strong>. Sie entscheidet über den Rabatt: Bei Abholung ab 12:00 und einer Miete von 2 oder mehr Tagen ist <strong>der 1. Tag zum halben Preis</strong> — der Kiosk der Filiale gibt dir Ausrüstung und Motorrad dann erst ab 12:00 am Abholtag heraus. Brauchst du das Motorrad früher? Ändere in der Reservierung die Abholzeit auf eine frühere — der Rabatt entfällt, du zahlst die Differenz nach und die Codes gelten sofort. Eine Rückgabezeit wählst du nicht: Du gibst das Motorrad jederzeit am letzten Miettag bis 24:00 zurück, rund um die Uhr mit Codes aus der App. Im Vertrag steht die Miete <strong>von 00:01 bis 24:00</strong>, bei einer Reservierung mit Rabatt für Abholung ab 12:00 <strong>von 12:00 bis 24:00</strong>; die tatsächliche Übernahmezeit wird im Übergabeprotokoll festgehalten, das du am Display der Filiale unterschreibst.$t$),
    ('es', '58ad18e5b153e9ef06714134b8a0440d', '8ea32f8dc17ab0a30ad7883906911c4f',
     $t$¿Cómo funcionan las horas de recogida y devolución en la sucursal de autoservicio?$t$,
     $t$En la sucursal de autoservicio de Velké Němčice solo eliges en la reserva (en la web o en la aplicación) la <strong>hora de recogida</strong>. Esta decide el descuento: si recoges a partir de las 12:00 y alquilas 2 o más días, <strong>el 1.er día es a mitad de precio</strong>; el quiosco de la sucursal te entrega entonces el equipamiento y la moto solo a partir de las 12:00 del día de recogida. ¿Necesitas la moto antes? Cambia en la reserva la hora de recogida por una anterior: el descuento se anula, pagas la diferencia y los códigos funcionan de inmediato. La hora de devolución no la eliges: devuelves la moto en cualquier momento del último día del alquiler hasta las 24:00, 24/7 con los códigos de la aplicación. El contrato indica el alquiler <strong>de 00:01 a 24:00</strong> y, en una reserva con el descuento por recogida desde las 12:00, <strong>de 12:00 a 24:00</strong>; la hora real de recogida queda registrada en el protocolo de entrega que firmas en la pantalla de la sucursal.$t$),
    ('fr', '86a44ece6f2f69f1296dd68f41ba5d0b', '40a3afe26f2c66518e053ce954b0ac4a',
     $t$Comment fonctionnent les heures de retrait et de restitution à l'agence en libre-service ?$t$,
     $t$À l'agence en libre-service de Velké Němčice, tu choisis dans la réservation (sur le site ou dans l'application) uniquement l'<strong>heure de retrait</strong>. C'est elle qui décide de la remise : pour un retrait à partir de 12:00 et une location de 2 jours ou plus, <strong>le 1er jour est à moitié prix</strong> — la borne de l'agence ne te remet alors l'équipement et la moto qu'à partir de 12:00 le jour du retrait. Tu as besoin de la moto plus tôt ? Avance l'heure de retrait dans ta réservation : la remise est annulée, tu paies la différence et les codes fonctionnent immédiatement. Tu ne choisis pas d'heure de restitution : tu rends la moto à tout moment le dernier jour de la location jusqu'à 24:00, 24h/24 et 7j/7 avec les codes de l'application. Le contrat indique la location <strong>de 00:01 à 24:00</strong>, ou <strong>de 12:00 à 24:00</strong> pour une réservation bénéficiant de la remise pour retrait à partir de 12:00 ; l'heure réelle du retrait est inscrite dans le protocole de remise que tu signes sur l'écran de l'agence.$t$),
    ('nl', '399d48a81bb7c4d79b67447560e675b5', 'aa4f09fd1308ab9b7eda87dbe1757aa5',
     $t$Hoe zit het met de ophaal- en inlevertijd bij het selfservicefiliaal?$t$,
     $t$Bij het selfservicefiliaal in Velké Němčice kies je in de reservering (op de website of in de app) alleen de <strong>ophaaltijd</strong>. Die bepaalt de korting: haal je op vanaf 12:00 en huur je 2 of meer dagen, dan is <strong>de 1e dag voor de halve prijs</strong> — de kiosk van het filiaal geeft je de uitrusting en de motor dan pas vanaf 12:00 op de ophaaldag mee. Heb je de motor eerder nodig? Zet in de reservering de ophaaltijd vroeger — de korting vervalt, je betaalt het verschil bij en de codes werken meteen. Een inlevertijd kies je niet: je brengt de motor op elk moment van de laatste huurdag tot 24:00 terug, 24/7 met codes uit de app. In het contract staat de huur <strong>van 00:01 tot 24:00</strong>, bij een reservering met korting voor ophalen vanaf 12:00 <strong>van 12:00 tot 24:00</strong>; de werkelijke ophaaltijd wordt vastgelegd in het overdrachtsprotocol dat je op het scherm van het filiaal ondertekent.$t$),
    ('pl', '5810fd002db1a32192ff1dfddb9fb634', '36374b1e1dfd1ec82a5db35d7693da81',
     $t$Jak to jest z godziną odbioru i zwrotu w oddziale samoobsługowym?$t$,
     $t$W oddziale samoobsługowym w Velké Němčice wybierasz w rezerwacji (na stronie lub w aplikacji) tylko <strong>godzinę odbioru</strong>. To ona decyduje o zniżce: przy odbiorze od 12:00 i wynajmie na 2 lub więcej dni <strong>1. dzień masz za pół ceny</strong> — kiosk oddziału wyda ci wtedy wyposażenie i motocykl dopiero od 12:00 w dniu odbioru. Potrzebujesz motocykla wcześniej? Zmień w rezerwacji godzinę odbioru na wcześniejszą — zniżka przepada, dopłacisz różnicę, a kody zaczną działać od razu. Godziny zwrotu nie wybierasz: motocykl zwrócisz o dowolnej porze ostatniego dnia wynajmu do 24:00, 24/7 za pomocą kodów z aplikacji. W umowie wynajem trwa <strong>od 00:01 do 24:00</strong>, a przy rezerwacji ze zniżką za odbiór od 12:00 <strong>od 12:00 do 24:00</strong>; rzeczywista godzina odbioru zostaje zapisana w protokole wydania, który podpisujesz na wyświetlaczu oddziału.$t$),
    ('uk', '8035628d7703b1262f84f426ab4f4114', 'b493ba88ec777a4b9d5d0ca71e7928cd',
     $t$Як це з часом отримання та повернення на філії самообслуговування?$t$,
     $t$На філії самообслуговування у Velké Němčice ви в бронюванні (на сайті чи в застосунку) обираєте лише <strong>час отримання</strong>. Саме він визначає знижку: якщо ви забираєте мотоцикл від 12:00 і орендуєте на 2 і більше днів, <strong>1-й день коштує половину</strong> — кіоск філії тоді видасть вам спорядження та мотоцикл лише від 12:00 у день отримання. Потрібен мотоцикл раніше? Змініть у бронюванні час отримання на раніший — знижка зникне, ви доплатите різницю, і коди запрацюють одразу. Час повернення ви не обираєте: мотоцикл можна повернути будь-коли в останній день оренди до 24:00, 24/7 за кодами із застосунку. У договорі оренда вказана <strong>з 00:01 до 24:00</strong>, а для бронювання зі знижкою за отримання від 12:00 — <strong>з 12:00 до 24:00</strong>; фактичний час отримання записується в протокол передачі, який ви підписуєте на дисплеї філії.$t$)
    ) AS v(lang, old_q, old_a, q, a)
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items SET question = f.q WHERE id = c_faq AND md5(question) = f.old_q;
      GET DIAGNOSTICS cnt = ROW_COUNT; n := n + cnt;
      UPDATE public.faq_items SET answer = f.a WHERE id = c_faq AND md5(answer) = f.old_a;
    ELSE
      UPDATE public.faq_items SET translations = jsonb_set(translations, ARRAY[f.lang, 'question'], to_jsonb(f.q))
       WHERE id = c_faq AND md5(translations -> f.lang ->> 'question') = f.old_q;
      GET DIAGNOSTICS cnt = ROW_COUNT; n := n + cnt;
      UPDATE public.faq_items SET translations = jsonb_set(translations, ARRAY[f.lang, 'answer'], to_jsonb(f.a))
       WHERE id = c_faq AND md5(translations -> f.lang ->> 'answer') = f.old_a;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT; n := n + cnt;
  END LOOP;
  RAISE NOTICE 'faq čas převzetí/vrácení (samoobsluha): přepsáno % polí', n;

  -- ── 2) e7079920: „kdykoliv 24/7“ → výdej se slevou až od 12:00 ────────────
  n := 0;
  FOR f IN
    SELECT * FROM (VALUES
    ('cs', $t$jen přímo na této pobočce, kdykoliv 24/7 pomocí kódů z aplikace —$t$,
           $t$jen přímo na této pobočce, 24/7 pomocí kódů z aplikace (rezervaci se slevou za vyzvednutí od 12:00 vydá kiosk až od 12:00) —$t$),
    ('en', $t$only at that branch, any time 24/7 using codes from the app —$t$,
           $t$only at that branch, 24/7 using codes from the app (a booking with the pickup-from-12:00 discount is released by the kiosk only from 12:00) —$t$),
    ('de', $t$in dieser Filiale übernommen und zurückgegeben, jederzeit rund um die Uhr mit Codes aus der App —$t$,
           $t$in dieser Filiale übernommen und zurückgegeben, rund um die Uhr mit Codes aus der App (eine Reservierung mit Rabatt für Abholung ab 12:00 gibt der Kiosk erst ab 12:00 heraus) —$t$),
    ('es', $t$solo en esa sucursal, en cualquier momento 24/7 con los códigos de la aplicación;$t$,
           $t$solo en esa sucursal, 24/7 con los códigos de la aplicación (una reserva con el descuento por recogida desde las 12:00 la entrega el quiosco solo a partir de las 12:00);$t$),
    ('fr', $t$uniquement à cette agence, à tout moment 24h/24 et 7j/7 avec les codes de l'application —$t$,
           $t$uniquement à cette agence, 24h/24 et 7j/7 avec les codes de l'application (une réservation bénéficiant de la remise pour retrait à partir de 12:00 n'est remise par la borne qu'à partir de 12:00) —$t$),
    ('nl', $t$alleen bij dat filiaal opgehaald en teruggebracht, altijd 24/7 met codes uit de app —$t$,
           $t$alleen bij dat filiaal opgehaald en teruggebracht, 24/7 met codes uit de app (een reservering met korting voor ophalen vanaf 12:00 geeft de kiosk pas vanaf 12:00 mee) —$t$),
    ('pl', $t$wyłącznie w tym oddziale, o każdej porze 24/7 za pomocą kodów z aplikacji —$t$,
           $t$wyłącznie w tym oddziale, 24/7 za pomocą kodów z aplikacji (rezerwację ze zniżką za odbiór od 12:00 kiosk wydaje dopiero od 12:00) —$t$)
    ) AS v(lang, old_txt, new_txt)
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items SET answer = replace(answer, f.old_txt, f.new_txt)
       WHERE id = 'e7079920-f08c-4b08-b52a-9b8623909035' AND strpos(answer, f.old_txt) > 0;
    ELSE
      UPDATE public.faq_items
         SET translations = jsonb_set(translations, ARRAY[f.lang, 'answer'],
               to_jsonb(replace(translations -> f.lang ->> 'answer', f.old_txt, f.new_txt)))
       WHERE id = 'e7079920-f08c-4b08-b52a-9b8623909035'
         AND strpos(translations -> f.lang ->> 'answer', f.old_txt) > 0;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT; n := n + cnt;
  END LOOP;
  RAISE NOTICE 'faq místo vyzvednutí (e7079920): upraveno % jazykových verzí', n;

  -- ── 3) CMS texty samoobslužné pobočky (jen nezměněný výchozí text) ────────
  n := 0;
  FOR f IN
    SELECT * FROM (VALUES
    ('web.pobocky.branches.1.hours', '590e6115ab6f3f071569ae0efe00ec7e',
     $t$Nonstop 24/7 kódem z aplikace. Čas vyzvednutí si zvolíte v rezervaci — při vyzvednutí od 12:00 (výpůjčka 2 a více dní) máte 1. den za polovinu a kiosk vám motorku vydá až od 12:00. Čas vrácení nevolíte: motorku vrátíte kdykoliv poslední den výpůjčky do 24:00.$t$,
     $j${
      "en": {"value": "Nonstop 24/7 with a code from the app. You choose the pickup time in your booking — if you pick up from 12:00 (rental of 2 or more days), the 1st day is half price and the kiosk releases the motorcycle to you only from 12:00. You don't choose a return time: you return the motorcycle any time on the last day of the rental until 24:00."},
      "de": {"value": "Rund um die Uhr (24/7) mit Code aus der App. Die Abholzeit wählen Sie in der Reservierung — bei Abholung ab 12:00 (Miete ab 2 Tagen) ist der 1. Tag zum halben Preis und der Kiosk gibt Ihnen das Motorrad erst ab 12:00 heraus. Eine Rückgabezeit wählen Sie nicht: Sie geben das Motorrad jederzeit am letzten Miettag bis 24:00 zurück."},
      "es": {"value": "Abierto 24/7 con un código de la aplicación. La hora de recogida la eliges en la reserva: si recoges a partir de las 12:00 (alquiler de 2 días o más), el 1.er día es a mitad de precio y el quiosco te entrega la moto solo a partir de las 12:00. La hora de devolución no la eliges: devuelves la moto en cualquier momento del último día del alquiler hasta las 24:00."},
      "fr": {"value": "Ouvert 24h/24 et 7j/7 avec un code de l'application. Vous choisissez l'heure de retrait dans la réservation — pour un retrait à partir de 12:00 (location de 2 jours ou plus), le 1er jour est à moitié prix et la borne ne vous remet la moto qu'à partir de 12:00. Vous ne choisissez pas d'heure de restitution : vous rendez la moto à tout moment le dernier jour de la location jusqu'à 24:00."},
      "nl": {"value": "Nonstop 24/7 met een code uit de app. De ophaaltijd kies je in de reservering — haal je op vanaf 12:00 (huur van 2 of meer dagen), dan is de 1e dag voor de halve prijs en geeft de kiosk je de motor pas vanaf 12:00 mee. Een inlevertijd kies je niet: je brengt de motor op elk moment van de laatste huurdag tot 24:00 terug."},
      "pl": {"value": "Całodobowo 24/7 z kodem z aplikacji. Godzinę odbioru wybierasz w rezerwacji — przy odbiorze od 12:00 (wynajem na 2 lub więcej dni) 1. dzień masz za pół ceny, a kiosk wyda ci motocykl dopiero od 12:00. Godziny zwrotu nie wybierasz: motocykl zwrócisz o dowolnej porze ostatniego dnia wynajmu do 24:00."},
      "uk": {"value": "Цілодобово 24/7 за кодом із застосунку. Час отримання ви обираєте в бронюванні — якщо забираєте від 12:00 (оренда на 2 і більше днів), 1-й день коштує половину, а кіоск видасть вам мотоцикл лише від 12:00. Час повернення ви не обираєте: мотоцикл повертаєте будь-коли в останній день оренди до 24:00."}
     }$j$),
    ('web.pobocky.branches.1.seo_description', '1ce8ae865e596ae4d438c72b528c18e9',
     $t$Samoobslužná pobočka půjčovny motorek MotoGo24 ve Velkých Němčicích u Brna: převzetí i vrácení 24/7 kódem z aplikace, čas vyzvednutí volíte v rezervaci (od 12:00 je 1. den za polovinu), parkování zdarma.$t$,
     $j${
      "en": {"value": "Self-service branch of the MotoGo24 motorcycle rental in Velké Němčice near Brno: pickup and return 24/7 with a code from the app, you choose the pickup time in your booking (from 12:00 the 1st day is half price), free parking."},
      "de": {"value": "Selbstbedienungs-Filiale des Motorradverleihs MotoGo24 in Velké Němčice bei Brno: Übernahme und Rückgabe rund um die Uhr mit Code aus der App, die Abholzeit wählen Sie in der Reservierung (ab 12:00 ist der 1. Tag zum halben Preis), kostenloses Parken."},
      "es": {"value": "Sucursal de autoservicio del alquiler de motos MotoGo24 en Velké Němčice, cerca de Brno: recogida y devolución 24/7 con un código de la aplicación, eliges la hora de recogida en la reserva (desde las 12:00 el 1.er día es a mitad de precio), aparcamiento gratuito."},
      "fr": {"value": "Agence en libre-service de la location de motos MotoGo24 à Velké Němčice, près de Brno : retrait et restitution 24h/24 et 7j/7 avec un code de l'application, heure de retrait au choix dans la réservation (à partir de 12:00, le 1er jour est à moitié prix), parking gratuit."},
      "nl": {"value": "Selfservicefiliaal van motorverhuur MotoGo24 in Velké Němčice bij Brno: ophalen en terugbrengen 24/7 met een code uit de app, de ophaaltijd kies je in de reservering (vanaf 12:00 is de 1e dag voor de halve prijs), gratis parkeren."},
      "pl": {"value": "Samoobsługowy oddział wypożyczalni motocykli MotoGo24 w Velké Němčice koło Brna: odbiór i zwrot 24/7 z kodem z aplikacji, godzinę odbioru wybierasz w rezerwacji (od 12:00 1. dzień za pół ceny), bezpłatny parking."},
      "uk": {"value": "Філія самообслуговування прокату мотоциклів MotoGo24 у Velké Němčice біля Брно: отримання та повернення 24/7 за кодом із застосунку, час отримання обираєте в бронюванні (від 12:00 1-й день за півціни), безкоштовне паркування."}
     }$j$),
    ('web.pobocky.branches.1.steps', '4efef821e0dc31328ee3cbefab6279e9',
     $t$1. Rezervujete a zaplatíte online, zvolíte čas vyzvednutí a doplníte doklady — kódy najdete v aplikaci i v e-mailu.<br>2. Na pobočce zadáte kód šatny a vezmete si výbavu (s vlastní výbavou šatnu přeskočíte). Máte-li slevu za vyzvednutí od 12:00, kódy platí až od 12:00.<br>3. Na displeji podepíšete předávací protokol.<br>4. Kódem motorky otevřete kóji s motorkou a vyrazíte.<br>5. Po jízdě motorku vrátíte do kóje a výbavu do šatny — kdykoliv poslední den výpůjčky do 24:00.$t$,
     $j${
      "en": {"value": "1. Book and pay online, choose the pickup time and add your documents — you will find the codes in the app and in the e-mail.<br>2. At the branch, enter the locker code and take your gear (with your own gear you skip the locker). If you have the pickup-from-12:00 discount, the codes work only from 12:00.<br>3. Sign the handover protocol on the display.<br>4. Open the motorcycle bay with the motorcycle code and ride off.<br>5. After the ride, return the motorcycle to the bay and the gear to the locker — any time on the last day of the rental until 24:00."},
      "de": {"value": "1. Sie reservieren und bezahlen online, wählen die Abholzeit und ergänzen Ihre Dokumente — die Codes finden Sie in der App und in der E-Mail.<br>2. An der Filiale geben Sie den Code der Garderobe ein und nehmen Ihre Ausrüstung (mit eigener Ausrüstung überspringen Sie die Garderobe). Haben Sie den Rabatt für Abholung ab 12:00, gelten die Codes erst ab 12:00.<br>3. Am Display unterschreiben Sie das Übergabeprotokoll.<br>4. Mit dem Motorrad-Code öffnen Sie die Box mit dem Motorrad und fahren los.<br>5. Nach der Fahrt stellen Sie das Motorrad zurück in die Box und die Ausrüstung in die Garderobe — jederzeit am letzten Miettag bis 24:00."},
      "es": {"value": "1. Reservas y pagas online, eliges la hora de recogida y completas tus documentos; encontrarás los códigos en la aplicación y en el correo electrónico.<br>2. En la sucursal introduces el código del vestuario y coges el equipamiento (con equipamiento propio te saltas el vestuario). Si tienes el descuento por recogida desde las 12:00, los códigos funcionan solo a partir de las 12:00.<br>3. En la pantalla firmas el protocolo de entrega.<br>4. Con el código de la moto abres el box con la moto y sales.<br>5. Después del viaje devuelves la moto al box y el equipamiento al vestuario, en cualquier momento del último día del alquiler hasta las 24:00."},
      "fr": {"value": "1. Vous réservez et payez en ligne, choisissez l'heure de retrait et complétez vos documents — vous trouverez les codes dans l'application et dans l'e-mail.<br>2. À l'agence, vous saisissez le code du vestiaire et prenez votre équipement (avec votre propre équipement, vous passez le vestiaire). Si vous bénéficiez de la remise pour retrait à partir de 12:00, les codes ne fonctionnent qu'à partir de 12:00.<br>3. Vous signez le protocole de remise sur l'écran.<br>4. Avec le code de la moto, vous ouvrez le box de la moto et partez.<br>5. Après la balade, vous remettez la moto dans le box et l'équipement au vestiaire — à tout moment le dernier jour de la location jusqu'à 24:00."},
      "nl": {"value": "1. Je reserveert en betaalt online, kiest de ophaaltijd en vult je documenten aan — de codes vind je in de app en in de e-mail.<br>2. Bij het filiaal voer je de code van de kleedruimte in en neem je je uitrusting (met eigen uitrusting sla je de kleedruimte over). Heb je de korting voor ophalen vanaf 12:00, dan werken de codes pas vanaf 12:00.<br>3. Op het scherm onderteken je het overdrachtsprotocol.<br>4. Met de motorcode open je de box met de motor en rijd je weg.<br>5. Na de rit zet je de motor terug in de box en de uitrusting in de kleedruimte — op elk moment van de laatste huurdag tot 24:00."},
      "pl": {"value": "1. Rezerwujesz i płacisz online, wybierasz godzinę odbioru i uzupełniasz dokumenty — kody znajdziesz w aplikacji i w e-mailu.<br>2. W oddziale wpisujesz kod szatni i bierzesz wyposażenie (z własnym wyposażeniem pomijasz szatnię). Jeśli masz zniżkę za odbiór od 12:00, kody działają dopiero od 12:00.<br>3. Na wyświetlaczu podpisujesz protokół wydania.<br>4. Kodem motocykla otwierasz boks z motocyklem i ruszasz w drogę.<br>5. Po jeździe odstawiasz motocykl do boksu, a wyposażenie do szatni — o dowolnej porze ostatniego dnia wynajmu do 24:00."},
      "uk": {"value": "1. Ви бронюєте й оплачуєте онлайн, обираєте час отримання та доповнюєте документи — коди знайдете в застосунку та в e-mail.<br>2. На філії вводите код гардеробу й берете спорядження (з власним спорядженням гардероб пропускаєте). Якщо у вас знижка за отримання від 12:00, коди діють лише від 12:00.<br>3. На дисплеї підписуєте протокол передачі.<br>4. Кодом мотоцикла відкриваєте бокс із мотоциклом і вирушаєте.<br>5. Після поїздки повертаєте мотоцикл у бокс, а спорядження в гардероб — будь-коли в останній день оренди до 24:00."}
     }$j$)
    ) AS v(key, old_md5, cs, tr)
  LOOP
    UPDATE public.cms_variables
       SET value = to_jsonb(f.cs),
           translations = COALESCE(translations, '{}'::jsonb) || f.tr::jsonb,
           updated_at = now()
     WHERE key = f.key AND jsonb_typeof(value) = 'string'
       AND (md5(value #>> '{}') = f.old_md5
            -- ještě starší výchozí text hours (4079838, dopoledne 2026-10-01)
            OR (f.key = 'web.pobocky.branches.1.hours' AND md5(value #>> '{}') = 'bb031e8fff7f38737017e38679b84cc2'));
    GET DIAGNOSTICS cnt = ROW_COUNT; n := n + cnt;
  END LOOP;
  RAISE NOTICE 'cms texty samoobslužné pobočky: přepsáno % klíčů', n;
END
$$;
