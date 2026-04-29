<?php
// ===== MotoGo24 Web PHP — Detail motorky =====
// Odpovídá pages-katalog.js (detail route)

$sb = new SupabaseClient();
$motoId = $_GET['id'] ?? '';
$motos = $sb->fetchMotos();

// Najdi motorku
$moto = null;
$idx = -1;
foreach ($motos as $i => $m) {
    if ($m['id'] === $motoId) {
        $moto = $m;
        $idx = $i;
        break;
    }
}

if (!$moto) {
    $content = '<main id="content"><div class="container">' .
        renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.catalog'), 'href' => '/katalog'], t('detail.notFoundHeading')]) .
        '<div class="ccontent"><h1>' . te('detail.notFoundHeading') . '</h1><p><a class="btn btngreen" href="' . BASE_URL . '/katalog">' . te('detail.backToCatalog') . '</a></p></div></div></main>';
    renderPage(t('detail.notFoundTitle'), $content, '/katalog/' . $motoId);
    return;
}

$model = htmlspecialchars($moto['model'] ?? '');
$prev = $idx > 0 ? $motos[$idx - 1] : null;
$next = $idx < count($motos) - 1 ? $motos[$idx + 1] : null;

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.catalog'), 'href' => '/katalog'], $model]);

// Navigace prev/next
$navHtml = '<nav class="moto-nav">';
$navHtml .= $prev ? '<a class="moto-nav-prev" href="' . BASE_URL . '/katalog/' . htmlspecialchars($prev['id']) . '">&larr; ' . htmlspecialchars($prev['model']) . '</a>' : '<span class="moto-nav-prev moto-nav-disabled"></span>';
$navHtml .= '<a class="moto-nav-back" href="' . BASE_URL . '/katalog">&#8801; ' . te('detail.navBackCatalog') . '</a>';
$navHtml .= $next ? '<a class="moto-nav-next" href="' . BASE_URL . '/katalog/' . htmlspecialchars($next['id']) . '">' . htmlspecialchars($next['model']) . ' &rarr;</a>' : '<span class="moto-nav-next moto-nav-disabled"></span>';
$navHtml .= '</nav>';

// ---- Availability check: dostupné dnes? (rychlý dotaz na RPC booked_dates) ----
$isAvailableToday = false;
if (($moto['status'] ?? '') === 'active') {
    $bookings = $sb->fetchMotoBookings($motoId);
    $today = date('Y-m-d');
    $isAvailableToday = true;
    if (is_array($bookings)) {
        foreach ($bookings as $b) {
            $s = $b['start_date'] ?? '';
            $e = $b['end_date'] ?? '';
            if ($s && $e && $today >= substr($s, 0, 10) && $today <= substr($e, 0, 10)) {
                $isAvailableToday = false;
                break;
            }
        }
    }
}

// ---- Branch info ----
$branch = $moto['branches'] ?? null;
$branchHtml = '';
if (is_array($branch) && !empty($branch['name'])) {
    $addr = trim(($branch['address'] ?? '') . ', ' . ($branch['city'] ?? ''), ', ');
    $branchHtml = '<p class="moto-branch-info"><span aria-hidden="true">📍</span> ' . te('detail.pickupPlace') . ': <strong>' . htmlspecialchars($branch['name']) . '</strong>'
        . ($addr ? ' · ' . htmlspecialchars($addr) : '')
        . '</p>';
}

// Header
$badgeHtml = $isAvailableToday
    ? '<span class="moto-badge-available">' . te('detail.availableToday') . '</span>'
    : (($moto['status'] ?? '') === 'active' ? '<span class="moto-badge-busy">' . te('detail.busyToday') . '</span>' : '');

$headerHtml = '<div class="moto-detail-header"><div>'
    . ($badgeHtml ? '<div>' . $badgeHtml . '</div>' : '')
    . '<h1>' . $model . '</h1>'
    . $branchHtml
    . '</div><div>'
    . '<a class="btn btngreen" href="' . BASE_URL . '/rezervace?moto=' . htmlspecialchars($moto['id']) . '">' . te('common.reserveOnline') . '</a></div></div>';

