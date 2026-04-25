<?php
// ===== MotoGo24 Web PHP — Vrácení motorky jinde (CMS-driven) =====

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Vrácení motorky jinde – odvoz a svoz | MotoGo24',
        'description' => 'Vrať motorku mimo půjčovnu – z hotelu, nádraží nebo jiné adresy. Svoz po Vysočině i mimo region. Ceník dle vzdálenosti, nonstop provoz.',
        'keywords' => 'vrácení motorky jinde, svoz motorky, odvoz motocyklu, vrácení mimo půjčovnu, půjčovna motorek Vysočina',
    ],
    'h1' => 'Vrácení motorky jinde – svoz až k tobě',
    'intro' => 'Nemusíš se vracet do půjčovny. <strong>Motogo24</strong> nabízí <strong>svoz motorky</strong> z místa, které ti vyhovuje – hotel, nádraží, vlastní adresa.',
    'top_cta' => ['label' => 'REZERVOVAT SE SVOZEM', 'href' => '/rezervace?return_delivery=1'],
    'why' => [
        'title' => 'Proč využít vrácení mimo půjčovnu',
        'items' => [
            ['icon' => 'gfx/ico-pohodli.svg', 'title' => 'Pohodlí', 'text' => 'odjeď přímo z hotelu nebo letiště'],
            ['icon' => 'gfx/ico-flexibilita.svg', 'title' => 'Flexibilita', 'text' => 'svoz domluvíme dle tvého času'],
            ['icon' => 'gfx/ico-nonstop.svg', 'title' => 'Nonstop provoz', 'text' => 'ráno, večer i v noci'],
            ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'Bez kauce', 'text' => 'férové podmínky'],
        ],
    ],
    'pricing' => [
        'title' => 'Ceník svozu motorky',
        'note' => 'Výchozí bod: <strong>Pelhřimov (Vysočina)</strong>. Platí cena za 1 směr (svoz). Lze kombinovat s přistavením.',
        'headers' => ['Vzdálenost od Pelhřimova', 'Cena za svoz', 'Příklady lokalit'],
        'rows' => [
            ['Do 10 km', '290 Kč', 'Centrum Pelhřimov, blízké obce'],
            ['Do 30 km', '590 Kč', 'Humpolec, Kamenice nad Lipou, Pacov'],
            ['Do 60 km', '990 Kč', 'Jihlava, Třebíč, Tábor'],
            ['Do 100 km', '1 490 Kč', 'České Budějovice, Kolín, Havlíčkův Brod'],
            ['100+ km', 'Individuálně', 'Praha, Brno, další místa po dohodě'],
        ],
    ],
    'process' => [
        'title' => 'Jak svoz probíhá',
        'steps' => [
            ['icon' => 'gfx/ico-step1.svg', 'title' => 'Při rezervaci', 'text' => 'zvol vrácení mimo půjčovnu'],
            ['icon' => 'gfx/ico-step3.svg', 'title' => 'Zadej adresu', 'text' => 'a čas předání motorky'],
            ['icon' => 'gfx/ico-step5.svg', 'title' => 'Potvrď cenu', 'text' => 'svozu dle vzdálenosti'],
            ['icon' => 'gfx/ico-step6.svg', 'title' => 'Předáme klíče', 'text' => 'na místě, podepíšeme protokol'],
        ],
    ],
    'tips' => [
        'title' => 'Praktické informace',
        'items' => [
            'Svoz se účtuje <strong>jednorázově dle vzdálenosti</strong>, ne za přepravu obousměrně.',
            'Lze kombinovat s <a href="/jak-pujcit/pristaveni"><strong>přistavením motorky</strong></a> – ušetříš čas i peníze.',
            'Při <strong>vícedenním pronájmu nad 7 dní</strong> nabízíme zvýhodněný ceník svozu.',
            '<strong>Mimo Vysočinu</strong> dohodneme cenu individuálně – stačí napsat na info@motogo24.cz.',
        ],
        'cta' => ['label' => 'CHCI MOTORKU SE SVOZEM', 'href' => '/rezervace?return_delivery=1'],
    ],
    'faq' => [
        'title' => 'Časté dotazy ke svozu',
        'items' => [
            ['q' => 'Mohu vrátit motorku v jiném městě než Pelhřimov?', 'a' => 'Ano, nabízíme <strong>svoz po Vysočině i mimo region</strong>. Cena se odvíjí od vzdálenosti od Pelhřimova.'],
            ['q' => 'Jak dlouho předem musím svoz objednat?', 'a' => 'Doporučujeme <strong>minimálně 24 hodin předem</strong>. Pro nonstop svoz volej na +420 774 256 271.'],
            ['q' => 'Co když motorku nemůžu předat osobně?', 'a' => 'Po předchozí domluvě umožňujeme <strong>bezkontaktní vrácení</strong> – stačí zaparkovat na domluvené adrese.'],
            ['q' => 'Můžu kombinovat přistavení a svoz?', 'a' => 'Ano. Standardně účtujeme <strong>každou cestu zvlášť</strong>, často nabízíme balíčkovou slevu.'],
            ['q' => 'Vracím motorku mimo Českou republiku – jde to?', 'a' => 'Po individuální dohodě ano. Pošli e-mail na <strong>info@motogo24.cz</strong> s adresou a termínem.'],
        ],
    ],
    'cta' => [
        'title' => 'Vrácení motorky kdekoli – Motogo24',
        'text' => 'Motogo24 zařídí <strong>svoz motorky</strong> z místa, které ti vyhovuje. <strong>Nonstop, bez kauce, bez starostí.</strong>',
        'buttons' => [['label' => 'REZERVOVAT SE SVOZEM', 'href' => '/rezervace?return_delivery=1', 'cls' => 'btndark pulse']],
    ],
];

