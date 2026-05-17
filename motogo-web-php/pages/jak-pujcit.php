<?php
// ===== MotoGo24 Web PHP — Jak si půjčit motorku (overview, CMS-driven) =====

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Jak si půjčit motorku | MotoGo24',
        'description' => 'Jak si půjčit motorku v Motogo24. Jednoduchý postup: výběr, rezervace, převzetí. Bez kauce, výbava v ceně, nonstop provoz.',
        'keywords' => 'motopůjčovna',
    ],
    'h1' => 'Jak si půjčit motorku',
    'intro' => 'V <strong>Motogo24 – půjčovna motorek na Vysočině</strong> je půjčení jednoduché, rychlé a férové.',
    'outro' => [
        'title' => 'Krok za krokem k vaší motorce',
        'body1' => 'Půjčení motorky v MotoGo24 jsme se snažili připravit tak, aby zabralo co nejméně času a nepřinášelo žádná nepříjemná překvapení. Vyberete si stroj v katalogu, online si rezervujete termín, zaplatíte přes platební bránu a v dohodnutý čas si motorku vyzvednete v naší půjčovně v Pelhřimově — nebo si ji necháte přistavit kamkoliv na Vysočině či po ČR. Po skončení rezervace ji jednoduše vrátíte zpět do půjčovny, nebo nám předáte na předem domluveném místě.',
        'body2' => 'Půjčujeme <strong>bez kauce</strong>, výbava pro řidiče (helma, bunda, kalhoty a rukavice) je <strong>vždy v ceně</strong> a otevřeno máme <strong>nonstop</strong> — pasuje to i lidem se směnným provozem nebo víkendovým plánem. Pokud cestujete s motorkou do zahraničí, dostanete s ní zelenou kartu a všechny potřebné dokumenty. V sekcích níže najdete podrobný postup pro každou fázi: výběr, převzetí, vrácení, dokumenty i odpovědi na nejčastější dotazy.',
    ],
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

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('menu.howto')]);

$linksHtml = '<div class="gr4 jp-tiles">';
foreach ($C['links'] as $i => $l) {
    $linksHtml .= '<a class="jp-tile" href="' . BASE_URL . $l['href'] . '" data-cms-key="web.jak_pujcit.links.' . $i . '.label">' . htmlspecialchars($l['label']) . '</a>';
}
$linksHtml .= '</div>';

$outroTitle = $C['outro']['title'] ?? $defaults['outro']['title'];
$outroBody1 = $C['outro']['body1'] ?? $defaults['outro']['body1'];
$outroBody2 = $C['outro']['body2'] ?? $defaults['outro']['body2'];

$outroHtml = '<section class="jp-outro">'
    . '<h2 data-cms-key="web.jak_pujcit.outro.title">' . htmlspecialchars($outroTitle) . '</h2>'
    . '<p data-cms-key="web.jak_pujcit.outro.body1">' . $outroBody1 . '</p>'
    . '<p data-cms-key="web.jak_pujcit.outro.body2">' . $outroBody2 . '</p>'
    . '</section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1 data-cms-key="web.jak_pujcit.h1">' . $C['h1'] . '</h1>' .
    '<p data-cms-key="web.jak_pujcit.intro">' . $C['intro'] . '</p>' .
    '<p>&nbsp;</p>' . $linksHtml .
    $outroHtml .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/jak-pujcit', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.howto'), 'url' => siteCanonicalUrl('/jak-pujcit')],
    ],
]);