// Short desc + features (auto-překlad popisku z translations JSONB sloupce)
$motoDesc = localized($moto, 'description');
$descHtml = '<div class="moto-shortdesc">';
if ($motoDesc !== '') {
    $descHtml .= '<div class="wbox"><p>' . htmlspecialchars($motoDesc) . '</p></div><p>&nbsp;</p>';
}
$features = [];
// Výkon (kW + cca koní, pokud máme power_hp)
if (!empty($moto['power_kw'])) {
    $kwBullet = htmlspecialchars($moto['power_kw']) . ' kW';
    if (!empty($moto['power_hp'])) $kwBullet .= ' (cca ' . htmlspecialchars($moto['power_hp']) . ' ' . te('detail.hpUnit') . ')';
    $features[] = '<strong>' . te('detail.specPower') . ':</strong> ' . $kwBullet;
}
// Typ (kategorie)
if (!empty($moto['category'])) $features[] = '<strong>' . te('detail.specType') . ':</strong> ' . htmlspecialchars($moto['category']);
// Motor: ccm + typ + převodovka v jednom bulletu (jako na originálním webu)
$motorParts = [];
if (!empty($moto['engine_cc'])) $motorParts[] = htmlspecialchars($moto['engine_cc']) . ' ccm';
if (!empty($moto['engine_type'])) $motorParts[] = htmlspecialchars($moto['engine_type']);
if (!empty($moto['transmission'])) $motorParts[] = htmlspecialchars($moto['transmission']);
if ($motorParts) $features[] = '<strong>' . te('detail.specEngine') . ':</strong> ' . implode(', ', $motorParts);
// Pohon
if (!empty($moto['drivetrain'])) {
    $dtMap = ['chain' => t('detail.drivetrainChain'), 'shaft' => t('detail.drivetrainShaft'), 'belt' => t('detail.drivetrainBelt')];
    $features[] = '<strong>' . te('detail.specDrivetrain') . ':</strong> ' . htmlspecialchars($dtMap[$moto['drivetrain']] ?? $moto['drivetrain']);
}
// Spotřeba
if (!empty($moto['fuel_consumption_l100km'])) $features[] = '<strong>' . te('detail.specFuelConsumption') . ':</strong> cca ' . htmlspecialchars($moto['fuel_consumption_l100km']) . ' l/100 km';
// Vhodná pro
if (!empty($moto['ideal_usage'])) $features[] = '<strong>' . te('detail.specSuitableFor') . ':</strong> ' . htmlspecialchars($moto['ideal_usage']);
if ($features) {
    $descHtml .= '<h2>' . te('detail.shortDesc') . '</h2><ul>';
    foreach ($features as $f) { $descHtml .= '<li>' . $f . '</li>'; }
    $descHtml .= '</ul><p>&nbsp;</p>';
}
// "Pro koho je motorka vhodná?" — volný HTML/text, plní se ve Velíně (suitable_for sloupec)
$suitableFor = localized($moto, 'suitable_for');
if ($suitableFor !== '') {
    $descHtml .= '<h3>' . te('detail.suitableForTitle') . '</h3>' . sanitizeHtml($suitableFor);
}
if (!empty($moto['features'])) {
    $descHtml .= '<h3>' . te('detail.featuresAdvantages') . '</h3><ul>';
    $featArr = is_string($moto['features']) ? explode(',', $moto['features']) : ($moto['features'] ?? []);
    foreach ($featArr as $f) { if (trim($f)) $descHtml .= '<li>' . htmlspecialchars(trim($f)) . '</li>'; }
    $descHtml .= '</ul>';
}
$descHtml .= '</div>';

// Gallery — sestavíme pole VŠECH fotek (main + ostatní), každá s indexem do lightboxu.
$rawImages = is_array($moto['images'] ?? null) ? $moto['images'] : [];
$mainImg = imgUrl($moto['image_url'] ?? (!empty($rawImages) ? $rawImages[0] : ''));
$allImages = [];
if ($mainImg) $allImages[] = $mainImg;
foreach ($rawImages as $img) {
    $u = imgUrl($img);
    if ($u && !in_array($u, $allImages, true)) $allImages[] = $u;
}
$galleryHtml = '<div class="moto-gallery">';
if (!empty($allImages)) {
    $modelAlt = htmlspecialchars($model, ENT_QUOTES, 'UTF-8');
    $openLabel = htmlspecialchars(t('gallery.openImage'), ENT_QUOTES, 'UTF-8');
    $main = $allImages[0];
    $galleryHtml .= '<div class="moto-photo"><a href="' . htmlspecialchars($main) . '" data-gallery="moto" data-index="0" aria-label="' . $openLabel . '"><div class="gallery-img"><img src="' . htmlspecialchars($main) . '" alt="' . $modelAlt . '" loading="lazy"></div></a></div>';
    if (count($allImages) > 1) {
        $prevLabel = htmlspecialchars(t('gallery.prev'), ENT_QUOTES, 'UTF-8');
        $nextLabel = htmlspecialchars(t('gallery.next'), ENT_QUOTES, 'UTF-8');
        $galleryHtml .= '<div class="moto-thumbs-wrap">';
        $galleryHtml .= '<button type="button" class="moto-thumbs-nav moto-thumbs-prev" aria-label="' . $prevLabel . '">&#10094;</button>';
        $galleryHtml .= '<div class="moto-thumbs">';
        for ($i = 1; $i < count($allImages); $i++) {
            $u = $allImages[$i];
            $galleryHtml .= '<div><a href="' . htmlspecialchars($u) . '" data-gallery="moto" data-index="' . $i . '" aria-label="' . $openLabel . '"><div class="gallery-img"><img src="' . htmlspecialchars($u) . '" alt="' . $modelAlt . '" loading="lazy"></div></a></div>';
        }
        $galleryHtml .= '</div>';
        $galleryHtml .= '<button type="button" class="moto-thumbs-nav moto-thumbs-next" aria-label="' . $nextLabel . '">&#10095;</button>';
        $galleryHtml .= '</div>';
    }
}
$galleryHtml .= '</div>';

