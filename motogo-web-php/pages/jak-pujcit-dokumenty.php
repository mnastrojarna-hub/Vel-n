<?php
// ===== MotoGo24 Web PHP — Dokumenty a návody (CMS-driven) =====

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Dokumenty a návody | MotoGo24',
        'description' => 'Nájemní smlouva, dokumenty a podmínky pronájmu motorky. Bez kauce, jasná pravidla, pojištění v ceně. Potřebné doklady pro půjčení.',
        'keywords' => 'nájemní smlouva motorka, dokumenty k půjčení, podmínky pronájmu, pojištění motorky',
    ],
    'h1' => 'Nájemní smlouva a kauce – férové podmínky bez zálohy',
    'intro' => 'V <strong>Motogo24</strong> klademe důraz na jednoduchost a férovost. Půjčujeme <strong>bez kauce</strong>, s <strong>jasnou nájemní smlouvou</strong>, <strong>pojištěním v ceně</strong> a <strong>výbavou pro řidiče</strong>.',
    'top_cta' => ['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace'],
    'summary' => [
        'title' => 'Shrnutí hlavních bodů',
        'items' => [
            ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'Bez kauce / zálohy', 'text' => 'motorku půjčujeme bez blokace peněz'],
            ['icon' => 'gfx/ico-pojisteni.svg', 'title' => 'Pojištění', 'text' => 'v ceně (povinné ručení; havarijní dle konkrétního modelu a podmínek)'],
            ['icon' => 'gfx/ico-vybava.svg', 'title' => 'Výbava pro řidiče', 'text' => 'v ceně (helma, bunda, kalhoty, rukavice)'],
            ['icon' => 'gfx/ico-nonstop.svg', 'title' => 'Nonstop provoz', 'text' => 'převzetí a vrácení kdykoli v den výpůjčky'],
            ['icon' => 'gfx/ico-jasna-pravidla.svg', 'title' => 'Jasná pravidla užívání', 'text' => 'doma i v zahraničí (podle zelené karty)'],
            ['icon' => 'gfx/ico-bezskryte.svg', 'title' => 'Žádné skryté poplatky', 'text' => 'vše je uvedeno níže a ve smlouvě'],
        ],
    ],
    'required_docs' => [
        'title' => 'Co potřebujete k uzavření smlouvy',
        'items' => [
            '<strong>Občanský průkaz / pas</strong>',
            '<strong>Řidičský průkaz</strong> odpovídající skupiny',
            '<strong>Věk</strong> min. 18 let',
            '<strong>Kontakty</strong> (telefon, e-mail)',
        ],
    ],
    'payments' => [
        'title' => 'Platby, storno a poplatky',
        'headers' => ['Položka', 'Podmínky'],
        'rows' => [
            ['<strong>Platba nájemného</strong>', 'Online předem.'],
            ['<strong>Storno rezervace</strong>', 'Lze bezplatně do předem domluveného času.'],
            ['<strong>Palivo & čištění</strong>', 'Vrácení bez povinnosti dotankovat a mýt.'],
            ['<strong>Přistavení / svoz</strong>', 'Dle ceníku přistavení.'],
            ['<strong>Pozdní vrácení</strong>', 'Při zpoždění účtujeme dle domluvy.'],
        ],
    ],
    'usage' => [
        'title' => 'Užívání motorky a odpovědnost',
        'items' => [
            'Jezděte v <strong>souladu s předpisy</strong>',
            'Za <strong>pokuty a přestupky</strong> odpovídá nájemce',
            '<strong>Zahraničí</strong>: možné; řiďte se územní platností pojištění',
            'V případě <strong>nehody nebo poruchy</strong> postupujte dle pokynů',
            '<strong>Úpravy motorky</strong> bez souhlasu nejsou dovoleny',
        ],
    ],
    'handover' => [
        'title' => 'Předání a vrácení',
        'items' => [
            '<strong>Převzetí</strong> v Pelhřimově nebo <a href="/jak-pujcit/pristaveni">přistavení</a>',
            'Při předání obdržíte <strong>klíče, výbavu a dokumenty</strong>',
            '<strong>Vrácení</strong> kdykoli během posledního dne výpůjčky',
        ],
    ],
    'cta' => [
        'title' => 'Nájemní smlouva bez kauce – půjčovna motorek Vysočina',
        'text' => 'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s férovými podmínkami.',
        'buttons' => [['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
    ],
];

$C = $sb->siteContent('jak_pujcit_dokumenty', $defaults);

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Dokumenty a návody']);

$summaryHtml = '<section><h2>' . $C['summary']['title'] . '</h2><div class="gr6">';
foreach ($C['summary']['items'] as $s) { $summaryHtml .= renderWbox($s['icon'], $s['title'], $s['text']); }
$summaryHtml .= '</div></section>';

$reqLis = '';
foreach ($C['required_docs']['items'] as $i) { $reqLis .= '<li>' . $i . '</li>'; }
$paymentTable = renderTable($C['payments']['headers'], $C['payments']['rows']);
$docsHtml = '<section><h2>' . $C['required_docs']['title'] . '</h2><ul>' . $reqLis . '</ul>' .
    '<p>&nbsp;</p><h2>' . $C['payments']['title'] . '</h2>' . $paymentTable . '</section>';

$useLis = '';
foreach ($C['usage']['items'] as $i) { $useLis .= '<li>' . $i . '</li>'; }
$handLis = '';
foreach ($C['handover']['items'] as $i) {
    // převést relativní /jak-pujcit/... na BASE_URL
    $html = preg_replace_callback('/href="(\/[^"]+)"/', function ($m) { return 'href="' . BASE_URL . $m[1] . '"'; }, $i);
    $handLis .= '<li>' . $html . '</li>';
}
$rightsHtml = '<section><div class="gr2">' .
    '<div><h2>' . $C['usage']['title'] . '</h2><ul>' . $useLis . '</ul></div>' .
    '<div><h2>' . $C['handover']['title'] . '</h2><ul>' . $handLis . '</ul></div>' .
    '</div></section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<section><h1>' . $C['h1'] . '</h1><p>' . $C['intro'] . '</p>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $C['top_cta']['href'] . '">' . $C['top_cta']['label'] . '</a></p></section>' .
    $summaryHtml . $docsHtml . $rightsHtml .
    renderCta($C['cta']['title'], $C['cta']['text'], $C['cta']['buttons']) .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/jak-pujcit/dokumenty', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => 'Dokumenty', 'url' => 'https://motogo24.cz/jak-pujcit/dokumenty'],
    ],
]);
