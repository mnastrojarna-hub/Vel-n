<?php
// ===== MotoGo24 Web PHP — Homepage (CMS-driven) =====
// Kompletní obsah je editovatelný přes app_settings klíč 'site.home' (JSONB).
// Defaults níže jsou fallback, pokud v DB není nic.

$sb = new SupabaseClient();
$motos = $sb->fetchMotos();
$posts = $sb->fetchCmsPages();
$reviews = $sb->fetchPublicReviews(6);

$defaults = [
    'seo' => [
        'title' => 'Půjčovna motorek na Vysočině | MotoGo24',
        'description' => 'Půjčte si motorku na Vysočině. Bez kauce, výbava v ceně, nonstop provoz. Cestovní, sportovní, enduro i dětské motorky. Online rezervace.',
        'keywords' => 'půjčovna motorek Vysočina, pronájem motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna, motorky k pronájmu, online rezervace motorky',
        'og_image' => 'https://motogo24.cz/gfx/hero-banner.png',
    ],
    'hero' => [
        'image' => 'gfx/hero-banner.png',
        'alt' => 'Půjčovna motorek Vysočina',
        'eyebrow' => '<strong>Půjčovna motorek</strong> na Vysočině',
        'body' => 'Půjč si motorku na Vysočině snadno online.<br>Vyber si z <strong>cestovních, sportovních i enduro</strong> modelů.<br>Rezervace s <strong>platbou kartou</strong> a <strong>rychlým převzetím</strong>.',
        'cta_primary' => ['label' => 'VYBER SI MOTORKU', 'href' => '/katalog', 'cls' => 'btngreen'],
        'cta_secondary' => ['label' => 'JAK TO FUNGUJE', 'href' => '/jak-pujcit', 'cls' => 'btndark'],
    ],
    'h1' => 'Půjčovna motorek Vysočina Motogo24 – bez kauce a nonstop',
    'signposts' => [
        ['icon' => 'gfx/ico-katalog.svg', 'title' => '<strong>Katalog</strong> motorek', 'text' => 'Prohlédněte si naši nabídku <strong>motorek na pronájem</strong> – od sportovních po cestovní modely.', 'btn' => 'KATALOG MOTOREK', 'href' => '/katalog'],
        ['icon' => 'gfx/ico-jak.svg', 'title' => '<strong>Jak si půjčit</strong> motorku', 'text' => 'Jednoduchý proces: vyberte <strong>motorku k zapůjčení</strong>, rezervujte, vyjeďte.', 'btn' => 'JAK SI PŮJČIT MOTORKU', 'href' => '/jak-pujcit'],
        ['icon' => 'gfx/ico-rezervace.svg', 'title' => '<strong>Online rezervace</strong> motorky', 'text' => 'Zarezervujte si <strong>motorku na pronájem</strong> přes snadný systém.', 'btn' => 'REZERVOVAT MOTORKU', 'href' => '/rezervace'],
        ['icon' => 'gfx/ico-kontakt.svg', 'title' => '<strong>Kontakty</strong> a mapa', 'text' => 'Navštivte naši <strong>půjčovnu motorek v Pelhřimově</strong> nebo nás kontaktujte.', 'btn' => 'KONTAKT', 'href' => '/kontakt'],
        ['icon' => 'gfx/ico-faq.svg', 'title' => 'Často kladené <strong>dotazy</strong>', 'text' => 'Nejčastější dotazy k <strong>půjčení motorky</strong> přehledně.', 'btn' => 'ČASTÉ DOTAZY', 'href' => '/jak-pujcit/faq'],
        ['icon' => 'gfx/ico-trasy.svg', 'title' => 'Motocyklové <strong>výlety</strong>', 'text' => 'Objevte nejlepší <strong>motocyklové trasy v Česku</strong> pro turisty.', 'btn' => 'MOTOCYKLOVÉ TRASY', 'href' => '/blog'],
    ],
    'motos_section' => [
        'title' => 'Naše motorky k pronájmu na Vysočině',
        'intro' => 'Prohlédněte si nabídku cestovních, sportovních a enduro z naší <strong>půjčovny motorek na Vysočině</strong>.',
        'empty' => 'Momentálně nemáme žádné motorky v nabídce.',
        'cta_label' => 'KATALOG MOTOREK',
        'cta_href' => '/katalog',
        'limit' => 4,
    ],
    'process' => [
        'title' => 'Jak probíhá půjčení motorky na Vysočině',
        'steps' => [
            ['icon' => 'gfx/ico-step1.svg', 'title' => '1. Vyber', 'text' => 'Vyberte si svou ideální motorku z naší nabídky motorek na pronájem.'],
            ['icon' => 'gfx/ico-step2.svg', 'title' => '2. Rezervuj', 'text' => 'Zarezervujte si půjčení motorky přes náš jednoduchý online systém.'],
            ['icon' => 'gfx/ico-step3.svg', 'title' => '3. Převzetí', 'text' => 'Vyzvedněte si motorku v naší půjčovně motorek v Pelhřimově.'],
            ['icon' => 'gfx/ico-step4.svg', 'title' => '4. Užij jízdu', 'text' => 'Užijte si svobodu a objevte Česko na motorkách k zapůjčení.'],
        ],
    ],
    'faq' => [
        'title' => 'Často kladené otázky',
        'more_link' => '/jak-pujcit/faq',
        'items' => [
            ['q' => 'Jak si mohu rezervovat motorku?', 'a' => 'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu. Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.'],
            ['q' => 'Můžu si motorku půjčit i bez předchozí rezervace?', 'a' => 'Bez rezervace to bohužel nejde. Každou motorku je nutné předem zamluvit – online, telefonicky, e-mailem nebo přes sociální sítě.'],
            ['q' => 'Musím složit kauci?', 'a' => 'Ne! U nás <strong>žádnou kauci platit nemusíš</strong>. Naše půjčovna se tímto zásadně liší od většiny konkurence.'],
            ['q' => 'Můžu odcestovat s motorkou do zahraničí?', 'a' => 'Ano, s motorkou můžeš bez problémů vyrazit i do zahraničí. Cesty mimo Česko neomezujeme, jen je potřeba dodržet územní platnost pojištění (zelená karta).'],
        ],
    ],
    'cta' => [
        'title' => 'Rezervuj svou motorku online',
        'text' => 'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená <strong>nonstop</strong>. Stačí pár kliků a tvoje jízda začíná.',
        'buttons' => [
            ['label' => 'REZERVOVAT MOTORKU', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
            ['label' => 'Dárkový poukaz', 'href' => '/poukazy', 'cls' => 'btndark'],
            ['label' => 'Tipy na trasy', 'href' => '/blog', 'cls' => 'btndark'],
        ],
    ],
    'blog' => [
        'title' => 'Blog a tipy',
        'empty' => 'Zatím nemáme žádné články.',
        'cta_label' => 'ČÍST VÍCE V BLOGU',
        'cta_href' => '/blog',
        'limit' => 3,
    ],
    'reviews' => [
        'title' => 'Co o nás říkají zákazníci',
        'intro' => 'Reálné recenze od motorkářů, kteří si u nás půjčili. Děkujeme za každé hodnocení.',
    ],
];

$C = $sb->siteContent('home', $defaults);

// ---- Signpost
$signHtml = '<section aria-labelledby="signpost"><div class="gr3">';
foreach ($C['signposts'] as $s) {
    $iconSrc = BASE_URL . '/' . ltrim($s['icon'], '/');
    $signHtml .= '<a class="gbox" href="' . BASE_URL . $s['href'] . '">' .
        '<div class="gr2"><div class="gbox-img"><img src="' . htmlspecialchars($iconSrc) . '" class="icon" alt="' . htmlspecialchars(strip_tags($s['btn'])) . '" loading="lazy"></div><div>' .
        '<h3><p>' . $s['title'] . '</p></h3><p>' . $s['text'] . '</p>' .
        '<div class="btn btngreen-small">' . $s['btn'] . '</div></div></div></a>';
}
$signHtml .= '</div></section>';

// ---- Motorky
$mo = $C['motos_section'];
$motosHtml = '<section aria-labelledby="catalogue"><h2>' . $mo['title'] . '</h2>' .
    '<p>' . $mo['intro'] . '</p><p>&nbsp;</p>' .
    '<div id="home-motos" class="gr4">';
if (!empty($motos)) {
    foreach (array_slice($motos, 0, (int)($mo['limit'] ?? 4)) as $m) {
        $motosHtml .= '<section aria-labelledby="catalogue">' . renderMotoCard($m) . '</section>';
    }
} else {
    $motosHtml .= '<p>' . htmlspecialchars($mo['empty']) . '</p>';
}
$motosHtml .= '</div><p>&nbsp;</p><p class="text-center"><a class="btn btngreen" href="' . BASE_URL . $mo['cta_href'] . '">' . $mo['cta_label'] . '</a></p></section>';

// ---- Proces
$processHtml = '<section aria-labelledby="process"><h2>' . $C['process']['title'] . '</h2><div class="gr4">';
foreach ($C['process']['steps'] as $s) {
    $processHtml .= renderWbox($s['icon'], $s['title'], $s['text']);
}
$processHtml .= '</div></section>';

// ---- FAQ
$faqHtml = renderFaqSection($C['faq']['title'], $C['faq']['items'], $C['faq']['more_link'] ?? null);

// ---- CTA
$ctaHtml = renderCta($C['cta']['title'], $C['cta']['text'], $C['cta']['buttons']);

// ---- Reviews (zobrazí se jen pokud data existují)
$reviewsHtml = '';
if (!empty($reviews)) {
    $reviewsHtml = '<section aria-labelledby="reviews"><h2>' . htmlspecialchars($C['reviews']['title']) . '</h2>'
        . '<p>' . htmlspecialchars($C['reviews']['intro']) . '</p><p>&nbsp;</p>'
        . '<div class="gr3">';
    foreach ($reviews as $r) {
        $rating = (int)($r['rating'] ?? 0);
        $stars = str_repeat('★', max(0, min(5, $rating))) . str_repeat('☆', max(0, 5 - $rating));
        $author = htmlspecialchars($r['author_name'] ?? 'Spokojený zákazník');
        $comment = htmlspecialchars($r['comment'] ?? '');
        $reviewsHtml .= '<div class="review-card">'
            . '<div class="review-stars" aria-label="Hodnocení ' . $rating . ' z 5">' . $stars . '</div>'
            . '<p class="review-comment">„' . $comment . '"</p>'
            . '<p class="review-author">— <strong>' . $author . '</strong></p>'
            . '</div>';
    }
    $reviewsHtml .= '</div></section>';
}

// ---- Blog
$bl = $C['blog'];
$blogHtml = '<section aria-labelledby="blog"><h2>' . $bl['title'] . '</h2><div id="home-blog" class="gr3">';
if (!empty($posts)) {
    foreach (array_slice($posts, 0, (int)($bl['limit'] ?? 3)) as $p) {
        $blogHtml .= renderBlogCard($p);
    }
} else {
    $blogHtml .= '<p>' . htmlspecialchars($bl['empty']) . '</p>';
}
$blogHtml .= '</div><p>&nbsp;</p><p class="text-center"><a class="btn btngreen" href="' . BASE_URL . $bl['cta_href'] . '">' . $bl['cta_label'] . '</a></p></section>';

// ---- Banner
$hero = $C['hero'];
$heroImgUrl = BASE_URL . '/' . ltrim($hero['image'], '/');
$heroWebp = preg_replace('/\.(png|jpg|jpeg)$/i', '.webp', $heroImgUrl);
$ctaP = $hero['cta_primary'];
$ctaS = $hero['cta_secondary'];
$bannerHtml = '<div class="banner">' .
    '<picture>' .
        '<source srcset="' . htmlspecialchars($heroWebp) . '" type="image/webp">' .
        '<img fetchpriority="high" alt="' . htmlspecialchars($hero['alt']) . '" src="' . htmlspecialchars($heroImgUrl) . '">' .
    '</picture>' .
    '<div class="banner-wrapper"><div class="container"><div class="banner-caption">' .
        '<p>' . $hero['eyebrow'] . '</p><p>&nbsp;</p>' .
        '<p>' . $hero['body'] . '</p><p>&nbsp;</p>' .
        '<p><a class="btn ' . ($ctaP['cls'] ?? 'btngreen') . '" href="' . BASE_URL . $ctaP['href'] . '">' . $ctaP['label'] . '</a> <a class="btn ' . ($ctaS['cls'] ?? 'btndark') . '" href="' . BASE_URL . $ctaS['href'] . '">' . $ctaS['label'] . '</a></p>' .
    '</div></div></div></div>';

$content = $bannerHtml .
    '<main id="content"><div class="container"><h1>' . $C['h1'] . '</h1>' .
    $signHtml . $motosHtml . $processHtml . $faqHtml . $reviewsHtml . $ctaHtml . $blogHtml .
    '</div></main>';

renderPage($C['seo']['title'], $content, '/', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'og_image' => $C['seo']['og_image'] ?? null,
]);