$infoHtml = '<section class="moto-info gr2">' . $descHtml . $galleryHtml . '</section>';

// Specs table (pořadí dle originálního webu)
$specsRows = [];
// Identifikace
if (!empty($moto['year']))    $specsRows[] = [t('detail.specYear'), $moto['year']];
if (!empty($moto['color']))   $specsRows[] = [t('detail.specColor'), htmlspecialchars($moto['color'])];
if (!empty($moto['engine_cc'])) $specsRows[] = [t('detail.specEngineCc'), $moto['engine_cc'] . ' ccm'];
if (!empty($moto['power_kw'])) {
    $kwVal = $moto['power_kw'] . ' kW';
    if (!empty($moto['power_hp'])) $kwVal .= ' (cca ' . $moto['power_hp'] . ' ' . t('detail.hpUnit') . ')';
    $specsRows[] = [t('detail.specEngineKw'), $kwVal];
}
if (!empty($moto['torque_nm'])) $specsRows[] = [t('detail.specTorque'), $moto['torque_nm'] . ' Nm'];
if (!empty($moto['engine_type'])) $specsRows[] = [t('detail.specEngineTypeRow'), $moto['engine_type']];
if (!empty($moto['transmission'])) $specsRows[] = [t('detail.specTransmission'), $moto['transmission']];
if (!empty($moto['drivetrain'])) {
    $dtMap = ['chain' => t('detail.drivetrainChain'), 'shaft' => t('detail.drivetrainShaft'), 'belt' => t('detail.drivetrainBelt')];
    $specsRows[] = [t('detail.specDrivetrain'), $dtMap[$moto['drivetrain']] ?? $moto['drivetrain']];
}
if (!empty($moto['top_speed_kmh'])) $specsRows[] = [t('detail.specTopSpeed'), $moto['top_speed_kmh'] . ' km/h'];
if (!empty($moto['fuel_consumption_l100km'])) $specsRows[] = [t('detail.specFuelConsumption'), 'cca ' . $moto['fuel_consumption_l100km'] . ' l/100 km'];
if (!empty($moto['fuel_type'])) $specsRows[] = [t('detail.specFuelType'), $moto['fuel_type']];
if (!empty($moto['fuel_tank_l'])) $specsRows[] = [t('detail.specFuelTank'), $moto['fuel_tank_l'] . ' l'];
if (!empty($moto['brake_type'])) $specsRows[] = [t('detail.specBrakeType'), $moto['brake_type']];
if (!empty($moto['has_abs'])) $specsRows[] = [t('detail.specAbs'), t('detail.specYes')];
if (!empty($moto['has_asc'])) $specsRows[] = [t('detail.specAsc'), t('detail.specYes')];
if (!empty($moto['weight_kg'])) $specsRows[] = [t('detail.specWeight'), $moto['weight_kg'] . ' kg'];
if (!empty($moto['seat_height_mm'])) $specsRows[] = [t('detail.specSeatHeight'), $moto['seat_height_mm'] . ' mm'];
if (!empty($moto['seats_count'])) $specsRows[] = [t('detail.specSeatsCount'), $moto['seats_count']];
if (!empty($moto['license_required'])) $specsRows[] = [t('detail.specLicense'), t('detail.specLicenseGroup', ['group' => $moto['license_required']])];
if (!empty($moto['min_rental_days'])) $specsRows[] = [t('detail.specMinRental'), t('detail.daysUnit', ['count' => (int)$moto['min_rental_days']])];
if (!empty($moto['max_rental_days'])) {
    $specsRows[] = [t('detail.specMaxRental'), t('detail.daysUnit', ['count' => (int)$moto['max_rental_days']])];
}
if (!empty($moto['ideal_usage'])) $specsRows[] = [t('detail.specIdealFor'), $moto['ideal_usage']];

