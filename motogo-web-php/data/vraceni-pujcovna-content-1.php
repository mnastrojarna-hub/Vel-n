<?php
// ===== MotoGo24 — Vraceni motocyklu v pujcovne 1/2 (intro + proces + cas vraceni) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/vraceni-motocyklu-v-pujcovne

return [
    'h1' => 'Vrácení motocyklu v půjčovně – rychle a bez komplikací',
    'intro' => 'Výpůjčka končí stejně jednoduše jako začala. Přijeď v domluvený čas vrácení na naši adresu v Pelhřimově, společně zkontrolujeme motorku a výbavu a je hotovo. Nemusíš tankovat ani mýt – to nech na nás.&nbsp;',
    'process' => [
        // Pozn: V originalu maji wbox jen titulky bez popisu. Zachovavame 1:1.
        'grid' => 'gr4',
        'steps' => [
            [
                'icon' => 'gfx/cas-prevzeti-motorky.svg',
                'title' => 'Přijeď v domluvený čas',
                'text' => '',
            ],
            [
                'icon' => 'gfx/predani-motorky.svg',
                'title' => 'Předej klíče a výbavu',
                'text' => '',
            ],
            [
                'icon' => 'gfx/podpis-dokumentu.svg',
                'title' => 'Společně zkontrolujeme stav motorky a výbavy',
                'text' => '',
            ],
            [
                'icon' => 'gfx/potvrzeni-rezervace.svg',
                'title' => 'Na e-mail ti přijde potvrzení o ukončení nájmu, konečná faktura a slevový kód na další rezervaci.',
                'text' => '',
            ],
        ],
    ],
    'time' => [
        'title' => 'Čas vrácení',
        'text' => 'Prosíme o dodržení času vrácení – pomůžeš nám tím zajistit, aby další zákazník převzal motorku včas. Pokud se přeci jen zpozdíš, dej nám prosím vědět telefonicky. Do půlnoci posledního dne výpůjčky neplatíš žádný poplatek. Pokud motorku vrátíš výrazně po tomto termínu, bude ti účtováno nájemné za další den.',
    ],
];
