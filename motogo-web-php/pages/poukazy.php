<?php
// ===== MotoGo24 Web PHP — Stránka Poukazy (info) =====

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'Poukazy']);

$intro = '<section aria-labelledby="title"><h1>Kup dárkový poukaz – daruj zážitek na dvou kolech!</h1>' .
    '<div class="gr2"><div>' .
    '<p>Hledáš originální dárek pro partnera, kamaráda nebo tátu?</p><p>&nbsp;</p>' .
    '<p>Naše <strong>dárkové poukazy na pronájem motorky</strong> od Motogo24 – <strong>půjčovna motorek Vysočina</strong> – potěší začátečníky i zkušené jezdce.</p><p>&nbsp;</p>' .
    '<p>Vyber hodnotu poukazu nebo konkrétní motorku a daruj svobodu na dvou kolech.</p><p>&nbsp;</p>' .
    '<p class="cta"><a aria-label="Objednat dárkový poukaz na pronájem motorky v půjčovně Motogo24" class="btn btngreen" href="' . BASE_URL . '/koupit-darkovy-poukaz">OBJEDNAT DÁRKOVÝ POUKAZ</a></p>' .
    '<p>&nbsp;</p>' .
    '</div><div>' .
    '<img alt="Dárkový poukaz" class="imgres" loading="lazy" src="gfx/darkovy-poukaz.jpg">' .
    '</div></div></section>';

$steps = '<section aria-labelledby="content"><div class="gr3">' .
    renderWbox('gfx/ico-step1.svg', '1. Vyber', 'Vybereš si hodnotu poukazu nebo konkrétní motorku.') .
    renderWbox('gfx/ico-step2.svg', '2. Zaplať', 'Zaplatíš online.') .
    renderWbox('gfx/ico-step3.svg', '3. Vyzvedni', 'Poukaz po zaplacení přistane do tvé e-mailové schránky.') .
    '</div>' .
    '<p>&nbsp;</p>' .
    '<p>Všechny vouchery mají <strong>platnost 3 roky</strong> od data vystavení. <strong>Obdarovaný si sám zvolí termín výpůjčky</strong>, který se mu hodí. Může nás kontaktovat e-mailem, telefonicky nebo přes sociální sítě.</p>' .
    '<p>&nbsp;</p><p>&nbsp;</p>' .
    '<div class="gr2"><div>' .
    '<h2>Proč zakoupit poukaz</h2><ul>' .
    '<li><strong>Flexibilní volba</strong> – hodnota poukazu nebo konkrétní motorka.</li>' .
    '<li><strong>Platnost 3 roky</strong> – obdarovaný si sám vybere termín.</li>' .
    '<li><strong>Bez kauce</strong> – férové podmínky bez zbytečných překážek.</li>' .
    '<li><strong>Výbava v ceně</strong> – helma, bunda, kalhoty a rukavice zdarma.</li>' .
    '<li><strong>Nonstop provoz</strong> – vyzvednutí i vrácení kdykoli v den výpůjčky.</li>' .
    '<li><strong>Online objednávka</strong> – poukaz ti po zaplacení přijde e-mailem.</li></ul>' .
    '</div><div>' .
    '<h2>Jak poukaz využít</h2><ul>' .
    '<li><strong>Cestovní motorky</strong> – víkendový roadtrip po Vysočině i celé ČR.</li>' .
    '<li><strong>Sportovní motorky</strong> – adrenalinová jízda v zatáčkách.</li>' .
    '<li><strong>Enduro</strong> – lehký terén a dobrodružství mimo hlavní cesty.</li>' .
    '<li><strong>Dětské motorky</strong> – první jízdy pro malé jezdce pod dohledem.</li></ul>' .
    '</div></div>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . '/katalog">ZOBRAZIT KATALOG MOTOREK</a></p>' .
    '<p>&nbsp;</p><p>&nbsp;</p></section>';

$faqItems = [
    ['q' => 'Jaká je platnost dárkového poukazu?', 'a' => 'Všechny vouchery mají platnost <strong>3 roky</strong> od data vystavení. Termín výpůjčky si obdarovaný volí sám.'],
    ['q' => 'Jak poukaz doručíte?', 'a' => '<strong>Okamžitě e-mailem</strong> po úhradě. Na požádání umíme připravit i dárkový tisk v provozovně.'],
    ['q' => 'Musí obdarovaný skládat kauci?', 'a' => 'Ne. <strong>Půjčujeme bez kauce</strong>. Podmínky jsou jasné a férové, výbava řidiče je v ceně.'],
    ['q' => 'Lze změnit termín uplatnění?', 'a' => 'Ano, <strong>termín lze po domluvě změnit</strong> dle dostupnosti konkrétní motorky v našem kalendáři.'],
    ['q' => 'Na jaké motorky lze voucher uplatnit?', 'a' => 'Na <strong>cestovní, sportovní, enduro i dětské motorky</strong> v nabídce Motogo24 – podle zvolené hodnoty poukazu.'],
];
$faqHtml = '';
foreach ($faqItems as $faq) { $faqHtml .= renderFaqItem($faq['q'], $faq['a']); }

$faqSection = '<h2>Často kladené dotazy k dárkovým poukazům</h2>' .
    '<div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">' .
    $faqHtml . '</div></div></div>';

$cta = renderCta('Dárkový poukaz na pronájem motorky – Vysočina',
    'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop provozem</strong>, <strong>bez kauce</strong> a <strong>výbavou v ceně</strong>. Dárkový voucher je ideální volba, jak darovat <em>motorbike rental</em> zážitek – od <strong>cestovních</strong> přes <strong>sportovní</strong> až po <strong>enduro</strong> a <strong>dětské motorky</strong>.',
    [['label' => 'OBJEDNAT VOUCHER', 'href' => '/koupit-darkovy-poukaz', 'cls' => 'btndark pulse']]);

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' . $intro . $steps . $faqSection . $cta .
    '</div></div></main>';

renderPage('Půjčovna motorek Vysočina - Poukazy', $content, '/poukazy', [
    'description' => 'Kupte dárkový poukaz na pronájem motorky. Platnost 3 roky, bez kauce, výbava v ceně. Elektronický i tištěný poukaz. Online objednávka.',
    'keywords' => 'dárkový poukaz motorka, voucher pronájem motorky, dárek pro motorkáře, poukaz Motogo24, půjčovna motorek Vysočina',
    'og_image' => 'https://motogo24.cz/gfx/darkovy-poukaz.jpg',
]);
