<?php
// ===== MotoGo24 — Vraceni motocyklu v pujcovne 1/2 (intro + proces + cas vraceni) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/vraceni-motocyklu-v-pujcovne

return [
    'h1' => 'Vrácení motocyklu v půjčovně – rychle a bez komplikací',
    'intro' => 'Motorku vrátíš na pobočku, kde sis ji půjčil/a, kdykoli poslední den výpůjčky do 24:00. Tankovat nemusíš – jen ať nesvítí rezerva. V Mezné u Pelhřimova ji nemusíš ani mýt; ve Velkých Němčicích u Brna ji vrať umytou do kóje a výbavu do šatny – pomocí kódů z aplikace.',
    'process' => [
        // Pozn: V originalu maji wbox jen titulky bez popisu. Zachovavame 1:1.
        'grid' => 'gr4',
        'steps' => [
            [
                'icon' => 'gfx/cas-prevzeti-motorky.svg',
                'title' => 'Přijeď poslední den výpůjčky do 24:00',
                'text' => '',
            ],
            [
                'icon' => 'gfx/predani-motorky.svg',
                'title' => 'Předej klíče a výbavu',
                'text' => '',
            ],
            [
                'icon' => 'gfx/prevezmi-motorku.svg',
                'title' => 'Společně zkontrolujeme stav motorky a výbavy',
                'text' => '',
            ],
            [
                'icon' => 'gfx/sleva-na-pristi-jizdu.svg',
                'title' => 'Potvrzení, fakturu a slevový kód dostaneš e-mailem',
                'text' => '',
            ],
        ],
    ],
    'time' => [
        'title' => 'Čas vrácení',
        'text' => 'Motorku vrať kdykoli poslední den výpůjčky do 24:00 – čas vrácení uvedený v rezervaci je jen orientační. Když víš, že to do půlnoci nestihneš, zavolej nám, nebo si výpůjčku prodluž v sekci Upravit rezervaci či v aplikaci MotoGo24 (pokud je motorka volná). Za každý další započatý den, kdy máš motorku u sebe, platíš nájemné za den navíc.',
    ],
];
