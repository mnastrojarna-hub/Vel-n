<?php
// ===== MotoGo24 Web PHP — Detail motorky =====

$motos = $sb->fetchMotos();

// Find current moto
$moto = null;
$motoIndex = null;
foreach ($motos as $i => $m) {
    if (($m['id'] ?? '') === $motoId) {
        $moto = $m;
        $motoIndex = $i;
        break;
    }
}

if (!$moto) {
    http_response_code(404);
    require __DIR__ . '/404.php';
    return;
}

$model = e($moto['model'] ?? '');
$cat = e($moto['category'] ?? '');
$desc = $moto['description'] ?? '';
$images = $moto['images'] ?? [];
$mainImg = imgUrl($moto['image_url'] ?? ($images[0] ?? ''));
$license = e($moto['license_required'] ?? '');
$engineCc = $moto['engine_cc'] ?? '';
$powerKw = $moto['power_kw'] ?? '';
$weight = $moto['weight_kg'] ?? '';
$seatHeight = $moto['seat_height_mm'] ?? '';
$idealUsage = $moto['ideal_usage'] ?? '';
$branch = $moto['branches'] ?? null;
$minPrice = getMinPrice($moto);

$pageTitle = $model . ' – pronájem motorky | Motogo24';
$pageDesc = 'Pronájem motorky ' . $model . ' v půjčovně motorek Motogo24 na Vysočině. ' . ($cat ? 'Kategorie: ' . $cat . '. ' : '') . ($minPrice > 0 ? 'Cena od ' . formatPrice($minPrice) . '/den.' : '');

echo renderHead($pageTitle, $pageDesc, '', $mainImg);
echo renderHeader();

// Prev / Next navigation
$prevMoto = ($motoIndex > 0) ? $motos[$motoIndex - 1] : null;
$nextMoto = ($motoIndex < count($motos) - 1) ? $motos[$motoIndex + 1] : null;

// Breadcrumb
$bc = renderBreadcrumb([
    ['href'=>'/', 'label'=>'Domů'],
    ['href'=>'/katalog', 'label'=>'Katalog motorek'],
    $model
]);

// Prev/Next nav
$prevNextHtml = '<div class="prev-next-nav dfjs" style="margin-bottom:24px">';
if ($prevMoto) {
    $prevNextHtml .= '<a class="btn btndark" href="/katalog/' . e($prevMoto['id']) . '">&larr; ' . e($prevMoto['model']) . '</a>';
} else {
    $prevNextHtml .= '<span></span>';
}
if ($nextMoto) {
    $prevNextHtml .= '<a class="btn btndark" href="/katalog/' . e($nextMoto['id']) . '">' . e($nextMoto['model']) . ' &rarr;</a>';
} else {
    $prevNextHtml .= '<span></span>';
}
$prevNextHtml .= '</div>';

// Header section with image and basic info
$headerHtml = '<div class="gr2">';
$headerHtml .= '<div>' . ($mainImg ? '<img src="' . e($mainImg) . '" alt="' . $model . '" class="imgres" loading="lazy">' : '') . '</div>';
$headerHtml .= '<div>';
$headerHtml .= '<h1>' . $model . '</h1>';
if ($cat) $headerHtml .= '<p><strong>Kategorie:</strong> ' . $cat . '</p>';
if ($license && $license !== 'N') $headerHtml .= '<p><strong>Řidičský průkaz:</strong> ' . $license . '</p>';
if ($minPrice > 0) $headerHtml .= '<p class="moto-price" style="font-size:1.3rem"><strong>Cena od ' . formatPrice($minPrice) . '/den</strong></p>';
$headerHtml .= '<p>&nbsp;</p>';
$headerHtml .= '<p><a class="btn btngreen pulse" id="moto-cal-reserve-btn" href="/rezervace?moto=' . e($motoId) . '">REZERVOVAT MOTORKU</a></p>';
$headerHtml .= '</div></div>';

// Description
$descHtml = '';
if ($desc) {
    $descHtml = '<section><h2>Popis motorky</h2><div class="cms-content">' . $desc . '</div></section>';
}

