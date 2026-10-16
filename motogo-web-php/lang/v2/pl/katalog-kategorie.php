<?php
// Strony kategorii katalogu (PL): tekst końcowy + meta description dla każdej kategorii (pages/katalog.php → siteContent('katalog_<cat>')).
// Domyślnie CS = $categoryOutros / $catDescriptions w pages/katalog.php. 'models' = zdanie z maks. 3 aktualnymi modelami
// ({models}), dołączane do body1 tylko gdy kategoria ma motocykle; w przeciwnym razie 'nomodels'.
return ['pages' => [
'katalog_cestovni' => [
    'outro' => [
        'title' => 'Motocykle turystyczne do wynajęcia — na długie trasy i urlop',
        'body1' => 'Motocykle turystyczne i adventure w naszej flocie są stworzone na długie dystanse — wyższa pozycja, wygodne siedzenie dla kierowcy i pasażera, duży zbiornik z zasięgiem 300–400 km i kufry na bagaż.',
        'models' => 'Obecnie znajdziesz u nas na przykład {models} — wszystkie regularnie serwisowane i gotowe na trasę po Czechach i za granicą.',
        'nomodels' => 'Wszystkie są regularnie serwisowane i gotowe na trasę po Czechach i za granicą.',
        'body2' => 'Wypożyczamy bez kaucji, zieloną kartę i dokumenty międzynarodowe dajemy automatycznie, a w cenie masz kompletne wyposażenie dla kierowcy. Wyposażenie dla pasażera (kask, kurtka, kominiarka) możesz domówić za dopłatą.',
    ],
    'description' => 'Wypożyczalnia motocykli turystycznych (touring, GT) w regionie Vysočina. Motocykle adventure na długie trasy i autostrady. Bez kaucji, rezerwacja online.',
],
'katalog_naked' => [
    'outro' => [
        'title' => 'Motocykle naked — sportowe maszyny na co dzień',
        'body1' => 'Motocykle naked bez owiewek dają <strong>niepowtarzalne poczucie wolności</strong> i bezpośredni kontakt z silnikiem. Sprawdzą się w dynamicznej jeździe po mieście, na weekendowych wypadach i na zakrętach.',
        'models' => 'W naszej flocie znajdziesz na przykład {models} — wszystkie w doskonałym stanie technicznym i regularnie serwisowane.',
        'nomodels' => 'Wszystkie są w doskonałym stanie technicznym i regularnie serwisowane.',
        'body2' => 'Wypożyczamy bez kaucji, a wyposażenie dla kierowcy (kask, kurtka, spodnie, rękawice) jest zawsze w cenie. Przed odbiorem wspólnie obejrzymy motocykl i wyjaśnimy jego specyfikę. Jeśli nie masz doświadczenia z daną klasą mocy, chętnie pomożemy w wyborze.',
    ],
    'description' => 'Wypożyczalnia motocykli naked w regionie Vysočina. Sportowo-turystyczne maszyny na co dzień. Bez kaucji, wyposażenie w cenie, rezerwacja online.',
],
'katalog_supermoto' => [
    'outro' => [
        'title' => 'Motocykle supermoto — lekkie i zwinne maszyny do zabawy w mieście',
        'body1' => 'Supermoto łączy zalety enduro (lekkość, długi skok zawieszenia, wysoka pozycja) z oponami szosowymi i hamulcami tarczowymi. Efektem jest <strong>bardzo zwinna maszyna</strong>, która dobrze radzi sobie w ruchu miejskim, na polnych drogach i na krótkich trasach po regionie Vysočina.',
        'models' => 'W katalogu znajdziesz na przykład {models}.',
        'body2' => 'Te motocykle wymagają prawa jazdy kategorii A lub A2 i są raczej dla bardziej doświadczonych kierowców, którzy chcą cieszyć się lekkością i zadziornością maszyny. Wypożyczamy bez kaucji, wyposażenie kierowcy jest w cenie. Przy odbiorze wyjaśnimy specyfikę jazdy z wyższą pozycją i znaczenie równowagi.',
    ],
    'description' => 'Wypożyczalnia motocykli supermoto w regionie Vysočina. Lekkie miejskie maszyny z wysoką pozycją. Bez kaucji, wyposażenie w cenie, rezerwacja online.',
],
'katalog_chopper' => [
    'outro' => [
        'title' => 'Motocykle chopper i cruiser do spokojnej jazdy',
        'body1' => 'Choppery i cruisery są stworzone do <strong>wygodnej jazdy na długich dystansach</strong> — niskie siedzenie, swobodna pozycja, charakterystyczny dźwięk dwucylindrowego silnika i klasyczna estetyka. Idealne na niedzielną przejażdżkę i dłuższą podróż po Czechach.',
        'body2' => 'Stale poszerzamy naszą ofertę — jeśli masz na myśli konkretny model, odezwij się do nas. Wypożyczamy bez kaucji, wyposażenie kierowcy jest w cenie. Przy odbiorze przekażemy kluczyki, dokumenty i kompletne wyposażenie.',
    ],
    'description' => 'Wypożyczalnia motocykli chopper i cruiser w regionie Vysočina. Wygodne maszyny do spokojnej jazdy. Bez kaucji, wyposażenie w cenie, rezerwacja online.',
],
'katalog_detske' => [
    'outro' => [
        'title' => 'Motocykle dla dzieci — bezpieczna zabawa dla małych kierowców',
        'body1' => 'Motocykle dla dzieci można wypożyczyć <strong>bez prawa jazdy</strong> i korzystać z nich w ogrodzie, na kempingu lub w ramach kursu jazdy dla dzieci.',
        'models' => 'W katalogu znajdziesz na przykład {models}.',
        'body2' => 'Przed każdą jazdą zalecamy omówić z dzieckiem podstawowe zasady bezpieczeństwa i zawsze wyposażyć je w kask i ochraniacze. Termin, oddział i ewentualną dostawę ustalisz bezpośrednio przy rezerwacji.',
    ],
    'description' => 'Wypożyczalnia motocykli dla dzieci bez prawa jazdy. Bezpieczna zabawa w ogrodzie lub na kempingu. Dostawa na terenie całych Czech, rezerwacja online.',
],
'katalog_sportovni' => [
    'outro' => [
        'title' => 'Motocykle sportowe — adrenalina i moc dla doświadczonych kierowców',
        'body1' => 'Motocykle sportowe (supersport) są przeznaczone dla <strong>doświadczonych kierowców</strong>, którzy szukają wysokich osiągów, ostrej geometrii i sportowej pozycji. Sprawdzą się na torze, krętych drogach i na weekendowych wypadach pięknymi trasami Moraw i regionu Vysočina.',
        'body2' => 'Wymagamy prawa jazdy kategorii A i co najmniej 2 lat doświadczenia na motocyklu powyżej 35 kW. Wypożyczamy bez kaucji, kompletne wyposażenie kierowcy jest w cenie. Przed odbiorem wyjaśnimy specyfikę jazdy motocyklem sportowym i doradzimy bezpieczne praktyki.',
    ],
    'description' => 'Wypożyczalnia motocykli sportowych w regionie Vysočina. Maszyny supersport i sportowo-turystyczne. Bez kaucji, wyposażenie w cenie, rezerwacja online.',
],
'katalog_scootery' => [
    'outro' => [
        'title' => 'Skutery do wynajęcia — wygodna jazda po mieście na prawo jazdy A1 i B',
        'body1' => 'Skutery to idealny wybór do <strong>wygodnej i niewymagającej jazdy po mieście</strong> — automatyczna skrzynia biegów, niskie siedzenie i schowek pod siedzeniem. Część naszych skuterów poprowadzisz także z prawem jazdy <strong>kategorii B</strong> (na samochód), pozostałe z <strong>A1</strong>. Wymaganą kategorię zawsze znajdziesz w szczegółach danej maszyny.',
        'body2' => 'Wypożyczamy bez kaucji, a wyposażenie dla kierowcy (kask, rękawice) jest w cenie. Skuter świetnie nadaje się do dojazdów, wycieczek po okolicy i jako pierwsze zetknięcie z jednośladem. Przy odbiorze wyjaśnimy obsługę i specyfikę jazdy.',
    ],
    'description' => 'Wypożyczalnia skuterów w regionie Vysočina. Skutery na prawo jazdy A1 i B do wygodnej jazdy po mieście. Bez kaucji, wyposażenie w cenie, rezerwacja online.',
],
'katalog_ostatni' => [
    'outro' => [
        'title' => 'Przyczepy do motocykli i inne wyposażenie do wynajęcia',
        'body1' => 'W kategorii Inne znajdziesz <strong>przyczepy do przewozu motocykli</strong> i inne dodatkowe wyposażenie do wypożyczenia. Przyczepa przyda się przy przewozie maszyny na tor, na urlop lub do serwisu. Do ciągnięcia przyczepy wystarczy zwykłe prawo jazdy <strong>kategorii B</strong> (w zależności od masy zestawu).',
        'body2' => 'Wypożyczamy bez kaucji i chętnie doradzimy przy wyborze oraz prawidłowym załadunku i zabezpieczeniu motocykla. Konkretne parametry (ładowność, wymiary, wymagana kategoria prawa jazdy) znajdziesz w szczegółach każdej pozycji. Termin i miejsce odbioru ustalisz bezpośrednio przy rezerwacji.',
    ],
    'description' => 'Wypożyczalnia przyczep do motocykli i innego wyposażenia w regionie Vysočina. Przyczepa na prawo jazdy B. Bez kaucji, rezerwacja online.',
],
]];
