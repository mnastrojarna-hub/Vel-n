<?php
// ===== MotoGo24 Web PHP — Kontakt (CMS-driven s fallback na config.php) =====

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Kontakt | MotoGo24 – půjčovna motorek Vysočina',
        'description' => 'Kontakty na půjčovnu motorek Motogo24 v Pelhřimově. Telefon ' . PHONE . ', e-mail ' . EMAIL_FULL . '. Nonstop provoz, adresa ' . ADDRESS . '.',
        'keywords' => 'kontakt Motogo24, půjčovna motorek Pelhřimov, telefon, adresa, provozní doba, nonstop',
    ],
    'h1' => 'Kontakty půjčovna motorek Motogo24',
    'intro' => 'Máte dotaz k <strong>půjčení motorky</strong>, chcete si objednat <strong>dárkový poukaz</strong>, poradit s výběrem nebo si rovnou <strong>domluvit rezervaci</strong>? Jsme tu pro vás každý den, <strong>nonstop</strong>.',
    'quick' => [
        ['label' => 'ZAVOLEJTE NÁM', 'value' => PHONE, 'href' => PHONE_LINK, 'icon' => 'gfx/telefon.svg', 'alt' => 'Telefon'],
        ['label' => 'NAPIŠTE NÁM', 'value' => EMAIL_FULL, 'href' => 'mailto:' . EMAIL_FULL, 'icon' => 'gfx/email.svg', 'alt' => 'E-mail'],
        ['label' => 'DATOVÁ SCHRÁNKA', 'value' => 'iuw3vnb', 'href' => null, 'icon' => null, 'alt' => null],
    ],
    'place' => [
        'title' => 'Provozovna',
        'address_label' => 'Adresa:',
        'address' => ADDRESS,
        'hours_label' => 'Provozní doba:',
        'hours' => 'PO – NE: 00:00 – 24:00 (nonstop)<br>Včetně víkendů a svátků',
        'billing_title' => 'Fakturační údaje',
        'billing_name' => COMPANY_NAME,
        'billing_address' => COMPANY_ADDRESS,
        'billing_ico' => COMPANY_ICO,
        'billing_vat' => 'Nejsem plátce DPH',
        'billing_note' => 'Společnost byla zapsána dne 31. 7. 2024 u Městského úřadu v Pelhřimově.',
    ],
    'social_title' => 'Sledujte nás',
    'social' => [
        ['label' => 'facebook', 'href' => FB_URL, 'icon' => 'gfx/facebook.svg', 'alt' => 'Facebook'],
        ['label' => 'instagram', 'href' => IG_URL, 'icon' => 'gfx/instagram.svg', 'alt' => 'Instagram'],
    ],
    'side_cta' => [
        'title' => 'Chcete si domluvit rezervaci?',
        'text' => 'Rezervujte si motorku online během pár minut a vyražte za dobrodružstvím.',
        'button' => ['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace', 'cls' => 'btndark'],
    ],
    'map' => [
        'title' => 'Kde nás najdete',
        'src' => 'https://www.google.com/maps?q=Mezn%C3%A1+9%2C+393+01+Pelh%C5%99imov&hl=cs&z=15&output=embed',
    ],
    'seo_text' => [
        'title' => 'Kontakty – půjčovna motorek Vysočina (Pelhřimov)',
        'body' => 'Motogo24 je <strong>moderní půjčovna motorek na Vysočině</strong>. Sídlíme v <strong>Pelhřimově</strong>, jsme otevřeni <strong>nonstop</strong> a půjčujeme <strong>bez kauce</strong>, s kompletní <strong>výbavou v ceně</strong>.',
    ],
];

$C = $sb->siteContent('kontakt', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('breadcrumb.contact')]);

