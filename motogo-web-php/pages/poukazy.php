<?php
// ===== MotoGo24 Web PHP — Stránka Poukazy (CMS-driven) =====

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Dárkové poukazy | Motopůjčovna a půjčovna motorek Vysočina',
        'description' => 'Kupte dárkový poukaz na pronájem motorky v motopůjčovně MotoGo24. Platnost 3 roky, bez kauce, výbava v ceně. Elektronický i tištěný poukaz. Online objednávka.',
        'keywords' => 'motopůjčovna, půjčovna motorek, dárkový poukaz na motorku, dárek pro motorkáře, poukaz na pronájem motorky, voucher motorka, MotoGo24',
        'og_image' => 'https://www.motogo24.cz/gfx/darkovy-poukaz.jpg',
    ],
    'h1' => 'Kup dárkový poukaz – daruj zážitek na dvou kolech!',
    'intro_left' => '<p>Hledáš originální dárek pro partnera, kamaráda nebo tátu?</p><p>&nbsp;</p><p>Naše <strong>dárkové poukazy na pronájem motorky</strong> od Motogo24 – <strong>půjčovna motorek Vysočina</strong> – potěší začátečníky i zkušené jezdce.</p><p>&nbsp;</p><p>Vyber hodnotu poukazu nebo konkrétní motorku a daruj svobodu na dvou kolech.</p>',
    'intro_cta' => ['label' => 'OBJEDNAT DÁRKOVÝ POUKAZ', 'href' => '/koupit-darkovy-poukaz', 'aria' => 'Objednat dárkový poukaz na pronájem motorky v půjčovně Motogo24'],
    'intro_image' => ['src' => 'gfx/darkovy-poukaz.jpg', 'alt' => 'Dárkový poukaz'],
    'steps' => [
        ['icon' => 'gfx/vyber-motorku.svg', 'title' => '1. Vyber', 'text' => 'Vybereš si hodnotu poukazu nebo konkrétní motorku.'],
        ['icon' => 'gfx/zaplat.svg', 'title' => '2. Zaplať', 'text' => 'Zaplatíš online.'],
        ['icon' => 'gfx/potvrzeni-rezervace.svg', 'title' => '3. Vyzvedni', 'text' => 'Poukaz po zaplacení přistane do tvé e-mailové schránky.'],
    ],
    'validity_note' => 'Všechny vouchery mají <strong>platnost 3 roky</strong> od data vystavení. <strong>Obdarovaný si sám zvolí termín výpůjčky</strong>, který se mu hodí. Může nás kontaktovat e-mailem, telefonicky nebo přes sociální sítě.',
    'why' => [
        'title' => 'Proč zakoupit poukaz',
        'items' => [
            '<strong>Flexibilní volba</strong> – hodnota poukazu nebo konkrétní motorka.',
            '<strong>Platnost 3 roky</strong> – obdarovaný si sám vybere termín.',
            '<strong>Bez kauce</strong> – férové podmínky bez zbytečných překážek.',
            '<strong>Výbava v ceně</strong> – helma, bunda, kalhoty a rukavice zdarma.',
            '<strong>Nonstop provoz</strong> – vyzvednutí i vrácení kdykoli v den výpůjčky.',
            '<strong>Online objednávka</strong> – poukaz ti po zaplacení přijde e-mailem.',
        ],
    ],
    'how' => [
        'title' => 'Jak poukaz využít',
        'items' => [
            // = znění majitele ve Velíně (web.poukazy.how.items.*, 2026-10) — kategorie, které flotila opravdu má
            '<strong>Cestovní motorky</strong> – víkendový roadtrip po Vysočině, celé ČR i v zahraničí.',
            '<strong>Naked motorky</strong> – dynamická jízda plná zábavy a adrenalinu.',
            '<strong>Supermoto</strong> – adrenalinová jízda v zatáčkách. <strong>Choppery a cruisery</strong> – pohodová vyjížďka ve stylu, kde je cesta cílem.',
            '<strong>Dětské motorky</strong> – první jízdy pro malé jezdce pod dohledem. <strong>Skútry</strong> – jednoduché svezení bez řazení, ideální na výlet po okolí.',
        ],
    ],
    'catalog_cta' => ['label' => 'ZOBRAZIT KATALOG MOTOREK', 'href' => '/katalog'],
    'faq' => [
        'title' => 'Často kladené dotazy k dárkovým poukazům',
        'items' => [
            ['q' => 'Jaká je platnost dárkového poukazu?', 'a' => 'Všechny vouchery mají platnost <strong>3 roky</strong> od data vystavení. Termín výpůjčky si obdarovaný volí sám.'],
            ['q' => 'Jak poukaz doručíte?', 'a' => '<strong>Okamžitě e-mailem</strong> po úhradě. Na požádání umíme připravit i dárkový tisk v provozovně.'],
            ['q' => 'Musí obdarovaný skládat kauci?', 'a' => 'Ne. <strong>Půjčujeme bez kauce</strong>. Podmínky jsou jasné a férové, výbava řidiče je v ceně.'],
            ['q' => 'Lze změnit termín uplatnění?', 'a' => 'Ano, <strong>termín lze po domluvě změnit</strong> dle dostupnosti konkrétní motorky v našem kalendáři.'],
            ['q' => 'Na jaké motorky lze voucher uplatnit?', 'a' => 'Poukaz můžeš uplatnit na všechny motorky v nabídce Motogo24 – podle zvolené hodnoty poukazu.'],
        ],
    ],
    'cta' => [
        'title' => 'Dárkový poukaz na pronájem motorky – Vysočina',
        'text' => 'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop provozem</strong>, <strong>bez kauce</strong> a <strong>výbavou v ceně</strong>. Dárkový voucher je ideální volba, jak darovat <em>motorbike rental</em> zážitek – od <strong>cestovních</strong> přes <strong>naked</strong> a <strong>supermoto</strong> až po <strong>dětské motorky, choppery</strong> nebo <strong>skútry</strong>.',
        'buttons' => [['label' => 'OBJEDNAT VOUCHER', 'href' => '/koupit-darkovy-poukaz', 'cls' => 'btndark pulse']],
    ],
];

