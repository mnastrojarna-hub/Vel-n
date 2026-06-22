<?php
// ===== MotoGo24 Web PHP — Rezervace =====
// PHP renderuje HTML shell + header/footer, JS zajišťuje interaktivitu
// (kalendář, ceník, mapa, OCR, Stripe platby)

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('breadcrumb.reservation')]);

// Předvyplnění z query stringu
$motoId = $_GET['moto'] ?? '';
$startDate = $_GET['start'] ?? '';
$endDate = $_GET['end'] ?? '';
$delivery = $_GET['delivery'] ?? '';
$resume = $_GET['resume'] ?? '';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent pcontent pcontent-wide">' .
    '<h1>' . te('rez.h1') . '</h1>' .
    '<div id="rezervace-app"><div class="loading-overlay"><span class="spinner"></span> ' . te('rezervace.loading') . '</div></div>' .
    '</div></div></main>';

// i18n payload pro JS — všechny rez.* klíče v aktuálním jazyce. JS používá MG.t().
$rezKeys = [
    'h1','intro.title','intro.specific','intro.bike','intro.benefits',
    'loading.resume','notFound.title','notFound.text','notFound.create',
    'error.loading','error.tryAgain',
    'step.moto','step.date','step.contact','step.location','step.gear','step.agreements',
    'contact.name','contact.street','contact.zip','contact.city','contact.country',
    'contact.countryDefault','contact.email','contact.phone','contact.voucher','contact.apply','contact.required','contact.dob',
    'pickup.title','pickup.sub','pickup.recommended','pickup.orCustom',
    'pickup.atRental','pickup.atRentalSub','pickup.delivery','pickup.deliverySub','pickup.deliveryTip',
    'pickup.deliveryAddr','pickup.sameAsDel','pickup.returnOther','pickup.returnTip','pickup.returnAddr','pickup.map','pickup.gps',
    // Geolokace + výpočet trasy přistavení/vrácení + mapový picker (pages-rezervace-pricing.js)
    'geo.failed','geo.denied','geo.unavailable','geo.timeout','geo.insecure','geo.unsupported','geo.found',
    'route.delivery','route.return','route.loading','route.error','route.priceLabel','route.fastestFrom','route.driveTime','route.calc',
    'map.title','map.confirm',
    'return.title','return.sub','return.expectedTitle','return.expectedSub','return.stateTitle','return.stateText',
    'gear.intro','gear.rider','gear.riderSub','gear.riderFree','gear.riderOwn',
    'gear.passenger','gear.passengerSub','gear.passengerTip',
    'gear.bootsRider','gear.bootsPassenger','gear.bootsRiderSub','gear.bootsPassengerSub',
    'gear.trailer','gear.trailerSub','gear.perDay',
    'gear.sizeHintGear','gear.sizeHintPassenger','gear.sizeHintBoots','gear.sizeChoose',
    'gear.label.helmet','gear.label.jacket','gear.label.gloves','gear.label.pants','gear.label.boots',
    'gear.item.passengerExtras','gear.item.bootsRider','gear.item.bootsPassenger','gear.item.trailer',
    'gear.item.delivery','gear.item.return',
    'agree.terms','agree.gdpr','agree.guardian','agree.marketing','agree.photo',
    'cta.continue','cta.continuePay','totalPrice','discount','latePickupDiscount',
    'motoSelect.label','motoSelect.any',
    'voucher.enter','voucher.duplicate','voucher.verifying','voucher.error',
    'voucher.invalid','voucher.percentOnce','voucher.discountApplied','voucher.voucherApplied',
    'alert.name','alert.dob','alert.street','alert.city','alert.zip','alert.email','alert.phone',
    'alert.terms','alert.gdpr','alert.guardian','alert.dates','alert.moto','alert.pickupTime',
    'alert.minTime','alert.minTimeDelivery','alert.returnTime',
    'alert.bookingOverlap','alert.bookingOverlapOwn','alert.error','alert.saveError',
    'alert.selectSize','alert.emailExists','alert.emailMismatch','alert.minRentalDays',
    // Přihlášení / obnova hesla v rezervaci (pages-rezervace-auth.js)
    'auth.returning.title','auth.returning.sub',
    'auth.login.title','auth.login.help','auth.login.submit','auth.login.submitting','auth.login.forgot',
    'auth.forgot.title','auth.forgot.help','auth.forgot.submit','auth.forgot.submitting','auth.forgot.back',
    'auth.otp.title','auth.otp.help','auth.otp.password','auth.otp.password2','auth.otp.submit','auth.otp.submitting',
    'auth.otp.errMissingEmail','auth.otp.errInvalid','auth.otp.errShort','auth.otp.errMismatch','auth.otp.errSave','auth.otp.errSame',
    'auth.email','auth.password','auth.edit','auth.logout',
    'auth.loggedin.title','auth.loggedin.docsOk','auth.loggedin.docsMissing',
    'auth.exists.title','auth.exists.body','auth.exists.btn',
    'auth.err.empty','auth.err.login','auth.err.forgot','auth.err.server',
    // Kalendář (pages-rezervace-calendar.js)
    'cal.month.0','cal.month.1','cal.month.2','cal.month.3','cal.month.4','cal.month.5',
    'cal.month.6','cal.month.7','cal.month.8','cal.month.9','cal.month.10','cal.month.11',
    'cal.dayShort.0','cal.dayShort.1','cal.dayShort.2','cal.dayShort.3','cal.dayShort.4','cal.dayShort.5','cal.dayShort.6',
    'cal.prev','cal.next','cal.legend.free','cal.legend.selected','cal.legend.occupied','cal.legend.unconfirmed',
    'cal.noMotoInRange','cal.freeInRange','cal.pickFromList','cal.selectMoto',
    'cal.rangeOccupied','cal.startSelected','cal.clearSelection','cal.selectedRange',
    // Výběr data platnosti ŘP (pages-rezervace-steps.js)
    'lic.day','lic.month','lic.year',
    // Kamera / scanner dokladů (pages-rezervace-camera.js)
    'cam.docs.id','cam.docs.license','cam.close','cam.hint','cam.shoot','cam.progress','cam.frame',
    // Krok 2 — sken/ověření dokladů (pages-rezervace-scan.js)
    'scan.alert.idNumber','scan.alert.licGroup','scan.alert.licNumber','scan.alert.licExpiry','scan.alert.licValid',
    'scan.alert.licConfirm','scan.alert.pwdShort','scan.alert.pwdMismatch','scan.alert.licRequired','scan.alert.notCreated',
    'scan.alert.shopOrderFail','scan.alert.unknownError','scan.alert.shopOrderException','scan.alert.overlapOther','scan.alert.overlapOwn',
    'scan.alert.paymentError','scan.alert.freeConfirmed','scan.alert.paymentFail','scan.alert.genericError',
    'scan.noLicense','scan.processing','scan.skipRest','scan.skipPay','scan.back',
    'scan.introMobile','scan.introDesktop','scan.title','scan.passport','scan.idCard','scan.recommended',
    'scan.photoSide','scan.bothSides','scan.shoot','scan.uploadDevice','scan.front','scan.backSide',
    'scan.shootFront','scan.uploadFront','scan.shootBack','scan.uploadBack','scan.dl','scan.hint',
    'scan.recognizingFrames','scan.uploaded','scan.recognizing','scan.recognized','scan.docNo',
    'scan.allUploaded','scan.fileUploaded','scan.cantUpload','scan.uploadError','scan.mobileMirror',
    // Krok 1 — výbava, doklady, heslo, náhled faktury (pages-rezervace-steps.js)
    'steps.prev','steps.next','steps.photoAria','steps.inCart','steps.qty','steps.less','steps.more','steps.remove','steps.add','steps.noProducts',
    'steps.invReservation','steps.invRental','steps.invDays','steps.invDiscount','steps.invItem','steps.invPrice','steps.invTotal',
    'steps.verifyAndPay','steps.qrTitle','steps.qrScan','steps.qrBranch','steps.qrValid','steps.docsOkTitle','steps.docsOkText',
    'steps.idTitle','steps.idSub','steps.idDoc','steps.docNumberLabel','steps.docNumberPh','steps.licNumberLabel','steps.licNumberPh',
    'steps.licGroupLabel','steps.licExpiryLabel','steps.licConfirmText','steps.uploadTitle','steps.uploadSub','steps.frontShort','steps.backShort',
    'steps.pwdTitle','steps.pwdSet','steps.pwdSetSub','steps.pwdCreate','steps.pwdCreateSub','steps.pwdPh','steps.pwdConfirmPh',
    'steps.extrasTitle','steps.extrasSub','steps.loadingProducts','steps.invTitle','steps.metaCustomer','steps.metaMotoTerm',
    'steps.metaDelivery','steps.metaReturn','steps.newReservation',
];
$rezI18n = [];
foreach ($rezKeys as $k) {
    $v = t('rez.' . $k);
    if (is_string($v)) $rezI18n['rez.' . $k] = $v;
}
// Krátké názvy dnů — použité v denním rozpisu ceny (calcPriceBreakdown v api.js).
foreach (['0','1','2','3','4','5','6'] as $dow) {
    $dk = 'dow.short.' . $dow;
    $dv = t($dk);
    if (is_string($dv)) $rezI18n[$dk] = $dv;
}

