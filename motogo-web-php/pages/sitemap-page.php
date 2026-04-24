<?php
// ===== MotoGo24 Web PHP — Mapa stránek =====
// Odpovídá pages-cms.js (route /mapa-stranek)

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'Mapa stránek']);

$links = [
    ['href' => '/', 'label' => 'Úvodní stránka'],
    ['href' => '/pujcovna-motorek', 'label' => 'Půjčovna motorek'],
    ['href' => '/katalog', 'label' => 'Katalog motorek'],
    ['href' => '/katalog/cestovni', 'label' => '  Cestovní motorky'],
    ['href' => '/katalog/naked', 'label' => '  Naked motorky'],
    ['href' => '/katalog/supermoto', 'label' => '  Supermoto motorky'],
    ['href' => '/katalog/detske', 'label' => '  Dětské motorky'],
    ['href' => '/jak-pujcit', 'label' => 'Jak si půjčit motorku'],
    ['href' => '/jak-pujcit/postup', 'label' => '  Postup půjčení'],
    ['href' => '/jak-pujcit/pristaveni', 'label' => '  Přistavení motocyklu'],
    ['href' => '/jak-pujcit/vyzvednuti', 'label' => '  Vyzvednutí motocyklu'],
    ['href' => '/jak-pujcit/co-v-cene', 'label' => '  Co je v ceně'],
    ['href' => '/jak-pujcit/dokumenty', 'label' => '  Dokumenty a návody'],
    ['href' => '/jak-pujcit/faq', 'label' => '  Často kladené dotazy'],
    ['href' => '/poukazy', 'label' => 'Poukazy'],
    ['href' => '/blog', 'label' => 'Blog'],
    ['href' => '/kontakt', 'label' => 'Kontakt'],
    ['href' => '/rezervace', 'label' => 'Rezervace'],
    ['href' => '/obchodni-podminky', 'label' => 'Obchodní podmínky'],
    ['href' => '/gdpr', 'label' => 'GDPR'],
    ['href' => '/smlouva', 'label' => 'Smlouva o pronájmu'],
];

$html = '<ul>';
foreach ($links as $l) {
    $html .= '<li><a href="' . BASE_URL . $l['href'] . '">' . htmlspecialchars($l['label']) . '</a></li>';
}
$html .= '</ul>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>Mapa stránek</h1>' . $html . '</div></div></main>';

renderPage('Mapa stránek | MotoGo24', $content, '/mapa-stranek');
