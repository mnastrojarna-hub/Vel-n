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
        'src' => 'https://frame.mapy.cz/s/?x=15.15413&y=49.35169&z=14&source=coor&id=15.15413%2C49.35169',
    ],
    'seo_text' => [
        'title' => 'Kontakty – půjčovna motorek Vysočina (Pelhřimov)',
        'body' => 'Motogo24 je <strong>moderní půjčovna motorek na Vysočině</strong>. Sídlíme v <strong>Pelhřimově</strong>, jsme otevřeni <strong>nonstop</strong> a půjčujeme <strong>bez kauce</strong>, s kompletní <strong>výbavou v ceně</strong>.',
    ],
];

$C = $sb->siteContent('kontakt', $defaults);

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'Kontakt']);

$quickHtml = '<section><div class="contact-quick-boxes">';
foreach ($C['quick'] as $q) {
    $iconHtml = '';
    if (!empty($q['icon'])) {
        $iconSrc = BASE_URL . '/' . ltrim($q['icon'], '/');
        $iconHtml = '<div class="img-icon dfcc"><img src="' . htmlspecialchars($iconSrc) . '" alt="' . htmlspecialchars($q['alt'] ?? '') . '" class="icon-small" loading="lazy"></div>';
    }
    $val = $q['value'];
    if (!empty($q['href'])) {
        $val = '<a href="' . htmlspecialchars($q['href']) . '">' . htmlspecialchars($q['value']) . '</a>';
    } else {
        $val = htmlspecialchars($q['value']);
    }
    $quickHtml .= '<div class="contact-quick-box dfc">' . $iconHtml .
        '<div><p><small>' . htmlspecialchars($q['label']) . '</small><br><strong>' . $val . '</strong></p></div></div>';
}
$quickHtml .= '</div></section>';

$p = $C['place'];
$sideCta = $C['side_cta'];
$infoSection = '<div class="gr2 contact-info"><section>' .
    '<h2>' . htmlspecialchars($p['title']) . '</h2>' .
    '<p><strong>' . htmlspecialchars($p['address_label']) . '</strong><br>' . $p['address'] . '</p><p>&nbsp;</p>' .
    '<p><strong>' . htmlspecialchars($p['hours_label']) . '</strong><br>' . $p['hours'] . '</p><p>&nbsp;</p>' .
    '<h2>' . htmlspecialchars($p['billing_title']) . '</h2>' .
    '<p><strong>' . htmlspecialchars($p['billing_name']) . '</strong><br>' . htmlspecialchars($p['billing_address']) . '</p><p>&nbsp;</p>' .
    '<p>IČO: ' . htmlspecialchars($p['billing_ico']) . '<br>' . htmlspecialchars($p['billing_vat']) . '</p><p>&nbsp;</p>' .
    '<p>' . htmlspecialchars($p['billing_note']) . '</p>' .
    '</section><div>';

$infoSection .= '<section><h2>' . htmlspecialchars($C['social_title']) . '</h2>';
foreach ($C['social'] as $s) {
    $iconSrc = BASE_URL . '/' . ltrim($s['icon'], '/');
    $infoSection .= '<p class="dfc"><span class="social-icon"><img alt="' . htmlspecialchars($s['alt']) . '" src="' . htmlspecialchars($iconSrc) . '"></span>&nbsp;<a href="' . htmlspecialchars($s['href']) . '">' . htmlspecialchars($s['label']) . '</a></p><p>&nbsp;</p>';
}
$infoSection .= '</section>';

$btn = $sideCta['button'];
$infoSection .= '<section class="cta-green-box"><h2>' . htmlspecialchars($sideCta['title']) . '</h2>' .
    '<p>' . $sideCta['text'] . '</p><p>&nbsp;</p>' .
    '<p><a class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . $btn['href'] . '">' . htmlspecialchars($btn['label']) . '</a></p></section>' .
    '</div></div>';

$mapSection = '<section>' .
    '<h2>' . htmlspecialchars($C['map']['title']) . '</h2>' .
    '<p><iframe aria-label="Mapa kde nás najdete" class="map" loading="lazy" src="' . htmlspecialchars($C['map']['src']) . '"></iframe></p></section>';

$seoText = '<h2>' . htmlspecialchars($C['seo_text']['title']) . '</h2><p>' . $C['seo_text']['body'] . '</p>';

$content = '<main id="content"><div class="container contact">' . $bc .
    '<div class="ccontent contacts">' .
    '<h1>' . htmlspecialchars($C['h1']) . '</h1>' .
    '<p>' . $C['intro'] . '</p><p>&nbsp;</p>' .
    $quickHtml . $infoSection . $mapSection . $seoText .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/kontakt', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Kontakt', 'url' => 'https://motogo24.cz/kontakt'],
    ],
]);