$quickHtml = '<section><div class="contact-quick-boxes">';
foreach ($C['quick'] as $i => $q) {
    $kBase = 'web.kontakt.quick.' . $i;
    $iconHtml = '';
    if (!empty($q['icon'])) {
        $iconSrc = BASE_URL . '/' . ltrim($q['icon'], '/');
        $iconHtml = '<div class="img-icon dfcc"><img src="' . htmlspecialchars($iconSrc) . '" alt="' . htmlspecialchars($q['alt'] ?? '') . '" class="icon-small" loading="lazy"></div>';
    }
    $val = $q['value'];
    if (!empty($q['href'])) {
        $val = '<a href="' . htmlspecialchars($q['href']) . '" data-cms-key="' . $kBase . '.value">' . htmlspecialchars($q['value']) . '</a>';
    } else {
        $val = '<span data-cms-key="' . $kBase . '.value">' . htmlspecialchars($q['value']) . '</span>';
    }
    $quickHtml .= '<div class="contact-quick-box dfc">' . $iconHtml .
        '<div><p><small data-cms-key="' . $kBase . '.label">' . htmlspecialchars($q['label']) . '</small><br><strong>' . $val . '</strong></p></div></div>';
}
$quickHtml .= '</div></section>';

$p = $C['place'];
$sideCta = $C['side_cta'];
$infoSection = '<div class="gr2 contact-info"><section>' .
    '<h2 data-cms-key="web.kontakt.place.title">' . htmlspecialchars($p['title']) . '</h2>' .
    '<p><strong data-cms-key="web.kontakt.place.address_label">' . htmlspecialchars($p['address_label']) . '</strong><br><span data-cms-key="web.kontakt.place.address">' . $p['address'] . '</span></p><p>&nbsp;</p>' .
    '<p><strong data-cms-key="web.kontakt.place.hours_label">' . htmlspecialchars($p['hours_label']) . '</strong><br><span data-cms-key="web.kontakt.place.hours">' . $p['hours'] . '</span></p><p>&nbsp;</p>' .
    '<h2 data-cms-key="web.kontakt.place.billing_title">' . htmlspecialchars($p['billing_title']) . '</h2>' .
    '<p><strong data-cms-key="web.kontakt.place.billing_name">' . htmlspecialchars($p['billing_name']) . '</strong><br><span data-cms-key="web.kontakt.place.billing_address">' . htmlspecialchars($p['billing_address']) . '</span></p><p>&nbsp;</p>' .
    '<p>IČO: <span data-cms-key="web.kontakt.place.billing_ico">' . htmlspecialchars($p['billing_ico']) . '</span><br><span data-cms-key="web.kontakt.place.billing_vat">' . htmlspecialchars($p['billing_vat']) . '</span></p><p>&nbsp;</p>' .
    '<p data-cms-key="web.kontakt.place.billing_note">' . htmlspecialchars($p['billing_note']) . '</p>' .
    '</section><div>';

$infoSection .= '<section><h2 data-cms-key="web.kontakt.social_title">' . htmlspecialchars($C['social_title']) . '</h2>';
foreach ($C['social'] as $i => $s) {
    $iconSrc = BASE_URL . '/' . ltrim($s['icon'], '/');
    $infoSection .= '<p class="dfc"><span class="social-icon"><img alt="' . htmlspecialchars($s['alt']) . '" src="' . htmlspecialchars($iconSrc) . '"></span>&nbsp;<a href="' . htmlspecialchars($s['href']) . '" data-cms-key="web.kontakt.social.' . $i . '.label">' . htmlspecialchars($s['label']) . '</a></p><p>&nbsp;</p>';
}
$infoSection .= '</section>';

$btn = $sideCta['button'];
$infoSection .= '<section class="cta-green-box"><h2 data-cms-key="web.kontakt.side_cta.title">' . htmlspecialchars($sideCta['title']) . '</h2>' .
    '<p data-cms-key="web.kontakt.side_cta.text">' . $sideCta['text'] . '</p><p>&nbsp;</p>' .
    '<p><a class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . $btn['href'] . '" data-cms-key="web.kontakt.side_cta.button.label">' . htmlspecialchars($btn['label']) . '</a></p></section>' .
    '</div></div>';

$mapSrc = $C['map']['src'] ?? '';
if (stripos($mapSrc, 'mapy.cz') !== false || $mapSrc === '') {
    $mapSrc = 'https://www.google.com/maps?q=Mezn%C3%A1+9%2C+393+01+Pelh%C5%99imov&hl=cs&z=15&output=embed';
}
$mapSection = '<section>' .
    '<h2 data-cms-key="web.kontakt.map.title">' . htmlspecialchars($C['map']['title']) . '</h2>' .
    '<p><iframe aria-label="Mapa kde nás najdete" class="map" loading="lazy" referrerpolicy="no-referrer-when-downgrade" allowfullscreen src="' . htmlspecialchars($mapSrc) . '"></iframe></p></section>';

