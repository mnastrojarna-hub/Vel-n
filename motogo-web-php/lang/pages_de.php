<?php
// MotoGo24 — pages_de.php (Deutsch overlay nad CS defaults)
// Zkracena verze — hlavni texty (h1, intro, SEO, CTA) prelozeny.
// Strukturalni obsah (steps, FAQ items, gear lists) propada na CS pres deep merge.

return [
    'pages' => [

        'jak_pujcit_cena' => [
            'seo' => [
                'title' => 'Motorradvermietung Vysočina – Wie miete ich – Was ist im Preis enthalten',
                'description' => 'Erfahre, was im Mietpreis bei MotoGo24 enthalten ist. Klare Bedingungen, Ausrüstung und Service ohne versteckte Gebühren. Reserviere deine Motorrad einfach online.',
                'keywords' => 'Motorradvermietung Vysočina, Motorradverleih Pelhřimov, Vermietung ohne Kaution, 24/7 Motorradverleih, Online-Reservierung Motorrad',
            ],
            'h1' => 'Was ist im Mietpreis enthalten',
            'intro' => 'Bei <strong>MotoGo24 – Motorradvermietung in Vysočina</strong> bekommst du faire Bedingungen. <strong>Ohne Kaution, mit Fahrerausrüstung im Preis und Rund-um-die-Uhr-Service</strong>. Alles, was du für eine sichere und entspannte Fahrt brauchst, ist enthalten.',
            'cta' => [
                'title' => 'Ausrüstung im Preis – Motorradvermietung MotoGo24 – Vysočina',
                'text' => '<strong>MotoGo24 ist eine moderne Motorradvermietung in Vysočina</strong> mit Fahrerausrüstung im Preis, Vermietung ohne Kaution und Rund-um-die-Uhr-Service. Wähle ein <strong>Touren-, Supermoto-, Naked- oder Kinder-Motorrad</strong> und reserviere online.',
                'buttons' => [
                    ['label' => 'ONLINE RESERVIEREN', 'href' => '/rezervace', 'cls' => 'btndark pulse', 'aria' => 'Motorrad mit Ausrüstung im Preis bei Motogo24 reservieren'],
                ],
            ],
        ],

        'jak_pujcit_dokumenty' => [
            'seo' => [
                'title' => 'Motorradvermietung Vysočina – Dokumente und Anleitungen',
                'description' => 'Mietvertrag, Bedingungen und notwendige Dokumente für die Motorradmiete. Ohne Kaution, klare Regeln, Versicherung im Preis.',
                'keywords' => 'Mietvertrag Motorrad, Vermietungsdokumente, Mietbedingungen, Motorradversicherung, MotoGo24',
            ],
            'h1' => 'Mietvertrag und Kaution – faire Bedingungen ohne Anzahlung',
            'intro' => 'Bei <strong>MotoGo24</strong> setzen wir auf Einfachheit und Fairness. Wir vermieten <strong>ohne Kaution</strong>, mit einem <strong>klaren Mietvertrag</strong>, <strong>Versicherung im Preis</strong> und <strong>Fahrerausrüstung</strong>.',
            'top_cta' => ['label' => 'ONLINE RESERVIEREN', 'href' => '/rezervace', 'aria' => 'Motorrad online bei Motogo24 reservieren'],
            'cta' => [
                'title' => 'Mietvertrag ohne Kaution – Motorradvermietung Vysočina',
                'text' => 'MotoGo24 ist eine <strong>Motorradvermietung in Vysočina</strong> mit fairen Bedingungen.',
                'buttons' => [['label' => 'ONLINE RESERVIEREN', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
            ],
        ],

        'jak_pujcit_pristaveni' => [
            'seo' => [
                'title' => 'Motorradlieferung | MotoGo24',
                'description' => 'Motorradlieferung direkt zu dir. Wir bringen das Motorrad zum Hotel, Bahnhof oder zu jeder Adresse. Tarif ab 290 Kč. Rund-um-die-Uhr-Service.',
                'keywords' => 'Motorradlieferung, Motorrad bringen, Motorrad-Auslieferung, Motorradverleih Vysočina',
            ],
            'h1' => 'Motorradlieferung – direkt zu dir',
            'intro' => 'Du willst losfahren, ohne zur Vermietung zu fahren? Wir organisieren die <strong>Motorradlieferung</strong> an einen <strong>vereinbarten Ort</strong>.',
            'top_cta' => ['label' => 'MIT LIEFERUNG RESERVIEREN', 'href' => '/rezervace?delivery=1'],
            'cta' => [
                'title' => 'Motorradlieferung – Motorradvermietung Vysočina',
                'text' => 'MotoGo24 bietet <strong>Motorradlieferung</strong> in der Region und darüber hinaus. <strong>Rund-um-die-Uhr-Service, ohne Kaution, Ausrüstung im Preis</strong>.',
                'buttons' => [['label' => 'MIT LIEFERUNG RESERVIEREN', 'href' => '/rezervace?delivery=1', 'cls' => 'btndark pulse']],
            ],
        ],

        'jak_pujcit_vraceni_jinde' => [
            'seo' => [
                'title' => 'Motorrad-Rückgabe woanders | MotoGo24',
                'description' => 'Gib das Motorrad außerhalb der Vermietung zurück – vom Hotel, Bahnhof oder einer anderen Adresse. Abholung in Vysočina und darüber hinaus. Preis nach Entfernung.',
                'keywords' => 'Motorrad-Rückgabe woanders, Motorrad-Abholung, Rückgabe außerhalb, Motorradverleih Vysočina',
            ],
            'h1' => 'Motorrad-Rückgabe woanders – Abholung zu dir',
            'intro' => 'Du musst nicht zur Vermietung zurückkehren. <strong>MotoGo24</strong> bietet die <strong>Motorrad-Abholung</strong> von einem Ort, der dir passt – Hotel, Bahnhof, eigene Adresse.',
            'top_cta' => ['label' => 'MIT ABHOLUNG RESERVIEREN', 'href' => '/rezervace?return_delivery=1'],
            'cta' => [
                'title' => 'Motorrad-Rückgabe überall – MotoGo24',
                'text' => 'MotoGo24 organisiert die <strong>Motorrad-Abholung</strong> von einem Ort deiner Wahl. <strong>Rund-um-die-Uhr, ohne Kaution, ohne Sorgen.</strong>',
                'buttons' => [['label' => 'MIT ABHOLUNG RESERVIEREN', 'href' => '/rezervace?return_delivery=1', 'cls' => 'btndark pulse']],
            ],
        ],

        'faq' => [
            'seo' => [
                'title' => 'Häufig gestellte Fragen | MotoGo24',
                'description' => 'Häufig gestellte Fragen zur Motorradmiete. Reservierung, Übernahme, Rückgabe, Bedingungen, Lieferung, Reisen ins Ausland, Geschenkgutscheine.',
                'keywords' => 'FAQ Motorradvermietung, Fragen Motorradmiete, Mietbedingungen, Kaution, Ausrüstung',
            ],
            'h1' => 'Häufig gestellte Fragen – Motorradvermietung MotoGo24',
            'closing' => 'Unsere <strong>Motorradvermietung in Vysočina</strong> ist für alle da, die eine <strong>unvergessliche Fahrt</strong> ohne unnötige Komplikationen erleben wollen.',
            'cta' => ['label' => 'Motorrad online reservieren', 'href' => '/rezervace'],
        ],

        'home' => [
            'seo' => [
                'title' => 'Motorradvermietung in Vysočina | MotoGo24',
                'description' => 'Miete ein Motorrad in Vysočina. Ohne Kaution, Ausrüstung im Preis, Rund-um-die-Uhr-Service. Touren-, Sport-, Enduro- und Kinder-Motorräder. Online-Reservierung.',
                'keywords' => 'Motorradvermietung Vysočina, Motorradverleih Pelhřimov, Vermietung ohne Kaution, 24/7 Vermietung, Motorräder zur Miete, Online-Reservierung Motorrad',
                'og_image' => null,
            ],
            'hero' => [
                'image' => 'gfx/hero-banner.jpg',
                'alt' => 'Motorradvermietung Vysočina',
                'eyebrow' => '<strong>Motorradvermietung</strong> in Vysočina',
                'body' => 'Miete ein Motorrad in Vysočina einfach online.<br>Wähle aus Touren-, Sport- und Enduro-Modellen.<br>Reservierung mit Kartenzahlung und schneller Übernahme.',
                'cta_primary' => ['label' => 'WÄHLE DEIN MOTORRAD', 'href' => '/katalog', 'cls' => 'btngreen'],
                'cta_secondary' => ['label' => 'WIE ES FUNKTIONIERT', 'href' => '/jak-pujcit', 'cls' => 'btndark'],
            ],
            'h1' => 'Motorradvermietung Vysočina Motogo24 – ohne Kaution und 24/7',
            'intro' => 'Willkommen bei <strong>Motogo24</strong> – deiner Motorradvermietung in Vysočina. Hier mietest du ein Motorrad <strong>ohne Kaution</strong>, mit Ausrüstung im Preis und im <strong>Rund-um-die-Uhr-Modus</strong>. Egal ob Touren-, Sport-, Enduro- oder Kinder-Motorrad – Motogo24 im Herzen von Vysočina hat das richtige für dich.',
            'signposts_title' => 'Schneller Wegweiser bei Motogo24',
            'motos_section' => [
                'title' => 'Unsere Motorräder zur Miete in Vysočina',
                'intro' => 'Schau dir unser Angebot an Touren-, Sport- und Enduro-Motorrädern unserer Vermietung in Vysočina an.',
                'empty' => 'Derzeit sind keine Motorräder verfügbar.',
                'cta_label' => 'MOTORRADKATALOG',
                'cta_href' => '/katalog',
                'limit' => 4,
            ],
            'process' => ['title' => 'Wie die Motorradvermietung in Vysočina abläuft'],
            'faq' => ['title' => 'Häufig gestellte Fragen', 'more_link' => '/jak-pujcit/faq'],
            'cta' => [
                'title' => 'Reserviere dein Motorrad online',
                'text' => 'Unsere <strong>Motorradvermietung Vysočina</strong> ist <strong>rund um die Uhr</strong> geöffnet. Ein paar Klicks und deine Fahrt beginnt.',
                'buttons' => [
                    ['label' => 'MOTORRAD RESERVIEREN', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
                    ['label' => 'Geschenkgutschein', 'href' => '/poukazy', 'cls' => 'btndark'],
                    ['label' => 'Tourentipps', 'href' => '/blog', 'cls' => 'btndark'],
                ],
            ],
            'blog' => [
                'title' => 'Blog und Tipps',
                'empty' => 'Noch keine Artikel.',
                'cta_label' => 'MEHR IM BLOG LESEN',
                'cta_href' => '/blog',
                'limit' => 3,
            ],
            'reviews' => [
                'title' => 'Was unsere Kunden sagen',
                'intro' => 'Echte Bewertungen von Motorradfahrern, die bei uns gemietet haben. Danke für jede Bewertung.',
            ],
        ],

        'pujcovna' => [
            'seo' => [
                'title' => 'Über die Motorradvermietung | MotoGo24',
                'description' => 'Motogo24 Motorradvermietung in Vysočina. Ohne Kaution, mit Online-Reservierung und Ausrüstung im Preis. Touren-, Sport-, Enduro- und Kinder-Motorräder. Rund-um-die-Uhr-Service.',
                'keywords' => 'Motorradvermietung, Motorradverleih Vysočina, Motorräder ohne Kaution, 24/7 Vermietung, Ausrüstung im Preis',
            ],
            'breadcrumb' => [['label' => 'Startseite', 'href' => '/'], 'Motorradvermietung'],
            'intro' => [
                'h1' => 'Motorradvermietung Vysočina Motogo24',
                'body' => 'Unsere <strong>Motorradvermietung in Vysočina</strong> in Pelhřimov bietet <strong>Motorradverleih</strong> ohne unnötige Hürden – <strong>ohne Kaution</strong>, mit <strong>Online-Reservierung</strong> und <strong>Ausrüstung im Preis</strong>. Wähle aus <strong>Touren-</strong>, <strong>Sport-</strong>, <strong>Enduro-</strong> und <strong>Kinder-Motorrädern</strong> und fahre los, wann immer du willst: wir haben <strong>rund um die Uhr</strong> geöffnet.',
            ],
            'benefits' => [
                'title' => 'Warum bei uns mieten',
                'closing' => 'Suchst du eine <strong>Motorradvermietung in Vysočina</strong>? Motogo24 bietet faire Bedingungen, einen klaren Ablauf und top gewartete Maschinen für Touren in Tschechien und ins Ausland.',
                'buttons' => [
                    ['label' => 'Motorräder zur Miete ansehen', 'href' => '/katalog', 'cls' => 'btngreen'],
                    ['label' => 'RESERVIEREN', 'href' => '/rezervace', 'cls' => 'btngreen pulse'],
                ],
            ],
            'process' => ['title' => 'Wie die Vermietung in Vysočina abläuft'],
            'faq' => ['title' => 'Häufig gestellte Fragen', 'more_link' => '/jak-pujcit/faq'],
            'cta' => [
                'title' => 'Reserviere dein Motorrad online',
                'text' => 'Unsere <strong>Motorradvermietung Vysočina</strong> ist <strong>rund um die Uhr</strong> geöffnet.',
                'buttons' => [
                    ['label' => 'MOTORRAD RESERVIEREN', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
                    ['label' => 'Geschenkgutschein', 'href' => '/poukazy', 'cls' => 'btndark'],
                    ['label' => 'Tourentipps', 'href' => '/blog', 'cls' => 'btndark'],
                ],
            ],
        ],

        'kontakt' => [
            'seo' => [
                'title' => 'Kontakt | MotoGo24 – Motorradvermietung Vysočina',
                'description' => 'Kontakte zur Motogo24 Motorradvermietung in Pelhřimov. Telefon +420 774 256 271, E-Mail info@motogo24.cz. Rund-um-die-Uhr-Service, Adresse Mezná 9, 393 01 Pelhřimov.',
                'keywords' => 'Kontakt Motogo24, Motorradvermietung Pelhřimov, Telefon, Adresse, Öffnungszeiten, 24/7',
            ],
            'h1' => 'Kontakte – Motogo24 Motorradvermietung',
            'intro' => 'Hast du eine Frage zur <strong>Motorradmiete</strong>, möchtest einen <strong>Geschenkgutschein</strong> bestellen, brauchst Hilfe bei der Auswahl oder möchtest direkt eine <strong>Reservierung vereinbaren</strong>? Wir sind jeden Tag für dich da, <strong>rund um die Uhr</strong>.',
            'side_cta' => [
                'title' => 'Möchtest du eine Reservierung vereinbaren?',
                'text' => 'Reserviere dein Motorrad online in wenigen Minuten und starte dein Abenteuer.',
                'button' => ['label' => 'ONLINE RESERVIEREN', 'href' => '/rezervace', 'cls' => 'btndark'],
            ],
            'social_title' => 'Folge uns',
            'map' => ['title' => 'Wo du uns findest'],
            'seo_text' => [
                'title' => 'Kontakte – Motorradvermietung Vysočina (Pelhřimov)',
                'body' => 'Motogo24 ist eine <strong>moderne Motorradvermietung in Vysočina</strong>. Wir sitzen in <strong>Pelhřimov</strong>, sind <strong>rund um die Uhr</strong> geöffnet und vermieten <strong>ohne Kaution</strong>, mit kompletter <strong>Ausrüstung im Preis</strong>.',
            ],
        ],

        'jak_pujcit' => [
            'seo' => [
                'title' => 'Wie miete ich ein Motorrad | MotoGo24',
                'description' => 'Wie miete ich ein Motorrad bei Motogo24. Einfacher Ablauf: Auswahl, Reservierung, Übernahme. Ohne Kaution, Ausrüstung im Preis, Rund-um-die-Uhr-Service.',
                'keywords' => 'wie miete ich ein Motorrad, Mietvorgang, Motorrad reservieren, Motorradverleih Vysočina',
            ],
            'h1' => 'Wie miete ich ein Motorrad',
            'intro' => 'Bei <strong>Motogo24 – Motorradvermietung in Vysočina</strong> ist die Miete einfach, schnell und fair.',
        ],

        'jak_pujcit_postup' => [
            'seo' => [
                'title' => 'Mietvorgang Motorrad | MotoGo24',
                'description' => 'Mietvorgang Motorrad bei Motogo24 Schritt für Schritt. Online-Reservierung, Ausrüstung im Preis, ohne Kaution, Rund-um-die-Uhr-Service und Lieferung.',
                'keywords' => 'Mietvorgang Motorrad, wie Motorrad mieten, Motorradreservierung, Motorradverleih Pelhřimov',
            ],
            'h1' => 'Mietvorgang Motorrad',
            'intro' => '<p>Bei <strong>Motogo24 – Motorradvermietung in Vysočina</strong> ist die Miete einfach, schnell und fair. <strong>Ohne Kaution, mit Ausrüstung im Preis und Rund-um-die-Uhr-Service</strong>.</p>',
            'cta' => [
                'title' => 'Bereit für die Fahrt?',
                'text' => 'Reserviere dein Motorrad noch heute online und genieße die <strong>Freiheit auf zwei Rädern</strong>.',
                'buttons' => [['label' => 'ONLINE RESERVIEREN', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
            ],
        ],

        'jak_pujcit_vyzvednuti' => [
            'seo' => [
                'title' => 'Übernahme des Motorrads in der Vermietung | MotoGo24',
                'description' => 'Übernahme des Motorrads in der Vermietung Pelhřimov. Rund-um-die-Uhr-Service, ohne Kaution, Ausrüstung im Preis. Was mitnehmen und wie die Übergabe abläuft.',
                'keywords' => 'Übernahme Motorrad Vermietung, Motorradabholung, Vermietung Pelhřimov, 24/7 Übernahme',
            ],
            'h1' => 'Übernahme des Motorrads in der Vermietung – schnell, einfach und rund um die Uhr',
            'intro' => 'Bei <strong>Motogo24 – Motorradvermietung Vysočina</strong> ist die <strong>Motorradübernahme</strong> in wenigen Minuten erledigt.',
            'top_cta' => ['label' => 'ONLINE RESERVIEREN', 'href' => '/rezervace'],
            'cta' => [
                'title' => 'Übernahme des Motorrads in der Vermietung – Motogo24 Vysočina',
                'text' => 'Motogo24 ist eine <strong>Motorradvermietung in Vysočina</strong> mit <strong>Rund-um-die-Uhr-Übernahme und -Rückgabe</strong>.',
                'buttons' => [['label' => 'ONLINE RESERVIEREN', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
            ],
        ],

        'jak_pujcit_vraceni_pujcovna' => [
            'seo' => [
                'title' => 'Motorrad-Rückgabe in der Vermietung | MotoGo24',
                'description' => 'Motorrad-Rückgabe direkt in der Vermietung Pelhřimov. Rund um die Uhr, ohne Kaution, ohne unnötige Bürokratie.',
                'keywords' => 'Motorrad-Rückgabe, Rückgabe in der Vermietung, Vermietung Pelhřimov, 24/7 Rückgabe',
            ],
            'h1' => 'Motorrad-Rückgabe in der Vermietung',
            'intro' => 'Du gibst das Motorrad bequem direkt bei <strong>Motogo24 – Motorradvermietung in Vysočina</strong> zurück. <strong>Rund-um-die-Uhr-Service</strong>, ohne Stress.',
            'top_cta' => ['label' => 'ONLINE RESERVIEREN', 'href' => '/rezervace'],
            'cta' => [
                'title' => 'Motorrad-Rückgabe in der Vermietung – Motogo24 Pelhřimov',
                'text' => 'Gib das Motorrad direkt bei uns in Pelhřimov zurück – <strong>rund um die Uhr, ohne Kaution, ohne Stress</strong>.',
                'buttons' => [['label' => 'ONLINE RESERVIEREN', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
            ],
        ],

        'poukazy' => [
            'seo' => [
                'title' => 'Motorradvermietung Vysočina – Geschenkgutscheine',
                'description' => 'Kaufe einen Geschenkgutschein für die Motorradmiete. Gültigkeit 3 Jahre, ohne Kaution, Ausrüstung im Preis. Elektronischer und gedruckter Gutschein.',
                'keywords' => 'Geschenkgutschein Motorrad, Voucher Motorradmiete, Geschenk für Motorradfahrer, Gutschein Motogo24',
                'og_image' => 'https://motogo24.cz/gfx/darkovy-poukaz.jpg',
            ],
            'h1' => 'Kaufe einen Geschenkgutschein – schenke ein Erlebnis auf zwei Rädern!',
            'cta' => [
                'title' => 'Geschenkgutschein für Motorradmiete – Vysočina',
                'text' => 'Motogo24 ist eine <strong>Motorradvermietung in Vysočina</strong> mit <strong>Rund-um-die-Uhr-Service</strong>, <strong>ohne Kaution</strong> und <strong>Ausrüstung im Preis</strong>.',
                'buttons' => [['label' => 'GUTSCHEIN BESTELLEN', 'href' => '/koupit-darkovy-poukaz', 'cls' => 'btndark pulse']],
            ],
        ],
    ],
];
