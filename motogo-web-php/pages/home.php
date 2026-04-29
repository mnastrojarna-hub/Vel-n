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
        // og_image necháme na default v renderPage() — ten použije aktuální doménu
        'og_image' => null,
    ],
    'hero' => [
        'image' => 'gfx/hero-banner.jpg',
        'alt' => 'Půjčovna motorek Vysočina',
        'eyebrow' => '<strong>Půjčovna motorek</strong> na Vysočině',
        'body' => 'Půjč si motorku na Vysočině snadno online.<br>Vyber si z cestovních, sportovních i enduro modelů.<br>Rezervace s platbou kartou a rychlým převzetím.',
        'cta_primary' => ['label' => 'VYBER SI MOTORKU', 'href' => '/katalog', 'cls' => 'btngreen'],
        'cta_secondary' => ['label' => 'JAK TO FUNGUJE', 'href' => '/jak-pujcit', 'cls' => 'btndark'],
    ],
    'h1' => 'Půjčovna motorek Vysočina Motogo24 – bez kauce a nonstop',
    'intro' => 'Vítejte v <strong>Motogo24</strong> – vaší půjčovně motorek na Vysočině. U nás si půjčíte motorku <strong>bez kauce</strong>, s výbavou v ceně a v režimu <strong>nonstop</strong>. Ať hledáte cestovní, sportovní, enduro nebo dětskou motorku, Motogo24 vám v srdci Vysočiny nabídne motorku na míru.',
    'signposts_title' => 'Rychlý rozcestník po Motogo24',
    'signposts' => [
        ['icon' => 'gfx/vyber-motorku.svg', 'title' => 'Katalog motorek', 'text' => 'Prohlédněte si naši nabídku motorek na pronájem – od sportovních po cestovní modely.', 'btn' => 'KATALOG MOTOREK', 'href' => '/katalog'],
        ['icon' => 'gfx/potvrzeni-rezervace.svg', 'title' => 'Jak si půjčit motorku', 'text' => 'Jednoduchý proces: vyberte motorku k zapůjčení, rezervujte a vyjeďte.', 'btn' => 'JAK SI PŮJČIT MOTORKU', 'href' => '/jak-pujcit'],
        ['icon' => 'gfx/rezervace-online.svg', 'title' => 'Online rezervace motorky', 'text' => 'Zarezervujte si motorku na pronájem přes snadný online systém.', 'btn' => 'REZERVOVAT MOTORKU', 'href' => '/rezervace'],
        ['icon' => 'gfx/kontakt.svg', 'title' => 'Kontakty a mapa', 'text' => 'Navštivte naši půjčovnu motorek v Pelhřimově nebo nás kontaktujte.', 'btn' => 'KONTAKT', 'href' => '/kontakt'],
        ['icon' => 'gfx/faq.svg', 'title' => 'Často kladené dotazy', 'text' => 'Nejčastější dotazy k půjčení motorky přehledně na jednom místě.', 'btn' => 'ČASTÉ DOTAZY', 'href' => '/jak-pujcit/faq'],
        ['icon' => 'gfx/uzij-si-jizdu.svg', 'title' => 'Motocyklové výlety', 'text' => 'Objevte nejlepší motocyklové trasy v Česku pro turisty i místní.', 'btn' => 'MOTOCYKLOVÉ TRASY', 'href' => '/blog'],
    ],
    'motos_section' => [
        'title' => 'Naše motorky k pronájmu na Vysočině',
        'intro' => 'Prohlédněte si nabídku cestovních, sportovních a enduro z naší půjčovny motorek na Vysočině.',
        'empty' => 'Momentálně nemáme žádné motorky v nabídce.',
        'cta_label' => 'KATALOG MOTOREK',
        'cta_href' => '/katalog',
        'limit' => 4,
    ],
    'process' => [
        'title' => 'Jak probíhá půjčení motorky na Vysočině',
        'steps' => [
            ['icon' => 'gfx/vyber-motorku.svg', 'title' => '1. Vyber', 'text' => 'Vyberte si svou ideální motorku z naší nabídky motorek na pronájem.'],
            ['icon' => 'gfx/rezervace-online.svg', 'title' => '2. Rezervuj', 'text' => 'Zarezervujte si půjčení motorky přes náš jednoduchý online systém.'],
            ['icon' => 'gfx/predani-motorky.svg', 'title' => '3. Převzetí', 'text' => 'Vyzvedněte si motorku v naší půjčovně motorek v Pelhřimově.'],
            ['icon' => 'gfx/uzij-si-jizdu.svg', 'title' => '4. Užij jízdu', 'text' => 'Užijte si svobodu a objevte Česko na motorkách k zapůjčení.'],
        ],
    ],
    'faq' => [
        'title' => 'Často kladené otázky',
        'more_link' => '/jak-pujcit/faq',
        // items se naplní z DB (faq_items WHERE featured_home=true) — viz níže
        'items' => [],
    ],
    'cta' => [
        'title' => 'Rezervuj svou motorku online',
        'text' => 'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená nonstop. Stačí pár kliků a tvoje jízda začíná.',
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
$signpostTitle = $C['signposts_title'] ?? 'Rychlý rozcestník po Motogo24';
$signHtml = '<section aria-labelledby="signpost-h"><h2 id="signpost-h" data-cms-key="web.home.signposts_title">' . htmlspecialchars($signpostTitle) . '</h2><p>&nbsp;</p><div class="gr3">';
foreach ($C['signposts'] as $i => $s) {
    $iconSrc = BASE_URL . '/' . ltrim($s['icon'], '/');
    $titleText = trim(strip_tags($s['title'] ?? ''));
    if ($titleText === '') $titleText = htmlspecialchars($s['btn'] ?? 'Informace');
    $kBase = 'web.home.signposts.' . $i;
    $signHtml .= '<a class="gbox" href="' . BASE_URL . $s['href'] . '">' .
        '<div class="gr2"><div class="gbox-img"><img src="' . htmlspecialchars($iconSrc) . '" class="icon" alt="' . htmlspecialchars(strip_tags($s['btn'] ?? $titleText)) . '" loading="lazy"></div><div>' .
        '<h3 data-cms-key="' . $kBase . '.title">' . ($s['title'] !== '' ? $s['title'] : $titleText) . '</h3>' .
        '<p data-cms-key="' . $kBase . '.text">' . $s['text'] . '</p>' .
        '<div class="btn btngreen-small" data-cms-key="' . $kBase . '.btn">' . $s['btn'] . '</div></div></div></a>';
}
$signHtml .= '</div></section>';

// ---- Motorky
$mo = $C['motos_section'];
$motosHtml = '<section aria-labelledby="catalogue"><h2 data-cms-key="web.home.motos_section.title">' . $mo['title'] . '</h2>' .
    '<p data-cms-key="web.home.motos_section.intro">' . $mo['intro'] . '</p><p>&nbsp;</p>' .
    '<div id="home-motos" class="gr4">';
if (!empty($motos)) {
    foreach (array_slice($motos, 0, (int)($mo['limit'] ?? 4)) as $m) {
        $motosHtml .= '<section aria-labelledby="catalogue">' . renderMotoCard($m) . '</section>';
    }
} else {
    $motosHtml .= '<p data-cms-key="web.home.motos_section.empty">' . htmlspecialchars($mo['empty']) . '</p>';
}
$motosHtml .= '</div><p>&nbsp;</p><p class="text-center"><a class="btn btngreen" href="' . BASE_URL . $mo['cta_href'] . '" data-cms-key="web.home.motos_section.cta_label">' . $mo['cta_label'] . '</a></p></section>';

// ---- Proces
$processHtml = '<section aria-labelledby="process"><h2 data-cms-key="web.home.process.title">' . $C['process']['title'] . '</h2><div class="gr4">';
foreach ($C['process']['steps'] as $i => $s) {
    $kBase = 'web.home.process.steps.' . $i;
    $processHtml .= renderWbox(
        $s['icon'],
        '<span data-cms-key="' . $kBase . '.title">' . $s['title'] . '</span>',
        '<span data-cms-key="' . $kBase . '.text">' . $s['text'] . '</span>'
    );
}
$processHtml .= '</div></section>';

// ---- FAQ — featured items z DB (faq_items WHERE featured_home=true)
// Položky se spravují ve Velíně v záložce „Časté dotazy"; admin označí 4 (nebo víc)
// otázek jako ⭐ a tady se zobrazí prvních N podle sort_order.
$lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
$featuredFaq = $sb->fetchFaqItems(['featured_only' => true, 'limit' => 4]);
$faqItemsKeyed = [];
foreach ($featuredFaq as $r) {
    $q = function_exists('localized') ? (localized($r, 'question', $lang) ?: $r['question']) : $r['question'];
    $a = function_exists('localized') ? (localized($r, 'answer', $lang) ?: $r['answer']) : $r['answer'];
    $faqItemsKeyed[] = ['q' => $q, 'a' => $a];
}
$faqTitleKeyed = '<span data-cms-key="web.home.faq.title">' . ($C['faq']['title'] ?? '') . '</span>';
$faqHtml = !empty($faqItemsKeyed)
    ? renderFaqSection($faqTitleKeyed, $faqItemsKeyed, $C['faq']['more_link'] ?? null)
    : '';

// ---- CTA
$ctaButtonsKeyed = [];
foreach (($C['cta']['buttons'] ?? []) as $i => $btn) {
    $b = $btn;
    $b['label'] = '<span data-cms-key="web.home.cta.buttons.' . $i . '.label">' . ($btn['label'] ?? '') . '</span>';
    $ctaButtonsKeyed[] = $b;
}
$ctaHtml = renderCta(
    '<span data-cms-key="web.home.cta.title">' . ($C['cta']['title'] ?? '') . '</span>',
    '<span data-cms-key="web.home.cta.text">' . ($C['cta']['text'] ?? '') . '</span>',
    $ctaButtonsKeyed
);

// ---- Reviews (zobrazí se jen pokud data existují)
$reviewsHtml = '';
if (!empty($reviews)) {
    $reviewsHtml = '<section aria-labelledby="reviews"><h2 data-cms-key="web.home.reviews.title">' . htmlspecialchars($C['reviews']['title']) . '</h2>'
        . '<p data-cms-key="web.home.reviews.intro">' . htmlspecialchars($C['reviews']['intro']) . '</p><p>&nbsp;</p>'
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
$blogHtml = '<section aria-labelledby="blog"><h2 data-cms-key="web.home.blog.title">' . $bl['title'] . '</h2><div id="home-blog" class="gr3">';
if (!empty($posts)) {
    foreach (array_slice($posts, 0, (int)($bl['limit'] ?? 3)) as $p) {
        $blogHtml .= renderBlogCard($p);
    }
} else {
    $blogHtml .= '<p data-cms-key="web.home.blog.empty">' . htmlspecialchars($bl['empty']) . '</p>';
}
$blogHtml .= '</div><p>&nbsp;</p><p class="text-center"><a class="btn btngreen" href="' . BASE_URL . $bl['cta_href'] . '" data-cms-key="web.home.blog.cta_label">' . $bl['cta_label'] . '</a></p></section>';

// ---- Banner
$hero = $C['hero'];
$heroImgUrl = BASE_URL . '/' . ltrim($hero['image'], '/');
$heroWebp = preg_replace('/\.(png|jpg|jpeg)$/i', '.webp', $heroImgUrl);
$ctaP = $hero['cta_primary'];
$ctaS = $hero['cta_secondary'];
$bannerHtml = '<div class="banner">' .
    '<picture>' .
        '<source srcset="' . htmlspecialchars($heroWebp) . '" type="image/webp" sizes="(max-width:480px) 100vw,(max-width:1024px) 100vw,1920px">' .
        '<img fetchpriority="high" decoding="async" alt="' . htmlspecialchars($hero['alt']) . '" src="' . htmlspecialchars($heroImgUrl) . '" width="1920" height="480">' .
    '</picture>' .
    '<div class="banner-wrapper"><div class="container"><div class="banner-caption">' .
        '<p data-cms-key="web.home.hero.eyebrow">' . $hero['eyebrow'] . '</p><p>&nbsp;</p>' .
        '<p data-cms-key="web.home.hero.body">' . $hero['body'] . '</p><p>&nbsp;</p>' .
        '<p><a class="btn ' . ($ctaP['cls'] ?? 'btngreen') . '" href="' . BASE_URL . $ctaP['href'] . '" data-cms-key="web.home.hero.cta_primary.label">' . $ctaP['label'] . '</a> <a class="btn ' . ($ctaS['cls'] ?? 'btndark') . '" href="' . BASE_URL . $ctaS['href'] . '" data-cms-key="web.home.hero.cta_secondary.label">' . $ctaS['label'] . '</a></p>' .
    '</div></div></div></div>';

$introHtml = !empty($C['intro']) ? '<p class="home-intro" data-cms-key="web.home.intro">' . $C['intro'] . '</p>' : '';

$content = $bannerHtml .
    '<main id="content"><div class="container"><h1 data-cms-key="web.home.h1">' . $C['h1'] . '</h1>' . $introHtml .
    $signHtml . $motosHtml . $processHtml . $faqHtml . $reviewsHtml . $ctaHtml . $blogHtml .
    '</div></main>';

// ---- Strukturovaná data: FAQ + HowTo + AggregateRating ze sekcí výše ----

// FAQPage schema z $faqItemsKeyed (DB-driven) — stripuje HTML, zachycuje strong/em jako text.
$faqSchemaItems = [];
if (!empty($faqItemsKeyed) && is_array($faqItemsKeyed)) {
    foreach ($faqItemsKeyed as $f) {
        $q = trim(strip_tags($f['q'] ?? ''));
        $a = trim(strip_tags($f['a'] ?? ''));
        if ($q === '' || $a === '') continue;
        $faqSchemaItems[] = '{"@type":"Question","name":' . json_encode($q, JSON_UNESCAPED_UNICODE) . ',"acceptedAnswer":{"@type":"Answer","text":' . json_encode($a, JSON_UNESCAPED_UNICODE) . '}}';
    }
}
$faqSchema = '';
if (!empty($faqSchemaItems)) {
    $faqSchema = '<script type="application/ld+json">{"@context":"https://schema.org","@type":"FAQPage","mainEntity":[' . implode(',', $faqSchemaItems) . ']}</script>';
}

// HowTo schema z $C['process']['steps'] — návod "Jak si půjčit motorku v Motogo24".
$howToSteps = [];
if (!empty($C['process']['steps']) && is_array($C['process']['steps'])) {
    foreach ($C['process']['steps'] as $i => $s) {
        $name = trim(strip_tags($s['title'] ?? ''));
        $text = trim(strip_tags($s['text'] ?? ''));
        if ($name === '' || $text === '') continue;
        $howToSteps[] = '{"@type":"HowToStep","position":' . ($i + 1) . ',"name":' . json_encode($name, JSON_UNESCAPED_UNICODE) . ',"text":' . json_encode($text, JSON_UNESCAPED_UNICODE) . ',"url":' . json_encode(siteCanonicalUrl('/jak-pujcit#krok-' . ($i + 1)), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . '}';
    }
}
$howToSchema = '';
if (!empty($howToSteps)) {
    $howToSchema = '<script type="application/ld+json">{"@context":"https://schema.org","@type":"HowTo","name":"Jak si půjčit motorku v MotoGo24","description":"Snadný 4krokový postup — výběr motorky, online rezervace, převzetí na pobočce v Pelhřimově, jízda.","totalTime":"PT10M","estimatedCost":{"@type":"MonetaryAmount","currency":"CZK","value":"990"},"supply":[{"@type":"HowToSupply","name":"Řidičský průkaz odpovídající skupiny (AM/A1/A2/A nebo B)"},{"@type":"HowToSupply","name":"Občanský průkaz nebo pas"},{"@type":"HowToSupply","name":"Platební karta (Visa/Mastercard, Apple/Google Pay)"}],"tool":[{"@type":"HowToTool","name":"Online rezervační formulář"}],"step":[' . implode(',', $howToSteps) . ']}</script>';
}

// AggregateRating z reálných reviews — pokud máme aspoň 1 recenzi s ratingem.
$aggRating = null;
if (!empty($reviews) && is_array($reviews)) {
    $rated = array_filter($reviews, function ($r) { return !empty($r['rating']); });
    if (count($rated) > 0) {
        $sum = array_sum(array_map(function ($r) { return (int)$r['rating']; }, $rated));
        $cnt = count($rated);
        $avg = round($sum / $cnt, 1);
        $aggRating = ['rating' => $avg, 'count' => $cnt];
    }
}

renderPage($C['seo']['title'], $content, '/', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'og_image' => $C['seo']['og_image'] ?? null,
    'schema' => $faqSchema . $howToSchema,
    'aggregate_rating' => $aggRating,
    'speakable' => ['h1', '.home-intro', '[aria-labelledby="catalogue"] > h2', '[aria-labelledby="process"]'],
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
    ],
]);
