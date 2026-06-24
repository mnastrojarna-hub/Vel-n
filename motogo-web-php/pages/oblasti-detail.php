<?php
// ===== MotoGo24 Web PHP — Oblasti: krajská landing stránka =====
// SEO landing pro frázi "motopůjčovna {kraj}". Hero banner + text o kraji + CTA.
// Města kraje jsou zmíněna v textu (kvůli SEO), NE jako samostatné karty.
// Texty jsou editovatelné z webu:
//   - šablony (s placeholdery {region}/{regionLoc}/{cities}) přes
//     siteContent('oblasti').detail.* a lang/pages_*.php (překlady),
//   - per-kraj přepis hlavních textů přes cms_variables
//     web.oblasti.region.<slug>.<pole> (data-cms-key inline edit ve Velíně).
// Struktura krajů/měst: data/oblasti.php.

require_once __DIR__ . '/../data/oblasti.php';

$slug = isset($_GET['region']) ? (string)$_GET['region'] : '';
$region = oblastiFindRegion($slug);

if (!$region) {
    http_response_code(404);
    require __DIR__ . '/404.php';
    return;
}

$sb = new SupabaseClient();
$lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';

$defaults = [
    'detail' => [
        'seoTitle' => 'Motopůjčovna {region} – půjčovna motorek bez kauce | MotoGo24',
        'seoDescription' => 'Motopůjčovna {regionLoc}. Půjčovna motorek MotoGo24 přistaví motorku do měst {regionLoc} – bez kauce, s online rezervací a výbavou v ceně. Půjčíme i ve městech: {cities}.',
        'heroTagline' => 'Půjčte si motorku {regionLoc} – bez kauce, s výbavou v ceně a nonstop převzetím.',
        'heroCta' => 'REZERVOVAT MOTORKU',
        'h1' => 'Motopůjčovna {region}',
        'intro' => 'Hledáte spolehlivou <strong>motopůjčovnu {regionLoc}</strong>? MotoGo24 vám přiveze a přistaví motorku přímo do vašeho města. Nabízíme <strong>pronájem motorek bez kauce</strong>, online rezervaci a kompletní motorkářskou výbavu v ceně. Ať bydlíte ve velkém městě, nebo menší obci, motorku vám rádi doručíme na domluvené místo a po skončení pronájmu si ji opět vyzvedneme.',
        'citiesTitle' => 'Kam motorku přivezeme',
        'citiesIntro' => 'Motorku přistavíme i vrátíme {regionLoc} – například ve městech a jejich okolí:',
        'cta' => [
            'title' => 'Rezervujte si motorku {regionLoc}',
            'text' => 'Vyberte si stroj, zvolte termín a my vám motorku přivezeme. Půjčovna MotoGo24 je otevřená nonstop.',
            'buttons' => [
                ['label' => 'REZERVOVAT MOTORKU', 'href' => '/rezervace'],
                ['label' => 'Zobrazit motorky', 'href' => '/katalog'],
            ],
        ],
        'faq' => [
            'title' => 'Často kladené otázky',
            'items' => [
                ['q' => 'Přivezete motorku až do mého města?', 'a' => 'Ano. Motorku přistavíme na domluvené místo {regionLoc} i jinde v ČR. Stačí místo uvést v rezervaci.'],
                ['q' => 'Musím u vás složit kauci?', 'a' => 'Ne. Naše <strong>motopůjčovna</strong> nevyžaduje žádnou kauci ani blokaci na kartě.'],
            ],
        ],
    ],
];

$C = $sb->siteContent('oblasti', $defaults);
$D = is_array($C['detail'] ?? null) ? $C['detail'] : $defaults['detail'];

// Seznam měst (čárkami) pro SEO popisek, text a strukturovaná data.
$cityNames = array_map(function ($c) { return $c['name']; }, $region['cities']);
$citiesCsv = implode(', ', $cityNames);

// Lokativ kraje — v češtině skloňovaný ("na Vysočině"), v ostatních jazycích
// stačí krátký název kraje (neskloňuje se).
$regionLoc = ($lang === 'cs') ? ($region['inRegion'] ?? $region['name']) : ($region['seoName'] ?? $region['name']);

