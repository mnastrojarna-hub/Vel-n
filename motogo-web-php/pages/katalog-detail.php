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
        renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Katalog', 'href' => '/katalog'], 'Motorka nenalezena']) .
        '<div class="ccontent"><h1>Motorka nenalezena</h1><p><a class="btn btngreen" href="' . BASE_URL . '/katalog">Zpět na katalog</a></p></div></div></main>';
    renderPage('Motorka nenalezena – Motogo24', $content, '/katalog/' . $motoId);
    return;
}

$model = htmlspecialchars($moto['model'] ?? '');
$prev = $idx > 0 ? $motos[$idx - 1] : null;
$next = $idx < count($motos) - 1 ? $motos[$idx + 1] : null;

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Katalog motorek', 'href' => '/katalog'], $model]);

// Navigace prev/next
$navHtml = '<nav class="moto-nav">';
$navHtml .= $prev ? '<a class="moto-nav-prev" href="' . BASE_URL . '/katalog/' . htmlspecialchars($prev['id']) . '">&larr; ' . htmlspecialchars($prev['model']) . '</a>' : '<span class="moto-nav-prev moto-nav-disabled"></span>';
$navHtml .= '<a class="moto-nav-back" href="' . BASE_URL . '/katalog">&#8801; Katalog motorek</a>';
$navHtml .= $next ? '<a class="moto-nav-next" href="' . BASE_URL . '/katalog/' . htmlspecialchars($next['id']) . '">' . htmlspecialchars($next['model']) . ' &rarr;</a>' : '<span class="moto-nav-next moto-nav-disabled"></span>';
$navHtml .= '</nav>';

// Header
$headerHtml = '<div class="moto-detail-header"><div><h1>' . $model . '</h1></div><div>' .
    '<a class="btn btngreen" href="' . BASE_URL . '/rezervace?moto=' . htmlspecialchars($moto['id']) . '">REZERVOVAT ONLINE</a></div></div>';

// Short desc + features
$descHtml = '<div class="moto-shortdesc">';
if (!empty($moto['description'])) {
    $descHtml .= '<div class="wbox"><p>' . htmlspecialchars($moto['description']) . '</p></div><p>&nbsp;</p>';
}
$features = [];
if (!empty($moto['power_kw'])) $features[] = '<strong>Výkon:</strong> ' . htmlspecialchars($moto['power_kw']) . ' kW';
if (!empty($moto['category'])) $features[] = '<strong>Typ:</strong> ' . htmlspecialchars($moto['category']);
if (!empty($moto['engine_cc'])) $features[] = '<strong>Motor:</strong> ' . htmlspecialchars($moto['engine_cc']) . ' ccm';
if (!empty($moto['engine_type'])) $features[] = '<strong>Motor typ:</strong> ' . htmlspecialchars($moto['engine_type']);
if (!empty($moto['ideal_usage'])) $features[] = '<strong>Vhodná pro:</strong> ' . htmlspecialchars($moto['ideal_usage']);
if ($features) {
    $descHtml .= '<h2>Krátký popis</h2><ul>';
    foreach ($features as $f) { $descHtml .= '<li>' . $f . '</li>'; }
    $descHtml .= '</ul><p>&nbsp;</p>';
}
if (!empty($moto['features'])) {
    $descHtml .= '<h3>Výbava a výhody</h3><ul>';
    $featArr = is_string($moto['features']) ? explode(',', $moto['features']) : ($moto['features'] ?? []);
    foreach ($featArr as $f) { if (trim($f)) $descHtml .= '<li>' . htmlspecialchars(trim($f)) . '</li>'; }
    $descHtml .= '</ul>';
}
$descHtml .= '</div>';

// Gallery
$mainImg = imgUrl($moto['image_url'] ?? ($moto['images'][0] ?? ''));
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
if (!empty($moto['engine_cc'])) $specsRows[] = ['Objem motoru', $moto['engine_cc'] . ' ccm'];
if (!empty($moto['power_kw'])) $specsRows[] = ['Výkon', $moto['power_kw'] . ' kW'];
if (!empty($moto['engine_type'])) $specsRows[] = ['Typ motoru', $moto['engine_type']];
if (!empty($moto['weight_kg'])) $specsRows[] = ['Hmotnost', $moto['weight_kg'] . ' kg'];
if (!empty($moto['seat_height_mm'])) $specsRows[] = ['Výška sedla', $moto['seat_height_mm'] . ' mm'];
if (!empty($moto['fuel_tank_l'])) $specsRows[] = ['Nádrž', $moto['fuel_tank_l'] . ' l'];
if (!empty($moto['has_abs'])) $specsRows[] = ['ABS', 'Ano'];
if (!empty($moto['license_required'])) $specsRows[] = ['Řidičák', 'Skupina ' . $moto['license_required']];
if (!empty($moto['ideal_usage'])) $specsRows[] = ['Ideální pro', $moto['ideal_usage']];

$descSpecsHtml = '<section class="gr2"><div>';
$descSpecsHtml .= '<h2>Popis motorky</h2><p>' . htmlspecialchars($moto['description'] ?? $moto['model']) . '</p>';
if (!empty($moto['manual_url'])) {
    $descSpecsHtml .= '<p>&nbsp;</p><p><a class="btn btngreen" href="' . htmlspecialchars($moto['manual_url']) . '" target="_blank" rel="noopener">Uživatelský manuál</a></p>';
}
$descSpecsHtml .= '</div><div><h2>Technická specifikace</h2>';
if ($specsRows) {
    $descSpecsHtml .= renderTable(['Parametr', 'Hodnota'], $specsRows);
}
$descSpecsHtml .= '</div></section>';