$C = $sb->siteContent('poukazy', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('breadcrumb.vouchers')]);
$kp = 'web.poukazy';
// Vzhled (2026-10-23, css/voucher.css): hero karta, kroky jako číslovaný stepper, seznamy jako karty.
// Texty, CMS klíče, ikony i pořadí bloků beze změny; mezery řeší CSS (žádné <p>&nbsp;</p>).

$img = is_array($C['intro_image'] ?? null) ? $C['intro_image'] : ($defaults['intro_image']);
$imgSrc = BASE_URL . '/' . ltrim($img['src'] ?? '', '/');

$intro_cta = is_array($C['intro_cta'] ?? null) ? $C['intro_cta'] : ($defaults['intro_cta']);
// Prázdné odstavce-mezery (<p>&nbsp;</p>) z CMS textu úvodu nahrazuje CSS mezera; v CMS admin režimu se
// nechávají, ať inline editor uloží text beze změny.
$introLeft = sanitizeHtml($C['intro_left'] ?? '');
if (!mgCmsAdminValid()) $introLeft = preg_replace('#<p>(?:\s|&nbsp;|&\#160;|\xC2\xA0)*</p>#i', '', $introLeft);
$intro = '<section aria-labelledby="title" class="gv-hero"><div class="gv-hero-txt">' .
    '<h1 id="title" data-cms-key="' . $kp . '.h1">' . sanitizeHtml($C['h1'] ?? '') . '</h1>' .
    '<div class="gv-hero-lead" data-cms-key="' . $kp . '.intro_left">' . $introLeft . '</div>' .
    '<p class="cta gv-hero-cta"><a aria-label="' . htmlspecialchars($intro_cta['aria'] ?? ($intro_cta['label'] ?? '')) . '" class="btn btngreen" href="' . BASE_URL . ($intro_cta['href'] ?? '#') . '" data-cms-key="' . $kp . '.intro_cta.label">' . sanitizeHtml($intro_cta['label'] ?? '') . '</a></p>' .
    '</div><div class="gv-hero-img">' .
    '<img alt="' . htmlspecialchars($img['alt'] ?? '') . '" class="imgres" loading="lazy" src="' . htmlspecialchars($imgSrc) . '">' .
    '</div></section>';

// Kroky: ikona + číslo + titulek + text. Když už titulek z CMS číslo má („1. Vyber“), odznak s číslem se nekreslí.
// Nadpis sekce = dosavadní aria-label (poukazy.steps.aria), přes tc() editovatelný v CMS admin režimu (web.layout.*).
$stepsHtml = '<section class="gv-how" aria-labelledby="gv-how-t"><h2 id="gv-how-t" class="gv-eyebrow">' . tc('poukazy.steps.aria') . '</h2><ol class="gv-steps">';
$n = 0;
foreach ((is_array($C['steps'] ?? null) ? $C['steps'] : []) as $i => $s) {
    if (!is_array($s)) continue;
    $n++;
    $kBase = $kp . '.steps.' . $i;
    $title = sanitizeHtml($s['title'] ?? '');
    $hasNum = (bool)preg_match('/^\s*\d+\s*[.)]/u', html_entity_decode(strip_tags($title), ENT_QUOTES | ENT_HTML5, 'UTF-8'));
    $icon = (string)($s['icon'] ?? '');
    $stepsHtml .= '<li class="gv-step">' .
        '<span class="gv-step-ico">' . ($icon !== '' ? '<img src="' . htmlspecialchars(BASE_URL . '/' . ltrim($icon, '/')) . '" class="icon" alt="' . htmlspecialchars(trim(strip_tags($title))) . '" aria-hidden="true" loading="lazy">' : '') .
        ($hasNum ? '' : '<span class="gv-step-n" aria-hidden="true">' . $n . '</span>') . '</span>' .
        '<div class="gv-step-body"><h3 class="gv-step-t"><span data-cms-key="' . $kBase . '.title">' . $title . '</span></h3>' .
        '<p class="gv-step-x"><span data-cms-key="' . $kBase . '.text">' . sanitizeHtml($s['text'] ?? '') . '</span></p></div></li>';
}
$stepsHtml .= '</ol><div class="gv-note"><svg class="gv-note-ico" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M12 3 4.5 6v5.5c0 4.6 3.2 8.4 7.5 9.5 4.3-1.1 7.5-4.9 7.5-9.5V6L12 3zM8.5 12l2.5 2.5 4.5-5"/></svg>' .
    '<p data-cms-key="' . $kp . '.validity_note">' . sanitizeHtml($C['validity_note'] ?? '') . '</p></div></section>';

