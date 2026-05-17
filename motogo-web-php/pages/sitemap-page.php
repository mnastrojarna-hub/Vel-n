<?php
// ===== MotoGo24 Web PHP — Mapa stránek =====
// Odpovídá pages-cms.js (route /mapa-stranek)

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('breadcrumb.sitemap')]);

$sb = new SupabaseClient();
$smDefaults = [
    'intro' => 'Tato mapa stránek slouží jako přehled <strong>celého webu MotoGo24</strong> — najdete tu odkazy na katalog motorek k pronájmu, postup půjčení krok za krokem, ceník, dárkové poukazy, blog s tipy pro motorkáře, e-shop s motorkářskými doplňky i právní dokumenty.',
    'outro' => [
        'title' => 'Hledáte něco konkrétního?',
        'body1' => 'Pokud nemůžete najít to, co hledáte, zkuste začít na <strong>domovské stránce</strong> nebo si projděte sekci <a href="/jak-pujcit">Jak si půjčit motorku</a>, kde jsou všechny informace ke způsobu rezervace, převzetí, vrácení i co je v ceně nájmu. Pro rychlou orientaci nabízíme také <a href="/jak-pujcit/faq">časté dotazy</a> a podrobný popis u každé motorky v <a href="/katalog">katalogu</a>.',
        'body2' => 'Stále se neorientujete? Ozvěte se nám telefonicky, e-mailem nebo přes naše sociální sítě — najdete je v sekci <a href="/kontakt">Kontakt</a>. Jsme dostupní nonstop a rádi poradíme s výběrem motorky, termínem nebo s objednávkou dárkového poukazu.',
    ],
];
$SMC = $sb->siteContent('mapa_stranek', $smDefaults);
$smIntro = $SMC['intro'] ?? $smDefaults['intro'];
$smOutroT = $SMC['outro']['title'] ?? $smDefaults['outro']['title'];
$smOutroB1 = $SMC['outro']['body1'] ?? $smDefaults['outro']['body1'];
$smOutroB2 = $SMC['outro']['body2'] ?? $smDefaults['outro']['body2'];

$links = [
    ['href' => '/', 'label' => t('sitemap.links.home')],
    ['href' => '/pujcovna-motorek', 'label' => t('sitemap.links.rental')],
    ['href' => '/katalog', 'label' => t('sitemap.links.catalog')],
    ['href' => '/katalog/cestovni', 'label' => t('sitemap.links.touring')],
    ['href' => '/katalog/naked', 'label' => t('sitemap.links.naked')],
    ['href' => '/katalog/supermoto', 'label' => t('sitemap.links.supermoto')],
    ['href' => '/katalog/detske', 'label' => t('sitemap.links.kids')],
    // /jak-pujcit zrušena (301 → /jak-pujcit/postup), v mapě stránek ji
    // proto nelinkujeme — uživatel jde rovnou na konkrétní podstránky.
    ['href' => '/jak-pujcit/postup', 'label' => t('sitemap.links.process')],
    ['href' => '/jak-pujcit/prevzeti', 'label' => t('sitemap.links.pickup')],
    ['href' => '/jak-pujcit/vraceni-pujcovna', 'label' => t('sitemap.links.returnHome')],
    ['href' => '/jak-pujcit/vraceni-jinde', 'label' => t('sitemap.links.returnElsewhere')],
    ['href' => '/jak-pujcit/co-v-cene', 'label' => t('sitemap.links.price')],
    ['href' => '/jak-pujcit/pristaveni', 'label' => t('sitemap.links.delivery')],
    ['href' => '/jak-pujcit/dokumenty', 'label' => t('sitemap.links.documents')],
    ['href' => '/jak-pujcit/faq', 'label' => t('sitemap.links.faq')],
    ['href' => '/poukazy', 'label' => t('sitemap.links.vouchers')],
    ['href' => '/blog', 'label' => t('sitemap.links.blog')],
    ['href' => '/kontakt', 'label' => t('sitemap.links.contact')],
    ['href' => '/rezervace', 'label' => t('sitemap.links.reservation')],
    // SEO: linkujeme primo na cilove /dokumenty/<slug> URL aby crawler nemusel
    // sledovat 301 redirect (Seobility hlasil 'Internal redirects' z mapa-stranek).
    ['href' => '/dokumenty/obchodni-podminky', 'label' => t('sitemap.links.terms')],
    ['href' => '/dokumenty/zasady-ochrany-osobnich-udaju', 'label' => t('sitemap.links.gdpr')],
    ['href' => '/dokumenty/smlouva-o-pronajmu', 'label' => t('sitemap.links.contract')],
];

$html = '<ul>';
foreach ($links as $l) {
    $html .= '<li><a href="' . BASE_URL . $l['href'] . '">' . htmlspecialchars($l['label']) . '</a></li>';
}
$html .= '</ul>';

$smOutroHtml = '<section class="sitemap-outro">'
    . '<h2 data-cms-key="web.mapa_stranek.outro.title">' . htmlspecialchars($smOutroT) . '</h2>'
    . '<p data-cms-key="web.mapa_stranek.outro.body1">' . $smOutroB1 . '</p>'
    . '<p data-cms-key="web.mapa_stranek.outro.body2">' . $smOutroB2 . '</p>'
    . '</section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>' . te('sitemap.h1') . '</h1>'
    . '<p data-cms-key="web.mapa_stranek.intro">' . $smIntro . '</p>'
    . $html
    . $smOutroHtml
    . '</div></div></main>';

renderPage(t('sitemap.title'), $content, '/mapa-stranek', [
    // Kratsi description (puvodne 180 znaku → 1156 px nad limit 1000 px).
    'description' => 'Mapa stránek MotoGo24 — přehled celého webu půjčovny motorek na Vysočině: katalog, postup půjčení, FAQ, dokumenty a kontakty.',
]);
