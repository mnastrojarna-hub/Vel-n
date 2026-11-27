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
            'platný řidičský průkaz skupiny, kterou motorka vyžaduje (A, A2, u skútrů A1 nebo B – najdeš ji u motorky v katalogu)',
            'vlastní výbavu – helmu, bundu, kalhoty, rukavice (pokud je nemáš zarezervované u nás)',
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
                'q' => 'Můžu si motorku převzít bez obsluhy?',
                'a' => 'Ano, na <strong>samoobslužné pobočce ve Velkých Němčicích u Brna</strong>. Motorku i výbavu si tam vyzvedneš pomocí kódů z aplikace a předávací protokol podepíšeš na displeji – doklady musíš mít předem nahrané a ověřené online. V Mezné u Pelhřimova ti motorku předáme vždy osobně.',
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
        'title' => 'Rezervuj si motorku i čas převzetí',
        'text' => 'Čas převzetí si zvolíš v rezervaci – i večer, o víkendu nebo ve svátek.',
        'text2' => 'Vyber motorku a rezervuj online.',
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
        'title' => 'Převzetí motorky v půjčovně – co si vzít | MotoGo24',
        'description' => 'Jak probíhá převzetí motorky: osobně v Mezné u Pelhřimova, nebo samoobslužně u Brna kódem z aplikace. Jaké doklady si vzít a co tě čeká na místě.',
        'keywords' => 'motopůjčovna',
    ],
];