// Pricing table
$days = ['Pondělí', 'Úterý', 'Středa', 'Čtvrtek', 'Pátek', 'Sobota', 'Neděle'];
$priceKeys = ['price_mon', 'price_tue', 'price_wed', 'price_thu', 'price_fri', 'price_sat', 'price_sun'];
$priceRows = [];
foreach ($days as $i => $day) {
    $p = $moto[$priceKeys[$i]] ?? 0;
    if ($p) $priceRows[] = [$day, formatPrice($p)];
}

$pricesHtml = '<section class="moto-prices gr2"><div><h2>Ceník půjčovného</h2>' .
    '<p>Cena půjčení se liší podle dne v týdnu:</p>';
if ($priceRows) $pricesHtml .= renderTable(['Den', 'Cena za den'], $priceRows);
$pricesHtml .= '<p><strong>V ceně je zahrnuta výbava:</strong> helma, bunda, kalhoty a rukavice.</p></div>';

// Kalendář — zůstane jako JS (interaktivní komponenta)
$calId = 'detail-cal-' . $moto['id'];
$pricesHtml .= '<div class="moto-reservation"><h2>Dostupnost</h2>' .
    '<p>Vyberte si volný termín přímo v kalendáři a přejděte na rezervaci.</p>' .
    '<div id="' . $calId . '" class="calendar-placeholder"><div class="loading-overlay"><span class="spinner"></span> Načítám dostupnost...</div></div>' .
    '<div class="calendar-icons gr3"><div><span class="cicon loosely">&nbsp;</span> Volné</div><div><span class="cicon occupied">&nbsp;</span> Obsazené</div><div><span class="cicon unconfirmed">&nbsp;</span> Nepotvrzené</div></div>' .
    '<div id="' . $calId . '-banner" style="display:none"></div>' .
    '<p class="calendar-info">* Vyberte si prosím minimálně 3 souvislé dny.</p>' .
    '<div class="reservation-btn"><a id="' . $calId . '-reserve-btn" class="btn btngreen" href="' . BASE_URL . '/rezervace?moto=' . htmlspecialchars($moto['id']) . '">PŘEJÍT NA REZERVACE</a></div>' .
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
    $relatedHtml = '<section class="moto-related"><h2>Podobné motorky k zapůjčení</h2><div class="gr4">';
    foreach ($related as $m) {
        $relatedHtml .= '<section aria-label="katalog motorek">' . renderMotoCard($m) . '</section>';
    }
    $relatedHtml .= '</div></section>';
}

// Inline JS pro kalendář (interaktivní komponenta — zůstává v JS)
$calendarJs = '<script>
var SUPABASE_URL = ' . json_encode(SUPABASE_URL) . ';
var SUPABASE_ANON_KEY = ' . json_encode(SUPABASE_ANON_KEY) . ';
var MOTO_ID = ' . json_encode($moto['id']) . ';
var CAL_ID = ' . json_encode($calId) . ';

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
  async function buildCalendar(){
    var el = document.getElementById(CAL_ID); if(!el) return;
    var bookings = await fetchBookings(MOTO_ID);
    var bookedDays = {}, now = new Date();
    (bookings||[]).forEach(function(b){
      var s=new Date(b.start_date),e=new Date(b.end_date),d=new Date(s);
      var isPending=b.status==="pending",createdAt=b.created_at?new Date(b.created_at):null;
      var isRecent=createdAt&&(now-createdAt)<4*60*60*1000;
      var status=(isPending&&isRecent)?"unconfirmed":"occupied";
      while(d<=e){var key=d.toISOString().split("T")[0];bookedDays[key]=status;d.setDate(d.getDate()+1);}
    });
    _calState={year:now.getFullYear(),month:now.getMonth(),bookedDays:bookedDays,motoId:MOTO_ID,startDate:null,endDate:null};
    renderMonth();
  }
  function renderMonth(){
    var el=document.getElementById(CAL_ID);if(!el)return;
    var s=_calState,y=s.year,m=s.month;
    var months=["Leden","Únor","Březen","Duben","Květen","Červen","Červenec","Srpen","Září","Říjen","Listopad","Prosinec"];
    var dayNames=["Po","Út","St","Čt","Pá","So","Ne"],dayFull=["Ne","Po","Út","St","Čt","Pá","So"];
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
    if(!s.endDate){
      ban.style.display="block";
      ban.innerHTML=\'<div style="background:#74FB71;color:#0b0b0b;padding:12px 16px;border-radius:25px;margin:12px 0;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px"><span>Vybrán začátek: <strong>\'+formatDateCal(s.startDate)+\'</strong> — klikněte na koncové datum</span><span class="btn" style="background:#0b0b0b;color:#74FB71;padding:6px 14px;font-size:.85rem;cursor:pointer;border-radius:20px" onclick="calReset()">&#x2715; ZRUŠIT VÝBĚR</span></div>\';
      return;
    }
    ban.style.display="block";
    ban.innerHTML=\'<div style="background:#74FB71;color:#0b0b0b;padding:14px 18px;border-radius:25px;margin:12px 0;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px"><span style="font-size:1.05rem"><strong>VYBRANÝ TERMÍN: \'+formatDateCal(s.startDate)+" – "+formatDateCal(s.endDate)+\'</strong></span><span class="btn" style="background:#0b0b0b;color:#74FB71;padding:6px 14px;font-size:.85rem;cursor:pointer;border-radius:20px" onclick="calReset()">&#x2715; ZRUŠIT VÝBĚR</span></div>\';
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

renderPage($model . ' – Motogo24', $content, '/katalog/' . $motoId);
