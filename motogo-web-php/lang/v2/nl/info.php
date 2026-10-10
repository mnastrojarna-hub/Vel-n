<?php
// Landing v2 — informační stránky (Jak si půjčit ×8, FAQ, Kontakt): texty nových
// prvků wrapperu landing-info.php (hero tlačítka a chipy, AI asistent, karty
// poboček na Kontaktu). Ruční NL texty dle ES pilotu, tykání (je), kauce = „borg“, měna EUR.
// CS defaulty: lpiDefaults() v landing-info.php.
return ['pages' => ['landing_info' => [
    'cta_primary' => 'RESERVEREN',
    'cta_secondary' => 'BEKIJK MOTOREN',
    'cta_call' => 'BELLEN',
    'reserve' => 'Motor reserveren',
    'steps_title' => 'Stap voor stap',
    'read_more' => 'Lees meer',
    'read_less' => 'Toon minder',
    'chips' => [
        'postup' => ['Zonder borg', 'Rijuitrusting inbegrepen', 'Online reserveren in minuten'],
        'prevzeti' => ['Ophalen op jouw tijd', 'Gratis parkeren', 'Zonder borg'],
        'vraceni_pujcovna' => ['Laatste dag tot 24:00', 'Tanken hoeft niet', 'Zonder borg'],
        'vraceni_jinde' => ['Overal in Tsjechië', 'Duidelijke prijs per km', 'Zonder borg'],
        'cena' => ['€ 0 borg', 'Rijuitrusting inbegrepen', 'Geen verborgen kosten'],
        'pristaveni' => ['Naar je huis, hotel of station', 'In heel Tsjechië', 'Zonder borg'],
        'dokumenty' => ['Zonder borg', 'Helder contract', 'Veilig online betalen'],
        'faq' => ['Zonder borg', 'Rijuitrusting inbegrepen', 'AI-assistent 24/7'],
        'kontakt' => ['2 vestigingen: Vysočina en Brno', 'Zelfbediening 24/7 bij Brno', 'Online reserveren'],
    ],
    'ai' => [
        'title' => 'AI-assistent 24/7',
        'text' => 'Geen antwoord gevonden? Vraag het aan Tomáš: hij antwoordt meteen, dag en nacht.',
        'card' => 'Vraag het aan Tomáš: direct antwoord',
        'btn' => 'Stel je vraag',
    ],
    'contact' => [
        'branches_title' => 'Onze vestigingen',
        'detail' => 'Bekijk vestiging',
        'route' => 'Route plannen',
        'branches' => [
            [
                'badge' => 'Bemande vestiging',
                'title' => 'Mezná (Pelhřimov, Vysočina)',
                'text' => 'We overhandigen je de motor persoonlijk op het tijdstip van je reservering, elke dag, ook in het weekend en op feestdagen.',
                'chips' => ['Ca. 90 min van Praag', 'Bezorging op je adres'],
                'detail' => 'Bekijk vestiging Mezná',
                'route' => 'Route naar Mezná',
            ],
            [
                'badge' => 'Zelfbediening 24/7',
                'title' => 'Velké Němčice (bij Brno)',
                'text' => 'Je haalt de motor en uitrusting zelf op en levert ze weer in met codes uit de app: 100% nonstop, zonder wachten.',
                'chips' => ['30 min van Brno', '35 min van luchthaven Brno'],
                'detail' => 'Bekijk vestiging Velké Němčice',
                'route' => 'Route naar Velké Němčice',
            ],
        ],
    ],
]]];
