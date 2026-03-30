<?php
// ===== MotoGo24 Web PHP — Jak si půjčit motorku =====

echo renderHead('Jak si půjčit motorku | MotoGo24', 'Jak si půjčit motorku v půjčovně Motogo24 na Vysočině. Jednoduchý postup, bez kauce, výbava v ceně, nonstop provoz.');
echo renderHeader();

$bc = renderBreadcrumb([['href'=>'/', 'label'=>'Domů'], 'Jak si půjčit motorku']);

$links = [
    ['href'=>'/jak-pujcit/postup', 'label'=>'Postup půjčení motorky'],
    ['href'=>'/jak-pujcit/pristaveni', 'label'=>'Přistavení motocyklu'],
    ['href'=>'/jak-pujcit/vyzvednuti', 'label'=>'Vyzvednutí motocyklu'],
    ['href'=>'/jak-pujcit/co-v-cene', 'label'=>'Co je v ceně'],
    ['href'=>'/jak-pujcit/dokumenty', 'label'=>'Dokumenty a návody'],
    ['href'=>'/jak-pujcit/faq', 'label'=>'Často kladené dotazy'],
];

$linksHtml = '<div class="gr3">';
foreach ($links as $l) {
    $linksHtml .= '<a class="gbox" href="' . $l['href'] . '"><div class="gr2"><div><h3>' . $l['label'] . '</h3></div></div></a>';
}
$linksHtml .= '</div>';

echo '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>Jak si půjčit motorku</h1>' .
    '<p>V <strong>Motogo24 – půjčovna motorek na Vysočině</strong> je půjčení jednoduché, rychlé a férové.</p>' .
    '<p>&nbsp;</p>' . $linksHtml .
    '</div></div></main>';

echo renderFooter();
echo renderPageEnd();
