<?php
// ===== MotoGo24 Web PHP — Stránka Poukazy (CMS-driven) =====

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Půjčovna motorek Vysočina - Poukazy',
        'description' => 'Kupte dárkový poukaz na pronájem motorky. Platnost 3 roky, bez kauce, výbava v ceně. Elektronický i tištěný poukaz. Online objednávka.',
        'keywords' => 'dárkový poukaz motorka, voucher pronájem motorky, dárek pro motorkáře, poukaz Motogo24, půjčovna motorek Vysočina',
        'og_image' => 'https://motogo24.cz/gfx/darkovy-poukaz.jpg',
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
            '<strong>Cestovní motorky</strong> – víkendový roadtrip po Vysočině i celé ČR.',
            '<strong>Sportovní motorky</strong> – adrenalinová jízda v zatáčkách.',
            '<strong>Enduro</strong> – lehký terén a dobrodružství mimo hlavní cesty.',
            '<strong>Dětské motorky</strong> – první jízdy pro malé jezdce pod dohledem.',
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
            ['q' => 'Na jaké motorky lze voucher uplatnit?', 'a' => 'Na <strong>cestovní, sportovní, enduro i dětské motorky</strong> v nabídce Motogo24 – podle zvolené hodnoty poukazu.'],
        ],
    ],
    'cta' => [
        'title' => 'Dárkový poukaz na pronájem motorky – Vysočina',
        'text' => 'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop provozem</strong>, <strong>bez kauce</strong> a <strong>výbavou v ceně</strong>. Dárkový voucher je ideální volba, jak darovat <em>motorbike rental</em> zážitek – od <strong>cestovních</strong> přes <strong>sportovní</strong> až po <strong>enduro</strong> a <strong>dětské motorky</strong>.',
        'buttons' => [['label' => 'OBJEDNAT VOUCHER', 'href' => '/koupit-darkovy-poukaz', 'cls' => 'btndark pulse']],
    ],
];

$C = $sb->siteContent('poukazy', $defaults);

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('breadcrumb.vouchers')]);
$kp = 'web.poukazy';

$img = is_array($C['intro_image'] ?? null) ? $C['intro_image'] : ($defaults['intro_image']);
$imgSrc = BASE_URL . '/' . ltrim($img['src'] ?? '', '/');

$intro_cta = is_array($C['intro_cta'] ?? null) ? $C['intro_cta'] : ($defaults['intro_cta']);
$intro = '<section aria-labelledby="title"><h1 data-cms-key="' . $kp . '.h1">' . ($C['h1'] ?? '') . '</h1>' .
    '<div class="gr2"><div><div data-cms-key="' . $kp . '.intro_left">' . ($C['intro_left'] ?? '') . '</div>' .
    '<p>&nbsp;</p>' .
    '<p class="cta"><a aria-label="' . htmlspecialchars($intro_cta['aria'] ?? ($intro_cta['label'] ?? '')) . '" class="btn btngreen" href="' . BASE_URL . ($intro_cta['href'] ?? '#') . '" data-cms-key="' . $kp . '.intro_cta.label">' . ($intro_cta['label'] ?? '') . '</a></p>' .
    '<p>&nbsp;</p>' .
    '</div><div>' .
    '<img alt="' . htmlspecialchars($img['alt'] ?? '') . '" class="imgres" loading="lazy" src="' . htmlspecialchars($imgSrc) . '">' .
    '</div></div></section>';

$stepsHtml = '<section aria-labelledby="content"><div class="gr3">';
foreach ((is_array($C['steps'] ?? null) ? $C['steps'] : []) as $i => $s) {
    if (!is_array($s)) continue;
    $kBase = $kp . '.steps.' . $i;
    $stepsHtml .= renderWbox(
        $s['icon'] ?? '',
        '<span data-cms-key="' . $kBase . '.title">' . ($s['title'] ?? '') . '</span>',
        '<span data-cms-key="' . $kBase . '.text">' . ($s['text'] ?? '') . '</span>'
    );
}
$stepsHtml .= '</div><p>&nbsp;</p><p data-cms-key="' . $kp . '.validity_note">' . ($C['validity_note'] ?? '') . '</p><p>&nbsp;</p><p>&nbsp;</p>';

$whyLis = '';
foreach ((is_array($C['why']['items'] ?? null) ? $C['why']['items'] : []) as $i => $item) {
    $whyLis .= '<li data-cms-key="' . $kp . '.why.items.' . $i . '">' . $item . '</li>';
}
$howLis = '';
foreach ((is_array($C['how']['items'] ?? null) ? $C['how']['items'] : []) as $i => $item) {
    $howLis .= '<li data-cms-key="' . $kp . '.how.items.' . $i . '">' . $item . '</li>';
}
$catCta = is_array($C['catalog_cta'] ?? null) ? $C['catalog_cta'] : ($defaults['catalog_cta']);
$stepsHtml .= '<div class="gr2"><div><h2 data-cms-key="' . $kp . '.why.title">' . ($C['why']['title'] ?? '') . '</h2><ul>' . $whyLis . '</ul></div>' .
    '<div><h2 data-cms-key="' . $kp . '.how.title">' . ($C['how']['title'] ?? '') . '</h2><ul>' . $howLis . '</ul></div></div>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . ($catCta['href'] ?? '#') . '" data-cms-key="' . $kp . '.catalog_cta.label">' . ($catCta['label'] ?? '') . '</a></p>' .
    '<p>&nbsp;</p><p>&nbsp;</p></section>';

$faqItemsHtml = '';
foreach ((is_array($C['faq']['items'] ?? null) ? $C['faq']['items'] : []) as $i => $faq) {
    if (!is_array($faq)) continue;
    $kBase = $kp . '.faq.items.' . $i;
    $faqItemsHtml .= renderFaqItem(
        '<span data-cms-key="' . $kBase . '.q">' . ($faq['q'] ?? '') . '</span>',
        '<span data-cms-key="' . $kBase . '.a">' . ($faq['a'] ?? '') . '</span>'
    );
}
$faqSection = '<h2 data-cms-key="' . $kp . '.faq.title">' . ($C['faq']['title'] ?? '') . '</h2>' .
    '<div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">' . $faqItemsHtml . '</div></div></div>';

$ctaButtonsKeyed = [];
foreach ((is_array($C['cta']['buttons'] ?? null) ? $C['cta']['buttons'] : []) as $i => $btn) {
    if (!is_array($btn)) continue;
    $b = $btn;
    $b['label'] = '<span data-cms-key="' . $kp . '.cta.buttons.' . $i . '.label">' . ($btn['label'] ?? '') . '</span>';
    $ctaButtonsKeyed[] = $b;
}
$ctaHtml = renderCta(
    '<span data-cms-key="' . $kp . '.cta.title">' . ($C['cta']['title'] ?? '') . '</span>',
    '<span data-cms-key="' . $kp . '.cta.text">' . ($C['cta']['text'] ?? '') . '</span>',
    $ctaButtonsKeyed
);

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' . $intro . $stepsHtml . $faqSection . $ctaHtml .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/poukazy', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'og_image' => $C['seo']['og_image'] ?? null,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.vouchers'), 'url' => siteCanonicalUrl('/poukazy')],
    ],
]);
