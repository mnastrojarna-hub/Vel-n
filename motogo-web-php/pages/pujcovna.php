<?php
// ===== MotoGo24 Web PHP — Stránka Půjčovna motorek (CMS-driven) =====
// Obsah lze editovat v app_settings klíč 'site.pujcovna'

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'O půjčovně motorek | MotoGo24',
        'description' => 'Půjčovna motorek Motogo24 na Vysočině. Bez kauce, s online rezervací a výbavou v ceně. Cestovní, sportovní, enduro i dětské motorky. Nonstop provoz.',
        'keywords' => 'půjčovna motorek, pronájem motorek Vysočina, motorky bez kauce, nonstop půjčovna, výbava v ceně',
    ],
    'breadcrumb' => [
        ['label' => 'Domů', 'href' => '/'],
        'Půjčovna motorek',
    ],
    'intro' => [
        'h1' => 'Půjčovna motorek Vysočina Motogo24',
        'body' => 'Naše <strong>půjčovna motorek Vysočina</strong> v Pelhřimově nabízí <strong>pronájem motorek</strong> bez zbytečných překážek – <strong>bez kauce</strong>, s <strong>online rezervací</strong> a <strong>výbavou v ceně</strong>. Vyberete si z <strong>cestovních</strong>, <strong>sportovních</strong>, <strong>enduro</strong> i <strong>dětských motorek</strong>, a vyrazíte kdykoli: máme otevřeno <strong>nonstop</strong>.',
    ],
    'benefits' => [
        'title' => 'Proč si půjčit motorku u nás',
        'closing' => 'Hledáte <strong>půjčovnu motorek na Vysočině</strong>? Motogo24 – <strong>půjčovna motorek na Vysočině</strong> – nabízí férové podmínky, jasný postup a špičkově udržované stroje pro výlety po ČR i do zahraničí.',
        'buttons' => [
            ['label' => 'Zobrazit motorky k pronájmu', 'href' => '/katalog', 'cls' => 'btngreen'],
            ['label' => 'REZERVOVAT', 'href' => '/rezervace', 'cls' => 'btngreen pulse'],
        ],
        'items' => [
            ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'Bez kauce', 'text' => 'a bez skrytých poplatků'],
            ['icon' => 'gfx/rezervace-online.svg', 'title' => 'Online rezervace', 'text' => 'na pár kliknutí'],
            ['icon' => 'gfx/vyber-vybavu.svg', 'title' => 'Výbava pro řidiče v ceně', 'text' => 'helma, bunda, kalhoty a rukavice'],
            ['icon' => 'gfx/ico-nonstop.svg', 'title' => 'Nonstop provoz', 'text' => 'pro vyzvednutí i vrácení dle rezervace'],
            ['icon' => 'gfx/ico-spolecne.svg', 'title' => 'Jsme v tom společně', 'text' => 'když se něco přihodí'],
            ['icon' => 'gfx/predani-motorky.svg', 'title' => 'Přistavení i vrácení motorky', 'text' => 'na domluvené místo'],
        ],
    ],
    'process' => [
        'title' => 'Jak probíhá půjčení motorky na Vysočině',
        'steps' => [
            ['icon' => 'gfx/vyber-motorku.svg', 'title' => '1. Vyber motorku', 'text' => 'Prohlédni si naši nabídku, vyber si typ, který ti vyhovuje, odpovídá tvým zkušenostem a řidičskému oprávnění.'],
            ['icon' => 'gfx/rezervace-online.svg', 'title' => '2. Rezervuj online', 'text' => 'Uskutečni rezervaci podle data nebo podle konkrétní motorky, kterou si chceš půjčit.'],
            ['icon' => 'gfx/vyber-vybavu.svg', 'title' => '3. Vyber výbavu', 'text' => 'Výbava pro řidiče je v ceně, pro spolujezdce za příplatek. Velikost si můžeš zvolit až na místě.'],
            ['icon' => 'gfx/zaplat.svg', 'title' => '4. Zaplať', 'text' => 'Zaplať jednoduše online prostřednictvím platební brány.'],
            ['icon' => 'gfx/predani-motorky.svg', 'title' => '5. Převezmi motorku', 'text' => 'Motorku si vyzvedni přímo v půjčovně, nebo na místě, které jsi zvolil při rezervaci.'],
            ['icon' => 'gfx/uzij-si-jizdu.svg', 'title' => '6. Užij si jízdu', 'text' => 'Vyraz na cestu, objevuj nové zážitky a užij si naplno svobodu na dvou kolech.'],
            ['icon' => 'gfx/vrat-motorku-vcas.svg', 'title' => '7. Vrať motorku', 'text' => 'Motorku jednoduše vrať ve sjednaný den – přímo v půjčovně, nebo na předem domluveném místě.'],
            ['icon' => 'gfx/sleva-na-pristi-jizdu.svg', 'title' => 'Sleva na příští jízdu', 'text' => 'Po vrácení motorky ti automaticky zašleme slevový kód 200 Kč na další rezervaci.'],
        ],
    ],
    'faq' => [
        'title' => 'Často kladené otázky',
        'more_link' => '/jak-pujcit/faq',
        'items' => [
            ['q' => 'Jak si mohu rezervovat motorku?', 'a' => 'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu. Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.'],
            ['q' => 'Můžu si motorku půjčit i bez předchozí rezervace?', 'a' => 'Bez rezervace to bohužel nejde. Každou motorku je nutné předem zamluvit.'],
            ['q' => 'Musím složit kauci?', 'a' => 'Ne! U nás <strong>žádnou kauci platit nemusíš</strong>. Naše půjčovna se tímto zásadně liší od většiny konkurence.'],
            ['q' => 'Můžu odcestovat s motorkou do zahraničí?', 'a' => 'Ano, s motorkou můžeš bez problémů vyrazit i do zahraničí. Cesty mimo Česko neomezujeme, jen je potřeba dodržet územní platnost pojištění (zelená karta).'],
        ],
    ],
    'cta' => [
        'title' => 'Rezervuj svou motorku online',
        'text' => 'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená <strong>nonstop</strong>. Stačí pár kliků a tvoje jízda začíná.',
        'buttons' => [
            ['label' => 'REZERVOVAT MOTORKU', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
            ['label' => 'Dárkový poukaz', 'href' => '/poukazy', 'cls' => 'btndark'],
            ['label' => 'Tipy na trasy', 'href' => '/blog', 'cls' => 'btndark'],
        ],
    ],
];

