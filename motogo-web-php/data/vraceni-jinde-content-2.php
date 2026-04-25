<?php
// ===== MotoGo24 — Vraceni motorky jinde 2/2 (proces + cenik + nesrovnalosti + FAQ + CTA + SEO) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/vraceni-motorky-jinde

return [
    'process' => [
        'title' => 'Jak vrácení jinde probíhá',
        'grid' => 'gr5',
        'steps' => [
            [
                'icon' => 'gfx/ico-step-misto-cas.svg',
                'title' => 'Zvol místo a čas vrácení',
                'text' => 'V rezervačním formuláři zadej adresu a čas, kdy motorku předáš.',
            ],
            [
                'icon' => 'gfx/ico-step-vybava.svg',
                'title' => 'Připrav si výbavu',
                'text' => 'Před předáním si nachystej výbavu, která byla součástí výpůjčky.',
            ],
            [
                'icon' => 'gfx/ico-step-prijedeme.svg',
                'title' => 'Přijedeme v domluvený čas',
                'text' => 'Dorazíme na sjednané místo přesně v domluvený čas.',
            ],
            [
                'icon' => 'gfx/ico-step-kontrola.svg',
                'title' => 'Společně zkontrolujeme motorku a výbavu',
                'text' => 'Zkontrolujeme stav motorky a výbavy, naložíme a odjedeme.&nbsp;',
            ],
            [
                'icon' => 'gfx/ico-step-email.svg',
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
                'a' => 'Ne. U nás netankuješ ani nemyješ. Jen hlídej, aby nesvítila rezerva.&nbsp;',
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
                'a' => 'Zavolej nám, jakmile víš, že to nestihneš na čas. Domluvíme se – většinou na tebe počkáme. Jen potřebujeme vědět, s jakým zpožděním počítat, abychom si mohli přizpůsobit plán dne.',
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
        'title' => 'Vrácení motorky jinde – půjčovna motorek MotoGo24',
        'text' => 'Půjčovna motorek MotoGo24 na Vysočině nabízí vrácení motorky kdekoliv v České republice. Předej nám motorku na místě podle svého výběru – my přijedeme v domluvený čas. Cena se odvíjí od vzdálenosti z místa vrácení do naší provozovny v Pelhřimově. Vyber si cestovní, supermoto, naked nebo dětskou motorku, rezervuj online a vyraž. O zbytek se postaráme my.',
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
        'title' => 'Půjčovna motorek Vysočina – Jak si půjčit motorku – Vrácení motorky jinde',
        'description' => 'Vrať motorku tam, kde ti to vyhovuje. MotoGo24 nabízí flexibilní vrácení motocyklu na Vysočině bez nutnosti návratu do půjčovny. Rezervuj si motorku jednoduše online. Vyber termín, stroj i výbavu a vyraz na nezapomenutelnou jízdu s MotoGo24 na Vysočině.',
        'keywords' => 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, půjčovna cestovní motorky, pronájem sportovní motorky, půjčovna enduro motorek, půjčovna skútrů Vysočina, dětské motorky k pronájmu, rezervace motorky online, motorky k pronájmu Vysočina, motorbike rental Czech Republic, motorcycle hire Vysocina, rent a motorbike Pelhřimov',
    ],
];
