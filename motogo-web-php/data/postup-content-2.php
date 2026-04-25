<?php
// ===== MotoGo24 — Postup pujceni motorky 2/2 (gallery + tabulky + FAQ + CTA + SEO) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/postup-pujceni-motorky

return [
    'gallery' => [
        // Diagram vybavy (originalne 69e5ff03bfe42 z motogo24.cz cdn)
        'image' => '/gfx/postup-vybava-diagram.jpg',
        'alt' => 'Výbava diagram&nbsp;Motogo24',
        'group' => 'gal_1',
    ],
    'sizes' => [
        'adult' => [
            'title' => 'Dospělá výbava',
            'headers' => ['Výbava', 'Dostupné velikosti'],
            'rows' => [
                ['Helma', 'XS, S, M, L, XL'],
                ['Bunda', 'M, L, XL, 2XL'],
                ['Kalhoty', 'M, L, XL, 2XL'],
                ['Rukavice', 'M, L, XL'],
                ['Motoboty', '39–46'],
                ['Kukla', 'univerzální'],
                ['Reflexní vesta&nbsp;', 'univerzální'],
            ],
        ],
        'kid' => [
            'title' => 'Dětská výbava',
            'headers' => ['Výbava', 'Dostupné velikosti'],
            'rows' => [
                ['Helma', 'S (47–48 cm), M (49–50 cm), L (51–52 cm)'],
                ['Bunda', '110–116, 122–128, 134–140, 146–152 cm'],
                ['Kalhoty', '110–116, 122–128, 134–140, 146–152 cm'],
                ['Rukavice', 'XS/S (4–7 let), M/L (8–12 let)'],
                ['Motoboty', '29–35'],
                ['Kukla', 'S (4–7 let), M (8–12 let)'],
                ['Reflexní vesta&nbsp;', 'XS, S, M'],
            ],
        ],
    ],
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
                'a' => 'Vyzvednutí probíhá v Pelhřimově, případně nabízíme&nbsp;<strong>přistavení motorky</strong>&nbsp;na tebou zvolené místo.',
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
        'title' => 'Půjčovna motorek Vysočina – Jak si půjčit motorku – Postup půjčení motorky',
        'description' => 'Zjisti, jak probíhá půjčení motorky u MotoGo24. Přehledný postup rezervace motorky, podmínky i tipy pro bezstarostnou jízdu. Rezervuj si motorku jednoduše online. Vyber termín, stroj i výbavu a vyraz na nezapomenutelnou jízdu s MotoGo24 na Vysočině.',
        'keywords' => 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, půjčovna cestovní motorky, pronájem sportovní motorky, půjčovna enduro motorek, půjčovna skútrů Vysočina, dětské motorky k pronájmu, rezervace motorky online, motorky k pronájmu Vysočina, motorbike rental Czech Republic, motorcycle hire Vysocina, rent a motorbike Pelhřimov',
    ],
];
