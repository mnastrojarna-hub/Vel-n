<?php
// ===== MotoGo24 Web PHP — Jak si půjčit motorku (overview, CMS-driven) =====

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Jak si půjčit motorku | MotoGo24',
        'description' => 'Jak si půjčit motorku v Motogo24. Jednoduchý postup: výběr, rezervace, převzetí. Bez kauce, výbava v ceně, nonstop provoz.',
        'keywords' => 'jak si půjčit motorku, postup půjčení, rezervace motorky, pronájem motorek Vysočina',
    ],
    'h1' => 'Jak si půjčit motorku',
    'intro' => 'V <strong>Motogo24 – půjčovna motorek na Vysočině</strong> je půjčení jednoduché, rychlé a férové.',
    'links' => [
        ['href' => '/jak-pujcit/postup', 'label' => 'Postup půjčení motorky'],
        ['href' => '/jak-pujcit/prevzeti', 'label' => 'Převzetí v půjčovně'],
        ['href' => '/jak-pujcit/vraceni-pujcovna', 'label' => 'Vrácení motocyklu v půjčovně'],
        ['href' => '/jak-pujcit/vraceni-jinde', 'label' => 'Vrácení motorky jinde'],
        ['href' => '/jak-pujcit/co-v-cene', 'label' => 'Co je v ceně nájmu'],
        ['href' => '/jak-pujcit/pristaveni', 'label' => 'Přistavení motocyklu'],
        ['href' => '/jak-pujcit/dokumenty', 'label' => 'Dokumenty a návody'],
        ['href' => '/jak-pujcit/faq', 'label' => 'Často kladené dotazy'],
    ],
];

$C = $sb->siteContent('jak_pujcit', $defaults);

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'Jak si půjčit motorku']);

$linksHtml = '<div class="gr4 jp-tiles">';
foreach ($C['links'] as $l) {
    $linksHtml .= '<a class="jp-tile" href="' . BASE_URL . $l['href'] . '">' . htmlspecialchars($l['label']) . '</a>';
}
$linksHtml .= '</div>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>' . $C['h1'] . '</h1>' .
    '<p>' . $C['intro'] . '</p>' .
    '<p>&nbsp;</p>' . $linksHtml .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/jak-pujcit', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'],
    ],
]);
