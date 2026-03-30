<?php
// ===== MotoGo24 Web PHP — Katalog motorek =====
// Odpovídá pages-katalog.js (listing)

$sb = new SupabaseClient();
$motos = $sb->fetchMotos();

// Zjistíme kategorii z URL
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

// Breadcrumb
$bc = [['label' => 'Domů', 'href' => '/'], ['label' => 'Katalog motorek', 'href' => '/katalog']];
if ($category) {
    $bc[] = $title;
} else {
    $bc[1] = $title;
}

// Filtrování dle kategorie (server-side)
$filtered = $motos;
if ($category) {
    $filtered = array_filter($motos, function($m) use ($category) {
        $cat = strtolower($m['category'] ?? '');
        if ($category === 'cestovni') {
            return strpos($cat, 'cestov') !== false || strpos($cat, 'adventure') !== false || strpos($cat, 'touring') !== false;
        } elseif ($category === 'detske') {
            return strpos($cat, 'dets') !== false || strpos($cat, 'dět') !== false || (isset($m['license_required']) && strtoupper($m['license_required']) === 'N');
        }
        return $cat === $category;
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

$filterHtml = '<div style="display:flex;flex-wrap:wrap;gap:.5rem;margin-bottom:1.5rem">';
$filterHtml .= '<select id="flt-cat" onchange="filterKatalog()" style="padding:.4rem .8rem;border-radius:20px;border:1px solid #ccc;font-size:.85rem;cursor:pointer">';
$filterHtml .= '<option value="">Všechny kategorie</option>';
foreach (array_keys($cats) as $c) {
    $sel = ($category === strtolower($c)) ? ' selected' : '';
    $filterHtml .= '<option value="' . htmlspecialchars($c) . '"' . $sel . '>' . htmlspecialchars($c) . '</option>';
}
$filterHtml .= '</select>';
$filterHtml .= '<select id="flt-lic" onchange="filterKatalog()" style="padding:.4rem .8rem;border-radius:20px;border:1px solid #ccc;font-size:.85rem;cursor:pointer">';
$filterHtml .= '<option value="">Všechny ŘP</option>';
foreach (array_keys($lics) as $l) {
    $filterHtml .= '<option value="' . htmlspecialchars($l) . '">Skupina ' . htmlspecialchars($l) . '</option>';
}
$filterHtml .= '</select>';
$filterHtml .= '</div>';

// Inline JS pro klientský filtr (zachová interaktivitu)
$filterJs = '<script>
function filterKatalog(){
  var cat = document.getElementById("flt-cat").value.toLowerCase();
  var lic = document.getElementById("flt-lic").value;
  var cards = document.querySelectorAll("#katalog-grid > section");
  cards.forEach(function(s){
    var show = true;
    var a = s.querySelector(".moto-wrapper");
    if(!a) return;
    var features = a.querySelector(".moto-desc ul");
    var items = features ? features.querySelectorAll("li") : [];
    var text = "";
    items.forEach(function(li){ text += li.textContent.toLowerCase() + " "; });
    if(cat){
      if(cat==="cestovni"){ if(text.indexOf("cestov")===-1 && text.indexOf("adventure")===-1 && text.indexOf("touring")===-1) show=false; }
      else if(cat==="detske"||cat==="dětské"){ if(text.indexOf("dets")===-1 && text.indexOf("dět")===-1) show=false; }
      else { if(text.indexOf(cat)===-1) show=false; }
    }
    if(lic && text.indexOf(lic)===-1) show=false;
    s.style.display = show ? "" : "none";
  });
}
</script>';

$content = '<main id="content"><div class="container">' .
    renderBreadcrumb($bc) .
    '<div class="ccontent"><h1>' . $title . '</h1>' .
    $filterHtml .
    '<div id="katalog-grid" class="gr4">' . $gridHtml . '</div>' .
    '</div></div></main>' . $filterJs;

renderPage($title . ' – Motogo24', $content, $path);
