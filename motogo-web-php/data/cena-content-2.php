<?php
// ===== MotoGo24 — Co je v cene najmu 2/2 (benefity + CTA + SEO) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/co-je-v-cene-najmu

return [
    'benefits' => [
        'title' => 'Další výhody v ceně',
        'grid' => 'gr5',
        'items' => [
            [
                'icon' => 'gfx/rezervace-online.svg',
                'title' => 'Online rezervace',
                'text' => 'rychlá a jednoduchá rezervace z pohodlí domova.',
            ],
            [
                'icon' => 'gfx/ico-nonstop.svg',
                'title' => 'Nonstop provoz',
                'text' => 'rezervuj a vyrazit můžeš kdykoliv – ve dne, v noci i o víkendu. Čas převzetí si volíš v rezervaci.',
            ],
            [
                'icon' => 'gfx/ico-bez-kauce.svg',
                'title' => 'Bez kauce',
                'text' => 'žádná kauce ani blokace peněz na kartě – platíš jen nájem.',
            ],
            [
                'icon' => 'gfx/jasne-podminky.svg',
                'title' => 'Jasné podmínky',
                'text' => 'bez skrytých poplatků.',
            ],
            [
                'icon' => 'gfx/sleva-na-pristi-jizdu.svg',
                'title' => 'Sleva na další rezervaci',
                'text' => 'po každém dokončeném pronájmu dostaneš slevový kód na příští rezervaci.&nbsp;',
            ],
        ],
    ],
    'cta' => [
        'title' => 'Rezervuj motorku online',
        'text' => 'Cenu všech doplňků uvidíš v rezervaci ještě před platbou. Vyber si motorku a rezervuj online.',
        'buttons' => [
            [
                'label' => 'REZERVOVAT ONLINE',
                'href' => '/rezervace',
                'cls' => 'btndark pulse',
                'aria' => 'Rezervovat motorku s výbavou v ceně v půjčovně Motogo24',
            ],
        ],
    ],
    'seo' => [
        'title' => 'Co je v ceně pronájmu motorky | MotoGo24',
        'description' => 'V ceně máš výbavu řidiče, neomezené kilometry, kotoučový zámek a 100% smluvní krytí škod. Bez kauce. Za příplatek výbava spolujezdce, boty a přistavení.',
        'keywords' => 'motopůjčovna',
    ],
];
