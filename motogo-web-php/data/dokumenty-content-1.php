<?php
// ===== MotoGo24 — Dokumenty a navody 1/2 (intro + benefity + pozadavky + platby) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/dokumenty-a-navody

return [
    'h1' => 'Nájemní smlouva a kauce – férové podmínky bez zálohy',
    'intro' => 'V <strong>Motogo24 – půjčovna motorek Vysočina (Pelhřimov)</strong> klademe důraz na jednoduchost a férovost. Půjčujeme <strong>bez kauce</strong>, s <strong>jasnou nájemní smlouvou</strong>, <strong>pojištěním v ceně</strong> a <strong>výbavou pro řidiče</strong> zahrnutou v půjčovném.',
    'top_cta' => [
        'label' => 'REZERVOVAT ONLINE',
        'href' => '/rezervace',
        'aria' => 'Přejít na online rezervaci motorky podle nájemní smlouvy Motogo24',
    ],
    'summary' => [
        'title' => 'Shrnutí hlavních bodů',
        'items' => [
            [
                'icon' => 'gfx/ico-bez-kauce.svg',
                'title' => 'Bez kauce / zálohy',
                'text' => 'motorku půjčujeme bez blokace peněz',
            ],
            [
                'icon' => 'gfx/ico-pojisteni.svg',
                'title' => 'Pojištění',
                'text' => 'v ceně (povinné ručení; havarijní dle konkrétního modelu a podmínek)',
            ],
            [
                'icon' => 'gfx/ico-vybava.svg',
                'title' => 'Výbava pro řidiče',
                'text' => 'v ceně (helma, bunda, kalhoty, rukavice)',
            ],
            [
                'icon' => 'gfx/ico-nonstop.svg',
                'title' => 'Nonstop provoz',
                'text' => 'převzetí a vrácení kdykoli v den výpůjčky',
            ],
            [
                'icon' => 'gfx/ico-jasna-pravidla.svg',
                'title' => 'Jasná pravidla užívání',
                'text' => 'doma i v zahraničí (podle zelené karty)',
            ],
            [
                'icon' => 'gfx/ico-bezskryte.svg',
                'title' => 'Žádné skryté poplatky',
                'text' => 'vše je uvedeno níže a ve smlouvě',
            ],
        ],
    ],
    'required_docs' => [
        'title' => 'Co potřebujete k uzavření smlouvy',
        'items' => [
            '<strong>Občanský průkaz / pas</strong>',
            '<strong>Řidičský průkaz</strong>&nbsp;odpovídající skupiny (A / A2 dle stroje)',
            '<strong>Věk</strong>&nbsp;min. 18 let (u dětských motorek ručí zákonný zástupce)',
            '<strong>Kontakty</strong>&nbsp;(telefon, e-mail) pro komunikaci a potvrzení rezervace',
        ],
    ],
    'payments' => [
        'title' => 'Platby, storno a poplatky',
        'lead' => '<strong>Kauce:</strong>&nbsp;<em>nevyžadujeme</em>. Platba za nájem probíhá online nebo při převzetí.',
        'aria' => 'Přehled plateb a poplatků',
        'headers' => ['Položka', 'Podmínky'],
        'rows' => [
            ['<strong>Platba nájemného</strong>', 'Online předem.'],
            ['<strong>Storno rezervace</strong>', 'Lze bezplatně do předem domluveného času (uvedeno v potvrzení rezervace). Později dle individuální dohody.'],
            ['<strong>Palivo &amp; čištění</strong>', 'Vrácení bez povinnosti dotankovat a mýt. Případné nadměrné znečištění řešíme individuálně.'],
            ['<strong>Přistavení / svoz</strong>', 'Dle ceníku přistavení (Vysočina / okolí). Potvrzujeme při rezervaci.'],
            ['<strong>Pozdní vrácení</strong>', 'Prosíme o včasné vrácení v poslední den výpůjčky; při zpoždění účtujeme dle domluvy (ohled na další rezervace).'],
        ],
        'mid_cta' => [
            'label' => 'POKRAČOVAT K REZERVACI',
            'href' => '/rezervace',
            'aria' => 'Zarezervovat motorku a souhlasit s nájemní smlouvou Motogo24',
        ],
    ],
];
