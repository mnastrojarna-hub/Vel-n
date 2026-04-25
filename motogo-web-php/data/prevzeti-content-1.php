<?php
// ===== MotoGo24 — Prevzeti v pujcovne 1/2 (intro + adresa+mapa + proces) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/prevzeti-v-pujcovne

return [
    'h1' => 'Převzetí v půjčovně – rychle, jednoduše a nonstop',
    'intro' => 'V <strong>Motogo24 – půjčovně motorek na Vysočině</strong>&nbsp;převzetí motorky otázkou pár minut. Půjčujeme bez <strong>kauce, s výbavou pro řidiče v ceně a nonstop provozem</strong>. Přijď osobně do Pelhřimova a vyraz na cestu!',
    'top_cta' => [
        'label' => 'REZERVOVAT ONLINE',
        'href' => '/rezervace',
        'aria' => 'Přejít na online rezervaci motorky v půjčovně Motogo24',
    ],
    'place' => [
        'title' => 'Kde probíhá převzetí motocyklu',
        'address_label' => 'Provozovna:',
        'address' => 'Mezná 9, 393 01 <strong>Pelhřimov</strong> (Vysočina)',
        'hours_label' => 'Provozní doba:',
        'hours' => '<em>nonstop</em> (vyzvednutí i vrácení kdykoli v den výpůjčky)',
        // Originalni Google Maps embed iframe URL z motogo24.cz
        'map_src' => 'https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d53928.274636159236!2d15.154130970132716!3d49.35168867371007!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!3m3!1m2!1s0x470ce75bf69a97b3%3A0xe75f9d3fadf02b5b!2zTWV6bsOhIDksIDM5MyAwMSBNZXpuw6E!5e0!3m2!1scs!2scz!4v1759860051295!5m2!1scs!2scz',
        'map_title' => 'Jak se k nám dostanete',
    ],
    'process' => [
        'title' => 'Jak probíhá převzetí v motopůjčovně',
        'grid' => 'gr4',
        'steps' => [
            [
                'icon' => 'gfx/ico-step-cas.svg',
                'title' => 'Přijď v domluvený čas',
                'text' => 'Na naši adresu: Mezná 9, 393 01 Pelhřimov.',
            ],
            [
                'icon' => 'gfx/ico-step-doklady.svg',
                'title' => 'Ověříme doklady',
                'text' => 'OP/pas a řidičský průkaz odpovídající skupiny',
            ],
            [
                'icon' => 'gfx/ico-step-smlouva.svg',
                'title' => 'Doplníme smlouvu',
                'text' => 'Předvyplněnou nájemní smlouvu doplníme o údaje z dokladů.',
            ],
            [
                'icon' => 'gfx/ico-step-vybava.svg',
                'title' => 'Vybereš a vyzkoušíš si výbavu',
                'text' => 'Výbavu z rezervace si můžeš vyzkoušet v naší zkušební kabince.',
            ],
            [
                'icon' => 'gfx/ico-step-projit-motorku.svg',
                'title' => 'Společně projdeme motorku',
                'text' => 'Zkontrolujeme stav stroje a seznámíš se s jeho ovládáním.',
            ],
            [
                'icon' => 'gfx/ico-step-protokol.svg',
                'title' => 'Podepíšeme předávací protokol',
                'text' => 'Zdokumentujeme stav motorky a výbavy před výpůjčkou.',
            ],
            [
                'icon' => 'gfx/ico-step-klice.svg',
                'title' => 'Předáme klíče',
                'text' => 'Motorka je připravená a čeká na tebe.',
            ],
            [
                'icon' => 'gfx/ico-step-jizda.svg',
                'title' => 'Můžeš vyrazit',
                'text' => 'Vyraz na cestu – bez kauce, bez stresu. Zbytek je jen asfalt a svoboda.',
            ],
        ],
    ],
];
