<?php
// ===== MotoGo24 Web PHP — Kontakt =====

echo renderHead('Kontakt – půjčovna motorek Motogo24', 'Kontaktujte půjčovnu motorek Motogo24 v Pelhřimově. Telefon, e-mail, adresa, mapa a sociální sítě.');
echo renderHeader();

$bc = renderBreadcrumb([['href'=>'/', 'label'=>'Domů'], 'Kontakt']);

$email = EMAIL_USER . '@' . EMAIL_DOMAIN;

// Quick contact boxes
$quickBoxes = '<div class="gr4">' .
    '<div class="wbox"><div class="wbox-img"><img src="gfx/telefon.svg" class="icon" alt="Telefon" loading="lazy"></div>' .
        '<h3><p>Zavolejte nám</p></h3>' .
        '<p><a href="' . PHONE_LINK . '">' . PHONE . '</a></p></div>' .
    '<div class="wbox"><div class="wbox-img"><img src="gfx/email.svg" class="icon" alt="E-mail" loading="lazy"></div>' .
        '<h3><p>Napište nám</p></h3>' .
        '<p><a href="mailto:' . $email . '">' . $email . '</a></p></div>' .
    '<div class="wbox"><div class="wbox-img"><img src="gfx/adresa.svg" class="icon" alt="Adresa" loading="lazy"></div>' .
        '<h3><p>Navštivte nás</p></h3>' .
        '<p>' . ADDRESS . '</p></div>' .
    '<div class="wbox"><div class="wbox-img"><img src="gfx/provozni-doba.svg" class="icon" alt="Provozní doba" loading="lazy"></div>' .
        '<h3><p>Provozní doba</p></h3>' .
        '<p><strong>PO – NE</strong> 00:00 – 24:00 (nonstop)</p></div>' .
'</div>';

// Info section
$info = '<section>' .
    '<h2>Informace o firmě</h2>' .
    '<p><strong>Bc. Petra Semorádová</strong></p>' .
    '<p>IČO: 21874263</p>' .
    '<p>Sídlo: ' . ADDRESS . '</p>' .
    '<p>&nbsp;</p>' .
    '<p>Kontaktní telefon: <a href="' . PHONE_LINK . '">' . PHONE . '</a></p>' .
    '<p>E-mail: <a href="mailto:' . $email . '">' . $email . '</a></p>' .
'</section>';

// Google Maps
$map = '<section>' .
    '<h2>Kde nás najdete</h2>' .
    '<div class="map-wrapper">' .
        '<iframe src="https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d2588.0!2d15.2256!3d49.4314!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!3m3!1m2!1s0x470d1a!2sMezn%C3%A1%209%2C%20393%2001%20Pelh%C5%99imov!5e0!3m2!1scs!2scz!4v1" ' .
            'width="100%" height="450" style="border:0;border-radius:12px" allowfullscreen loading="lazy" referrerpolicy="no-referrer-when-downgrade" title="Mapa – půjčovna motorek Motogo24"></iframe>' .
    '</div>' .
'</section>';

// Social links
$social = '<section>' .
    '<h2>Sledujte nás</h2>' .
    '<div class="gr2">' .
        '<div class="wbox"><div class="dfc">' .
            '<span class="footer-social-icon"><img alt="Facebook" src="gfx/facebook.svg"></span>&nbsp;' .
            '<a href="' . FB_URL . '" target="_blank" rel="noopener">Facebook</a>' .
        '</div></div>' .
        '<div class="wbox"><div class="dfc">' .
            '<span class="footer-social-icon"><img alt="Instagram" src="gfx/instagram.svg"></span>&nbsp;' .
            '<a href="' . IG_URL . '" target="_blank" rel="noopener">Instagram</a>' .
        '</div></div>' .
    '</div>' .
'</section>';

$cta = renderCta('Máte zájem o pronájem motorky?',
    'Neváhejte a <strong>zarezervujte si motorku online</strong>. Jsme tu pro vás <strong>nonstop</strong>.',
    [
        ['label'=>'REZERVOVAT MOTORKU', 'href'=>'/rezervace', 'cls'=>'btndark pulse'],
        ['label'=>'KATALOG MOTOREK', 'href'=>'/katalog', 'cls'=>'btndark'],
    ]);

echo '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>Kontakt – půjčovna motorek Motogo24</h1>' .
    $quickBoxes . $info . $map . $social . $cta .
    '</div></div></main>';

echo renderFooter();
echo renderPageEnd();