// Specs table
$specsRows = [];
if ($cat) $specsRows[] = ['Kategorie', $cat];
if ($license && $license !== 'N') $specsRows[] = ['Řidičský průkaz', $license];
if ($engineCc) $specsRows[] = ['Objem motoru', $engineCc . ' ccm'];
if ($powerKw) $specsRows[] = ['Výkon', $powerKw . ' kW'];
if ($weight) $specsRows[] = ['Hmotnost', $weight . ' kg'];
if ($seatHeight) $specsRows[] = ['Výška sedla', $seatHeight . ' mm'];
if ($idealUsage) {
    $usageText = is_array($idealUsage) ? implode(', ', $idealUsage) : $idealUsage;
    $specsRows[] = ['Ideální využití', e($usageText)];
}
if ($branch) {
    $branchText = e($branch['name'] ?? '') . ', ' . e($branch['address'] ?? '') . ' ' . e($branch['city'] ?? '');
    $specsRows[] = ['Pobočka', trim($branchText, ', ')];
}

$specsHtml = '';
if (!empty($specsRows)) {
    $specsHtml = '<section><h2>Technické parametry</h2>' .
        renderTable(['Parametr', 'Hodnota'], $specsRows) .
        '</section>';
}

// Gallery
$galleryHtml = '';
if (count($images) > 1) {
    $galleryHtml = '<section><h2>Galerie</h2><div class="gallery gr3">';
    foreach ($images as $img) {
        $src = imgUrl($img);
        $galleryHtml .= '<div class="gallery-item"><img src="' . e($src) . '" alt="' . $model . '" class="imgres" loading="lazy"></div>';
    }
    $galleryHtml .= '</div></section>';
}

// Pricing table
$pricingHtml = '<section><h2>Ceník pronájmu</h2>';
$dayNames = ['Pondělí'=>'price_mon','Úterý'=>'price_tue','Středa'=>'price_wed','Čtvrtek'=>'price_thu','Pátek'=>'price_fri','Sobota'=>'price_sat','Neděle'=>'price_sun'];
$priceRows = [];
foreach ($dayNames as $label => $key) {
    $val = $moto[$key] ?? 0;
    if ($val > 0) {
        $priceRows[] = [$label, formatPrice($val)];
    }
}
if (!empty($priceRows)) {
    $pricingHtml .= renderTable(['Den', 'Cena / den'], $priceRows);
} else {
    $pricingHtml .= '<p>Ceník bude doplněn.</p>';
}
$pricingHtml .= '</section>';

// Calendar section (interactive JS)
$calendarHtml = '<section><h2>Dostupnost a kalendář</h2>' .
    '<div id="moto-calendar"></div>' .
    '<div class="calendar-icons gr3"><div><span class="cicon loosely">&nbsp;</span> Volné</div><div><span class="cicon occupied">&nbsp;</span> Obsazené</div><div><span class="cicon unconfirmed">&nbsp;</span> Nepotvrzené</div></div>' .
    '<div id="moto-calendar-banner" style="display:none"></div>' .
    '</section>';

// Related motos (same category, max 4)
$relatedHtml = '';
$related = array_filter($motos, function($m) use ($motoId, $moto) {
    return ($m['id'] ?? '') !== $motoId && ($m['category'] ?? '') === ($moto['category'] ?? '');
});
$related = array_slice(array_values($related), 0, 4);
if (!empty($related)) {
    $relatedHtml = '<section><h2>Další motorky v kategorii</h2><div class="gr4">';
    foreach ($related as $r) {
        $relatedHtml .= renderMotoCard($r);
    }
    $relatedHtml .= '</div></section>';
}

echo '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    $prevNextHtml .
    $headerHtml .
    '<p>&nbsp;</p>' .
    $descHtml .
    $specsHtml .
    $galleryHtml .
    $pricingHtml .
    $calendarHtml .
    '<p>&nbsp;</p>' .
    $prevNextHtml .
    $relatedHtml .
    '</div></div></main>';

echo renderFooter();

// Calendar JS init
$needsSupabase = true;
?>
<script>
document.addEventListener('DOMContentLoaded', function(){
  // Wait for Supabase SDK and components to load
  var checkReady = setInterval(function(){
    if(typeof MG !== 'undefined' && typeof MG._buildCalendar === 'function'){
      clearInterval(checkReady);
      MG._buildCalendar('moto-calendar', '<?php echo e($motoId); ?>');

      // Override reserve button updater for clean URLs
      var origUpdate = MG._calUpdateReserveBtn;
      MG._calUpdateReserveBtn = function(containerId){
        var state = MG._calState[containerId];
        if(!state) return;
        var btn = document.getElementById('moto-cal-reserve-btn');
        if(!btn) return;
        var href = '/rezervace?moto=' + state.motoId;
        if(state.startDate) href += '&start=' + state.startDate;
        if(state.endDate) href += '&end=' + state.endDate;
        btn.href = href;
      };
    }
  }, 100);
});
</script>
<?php
echo renderPageEnd($needsSupabase);
