<?php
// ===== MotoGo24 Web PHP — Oblasti (rozcestník krajů) =====
// SEO hub pro frázi "motopůjčovna {město}". Vypíše kraje a v každém města
// nad 10 000 obyvatel s odkazem na krajskou landing stránku /oblasti/<slug>.
// Texty (hero, CTA) jsou editovatelné z webu přes siteContent('oblasti')
// + data-cms-key (Velín CMS → Texty webu). Struktura krajů/měst: data/oblasti.php.

require_once __DIR__ . '/../data/oblasti.php';

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Oblasti – motopůjčovna v krajích a městech ČR | MotoGo24',
        'description' => 'Motopůjčovna MotoGo24 přiveze a přistaví motorku do měst po celé ČR. Vyberte si svůj kraj a město – půjčovna motorek bez kauce, s online rezervací a výbavou v ceně.',
        'keywords' => 'motopůjčovna, půjčovna motorek, motopůjčovna podle města, pronájem motorek, motorka bez kauce, MotoGo24',
    ],
    'hero' => [
        'h1' => 'Motopůjčovna ve vašem kraji a městě',
        'intro' => 'Hledáte <strong>půjčovnu motorek</strong> ve svém okolí? MotoGo24 přistaví a doručí motorku do měst po celé České republice. Vyberte si svůj kraj a podívejte se, kam všude motorku přivezeme – <strong>bez kauce</strong>, s <strong>online rezervací</strong> a kompletní výbavou v ceně.',
    ],
    'regionsTitle' => 'Vyberte si kraj',
    'citiesLabel' => 'Půjčovna motorek ve městech:',
    'regionCta' => 'Zobrazit kraj',
    'cta' => [
        'title' => 'Nenašli jste své město?',
        'text' => 'Motorku přistavíme prakticky kamkoliv v ČR. Napište nám nebo rovnou rezervujte online.',
        'buttons' => [
            ['label' => 'REZERVOVAT MOTORKU', 'href' => '/rezervace', 'cls' => 'btngreen pulse'],
            ['label' => 'Kontaktujte nás', 'href' => '/kontakt', 'cls' => 'btndark'],
        ],
    ],
];

$C = $sb->siteContent('oblasti', $defaults);
$regions = oblastiRegions();

// Breadcrumb
$bc = renderBreadcrumb([
    ['label' => t('breadcrumb.home'), 'href' => '/'],
    t('breadcrumb.areas'),
]);

// Hero
$hero = '<section><h1 data-cms-key="web.oblasti.hero.h1">' . ($C['hero']['h1'] ?? '') . '</h1>'
      . '<p data-cms-key="web.oblasti.hero.intro">' . sanitizeHtml($C['hero']['intro'] ?? '') . '</p></section>';

// Karty krajů — každá obsahuje výpis měst >10k jako odkazy (kotvy na detailu)
$citiesLabel = $C['citiesLabel'] ?? 'Půjčovna motorek ve městech:';
$regionCta = $C['regionCta'] ?? 'Zobrazit kraj';
$cards = '';
foreach ($regions as $r) {
    $href = BASE_URL . '/oblasti/' . $r['slug'];
    // Klik na kterékoliv město vede na stránku kraje (ne na kotvu).
    $cityLinks = [];
    foreach ($r['cities'] as $c) {
        $cityLinks[] = '<a href="' . $href . '">' . htmlspecialchars($c['name']) . '</a>';
    }
    $cards .= '<div class="oblasti-card">'
        . '<h2 class="oblasti-card-title"><a href="' . $href . '">' . htmlspecialchars($r['name']) . '</a></h2>'
        . '<p class="oblasti-card-label">' . htmlspecialchars($citiesLabel) . '</p>'
        . '<p class="oblasti-cities">' . implode(', ', $cityLinks) . '</p>'
        . '<p class="oblasti-card-cta"><a class="btn btngreen-small" href="' . $href . '">' . htmlspecialchars($regionCta) . '</a></p>'
        . '</div>';
}
$regionsSection = '<section><h2 data-cms-key="web.oblasti.regionsTitle">' . ($C['regionsTitle'] ?? '') . '</h2>'
    . '<div class="oblasti-grid">' . $cards . '</div></section>';

// CTA
$ctaButtons = [];
foreach ((is_array($C['cta']['buttons'] ?? null) ? $C['cta']['buttons'] : []) as $i => $btn) {
    if (!is_array($btn)) continue;
    $ctaButtons[] = [
        'label' => '<span data-cms-key="web.oblasti.cta.buttons.' . $i . '.label">' . ($btn['label'] ?? '') . '</span>',
        'href' => $btn['href'] ?? '#',
        // btndark pulse = viditelný text na tmavém CTA boxu (jako homepage/pujcovna)
        'cls' => ($i === 0 ? 'btndark pulse' : 'btndark'),
    ];
}
$ctaHtml = renderCta(
    '<span data-cms-key="web.oblasti.cta.title">' . ($C['cta']['title'] ?? '') . '</span>',
    '<span data-cms-key="web.oblasti.cta.text">' . ($C['cta']['text'] ?? '') . '</span>',
    $ctaButtons
);

$content = '<main id="content"><div class="container">' . $bc
    . '<div class="ccontent">' . $hero . $regionsSection . $ctaHtml . '</div></div></main>';

// ItemList JSON-LD — seznam krajských landing stránek (interní prolinkování pro Google).
$itemListEls = [];
$nameTpl = (isset($C['detail']['h1']) && is_string($C['detail']['h1'])) ? $C['detail']['h1'] : 'Motopůjčovna {region}';
foreach ($regions as $i => $r) {
    $url = siteCanonicalUrl('/oblasti/' . $r['slug']);
    $itemListEls[] = '{"@type":"ListItem","position":' . ($i + 1)
        . ',"name":' . json_encode(str_replace('{region}', $r['seoName'], $nameTpl), JSON_UNESCAPED_UNICODE)
        . ',"url":' . json_encode($url, JSON_UNESCAPED_UNICODE) . '}';
}
$itemListSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"ItemList","name":"Motopůjčovna podle krajů","itemListElement":[' . implode(',', $itemListEls) . ']}
  </script>';

renderPage($C['seo']['title'], $content, '/oblasti', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'] ?? null,
    'schema' => $itemListSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.areas'), 'url' => siteCanonicalUrl('/oblasti')],
    ],
]);
