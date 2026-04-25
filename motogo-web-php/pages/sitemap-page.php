<?php
// ===== MotoGo24 Web PHP — Mapa stránek =====
// Odpovídá pages-cms.js (route /mapa-stranek)

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('breadcrumb.sitemap')]);

$links = [
    ['href' => '/', 'label' => t('sitemap.links.home')],
    ['href' => '/pujcovna-motorek', 'label' => t('sitemap.links.rental')],
    ['href' => '/katalog', 'label' => t('sitemap.links.catalog')],
    ['href' => '/katalog/cestovni', 'label' => t('sitemap.links.touring')],
    ['href' => '/katalog/naked', 'label' => t('sitemap.links.naked')],
    ['href' => '/katalog/supermoto', 'label' => t('sitemap.links.supermoto')],
    ['href' => '/katalog/detske', 'label' => t('sitemap.links.kids')],
    ['href' => '/jak-pujcit', 'label' => t('sitemap.links.howto')],
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
    ['href' => '/obchodni-podminky', 'label' => t('sitemap.links.terms')],
    ['href' => '/gdpr', 'label' => t('sitemap.links.gdpr')],
    ['href' => '/smlouva', 'label' => t('sitemap.links.contract')],
];

$html = '<ul>';
foreach ($links as $l) {
    $html .= '<li><a href="' . BASE_URL . $l['href'] . '">' . htmlspecialchars($l['label']) . '</a></li>';
}
$html .= '</ul>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>' . te('sitemap.h1') . '</h1>' . $html . '</div></div></main>';

renderPage(t('sitemap.title'), $content, '/mapa-stranek');
