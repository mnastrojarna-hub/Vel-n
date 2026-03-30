<?php
// ===== MotoGo24 Web PHP — Katalog motorek (listing) =====

// Detect category from URL
$categoryMap = [
    '/katalog/cestovni' => 'cestovní',
    '/katalog/detske' => 'dětské',
];

$activeCategory = '';
$activeLicense = '';

if (isset($categoryMap[$requestUri])) {
    $activeCategory = $categoryMap[$requestUri];
} elseif (!empty($_GET['category'])) {
    $activeCategory = $_GET['category'];
}

if (!empty($_GET['license'])) {
    $activeLicense = $_GET['license'];
}

// Page titles per category
$titleMap = [
    'cestovní' => 'Cestovní motorky k pronájmu',
    'dětské' => 'Dětské motorky k pronájmu',
];

$pageTitle = $titleMap[$activeCategory] ?? 'Katalog motorek k pronájmu';
$pageDesc = 'Prohlédněte si nabídku motorek k pronájmu z naší půjčovny motorek na Vysočině. Cestovní, sportovní, enduro i dětské motorky.';

echo renderHead($pageTitle . ' – Motogo24', $pageDesc);
echo renderHeader();

// Breadcrumb
$bcItems = [['href'=>'/', 'label'=>'Domů']];
if ($activeCategory && isset($titleMap[$activeCategory])) {
    $bcItems[] = ['href'=>'/katalog', 'label'=>'Katalog motorek'];
    $bcItems[] = $titleMap[$activeCategory];
} else {
    $bcItems[] = 'Katalog motorek';
}
$bc = renderBreadcrumb($bcItems);

// Fetch motos
$motos = $sb->fetchMotos();

// Collect available categories and licenses for filters
$categories = [];
$licenses = [];
foreach ($motos as $m) {
    $cat = $m['category'] ?? '';
    $lic = $m['license_required'] ?? '';
    if ($cat && !in_array($cat, $categories)) $categories[] = $cat;
    if ($lic && $lic !== 'N' && !in_array($lic, $licenses)) $licenses[] = $lic;
}
sort($categories);
sort($licenses);

// Filter motos
$filtered = $motos;
if ($activeCategory) {
    $filtered = array_filter($filtered, function($m) use ($activeCategory) {
        return mb_strtolower($m['category'] ?? '') === mb_strtolower($activeCategory);
    });
}
if ($activeLicense) {
    $filtered = array_filter($filtered, function($m) use ($activeLicense) {
        return ($m['license_required'] ?? '') === $activeLicense;
    });
}
$filtered = array_values($filtered);

// Build filter dropdowns
$filterBase = $requestUri;
if (isset($categoryMap[$requestUri])) {
    $filterBase = '/katalog';
}

$filterHtml = '<div class="filters dfc" style="gap:12px;flex-wrap:wrap;margin-bottom:24px">';

// Category dropdown
$filterHtml .= '<select onchange="window.location.href=this.value" aria-label="Filtr kategorie">';
$filterHtml .= '<option value="' . $filterBase . ($activeLicense ? '?license=' . e($activeLicense) : '') . '"' . (!$activeCategory ? ' selected' : '') . '>Všechny kategorie</option>';
foreach ($categories as $cat) {
    $catParam = $activeLicense ? '?category=' . urlencode($cat) . '&license=' . urlencode($activeLicense) : '?category=' . urlencode($cat);
    $sel = (mb_strtolower($cat) === mb_strtolower($activeCategory)) ? ' selected' : '';
    $filterHtml .= '<option value="' . $filterBase . $catParam . '"' . $sel . '>' . e($cat) . '</option>';
}
$filterHtml .= '</select>';

// License dropdown
$filterHtml .= '<select onchange="window.location.href=this.value" aria-label="Filtr řidičáku">';
$catParam = $activeCategory ? '?category=' . urlencode($activeCategory) : '';
$filterHtml .= '<option value="' . $filterBase . $catParam . '"' . (!$activeLicense ? ' selected' : '') . '>Všechny řidičáky</option>';
foreach ($licenses as $lic) {
    $licParam = $activeCategory ? '?category=' . urlencode($activeCategory) . '&license=' . urlencode($lic) : '?license=' . urlencode($lic);
    $sel = ($lic === $activeLicense) ? ' selected' : '';
    $filterHtml .= '<option value="' . $filterBase . $licParam . '"' . $sel . '>' . e($lic) . '</option>';
}
$filterHtml .= '</select>';

$filterHtml .= '</div>';

// Render cards
$cardsHtml = '';
if (!empty($filtered)) {
    $cardsHtml .= '<div class="gr4">';
    foreach ($filtered as $m) {
        $cardsHtml .= '<section aria-labelledby="catalogue">' . renderMotoCard($m) . '</section>';
    }
    $cardsHtml .= '</div>';
} else {
    $cardsHtml .= '<p>Pro zvolený filtr nebyly nalezeny žádné motorky.</p>';
}

echo '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>' . e($pageTitle) . '</h1>' .
    '<p>Prohlédněte si nabídku <strong>motorek k pronájmu</strong> z naší <strong>půjčovny motorek na Vysočině</strong>.</p>' .
    '<p>&nbsp;</p>' .
    $filterHtml .
    $cardsHtml .
    '<p>&nbsp;</p>' .
    renderCta('Rezervuj svou motorku online',
        'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená <strong>nonstop</strong>. Stačí pár kliků a tvoje jízda začíná.',
        [['label'=>'REZERVOVAT MOTORKU','href'=>'/rezervace','cls'=>'btndark pulse']]) .
    '</div></div></main>';

echo renderFooter();
echo renderPageEnd();
