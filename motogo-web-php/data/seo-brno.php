<?php
// ===== MotoGo24 — SEO stránka „Motopůjčovna Brno a jižní Morava“ (/motopujcovna-brno) =====
// Výchozí CS texty (pages/seo-pobocka.php). Pobočka Velké Němčice (samoobslužná).
// Fakta jen z data/pobocky.php a pages/pobocky-v2-texts.php (dojezd, provoz, výbava) —
// při změně podmínek pobočky upravit i tady. Texty jdou přepsat z webu (inline CMS,
// klíče web.seo_brno.*). Nahradila krajské stránky /oblasti (majitel 2026-11-26).
// Majitel 2026-11-27: bez tipů na výlety (sekce 'tips' zrušena) a FAQ jen místní otázky, které neřeší
// obecné /jak-pujcit/faq (kauce, výbava, parkování… tam, ne tady).

return [
    'seo' => [
        'title' => 'Motopůjčovna Brno – půjčovna motorek nonstop | MotoGo24',
        'description' => 'Samoobslužná půjčovna motorek ve Velkých Němčicích, 20 minut od jižního okraje Brna. Převzetí nonstop kódem z aplikace, bez kauce, výbava v ceně.',
        'keywords' => 'motopůjčovna Brno, půjčovna motorek Brno, pronájem motorky Brno, půjčení motorky Brno, motopůjčovna jižní Morava, půjčovna motorek jižní Morava, motopůjčovna Břeclav, motopůjčovna Hodonín, motopůjčovna Znojmo, samoobslužná půjčovna motorek',
    ],
    'h1' => 'Motopůjčovna Brno a jižní Morava',
    'intro' => 'Hledáš <strong>motopůjčovnu v Brně</strong> nebo jinde na jižní Moravě? Naše <strong>samoobslužná pobočka ve Velkých Němčicích</strong> je 20 minut od jižního okraje Brna. Motorku si vyzvedneš <strong>nonstop 24/7</strong> kódem z aplikace — <strong>bez kauce</strong>, s výbavou pro řidiče v ceně a s parkováním zdarma po celou dobu výpůjčky.',
    'cta_top' => 'REZERVOVAT U BRNA',
    'why' => [
        'title' => 'Proč si půjčit motorku u Brna právě u nás',
        'items' => [
            ['icon' => 'gfx/ico-nonstop.svg', 'title' => 'Nonstop 24/7', 'text' => 'Motorku převezmeš i vrátíš kdykoliv — v noci, o víkendu i ve svátek. Vše vyřídíš na dotykovém displeji kódem z aplikace.'],
            ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'Bez kauce', 'text' => 'Neblokujeme ti peníze na kartě. Zaplatíš jen cenu pronájmu online při rezervaci.'],
            ['icon' => 'gfx/ico-vybava.svg', 'title' => 'Výbava pro řidiče v ceně', 'text' => 'Helma, bunda s páteřákem, kalhoty, rukavice a kukla jsou v ceně, motocyklové boty za příplatek. Helmy S–3XL, oblečení do 4XL.'],
            ['icon' => 'gfx/cas-prevzeti-motorky.svg', 'title' => '20 minut z Brna', 'text' => '20 minut z jižního okraje Brna, zhruba 30 minut z centra, 35 minut z letiště a 1 h 40 min z Vídně.'],
            ['icon' => 'gfx/adresa.svg', 'title' => 'Parkování zdarma', 'text' => 'Auto necháš u pobočky po celou dobu výpůjčky a nic za něj neplatíš.'],
            ['icon' => 'gfx/ico-sleva.svg', 'title' => 'Od poledne za polovinu', 'text' => 'Když si motorku vyzvedneš od 12:00 a půjčíš ji aspoň na 2 dny, první den platíš jen polovinu.'],
        ],
    ],
    'areas' => [
        'title' => 'Motopůjčovna pro Brno, Břeclav, Hodonín i Znojmo',
        'text' => 'Pobočka leží jižně od Brna, mezi Židlochovicemi a Hustopečemi. Pohodlně k nám dojedeš z <strong>Brna</strong> i z dalších měst <strong>jižní Moravy</strong>:',
        'items' => [
            '<strong>Brno</strong> — 20 minut z jižního okraje, zhruba 30 minut z centra',
            '<strong>Židlochovice a Hustopeče</strong> — pár minut',
            '<strong>Pohořelice, Mikulov a Valtice</strong>',
            '<strong>Břeclav, Hodonín a Kyjov</strong>',
            '<strong>Vyškov a Slavkov u Brna</strong>',
            '<strong>Blansko a Znojmo</strong>',
            '<strong>Vídeň</strong> — zhruba 1 h 40 min',
        ],
        'note' => 'Motorky z této pobočky se přebírají i vracejí přímo na pobočce — přistavení ani odvoz u nich nenabízíme. Motorku na adresu přivezeme z <a href="/motopujcovna-vysocina">obslužné pobočky v Mezné u Pelhřimova</a>.',
    ],
    'process' => [
        'title' => 'Jak si půjčit motorku u Brna',
        'steps' => [
            ['icon' => 'gfx/ico-step1.svg', 'title' => 'Rezervuj online', 'text' => 'Vyber motorku na pobočce Velké Němčice, zvol termín a čas vyzvednutí a zaplať online.'],
            ['icon' => 'gfx/ico-step2.svg', 'title' => 'Nahraj doklady', 'text' => 'Nahraj občanku nebo pas a řidičák. Po ověření ti v aplikaci, e-mailu a SMS přijdou kódy.'],
            ['icon' => 'gfx/ico-step3.svg', 'title' => 'Převezmi motorku', 'text' => 'Na displeji zadáš kód šatny a vezmeš si výbavu, podepíšeš předávací protokol a kódem motorky otevřeš kóji.'],
            ['icon' => 'gfx/ico-step4.svg', 'title' => 'Vrať ji do půlnoci', 'text' => 'Motorku vrátíš do kóje a výbavu do šatny kdykoliv poslední den výpůjčky do 24:00.'],
        ],
    ],
    'faq' => [
        'title' => 'Časté otázky: půjčovna motorek Brno',
        'items' => [
            ['q' => 'Kde najdu motopůjčovnu u Brna?', 'a' => 'Samoobslužná pobočka MotoGo24 je ve Velkých Němčicích (Boudky, 691 63 Velké Němčice), 20 minut od jižního okraje Brna a zhruba 30 minut z centra. Z letiště Brno-Tuřany je to asi 35 minut.'],
            ['q' => 'Můžu si motorku půjčit v noci nebo o víkendu?', 'a' => 'Ano. Pobočka ve Velkých Němčicích je bez obsluhy a funguje nonstop 24/7 – motorku převezmeš kódem z aplikace v čase, který si zvolíš v rezervaci, klidně v noci, o víkendu i ve svátek. Vrátíš ji kdykoliv poslední den výpůjčky do 24:00.'],
            ['q' => 'Přivezete mi motorku do Brna?', 'a' => 'Motorky z Velkých Němčic se přebírají i vracejí jen přímo na pobočce. Do Brna ti za příplatek přivezeme motorku z obslužné pobočky v Mezné u Pelhřimova – adresu a čas přistavení zadáš v rezervaci.'],
        ],
    ],
    'cta' => [
        'title' => 'Rezervuj si motorku u Brna',
        'text' => 'Vyber si stroj na pobočce Velké Němčice, zvol termín a vyzvedni si ho kdykoliv, ve dne i v noci.',
        'buttons' => [
            ['label' => 'REZERVOVAT', 'href' => '{rezervace}'],
            ['label' => 'Motorky na pobočce', 'href' => '{katalog}'],
            ['label' => 'Detail pobočky', 'href' => '/pobocky/velke-nemcice'],
        ],
    ],
    'outro' => [
        'title' => 'Půjčovna motorek Brno – pronájem motorky na jižní Moravě',
        'paragraphs' => [
            'MotoGo24 je <strong>motopůjčovna pro Brno a celou jižní Moravu</strong>. Na samoobslužné pobočce ve Velkých Němčicích si půjčíš motorku bez kauce a bez čekání na obsluhu — rezervaci i platbu vyřídíš online a <strong>pronájem motorky</strong> začne ve chvíli, kterou si sám zvolíš.',
            '<strong>Půjčení motorky u Brna</strong> se hodí na den, na víkend i na delší cestu – kilometry neomezujeme a vyrazit můžeš i do zahraničí (v rámci zelené karty). Pobočka leží mezi Židlochovicemi a Hustopečemi, 20 minut od jižního okraje Brna.',
            'Jedeš z Vysočiny nebo z Prahy? Vyzkoušej naši obslužnou pobočku — <a href="/motopujcovna-vysocina">motopůjčovna Vysočina v Mezné u Pelhřimova</a>, kde ti motorku předáme osobně.',
        ],
    ],
];
