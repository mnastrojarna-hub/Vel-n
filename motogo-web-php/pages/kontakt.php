<?php
// ===== MotoGo24 Web PHP — Kontakt =====
// Odpovídá pages-kontakt.js

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'Kontakt']);

$quickContact = '<section><div class="contact-quick-boxes">' .
    '<div class="contact-quick-box dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/telefon.svg" alt="Telefon" class="icon-small" loading="lazy"></div><div>' .
    '<p><small>ZAVOLEJTE NÁM</small><br><strong><a href="' . PHONE_LINK . '">' . PHONE . '</a></strong></p></div></div>' .
    '<div class="contact-quick-box dfc"><div class="img-icon dfcc"><img src="' . BASE_URL . '/gfx/email.svg" alt="E-mail" class="icon-small" loading="lazy"></div><div>' .
    '<p><small>NAPIŠTE NÁM</small><br><strong>' . EMAIL_USER . '@' . EMAIL_DOMAIN . '</strong></p></div></div>' .
    '<div class="contact-quick-box dfc"><div><p><small>DATOVÁ SCHRÁNKA</small><br><strong>iuw3vnb</strong></p></div></div>' .
    '</div></section>';

$infoSection = '<div class="gr2 contact-info"><section>' .
    '<h2>Provozovna</h2>' .
    '<p><strong>Adresa:</strong><br>' . ADDRESS . '</p><p>&nbsp;</p>' .
    '<p><strong>Provozní doba:</strong><br>PO – NE: 00:00 – 24:00 (nonstop)<br>Včetně víkendů a svátků</p><p>&nbsp;</p>' .
    '<h2>Fakturační údaje</h2>' .
    '<p><strong>' . COMPANY_NAME . '</strong><br>' . COMPANY_ADDRESS . '</p><p>&nbsp;</p>' .
    '<p>IČO: ' . COMPANY_ICO . '<br>Nejsem plátce DPH</p><p>&nbsp;</p>' .
    '<p>Společnost byla zapsána dne 31. 7. 2024 u Městského úřadu v Pelhřimově.</p>' .
    '</section><div>' .
    '<section><h2>Sledujte nás</h2>' .
    '<p class="dfc"><span class="social-icon"><img alt="Facebook" src="' . BASE_URL . '/gfx/facebook.svg"></span>&nbsp;<a href="' . FB_URL . '">facebook</a></p><p>&nbsp;</p>' .
    '<p class="dfc"><span class="social-icon"><img alt="Instagram" src="' . BASE_URL . '/gfx/instagram.svg"></span>&nbsp;<a href="' . IG_URL . '">instagram</a></p></section>' .
    '<section class="cta-green-box"><h2>Chcete si domluvit rezervaci?</h2>' .
    '<p>Rezervujte si motorku online během pár minut a vyražte za dobrodružstvím.</p><p>&nbsp;</p>' .
    '<p><a class="btn btndark" href="' . BASE_URL . '/rezervace">REZERVOVAT ONLINE</a></p></section>' .
    '</div></div>';

$mapSection = '<section>' .
    '<h2>Kde nás najdete</h2>' .
    '<p><iframe aria-label="Mapa kde nás najdete" class="map" loading="lazy" src="https://frame.mapy.cz/s/?x=15.15413&y=49.35169&z=14&source=coor&id=15.15413%2C49.35169"></iframe></p></section>';

$seoText = '<h2>Kontakty – půjčovna motorek Vysočina (Pelhřimov)</h2>' .
    '<p>Motogo24 je&nbsp;<strong>moderní půjčovna motorek na Vysočině</strong>. Sídlíme v&nbsp;<strong>Pelhřimově</strong>, jsme otevřeni&nbsp;<strong>nonstop</strong>&nbsp;a půjčujeme&nbsp;<strong>bez kauce</strong>, s kompletní&nbsp;<strong>výbavou v ceně</strong>.</p>';

$content = '<main id="content"><div class="container contact">' . $bc .
    '<div class="ccontent contacts">' .
    '<h1>Kontakty půjčovna motorek Motogo24</h1>' .
    '<p>Máte dotaz k <strong>půjčení motorky</strong>, chcete si objednat <strong>dárkový poukaz</strong>, poradit s výběrem nebo si rovnou <strong>domluvit rezervaci</strong>? Jsme tu pro vás každý den, <strong>nonstop</strong>.</p><p>&nbsp;</p>' .
    $quickContact . $infoSection . $mapSection . $seoText .
    '</div></div></main>';

renderPage('Kontakt | MotoGo24 – půjčovna motorek Vysočina', $content, '/kontakt', [
    'description' => 'Kontakty na půjčovnu motorek Motogo24 v Pelhřimově. Telefon +420 774 256 271, e-mail info@motogo24.cz. Nonstop provoz, adresa Mezná 9.',
    'keywords' => 'kontakt Motogo24, půjčovna motorek Pelhřimov, telefon, adresa, provozní doba, nonstop',
]);
