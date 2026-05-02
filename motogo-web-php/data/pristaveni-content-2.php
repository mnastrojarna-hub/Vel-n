<?php
// ===== MotoGo24 — Pristaveni motocyklu 2/2 (proces + cenik + FAQ + CTA + SEO) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/pristaveni-motocyklu

return [
    'process' => [
        'title' => 'Jak přistavení probíhá',
        'grid' => 'gr5',
        'steps' => [
            [
                'icon' => 'gfx/vyber-motorku.svg',
                'title' => 'Vyber motorku',
                'text' => 'Prohlédni si naši nabídku cestovních, supermoto, naked a dětských motorek a vyber si tu pravou.',
            ],
            [
                'icon' => 'gfx/rezervace-online.svg',
                'title' => 'Zvol termín',
                'text' => 'V kalendáři vyber datum, kdy chceš vyjet. Uvidíš, které motorky jsou volné.',
            ],
            [
                'icon' => 'gfx/kontaktni-udaje.svg',
                'title' => 'Kontaktní údaje',
                'text' => 'Vyplň jméno, adresu, e-mail a telefon.',
            ],
            [
                'icon' => 'gfx/cas-prevzeti-motorky.svg',
                'title' => 'Čas přistavení',
                'text' => 'Zvol, kdy ti motorku přistavíme – klidně večer nebo o víkendu.',
            ],
            [
                'icon' => 'gfx/vyzvednuti-vraceni-motorky.svg',
                'title' => 'Místo přistavení',
                'text' => 'Zadej adresu, kam motorku přivézt – domů, do hotelu, k nádraží nebo na start výletu.',
            ],
            [
                'icon' => 'gfx/vyber-vybavu.svg',
                'title' => 'Výbava',
                'text' => 'Základní výbava řidiče je v ceně. Požadované velikosti pro všechny části výbavy uveď do pole Poznámka – povinné.',
            ],
            [
                'icon' => 'gfx/zaplat.svg',
                'title' => 'Potvrzení a platba',
                'text' => 'Zkontroluj shrnutí objednávky, odsouhlas podmínky a zaplať online.',
            ],
            [
                'icon' => 'gfx/podpis-dokumentu.svg',
                'title' => 'Převzetí na místě',
                'text' => 'Při předání zkontrolujeme doklady, doplníme smlouvu a podepíšeme předávací protokol.',
            ],
            [
                'icon' => 'gfx/uzij-si-jizdu.svg',
                'title' => 'Užij si jízdu',
                'text' => 'Vyraz na cestu – bez kauce, bez stresu. Zbytek je jen asfalt a svoboda.',
            ],
            [
                'icon' => 'gfx/predani-motorky.svg',
                'title' => 'Vrácení motorky',
                'text' => 'Motorku vrať včas na předem sjednané místo. Nemusíš tankovat ani mýt.',
            ],
        ],
    ],
    'pricing' => [
        'title' => 'Ceník přistavení',
        'lead' => '<strong>Cena přistavení se skládá ze tří složek:</strong>',
        'items' => [
            '<strong>500 Kč</strong>&nbsp;za naložení motorky,',
            '<strong>500 Kč</strong>&nbsp;za vyložení motorky,',
            '<strong>20 Kč</strong>&nbsp;za každý kilometr (počítá se vzdálenost z půjčovny na místo určení tam i zpět)',
        ],
        'example' => '<strong>Příklad:</strong>&nbsp;Chcete motorku přistavit 30 km od půjčovny? Zaplatíte 500 + 500 + (30 × 2 × 20) =&nbsp;<strong>2 200 Kč.</strong>',
    ],
    'faq' => [
        'title' => 'Často kladené dotazy k přistavení',
        'items' => [
            [
                'q' => 'Jak dopředu objednat přistavení?',
                'a' => 'Ideálně <strong>při</strong> <strong>online rezervaci</strong> – zadáš adresu a čas. U urgentních požadavků nás kontaktuj telefonicky.',
            ],
            [
                'q' => 'Můžu vrátit motorku jinde než jsem ji převzal?',
                'a' => 'Ano, účtujeme <strong>svoz</strong> dle vzdálenosti od Pelhřimova. Domluvíme při rezervaci.',
            ],
            [
                'q' => 'Kolik stojí přistavení mimo Vysočinu?',
                'a' => 'Řídíme se tabulkou vzdáleností. Nad 100 km cenu kalkulujeme <strong>individuálně</strong>.',
            ],
            [
                'q' => 'Platí se kauce?',
                'a' => 'Ne. <strong>Půjčujeme bez kauce</strong>, podmínky jsou jasné a férové.',
            ],
            [
                'q' => 'Je v ceně i výbava řidiče?',
                'a' => 'Ano. Helma, bunda, kalhoty a rukavice jsou pro řidiče&nbsp;<strong>v ceně výpůjčky</strong>.',
            ],
        ],
    ],
    'cta' => [
        'title' => 'Přistavení motorky – půjčovna motorek',
        'text' => 'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s možností <strong>přistavení motocyklu</strong> kamkoliv v České republice. Cena přistavení se odvíjí od vzdálenosti z naší provozovny v Pelhřimově.&nbsp;Nabízíme <strong>nonstop provoz, bez kauce, výbavu pro řidiče v ceně</strong> a jednoduchou<strong> online rezervaci</strong>.',
        'buttons' => [
            [
                'label' => 'REZERVOVAT DORUČENÍ',
                'href' => '/rezervace',
                'cls' => 'btndark pulse',
                'aria' => 'Rezervovat doručení motorky na domluvené místo',
            ],
        ],
    ],
    'seo' => [
        'title' => 'Půjčovna motorek Vysočina – Jak si půjčit motorku – Přistavení motocyklu',
        'description' => 'MotoGo24 zajistí přistavení motorky na místo podle tvého výběru. Pohodlné půjčení motorky na Vysočině bez zbytečného cestování. Rezervuj si motorku jednoduše online. Vyber termín, stroj i výbavu a vyraz na nezapomenutelnou jízdu s MotoGo24 na Vysočině.',
        'keywords' => 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, půjčovna cestovní motorky, pronájem sportovní motorky, půjčovna enduro motorek, půjčovna skútrů Vysočina, dětské motorky k pronájmu, rezervace motorky online, motorky k pronájmu Vysočina, motorbike rental Czech Republic, motorcycle hire Vysocina, rent a motorbike Pelhřimov',
    ],
];
