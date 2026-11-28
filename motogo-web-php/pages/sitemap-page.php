<?php
// ===== MotoGo24 Web PHP — Mapa stránek =====
// Odpovídá pages-cms.js (route /mapa-stranek)

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('breadcrumb.sitemap')]);

$sb = new SupabaseClient();
$smDefaults = [
    'intro' => 'Tato mapa stránek slouží jako přehled <strong>celého webu MotoGo24</strong> — najdeš tu odkazy na katalog motorek k pronájmu, postup půjčení krok za krokem, ceník, dárkové poukazy, blog s tipy pro motorkáře, e-shop s motorkářskými doplňky i právní dokumenty.',
    'outro' => [
        'title' => 'Hledáš něco konkrétního?',
        'body1' => 'Pokud nemůžeš najít to, co hledáš, zkus začít na <strong>domovské stránce</strong> nebo si projdi sekci <a href="/jak-pujcit">Jak si půjčit motorku</a>, kde jsou všechny informace ke způsobu rezervace, převzetí, vrácení i co je v ceně nájmu. Pro rychlou orientaci nabízíme také <a href="/jak-pujcit/faq">časté dotazy</a> a podrobný popis u každé motorky v <a href="/katalog">katalogu</a>.',
        // telefon a e-mail Po–Pá 8–17 (kontakt, patička); nonstop je jen výdej motorek a AI asistent
        'body2' => 'Stále se neorientuješ? Ozvi se nám telefonicky, e-mailem nebo přes naše sociální sítě — najdeš je v sekci <a href="/kontakt">Kontakt</a>. Telefon a e-mail vyřizujeme Po–Pá 8–17, AI asistent na webu ti poradí kdykoli — s výběrem motorky, termínem i s objednávkou dárkového poukazu.',
    ],
];
$SMC = $sb->siteContent('mapa_stranek', $smDefaults);
$smIntro = $SMC['intro'] ?? $smDefaults['intro'];
$smOutroT = $SMC['outro']['title'] ?? $smDefaults['outro']['title'];
$smOutroB1 = $SMC['outro']['body1'] ?? $smDefaults['outro']['body1'];
$smOutroB2 = $SMC['outro']['body2'] ?? $smDefaults['outro']['body2'];
// /jak-pujcit je jen 301 na /jak-pujcit/postup — odkaz rovnou na cíl (i v textech z CMS / překladů)
$smOutroB1 = str_replace('href="/jak-pujcit"', 'href="/jak-pujcit/postup"', (string)$smOutroB1);
$smOutroB2 = str_replace('href="/jak-pujcit"', 'href="/jak-pujcit/postup"', (string)$smOutroB2);

// Kategorie katalogu jen ty, které ve flotile reálně mají motorky — prázdná kategorie (dnes /katalog/sportovni)
// je noindex (pages/katalog.php) a není ani v sitemap.xml (sitemap.php), tak na ni neodkazujeme ani odsud.
// Při výpadku dat (žádné motorky) zůstanou odkazy všechny.
require_once __DIR__ . '/katalog-v2-lib.php';
$smMotos = $sb->fetchMotos();
$smMotos = is_array($smMotos) ? $smMotos : [];
$smHasMotos = function ($href) use ($smMotos) {
    if (!$smMotos || !preg_match('#^/katalog/([a-z]+)$#', $href, $mm)) return true;
    foreach ($smMotos as $m) { if (katalogCategoryMatch($m, $mm[1])) return true; }
    return false;
};

$links = [
    ['href' => '/', 'label' => t('sitemap.links.home')],
    ['href' => '/pujcovna-motorek', 'label' => t('sitemap.links.rental')],
    ['href' => '/katalog', 'label' => t('sitemap.links.catalog')],
    ['href' => '/katalog/cestovni', 'label' => t('sitemap.links.touring')],
    ['href' => '/katalog/naked', 'label' => t('sitemap.links.naked')],
    ['href' => '/katalog/supermoto', 'label' => t('sitemap.links.supermoto')],
    ['href' => '/katalog/detske', 'label' => t('sitemap.links.kids')],
    ['href' => '/katalog/sportovni', 'label' => '  ' . t('menu.catalog.sport')],
    ['href' => '/katalog/chopper', 'label' => '  ' . t('menu.catalog.chopper')],
    ['href' => '/katalog/scootery', 'label' => '  ' . t('menu.catalog.scooters')],
    ['href' => '/katalog/ostatni', 'label' => '  ' . t('menu.catalog.other')],
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
    ['href' => '/pobocky', 'label' => t('menu.branches')],
    ['href' => '/pobocky/mezna', 'label' => t('menu.branchMezna')],
    ['href' => '/pobocky/velke-nemcice', 'label' => t('menu.branchNemcice')],
    ['href' => '/rezervace', 'label' => t('sitemap.links.reservation')],
    // SEO: linkujeme primo na cilove /dokumenty/<slug> URL aby crawler nemusel
    // sledovat 301 redirect (Seobility hlasil 'Internal redirects' z mapa-stranek).
    ['href' => '/dokumenty/obchodni-podminky', 'label' => t('sitemap.links.terms')],
    ['href' => '/dokumenty/zasady-ochrany-osobnich-udaju', 'label' => t('sitemap.links.gdpr')],
    ['href' => '/dokumenty/smlouva-o-pronajmu', 'label' => t('sitemap.links.contract')],
];
// česky je /pujcovna-motorek 301 na úvodní stránku (index.php) — odkaz na ni už je první položkou
$smCs = (function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs') === 'cs';
$links = array_values(array_filter($links, function ($l) use ($smHasMotos, $smCs) { return $smHasMotos($l['href']) && !($smCs && $l['href'] === '/pujcovna-motorek'); }));
if (function_exists('webShopVisible') && webShopVisible()) $links[] = ['href' => '/eshop', 'label' => t('menu.shop')];
$links[] = ['href' => '/partneri', 'label' => t('footer.partners')];
// SEO stránky poboček (Motopůjčovna Brno / Vysočina) — existují jen česky
if (i18nDetectLanguage() === 'cs') {
    require_once __DIR__ . '/../data/seo-pobocky.php';
    foreach (seoPobockyPages() as $p) $links[] = ['href' => $p['path'], 'label' => $p['menu']];
}

$html = '<ul>';
foreach ($links as $l) {
    $html .= '<li><a href="' . BASE_URL . $l['href'] . '">' . htmlspecialchars($l['label']) . '</a></li>';
}
$html .= '</ul>';

$smOutroHtml = '<section class="sitemap-outro">'
    . '<h2 data-cms-key="web.mapa_stranek.outro.title">' . sanitizeHtml($smOutroT) . '</h2>'
    . '<p data-cms-key="web.mapa_stranek.outro.body1">' . sanitizeHtml($smOutroB1) . '</p>'
    . '<p data-cms-key="web.mapa_stranek.outro.body2">' . sanitizeHtml($smOutroB2) . '</p>'
    . '</section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>' . te('sitemap.h1') . '</h1>'
    . '<p data-cms-key="web.mapa_stranek.intro">' . sanitizeHtml($smIntro) . '</p>'
    . $html
    . $smOutroHtml
    . '</div></div></main>';

renderPage(t('sitemap.title'), $content, '/mapa-stranek', [
    // Kratsi description (puvodne 180 znaku → 1156 px nad limit 1000 px).
    'description' => t('sitemap.description'),
]);
