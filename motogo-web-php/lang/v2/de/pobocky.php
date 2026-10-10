<?php
// DE překlad textů poboček (němčina, tykání „du“; Velín → Texty webu → Pobočky, klíče web.pobocky.*;
// CS hodnoty z CMS k 2026-10-10 = pobockyDefaults() v data/pobocky.php, u výbavy Velkých Němčic
// nové velikosti — helmy S–3XL, bundy/kalhoty/rukavice do 4XL). Struktura = lang/v2/es/pobocky.php
// (bez polí jen z kódu: slug, branch_id, map, photo, gallery, video). siteContent('pobocky')
// použije tento overlay. Texty v2 (karty, průvodce, srovnání): lang/v2/de/pobocky-v2.php.

return ['pages' => ['pobocky' => [
    'seo' => [
        'title' => 'Filialen | MotoGo24 – Motorradvermietung Pelhřimov und Brno',
        'description' => 'Filialen der Motorradvermietung MotoGo24: Filiale mit Personal in Mezná bei Pelhřimov (Vysočina) und Selbstbedienungsfiliale in Velké Němčice bei Brno – Übernahme des Motorrads rund um die Uhr.',
        'keywords' => 'Filialen MotoGo24, Motorradvermietung Pelhřimov, Motorradvermietung Brno, Motorradvermietung Selbstbedienung, Velké Němčice, Mezná',
    ],
    'h1' => 'Filialen von MotoGo24',
    'intro' => 'Dein Motorrad kannst du an <strong>zwei Orten</strong> abholen: in der <strong>Filiale mit Personal in Mezná bei Pelhřimov</strong>, wo wir dich persönlich empfangen, oder in der <strong>Selbstbedienungsfiliale in Velké Němčice bei Brno</strong>, wo du Motorrad und Ausrüstung selbst per Code übernimmst.',
    'branches' => [
        [
            'badge' => 'Filiale mit Personal',
            'title' => 'Mezná bei Pelhřimov',
            'address' => 'Mezná 9, 393 01 Pelhřimov',
            'hours' => 'Mo–So rund um die Uhr (nonstop), auch an Wochenenden und Feiertagen. Abhol- und Rückgabezeit wählst du bei der Reservierung.',
            'text' => 'Unsere Hauptfiliale in Vysočina. Wir <strong>übergeben dir das Motorrad persönlich</strong>: Wir erklären dir alles, helfen beim Einstellen und bei der Wahl der Ausrüstung und gehen gemeinsam das Übergabeprotokoll durch. Die Fahrerausrüstung ist im Preis inbegriffen. Von hier aus bieten wir auch die <strong>Lieferung des Motorrads</strong> an eine Adresse deiner Wahl an.',
            'gear' => 'Fahrerausrüstung im Preis inbegriffen: Jacken und Hosen in Größen bis <strong>6XL</strong>. Nur hier kannst du auch <strong>Regenkombis</strong> und weitere Zusatzausrüstung leihen.',
            'steps_title' => 'So läuft es ab',
            'steps' => '1. Du reservierst und bezahlst online (Website oder App) und lädst deine Dokumente hoch (Ausweis/Reisepass + Führerschein) – darum bitten wir auch in der Filiale mit Personal; lädst du sie nicht hoch, prüfen wir sie bei der Übernahme vor Ort.<br>2. Zur gewählten Zeit kommst du zur Filiale, wo wir auf dich warten.<br>3. Wir übergeben dir Motorrad und Ausrüstung und unterschreiben das Übergabeprotokoll.<br>4. Nach der Fahrt gibst du das Motorrad in der Filiale zurück (oder wir holen es an der vereinbarten Adresse ab).',
            'video_title' => 'Video: So läuft es in der Filiale ab',
            'gallery_title' => 'Fotogalerie der Filiale',
            'seo_title' => 'Filiale Mezná bei Pelhřimov | MotoGo24 – Motorradvermietung mit Personal',
            'seo_description' => 'Filiale der Motorradvermietung MotoGo24 mit Personal in Mezná bei Pelhřimov (Vysočina): persönliche Übergabe des Motorrads rund um die Uhr, Ausrüstung inklusive, Lieferung an deine Adresse.',
        ],
        [
            'badge' => 'Selbstbedienungsfiliale',
            'title' => 'Velké Němčice bei Brno',
            'address' => 'Boudky, 691 63 Velké Němčice',
            'hours' => 'Rund um die Uhr (24/7) per Code aus der App. Die Abholzeit wählst du bei der Reservierung: Bei Abholung ab 12:00 Uhr (Miete ab 2 Tagen) zahlst du für den 1. Tag nur die Hälfte, und der Kiosk gibt dir das Motorrad erst ab 12:00 Uhr heraus. Die Rückgabezeit wählst du nicht: Du gibst das Motorrad am letzten Miettag jederzeit bis 24:00 Uhr zurück.',
            'text' => 'Moderne <strong>Selbstbedienungsfiliale</strong> südlich von Brno. Vor Ort gibt es kein Personal: Du erledigst alles selbst am Touchscreen mit den <strong>Codes aus der App</strong>, die du nach der Zahlung und dem Hochladen deiner Dokumente erhältst. Motorräder dieser Filiale werden nur direkt in der Filiale übernommen und zurückgegeben – Lieferung oder Abholung bieten wir für sie nicht an. An der Filiale kannst du während der gesamten Miete <strong>kostenlos parken</strong>.',
            'gear' => 'Verfügbar sind nur <strong>Helm, Jacke mit Rückenprotektor, Hose, Handschuhe, Sturmhaube und Stiefel</strong>: Die Fahrerausrüstung ist im Preis inbegriffen, Motorradstiefel gegen Aufpreis. Helme in den Größen <strong>S–3XL</strong>, Jacken, Hosen und Handschuhe bis Größe <strong>4XL</strong> (größere Größen bis 6XL gibt es in Mezná). <strong>Regenkombis</strong> und weitere Zusatzausrüstung verleihen wir in der Selbstbedienungsfiliale nicht – die gibt es nur in der Filiale mit Personal in Mezná. Die Ausrüstung probierst du in der Umkleide an; passt die Größe nicht, nimmst du eine andere verfügbare und markierst sie einfach im Übergabeprotokoll. Warnweste, Verbandskasten, Unfallbericht, Bremsscheibenschloss und den Schlüssel für die Handyhalterung findest du am Motorrad.',
            'steps_title' => 'So läuft es ab',
            'steps' => '1. Du reservierst und bezahlst online, wählst die Abholzeit und lädst deine Dokumente hoch (Ausweis/Reisepass + Führerschein) – in der Selbstbedienungsfiliale ist das zwingend: Ohne verifizierte Dokumente bekommst du keine Codes und kommst nicht in die Filiale. Nach der Prüfung der Dokumente erhältst du in der App, per E-Mail und SMS die Codes in der Reihenfolge, in der du sie eingibst: <strong>1) Code der Schlüsselbox mit dem Torschlüssel, 2) Code der Umkleide</strong> (wenn du Ausrüstung leihst) <strong>und 3) Code des Motorrads</strong>.<br>2. <strong>Ist das Einfahrtstor geschlossen</strong>, öffnest du mit dem Code aus der App die <strong>obere Schlüsselbox am rechten Torpfosten</strong>: Darin liegt der Schlüssel für das Vorhängeschloss. Schließ das Tor auf, fahr hinein und park auf einem der Stellplätze <strong>1–7 rechts am Zaun</strong> (siehe Foto vom Parkplatz). Dein Auto kann hier während der gesamten Miete kostenlos stehen. Ist das Tor offen, brauchst du den Code der Schlüsselbox nicht.<br>3. Am Display gibst du den Code der Umkleide ein: <strong>Die Umkleide ist Tür Nr. 8</strong>. Du nimmst die Ausrüstung, ziehst dich um und schließt die Tür der Umkleide (mit eigener Ausrüstung überspringst du die Umkleide). Hast du den Rabatt für die Abholung ab 12:00 Uhr, gelten die Codes erst ab 12:00 Uhr.<br>4. Am Display passt du im Übergabeprotokoll die Größen an, unterschreibst das Protokoll und gibst den Code des Motorrads ein: Die Box mit deinem Motorrad öffnet sich. Box schließen und los geht\'s!<br>5. <strong>War das Tor geschlossen, schließ es nach der Abfahrt wieder, sperr es mit dem Vorhängeschloss ab, leg den Schlüssel zurück in die obere Schlüsselbox und verstell die Zahlenräder.</strong> Ein offenes Tor lässt du offen: Ändere nie den Zustand des Tors.<br>6. Nach der Fahrt bringst du das Motorrad zurück in seine Box und die Ausrüstung in die Umkleide – jederzeit am letzten Miettag bis 24:00 Uhr. Ist das Tor geschlossen, gehst du genauso vor: Du schließt es mit dem Schlüssel aus der Schlüsselbox auf, nach der Abfahrt wieder ab und legst den Schlüssel zurück.',
            'video_title' => 'Video: So nutzt du die Selbstbedienungsfiliale',
            'gallery_title' => 'Fotogalerie der Filiale',
            'seo_title' => 'Selbstbedienungsfiliale Velké Němčice bei Brno | MotoGo24',
            'seo_description' => 'Selbstbedienungsfiliale der Motorradvermietung MotoGo24 in Velké Němčice bei Brno: Übernahme und Rückgabe 24/7 per Code aus der App, Abholzeit wählst du bei der Reservierung (ab 12:00 Uhr kostet der 1. Tag die Hälfte), kostenloses Parken.',
        ],
    ],
    'detail_button' => 'Zur Filiale',
    'back_link' => '← Alle Filialen',
    'cta' => [
        'title' => 'Wähle dein Motorrad in deiner Filiale',
        'text' => 'Bei der Reservierung wählst du die Filiale und siehst nur die Motorräder, die dort stehen.',
        'button' => 'ONLINE RESERVIEREN',
    ],
]]];
