<?php
// ===== MotoGo24 — Postup pujceni motorky 1/2 (intro + proces 12x) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/postup-pujceni-motorky
// POZN: V originale jsou drobne preklepy ("pujcove" misto "pujcovne",
//       dvojite ".." na konci paragraphu). Zachovavame 1:1.

return [
    'h1' => 'Postup půjčení motorky',
    // POZOR: V originalu je preklep "pujcove" - zachovavame 1:1
    'intro_p1' => 'V <strong>Motogo24 – půjčově motorek na Vysočině</strong> je půjčení jednoduché, rychlé a férové.&nbsp;<strong>Bez kauce, s výbavou pro řidiče v ceně a nonstop provozem pro půjčení a vrácení motorky</strong>. Přesvědč se, jak snadno to funguje.',
    'intro_h2' => 'Jak si půjčit motorku – půjčovna Motogo24 – Vysočina',
    // POZOR: V originalu je dvojita tecka ".." na konci - zachovavame 1:1
    'intro_p2' => 'V naší <strong>motopůjčovně </strong>zvládneš vše online: vyber motorku, zvol termín a vyplň rezervační formulář – včetně výbavy a způsobu předání. Motorku si vyzvedni v Pelhřimově, nebo si objednej přistavení kamkoliv v ČR. Platbu provedeš online při dokončení rezervace..',
    'process' => [
        'title' => 'Jak probíhá pronájem krok za krokem',
        'grid' => 'gr4',
        'steps' => [
            [
                'icon' => 'gfx/ico-step-vyber.svg',
                'title' => '1. Vyber motorku',
                'text' => 'Prohlédni si naši nabídku&nbsp;<strong>cestovních, supermoto, naked a dětských motorek</strong>&nbsp;a vyber si tu pravou.',
            ],
            [
                'icon' => 'gfx/ico-step-termin.svg',
                'title' => '2. Zvol termín',
                'text' => 'V kalendáři vyber datum, kdy chceš vyjet. Uvidíš, které motorky jsou volné.',
            ],
            [
                'icon' => 'gfx/ico-step-udaje.svg',
                'title' => '3. Kontaktní údaje',
                'text' => 'Vyplň jméno, adresu, e-mail a telefon.',
            ],
            [
                'icon' => 'gfx/ico-step-cas.svg',
                'title' => '4. Čas převzetí',
                'text' => 'Zvol, kdy si motorku vyzvedneš nebo kdy ji přistavíme.',
            ],
            [
                'icon' => 'gfx/ico-step-predani.svg',
                'title' => '5. Zvol si předání',
                'text' => 'Vyber způsob převzetí – osobně v Pelhřimově, nebo přistavení kamkoliv v ČR.&nbsp;',
            ],
            [
                'icon' => 'gfx/ico-step-vraceni.svg',
                'title' => '6. Zvol si vrácení',
                'text' => 'Vyber, jestli budeš motorku vracet na adrese motopůjčovny, nebo jinde.',
            ],
            [
                'icon' => 'gfx/ico-step-vybava.svg',
                'title' => '7. Výbava',
                'text' => 'Základní výbava řidiče je v ceně. Chceš výbavu pro spolujezdce, zapůjčit boty nebo jedeš s vlastní výbavou? Zaškrtneš při rezervaci.',
            ],
            [
                'icon' => 'gfx/ico-step-platba.svg',
                'title' => '8. Shrnutí objednávky a platba',
                'text' => 'Zkontroluj shrnutí objednávky, odsouhlas podmínky a zaplať online platební kartou.',
            ],
            [
                'icon' => 'gfx/ico-step-email.svg',
                'title' => '9. Potvrzení e-mailem',
                'text' => 'Po dokončení rezervace ti přijde e-mail s potvrzením rezervace a platby, dokladem o platbě, předvyplněnou nájemní smlouvou a základními instrukcemi pro vyzvednutí motorky.',
            ],
            [
                'icon' => 'gfx/ico-step-prevzeti.svg',
                'title' => '10. Převzetí motorky',
                'text' => 'Při předání zkontrolujeme doklady, doplníme smlouvu a podepíšeme předávací protokol. Vyzkouší se velikost výbavy – a pak už jen nastartovat!',
            ],
            [
                'icon' => 'gfx/ico-step-jizda.svg',
                'title' => '11. Užij si jízdu',
                'text' => 'Vyraz na cestu – <strong>bez kauce, bez stresu</strong>. Zbytek je jen asfalt a svoboda.',
            ],
            [
                'icon' => 'gfx/ico-step-final-vraceni.svg',
                'title' => '12. Vrácení motorky',
                'text' => 'Motorku vrať včas – osobně do půjčovny v Pelhřimově, nebo na předem sjednané místo. Nemusíš tankovat ani mýt.',
            ],
        ],
    ],
];
