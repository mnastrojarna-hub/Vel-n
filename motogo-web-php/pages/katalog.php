<?php
// ===== MotoGo24 Web PHP — Katalog motorek =====
// Odpovídá pages-katalog.js (listing)
// ZMĚNA: Filtry fungují přes GET parametry (?kategorie=X&ridicak=Y) + JS fallback

$sb = new SupabaseClient();
$motos = $sb->fetchMotos();

// Zjistíme kategorii z URL path NEBO GET parametru
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$category = null;
$title = 'Katalog motorek';

if ($path === '/katalog/cestovni') {
    $category = 'cestovni';
    $title = 'Cestovní motorky';
} elseif ($path === '/katalog/detske') {
    $category = 'detske';
    $title = 'Dětské motorky';
}

// GET parametry (přepisují URL path)
$getCat = $_GET['kategorie'] ?? '';
$getLic = $_GET['ridicak'] ?? '';
if ($getCat) $category = $getCat;

// Breadcrumb
$bc = [['label' => 'Domů', 'href' => '/'], ['label' => 'Katalog motorek', 'href' => '/katalog']];
if ($category) {
    $bc[] = $title;
} else {
    $bc[1] = $title;
}

// Filtrování dle kategorie a ŘP skupiny (server-side)
$filtered = $motos;
if ($category) {
    $filtered = array_filter($motos, function($m) use ($category) {
        $cat = strtolower($m['category'] ?? '');
        $fc = strtolower($category);
        if ($fc === 'cestovni') {
            return strpos($cat, 'cestov') !== false || strpos($cat, 'adventure') !== false || strpos($cat, 'touring') !== false;
        } elseif ($fc === 'detske') {
            return strpos($cat, 'dets') !== false || strpos($cat, 'dět') !== false || (isset($m['license_required']) && strtoupper($m['license_required']) === 'N');
        }
        return $cat === $fc;
    });
}
if ($getLic) {
    $filtered = array_filter($filtered, function($m) use ($getLic) {
        return ($m['license_required'] ?? '') === $getLic;
    });
}

// Sestavení seznamu karet
$gridHtml = '';
if (empty($filtered)) {
    $gridHtml = '<p>V této kategorii nemáme momentálně žádné motorky.</p>';
} else {
    foreach ($filtered as $m) {
        $gridHtml .= '<section aria-label="katalog motorek">' . renderMotoCard($m) . '</section>';
    }
}

// Filtry — kategorie a ŘP skupiny
$cats = [];
$lics = [];
foreach ($motos as $m) {
    if (!empty($m['category'])) $cats[$m['category']] = true;
    if (!empty($m['license_required'])) $lics[$m['license_required']] = true;
}
ksort($cats);
ksort($lics);

// Aktuální hodnoty filtrů pro selected stav
$activeCat = $category ?: '';
$activeLic = $getLic ?: '';

$filterHtml = '<div id="katalog-filters"><div style="display:flex;flex-wrap:wrap;gap:.5rem;margin-bottom:1.5rem">';
$filterHtml .= '<select id="flt-cat" onchange="filterKatalog()" style="padding:.4rem .8rem;border-radius:20px;border:1px solid #ccc;font-size:.85rem;cursor:pointer">';
$filterHtml .= '<option value="">Všechny kategorie</option>';
foreach (array_keys($cats) as $c) {
    $sel = (strtolower($activeCat) === strtolower($c)) ? ' selected' : '';
    $filterHtml .= '<option value="' . htmlspecialchars($c) . '"' . $sel . '>' . htmlspecialchars($c) . '</option>';
}
$filterHtml .= '</select>';
$filterHtml .= '<select id="flt-lic" onchange="filterKatalog()" style="padding:.4rem .8rem;border-radius:20px;border:1px solid #ccc;font-size:.85rem;cursor:pointer">';
$filterHtml .= '<option value="">Všechny ŘP</option>';
foreach (array_keys($lics) as $l) {
    $sel = ($activeLic === $l) ? ' selected' : '';
    $filterHtml .= '<option value="' . htmlspecialchars($l) . '"' . $sel . '>Skupina ' . htmlspecialchars($l) . '</option>';
}
$filterHtml .= '</select>';
$filterHtml .= '</div></div>';

// JS pro filtr: přesměruje na GET parametry (server-side filtrování)
$filterJs = '<script>
function filterKatalog(){
  var cat = document.getElementById("flt-cat").value;
  var lic = document.getElementById("flt-lic").value;
  var params = [];
  if(cat) params.push("kategorie=" + encodeURIComponent(cat));
  if(lic) params.push("ridicak=" + encodeURIComponent(lic));
  var url = "' . BASE_URL . '/katalog" + (params.length ? "?" + params.join("&") : "");
  window.location.href = url;
}
</script>';

$content = '<main id="content"><div class="container">' .
    renderBreadcrumb($bc) .
    '<div class="ccontent"><h1>' . $title . '</h1>' .
    $filterHtml .
    '<div id="katalog-grid" class="gr4">' . $gridHtml . '</div>' .
    '</div></div></main>' . $filterJs;

renderPage($title . ' – Motogo24', $content, $path);