$descSpecsHtml = '<section class="gr2"><div>';
$descSpecsHtml .= '<h2>' . te('detail.descTitle') . '</h2><p>' . htmlspecialchars($motoDesc !== '' ? $motoDesc : ($moto['model'] ?? '')) . '</p>';
if (!empty($moto['manual_url'])) {
    $descSpecsHtml .= '<p>&nbsp;</p><p><a class="btn btngreen" href="' . htmlspecialchars($moto['manual_url']) . '" target="_blank" rel="noopener">' . te('detail.userManual') . '</a></p>';
}
$descSpecsHtml .= '</div><div><h2>' . te('detail.specsTitle') . '</h2>';
if ($specsRows) {
    $descSpecsHtml .= renderTable([t('detail.specHeaderParam'), t('detail.specHeaderValue')], $specsRows);
}
$descSpecsHtml .= '</div></section>';

// Pricing table — názvy dnů ze slovníku
$days = [t('days.mon'), t('days.tue'), t('days.wed'), t('days.thu'), t('days.fri'), t('days.sat'), t('days.sun')];
$priceKeys = ['price_mon', 'price_tue', 'price_wed', 'price_thu', 'price_fri', 'price_sat', 'price_sun'];
$priceRows = [];
foreach ($days as $i => $day) {
    $p = $moto[$priceKeys[$i]] ?? 0;
    if ($p) $priceRows[] = [$day, formatPrice($p)];
}

$pricesHtml = '<section class="moto-prices gr2"><div><h2>' . te('detail.priceTitle') . '</h2>' .
    '<p>' . te('detail.priceLead') . '</p>';
if ($priceRows) $pricesHtml .= renderTable([t('detail.priceHeaderDay'), t('detail.priceHeaderPrice')], $priceRows);
$pricesHtml .= '<p>' . t('detail.priceIncludes') . '</p></div>';

// Kalendář — zůstane jako JS (interaktivní komponenta), labely propagujeme do JS
$calId = 'detail-cal-' . $moto['id'];
$pricesHtml .= '<div class="moto-reservation"><h2>' . te('detail.availabilityTitle') . '</h2>' .
    '<p>' . te('detail.availabilityLead') . '</p>' .
    '<div id="' . $calId . '" class="calendar-placeholder"><div class="loading-overlay"><span class="spinner"></span> ' . te('detail.calendarLoading') . '</div></div>' .
    '<div class="calendar-icons gr3"><div><span class="cicon loosely">&nbsp;</span> ' . te('detail.calendarFree') . '</div><div><span class="cicon occupied">&nbsp;</span> ' . te('detail.calendarOccupied') . '</div><div><span class="cicon unconfirmed">&nbsp;</span> ' . te('detail.calendarPending') . '</div></div>' .
    '<div id="' . $calId . '-banner" style="display:none"></div>' .
    '<p class="calendar-info">' . te('detail.calendarMinDays') . '</p>' .
    '<div class="reservation-btn"><a id="' . $calId . '-reserve-btn" class="btn btngreen" href="' . BASE_URL . '/rezervace?moto=' . htmlspecialchars($moto['id']) . '">' . te('detail.calendarGoToReservation') . '</a></div>' .
'</div></section>';

// Podobné motorky
$related = array_filter($motos, function($m) use ($moto) {
    if ($m['id'] === $moto['id']) return false;
    $sameLP = ($m['license_required'] ?? '') === ($moto['license_required'] ?? '');
    $sameCat = ($m['category'] ?? '') === ($moto['category'] ?? '');
    return $sameLP || $sameCat;
});
usort($related, function($a, $b) use ($moto) {
    $aScore = (($a['category'] ?? '') === ($moto['category'] ?? '') ? 2 : 0) + (($a['license_required'] ?? '') === ($moto['license_required'] ?? '') ? 1 : 0);
    $bScore = (($b['category'] ?? '') === ($moto['category'] ?? '') ? 2 : 0) + (($b['license_required'] ?? '') === ($moto['license_required'] ?? '') ? 1 : 0);
    return $bScore - $aScore;
});
$related = array_slice($related, 0, 4);

$relatedHtml = '';
if ($related) {
    $relatedHtml = '<section class="moto-related"><h2>' . te('detail.relatedTitle') . '</h2><div class="gr4">';
    foreach ($related as $m) {
        $relatedHtml .= '<section aria-label="' . te('filters.aria.catalog') . '">' . renderMotoCard($m) . '</section>';
    }
    $relatedHtml .= '</div></section>';
}

// Inline JS pro kalendář (interaktivní komponenta — zůstává v JS)
$calMonths = [t('months.1'), t('months.2'), t('months.3'), t('months.4'), t('months.5'), t('months.6'), t('months.7'), t('months.8'), t('months.9'), t('months.10'), t('months.11'), t('months.12')];
$calDayNames = [t('days.short.mon'), t('days.short.tue'), t('days.short.wed'), t('days.short.thu'), t('days.short.fri'), t('days.short.sat'), t('days.short.sun')];
// Pořadí Sun-first pro getDay() (0=Sun)
$calDayFull = [t('days.short.sun'), t('days.short.mon'), t('days.short.tue'), t('days.short.wed'), t('days.short.thu'), t('days.short.fri'), t('days.short.sat')];
$calStartLabel = t('detail.calendarStartSelected', ['date' => '__DATE__']);
$calRangeLabel = t('detail.calendarRangeSelected', ['start' => '__START__', 'end' => '__END__']);
$calClearLabel = t('detail.calendarClearSelection');

