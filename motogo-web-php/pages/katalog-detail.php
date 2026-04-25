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
if (!empty($moto['power_kw'])) $features[] = '<strong>' . te('detail.specPower') . ':</strong> ' . htmlspecialchars($moto['power_kw']) . ' kW';
if (!empty($moto['category'])) $features[] = '<strong>' . te('detail.specType') . ':</strong> ' . htmlspecialchars($moto['category']);
if (!empty($moto['engine_cc'])) $features[] = '<strong>' . te('detail.specEngine') . ':</strong> ' . htmlspecialchars($moto['engine_cc']) . ' ccm';
if (!empty($moto['engine_type'])) $features[] = '<strong>' . te('detail.specEngineType') . ':</strong> ' . htmlspecialchars($moto['engine_type']);
if (!empty($moto['ideal_usage'])) $features[] = '<strong>' . te('detail.specSuitableFor') . ':</strong> ' . htmlspecialchars($moto['ideal_usage']);
if ($features) {
    $descHtml .= '<h2>' . te('detail.shortDesc') . '</h2><ul>';
    foreach ($features as $f) { $descHtml .= '<li>' . $f . '</li>'; }
    $descHtml .= '</ul><p>&nbsp;</p>';
}
if (!empty($moto['features'])) {
    $descHtml .= '<h3>' . te('detail.featuresAdvantages') . '</h3><ul>';
    $featArr = is_string($moto['features']) ? explode(',', $moto['features']) : ($moto['features'] ?? []);
    foreach ($featArr as $f) { if (trim($f)) $descHtml .= '<li>' . htmlspecialchars(trim($f)) . '</li>'; }
    $descHtml .= '</ul>';
}
$descHtml .= '</div>';

// Gallery
$images = $moto['images'] ?? [];
$mainImg = imgUrl($moto['image_url'] ?? (!empty($images) ? $images[0] : ''));
$galleryHtml = '<div class="moto-gallery">';
if ($mainImg) {
    $galleryHtml .= '<div class="moto-photo"><a href="' . htmlspecialchars($mainImg) . '" target="_blank"><div class="gallery-img"><img src="' . htmlspecialchars($mainImg) . '" alt="' . $model . '" loading="lazy"></div></a></div>';
}
if (!empty($moto['images']) && count($moto['images']) > 1) {
    $galleryHtml .= '<div class="gr3">';
    foreach (array_slice($moto['images'], 1, 3) as $img) {
        $u = imgUrl($img);
        $galleryHtml .= '<div><a href="' . htmlspecialchars($u) . '" target="_blank"><div class="gallery-img"><img src="' . htmlspecialchars($u) . '" alt="' . $model . '" loading="lazy"></div></a></div>';
    }
    $galleryHtml .= '</div>';
}
$galleryHtml .= '</div>';

$infoHtml = '<section class="moto-info gr2">' . $descHtml . $galleryHtml . '</section>';

// Specs table
$specsRows = [];
if (!empty($moto['engine_cc'])) $specsRows[] = [t('detail.specEngineCc'), $moto['engine_cc'] . ' ccm'];
if (!empty($moto['power_kw'])) $specsRows[] = [t('detail.specEngineKw'), $moto['power_kw'] . ' kW'];
if (!empty($moto['engine_type'])) $specsRows[] = [t('detail.specEngineTypeRow'), $moto['engine_type']];
if (!empty($moto['weight_kg'])) $specsRows[] = [t('detail.specWeight'), $moto['weight_kg'] . ' kg'];
if (!empty($moto['seat_height_mm'])) $specsRows[] = [t('detail.specSeatHeight'), $moto['seat_height_mm'] . ' mm'];
if (!empty($moto['fuel_tank_l'])) $specsRows[] = [t('detail.specFuelTank'), $moto['fuel_tank_l'] . ' l'];
if (!empty($moto['has_abs'])) $specsRows[] = [t('detail.specAbs'), t('detail.specYes')];
if (!empty($moto['license_required'])) $specsRows[] = [t('detail.specLicense'), t('detail.specLicenseGroup', ['group' => $moto['license_required']])];
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

$calendarJs = '<script>
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

// Product schema
$minPrice = getMinPrice($moto);
$productSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"Product","name":' . json_encode($moto['model'], JSON_UNESCAPED_UNICODE) . ',"description":' . json_encode($motoDesc !== '' ? $motoDesc : ($moto['model'] ?? ''), JSON_UNESCAPED_UNICODE) . ',"image":' . json_encode($mainImg ?: 'https://motogo24.cz/gfx/logo.svg') . ',"brand":{"@type":"Brand","name":' . json_encode($moto['brand'] ?? '', JSON_UNESCAPED_UNICODE) . '},"offers":{"@type":"Offer","priceCurrency":"CZK","price":' . json_encode($minPrice) . ',"availability":"https://schema.org/InStock","url":"https://motogo24.cz/katalog/' . $motoId . '"}}
  </script>';

renderPage($model . ' | Půjčovna MotoGo24', $content, '/katalog/' . $motoId, [
    'description' => htmlspecialchars($motoDesc !== '' ? $motoDesc : t('detail.descFallback', ['model' => $moto['model'] ?? ''])),
    'keywords' => t('detail.descKeywords', ['model' => $moto['model'] ?? '']),
    'og_image' => $mainImg ?: null,
    'og_type' => 'product',
    'schema' => $productSchema,
    'breadcrumbs' => [['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'], ['name' => t('breadcrumb.catalog'), 'url' => 'https://motogo24.cz/katalog'], ['name' => $moto['model'], 'url' => 'https://motogo24.cz/katalog/' . $motoId]],
]);