$C = $sb->siteContent('jak_pujcit_vraceni_jinde', $defaults);

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Vrácení motorky jinde']);

$whyHtml = '<section><h2>' . $C['why']['title'] . '</h2><div class="gr4">';
foreach ($C['why']['items'] as $w) { $whyHtml .= renderWbox($w['icon'], $w['title'], $w['text']); }
$whyHtml .= '</div></section>';

$priceTable = renderTable($C['pricing']['headers'], $C['pricing']['rows']);
$priceHtml = '<section><h2>' . $C['pricing']['title'] . '</h2><p>' . $C['pricing']['note'] . '</p><p>&nbsp;</p>' . $priceTable . '</section>';

$processHtml = '<section><h2>' . $C['process']['title'] . '</h2><div class="gr4">';
foreach ($C['process']['steps'] as $s) { $processHtml .= renderWbox($s['icon'], $s['title'], $s['text']); }
$processHtml .= '</div></section>';

$tipsLis = '';
foreach ($C['tips']['items'] as $t) { $tipsLis .= '<li>' . $t . '</li>'; }
$tipsHtml = '<section><h2>' . $C['tips']['title'] . '</h2><ul>' . $tipsLis . '</ul>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $C['tips']['cta']['href'] . '">' . $C['tips']['cta']['label'] . '</a></p></section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<section><h1>' . $C['h1'] . '</h1><p>' . $C['intro'] . '</p>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $C['top_cta']['href'] . '">' . $C['top_cta']['label'] . '</a></p></section>' .
    $whyHtml . $priceHtml . $processHtml . $tipsHtml .
    renderFaqSection($C['faq']['title'], $C['faq']['items']) .
    renderCta($C['cta']['title'], $C['cta']['text'], $C['cta']['buttons']) .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/jak-pujcit/vraceni-jinde', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => 'Vrácení motorky jinde', 'url' => 'https://motogo24.cz/jak-pujcit/vraceni-jinde'],
    ],
]);
