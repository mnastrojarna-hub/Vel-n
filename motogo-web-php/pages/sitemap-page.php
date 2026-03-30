<?php
// ===== MotoGo24 Web PHP — Mapa stránek =====

echo renderHead('Mapa stránek – Motogo24', 'Přehled všech stránek webu půjčovny motorek Motogo24.');
echo renderHeader();

$bc = renderBreadcrumb([['href'=>'/', 'label'=>'Domů'], 'Mapa stránek']);

$links = [
    ['href'=>'/', 'label'=>'Úvodní stránka'],
    ['href'=>'/pujcovna-motorek', 'label'=>'Půjčovna motorek'],
    ['href'=>'/katalog', 'label'=>'Katalog motorek'],
    ['href'=>'/katalog/cestovni', 'label'=>'Cestovní motorky'],
    ['href'=>'/katalog/detske', 'label'=>'Dětské motorky'],
    ['href'=>'/jak-pujcit', 'label'=>'Jak si půjčit motorku'],
    ['href'=>'/jak-pujcit/postup', 'label'=>'Postup půjčení'],
    ['href'=>'/jak-pujcit/pristaveni', 'label'=>'Přistavení motocyklu'],
    ['href'=>'/jak-pujcit/vyzvednuti', 'label'=>'Vyzvednutí motocyklu'],
    ['href'=>'/jak-pujcit/co-v-cene', 'label'=>'Co je v ceně'],
    ['href'=>'/jak-pujcit/dokumenty', 'label'=>'Dokumenty a návody'],
    ['href'=>'/jak-pujcit/faq', 'label'=>'Často kladené dotazy'],
    ['href'=>'/poukazy', 'label'=>'Dárkové poukazy'],
    ['href'=>'/blog', 'label'=>'Blog'],
    ['href'=>'/kontakt', 'label'=>'Kontakt'],
    ['href'=>'/rezervace', 'label'=>'Rezervace'],
    ['href'=>'/obchodni-podminky', 'label'=>'Obchodní podmínky'],
    ['href'=>'/gdpr', 'label'=>'GDPR'],
    ['href'=>'/smlouva', 'label'=>'Smlouva o pronájmu'],
];

$listHtml = '<ul>';
foreach ($links as $link) {
    $listHtml .= '<li><a href="' . $link['href'] . '">' . $link['label'] . '</a></li>';
}
$listHtml .= '</ul>';

echo '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<h1>Mapa stránek</h1>' .
    $listHtml .
    '</div></div></main>';

echo renderFooter();
echo renderPageEnd();
