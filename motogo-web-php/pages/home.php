<?php
// ===== MotoGo24 Web PHP — Homepage =====

echo renderHead('Půjčovna motorek Vysočina Motogo24', 'Půjčovna motorek Vysočina – silniční, sportovní, enduro i dětské. Nonstop pronájem bez kauce, online rezervace a motorkářská výbava zdarma.');
echo renderHeader();

// Banner
echo '<div class="banner">' .
  '<img fetchpriority="high" alt="Půjčovna motorek Vysočina" src="gfx/hero-banner.png">' .
  '<div class="banner-wrapper"><div class="container"><div class="banner-caption">' .
    '<p><strong>Půjčovna motorek</strong> na Vysočině</p><p>&nbsp;</p>' .
    '<p>Půjč si motorku na Vysočině snadno online.<br>Vyber si z <strong>cestovních, sportovních i enduro</strong> modelů.<br>Rezervace s <strong>platbou kartou</strong> a <strong>rychlým převzetím</strong>.</p><p>&nbsp;</p>' .
    '<p><a class="btn btngreen" href="/katalog">VYBER SI MOTORKU</a> <a class="btn btndark" href="/jak-pujcit">JAK TO FUNGUJE</a></p>' .
  '</div></div></div></div>';

echo '<main id="content"><div class="container">';
echo '<h1>Půjčovna motorek Vysočina Motogo24 – bez kauce a nonstop</h1>';

// Signpost (6 cards)
$signposts = [
  ['icon'=>'gfx/ico-katalog.svg', 'title'=>'<strong>Katalog</strong> motorek', 'text'=>'Prohlédněte si naši nabídku <strong>motorek na pronájem</strong> – od sportovních po cestovní modely.', 'btn'=>'KATALOG MOTOREK', 'href'=>'/katalog'],
  ['icon'=>'gfx/ico-jak.svg', 'title'=>'<strong>Jak si půjčit</strong> motorku', 'text'=>'Jednoduchý proces: vyberte <strong>motorku k zapůjčení</strong>, rezervujte, vyjeďte.', 'btn'=>'JAK SI PŮJČIT MOTORKU', 'href'=>'/jak-pujcit'],
  ['icon'=>'gfx/ico-rezervace.svg', 'title'=>'<strong>Online rezervace</strong> motorky', 'text'=>'Zarezervujte si <strong>motorku na pronájem</strong> přes snadný systém.', 'btn'=>'REZERVOVAT MOTORKU', 'href'=>'/rezervace'],
  ['icon'=>'gfx/ico-kontakt.svg', 'title'=>'<strong>Kontakty</strong> a mapa', 'text'=>'Navštivte naši <strong>půjčovnu motorek v Pelhřimově</strong> nebo nás kontaktujte.', 'btn'=>'KONTAKT', 'href'=>'/kontakt'],
  ['icon'=>'gfx/ico-faq.svg', 'title'=>'Často kladené <strong>dotazy</strong>', 'text'=>'Nejčastější dotazy k <strong>půjčení motorky</strong> přehledně.', 'btn'=>'ČASTÉ DOTAZY', 'href'=>'/jak-pujcit/faq'],
  ['icon'=>'gfx/ico-trasy.svg', 'title'=>'Motocyklové <strong>výlety</strong>', 'text'=>'Objevte nejlepší <strong>motocyklové trasy v Česku</strong> pro turisty.', 'btn'=>'MOTOCYKLOVÉ TRASY', 'href'=>'/blog'],
];
echo '<section aria-labelledby="signpost"><div class="gr3">';
foreach ($signposts as $s) {
  echo '<a class="gbox" href="' . $s['href'] . '">' .
    '<div class="gr2"><div class="gbox-img"><img src="' . $s['icon'] . '" class="icon" alt="' . $s['btn'] . '" loading="lazy"></div><div>' .
    '<h3><p>' . $s['title'] . '</p></h3><p>' . $s['text'] . '</p>' .
    '<div class="btn btngreen-small">' . $s['btn'] . '</div></div></div></a>';
}
echo '</div></section>';