$C = $sb->siteContent('pujcovna', $defaults);

$bc = renderBreadcrumb($C['breadcrumb']);

$intro = '<section><h1 data-cms-key="web.pujcovna.intro.h1">' . $C['intro']['h1'] . '</h1><p data-cms-key="web.pujcovna.intro.body">' . $C['intro']['body'] . '</p></section>';

$benefitsHtml = '<section><h2 data-cms-key="web.pujcovna.benefits.title">' . $C['benefits']['title'] . '</h2><div class="gr6">';
foreach ($C['benefits']['items'] as $i => $b) {
    $kBase = 'web.pujcovna.benefits.items.' . $i;
    $benefitsHtml .= renderWbox(
        $b['icon'],
        '<span data-cms-key="' . $kBase . '.title">' . $b['title'] . '</span>',
        '<span data-cms-key="' . $kBase . '.text">' . $b['text'] . '</span>'
    );
}
$benefitsHtml .= '</div><p>&nbsp;</p><p data-cms-key="web.pujcovna.benefits.closing">' . $C['benefits']['closing'] . '</p><p>&nbsp;</p><p>';
foreach ($C['benefits']['buttons'] as $i => $btn) {
    $benefitsHtml .= '<a class="btn ' . ($btn['cls'] ?? 'btndark') . '" href="' . BASE_URL . $btn['href'] . '" data-cms-key="web.pujcovna.benefits.buttons.' . $i . '.label">' . $btn['label'] . '</a> ';
}
$benefitsHtml .= '</p></section>';

$stepsHtml = '<section aria-labelledby="process"><h2 data-cms-key="web.pujcovna.process.title">' . $C['process']['title'] . '</h2><div class="gr4">';
foreach ($C['process']['steps'] as $i => $s) {
    $kBase = 'web.pujcovna.process.steps.' . $i;
    $stepsHtml .= renderWbox(
        $s['icon'],
        '<span data-cms-key="' . $kBase . '.title">' . $s['title'] . '</span>',
        '<span data-cms-key="' . $kBase . '.text">' . $s['text'] . '</span>'
    );
}
$stepsHtml .= '</div></section>';

$faqItemsKeyed = [];
foreach (($C['faq']['items'] ?? []) as $i => $f) {
    $faqItemsKeyed[] = [
        'q' => '<span data-cms-key="web.pujcovna.faq.items.' . $i . '.q">' . ($f['q'] ?? '') . '</span>',
        'a' => '<span data-cms-key="web.pujcovna.faq.items.' . $i . '.a">' . ($f['a'] ?? '') . '</span>',
    ];
}
$faqTitleKeyed = '<span data-cms-key="web.pujcovna.faq.title">' . ($C['faq']['title'] ?? '') . '</span>';
$faqHtml = renderFaqSection($faqTitleKeyed, $faqItemsKeyed, $C['faq']['more_link'] ?? null);