$whyLis = '';
foreach ((is_array($C['why']['items'] ?? null) ? $C['why']['items'] : []) as $i => $item) {
    $whyLis .= '<li data-cms-key="' . $kp . '.why.items.' . $i . '">' . sanitizeHtml($item) . '</li>';
}
$howLis = '';
foreach ((is_array($C['how']['items'] ?? null) ? $C['how']['items'] : []) as $i => $item) {
    $howLis .= '<li data-cms-key="' . $kp . '.how.items.' . $i . '">' . sanitizeHtml($item) . '</li>';
}
$catCta = is_array($C['catalog_cta'] ?? null) ? $C['catalog_cta'] : ($defaults['catalog_cta']);
$listsHtml = '<section class="gv-lists"><div class="gv-cards">' .
    '<div class="gv-card gv-card--why"><h2 data-cms-key="' . $kp . '.why.title">' . sanitizeHtml($C['why']['title'] ?? '') . '</h2><ul class="gv-list">' . $whyLis . '</ul></div>' .
    '<div class="gv-card gv-card--how"><h2 data-cms-key="' . $kp . '.how.title">' . sanitizeHtml($C['how']['title'] ?? '') . '</h2><ul class="gv-list">' . $howLis . '</ul></div></div>' .
    '<p class="gv-lists-cta"><a class="btn btngreen" href="' . BASE_URL . ($catCta['href'] ?? '#') . '" data-cms-key="' . $kp . '.catalog_cta.label">' . sanitizeHtml($catCta['label'] ?? '') . '</a></p></section>';

$faqItemsHtml = '';
foreach ((is_array($C['faq']['items'] ?? null) ? $C['faq']['items'] : []) as $i => $faq) {
    if (!is_array($faq)) continue;
    $kBase = $kp . '.faq.items.' . $i;
    $faqItemsHtml .= renderFaqItem(
        '<span data-cms-key="' . $kBase . '.q">' . sanitizeHtml($faq['q'] ?? '') . '</span>',
        '<span data-cms-key="' . $kBase . '.a">' . sanitizeHtml($faq['a'] ?? '') . '</span>'
    );
}
$faqSection = '<section class="gv-faq" aria-labelledby="gv-faq-t"><h2 id="gv-faq-t" data-cms-key="' . $kp . '.faq.title">' . sanitizeHtml($C['faq']['title'] ?? '') . '</h2>' .
    '<div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">' . $faqItemsHtml . '</div></div></div></section>';

// CTA = struktura renderCta() (section[aria-labelledby=cta]) bez <p>&nbsp;</p> mezer; fallback titulku stejný.
$ctaTitle = '<span data-cms-key="' . $kp . '.cta.title">' . sanitizeHtml($C['cta']['title'] ?? '') . '</span>';
if (trim(strip_tags($ctaTitle)) === '' && !mgCmsAdminValid()) $ctaTitle = 'Rezervujte si motorku';
$ctaBtns = '';
foreach ((is_array($C['cta']['buttons'] ?? null) ? $C['cta']['buttons'] : []) as $i => $btn) {
    if (!is_array($btn)) continue;
    $ctaBtns .= '<a class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . ($btn['href'] ?? '#') . '"><span data-cms-key="' . $kp . '.cta.buttons.' . $i . '.label">' . sanitizeHtml($btn['label'] ?? '') . '</span></a>';
}
$ctaHtml = '<section aria-labelledby="cta" class="gv-cta"><h2 id="cta">' . $ctaTitle . '</h2>' .
    '<p><span data-cms-key="' . $kp . '.cta.text">' . sanitizeHtml($C['cta']['text'] ?? '') . '</span></p>' .
    '<p class="gv-cta-btns">' . $ctaBtns . '</p></section>';

$content = '<main id="content" class="gv-page"><div class="container">' . $bc .
    '<div class="ccontent">' . $intro . $stepsHtml . $listsHtml . $faqSection . $ctaHtml .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/poukazy', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'og_image' => $C['seo']['og_image'] ?? null,
    'styles' => ['/css/voucher.css'],
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.vouchers'), 'url' => siteCanonicalUrl('/poukazy')],
    ],
]);
