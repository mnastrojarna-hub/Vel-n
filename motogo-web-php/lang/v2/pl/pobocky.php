<?php
// PL překlad textů poboček (Velín → Texty webu → Pobočky, klíče web.pobocky.*; aktuální
// CS hodnoty z CMS k 2026-10-10, u výbavy Velkých Němčic už nové velikosti z data/pobocky.php
// — helmy S–3XL, bundy/kalhoty/rukavice do 4XL). Ruční PL texty, tykání „ty“, kauce = „kaucja“.
// Struktura = lang/v2/es/pobocky.php (= pobockyDefaults() bez polí jen z kódu: slug, branch_id,
// map, photo, gallery, video). siteContent('pobocky') použije tento overlay, protože CMS klíče
// bez PL překladu se pro PL přeskakují. Texty v2 (karty, průvodce, srovnání): lang/v2/pl/pobocky-v2.php.

return ['pages' => ['pobocky' => [
    'seo' => [
        'title' => 'Oddziały | MotoGo24 – wypożyczalnia motocykli Pelhřimov i Brno',
        'description' => 'Oddziały wypożyczalni motocykli MotoGo24: oddział z obsługą Mezná koło Pelhřimova (Wysoczyna) i oddział samoobsługowy Velké Němčice koło Brna – odbiór motocykla o każdej porze.',
        'keywords' => 'oddziały MotoGo24, wypożyczalnia motocykli Pelhřimov, wypożyczalnia motocykli Brno, samoobsługowa wypożyczalnia motocykli, Velké Němčice, Mezná',
    ],
    'h1' => 'Oddziały MotoGo24',
    'intro' => 'Motocykl odbierzesz w <strong>dwóch miejscach</strong>: w <strong>oddziale z obsługą Mezná koło Pelhřimova</strong>, gdzie przywitamy cię osobiście, lub w <strong>oddziale samoobsługowym Velké Němčice koło Brna</strong>, gdzie motocykl i wyposażenie odbierasz samodzielnie za pomocą kodów.',
    'branches' => [
        [
            'badge' => 'Oddział z obsługą',
            'title' => 'Mezná koło Pelhřimova',
            'address' => 'Mezná 9, 393 01 Pelhřimov',
            'hours' => 'Od poniedziałku do niedzieli, o dowolnej porze (nonstop), także w weekendy i święta. Godzinę odbioru i zwrotu wybierasz w rezerwacji.',
            'text' => 'Nasz główny oddział w regionie Wysoczyna. Motocykl <strong>przekażemy ci osobiście</strong>: wszystko wyjaśnimy, pomożemy w ustawieniu i wyborze wyposażenia, a protokół przekazania przejdziemy razem. Wyposażenie kierowcy jest w cenie. Stąd oferujemy też <strong>dostawę motocykla</strong> pod wybrany przez ciebie adres.',
            'gear' => 'Wyposażenie kierowcy w cenie: kurtki i spodnie w rozmiarach do <strong>6XL</strong>. Tylko tutaj wypożyczysz też <strong>odzież przeciwdeszczową</strong> i inne dodatkowe wyposażenie.',
            'steps_title' => 'Jak to przebiega',
            'steps' => '1. Rezerwujesz i płacisz online (strona lub aplikacja) i przesyłasz dokumenty (dowód osobisty/paszport + prawo jazdy); prosimy o to również w oddziale z obsługą: jeśli ich nie prześlesz, sprawdzimy je przy odbiorze na miejscu.<br>2. O wybranej godzinie przyjeżdżasz do oddziału, gdzie na ciebie czekamy.<br>3. Przekazujemy ci motocykl i wyposażenie, a następnie podpisujemy protokół przekazania.<br>4. Po jeździe oddajesz motocykl w oddziale (albo odbierzemy go pod umówionym adresem).',
            'video_title' => 'Wideo: jak to przebiega w oddziale',
            'gallery_title' => 'Galeria zdjęć oddziału',
            'seo_title' => 'Oddział Mezná koło Pelhřimova | MotoGo24 – wypożyczalnia motocykli z obsługą',
            'seo_description' => 'Oddział z obsługą wypożyczalni motocykli MotoGo24 – Mezná koło Pelhřimova (Wysoczyna): osobiste przekazanie motocykla o każdej porze, wyposażenie w cenie, dostawa pod adres.',
        ],
        [
            'badge' => 'Oddział samoobsługowy',
            'title' => 'Velké Němčice koło Brna',
            'address' => 'Boudky, 691 63 Velké Němčice',
            'hours' => 'Czynny 24/7 z kodem z aplikacji. Godzinę odbioru wybierasz w rezerwacji: przy odbiorze od 12:00 (wynajem na 2 dni lub dłużej) 1. dzień masz za pół ceny, a kiosk wyda ci motocykl dopiero od 12:00. Godziny zwrotu nie wybierasz: motocykl oddajesz o dowolnej porze ostatniego dnia wynajmu, do 24:00.',
            'text' => 'Nowoczesny <strong>oddział samoobsługowy</strong> na południe od Brna. Na miejscu nie ma obsługi: wszystko załatwiasz samodzielnie na ekranie dotykowym za pomocą <strong>kodów z aplikacji</strong>, które dostajesz po opłaceniu rezerwacji i uzupełnieniu dokumentów. Motocykle z tego oddziału odbiera się i zwraca tylko na miejscu: nie oferujemy dostawy ani odbioru spod adresu. Przy oddziale możesz przez cały czas wynajmu <strong>parkować za darmo</strong>.',
            'gear' => 'Dostępne są tylko <strong>kask, kurtka z ochraniaczem pleców, spodnie, rękawice, kominiarka i buty</strong>: wyposażenie kierowcy jest w cenie, buty motocyklowe za dopłatą. Kaski w rozmiarach <strong>S–3XL</strong>; kurtki, spodnie i rękawice do rozmiaru <strong>4XL</strong> (większe rozmiary, do 6XL, mamy w oddziale Mezná). W oddziale samoobsługowym nie wypożyczamy <strong>odzieży przeciwdeszczowej</strong> ani innego dodatkowego wyposażenia: są tylko w oddziale z obsługą Mezná. Wyposażenie przymierzysz w szatni, a jeśli rozmiar nie pasuje, weź inny dostępny i po prostu zaznacz go w protokole przekazania. Kamizelkę odblaskową, apteczkę, oświadczenie o zdarzeniu drogowym, blokadę tarczy i kluczyk do uchwytu na telefon znajdziesz w motocyklu.',
            'steps_title' => 'Jak to przebiega',
            'steps' => '1. Rezerwujesz i płacisz online, wybierasz godzinę odbioru i przesyłasz dokumenty (dowód osobisty/paszport + prawo jazdy): w oddziale samoobsługowym to konieczne – bez zweryfikowanych dokumentów nie dostaniesz kodów i nie wejdziesz do oddziału. Po weryfikacji dokumentów dostaniesz w aplikacji, e-mailem i SMS-em kody w kolejności, w jakiej będziesz je wpisywać: <strong>1) kod skrytki z kluczem do bramy, 2) kod szatni</strong> (jeśli wypożyczasz wyposażenie) <strong>i 3) kod motocykla</strong>.<br>2. <strong>Jeśli brama wjazdowa jest zamknięta</strong>, otwórz kodem z aplikacji <strong>górną skrytkę na prawym słupku bramy</strong>: jest w niej klucz do kłódki. Otwórz bramę, wjedź do środka i zaparkuj na dowolnym miejscu <strong>1–7, po prawej przy ogrodzeniu</strong> (zobacz zdjęcie parkingu). Auto może tu stać za darmo przez cały czas wynajmu. Jeśli brama jest otwarta, kod skrytki nie jest potrzebny.<br>3. Na ekranie wpisujesz kod szatni: <strong>szatnia to drzwi nr 8</strong>. Bierzesz wyposażenie, przebierasz się i zamykasz drzwi szatni (z własnym wyposażeniem pomijasz szatnię). Jeśli masz zniżkę za odbiór od 12:00, kody działają dopiero od 12:00.<br>4. Na ekranie poprawiasz rozmiary w protokole przekazania, podpisujesz go i wpisujesz kod motocykla: otwiera się boks z twoim motocyklem. Zamykasz boks i ruszasz w drogę!<br>5. <strong>Jeśli brama była zamknięta, po wyjeździe znów ją zamknij, zapnij kłódkę, odłóż klucz do górnej skrytki i pomieszaj cyfry szyfru.</strong> Jeśli brama jest otwarta, zostaw ją otwartą: nigdy nie zmieniaj stanu bramy.<br>6. Po jeździe oddajesz motocykl do boksu, a wyposażenie do szatni, o dowolnej porze ostatniego dnia wynajmu, do 24:00. Jeśli brama jest zamknięta, postępujesz tak samo: otwierasz ją kluczem ze skrytki, a po wyjeździe znów zamykasz na kłódkę i odkładasz klucz.',
            'video_title' => 'Wideo: jak korzystać z oddziału samoobsługowego',
            'gallery_title' => 'Galeria zdjęć oddziału',
            'seo_title' => 'Oddział samoobsługowy Velké Němčice koło Brna | MotoGo24',
            'seo_description' => 'Samoobsługowy oddział wypożyczalni motocykli MotoGo24 – Velké Němčice koło Brna: odbiór i zwrot 24/7 z kodem z aplikacji, godzinę odbioru wybierasz w rezerwacji (od 12:00 1. dzień za pół ceny), bezpłatny parking.',
        ],
    ],
    'detail_button' => 'Szczegóły oddziału',
    'back_link' => '← Wszystkie oddziały',
    'cta' => [
        'title' => 'Wybierz motocykl w swoim oddziale',
        'text' => 'W rezerwacji wybierasz oddział i widzisz tylko motocykle, które są w nim dostępne.',
        'button' => 'ZAREZERWUJ ONLINE',
    ],
]]];
