<?php
// ===== MotoGo24 — Vraceni motorky jinde 2/2 (proces + cenik + nesrovnalosti + FAQ + CTA + SEO) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/vraceni-motorky-jinde

return [
    'process' => [
        'title' => 'Jak vrácení jinde probíhá',
        'grid' => 'gr5',
        'steps' => [
            [
                'icon' => 'gfx/uzij-si-jizdu.svg',
                'title' => 'Zvol místo a čas vrácení',
                'text' => 'V rezervačním formuláři zadej adresu a čas, kdy motorku předáš.',
            ],
            [
                'icon' => 'gfx/vyber-vybavu.svg',
                'title' => 'Připrav si výbavu',
                'text' => 'Před předáním si nachystej výbavu, která byla součástí výpůjčky.',
            ],
            [
                'icon' => 'gfx/cas-prevzeti-motorky.svg',
                'title' => 'Přijedeme v domluvený čas',
                'text' => 'Dorazíme na sjednané místo přesně v domluvený čas.',
            ],
            [
                'icon' => 'gfx/prevezmi-motorku.svg',
                'title' => 'Společně zkontrolujeme motorku a výbavu',
                'text' => 'Zkontrolujeme stav motorky a výbavy, naložíme a odjedeme.&nbsp;',
            ],
            [
                'icon' => 'gfx/sleva-na-pristi-jizdu.svg',
                'title' => 'Na e-mail ti přijde potvrzení',
                'text' => 'Potvrzení o ukončení nájmu, konečná faktura a slevový kód na další rezervaci.',
            ],
        ],
    ],
    'pricing' => [
        'title' => 'Ceník vrácení jinde',
        'lead' => 'Cena se skládá ze tří složek:',
        'items' => [
            '500 Kč za naložení motorky',
            '500 Kč za vyložení motorky',
            '20 Kč za každý kilometr (vzdálenost z místa vrácení do půjčovny tam i zpět)',
        ],
        'example_title' => 'Příklad:',
        'example_q' => 'Chceš motorku vrátit 30 km od půjčovny?',
        'example_a' => 'Zaplatíš 500 + 500 + (30 × 2 × 20) = 2 200 Kč.',
    ],
    'issues' => [
        'title' => 'Nesrovnalosti při vrácení',
        'lead' => 'Při vrácení společně zkontrolujeme stav motorky i výbavy. Pokud by nastala některá z níže uvedených situací, sepíšeme protokol o zjištěném poškození:',
        'items' => [
            'chybějící výbava',
            'poškozená výbava',
            'poškozený motocykl',
        ],
        'closing' => 'Protokol zákazník podepíše a obdrží jeho kopii. Další postup se řídí podmínkami nájemní smlouvy a obchodními podmínkami.',
    ],
    'faq' => [
        'title' => 'Často kladené dotazy k vrácení motorky jinde',
        'items' => [
            [
                'q' => 'Do kdy musím motorku vrátit?',
                'a' => 'Motorku vrať ideálně ve sjednaný čas. Pokud vracíš v místě půjčovny, můžeš ale přijet po dohodě kdykoli během posledního dne výpůjčky – nejpozději do půlnoci, bez jakýchkoli sankcí. Vracíš-li na jiném místě, je sjednaný čas závazný.',
            ],
            [
                'q' => 'Musím vracet s plnou nádrží a čistou?',
                'a' => 'Ne. Při vrácení jinde ji mýt ani tankovat nemusíš – jen ať nesvítí rezerva.&nbsp;',
            ],
            [
                'q' => 'Můžu motorku při vrácení na jiném místě vrátit dřív, než jsme se domluvili?&nbsp;',
                'a' => 'Na sjednané místo vyjíždíme z Pelhřimova přesně podle domluveného času, takže dřívější vrácení bohužel není možné. Pokud se ti plány změní, ozvi se nám – pokusíme se čas přizpůsobit, ale záleží na naší aktuální vytíženosti.',
            ],
            [
                'q' => 'Můžu motorku vrátit opravdu kdekoliv v ČR?&nbsp;',
                'a' => 'Ano, přijedeme si pro motorku kamkoliv v České republice. Místo vrácení zadáš při rezervaci – může to být hotel, parkoviště, nádraží nebo jakákoliv jiná adresa.',
            ],
            [
                'q' => 'Jak daleko dopředu musím vrácení na jiném místě nahlásit?&nbsp;',
                'a' => 'Místo a čas vrácení zadáváš už v rezervačním formuláři.&nbsp;',
            ],
            [
                'q' => 'Co když se na místo vrácení zpozdím?&nbsp;',
                'a' => 'Zavolej nám, jakmile víš, že to nestihneš. Když dáš vědět předem, většinou na tebe počkáme. Pokud se v domluvený čas bez ohlášení nedostavíš, můžeme podle obchodních podmínek (čl. 2 e) odjet a účtovat ti marnou cestu ve výši poplatku za vyzvednutí.',
            ],
            [
                'q' => 'Jak se počítá cena za vrácení na jiném místě?&nbsp;',
                'a' => 'Cena zahrnuje 500 Kč za naložení, 500 Kč za vyložení a 20 Kč za každý kilometr vzdálenosti z místa vrácení do půjčovny (tam i zpět). Například při vrácení 50 km od Pelhřimova zaplatíš 500 + 500 + (50 × 2 × 20) = 3 000 Kč.',
            ],
            [
                'q' => 'Platím za vrácení jinde zvlášť, nebo je to součástí ceny pronájmu?&nbsp;',
                'a' => 'Vrácení na jiném místě je doplňková služba a platí se zvlášť nad rámec ceny pronájmu.&nbsp;',
            ],
            [
                'q' => 'Co když chci motorku vyzvednout v Pelhřimově, ale vrátit jinde – jde to?&nbsp;',
                'a' => 'Ano, můžeš vyzvednout motorku u nás v Pelhřimově a vrátíš ji tam, kde potřebuješ.&nbsp;',
            ],
            [
                'q' => 'Co mám mít připravené, když přijedete pro motorku?&nbsp;',
                'a' => 'Měj připravené klíče a veškerou výbavu, která byla součástí výpůjčky. Společně zkontrolujeme stav motorky a výbavy.',
            ],
        ],
    ],
    'cta' => [
        'title' => 'Máš dotaz k vrácení jinde?',
        'text' => 'Místo a čas vrácení zadáš přímo v rezervaci a cenu ti formulář spočítá hned. Když si nevíš rady, zavolej nám nebo napiš.',
        'buttons' => [
            [
                'label' => 'KONTAKT',
                'href' => '/kontakt',
                'cls' => 'btndark',
                'aria' => 'Kontaktujte nás',
            ],
        ],
    ],
    'seo' => [
        'title' => 'Vrácení motorky jinde – odvoz kdekoli v ČR | MotoGo24',
        'description' => 'Motorku z Mezné si vyzvedneme u hotelu, na nádraží i u tebe doma – kdekoli v ČR. Cena: 500 + 500 Kč a 20 Kč/km tam i zpět. Čas vrácení je závazný.',
        'keywords' => 'motopůjčovna',
    ],
];
