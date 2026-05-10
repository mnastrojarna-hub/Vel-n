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
                'a' => 'Ne, půjčujeme bez kauce. Podmínky jsou jasně dané a férové.',
            ],
            [
                'q' => 'Je možný kontakt bez osobního setkání?',
                'a' => 'Ano, nabízíme bezkontaktní předání po domluvě. Instrukce a dokumenty dostaneš předem.',
            ],
            [
                'q' => 'Co když nestíhám domluvený čas?',
                'a' => 'Dej nám vědět telefonicky – přizpůsobíme čas, nebo nabídneme přistavení / jiný termín.',
            ],
            [
                'q' => 'Je v ceně i výbava pro spolujezdce?',
                'a' => 'Výbava pro řidiče je v ceně vždy. Výbavu pro spolujezdce lze přiobjednat jako nadstandard.',
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
        'text' => 'MotoGo24 je <strong>půjčovna motorek na Vysočině</strong> s možností převzetí motorky kdykoliv během dne, včetně svátků i víkendů, bez kauce a s výbavou pro řidiče v ceně výpůjčky.',
        'text2' => 'Vyber si cestovní, supermoto, naked nebo dětskou motorku a pohodlně ji rezervuj online.',
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
        // Krátký, klíčová slova vpředu (~58 znaků – v Google SERP se neořeže).
        'title' => 'Převzetí motorky v půjčovně Pelhřimov | MotoGo24',
        // ~155 znaků – pod 1000 px limitem, jasné CTA + lokalita.
        'description' => 'Převzetí motorky v MotoGo24 Pelhřimov: rychle, bez kauce, výbava pro řidiče v ceně. Otevřeno nonstop. Rezervuj termín online během pár minut.',
        'keywords' => 'motopůjčovna, půjčovna motorek Vysočina, převzetí motorky Pelhřimov, MotoGo24',
    ],
];
