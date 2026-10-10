<?php
// Landing v2 — informační stránky (Jak si půjčit ×8, FAQ, Kontakt): texty nových
// prvků wrapperu landing-info.php (hero tlačítka a chipy, AI asistent, karty
// poboček na Kontaktu). Ruční DE texty, tykání „du“, kauce = „Kaution“.
// Struktura = lang/v2/es/info.php (schválený pilot); CS defaulty: lpiDefaults() v landing-info.php.
return ['pages' => ['landing_info' => [
    'cta_primary' => 'RESERVIEREN',
    'cta_secondary' => 'MOTORRÄDER ANSEHEN',
    'cta_call' => 'ANRUFEN',
    'reserve' => 'Motorrad reservieren',
    'steps_title' => 'Schritt für Schritt',
    'read_more' => 'Weiterlesen',
    'read_less' => 'Weniger anzeigen',
    'chips' => [
        'postup' => ['Keine Kaution', 'Fahrerausrüstung inklusive', 'Online gebucht in Minuten'],
        'prevzeti' => ['Abholung zu deiner Zeit', 'Kostenloser Parkplatz', 'Keine Kaution'],
        'vraceni_pujcovna' => ['Letzter Tag bis 24:00 Uhr', 'Ohne Tanken und Waschen', 'Keine Kaution'],
        'vraceni_jinde' => ['Überall in Tschechien', 'Klarer Preis pro km', 'Keine Kaution'],
        'cena' => ['0 € Kaution', 'Fahrerausrüstung inklusive', 'Keine versteckten Gebühren'],
        'pristaveni' => ['Nach Hause, ins Hotel oder zum Bahnhof', 'In ganz Tschechien', 'Keine Kaution'],
        'dokumenty' => ['Keine Kaution', 'Verständlicher Vertrag', 'Sichere Online-Zahlung'],
        'faq' => ['Keine Kaution', 'Fahrerausrüstung inklusive', 'KI-Assistent 24/7'],
        'kontakt' => ['2 Filialen: Vysočina und Brno', 'Selbstbedienung 24/7 bei Brno', 'Ca. 90 Min. von Prag'],
    ],
    'ai' => [
        'title' => 'KI-Assistent 24/7',
        'text' => 'Keine Antwort gefunden? Frag Tomáš: Er antwortet sofort, Tag und Nacht.',
        'card' => 'Frag Tomáš: Er antwortet sofort',
        'btn' => 'Fragen',
    ],
    'contact' => [
        'branches_title' => 'Unsere Filialen',
        'detail' => 'Zur Filiale',
        'route' => 'Route planen',
        'branches' => [
            [
                'badge' => 'Mit Personal',
                'title' => 'Mezná (Pelhřimov, Vysočina)',
                'text' => 'Wir übergeben dir das Motorrad persönlich zur reservierten Zeit, jeden Tag, auch am Wochenende und an Feiertagen.',
                'chips' => ['Ca. 90 Min. von Prag', 'Lieferung an deine Adresse'],
            ],
            [
                'badge' => 'Selbstbedienung 24/7',
                'title' => 'Velké Němčice (bei Brno)',
                'text' => 'Motorrad und Ausrüstung holst du selbst ab und gibst sie selbst zurück, mit Codes aus der App: 100 % nonstop, ohne Warten.',
                'chips' => ['30 Min. von Brno', '35 Min. vom Flughafen Brno'],
            ],
        ],
    ],
]]];
