-- =============================================================================
-- 20261016k_qa_moto_translations.sql — NÁVRH ke schválení (QA brána 2026-10-16), neaplikováno
-- Detail motorky na webu: seznam výbavy/vlastností (features) některých motorek nemá překlad → česky:
--   KTM SX 50 Replica a Yamaha PW 50 ve všech 7 jazycích (+ uk popis), XL 1000 Varadero pl,
--   Yamaha MT-09 Street Rally de, Honda CRF 1000 Africa Twin de + pl. (Honda CRF 1000 Africa Twin, KTM SX 50 Replica, XL 1000 VARADERO, Yamaha MT-09 Street Rally, Yamaha PW 50)
-- Web čte translations.<jazyk>.features jako řádky oddělené \n (localizedList), popis přes localized().
-- Alternativa bez SQL: Velín → Flotila → motorka → Uložit (spustí auto-překlad popisu i features).
-- Bezpečnost: doplní jen chybějící/prázdné pole a jen když české znění odpovídá tomu, ze kterého se
-- překládalo (md5); jinak NOTICE. Ostatní jazyky a pole motorky beze změny. Idempotentní. Bez BEGIN/COMMIT.
-- Technické údaje (barva, motor, převodovka, palivo, brzdy, popisky fotek) řeší web slovníkem
-- (motogo-web-php/i18n_moto_specs.php + lang/moto-specs/*.php) – bez SQL.
-- =============================================================================
DO $$
DECLARE
  r record;
  n integer;
  n_f integer := 0;
  n_d integer := 0;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('6071c49d-8019-415e-a9d9-ef23c7ec88a6', 'en', '6b898728c240c0052107e3ba5ff70fbc', $q$Factory Replica graphics and colours — the authentic motocross look the pros know
Liquid-cooled 2-stroke race engine — no surprises in any situation
Disc brakes front and rear — safe, precise braking
Weighs under 40 kg — kids handle the bike on their own with ease
Low 585 mm seat — even a five-year-old reaches the ground
Liquid cooling (LC) — handles longer rides without overheating
Automatic centrifugal clutch — no gear shifting
Optional throttle limiter — parents can set a rev limit for the first rides
Light sporty frame — agile, nimble, racing character
The step before the KTM SX 65 — when your child outgrows the 50, moving up to the 65 comes naturally$q$),
    ('6071c49d-8019-415e-a9d9-ef23c7ec88a6', 'de', '6b898728c240c0052107e3ba5ff70fbc', $q$Werks-Replica-Grafik und -Farben — der authentische Motocross-Look, den die Profis kennen
Flüssigkeitsgekühlter 2-Takt-Rennmotor — keine Überraschungen in keiner Situation
Scheibenbremsen vorn und hinten — sicheres, präzises Bremsen
Unter 40 kg — das Kind manövriert das Motorrad spielend selbst
Niedrige Sitzhöhe von 585 mm — auch Fünfjährige erreichen den Boden
Flüssigkeitskühlung (LC) — hält auch längere Fahrten ohne Überhitzung durch
Automatische Fliehkraftkupplung — kein Schalten
Optionaler Gasbegrenzer — Eltern stellen für den Anfang eine Drehzahlgrenze ein
Leichter Sportrahmen — agil, wendig, Renncharakter
Vorstufe zur KTM SX 65 — wächst das Kind aus der 50er heraus, steigt es ganz natürlich auf die 65er um$q$),
    ('6071c49d-8019-415e-a9d9-ef23c7ec88a6', 'es', '6b898728c240c0052107e3ba5ff70fbc', $q$Gráficos y colores Replica de fábrica: el auténtico look de motocross que conocen los profesionales
Motor de competición de 2 tiempos con refrigeración líquida: sin sorpresas en ninguna situación
Frenos de disco delante y detrás: frenada segura y precisa
Menos de 40 kg: el niño maneja la moto solo y sin esfuerzo
Asiento bajo de 585 mm: incluso un niño de cinco años llega al suelo
Refrigeración líquida (LC): aguanta trayectos más largos sin sobrecalentarse
Embrague centrífugo automático: sin cambiar de marcha
Limitador de acelerador opcional: los padres fijan un límite de revoluciones para empezar
Chasis deportivo ligero: carácter ágil, vivo y de competición
La antesala de la KTM SX 65: cuando el niño se queda pequeño para la 50, pasa de forma natural a la 65$q$),
    ('6071c49d-8019-415e-a9d9-ef23c7ec88a6', 'fr', '6b898728c240c0052107e3ba5ff70fbc', $q$Graphismes et couleurs Replica d'usine — le look motocross authentique que connaissent les pros
Moteur de course 2 temps refroidi par liquide — aucune surprise, quelle que soit la situation
Freins à disque à l'avant et à l'arrière — un freinage sûr et précis
Moins de 40 kg — l'enfant manie la moto tout seul sans effort
Selle basse de 585 mm — même un enfant de cinq ans touche le sol
Refroidissement liquide (LC) — tient aussi les longues sorties sans surchauffer
Embrayage centrifuge automatique — pas de passage de vitesses
Limiteur de gaz en option — les parents fixent une limite de régime pour les débuts
Cadre sportif léger — agile, vive, caractère de course
L'étape avant la KTM SX 65 — quand l'enfant devient trop grand pour la 50, il passe naturellement à la 65$q$),
    ('6071c49d-8019-415e-a9d9-ef23c7ec88a6', 'nl', '6b898728c240c0052107e3ba5ff70fbc', $q$Fabrieks-Replica-graphics en -kleuren — de authentieke motorcrosslook die de profs kennen
Vloeistofgekoelde 2-takt-racemotor — geen verrassingen, in welke situatie dan ook
Schijfremmen voor en achter — veilig, precies remmen
Lichter dan 40 kg — het kind hanteert de motor speels zelf
Lage zithoogte van 585 mm — zelfs een vijfjarige komt met de voeten aan de grond
Vloeistofkoeling (LC) — houdt ook langere ritten vol zonder oververhitting
Automatische centrifugaalkoppeling — geen schakelen
Optionele gasbegrenzer — ouders stellen voor het begin een toerentalgrens in
Licht sportframe — wendbaar, vlot, racekarakter
Opstap naar de KTM SX 65 — als het kind de 50 ontgroeit, stapt het vanzelf over op de 65$q$),
    ('6071c49d-8019-415e-a9d9-ef23c7ec88a6', 'pl', '6b898728c240c0052107e3ba5ff70fbc', $q$Fabryczna grafika i kolory Replica — autentyczny motocrossowy wygląd, jaki znają zawodowcy
Wyczynowy silnik 2-suwowy chłodzony cieczą — żadnych niespodzianek w żadnej sytuacji
Hamulce tarczowe z przodu i z tyłu — bezpieczne, precyzyjne hamowanie
Masa poniżej 40 kg — dziecko bez trudu samo manewruje motocyklem
Niskie siedzenie 585 mm — nawet pięciolatek dosięgnie ziemi
Chłodzenie cieczą (LC) — wytrzyma też dłuższą jazdę bez przegrzania
Automatyczne sprzęgło odśrodkowe — bez zmiany biegów
Opcjonalny ogranicznik gazu — rodzic na początek ustawi limit obrotów
Lekka sportowa rama — zwinny, żwawy, wyczynowy charakter
Poprzednik KTM SX 65 — gdy dziecko wyrośnie z „pięćdziesiątki”, naturalnie przesiądzie się na „sześćdziesiątkę piątkę”$q$),
    ('6071c49d-8019-415e-a9d9-ef23c7ec88a6', 'uk', '6b898728c240c0052107e3ba5ff70fbc', $q$Заводська графіка й кольори Replica — справжній мотокросовий вигляд, який знають профі
Гоночний 2-тактний двигун із рідинним охолодженням — жодних несподіванок у будь-якій ситуації
Дискові гальма спереду й ззаду — безпечне, точне гальмування
Вага до 40 кг — дитина легко керує мотоциклом сама
Низьке сидіння 585 мм — навіть п’ятирічна дитина дістане до землі
Рідинне охолодження (LC) — витримає й довшу їзду без перегріву
Автоматичне відцентрове зчеплення — без перемикання передач
Можливість обмежувача газу — батьки на початок встановлять ліміт обертів
Легка спортивна рама — спритний, жвавий, гоночний характер
Попередник KTM SX 65 — коли дитина виросте з «п’ятдесятки», природно пересяде на «шістдесят п’ятку»$q$),
    ('a0000001-0000-0000-0000-000000000012', 'en', 'a77dd3c566317f280dff058be444a975', $q$Fully automatic — no gear shifting, the child only learns balance and braking
Speed limiter — safety adapted to the child's age
Very low seat (470 mm) — suitable from age 3
Light (37 kg) — the child handles the bike easily
Shaft drive — maintenance-free, no chain
Yamaha quality — reliability proven over generations$q$),
    ('a0000001-0000-0000-0000-000000000012', 'de', 'a77dd3c566317f280dff058be444a975', $q$Vollautomatisch — kein Schalten, das Kind lernt nur Gleichgewicht und Bremsen
Geschwindigkeitsbegrenzer — Sicherheit passend zum Alter des Kindes
Sehr niedrige Sitzhöhe (470 mm) — passt schon ab 3 Jahren
Leicht (37 kg) — das Kind kommt mit dem Motorrad gut zurecht
Kardanantrieb — wartungsfrei, keine Kette
Yamaha-Qualität — über Generationen bewährte Zuverlässigkeit$q$),
    ('a0000001-0000-0000-0000-000000000012', 'es', 'a77dd3c566317f280dff058be444a975', $q$Totalmente automática: sin cambiar de marcha, el niño solo aprende equilibrio y frenada
Limitador de velocidad: seguridad adaptada a la edad del niño
Asiento muy bajo (470 mm): apta desde los 3 años
Ligera (37 kg): el niño la maneja con facilidad
Transmisión por cardán: sin mantenimiento, sin cadena
Calidad Yamaha: fiabilidad probada durante generaciones$q$),
    ('a0000001-0000-0000-0000-000000000012', 'fr', 'a77dd3c566317f280dff058be444a975', $q$Entièrement automatique — pas de vitesses, l'enfant n'apprend que l'équilibre et le freinage
Limiteur de vitesse — une sécurité adaptée à l'âge de l'enfant
Selle très basse (470 mm) — adaptée dès 3 ans
Légère (37 kg) — l'enfant maîtrise facilement la moto
Transmission par cardan — sans entretien, pas de chaîne
Qualité Yamaha — une fiabilité éprouvée depuis des générations$q$),
    ('a0000001-0000-0000-0000-000000000012', 'nl', 'a77dd3c566317f280dff058be444a975', $q$Volledig automatisch — geen schakelen, het kind leert alleen evenwicht en remmen
Snelheidsbegrenzer — veiligheid afgestemd op de leeftijd van het kind
Zeer lage zithoogte (470 mm) — geschikt vanaf 3 jaar
Licht (37 kg) — het kind kan de motor makkelijk aan
Cardanaandrijving — onderhoudsvrij, geen ketting
Yamaha-kwaliteit — betrouwbaarheid die zich al generaties bewijst$q$),
    ('a0000001-0000-0000-0000-000000000012', 'pl', 'a77dd3c566317f280dff058be444a975', $q$W pełni automatyczny — bez zmiany biegów, dziecko uczy się tylko równowagi i hamowania
Ogranicznik prędkości — bezpieczeństwo dopasowane do wieku dziecka
Bardzo niskie siedzenie (470 mm) — odpowiedni już od 3 lat
Lekki (37 kg) — dziecko łatwo sobie z nim radzi
Napęd wałem kardana — bezobsługowy, bez łańcucha
Jakość Yamahy — niezawodność sprawdzona przez pokolenia$q$),
    ('a0000001-0000-0000-0000-000000000012', 'uk', 'a77dd3c566317f280dff058be444a975', $q$Повністю автоматичний — без перемикання передач, дитина вчиться лише рівноваги й гальмування
Обмежувач швидкості — безпека з урахуванням віку дитини
Дуже низьке сидіння (470 мм) — підходить уже з 3 років
Легкий (37 кг) — дитина легко з ним впорається
Карданний привід — без обслуговування, без ланцюга
Якість Yamaha — надійність, перевірена поколіннями$q$),
    ('4570ce0f-a8e1-4981-bf69-20eed8a45323', 'pl', 'c0b849b6cff0063273bd3520ce610d45', $q$Ogromny bak 25 l — zasięg ponad 450 km
V-twin z charakterem — ciągnie od dołu, ciepły dźwięk dwucylindrowca
Pełna turystyczna szyba i owiewki — chronią cię przed wiatrem i deszczem
Wygodne, szerokie siedzenie — nawet po 600 km bez bólu pleców
Wyprostowana pozycja z szeroką kierownicą — komfort i kontrola
Wtrysk paliwa PGM-FI — bez regulacji gaźników, niezawodny rozruch w każdą pogodę
ABS — bezpieczne hamowanie na każdej nawierzchni
Niezawodność Hondy — silnik, który bez problemu pokona setki tysięcy km
2 kufry boczne i 1 tylny
Antywibracyjny uchwyt na telefon
Ładowanie USB$q$),
    ('a0000001-0000-0000-0000-000000000008', 'de', '15242c760870ed73664e1ad977a8c9e1', $q$Dreizylindermotor mit Charakter — der Puls eines Zweizylinders und die Laufruhe eines Vierzylinders in einem
Nur 191 kg — extrem leicht, agil in Kurven und im Stadtverkehr
115 PS mit kräftigem Durchzug von unten — kein Warten auf Drehzahl
3 Fahrmodi (D-Mode: A, STD, B) — wähle die Gasannahme je nach Laune und Wetter
ABS serienmäßig — sicheres Bremsen
Rallye-Look des „Street Rally“-Pakets — höherer Lenker, Lampenmaske, Protektoren
Aufrechte Sitzposition mit höherem Lenker — entspannt und komfortabel in der Stadt
Niedrige Sitzhöhe (815 mm) — passt auch kleineren Fahrern
LED-Scheinwerfer vorn
LCD-Cockpit
Vibrationsgedämpfte Handyhalterung
Kein USB$q$),
    ('e3123fff-5ecc-486b-9481-fb5eebc11fdf', 'de', '59e0c908720e045c82117265a6f682c3', $q$Echte Adventure-Geometrie — Asphalt und Schotter ohne Kompromisse
21"-Vorderrad mit Drahtspeichen — meistert auch gröberes Gelände
Lange Federwege (230/220 mm) — schluckt auch üble Schlaglöcher
Abschaltbares ABS am Hinterrad — für kontrollierte Drifts im Gelände
Dreistufige Traktionskontrolle (HSTC) — je nach Untergrund wählbar
Aufrechte Sitzposition und breiter Lenker — Komfort und Kontrolle den ganzen Tag
18,8-l-Tank — ordentliche Reichweite zwischen den Tankstellen
Sturzbügel aus Aluminium und Motorschutz
Höhenverstellbare Sitzbank — passt auch kleineren Fahrern
Vibrationsgedämpfte Handyhalterung
USB-Ladeanschluss$q$),
    ('e3123fff-5ecc-486b-9481-fb5eebc11fdf', 'pl', '59e0c908720e045c82117265a6f682c3', $q$Prawdziwa geometria adventure — asfalt i szuter bez kompromisów
21-calowe przednie koło na szprychach — poradzi sobie też w trudniejszym terenie
Długie skoki zawieszenia (230/220 mm) — wybiera nawet paskudne dziury
Wyłączany ABS na tylnym kole — do kontrolowanych poślizgów w terenie
Trzystopniowa kontrola trakcji (HSTC) — wybierz według nawierzchni
Wyprostowana pozycja i szeroka kierownica — wygoda i kontrola przez cały dzień
Bak 18,8 l — przyzwoity zasięg między stacjami
Aluminiowe gmole i osłona silnika
Siedzenie z regulacją wysokości — pasuje też niższym kierowcom
Antywibracyjny uchwyt na telefon
Ładowanie USB$q$)
  ) AS v(id, lang, cs_md5, features) LOOP
    UPDATE public.motorcycles
       SET translations = jsonb_set(COALESCE(translations, '{}'::jsonb), ARRAY[r.lang],
             COALESCE(translations -> r.lang, '{}'::jsonb) || jsonb_build_object('features', r.features))
     WHERE id = r.id::uuid
       AND md5(array_to_string(features, E'\n')) = r.cs_md5
       AND COALESCE(translations -> r.lang ->> 'features', '') = '';
    GET DIAGNOSTICS n = ROW_COUNT; n_f := n_f + n;
    IF n = 0 THEN RAISE NOTICE 'moto features: beze změny % %', r.id, r.lang; END IF;
  END LOOP;
  FOR r IN SELECT * FROM (VALUES
    ('6071c49d-8019-415e-a9d9-ef23c7ec88a6', '122528ffc5cda57c01292a1eca9bd38a', $q$<p><strong>KTM SX 50 Replica — помаранчева гоночна легенда для наймолодших райдерів.</strong> Без компромісів, без половинчастих рішень, без дитячого дизайну. <strong>SX 50 створена для закритих мотокросових трас або інших закритих майданчиків</strong>&nbsp;— перші спроби, змагання, мрії про велику кар’єру — це її стихія.</p>
<p><strong>5,5 кВт із 49,9-кубового двотактного двигуна</strong>, вага до <strong>40 кг</strong> і низьке сидіння <strong>585 мм</strong> означають одне: <strong>гоночні враження, скроєні під маленького райдера</strong>. Версія Replica має кольори й графіку <strong>заводської команди KTM</strong> — помаранчевий, чорний, справжній мотокросовий вигляд. <strong>Рідинне охолодження та дискові гальма</strong> роблять її справжнім гоночним мотоциклом, а не іграшкою. <strong>Легка, спритна, потужна.</strong> Якщо твоя дитина хоче відчути адреналін від їзди, далі можна не шукати.&nbsp;</p>$q$),
    ('a0000001-0000-0000-0000-000000000012', '78b4efc214811706cba1f9d2d8745b21', $q$<span style="font-weight: bold;">Yamaha PW 50 — легенда серед дитячих мотоциклів </span>— її виробляють практично без змін ще з 1981 року, і на ній виросли сотні тисяч маленьких райдерів у всьому світі. Двотактний автоматичний двигун 50 см³, <span style="font-weight: bold;">жодного зчеплення, жодного перемикання передач</span>, лише газ і гальмо. <span style="font-weight: bold;">До того ж гальма керуються як на велосипеді, тож дитина пересяде з велосипеда на мотоцикл абсолютно плавно</span>, без плутанини. Повного бака бензину <span style="font-weight: bold;">(2 л) дитині вистачить на 1–2 години інтенсивного катання</span>. <span style="font-weight: bold;">Обмежувач швидкості </span>дає батькам змогу налаштувати, як швидко їхатиме мотоцикл — від «кроком» до «повної потужності», залежно від віку й досвіду дитини. Підходить <span style="font-weight: bold;">уже з 3 років.</span>$q$)
  ) AS v(id, cs_md5, descr) LOOP
    UPDATE public.motorcycles
       SET translations = jsonb_set(COALESCE(translations, '{}'::jsonb), '{uk}',
             COALESCE(translations -> 'uk', '{}'::jsonb) || jsonb_build_object('description', r.descr))
     WHERE id = r.id::uuid AND md5(description) = r.cs_md5
       AND COALESCE(translations -> 'uk' ->> 'description', '') = '';
    GET DIAGNOSTICS n = ROW_COUNT; n_d := n_d + n;
    IF n = 0 THEN RAISE NOTICE 'moto popis uk: beze změny %', r.id; END IF;
  END LOOP;
  RAISE NOTICE 'qa_moto_translations: features %, popisy uk %', n_f, n_d;
END $$;