$seoText = '<h2 data-cms-key="web.kontakt.seo_text.title">' . htmlspecialchars($C['seo_text']['title']) . '</h2><p data-cms-key="web.kontakt.seo_text.body">' . $C['seo_text']['body'] . '</p>';

$content = '<main id="content"><div class="container contact">' . $bc .
    '<div class="ccontent contacts">' .
    '<h1 data-cms-key="web.kontakt.h1">' . htmlspecialchars($C['h1']) . '</h1>' .
    '<p data-cms-key="web.kontakt.intro">' . $C['intro'] . '</p><p>&nbsp;</p>' .
    $quickHtml . $infoSection . $mapSection . $seoText .
    '</div></div></main>';

// ===== Per-branch LocalBusiness JSON-LD =====
// Pro každou aktivní pobočku z DB vystavíme samostatný AutomotiveBusiness záznam
// s adresou, GPS, otevírací dobou a vazbou na hlavní Organization. AI agenti tak
// vědí, kde přesně si zákazník motorku vyzvedne (multi-branch routing).
$branches = $sb->fetchBranches();
$branchSchemas = [];
if (is_array($branches)) {
    foreach ($branches as $br) {
        if (empty($br['id']) || empty($br['name'])) continue;
        $brName = (string)$br['name'];
        $brAddr = (string)($br['address'] ?? '');
        $brCity = (string)($br['city'] ?? '');
        $brZip  = (string)($br['zip'] ?? '');
        $brPhone= (string)($br['phone'] ?? PHONE);
        $brEmail= (string)($br['email'] ?? EMAIL_FULL);
        $brLat  = isset($br['latitude'])  ? (float)$br['latitude']  : null;
        $brLng  = isset($br['longitude']) ? (float)$br['longitude'] : null;
        $isOpen = !empty($br['is_open']);
        $brType = (string)($br['type'] ?? '');
        $brNotes = trim((string)localized($br, 'notes'));

        $hours = $isOpen
            ? '"openingHoursSpecification":{"@type":"OpeningHoursSpecification","dayOfWeek":["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"],"opens":"00:00","closes":"23:59"}'
            : '"openingHoursSpecification":{"@type":"OpeningHoursSpecification","dayOfWeek":["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"],"opens":"08:00","closes":"20:00"}';

        $geo = ($brLat !== null && $brLng !== null)
            ? ',"geo":{"@type":"GeoCoordinates","latitude":' . $brLat . ',"longitude":' . $brLng . '}'
            : '';

        $branchSchemas[] = '{"@type":["LocalBusiness","AutomotiveBusiness"]'
            . ',"@id":"https://motogo24.cz/kontakt#branch-' . htmlspecialchars($br['id']) . '"'
            . ',"name":' . json_encode('MotoGo24 — ' . $brName, JSON_UNESCAPED_UNICODE)
            . ',"branchOf":{"@id":"https://motogo24.cz/#organization"}'
            . ',"parentOrganization":{"@id":"https://motogo24.cz/#organization"}'
            . ',"telephone":' . json_encode($brPhone)
            . ',"email":' . json_encode($brEmail)
            . ',"url":"https://motogo24.cz/kontakt"'
            . ',"address":{"@type":"PostalAddress","streetAddress":' . json_encode($brAddr, JSON_UNESCAPED_UNICODE)
                . ',"addressLocality":' . json_encode($brCity, JSON_UNESCAPED_UNICODE)
                . ',"postalCode":' . json_encode($brZip)
                . ',"addressCountry":"CZ"}'
            . $geo
            . ',' . $hours
            . ($brType !== '' ? ',"description":' . json_encode($brType . ($brNotes !== '' ? ' — ' . $brNotes : ''), JSON_UNESCAPED_UNICODE) : ($brNotes !== '' ? ',"description":' . json_encode($brNotes, JSON_UNESCAPED_UNICODE) : ''))
            . ',"priceRange":"990 – 5000 Kč/den"'
            . '}';
    }
}

$branchesSchema = '';
if (!empty($branchSchemas)) {
    $branchesSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@graph":[' . implode(',', $branchSchemas) . ']}
  </script>';
}

renderPage($C['seo']['title'], $content, '/kontakt', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'schema' => $branchesSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => t('breadcrumb.contact'), 'url' => 'https://motogo24.cz/kontakt'],
    ],
]);
