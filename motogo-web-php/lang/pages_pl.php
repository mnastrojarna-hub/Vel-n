<?php
// MotoGo24 — pages_pl.php (Polski overlay nad CS defaults)

return [
    'pages' => [

        'jak_pujcit_cena' => [
            'seo' => [
                'title' => 'Wypożyczalnia motocykli Vysočina – Jak wypożyczyć – Co jest w cenie',
                'description' => 'Sprawdź, co zawiera cena wynajmu motocykla w MotoGo24. Jasne warunki, wyposażenie i usługi bez ukrytych opłat. Zarezerwuj motocykl online.',
                'keywords' => 'wypożyczalnia motocykli Vysočina, wynajem motocykli Pelhřimov, wynajem bez kaucji, obsługa całodobowa, rezerwacja online motocykl',
            ],
            'h1' => 'Co jest w cenie wynajmu motocykla',
            'intro' => 'W <strong>MotoGo24 – wypożyczalni motocykli w Vysočina</strong> otrzymasz uczciwe warunki. <strong>Bez kaucji, z wyposażeniem kierowcy w cenie i obsługą całodobową</strong>. Wszystko, czego potrzebujesz do bezpiecznej i przyjemnej jazdy, jest wliczone.',
            'cta' => [
                'title' => 'Wyposażenie w cenie – wypożyczalnia motocykli MotoGo24 – Vysočina',
                'text' => '<strong>MotoGo24 to nowoczesna wypożyczalnia motocykli w Vysočina</strong> z wyposażeniem kierowcy w cenie, wynajmem bez kaucji i obsługą całodobową. Wybierz <strong>motocykl turystyczny, supermoto, naked lub dla dzieci</strong> i zarezerwuj online.',
                'buttons' => [
                    ['label' => 'REZERWUJ ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse', 'aria' => 'Zarezerwuj motocykl z wyposażeniem w cenie w Motogo24'],
                ],
            ],
        ],

        'jak_pujcit_dokumenty' => [
            'seo' => [
                'title' => 'Wypożyczalnia motocykli Vysočina – Dokumenty i instrukcje',
                'description' => 'Umowa najmu, warunki i dokumenty potrzebne do wynajmu motocykla. Bez kaucji, jasne zasady, ubezpieczenie w cenie.',
                'keywords' => 'umowa najmu motocykl, dokumenty wynajmu, warunki wynajmu, ubezpieczenie motocykl, MotoGo24',
            ],
            'h1' => 'Umowa najmu i kaucja – uczciwe warunki bez zaliczki',
            'intro' => 'W <strong>MotoGo24</strong> stawiamy na prostotę i uczciwość. Wypożyczamy <strong>bez kaucji</strong>, z <strong>jasną umową najmu</strong>, <strong>ubezpieczeniem w cenie</strong> i <strong>wyposażeniem kierowcy</strong>.',
            'top_cta' => ['label' => 'REZERWUJ ONLINE', 'href' => '/rezervace', 'aria' => 'Zarezerwuj motocykl online w Motogo24'],
            'cta' => [
                'title' => 'Umowa najmu bez kaucji – wypożyczalnia motocykli Vysočina',
                'text' => 'MotoGo24 to <strong>wypożyczalnia motocykli w Vysočina</strong> z uczciwymi warunkami.',
                'buttons' => [['label' => 'REZERWUJ ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
            ],
        ],

        'jak_pujcit_pristaveni' => [
            'seo' => [
                'title' => 'Dostawa motocykla | MotoGo24',
                'description' => 'Dostawa motocykla pod twoje drzwi. Dowieziemy motocykl do hotelu, na dworzec lub pod inny adres. Cennik od 290 Kč. Obsługa całodobowa.',
                'keywords' => 'dostawa motocykla, dowóz motocykla, doręczenie motocykla, wypożyczalnia motocykli Vysočina',
            ],
            'h1' => 'Dostawa motocykla – prosto do ciebie',
            'intro' => 'Chcesz wyruszyć bez konieczności jazdy do wypożyczalni? Zorganizujemy <strong>dostawę motocykla</strong> w <strong>uzgodnione miejsce</strong>.',
            'top_cta' => ['label' => 'REZERWUJ Z DOSTAWĄ', 'href' => '/rezervace?delivery=1'],
            'cta' => [
                'title' => 'Dostawa motocykla – wypożyczalnia motocykli Vysočina',
                'text' => 'MotoGo24 oferuje <strong>dostawę motocykla</strong> w regionie i poza nim. <strong>Obsługa całodobowa, bez kaucji, wyposażenie w cenie</strong>.',
                'buttons' => [['label' => 'REZERWUJ Z DOSTAWĄ', 'href' => '/rezervace?delivery=1', 'cls' => 'btndark pulse']],
            ],
        ],

        'jak_pujcit_vraceni_jinde' => [
            'seo' => [
                'title' => 'Zwrot motocykla w innym miejscu | MotoGo24',
                'description' => 'Zwróć motocykl poza wypożyczalnią – z hotelu, dworca lub innego adresu. Odbiór w Vysočina i poza nią.',
                'keywords' => 'zwrot motocykla gdzie indziej, odbiór motocykla, zwrot poza wypożyczalnią, wypożyczalnia motocykli Vysočina',
            ],
            'h1' => 'Zwrot motocykla w innym miejscu – odbiór do ciebie',
            'intro' => 'Nie musisz wracać do wypożyczalni. <strong>MotoGo24</strong> oferuje <strong>odbiór motocykla</strong> z miejsca, które ci pasuje – hotel, dworzec, własny adres.',
            'top_cta' => ['label' => 'REZERWUJ Z ODBIOREM', 'href' => '/rezervace?return_delivery=1'],
            'cta' => [
                'title' => 'Zwrot motocykla wszędzie – MotoGo24',
                'text' => 'MotoGo24 organizuje <strong>odbiór motocykla</strong> z miejsca, które ci pasuje. <strong>Całodobowo, bez kaucji, bez zmartwień.</strong>',
                'buttons' => [['label' => 'REZERWUJ Z ODBIOREM', 'href' => '/rezervace?return_delivery=1', 'cls' => 'btndark pulse']],
            ],
        ],

        'faq' => [
            'seo' => [
                'title' => 'Najczęściej zadawane pytania | MotoGo24',
                'description' => 'Najczęściej zadawane pytania dotyczące wynajmu motocykla. Rezerwacja, odbiór, zwrot, warunki, dostawa, podróże zagraniczne, bony prezentowe.',
                'keywords' => 'FAQ wypożyczalnia motocykli, pytania wynajem motocykla, warunki wynajmu, kaucja, wyposażenie',
            ],
            'h1' => 'Najczęściej zadawane pytania – wypożyczalnia motocykli MotoGo24',
            'closing' => 'Nasza <strong>wypożyczalnia motocykli w Vysočina</strong> jest dla wszystkich, którzy chcą przeżyć <strong>niezapomnianą jazdę</strong> bez zbędnych komplikacji.',
            'cta' => ['label' => 'Zarezerwuj motocykl online', 'href' => '/rezervace'],
        ],

        'home' => [
            'seo' => [
                'title' => 'Wypożyczalnia motocykli w Vysočina | MotoGo24',
                'description' => 'Wypożycz motocykl w Vysočina. Bez kaucji, wyposażenie w cenie, obsługa całodobowa. Motocykle turystyczne, sportowe, enduro i dla dzieci. Rezerwacja online.',
                'keywords' => 'wypożyczalnia motocykli Vysočina, wypożyczalnia motocykli Pelhřimov, wynajem bez kaucji, obsługa całodobowa, motocykle do wynajęcia, rezerwacja online motocykl',
                'og_image' => null,
            ],
            'hero' => [
                'image' => 'gfx/hero-banner.jpg',
                'alt' => 'Wypożyczalnia motocykli Vysočina',
                'eyebrow' => '<strong>Wypożyczalnia motocykli</strong> w Vysočina',
                'body' => 'Wypożycz motocykl w Vysočina łatwo online.<br>Wybierz spośród modeli turystycznych, sportowych i enduro.<br>Rezerwacja z płatnością kartą i szybkim odbiorem.',
                'cta_primary' => ['label' => 'WYBIERZ MOTOCYKL', 'href' => '/katalog', 'cls' => 'btngreen'],
                'cta_secondary' => ['label' => 'JAK TO DZIAŁA', 'href' => '/jak-pujcit', 'cls' => 'btndark'],
            ],
            'h1' => 'Wypożyczalnia motocykli Vysočina Motogo24 – bez kaucji i całodobowo',
            'intro' => 'Witamy w <strong>Motogo24</strong> – twojej wypożyczalni motocykli w Vysočina. U nas wypożyczasz motocykl <strong>bez kaucji</strong>, z wyposażeniem w cenie i w trybie <strong>całodobowym</strong>. Niezależnie czy szukasz motocykla turystycznego, sportowego, enduro czy dla dzieci, Motogo24 w sercu Vysočina ma dla ciebie odpowiedni motocykl.',
            'signposts_title' => 'Szybki przewodnik po Motogo24',
            'signposts' => [
                ['icon' => 'gfx/ico-katalog.svg', 'title' => 'Katalog motocykli', 'text' => 'Zobacz naszą ofertę motocykli do wynajęcia — od sportowych po turystyczne.', 'btn' => 'KATALOG MOTOCYKLI', 'href' => '/katalog'],
                ['icon' => 'gfx/ico-jak.svg', 'title' => 'Jak wypożyczyć motocykl', 'text' => 'Prosty proces: wybierz motocykl, zarezerwuj i ruszaj.', 'btn' => 'JAK WYPOŻYCZYĆ', 'href' => '/jak-pujcit'],
                ['icon' => 'gfx/ico-rezervace.svg', 'title' => 'Rezerwacja online', 'text' => 'Zarezerwuj motocykl przez nasz prosty system online.', 'btn' => 'ZAREZERWUJ MOTOCYKL', 'href' => '/rezervace'],
                ['icon' => 'gfx/ico-kontakt.svg', 'title' => 'Kontakt i mapa', 'text' => 'Odwiedź naszą wypożyczalnię w Pelhřimovie lub skontaktuj się z nami.', 'btn' => 'KONTAKT', 'href' => '/kontakt'],
                ['icon' => 'gfx/ico-faq.svg', 'title' => 'Najczęściej zadawane pytania', 'text' => 'Najczęstsze pytania o wynajem motocykla zebrane w jednym miejscu.', 'btn' => 'FAQ', 'href' => '/jak-pujcit/faq'],
                ['icon' => 'gfx/ico-trasy.svg', 'title' => 'Trasy motocyklowe', 'text' => 'Odkryj najlepsze trasy motocyklowe w Czechach dla turystów i lokalnych.', 'btn' => 'TRASY MOTOCYKLOWE', 'href' => '/blog'],
            ],
            'motos_section' => [
                'title' => 'Nasze motocykle do wynajęcia w Vysočina',
                'intro' => 'Zobacz naszą ofertę motocykli turystycznych, sportowych i enduro z naszej wypożyczalni w Vysočina.',
                'empty' => 'Aktualnie nie mamy dostępnych motocykli.',
                'cta_label' => 'KATALOG MOTOCYKLI',
                'cta_href' => '/katalog',
                'limit' => 4,
            ],
            'process' => [
                'title' => 'Jak działa wypożyczanie motocykli w Vysočina',
                'steps' => [
                    ['icon' => 'gfx/ico-step1.svg', 'title' => '1. Wybierz', 'text' => 'Wybierz idealny motocykl z naszej oferty motocykli do wynajęcia.'],
                    ['icon' => 'gfx/ico-step2.svg', 'title' => '2. Zarezerwuj', 'text' => 'Zarezerwuj motocykl przez nasz prosty system online.'],
                    ['icon' => 'gfx/ico-step3.svg', 'title' => '3. Odbierz', 'text' => 'Odbierz motocykl w naszej wypożyczalni w Pelhřimovie.'],
                    ['icon' => 'gfx/ico-step4.svg', 'title' => '4. Ciesz się jazdą', 'text' => 'Poczuj wolność i odkryj Czechy na motocyklach do wynajęcia.'],
                ],
            ],
            'faq' => [
                'title' => 'Najczęściej zadawane pytania',
                'more_link' => '/jak-pujcit/faq',
                'items' => [
                    ['q' => 'Jak mogę zarezerwować motocykl?', 'a' => 'Motocykl możesz zarezerwować przez nasz system rezerwacji online bezpośrednio na stronie. Lub skontaktuj się z nami przez e-mail, telefon lub media społecznościowe.'],
                    ['q' => 'Czy mogę wypożyczyć motocykl bez wcześniejszej rezerwacji?', 'a' => 'Niestety nie. Każdy motocykl trzeba zarezerwować z wyprzedzeniem — online, telefonicznie, e-mailem lub przez media społecznościowe.'],
                    ['q' => 'Czy muszę wpłacić kaucję?', 'a' => 'Nie! U nas <strong>nie płacisz żadnej kaucji</strong>. Tym fundamentalnie różnimy się od większości konkurencji.'],
                    ['q' => 'Czy mogę pojechać motocyklem za granicę?', 'a' => 'Tak, motocyklem bez problemu pojedziesz za granicę. Podróży poza Czechy nie ograniczamy; trzeba tylko zachować terytorialny zakres ubezpieczenia (zielona karta).'],
                ],
            ],
            'cta' => [
                'title' => 'Zarezerwuj motocykl online',
                'text' => 'Nasza <strong>wypożyczalnia motocykli Vysočina</strong> jest otwarta <strong>całodobowo</strong>. Kilka kliknięć i twoja jazda się rozpoczyna.',
                'buttons' => [
                    ['label' => 'ZAREZERWUJ MOTOCYKL', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
                    ['label' => 'Bon prezentowy', 'href' => '/poukazy', 'cls' => 'btndark'],
                    ['label' => 'Wskazówki dotyczące tras', 'href' => '/blog', 'cls' => 'btndark'],
                ],
            ],
            'blog' => [
                'title' => 'Blog i wskazówki',
                'empty' => 'Brak artykułów.',
                'cta_label' => 'CZYTAJ WIĘCEJ NA BLOGU',
                'cta_href' => '/blog',
                'limit' => 3,
            ],
            'reviews' => [
                'title' => 'Co mówią nasi klienci',
                'intro' => 'Prawdziwe opinie motocyklistów, którzy u nas wynajmowali. Dziękujemy za każdą ocenę.',
            ],
        ],

        'pujcovna' => [
            'seo' => [
                'title' => 'O wypożyczalni motocykli | MotoGo24',
                'description' => 'Wypożyczalnia motocykli Motogo24 w Vysočina. Bez kaucji, z rezerwacją online i wyposażeniem w cenie. Motocykle turystyczne, sportowe, enduro i dla dzieci.',
                'keywords' => 'wypożyczalnia motocykli, wynajem motocykli Vysočina, motocykle bez kaucji, obsługa całodobowa, wyposażenie w cenie',
            ],
            'breadcrumb' => [['label' => 'Strona główna', 'href' => '/'], 'Wypożyczalnia motocykli'],
            'intro' => [
                'h1' => 'Wypożyczalnia motocykli Vysočina Motogo24',
                'body' => 'Nasza <strong>wypożyczalnia motocykli w Vysočina</strong> w Pelhřimov oferuje <strong>wynajem motocykli</strong> bez zbędnych przeszkód – <strong>bez kaucji</strong>, z <strong>rezerwacją online</strong> i <strong>wyposażeniem w cenie</strong>. Wybierz spośród <strong>motocykli turystycznych</strong>, <strong>sportowych</strong>, <strong>enduro</strong> i <strong>dla dzieci</strong>, i wyrusz kiedy chcesz: jesteśmy otwarci <strong>całodobowo</strong>.',
            ],
            'benefits' => [
                'title' => 'Dlaczego wypożyczać u nas',
                'closing' => 'Szukasz <strong>wypożyczalni motocykli w Vysočina</strong>? Motogo24 oferuje uczciwe warunki, jasny proces i doskonale utrzymane maszyny do podróży po Czechach i za granicą.',
                'buttons' => [
                    ['label' => 'Zobacz motocykle do wynajęcia', 'href' => '/katalog', 'cls' => 'btngreen'],
                    ['label' => 'REZERWUJ', 'href' => '/rezervace', 'cls' => 'btngreen pulse'],
                ],
                'items' => [
                    ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'Bez kaucji', 'text' => 'i bez ukrytych opłat'],
                    ['icon' => 'gfx/ico-online-rez.svg', 'title' => 'Rezerwacja online', 'text' => 'w kilka kliknięć'],
                    ['icon' => 'gfx/ico-vybava.svg', 'title' => 'Wyposażenie kierowcy w cenie', 'text' => 'kask, kurtka, spodnie i rękawice'],
                    ['icon' => 'gfx/ico-nonstop.svg', 'title' => 'Obsługa całodobowa', 'text' => 'do odbioru i zwrotu zgodnie z rezerwacją'],
                    ['icon' => 'gfx/ico-spolecne.svg', 'title' => 'Jesteśmy razem', 'text' => 'gdy coś się wydarzy'],
                    ['icon' => 'gfx/ico-pristaveni.svg', 'title' => 'Dostawa i odbiór motocykla', 'text' => 'w umówione miejsce'],
                ],
            ],
            'process' => [
                'title' => 'Jak działa wypożyczanie w Vysočina',
                'steps' => [
                    ['icon' => 'gfx/ico-step1.svg', 'title' => '1. Wybierz motocykl', 'text' => 'Zobacz naszą ofertę i wybierz typ, który ci odpowiada, twoim doświadczeniom i prawu jazdy.'],
                    ['icon' => 'gfx/ico-step3.svg', 'title' => '2. Zarezerwuj online', 'text' => 'Zarezerwuj według daty lub konkretnego motocykla, który chcesz wypożyczyć.'],
                    ['icon' => 'gfx/ico-step4.svg', 'title' => '3. Wybierz wyposażenie', 'text' => 'Wyposażenie kierowcy jest w cenie, dla pasażera za dopłatą. Rozmiar wybierzesz na miejscu.'],
                    ['icon' => 'gfx/ico-step5.svg', 'title' => '4. Zapłać', 'text' => 'Zapłać prosto online przez bramkę płatności.'],
                    ['icon' => 'gfx/ico-step6.svg', 'title' => '5. Odbierz motocykl', 'text' => 'Odbierz motocykl bezpośrednio w wypożyczalni lub w wybranym przy rezerwacji miejscu.'],
                    ['icon' => 'gfx/ico-step7.svg', 'title' => '6. Ciesz się jazdą', 'text' => 'Wyrusz w drogę, odkrywaj nowe doświadczenia i ciesz się pełną wolnością na dwóch kołach.'],
                    ['icon' => 'gfx/ico-step8.svg', 'title' => '7. Zwróć motocykl', 'text' => 'Po prostu zwróć motocykl w umówionym dniu – w wypożyczalni lub w umówionym miejscu.'],
                    ['icon' => 'gfx/ico-sleva.svg', 'title' => 'Zniżka na kolejną jazdę', 'text' => 'Po zwrocie motocykla automatycznie wyślemy ci kod rabatowy 200 Kč na kolejną rezerwację.'],
                ],
            ],
            'faq' => [
                'title' => 'Najczęściej zadawane pytania',
                'more_link' => '/jak-pujcit/faq',
                'items' => [
                    ['q' => 'Jak mogę zarezerwować motocykl?', 'a' => 'Motocykl możesz zarezerwować przez nasz system rezerwacji online bezpośrednio na stronie. Lub skontaktuj się z nami e-mailem, telefonicznie lub przez media społecznościowe.'],
                    ['q' => 'Czy mogę wypożyczyć motocykl bez wcześniejszej rezerwacji?', 'a' => 'Niestety nie. Każdy motocykl trzeba zarezerwować z wyprzedzeniem.'],
                    ['q' => 'Czy muszę wpłacić kaucję?', 'a' => 'Nie! U nas <strong>nie płacisz żadnej kaucji</strong>. Tym fundamentalnie różnimy się od większości konkurencji.'],
                    ['q' => 'Czy mogę pojechać motocyklem za granicę?', 'a' => 'Tak, motocyklem bez problemu pojedziesz za granicę. Podróży poza Czechy nie ograniczamy; trzeba tylko zachować terytorialny zakres ubezpieczenia (zielona karta).'],
                ],
            ],
            'cta' => [
                'title' => 'Zarezerwuj motocykl online',
                'text' => 'Nasza <strong>wypożyczalnia motocykli Vysočina</strong> jest otwarta <strong>całodobowo</strong>.',
                'buttons' => [
                    ['label' => 'ZAREZERWUJ MOTOCYKL', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
                    ['label' => 'Bon prezentowy', 'href' => '/poukazy', 'cls' => 'btndark'],
                    ['label' => 'Wskazówki dotyczące tras', 'href' => '/blog', 'cls' => 'btndark'],
                ],
            ],
        ],

        'kontakt' => [
            'seo' => [
                'title' => 'Kontakt | MotoGo24 – wypożyczalnia motocykli Vysočina',
                'description' => 'Kontakty do wypożyczalni motocykli Motogo24 w Pelhřimov. Telefon +420 774 256 271, e-mail info@motogo24.cz. Obsługa całodobowa, adres Mezná 9, 393 01 Pelhřimov.',
                'keywords' => 'kontakt Motogo24, wypożyczalnia motocykli Pelhřimov, telefon, adres, godziny otwarcia, całodobowo',
            ],
            'h1' => 'Kontakt – wypożyczalnia motocykli Motogo24',
            'intro' => 'Masz pytanie dotyczące <strong>wynajmu motocykla</strong>, chcesz zamówić <strong>bon prezentowy</strong>, potrzebujesz pomocy w wyborze albo chcesz od razu <strong>umówić rezerwację</strong>? Jesteśmy dla ciebie codziennie, <strong>całodobowo</strong>.',
            'side_cta' => [
                'title' => 'Chcesz umówić rezerwację?',
                'text' => 'Zarezerwuj motocykl online w kilka minut i wyrusz na przygodę.',
                'button' => ['label' => 'REZERWUJ ONLINE', 'href' => '/rezervace', 'cls' => 'btndark'],
            ],
            'social_title' => 'Śledź nas',
            'map' => ['title' => 'Gdzie nas znaleźć'],
            'seo_text' => [
                'title' => 'Kontakt – wypożyczalnia motocykli Vysočina (Pelhřimov)',
                'body' => 'Motogo24 to <strong>nowoczesna wypożyczalnia motocykli w Vysočina</strong>. Mieścimy się w <strong>Pelhřimov</strong>, jesteśmy otwarci <strong>całodobowo</strong> i wypożyczamy <strong>bez kaucji</strong>, z kompletnym <strong>wyposażeniem w cenie</strong>.',
            ],
        ],

        'jak_pujcit' => [
            'seo' => [
                'title' => 'Jak wypożyczyć motocykl | MotoGo24',
                'description' => 'Jak wypożyczyć motocykl w Motogo24. Prosty proces: wybór, rezerwacja, odbiór. Bez kaucji, wyposażenie w cenie, obsługa całodobowa.',
                'keywords' => 'jak wypożyczyć motocykl, proces wypożyczenia, rezerwacja motocykla, wypożyczalnia motocykli Vysočina',
            ],
            'h1' => 'Jak wypożyczyć motocykl',
            'intro' => 'W <strong>Motogo24 – wypożyczalni motocykli w Vysočina</strong> wypożyczanie jest proste, szybkie i uczciwe.',
        ],

        'jak_pujcit_postup' => [
            'seo' => [
                'title' => 'Proces wypożyczenia motocykla | MotoGo24',
                'description' => 'Proces wypożyczenia motocykla w Motogo24 krok po kroku. Rezerwacja online, wyposażenie w cenie, bez kaucji, obsługa całodobowa i dostawa.',
                'keywords' => 'proces wypożyczenia motocykla, jak wypożyczyć motocykl, rezerwacja motocykla, wypożyczalnia motocykli Pelhřimov',
            ],
            'h1' => 'Proces wypożyczenia motocykla',
            'intro' => '<p>W <strong>Motogo24 – wypożyczalni motocykli w Vysočina</strong> wypożyczanie jest proste, szybkie i uczciwe. <strong>Bez kaucji, z wyposażeniem w cenie i obsługą całodobową</strong>.</p>',
            'cta' => [
                'title' => 'Gotowy na jazdę?',
                'text' => 'Zarezerwuj motocykl online już dziś i ciesz się <strong>wolnością na dwóch kołach</strong>.',
                'buttons' => [['label' => 'REZERWUJ ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
            ],
        ],

        'jak_pujcit_vyzvednuti' => [
            'seo' => [
                'title' => 'Odbiór motocykla w wypożyczalni | MotoGo24',
                'description' => 'Odbiór motocykla w wypożyczalni Pelhřimov. Obsługa całodobowa, bez kaucji, wyposażenie w cenie. Co zabrać i jak przebiega odbiór.',
                'keywords' => 'odbiór motocykla wypożyczalnia, odebranie motocykla, wypożyczalnia Pelhřimov, całodobowy odbiór',
            ],
            'h1' => 'Odbiór motocykla w wypożyczalni – szybko, łatwo i całodobowo',
            'intro' => 'W <strong>Motogo24 – wypożyczalni motocykli Vysočina</strong> <strong>odbiór motocykla</strong> trwa kilka minut.',
            'top_cta' => ['label' => 'REZERWUJ ONLINE', 'href' => '/rezervace'],
            'cta' => [
                'title' => 'Odbiór motocykla w wypożyczalni – Motogo24 Vysočina',
                'text' => 'Motogo24 to <strong>wypożyczalnia motocykli w Vysočina</strong> z <strong>całodobowym odbiorem i zwrotem</strong>.',
                'buttons' => [['label' => 'REZERWUJ ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
            ],
        ],

        'jak_pujcit_vraceni_pujcovna' => [
            'seo' => [
                'title' => 'Zwrot motocykla w wypożyczalni | MotoGo24',
                'description' => 'Zwrot motocykla bezpośrednio w wypożyczalni Pelhřimov. Całodobowo, bez kaucji, bez zbędnej biurokracji.',
                'keywords' => 'zwrot motocykla, zwrot w wypożyczalni, wypożyczalnia Pelhřimov, całodobowy zwrot',
            ],
            'h1' => 'Zwrot motocykla w wypożyczalni',
            'intro' => 'Motocykl wracasz wygodnie bezpośrednio w <strong>Motogo24 – wypożyczalni motocykli w Vysočina</strong>. <strong>Obsługa całodobowa</strong>, bez stresu.',
            'top_cta' => ['label' => 'REZERWUJ ONLINE', 'href' => '/rezervace'],
            'cta' => [
                'title' => 'Zwrot motocykla w wypożyczalni – Motogo24 Pelhřimov',
                'text' => 'Wróć motocyklem bezpośrednio do nas w Pelhřimov – <strong>całodobowo, bez kaucji, bez stresu</strong>.',
                'buttons' => [['label' => 'REZERWUJ ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
            ],
        ],

        'poukazy' => [
            'seo' => [
                'title' => 'Wypożyczalnia motocykli Vysočina – Bony',
                'description' => 'Kup bon prezentowy na wynajem motocykla. Ważność 3 lata, bez kaucji, wyposażenie w cenie. Bon elektroniczny i drukowany.',
                'keywords' => 'bon prezentowy motocykl, voucher wynajem motocykla, prezent dla motocyklisty, bon Motogo24',
                'og_image' => 'https://motogo24.cz/gfx/darkovy-poukaz.jpg',
            ],
            'h1' => 'Kup bon prezentowy – podaruj przygodę na dwóch kołach!',
            'cta' => [
                'title' => 'Bon prezentowy na wynajem motocykla – Vysočina',
                'text' => 'Motogo24 to <strong>wypożyczalnia motocykli w Vysočina</strong> z <strong>obsługą całodobową</strong>, <strong>bez kaucji</strong> i <strong>wyposażeniem w cenie</strong>.',
                'buttons' => [['label' => 'ZAMÓW BON', 'href' => '/koupit-darkovy-poukaz', 'cls' => 'btndark pulse']],
            ],
        ],
    ],
];