// Pro AI agenta — kontext aktuálně prohlížené motorky (značka, model, kategorie, cena, výkon).
// Widget si tohle čte z window.MOTOGO_PAGE_CTX a posílá s každou zprávou, ať agent ví,
// na co se zákazník dívá, když řekne "rezervuj mi tuhle motorku".
$aiPageCtx = json_encode([
    'type' => 'moto_detail',
    'moto_id' => $moto['id'] ?? null,
    'brand' => $moto['brand'] ?? null,
    'model' => $moto['model'] ?? null,
    'category' => $moto['category'] ?? null,
    'license_required' => $moto['license_required'] ?? null,
    'power_kw' => $moto['power_kw'] ?? null,
    'price_min_kc' => $moto['price_min'] ?? ($moto['price_mon'] ?? null),
    'status' => $moto['status'] ?? null,
    'available_today' => $isAvailableToday,
], JSON_UNESCAPED_UNICODE);

$calendarJs = '<script>
window.MOTOGO_PAGE_CTX = ' . $aiPageCtx . ';
var SUPABASE_URL = ' . json_encode(SUPABASE_URL) . ';
var SUPABASE_ANON_KEY = ' . json_encode(SUPABASE_ANON_KEY) . ';
var MOTO_ID = ' . json_encode($moto['id']) . ';
var CAL_ID = ' . json_encode($calId) . ';
var CAL_I18N = {
  months: ' . json_encode($calMonths, JSON_UNESCAPED_UNICODE) . ',
  dayNames: ' . json_encode($calDayNames, JSON_UNESCAPED_UNICODE) . ',
  dayFull: ' . json_encode($calDayFull, JSON_UNESCAPED_UNICODE) . ',
  startSelectedTpl: ' . json_encode($calStartLabel, JSON_UNESCAPED_UNICODE) . ',
  rangeSelectedTpl: ' . json_encode($calRangeLabel, JSON_UNESCAPED_UNICODE) . ',
  clearLabel: ' . json_encode($calClearLabel, JSON_UNESCAPED_UNICODE) . '
};