// Substituce placeholderů v šablonách.
$subst = function ($s, $extra = []) use ($region, $regionLoc, $citiesCsv) {
    if (!is_string($s)) return '';
    $map = array_merge([
        '{region}' => $region['seoName'],
        '{regionFull}' => $region['name'],
        '{regionLoc}' => $regionLoc,
        '{cities}' => $citiesCsv,
    ], $extra);
    return strtr($s, $map);
};

// Per-kraj přepis hlavních textů (Velín: web.oblasti.region.<slug>.<pole>),
// fallback na přeloženou šablonu z $D.
$regionOverride = (isset($C['region'][$slug]) && is_array($C['region'][$slug])) ? $C['region'][$slug] : [];
$field = function ($name) use ($regionOverride, $D, $subst) {
    if (isset($regionOverride[$name]) && is_string($regionOverride[$name]) && $regionOverride[$name] !== '') {
        return $regionOverride[$name]; // už uloženo finálně (admin přepis)
    }
    return $subst($D[$name] ?? '');
};

$cmsKey = 'web.oblasti.region.' . $slug;
$h1 = $field('h1');

// ---- Hero banner (jako na landing page) ----
$heroImgUrl = BASE_URL . '/gfx/hero-banner.jpg';
$heroWebp   = BASE_URL . '/gfx/hero-banner.webp';
$heroBase   = BASE_URL . '/gfx/hero-banner';
$heroSrcset = $heroBase . '-480.webp 480w, ' . $heroBase . '-768.webp 768w, ' . $heroBase . '-1500.webp 1500w, ' . $heroWebp . ' 1920w';
$heroCtaLabel = $field('heroCta') !== '' ? $field('heroCta') : 'REZERVOVAT MOTORKU';
$banner = '<div class="banner">' .
    '<picture>' .
        '<source srcset="' . htmlspecialchars($heroSrcset) . '" type="image/webp" sizes="100vw">' .
        '<img fetchpriority="high" decoding="async" alt="' . htmlspecialchars($h1) . '" src="' . htmlspecialchars($heroImgUrl) . '" width="1920" height="480">' .
    '</picture>' .
    '<div class="banner-wrapper"><div class="container"><div class="banner-caption">' .
        '<p data-cms-key="' . $cmsKey . '.heroTagline">' . sanitizeHtml($field('heroTagline')) . '</p><p>&nbsp;</p>' .
        '<p><a class="btn btngreen" href="' . BASE_URL . '/rezervace">' . htmlspecialchars($heroCtaLabel) . '</a></p>' .
    '</div></div></div></div>';

// Breadcrumb
$bc = renderBreadcrumb([
    ['label' => t('breadcrumb.home'), 'href' => '/'],
    ['label' => t('breadcrumb.areas'), 'href' => '/oblasti'],
    htmlspecialchars($region['name']),
]);

// Intro (text o kraji)
$introHtml = '<section><h1 data-cms-key="' . $cmsKey . '.h1">' . htmlspecialchars($h1) . '</h1>'
    . '<p data-cms-key="' . $cmsKey . '.intro">' . sanitizeHtml($field('intro')) . '</p></section>';

// Města kraje — JEN jako text (seznam v jedné větě), žádné karty.
$citiesHtml = '<section><h2 data-cms-key="' . $cmsKey . '.citiesTitle">' . htmlspecialchars($field('citiesTitle')) . '</h2>'
    . '<p data-cms-key="' . $cmsKey . '.citiesIntro">' . sanitizeHtml($field('citiesIntro')) . ' <strong>' . htmlspecialchars($citiesCsv) . '</strong>.</p></section>';

