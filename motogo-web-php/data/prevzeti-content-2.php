<?php
// ===== MotoGo24 — Prevzeti v pujcovne 2/2 (amenity + s sebou + FAQ + CTA + SEO) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/prevzeti-v-pujcovne

return [
    'amenities' => [
        'title' => 'Co najdeš v půjčovně',
        'lead' => 'Pro pohodlné převzetí máme připraveno – vše zdarma:',
        'items' => [
            'parkoviště pro zákazníky (kapacita je omezená)',
            'Wi-Fi',
            'WC',
            'zkušební kabinku na vyzkoušení výbavy',
            'uzamykatelné skříňky na úschovu osobních věcí, které nechceš brát na cestu (kapacita omezená)',
        ],
        'cta' => [
            'label' => 'ZAREZERVOVAT TERMÍN',
            'href' => '/rezervace',
            'aria' => 'Zarezervovat termín vyzvednutí motorky v Motogo24',
        ],
    ],
    'bring' => [
        'title' => 'Co si vzít s sebou',
        'items' => [
            'platný občanský průkaz nebo pas',
            'platný řidičský průkaz s oprávněním odpovídající skupiny (A/A2 podle vybrané motorky)',
            'vlastní výbavu – helma, bunda, kalhoty, rukavice (pokud nemáš zarezervované u nás)',
            'pevnou obuv (pokud u nás nemáš rezervaci na motocyklové boty)',
            'vlastní navigaci nebo telefon s navigační aplikací – navigace není součástí výpůjčky',
        ],
    ],
    'faq' => [
        'title' => 'Časté dotazy k vyzvednutí',
        'items' => [
            [
                'q' => 'Musím platit kauci při vyzvednutí?',
                'a' => 'Ne, <strong>půjčujeme bez kauce</strong>. Podmínky jsou jasně dané a férové.',
            ],
            [
                'q' => 'Je možný kontakt bez osobního setkání?',
                'a' => 'Ano, nabízíme <strong>bezkontaktní předání</strong> po domluvě. Instrukce a dokumenty dostaneš předem.',
            ],
            [
                'q' => 'Co když nestíhám domluvený čas?',
                'a' => 'Dej nám vědět telefonicky – přizpůsobíme čas, nebo nabídneme <strong>přistavení</strong> / jiný termín.',
            ],
            [
                'q' => 'Je v ceně i výbava pro spolujezdce?',
                'a' => 'Výbava pro řidiče je v ceně vždy. Výbavu pro spolujezdce lze přiobjednat jako <strong>nadstandard</strong>.',
            ],
        ],
    ],
    'mid_cta' => [
        'label' => 'REZERVOVAT VYZVEDNUTÍ',
        'href' => '/rezervace',
        'aria' => 'Rezervovat vyzvednutí motorky v půjčovně Motogo24',
    ],
    'cta' => [
        'title' => 'Převzetí v půjčovně – půjčovna motorek Vysočina (Pelhřimov)',
        'text' => 'MotoGo24 je <strong>půjčovna motorek na Vysočině</strong> s možností <strong>převzetí motorky kdykoliv</strong> během dne, včetně svátků i víkendů, <strong>bez kauce</strong> a <strong>s výbavou pro řidiče v ceně</strong> výpůjčky.',
        'text2' => 'Vyber si <strong>cestovní, supermoto, naked nebo dětskou motorku</strong> a pohodlně ji rezervuj online.',
        'buttons' => [
            [
                'label' => 'REZERVOVAT ONLINE',
                'href' => '/rezervace',
                'cls' => 'btndark pulse',
                'aria' => 'Přejít na online rezervaci a domluvit vyzvednutí motorky',
            ],
        ],
    ],
    'seo' => [
        'title' => 'Půjčovna motorek Vysočina – Jak si půjčit motorku – Převzetí v půjčovně',
        'description' => 'Převzetí motorky v půjčovně motorek MotoGo24 je rychlé a bez starostí. Připrav si doklady a během pár minut můžeš vyrazit. Rezervuj si motorku jednoduše online. Vyber termín, stroj i výbavu a vyraz na nezapomenutelnou jízdu s MotoGo24 na Vysočině.',
        'keywords' => 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, půjčovna cestovní motorky, pronájem sportovní motorky, půjčovna enduro motorek, půjčovna skútrů Vysočina, dětské motorky k pronájmu, rezervace motorky online, motorky k pronájmu Vysočina, motorbike rental Czech Republic, motorcycle hire Vysocina, rent a motorbike Pelhřimov',
    ],
];
