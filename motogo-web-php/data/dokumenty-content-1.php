<?php
// ===== MotoGo24 — Dokumenty a navody 1/2 (intro + benefity + pozadavky + platby) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/dokumenty-a-navody

return [
    'h1' => 'Podmínky půjčení motorky a dokumenty ke stažení',
    'intro' => 'Na této stránce najdeš přehled nejdůležitějších pravidel: co potřebuješ k uzavření smlouvy, jak se platí, kolik stojí storno a za co odpovídáš. Níže si stáhneš <strong>obchodní podmínky, vzor smlouvy o pronájmu a protokoly v PDF</strong>.',
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
                'title' => 'Žádná kauce',
                'text' => 'nic ti neblokujeme na kartě ani nechceme hotovost',
            ],
            [
                'icon' => 'gfx/rezervace-online.svg',
                'title' => 'Online rezervace',
                'text' => 'včetně platby',
            ],
            [
                'icon' => 'gfx/vyber-vybavu.svg',
                'title' => 'Výbava pro řidiče',
                'text' => 'v ceně (helma, bunda, kalhoty, rukavice)',
            ],
            [
                'icon' => 'gfx/ico-nonstop.svg',
                'title' => 'Nonstop provoz',
                'text' => 'čas převzetí si zvolíš v rezervaci, vrátit můžeš kdykoli poslední den do 24:00',
            ],
            [
                'icon' => 'gfx/jasne-podminky.svg',
                'title' => 'Jasná pravidla užívání',
                'text' => 'doma i v zahraničí (podle zelené karty)',
            ],
            [
                'icon' => 'gfx/zadne-skryte-poplatky.svg',
                'title' => 'Žádné skryté poplatky',
                'text' => 'vše je uvedeno níže a ve smlouvě',
            ],
        ],
    ],
    'required_docs' => [
        'title' => 'Co potřebujete k uzavření smlouvy',
        'items' => [
            '<strong>Občanský průkaz / pas</strong>',
            '<strong>Řidičský průkaz</strong>&nbsp;odpovídající skupiny (A, A2 nebo A1/B podle motorky)',
            '<strong>Věk</strong>&nbsp;alespoň 18 let (u dětských motorek je nájemcem zákonný zástupce dítěte, např. rodič)',
            '<strong>Kontakty</strong>&nbsp;(telefon, e-mail) pro komunikaci a potvrzení rezervace',
        ],
    ],
    'payments' => [
        'title' => 'Platby, storno a poplatky',
        'lead' => '<strong>Kauce:</strong>&nbsp;<em>nevyžadujeme</em>. Nájem zaplatíš předem online kartou (i přes Apple Pay nebo Google Pay), při rezervaci na webu také QR platbou nebo bankovním převodem. Platba musí dorazit do 4 hodin od odeslání rezervace, jinak můžeme rezervaci zrušit.',
        'aria' => 'Přehled plateb a poplatků',
        'headers' => ['Položka', 'Podmínky'],
        'rows' => [
            ['<strong>Platba nájemného</strong>', 'Online předem.'],
            ['<strong>Storno rezervace</strong>', 'Zdarma nejpozději 7 dní před převzetím. Při zrušení 2–7 dní předem můžeme účtovat až 50 % nájemného, při zrušení méně než 2 dny předem nebo při nevyzvednutí motorky celé nájemné (VOP čl. 3).'],
            ['<strong>Palivo &amp; čištění</strong>', 'Vrácení bez povinnosti tankovat – jen ať nesvítí rezerva. Umytou je potřeba motorku vrátit jen na samoobslužné pobočce ve Velkých Němčicích. Případné nadměrné znečištění řešíme individuálně.'],
            ['<strong>Přistavení / svoz</strong>', 'Dle ceníku přistavení (Vysočina / okolí). Potvrzujeme při rezervaci.'],
            ['<strong>Pozdní vrácení</strong>', 'Motorku vrať poslední den výpůjčky do 24:00. Za každý další započatý den platíš nájemné za den navíc (VOP čl. 2 d). Nestihneš to? Prodluž si výpůjčku v sekci Upravit rezervaci.'],
        ],
        'mid_cta' => [
            'label' => 'POKRAČOVAT K REZERVACI',
            'href' => '/rezervace',
            'aria' => 'Zarezervovat motorku a souhlasit s nájemní smlouvou Motogo24',
        ],
    ],
];