// Featured motos
echo '<section aria-labelledby="catalogue"><h2>Naše motorky k pronájmu na Vysočině</h2>' .
  '<p>Prohlédněte si nabídku cestovních, sportovních a enduro z naší <strong>půjčovny motorek na Vysočině</strong>.</p><p>&nbsp;</p>';

$motos = $sb->fetchMotos();
if (!empty($motos)) {
    echo '<div class="gr4">';
    $shown = array_slice($motos, 0, 4);
    foreach ($shown as $m) {
        echo '<section aria-labelledby="catalogue">' . renderMotoCard($m) . '</section>';
    }
    echo '</div>';
} else {
    echo '<p>Momentálně nemáme žádné motorky v nabídce.</p>';
}

echo '<p>&nbsp;</p><p class="text-center"><a class="btn btngreen" href="/katalog">KATALOG MOTOREK</a></p></section>';

// Process steps
$steps = [
  ['icon'=>'gfx/ico-step1.svg', 'title'=>'1. Vyber', 'text'=>'Vyberte si svou ideální motorku z naší nabídky motorek na pronájem.'],
  ['icon'=>'gfx/ico-step2.svg', 'title'=>'2. Rezervuj', 'text'=>'Zarezervujte si půjčení motorky přes náš jednoduchý online systém.'],
  ['icon'=>'gfx/ico-step3.svg', 'title'=>'3. Převzetí', 'text'=>'Vyzvedněte si motorku v naší půjčovně motorek v Pelhřimově.'],
  ['icon'=>'gfx/ico-step4.svg', 'title'=>'4. Užij jízdu', 'text'=>'Užijte si svobodu a objevte Česko na motorkách k zapůjčení.'],
];
echo '<section aria-labelledby="process"><h2>Jak probíhá půjčení motorky na Vysočině</h2><div class="gr4">';
foreach ($steps as $s) {
    echo renderWbox($s['icon'], $s['title'], $s['text']);
}
echo '</div></section>';

// FAQ
$faqItems = [
  ['q'=>'Jak si mohu rezervovat motorku?', 'a'=>'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu. Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.'],
  ['q'=>'Můžu si motorku půjčit i bez předchozí rezervace?', 'a'=>'Bez rezervace to bohužel nejde. Každou motorku je nutné předem zamluvit – online, telefonicky, e-mailem nebo přes sociální sítě.'],
  ['q'=>'Musím složit kauci?', 'a'=>'Ne! U nás <strong>žádnou kauci platit nemusíš</strong>. Naše půjčovna se tímto zásadně liší od většiny konkurence.'],
  ['q'=>'Můžu odcestovat s motorkou do zahraničí?', 'a'=>'Ano, s motorkou můžeš bez problémů vyrazit i do zahraničí. Cesty mimo Česko neomezujeme, jen je potřeba dodržet územní platnost pojištění (zelená karta).'],
];
echo renderFaqSection('Často kladené otázky', $faqItems, '/jak-pujcit/faq');

// CTA
echo renderCta('Rezervuj svou motorku online',
  'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená <strong>nonstop</strong>. Stačí pár kliků a tvoje jízda začíná.',
  [
    ['label'=>'REZERVOVAT MOTORKU', 'href'=>'/rezervace', 'cls'=>'btndark pulse'],
    ['label'=>'Dárkový poukaz', 'href'=>'/poukazy', 'cls'=>'btndark'],
    ['label'=>'Tipy na trasy', 'href'=>'/blog', 'cls'=>'btndark'],
  ]);

// Blog
echo '<section aria-labelledby="blog"><h2>Blog a tipy</h2>';

$posts = $sb->fetchCmsPages();
if (!empty($posts)) {
    echo '<div class="gr3">';
    $shown = array_slice($posts, 0, 3);
    foreach ($shown as $p) {
        echo renderBlogCard($p);
    }
    echo '</div>';
} else {
    echo '<p>Zatím nemáme žádné články.</p>';
}

echo '<p>&nbsp;</p><p class="text-center"><a class="btn btngreen" href="/blog">ČÍST VÍCE V BLOGU</a></p></section>';

echo '</div></main>';

echo renderFooter();
echo renderPageEnd();
