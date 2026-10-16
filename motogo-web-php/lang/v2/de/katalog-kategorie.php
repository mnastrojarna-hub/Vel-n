<?php
// Katalog-Kategorieseiten (DE): Outro-Text + Meta-Description je Kategorie (pages/katalog.php → siteContent('katalog_<cat>')).
// CS-Standard = $categoryOutros / $catDescriptions in pages/katalog.php. 'models' = Satz mit bis zu 3 aktuellen Modellen
// ({models}), nur bei Kategorien mit Motorrädern an body1 angehängt; sonst 'nomodels'.
return ['pages' => [
'katalog_cestovni' => [
    'outro' => [
        'title' => 'Reisemotorräder zur Miete — für lange Touren und den Urlaub',
        'body1' => 'Die Reise- und Adventure-Motorräder unserer Flotte sind für lange Strecken gebaut — höhere Sitzposition, bequemer Sitz für Fahrer und Sozius, großer Tank mit 300–400 km Reichweite und Koffer für das Gepäck.',
        'models' => 'Aktuell finden Sie bei uns zum Beispiel {models} — alle regelmäßig gewartet und bereit für Touren durch Tschechien und ins Ausland.',
        'nomodels' => 'Alle sind regelmäßig gewartet und bereit für Touren durch Tschechien und ins Ausland.',
        'body2' => 'Wir vermieten ohne Kaution, die Grüne Karte und internationale Dokumente gibt es automatisch dazu, und die komplette Fahrerausrüstung ist im Preis inbegriffen. Ausrüstung für den Sozius (Helm, Jacke, Sturmhaube) können Sie gegen Aufpreis dazubuchen.',
    ],
    'description' => 'Verleih von Reisemotorrädern (Touring, GT) in der Region Vysočina. Adventure-Bikes für lange Strecken und Autobahnen. Ohne Kaution, Online-Buchung.',
],
'katalog_naked' => [
    'outro' => [
        'title' => 'Naked Bikes — sportliche Maschinen für jeden Tag',
        'body1' => 'Naked Bikes ohne Verkleidung bieten <strong>ein unverwechselbares Gefühl von Freiheit</strong> und eine direkte Verbindung zum Motor. Sie eignen sich für zügige Fahrten in der Stadt, Wochenendausflüge und Kurvenspaß.',
        'models' => 'In unserer Flotte finden Sie zum Beispiel {models} — alle in hervorragendem technischem Zustand und regelmäßig gewartet.',
        'nomodels' => 'Alle sind in hervorragendem technischem Zustand und regelmäßig gewartet.',
        'body2' => 'Wir vermieten ohne Kaution, und die Fahrerausrüstung (Helm, Jacke, Hose, Handschuhe) ist immer im Preis inbegriffen. Vor der Übernahme sehen wir uns das Motorrad gemeinsam an und erklären Ihnen seine Besonderheiten. Wenn Sie mit einer bestimmten Leistungsklasse keine Erfahrung haben, helfen wir Ihnen gern bei der Auswahl.',
    ],
    'description' => 'Verleih von Naked Bikes in der Region Vysočina. Sportliche Tourenmaschinen für jeden Tag. Ohne Kaution, Ausrüstung inklusive, Online-Buchung.',
],
'katalog_supermoto' => [
    'outro' => [
        'title' => 'Supermoto-Motorräder — leichte und wendige Maschinen für Stadtspaß',
        'body1' => 'Supermoto verbindet die Vorzüge einer Enduro (geringes Gewicht, lange Federwege, hohe Sitzposition) mit Straßenreifen und Scheibenbremsen. Das Ergebnis ist <strong>eine sehr wendige Maschine</strong>, die mit Stadtverkehr, Feldwegen und kurzen Touren durch die Vysočina gleichermaßen zurechtkommt.',
        'models' => 'Im Katalog finden Sie zum Beispiel {models}.',
        'body2' => 'Diese Motorräder erfordern einen Führerschein der Klasse A oder A2 und eignen sich eher für erfahrenere Fahrer, die die Verspieltheit und Leichtigkeit der Maschine genießen möchten. Wir vermieten ohne Kaution, die Fahrerausrüstung ist im Preis inbegriffen. Bei der Übernahme erklären wir Ihnen die Besonderheiten des Fahrens mit hoher Sitzposition und worauf es beim Gleichgewicht ankommt.',
    ],
    'description' => 'Verleih von Supermoto-Motorrädern in der Region Vysočina. Leichte Stadtmaschinen mit hoher Sitzposition. Ohne Kaution, Ausrüstung inklusive, Online-Buchung.',
],
'katalog_chopper' => [
    'outro' => [
        'title' => 'Chopper und Cruiser für entspanntes Fahren',
        'body1' => 'Chopper und Cruiser sind für <strong>bequemes Fahren über lange Strecken</strong> gebaut — niedrige Sitzhöhe, entspannte Sitzhaltung, der charakteristische Klang eines Zweizylinders und klassische Optik. Ideal für den Sonntagsausflug oder eine längere Reise durch Tschechien.',
        'body2' => 'Wir erweitern unser Angebot laufend — wenn Sie ein bestimmtes Modell im Sinn haben, melden Sie sich bei uns. Wir vermieten ohne Kaution, die Fahrerausrüstung ist im Preis inbegriffen. Bei der Übernahme erhalten Sie die Schlüssel, die Papiere und die komplette Ausrüstung.',
    ],
    'description' => 'Verleih von Choppern und Cruisern in der Region Vysočina. Bequeme Maschinen für entspanntes Fahren. Ohne Kaution, Ausrüstung inklusive, Online-Buchung.',
],
'katalog_detske' => [
    'outro' => [
        'title' => 'Kindermotorräder — sicherer Spaß für kleine Fahrer',
        'body1' => 'Kindermotorräder können Sie <strong>ohne Führerschein</strong> mieten und im Garten, auf dem Campingplatz oder im Rahmen eines Fahrkurses für Kinder nutzen.',
        'models' => 'Im Katalog finden Sie zum Beispiel {models}.',
        'body2' => 'Vor jeder Fahrt empfehlen wir, mit dem Kind die grundlegenden Sicherheitsregeln durchzugehen und es immer mit Helm und Protektoren auszustatten. Termin, Filiale und eine eventuelle Zustellung vereinbaren Sie direkt bei der Buchung.',
    ],
    'description' => 'Verleih von Kindermotorrädern ohne Führerschein. Sicherer Spaß im Garten oder auf dem Campingplatz. Lieferung in ganz Tschechien, Online-Buchung.',
],
'katalog_sportovni' => [
    'outro' => [
        'title' => 'Sportmotorräder — Adrenalin und Leistung für erfahrene Fahrer',
        'body1' => 'Sportmotorräder (Supersport) sind für <strong>erfahrene Fahrer</strong> gedacht, die hohe Leistung, eine scharfe Geometrie und eine sportliche Sitzposition suchen. Sie eignen sich für die Rennstrecke, kurvige Straßen und Wochenendausflüge auf schönen Strecken in Mähren und der Vysočina.',
        'body2' => 'Wir verlangen einen Führerschein der Klasse A und mindestens 2 Jahre Fahrpraxis auf einem Motorrad über 35 kW. Wir vermieten ohne Kaution, die komplette Fahrerausrüstung ist im Preis inbegriffen. Vor der Übernahme erklären wir Ihnen die Besonderheiten eines Sportmotorrads und empfehlen sichere Fahrweisen.',
    ],
    'description' => 'Verleih von Sportmotorrädern in der Region Vysočina. Supersport- und Sporttourer-Maschinen. Ohne Kaution, Ausrüstung inklusive, Online-Buchung.',
],
'katalog_scootery' => [
    'outro' => [
        'title' => 'Roller zur Miete — bequem durch die Stadt mit Führerschein A1 oder B',
        'body1' => 'Roller sind die ideale Wahl für <strong>bequemes und unkompliziertes Fahren in der Stadt</strong> — Automatikgetriebe, niedrige Sitzhöhe und Stauraum unter dem Sitz. Einen Teil unserer Roller dürfen Sie auch mit dem Führerschein der <strong>Klasse B</strong> (Autoführerschein) fahren, die übrigen mit <strong>A1</strong>. Die genaue Führerscheinklasse finden Sie immer im Detail der jeweiligen Maschine.',
        'body2' => 'Wir vermieten ohne Kaution, und die Fahrerausrüstung (Helm, Handschuhe) ist im Preis inbegriffen. Ein Roller ist ideal zum Pendeln, für Ausflüge in die Umgebung und als erstes Kennenlernen eines Zweirads. Bei der Übernahme erklären wir Ihnen die Bedienung und die Besonderheiten des Fahrens.',
    ],
    'description' => 'Rollerverleih in der Region Vysočina. Roller für Führerschein A1 oder B für bequeme Stadtfahrten. Ohne Kaution, Ausrüstung inklusive, Online-Buchung.',
],
'katalog_ostatni' => [
    'outro' => [
        'title' => 'Motorradanhänger und weitere Ausrüstung zur Miete',
        'body1' => 'In der Kategorie Sonstiges finden Sie <strong>Anhänger für den Motorradtransport</strong> und weitere Zusatzausrüstung zum Ausleihen. Ein Motorradanhänger ist praktisch, wenn Sie Ihre Maschine zur Rennstrecke, in den Urlaub oder in die Werkstatt bringen. Zum Ziehen des Anhängers genügt ein normaler Führerschein der <strong>Klasse B</strong> (je nach Gesamtgewicht des Gespanns).',
        'body2' => 'Wir vermieten ohne Kaution und beraten Sie gern bei der Auswahl sowie beim richtigen Verladen und Sichern des Motorrads. Die genauen Parameter (Nutzlast, Abmessungen, erforderliche Führerscheinklasse) finden Sie im Detail jedes Artikels. Termin und Ort der Abholung vereinbaren Sie direkt bei der Buchung.',
    ],
    'description' => 'Verleih von Motorradanhängern und weiterer Ausrüstung in der Region Vysočina. Anhänger für Führerschein B. Ohne Kaution, Online-Buchung.',
],
]];
