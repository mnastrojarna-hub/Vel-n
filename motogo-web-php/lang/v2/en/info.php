<?php
// Landing v2 — informační stránky (Jak si půjčit ×8, FAQ, Kontakt): texty nových
// prvků wrapperu landing-info.php (hero tlačítka a chipy, AI asistent, karty
// poboček na Kontaktu). Ruční EN texty dle ES pilotu, kauce = „deposit“, měna EUR.
// CS defaulty: lpiDefaults() v landing-info.php.
return ['pages' => ['landing_info' => [
    'cta_primary' => 'BOOK NOW',
    'cta_secondary' => 'SEE BIKES',
    'cta_call' => 'CALL US',
    'reserve' => 'Book a bike',
    'steps_title' => 'Step by step',
    'read_more' => 'Read more',
    'read_less' => 'Show less',
    'chips' => [
        'postup' => ['No deposit', 'Rider gear included', 'Book online in minutes'],
        'prevzeti' => ['Pick-up at your booked time', 'Free parking', 'No deposit'],
        'vraceni_pujcovna' => ['Last day until 24:00', 'No refuelling or washing', 'No deposit'],
        'vraceni_jinde' => ['Anywhere in Czechia', 'Clear per-km pricing', 'No deposit'],
        'cena' => ['€0 deposit', 'Rider gear included', 'No hidden fees'],
        'pristaveni' => ['To your home, hotel or station', 'Across Czechia', 'No deposit'],
        'dokumenty' => ['No deposit', 'Clear contract', 'Secure online payment'],
        'faq' => ['No deposit', 'Rider gear included', 'AI assistant 24/7'],
        'kontakt' => ['2 branches: Vysočina & Brno', 'Self-service 24/7 near Brno', 'About 90 min from Prague'],
    ],
    'ai' => [
        'title' => 'AI assistant 24/7',
        'text' => 'Can\'t find your answer? Ask Tomáš: he replies instantly, day or night.',
        'card' => 'Ask Tomáš: instant answers',
        'btn' => 'Ask now',
    ],
    'contact' => [
        'branches_title' => 'Our branches',
        'detail' => 'Branch details',
        'route' => 'Get directions',
        'branches' => [
            [
                'badge' => 'Staffed branch',
                'title' => 'Mezná (Pelhřimov, Vysočina)',
                'text' => 'We hand over the bike in person at your booked time, every day, weekends and holidays included.',
                'chips' => ['About 90 min from Prague', 'Delivery to your address'],
            ],
            [
                'badge' => 'Self-service 24/7',
                'title' => 'Velké Němčice (near Brno)',
                'text' => 'Pick up and return the bike and gear on your own with app codes: 100% nonstop, no waiting.',
                'chips' => ['30 min from Brno', '35 min from Brno airport'],
            ],
        ],
    ],
]]];
