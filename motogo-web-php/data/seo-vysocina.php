<?php
// ===== MotoGo24 — SEO stránka „Motopůjčovna Vysočina“ (/motopujcovna-vysocina) =====
// Výchozí CS texty (pages/seo-pobocka.php). Pobočka Mezná u Pelhřimova (obslužná).
// Fakta jen z data/pobocky.php, pages/pobocky-v2-texts.php a stránky Přistavení —
// při změně podmínek pobočky upravit i tady. Texty jdou přepsat z webu (inline CMS,
// klíče web.seo_vysocina.*). Nahradila krajské stránky /oblasti (majitel 2026-11-26).
// Majitel 2026-11-27: bez tipů na výlety (sekce 'tips' zrušena) a FAQ jen místní otázky, které neřeší
// obecné /jak-pujcit/faq (kauce, výbava, mytí a tankování… tam, ne tady). V Jihlavě pobočka není — jen přistavení.

return [
    'seo' => [
        'title' => 'Motopůjčovna Vysočina – půjčovna motorek | MotoGo24',
        'description' => 'Půjčovna motorek na Vysočině: Mezná u Pelhřimova, zhruba 90 minut z Prahy. Osobní předání nonstop, bez kauce, výbava v ceně, přistavení na adresu.',
        'keywords' => 'motopůjčovna Vysočina, půjčovna motorek Vysočina, motopůjčovna Pelhřimov, půjčovna motorek Pelhřimov, motopůjčovna Jihlava, půjčovna motorek Jihlava, motopůjčovna Humpolec, motopůjčovna Tábor, motopůjčovna Havlíčkův Brod, pronájem motorky Vysočina',
    ],
    'h1' => 'Motopůjčovna Vysočina – Mezná u Pelhřimova',
    'intro' => 'Hledáš <strong>motopůjčovnu na Vysočině</strong>? Na <strong>obslužné pobočce v Mezné u Pelhřimova</strong> ti motorku <strong>předáme osobně</strong> — vše vysvětlíme a pomůžeme s nastavením i výbavou. Pobočka funguje <strong>nonstop</strong> včetně víkendů a svátků, je <strong>bez kauce</strong> a výbavu pro řidiče máš v ceně. Z Prahy to máš po D1 zhruba 90 minut.',
    'cta_top' => 'REZERVOVAT NA VYSOČINĚ',
    'why' => [
        'title' => 'Proč si půjčit motorku na Vysočině právě u nás',
        'items' => [
            ['icon' => 'gfx/predani-motorky.svg', 'title' => 'Předání osobně', 'text' => 'Motorku ti předáme osobně, projdeme s tebou ovládání i předávací protokol a poradíme s výbavou.'],
            ['icon' => 'gfx/ico-nonstop.svg', 'title' => 'Nonstop i o svátcích', 'text' => 'Pobočka funguje PO–NE nonstop včetně víkendů a svátků. Čas převzetí a vrácení si zvolíš v rezervaci.'],
            ['icon' => 'gfx/ico-vybava.svg', 'title' => 'Výbava v ceně až do 6XL', 'text' => 'Výbava pro řidiče je v ceně, bundy a kalhoty máme až do velikosti 6XL. Půjčíme ti i nepromoky a další doplňkovou výbavu.'],
            ['icon' => 'gfx/ico-pristaveni.svg', 'title' => 'Přistavení na adresu', 'text' => 'Motorku ti za příplatek přivezeme domů, na hotel nebo na nádraží — do Jihlavy, Tábora i kamkoliv v Česku.'],
            ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'Bez kauce', 'text' => 'Neblokujeme ti peníze na kartě. Zaplatíš jen cenu pronájmu online při rezervaci.'],
            ['icon' => 'gfx/adresa.svg', 'title' => 'Zázemí a parkování', 'text' => 'Wi-Fi, WC, převlékací kabinka a uzamykatelné skříňky. Auto u nás necháš po celou dobu výpůjčky zdarma.'],
        ],
    ],
    'areas' => [
        'title' => 'Motopůjčovna pro Pelhřimov, Jihlavu, Humpolec i Tábor',
        'text' => 'Mezná leží kousek za Pelhřimovem, na pomezí <strong>Vysočiny</strong> a jižních Čech. K pobočce to máš blízko z celého okolí:',
        'items' => [
            '<strong>Pelhřimov</strong> — pár minut',
            '<strong>Humpolec, Pacov a Kamenice nad Lipou</strong>',
            '<strong>Jihlava, Telč a Třebíč</strong>',
            '<strong>Havlíčkův Brod a Žďár nad Sázavou</strong>',
            '<strong>Tábor a Jindřichův Hradec</strong>',
            '<strong>Praha</strong> — zhruba 90 minut po D1',
        ],
        'note' => 'Nechceš jet na pobočku? Motorku ti <a href="/jak-pujcit/pristaveni">přistavíme na adresu</a> — do Jihlavy, Havlíčkova Brodu, Tábora i jinam po Česku.',
    ],
    'process' => [
        'title' => 'Jak si půjčit motorku na Vysočině',
        'steps' => [
            ['icon' => 'gfx/ico-step1.svg', 'title' => 'Rezervuj online', 'text' => 'Vyber motorku na pobočce Mezná, zvol termín a čas převzetí a zaplať online.'],
            ['icon' => 'gfx/ico-step2.svg', 'title' => 'Nahraj doklady', 'text' => 'Občanku nebo pas a řidičák nahraj online. Když to nestihneš, zkontrolujeme je při převzetí.'],
            ['icon' => 'gfx/ico-step3.svg', 'title' => 'Převezmi motorku', 'text' => 'Ve zvolený čas tě na pobočce čekáme, předáme motorku i výbavu a podepíšeme protokol.'],
            ['icon' => 'gfx/ico-step4.svg', 'title' => 'Vrať ji na pobočku', 'text' => 'Mýt ani tankovat nemusíš, jen ať nesvítí rezerva. Nebo si ji vyzvedneme na domluvené adrese.'],
        ],
    ],
    'faq' => [
        'title' => 'Časté otázky: půjčovna motorek Vysočina',
        'items' => [
            ['q' => 'Kde je motopůjčovna na Vysočině?', 'a' => 'Obslužná pobočka MotoGo24 je v Mezné u Pelhřimova (Mezná 9, 393 01 Pelhřimov), pár minut od Pelhřimova. Z Prahy to máš po D1 zhruba 90 minut.'],
            ['q' => 'Přivezete motorku i do Jihlavy nebo Tábora?', 'a' => 'Ano. Z pobočky v Mezné ti motorku za příplatek přistavíme na adresu – do Jihlavy, Tábora, Humpolce i kamkoliv v Česku. Adresu a čas zadáš v rezervaci a cena přistavení se dopočítá sama.'],
            ['q' => 'Kdy si můžu motorku v Mezné vyzvednout?', 'a' => 'V Mezné předáváme motorky osobně PO–NE nonstop, včetně víkendů a svátků. Čas převzetí i vrácení si zvolíš v rezervaci a ve zvolený čas tě na pobočce čekáme.'],
        ],
    ],
    'cta' => [
        'title' => 'Rezervuj si motorku na Vysočině',
        'text' => 'Vyber si stroj na pobočce Mezná, zvol termín a my ti ho předáme osobně — nebo přivezeme na adresu.',
        'buttons' => [
            ['label' => 'REZERVOVAT', 'href' => '{rezervace}'],
            ['label' => 'Motorky na pobočce', 'href' => '{katalog}'],
            ['label' => 'Detail pobočky', 'href' => '/pobocky/mezna'],
        ],
    ],
    'outro' => [
        'title' => 'Půjčovna motorek Vysočina – pronájem motorky u Pelhřimova',
        'paragraphs' => [
            'MotoGo24 je <strong>motopůjčovna na Vysočině</strong> s obslužnou pobočkou v Mezné u Pelhřimova. Motorku ti předáme osobně, bez kauce a s výbavou pro řidiče v ceně — <strong>pronájem motorky</strong> si rezervuješ online za pár minut.',
            'Za příplatek ti motorku přivezeme i na adresu, třeba do Jihlavy nebo Tábora. Čas převzetí i vrácení si zvolíš v rezervaci – motorky předáváme denně, včetně víkendů a svátků.',
            'Jsi z Brna nebo jižní Moravy? Vyzkoušej naši samoobslužnou pobočku — <a href="/motopujcovna-brno">motopůjčovna Brno ve Velkých Němčicích</a>, kde si motorku vyzvedneš nonstop 24/7.',
        ],
    ],
];