$ctaButtonsKeyed = [];
foreach (($C['cta']['buttons'] ?? []) as $i => $btn) {
    $b = $btn;
    $b['label'] = '<span data-cms-key="web.pujcovna.cta.buttons.' . $i . '.label">' . ($btn['label'] ?? '') . '</span>';
    $ctaButtonsKeyed[] = $b;
}
$ctaHtml = renderCta(
    '<span data-cms-key="web.pujcovna.cta.title">' . ($C['cta']['title'] ?? '') . '</span>',
    '<span data-cms-key="web.pujcovna.cta.text">' . ($C['cta']['text'] ?? '') . '</span>',
    $ctaButtonsKeyed
);

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' . $intro . $benefitsHtml . $stepsHtml . $faqHtml . $ctaHtml . '</div></div></main>';

// ===== Service + FAQPage JSON-LD =====
// Service popisuje hlavní byznys — pronájem motorek — s areaServed,
// price range, providerMobility, hoursAvailable. AI agenti ho používají
// jako "what they do" answer pro prompty typu "kde si půjčit motorku v ČR".
$benefitFeatures = [];
foreach (($C['benefits']['items'] ?? []) as $b) {
    $title = trim(strip_tags($b['title'] ?? ''));
    $text  = trim(strip_tags($b['text'] ?? ''));
    if ($title === '' && $text === '') continue;
    $benefitFeatures[] = '{"@type":"PropertyValue","name":' . json_encode($title, JSON_UNESCAPED_UNICODE)
        . ',"value":' . json_encode($text !== '' ? $text : $title, JSON_UNESCAPED_UNICODE) . '}';
}

$serviceSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"Service"'
    . ',"@id":"https://motogo24.cz/pujcovna-motorek#service"'
    . ',"serviceType":"Motorcycle rental"'
    . ',"name":"Pronájem motorek MotoGo24 — Vysočina"'
    . ',"description":' . json_encode(strip_tags($C['intro']['body'] ?? 'Půjčovna motorek na Vysočině — bez kauce, výbava v ceně, nonstop provoz.'), JSON_UNESCAPED_UNICODE)
    . ',"url":"https://motogo24.cz/pujcovna-motorek"'
    . ',"provider":{"@id":"https://motogo24.cz/#organization"}'
    . ',"areaServed":[{"@type":"Country","name":"Česko"},{"@type":"AdministrativeArea","name":"Kraj Vysočina"},{"@type":"Country","name":"Slovensko"},{"@type":"Country","name":"Rakousko"},{"@type":"Country","name":"Polsko"}]'
    . ',"availableChannel":{"@type":"ServiceChannel","serviceUrl":"https://motogo24.cz/rezervace","availableLanguage":["cs","en","de","es","fr","nl","pl"]}'
    . ',"hoursAvailable":{"@type":"OpeningHoursSpecification","dayOfWeek":["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"],"opens":"00:00","closes":"23:59"}'
    . ',"offers":{"@type":"AggregateOffer","priceCurrency":"CZK","lowPrice":"990","highPrice":"5000","offerCount":' . max(1, count($sb->fetchMotos() ?: [])) . ',"url":"https://motogo24.cz/katalog"}'
    . ',"category":"Vehicle rental"'
    . (!empty($benefitFeatures) ? ',"additionalProperty":[' . implode(',', $benefitFeatures) . ']' : '')
    . '}
  </script>';

// FAQPage z home FAQ items
$faqSchemaItems = [];
foreach (($C['faq']['items'] ?? []) as $faq) {
    if (empty($faq['q']) || empty($faq['a'])) continue;
    $faqSchemaItems[] = '{"@type":"Question","name":' . json_encode(strip_tags($faq['q']), JSON_UNESCAPED_UNICODE)
        . ',"acceptedAnswer":{"@type":"Answer","text":' . json_encode(strip_tags($faq['a']), JSON_UNESCAPED_UNICODE) . '}}';
}
$faqSchema = '';
if (!empty($faqSchemaItems)) {
    $faqSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"FAQPage","mainEntity":[' . implode(',', $faqSchemaItems) . ']}
  </script>';
}

renderPage($C['seo']['title'], $content, '/pujcovna-motorek', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'schema' => $serviceSchema . $faqSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => t('menu.rental'), 'url' => 'https://motogo24.cz/pujcovna-motorek'],
    ],
]);