(function(){
  var _calState = {};
  function formatDateCal(iso){
    if(!iso) return "";
    var d = new Date(iso);
    return d.getDate()+"."+(d.getMonth()+1)+"."+d.getFullYear();
  }
  async function fetchBookings(motoId){
    try {
      var r = await fetch(SUPABASE_URL+"/rest/v1/rpc/get_moto_booked_dates",{
        method:"POST",headers:{"apikey":SUPABASE_ANON_KEY,"Authorization":"Bearer "+SUPABASE_ANON_KEY,"Content-Type":"application/json"},
        body:JSON.stringify({p_moto_id:motoId})
      });
      return await r.json();
    } catch(e){ return []; }
  }
  function buildBookedDays(bookings){
    var bookedDays = {}, now = new Date();
    (bookings||[]).forEach(function(b){
      var s=new Date(b.start_date),e=new Date(b.end_date),d=new Date(s);
      var isPending=b.status==="pending",createdAt=b.created_at?new Date(b.created_at):null;
      var isRecent=createdAt&&(now-createdAt)<4*60*60*1000;
      var status=(isPending&&isRecent)?"unconfirmed":"occupied";
      while(d<=e){var key=d.toISOString().split("T")[0];bookedDays[key]=status;d.setDate(d.getDate()+1);}
    });
    return bookedDays;
  }
  async function buildCalendar(){
    var el = document.getElementById(CAL_ID); if(!el) return;
    var bookings = await fetchBookings(MOTO_ID);
    var bookedDays = buildBookedDays(bookings);
    var now = new Date();
    _calState={year:now.getFullYear(),month:now.getMonth(),bookedDays:bookedDays,motoId:MOTO_ID,startDate:null,endDate:null};
    renderMonth();
    startLiveRefresh();
  }
  // Real-time refresh — pending bookings se zobrazí všem v 30s okně (anon RLS bypass přes get_moto_booked_dates RPC)
  var _liveTimer = null;
  function startLiveRefresh(){
    if(_liveTimer) return;
    _liveTimer = setInterval(async function(){
      var el = document.getElementById(CAL_ID);
      if(!el){ clearInterval(_liveTimer); _liveTimer = null; return; }
      var bookings = await fetchBookings(MOTO_ID);
      var fresh = buildBookedDays(bookings);
      if(JSON.stringify(fresh) !== JSON.stringify(_calState.bookedDays)){
        _calState.bookedDays = fresh;
        renderMonth();
      }
    }, 30000);
  }
  function renderMonth(){
    var el=document.getElementById(CAL_ID);if(!el)return;
    var s=_calState,y=s.year,m=s.month;
    var months=CAL_I18N.months;
    var dayNames=CAL_I18N.dayNames,dayFull=CAL_I18N.dayFull;
    var firstDay=new Date(y,m,1),lastDay=new Date(y,m+1,0);
    var startDow=(firstDay.getDay()+6)%7,todayStr=new Date().toISOString().split("T")[0];
    var sd=s.startDate,ed=s.endDate;
    var html=\'<div class="cal-nav"><button onclick="calPrev()">&larr;</button><span>\'+months[m]+" "+y+\'</span><button onclick="calNext()">&rarr;</button></div>\';
    html+=\'<div class="cal-grid">\';
    dayNames.forEach(function(d){html+=\'<div class="cal-header">\'+d+"</div>";});
    for(var i=0;i<startDow;i++)html+=\'<div class="cal-day empty"></div>\';
    for(var d=1;d<=lastDay.getDate();d++){
      var ds=y+"-"+String(m+1).padStart(2,"0")+"-"+String(d).padStart(2,"0");
      var booked=s.bookedDays[ds],isPast=ds<todayStr;
      var inRange=sd&&ed&&ds>=sd&&ds<=ed,isStart=sd&&ds===sd,isEnd=ed&&ds===ed;
      var dayOfWeek=dayFull[new Date(y,m,d).getDay()];
      var bg,color,cursor="default",border="none";
      if(isPast||booked==="occupied"){bg="#444";color="#fff";cursor="not-allowed";}
      else if(booked==="unconfirmed"){bg="#fff";color="#333";cursor="not-allowed";border="2px solid #ccc";}
      else if(isStart||isEnd){bg="#1a8c1a";color="#fff";cursor="pointer";border="2px solid #fff";}
      else if(inRange){bg="#1a8c1a";color="#fff";cursor="pointer";}
      else{bg="#74FB71";color="#0b0b0b";cursor="pointer";}
      var canClick=!isPast&&!booked;
      var style="background:"+bg+";color:"+color+";cursor:"+cursor+";border:"+border+";border-radius:12px;";
      var click=canClick?" onclick=\"calPick(\'"+ds+"\')\"":"";
      html+=\'<div class="cal-day" style="\'+style+\'"\'+click+\'><span style="font-size:.65rem;opacity:.7;display:block;line-height:1">\'+dayOfWeek+"</span><span style=\"font-weight:700\">"+d+"</span></div>";
    }
    html+="</div>";el.innerHTML=html;
  }
  window.calPick=function(ds){
    var s=_calState;
    if(!s.startDate||s.endDate){s.startDate=ds;s.endDate=null;}
    else if(ds<s.startDate){s.startDate=ds;s.endDate=null;}
    else if(ds===s.startDate){s.startDate=null;s.endDate=null;}
    else{s.endDate=ds;}
    renderMonth();updateBanner();updateBtn();
  };
  function updateBanner(){
    var ban=document.getElementById(CAL_ID+"-banner");if(!ban)return;
    var s=_calState;
    if(!s.startDate){ban.style.display="none";return;}
    var clearBtn=\'<span class="btn" style="background:#0b0b0b;color:#74FB71;padding:6px 14px;font-size:.85rem;cursor:pointer;border-radius:20px" onclick="calReset()">\'+CAL_I18N.clearLabel+\'</span>\';
    if(!s.endDate){
      ban.style.display="block";
      var startMsg=CAL_I18N.startSelectedTpl.replace("__DATE__", formatDateCal(s.startDate));
      ban.innerHTML=\'<div style="background:#74FB71;color:#0b0b0b;padding:12px 16px;border-radius:25px;margin:12px 0;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px"><span>\'+startMsg+\'</span>\'+clearBtn+\'</div>\';
      return;
    }
    ban.style.display="block";
    var rangeMsg=CAL_I18N.rangeSelectedTpl.replace("__START__", formatDateCal(s.startDate)).replace("__END__", formatDateCal(s.endDate));
    ban.innerHTML=\'<div style="background:#74FB71;color:#0b0b0b;padding:14px 18px;border-radius:25px;margin:12px 0;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px"><span style="font-size:1.05rem">\'+rangeMsg+\'</span>\'+clearBtn+\'</div>\';
  }
  function updateBtn(){
    var s=_calState;var btn=document.getElementById(CAL_ID+"-reserve-btn");if(!btn)return;
    var href="' . BASE_URL . '/rezervace?moto="+s.motoId;
    if(s.startDate)href+="&start="+s.startDate;
    if(s.endDate)href+="&end="+s.endDate;
    btn.href=href;
  }
  window.calReset=function(){_calState.startDate=null;_calState.endDate=null;renderMonth();updateBanner();updateBtn();};
  window.calPrev=function(){_calState.month--;if(_calState.month<0){_calState.month=11;_calState.year--;}renderMonth();};
  window.calNext=function(){_calState.month++;if(_calState.month>11){_calState.month=0;_calState.year++;}renderMonth();};
  buildCalendar();
})();
</script>';

$content = '<main id="content"><div class="container">' . $bc .
    '<article class="moto-detail ccontent" itemscope itemtype="https://schema.org/Product">' .
        '<header>' . $navHtml . $headerHtml . '</header>' .
        $infoHtml . $descSpecsHtml . $pricesHtml . $relatedHtml .
    '</article></div></main>' . $calendarJs;

// ===== Product + Vehicle (Motorcycle subtype) JSON-LD =====
// AI agenti dostávají kompletní popis motorky: motor, výkon, kapacita,
// cena per den (UnitPriceSpecification), dostupnost (InStock/OutOfStock dle dnes),
// brand, fotky, kategorie ŘP. Schema.org Motorcycle dědí z Vehicle.
$minPrice = getMinPrice($moto);
$availability = $isAvailableToday ? 'https://schema.org/InStock' : 'https://schema.org/PreOrder';
$motoUrl = 'https://motogo24.cz/katalog/' . $motoId;

// Sbírej všechny obrázky (ne jen mainImg)
$schemaImages = [];
if ($mainImg) $schemaImages[] = $mainImg;
if (!empty($moto['images']) && is_array($moto['images'])) {
    foreach ($moto['images'] as $img) {
        $u = imgUrl($img);
        if ($u && !in_array($u, $schemaImages, true)) $schemaImages[] = $u;
    }
}
if (empty($schemaImages)) $schemaImages[] = 'https://motogo24.cz/gfx/logo.svg';

// Per-day pricing → UnitPriceSpecification[]
$dayMap = ['mon' => 'Monday', 'tue' => 'Tuesday', 'wed' => 'Wednesday', 'thu' => 'Thursday', 'fri' => 'Friday', 'sat' => 'Saturday', 'sun' => 'Sunday'];
$priceSpecs = [];
foreach ($dayMap as $short => $long) {
    $p = (float)($moto['price_' . $short] ?? 0);
    if ($p > 0) {
        $priceSpecs[] = '{"@type":"UnitPriceSpecification","price":' . $p . ',"priceCurrency":"CZK","unitCode":"DAY","name":"Cena ' . $long . '","validFrom":null,"eligibleQuantity":{"@type":"QuantitativeValue","unitCode":"DAY","value":1}}';
    }
}

// Vehicle properties — všechno co máme v DB
$vehicleProps = [];
$vehicleProps[] = '"vehicleSpecialUsage":"https://schema.org/RentalVehicleUsage"';
if (!empty($moto['year']))           $vehicleProps[] = '"vehicleModelDate":' . json_encode((string)$moto['year']);
if (!empty($moto['mileage']))        $vehicleProps[] = '"mileageFromOdometer":{"@type":"QuantitativeValue","value":' . (int)$moto['mileage'] . ',"unitCode":"KMT"}';
if (!empty($moto['weight_kg']))      $vehicleProps[] = '"weight":{"@type":"QuantitativeValue","value":' . (float)$moto['weight_kg'] . ',"unitCode":"KGM"}';
if (!empty($moto['fuel_tank_l']))    $vehicleProps[] = '"fuelCapacity":{"@type":"QuantitativeValue","value":' . (float)$moto['fuel_tank_l'] . ',"unitCode":"LTR"}';
if (!empty($moto['seat_height_mm'])) $vehicleProps[] = '"height":{"@type":"QuantitativeValue","value":' . (float)$moto['seat_height_mm'] . ',"unitCode":"MMT","name":"Výška sedla"}';
if (!empty($moto['vin']))            $vehicleProps[] = '"vehicleIdentificationNumber":' . json_encode((string)$moto['vin']);

// Engine — kombinace výkon + zdvih
$engineParts = [];
if (!empty($moto['power_kw']))    $engineParts[] = '"enginePower":{"@type":"QuantitativeValue","value":' . (float)$moto['power_kw'] . ',"unitCode":"KWT"}';
if (!empty($moto['torque_nm']))   $engineParts[] = '"torque":{"@type":"QuantitativeValue","value":' . (float)$moto['torque_nm'] . ',"unitCode":"NU"}';
if (!empty($moto['engine_cc']))   $engineParts[] = '"engineDisplacement":{"@type":"QuantitativeValue","value":' . (float)$moto['engine_cc'] . ',"unitCode":"CMQ"}';
if (!empty($moto['engine_type'])) $engineParts[] = '"name":' . json_encode((string)$moto['engine_type'], JSON_UNESCAPED_UNICODE);
if (!empty($engineParts)) {
    $vehicleProps[] = '"vehicleEngine":{"@type":"EngineSpecification",' . implode(',', $engineParts) . '}';
}

// License required (kategorie ŘP)
if (!empty($moto['license_required'])) {
    $vehicleProps[] = '"requiresSubscription":false';
    $vehicleProps[] = '"audience":{"@type":"Audience","audienceType":"' . htmlspecialchars((string)$moto['license_required']) . ' driving license holders","requiredMinAge":' . ((string)$moto['license_required'] === 'A' ? 24 : ((string)$moto['license_required'] === 'A2' ? 18 : 16)) . '}';
}

// Branch info → seller
$sellerBlock = '';
if (is_array($branch) && !empty($branch['name'])) {
    $sellerBlock = ',"seller":{"@type":"Organization","name":' . json_encode($branch['name'], JSON_UNESCAPED_UNICODE)
        . ',"address":{"@type":"PostalAddress","streetAddress":' . json_encode($branch['address'] ?? '', JSON_UNESCAPED_UNICODE)
        . ',"addressLocality":' . json_encode($branch['city'] ?? '', JSON_UNESCAPED_UNICODE)
        . ',"addressCountry":"CZ"}}';
}

// AggregateRating — pokud máme ≥3 recenzí v cache (z home.php), použijeme je jako globální značku kvality
$reviewAgg = '';
$globalReviews = $sb->fetchPublicReviews(50);
if (is_array($globalReviews) && count($globalReviews) >= 3) {
    $sum = 0; $n = 0;
    foreach ($globalReviews as $r) {
        $rt = (int)($r['rating'] ?? 0);
        if ($rt >= 1 && $rt <= 5) { $sum += $rt; $n++; }
    }
    if ($n >= 3) {
        $avg = round($sum / $n, 2);
        $reviewAgg = ',"aggregateRating":{"@type":"AggregateRating","ratingValue":' . $avg . ',"bestRating":5,"worstRating":1,"ratingCount":' . $n . ',"reviewCount":' . $n . '}';
    }
}

$offerBlock = '{"@type":"Offer","priceCurrency":"CZK","price":' . json_encode($minPrice)
    . ',"availability":' . json_encode($availability)
    . ',"url":' . json_encode($motoUrl)
    . ',"priceValidUntil":' . json_encode(date('Y-m-d', strtotime('+1 year')))
    . ',"businessFunction":"https://purl.org/goodrelations/v1#LeaseOut"'
    . ',"itemCondition":"https://schema.org/UsedCondition"'
    . (!empty($priceSpecs) ? ',"priceSpecification":[' . implode(',', $priceSpecs) . ']' : '')
    . ($sellerBlock !== '' ? $sellerBlock : '')
    . '}';

$brandName = $moto['brand'] ?? '';
$brandBlock = $brandName !== '' ? ',"brand":{"@type":"Brand","name":' . json_encode($brandName, JSON_UNESCAPED_UNICODE) . '}' : '';
$catBlock = !empty($moto['category']) ? ',"category":' . json_encode((string)$moto['category'], JSON_UNESCAPED_UNICODE) : '';
$colorBlock = !empty($moto['color']) ? ',"color":' . json_encode((string)$moto['color'], JSON_UNESCAPED_UNICODE) : '';
$skuBlock = !empty($moto['spz']) ? ',"sku":' . json_encode((string)$moto['spz']) : '';

$descForSchema = $motoDesc !== '' ? $motoDesc : ($moto['model'] ?? '');

$productSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":["Product","Motorcycle"],"name":' . json_encode($moto['model'], JSON_UNESCAPED_UNICODE)
  . ',"description":' . json_encode($descForSchema, JSON_UNESCAPED_UNICODE)
  . ',"image":' . json_encode($schemaImages)
  . ',"url":' . json_encode($motoUrl)
  . $brandBlock . $catBlock . $colorBlock . $skuBlock
  . ',' . implode(',', $vehicleProps)
  . ',"offers":' . $offerBlock
  . $reviewAgg
  . '}
  </script>';

renderPage($model . ' | Půjčovna MotoGo24', $content, '/katalog/' . $motoId, [
    'description' => htmlspecialchars($motoDesc !== '' ? $motoDesc : t('detail.descFallback', ['model' => $moto['model'] ?? ''])),
    'keywords' => t('detail.descKeywords', ['model' => $moto['model'] ?? '']),
    'og_image' => $mainImg ?: null,
    'og_type' => 'product',
    'schema' => $productSchema,
    'breadcrumbs' => [['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')], ['name' => t('breadcrumb.catalog'), 'url' => siteCanonicalUrl('/katalog')], ['name' => $moto['model'], 'url' => siteCanonicalUrl('/katalog/') . $motoId]],
]);
