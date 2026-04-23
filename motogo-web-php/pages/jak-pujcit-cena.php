<?php
// ===== MotoGo24 Web PHP — Co je v ceně (CMS-driven) =====

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Co je v ceně pronájmu motorky | MotoGo24',
        'description' => 'Co je v ceně pronájmu motorky. Helma, bunda, kalhoty, rukavice zdarma. Pojištění, nonstop provoz, bez kauce.',
        'keywords' => 'výbava v ceně, co je v ceně pronájmu, helma zdarma, pojištění motorky, bez kauce',
    ],
    'h1' => 'Co je v ceně pronájmu motorky',
    'intro' => 'V <strong>Motogo24 – půjčovna motorek na Vysočině</strong> dostaneš férové podmínky. <strong>Bez kauce, s výbavou v ceně a nonstop provozem</strong>.',
    'gear' => [
        'basic' => [
            'title' => 'Základní výbava zdarma',
            'lead' => 'Každý řidič má k dispozici kompletní <strong>motorkářskou výbavu</strong>:',
            'items' => [
                '<strong>Helma</strong> – vždy čistá a bezpečná',
                '<strong>Motorkářská bunda</strong> s chrániči',
                '<strong>Moto kalhoty</strong> pro maximální komfort',
                '<strong>Rukavice</strong> ve správné velikosti',
            ],
        ],
        'extra' => [
            'title' => 'Nadstandardní výbava',
            'items' => [
                '<strong>Výbava pro spolujezdce</strong>',
                '<strong>Páteřák</strong> pro maximální ochranu',
                '<strong>Chrániče hrudi</strong> (pro enduro/cross)',
                '<strong>Motorkářské boty</strong>',
                '<strong>Bluetooth komunikátor</strong>',
                '<strong>Kufry</strong> a zavazadlový systém',
            ],
        ],
    ],
    'benefits' => [
        'title' => 'Další výhody v ceně',
        'items' => [
            ['icon' => 'gfx/ico-nonstop.svg', 'title' => 'Nonstop provoz', 'text' => 'vyzvednutí i vrácení kdykoli'],
            ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'Bez kauce', 'text' => 'žádná záloha při půjčení'],
            ['icon' => 'gfx/ico-pojisteni.svg', 'title' => 'Pojištění', 'text' => 'součástí pronájmu'],
            ['icon' => 'gfx/ico-bezkontaktni.svg', 'title' => 'Bezkontaktní předání', 'text' => 'na vyžádání'],
            ['icon' => 'gfx/ico-jasna-pravidla.svg', 'title' => 'Jasné podmínky', 'text' => 'bez skrytých poplatků'],
        ],
    ],
    'closing' => [
        'title' => 'Rezervuj si motorku s výbavou v ceně',
        'text' => 'Vyber si z nabídky <strong>cestovních, sportovních, enduro i dětských motorek</strong> a vyraž na cestu bez starostí. Vše potřebné máš zahrnuto v půjčovném.',
    ],
    'cta' => [
        'title' => 'Výbava v ceně – půjčovna motorek Vysočina',
        'text' => 'Motogo24 je moderní <strong>půjčovna motorek na Vysočině</strong>. U nás dostaneš <strong>výbavu v ceně</strong>, půjčení <strong>bez kauce</strong>, <strong>online rezervaci</strong> a <strong>nonstop provoz</strong>.',
        'buttons' => [['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
    ],
];

$C = $sb->siteContent('jak_pujcit_cena', $defaults);

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Co je v ceně']);

$basicLis = '';
foreach ($C['gear']['basic']['items'] as $i) { $basicLis .= '<li>' . $i . '</li>'; }
$extraLis = '';
foreach ($C['gear']['extra']['items'] as $i) { $extraLis .= '<li>' . $i . '</li>'; }

$gearHtml = '<section><h1>' . $C['h1'] . '</h1>' .
    '<p>' . $C['intro'] . '</p>' .
    '<div class="gr2"><div>' .
        '<h2>' . $C['gear']['basic']['title'] . '</h2>' .
        '<p>' . $C['gear']['basic']['lead'] . '</p>' .
        '<ul>' . $basicLis . '</ul>' .
    '</div><div>' .
        '<h2>' . $C['gear']['extra']['title'] . '</h2>' .
        '<ul>' . $extraLis . '</ul>' .
    '</div></div></section>';

$benefitsHtml = '<section aria-labelledby="benefits"><h2>' . $C['benefits']['title'] . '</h2><div class="gr6">';
foreach ($C['benefits']['items'] as $b) {
    $benefitsHtml .= renderWbox($b['icon'], $b['title'], $b['text']);
}
$benefitsHtml .= '</div></section>';

$closingHtml = '<section><h2>' . $C['closing']['title'] . '</h2><p>' . $C['closing']['text'] . '</p></section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' . $gearHtml . $benefitsHtml . $closingHtml .
    renderCta($C['cta']['title'], $C['cta']['text'], $C['cta']['buttons']) .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/jak-pujcit/co-v-cene', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => 'Co je v ceně', 'url' => 'https://motogo24.cz/jak-pujcit/co-v-cene'],
    ],
]);
