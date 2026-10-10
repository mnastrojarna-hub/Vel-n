<?php
// NL překlad textů poboček (nizozemština, tykání „je/jij“; Velín → Texty webu → Pobočky, klíče
// web.pobocky.*; aktuální CS hodnoty z CMS k 2026-10-10, u výbavy Velkých Němčic už nové velikosti
// z data/pobocky.php — helmy S–3XL, bundy/kalhoty/rukavice do 4XL). Struktura = lang/v2/es/pobocky.php
// (= pobockyDefaults() bez polí jen z kódu: slug, branch_id, map, photo, gallery, video).
// siteContent('pobocky') použije tento overlay, protože CMS klíče bez NL překladu se pro NL přeskakují.
// Texty v2 (karty, průvodce, srovnání): lang/v2/nl/pobocky-v2.php.

return ['pages' => ['pobocky' => [
    'seo' => [
        'title' => 'Vestigingen | MotoGo24 – motorverhuur in Pelhřimov en Brno',
        'description' => 'Vestigingen van motorverhuur MotoGo24: bemande vestiging in Mezná bij Pelhřimov (Vysočina) en zelfbedieningsvestiging in Velké Němčice bij Brno – motor ophalen op elk moment.',
        'keywords' => 'vestigingen MotoGo24, motorverhuur Pelhřimov, motorverhuur Brno, motorverhuur zelfbediening, Velké Němčice, Mezná',
    ],
    'h1' => 'Vestigingen van MotoGo24',
    'intro' => 'Je kunt je motor op <strong>twee plekken</strong> ophalen: bij de <strong>bemande vestiging in Mezná bij Pelhřimov</strong>, waar we je persoonlijk ontvangen, of bij de <strong>zelfbedieningsvestiging in Velké Němčice bij Brno</strong>, waar je de motor en de uitrusting zelf ophaalt met codes.',
    'branches' => [
        [
            'badge' => 'Bemande vestiging',
            'title' => 'Mezná bij Pelhřimov',
            'address' => 'Mezná 9, 393 01 Pelhřimov',
            'hours' => 'Maandag t/m zondag, op elk moment (nonstop), ook in het weekend en op feestdagen. Het tijdstip van ophalen en inleveren kies je in de reservering.',
            'text' => 'Onze hoofdvestiging in Vysočina. We <strong>overhandigen je de motor persoonlijk</strong>: we leggen alles uit, helpen je met het afstellen en het kiezen van je uitrusting en lopen samen het overdrachtsprotocol door. De rijuitrusting is bij de prijs inbegrepen. Vanaf hier bieden we ook <strong>bezorging van de motor</strong> op een adres naar keuze.',
            'gear' => 'Rijuitrusting bij de prijs inbegrepen: jassen en broeken in maten tot <strong>6XL</strong>. Alleen hier kun je ook <strong>regenkleding</strong> en andere extra uitrusting huren.',
            'steps_title' => 'Zo werkt het',
            'steps' => '1. Je reserveert en betaalt online (website of app) en uploadt je documenten (ID-kaart/paspoort + rijbewijs); dat vragen we ook bij de bemande vestiging: upload je ze niet, dan controleren we ze ter plaatse bij het ophalen.<br>2. Op het gekozen tijdstip kom je naar de vestiging, waar we op je wachten.<br>3. We overhandigen je de motor en de uitrusting en ondertekenen het overdrachtsprotocol.<br>4. Na je rit lever je de motor in bij de vestiging (of we halen hem op het afgesproken adres op).',
            'video_title' => 'Video: zo werkt het bij de vestiging',
            'gallery_title' => 'Fotogalerij van de vestiging',
            'seo_title' => 'Vestiging Mezná bij Pelhřimov | MotoGo24 – bemande motorverhuur',
            'seo_description' => 'Bemande vestiging van motorverhuur MotoGo24 in Mezná bij Pelhřimov (Vysočina): persoonlijke overdracht van de motor op elk moment, uitrusting inbegrepen, bezorging op je adres.',
        ],
        [
            'badge' => 'Zelfbedieningsvestiging',
            'title' => 'Velké Němčice bij Brno',
            'address' => 'Boudky, 691 63 Velké Němčice',
            'hours' => 'Open 24/7 met de code uit de app. Het ophaaltijdstip kies je in de reservering: haal je op vanaf 12:00 (huur van 2 dagen of langer), dan betaal je de 1e dag maar de helft en geeft de kiosk je de motor pas vanaf 12:00 mee. Het inlevertijdstip kies je niet: je levert de motor in wanneer je wilt op de laatste huurdag, tot 24:00.',
            'text' => 'Moderne <strong>zelfbedieningsvestiging</strong> ten zuiden van Brno. Er is geen personeel: je regelt alles zelf op het touchscreen met de <strong>codes uit de app</strong>, die je krijgt na betaling en het aanvullen van je documenten. Motoren van deze vestiging worden alleen bij de vestiging zelf opgehaald en ingeleverd: bezorging of ophalen op een adres bieden we hier niet aan. Bij de vestiging kun je de hele huurperiode <strong>gratis parkeren</strong>.',
            'gear' => 'Er zijn alleen <strong>helm, jas met rugprotector, broek, handschoenen, bivakmuts en laarzen</strong> beschikbaar: de rijuitrusting is bij de prijs inbegrepen, motorlaarzen tegen meerprijs. Helmen in maten <strong>S–3XL</strong>; jassen, broeken en handschoenen tot maat <strong>4XL</strong> (grotere maten, tot 6XL, hebben we in Mezná). <strong>Regenkleding</strong> en andere extra uitrusting verhuren we niet bij de zelfbedieningsvestiging: die zijn er alleen bij de bemande vestiging in Mezná. De uitrusting pas je in de kleedkamer; zit een maat niet goed, neem dan een andere beschikbare maat en geef dat gewoon aan in het overdrachtsprotocol. Het veiligheidshesje, de EHBO-set, het ongevalsformulier, het schijfremslot en het sleuteltje van de telefoonhouder vind je in de motor.',
            'steps_title' => 'Zo werkt het',
            'steps' => '1. Je reserveert en betaalt online, kiest het ophaaltijdstip en uploadt je documenten (ID-kaart/paspoort + rijbewijs): bij de zelfbedieningsvestiging is dat noodzakelijk; zonder geverifieerde documenten krijg je geen codes en kom je de vestiging niet in. Na verificatie van je documenten ontvang je in de app, per e-mail en per sms de codes in de volgorde waarin je ze invoert: <strong>1) code van het kastje met de poortsleutel, 2) code van de kleedkamer</strong> (als je uitrusting huurt) <strong>en 3) code van de motor</strong>.<br>2. <strong>Is de toegangspoort gesloten</strong>, open dan met de code uit de app het <strong>bovenste kastje aan de rechterpaal van de poort</strong>: daarin zit de sleutel van het hangslot. Open de poort, rijd naar binnen en parkeer op een van de plekken <strong>1–7, rechts langs het hek</strong> (zie de foto van de parkeerplaats). Je auto mag hier de hele huurperiode gratis staan. Staat de poort open, dan heb je de code van het kastje niet nodig.<br>3. Op het scherm voer je de code van de kleedkamer in: <strong>de kleedkamer is deur nr. 8</strong>. Je pakt de uitrusting, kleedt je om en sluit de deur van de kleedkamer (met je eigen uitrusting sla je de kleedkamer over). Heb je de korting voor ophalen vanaf 12:00, dan zijn de codes pas vanaf 12:00 geldig.<br>4. Op het scherm pas je in het overdrachtsprotocol de maten aan, onderteken je het en voer je de code van de motor in: de box met je motor gaat open. Je sluit de box en je bent weg!<br>5. <strong>Was de poort gesloten, sluit hem dan na vertrek weer, doe het hangslot erop, leg de sleutel terug in het bovenste kastje en verdraai de cijferwieltjes.</strong> Staat de poort open, laat hem dan open: verander nooit de toestand van de poort.<br>6. Na je rit zet je de motor terug in zijn box en de uitrusting in de kleedkamer, wanneer je wilt op de laatste huurdag, tot 24:00. Is de poort gesloten, dan doe je hetzelfde: je opent hem met de sleutel uit het kastje en sluit hem na vertrek weer af met het hangslot en legt de sleutel terug.',
            'video_title' => 'Video: zo gebruik je de zelfbedieningsvestiging',
            'gallery_title' => 'Fotogalerij van de vestiging',
            'seo_title' => 'Zelfbedieningsvestiging Velké Němčice bij Brno | MotoGo24',
            'seo_description' => 'Zelfbedieningsvestiging van motorverhuur MotoGo24 in Velké Němčice bij Brno: ophalen en inleveren 24/7 met de code uit de app, ophaaltijdstip kies je in de reservering (vanaf 12:00 betaal je de 1e dag maar de helft), gratis parkeren.',
        ],
    ],
    'detail_button' => 'Bekijk vestiging',
    'back_link' => '← Alle vestigingen',
    'cta' => [
        'title' => 'Kies je motor bij jouw vestiging',
        'text' => 'In de reservering kies je de vestiging en zie je alleen de motoren die daar staan.',
        'button' => 'ONLINE RESERVEREN',
    ],
]]];