// CTA — tlačítka stejná jako na homepage/pujcovně (btndark pulse = viditelný text na tmavém boxu)
$ctaDef = is_array($D['cta'] ?? null) ? $D['cta'] : [];
$ctaButtons = [];
foreach ((is_array($ctaDef['buttons'] ?? null) ? $ctaDef['buttons'] : []) as $i => $btn) {
    if (!is_array($btn)) continue;
    $ctaButtons[] = [
        'label' => $subst($btn['label'] ?? ''),
        'href' => $btn['href'] ?? '#',
        'cls' => ($i === 0 ? 'btndark pulse' : 'btndark'),
    ];
}
$ctaHtml = renderCta(
    '<span data-cms-key="' . $cmsKey . '.ctaTitle">' . htmlspecialchars($subst($ctaDef['title'] ?? '')) . '</span>',
    '<span data-cms-key="' . $cmsKey . '.ctaText">' . htmlspecialchars($subst($ctaDef['text'] ?? '')) . '</span>',
    $ctaButtons
);

// FAQ
$faqDef = is_array($D['faq'] ?? null) ? $D['faq'] : [];
$faqItems = [];
$faqSchemaItems = [];
foreach ((is_array($faqDef['items'] ?? null) ? $faqDef['items'] : []) as $f) {
    if (!is_array($f) || empty($f['q']) || empty($f['a'])) continue;
    $q = $subst($f['q']);
    $a = $subst($f['a']);
    $faqItems[] = ['q' => $q, 'a' => $a];
    $faqSchemaItems[] = '{"@type":"Question","name":' . json_encode(strip_tags($q), JSON_UNESCAPED_UNICODE)
        . ',"acceptedAnswer":{"@type":"Answer","text":' . json_encode(strip_tags($a), JSON_UNESCAPED_UNICODE) . '}}';
}
$faqHtml = !empty($faqItems) ? renderFaqSection($subst($faqDef['title'] ?? ''), $faqItems) : '';

$content = $banner . '<main id="content"><div class="container">' . $bc
    . '<div class="ccontent">' . $introHtml . $citiesHtml . $ctaHtml . $faqHtml . '</div></div></main>';

// ===== Service JSON-LD — areaServed = kraj + jednotlivá města =====
$areaServed = ['{"@type":"AdministrativeArea","name":' . json_encode($region['name'], JSON_UNESCAPED_UNICODE) . '}'];
foreach ($cityNames as $cn) {
    $areaServed[] = '{"@type":"City","name":' . json_encode($cn, JSON_UNESCAPED_UNICODE) . '}';
}
$canonical = siteCanonicalUrl('/oblasti/' . $slug);
$serviceSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"Service"'
    . ',"@id":' . json_encode($canonical . '#service', JSON_UNESCAPED_UNICODE)
    . ',"serviceType":"Motorcycle rental"'
    . ',"name":' . json_encode($h1, JSON_UNESCAPED_UNICODE)
    . ',"description":' . json_encode(strip_tags($subst($D['intro'] ?? '')), JSON_UNESCAPED_UNICODE)
    . ',"url":' . json_encode($canonical, JSON_UNESCAPED_UNICODE)
    . ',"provider":{"@id":"https://www.motogo24.cz/#organization"}'
    . ',"areaServed":[' . implode(',', $areaServed) . ']'
    . ',"availableChannel":{"@type":"ServiceChannel","serviceUrl":' . json_encode(siteCanonicalUrl('/rezervace'), JSON_UNESCAPED_UNICODE) . ',"availableLanguage":["cs","en","de","es","fr","nl","pl"]}'
    . ',"offers":{"@type":"AggregateOffer","priceCurrency":"CZK","lowPrice":"990","highPrice":"5000","availability":"https://schema.org/InStock"}'
    . '}
  </script>';
$faqSchema = !empty($faqSchemaItems)
    ? '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"FAQPage","mainEntity":[' . implode(',', $faqSchemaItems) . ']}
  </script>'
    : '';

renderPage($subst($field('seoTitle') !== '' ? $field('seoTitle') : ($D['seoTitle'] ?? '')), $content, '/oblasti/' . $slug, [
    'description' => $subst($D['seoDescription'] ?? ''),
    'schema' => $serviceSchema . $faqSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.areas'), 'url' => siteCanonicalUrl('/oblasti')],
        ['name' => $h1, 'url' => $canonical],
    ],
]);