// Supabase SDK + konfigurace + JS moduly pro rezervaci
$rezervaceJs = '<script>
window.MOTOGO_CONFIG = {
  SUPABASE_URL: ' . json_encode(SUPABASE_URL) . ',
  SUPABASE_ANON_KEY: ' . json_encode(SUPABASE_ANON_KEY) . ',
  LANG: ' . json_encode(function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs') . ',
  CURRENCY: ' . json_encode(function_exists('currencyJsConfig') ? currencyJsConfig() : ['current'=>'CZK','rates'=>[]], JSON_UNESCAPED_UNICODE) . '
};
window.MG_I18N = Object.assign(window.MG_I18N || {}, ' . json_encode($rezI18n, JSON_UNESCAPED_UNICODE) . ');
window.REZERVACE_PARAMS = {
  moto: ' . json_encode($motoId) . ',
  start: ' . json_encode($startDate) . ',
  end: ' . json_encode($endDate) . ',
  delivery: ' . json_encode($delivery) . ',
  resume: ' . json_encode($resume) . '
};
// Pre-init MG namespace a _rez state PRED nacitanim JS modulu
var MG = window.MG || {};
window.MG = MG;
MG._rez = { startDate: null, endDate: null, motos: [], motoId: "", allBookings: {}, appliedCodes: [], discountAmt: 0 };
</script>
<script src="' . assetUrl('/js/supabase-sdk.js') . '"></script>
<script src="' . assetUrl('/js/supabase-init.js') . '"></script>
<script src="' . assetUrl('/js/auth-idle-logout.js') . '"></script>
<script src="' . assetUrl('/js/api.js') . '"></script>
<script src="' . assetUrl('/js/components.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-auth.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-calendar.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-pricing.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-steps.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-camera.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-scan.js') . '"></script>
<script>
// Vynucení min_rental_days z DB (per-motorka, nastavuje admin ve Velíně).
// Default je 1 den. Hookne se na _rezPickDate (po vyběru rozsahu v kalendáři),
// při překroceni minima zobrazi alert a vyresetuje výběr. Beží JEN když je
// min_rental_days > 1, jinak žádné omezeni.
(function(){
  function dayCount(s, e){ return Math.round((new Date(e) - new Date(s)) / 86400000) + 1; }
  function selectedMoto(){
    var r = MG._rez || {}; var id = r.motoId; if (!id) return null;
    var list = r.motos || []; for (var i=0;i<list.length;i++) if (list[i].id===id) return list[i];
    return null;
  }
  function validateMinDays(){
    var r = MG._rez || {}; if (!r.startDate || !r.endDate) return true;
    var m = selectedMoto(); if (!m) return true;
    var minDays = parseInt(m.min_rental_days, 10) || 1;
    if (minDays <= 1) return true;
    var n = dayCount(r.startDate, r.endDate);
    if (n < minDays) {
      var msg = (MG.t && MG.t("rez.alert.minRentalDays", { count: minDays }))
        || ("Minimální délka pronájmu této motorky je " + minDays + " dní. Zvolte prosím delší termín.");
      alert(msg);
      if (typeof MG._rezResetDates === "function") MG._rezResetDates();
      return false;
    }
    return true;
  }
  function hookPickDate(){
    if (!MG._rezPickDate || MG._rezPickDate._minDaysHooked) return;
    var orig = MG._rezPickDate;
    MG._rezPickDate = function(e){
      orig.call(this, e);
      validateMinDays();
    };
    MG._rezPickDate._minDaysHooked = true;
  }
  function tryHook(){
    if (MG && MG._rezPickDate) { hookPickDate(); return; }
    setTimeout(tryHook, 100);
  }
  tryHook();
})();
// Spustit inicializaci po načtení všech JS souborů
(function(){
  function tryInit(){
    if(window.sb && MG._rezInit){ MG._rezInit(); }
    else { setTimeout(tryInit, 100); }
  }
  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", function(){ setTimeout(tryInit, 100); });
  } else { setTimeout(tryInit, 100); }
})();
</script>';

renderPage(t('rezervace.title'), $content . $rezervaceJs, '/rezervace', [
    'description' => t('rezervace.description'),
    'keywords' => t('rezervace.keywords'),
    'robots' => 'noindex,follow',
]);
