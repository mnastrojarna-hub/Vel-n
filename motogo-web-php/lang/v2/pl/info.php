<?php
// Landing v2 — informační stránky (Jak si půjčit ×8, FAQ, Kontakt): texty nových
// prvků wrapperu landing-info.php (hero tlačítka a chipy, AI asistent, karty
// poboček na Kontaktu). Ruční PL texty, tykání „ty“, kauce = „kaucja“, měna zł.
// Struktura = lang/v2/es/info.php (schválený pilot); CS defaulty: lpiDefaults() v landing-info.php.
return ['pages' => ['landing_info' => [
    'cta_primary' => 'ZAREZERWUJ',
    'cta_secondary' => 'ZOBACZ MOTOCYKLE',
    'cta_call' => 'ZADZWOŃ',
    'reserve' => 'Zarezerwuj motocykl',
    'steps_title' => 'Krok po kroku',
    'read_more' => 'Czytaj dalej',
    'read_less' => 'Pokaż mniej',
    'chips' => [
        'postup' => ['Bez kaucji', 'Wyposażenie w cenie', 'Rezerwacja online w kilka minut'],
        'prevzeti' => ['Odbiór o wybranej godzinie', 'Bezpłatny parking', 'Bez kaucji'],
        'vraceni_pujcovna' => ['Ostatni dzień do 24:00', 'Bez tankowania', 'Bez kaucji'],
        'vraceni_jinde' => ['W całych Czechach', 'Jasny cennik za km', 'Bez kaucji'],
        'cena' => ['0 zł kaucji', 'Wyposażenie kierowcy w cenie', 'Bez ukrytych opłat'],
        'pristaveni' => ['Do domu, hotelu lub na dworzec', 'W całych Czechach', 'Bez kaucji'],
        'dokumenty' => ['Bez kaucji', 'Przejrzysta umowa', 'Bezpieczna płatność online'],
        'faq' => ['Bez kaucji', 'Wyposażenie kierowcy w cenie', 'Asystent AI 24/7'],
        'kontakt' => ['2 oddziały: Vysočina i Brno', 'Samoobsługa 24/7 pod Brnem', 'Ok. 90 min z Pragi'],
    ],
    'ai' => [
        'title' => 'Asystent AI 24/7',
        'text' => 'Nie znalazłeś odpowiedzi? Zapytaj Tomáša: odpowie od razu, w dzień i w nocy.',
        'card' => 'Zapytaj Tomáša: odpowie od razu',
        'btn' => 'Zapytaj',
    ],
    'contact' => [
        'branches_title' => 'Nasze oddziały',
        'detail' => 'Szczegóły oddziału',
        'route' => 'Wyznacz trasę',
        'branches' => [
            [
                'badge' => 'Oddział z obsługą',
                'title' => 'Mezná (Pelhřimov, Vysočina)',
                'text' => 'Motocykl przekażemy ci osobiście o godzinie podanej w rezerwacji, codziennie, także w weekendy i święta.',
                'chips' => ['Ok. 90 min z Pragi', 'Dostawa pod adres'],
            ],
            [
                'badge' => 'Samoobsługa 24/7',
                'title' => 'Velké Němčice (pod Brnem)',
                'text' => 'Motocykl i wyposażenie odbierasz i zwracasz sam, za pomocą kodów z aplikacji: w 100% non stop, bez czekania.',
                'chips' => ['30 min z Brna', '35 min z lotniska w Brnie'],
            ],
        ],
    ],
]]];
