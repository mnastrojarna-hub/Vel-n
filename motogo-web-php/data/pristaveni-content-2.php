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
                'text' => 'Vyraz na cestu. Kdyby se cokoli stalo, jsme ti během výpůjčky nonstop k dispozici.',
            ],
            [
                'icon' => 'gfx/predani-motorky.svg',
                'title' => 'Vrácení motorky',
                'text' => 'Motorku vrať včas na předem sjednané místo. Mýt ani tankovat ji nemusíš – jen ať nesvítí rezerva.',
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
        'example' => '<strong>Příklad:</strong>&nbsp;Chceš motorku přistavit 30 km od Mezné? Zaplatíš 500 + 500 + (30 × 2 × 20) =&nbsp;<strong>2 200 Kč.</strong>',
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
                'q' => 'Přistavíte i motorku z Velkých Němčic?',
                'a' => 'Ne. Přistavení nabízíme jen u motorek z <strong>obslužné pobočky v Mezné u Pelhřimova</strong>; motorky ze samoobslužné pobočky ve Velkých Němčicích se přebírají i vracejí jen na pobočce.',
            ],
            [
                'q' => 'Je v ceně i výbava řidiče?',
                'a' => 'Ano. Helma, bunda, kalhoty a rukavice jsou pro řidiče&nbsp;<strong>v ceně výpůjčky</strong>.',
            ],
        ],
    ],
    'cta' => [
        'title' => 'Objednej si přistavení',
        'text' => 'Přistavení si objednáš přímo v rezervaci – adresu a čas zadáš ve formuláři a cenu uvidíš hned.',
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
        'title' => 'Přistavení motorky kamkoli v ČR – ceník | MotoGo24',
        'description' => 'Motorku z Mezné u Pelhřimova ti přivezeme domů, k hotelu nebo na nádraží kdekoli v ČR. Cena: 500 + 500 Kč a 20 Kč/km tam i zpět. Objednáš v rezervaci.',
        'keywords' => 'motopůjčovna',
    ],
];
