<?php
// ===== MotoGo24 — Postup pujceni motorky 2/2 (gallery + tabulky + FAQ + CTA + SEO) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/postup-pujceni-motorky

return [
    'faq' => [
        'title' => 'Často kladené otázky',
        'items' => [
            [
                'q' => 'Je nutná kauce při půjčení?',
                'a' => 'Ne.&nbsp;<strong>Půjčujeme bez kauce</strong>&nbsp;– férově a bez zbytečných překážek.',
            ],
            [
                'q' => 'Je v ceně půjčovného i výbava?',
                'a' => 'Ano. Každý řidič dostane&nbsp;<strong>helmu, bundu, kalhoty a rukavice zdarma</strong>.',
            ],
            [
                'q' => 'Kde si mohu motorku převzít?',
                'a' => 'Na obslužné pobočce v Mezné u Pelhřimova (odtud nabízíme i&nbsp;<strong>přistavení motorky</strong>&nbsp;na tebou zvolené místo), nebo samoobslužně na pobočce ve Velkých Němčicích u Brna.',
            ],
            [
                'q' => 'Do kdy musím motorku vrátit?',
                'a' => 'Motorku můžeš vrátit kdykoli během posledního dne výpůjčky – klidně i o půlnoci.',
            ],
        ],
        'more_link' => [
            'label' => 'Další často kladené otázky',
            'href' => '/jak-pujcit/faq',
            'aria' => 'Přečti si další často pokládané otázky',
        ],
    ],
    'cta' => [
        'title' => 'Sedni na motorku!',
        'text' => 'Rezervuj si motorku online ještě dnes a užij si <strong>svobodu na dvou kolech</strong> – jednoduše a bez zbytečných podmínek.',
        'buttons' => [
            [
                'label' => 'REZERVOVAT ONLINE',
                'href' => '/rezervace',
                'cls' => 'btndark pulse',
                'aria' => 'Rezervovat motorku online',
            ],
        ],
    ],
    'seo' => [
        'title' => 'Jak si půjčit motorku – postup krok za krokem | MotoGo24',
        'description' => 'Jak si půjčit motorku u MotoGo24: vyber motorku a termín, zaplať online a vyzvedni ji u Pelhřimova, nebo samoobslužně u Brna. Bez kauce, výbava v ceně.',
        'keywords' => 'motopůjčovna',
    ],
];
