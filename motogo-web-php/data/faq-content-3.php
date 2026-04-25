<?php
// ===== MotoGo24 — FAQ obsah 3/3 (Cestovani + Poukazy + meta) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/casto-kladene-dotazy

return [
    'travel' => [
        'label' => 'Cesty do zahraničí',
        'items' => [
            [
                'q' => 'Můžu odcestovat s motorkou do zahraničí?',
                'a' => 'Ano, s motorkou můžeš bez problémů vyrazit i do zahraničí. Cesty mimo Česko neomezujeme, jen je potřeba dodržet územní platnost pojištění (zelená karta).<br>Pojištění se nevztahuje na Bělorusko, Írán, Rusko, Srbsko a Kypr – jízda do těchto zemí je proto zakázána.',
            ],
            [
                'q' => 'Mohu s motorkou vycestovat do zahraničí?',
                'a' => 'Ano, ale drž se <strong>územní platnosti pojištění</strong> (zelená karta). Některé země mohou být vyloučené.',
            ],
            [
                'q' => 'Potřebuji něco speciálního do zahraničí?',
                'a' => 'Nic speciálního – malý technický průkaz a zelená karta jsou součástí motorky. Doporučujeme mít u sebe <strong>nájemní smlouvu</strong>, kterou dostaneš při převzetí – slouží jako doklad oprávněného užívání vozidla při případné policejní kontrole. Rovněž doporučujeme sjednání cestovního pojištění.',
            ],
        ],
    ],
    'vouchers' => [
        'label' => 'Poukazy',
        'items' => [
            [
                'q' => 'Jaká je platnost dárkového poukazu?',
                'a' => '<strong>3 roky</strong> od data vystavení. Termín na motorku si obdarovaný volí sám přes náš rezervační systém podle aktuální dostupnosti.',
            ],
            [
                'q' => 'Na jaké motorky lze poukaz uplatnit?',
                'a' => 'Na <strong>cestovní, sportovní, enduro i dětské</strong> modely dle hodnoty poukazu a oprávnění.',
            ],
            [
                'q' => 'Musí obdarovaný platit kauci?',
                'a' => '<strong>Ne, žádná kauce se neskládá.</strong> Naše podmínky jsou transparentní a výbava pro řidiče je vždy zahrnuta v ceně.',
            ],
            [
                'q' => 'Jak voucher doručíte?',
                'a' => '<strong>Okamžitě e-mailem</strong> po úhradě (PDF). Na požádání i tištěný voucher.',
            ],
            [
                'q' => 'Dá se termín uplatnění změnit?',
                'a' => 'Ano, po předchozí domluvě je možné termín upravit podle aktuální dostupnosti zvolené motorky.',
            ],
        ],
    ],
    '__meta' => [
        'seo' => [
            'title' => 'Půjčovna motorek Vysočina – Jak si půjčit motorku – Často kladené dotazy',
            'description' => 'Nejčastější dotazy k půjčení motorky u MotoGo24. Odpovědi na rezervaci motorky, podmínky i průběh zapůjčení motocyklu. Rezervuj si motorku jednoduše online. Vyber termín, stroj i výbavu a vyraz na nezapomenutelnou jízdu s MotoGo24 na Vysočině.',
            'keywords' => 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, půjčovna cestovních motorek, pronájem sportovních motorek, půjčovna enduro motorek, půjčovna skútrů Vysočina, dětské motorky k pronájmu, rezervace motorek online, motorky k pronájmu Vysočina, půjčovna motorek Česká republika, půjčovna motocyklů Pelhřimov',
        ],
        'h1' => 'Často kladené dotazy',
        'closing' => 'Naše <strong>půjčovna motorek Vysočina</strong> je tu pro všechny, kdo chtějí zažít <strong>nezapomenutelnou jízdu</strong> bez zbytečných komplikací. Pronájem je <strong>bez kauce</strong>, s <strong>výbavou v ceně</strong> a <strong>nonstop</strong>. Stačí si vybrat svůj stroj a rezervovat motorku online během pár minut. Ať už hledáte <strong>cestovní motorku, sportovní model nebo enduro</strong>, u nás si vyberete.',
        'cta' => ['label' => 'Rezervovat motorku online', 'href' => '/rezervace'],
    ],
];
