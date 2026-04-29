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
    '<div id="rezervace-app"><div class="loading-overlay"><span class="spinner"></span> ' . te('rezervace.loading') . '</div></div>' .
    '</div></div></main>';

// i18n payload pro JS — všechny rez.* klíče v aktuálním jazyce. JS používá MG.t().
$rezKeys = [
    'h1','intro.title','intro.specific','intro.bike','intro.benefits',
    'loading.resume','notFound.title','notFound.text','notFound.create',
    'error.loading','error.tryAgain',
    'step.moto','step.date','step.contact','step.location','step.gear','step.agreements',
    'contact.name','contact.street','contact.zip','contact.city','contact.country',
    'contact.countryDefault','contact.email','contact.phone','contact.voucher','contact.apply','contact.required',
    'pickup.title','pickup.sub','pickup.recommended','pickup.orCustom',
    'pickup.atRental','pickup.atRentalSub','pickup.delivery','pickup.deliverySub','pickup.deliveryTip',
    'pickup.deliveryAddr','pickup.sameAsDel','pickup.returnOther','pickup.returnTip','pickup.returnAddr','pickup.map',
    'return.title','return.sub',
    'gear.intro','gear.rider','gear.riderSub','gear.riderFree','gear.riderOwn',
    'gear.passenger','gear.passengerSub','gear.passengerTip',
    'gear.bootsRider','gear.bootsPassenger','gear.bootsRiderSub','gear.bootsPassengerSub',
    'gear.sizeHintGear','gear.sizeHintPassenger','gear.sizeHintBoots','gear.sizeChoose',
    'gear.label.helmet','gear.label.jacket','gear.label.gloves','gear.label.pants','gear.label.boots',
    'gear.item.passengerExtras','gear.item.bootsRider','gear.item.bootsPassenger',
    'gear.item.delivery','gear.item.return',
    'agree.terms','agree.gdpr','agree.marketing','agree.photo',
    'cta.continue','cta.continuePay','totalPrice','discount',
    'motoSelect.label','motoSelect.any',
    'voucher.enter','voucher.duplicate','voucher.verifying','voucher.error',
    'voucher.invalid','voucher.percentOnce','voucher.discountApplied','voucher.voucherApplied',
    'alert.name','alert.street','alert.city','alert.zip','alert.email','alert.phone',
    'alert.terms','alert.dates','alert.moto','alert.pickupTime',
    'alert.minTime','alert.minTimeDelivery','alert.returnTime',
    'alert.bookingOverlap','alert.bookingOverlapOwn','alert.error','alert.saveError',
];
$rezI18n = [];
foreach ($rezKeys as $k) {
    $v = t('rez.' . $k);
    if (is_string($v)) $rezI18n['rez.' . $k] = $v;
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
<script src="' . assetUrl('/js/api.js') . '"></script>
<script src="' . assetUrl('/js/components.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-calendar.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-pricing.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-steps.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-camera.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-scan.js') . '"></script>
<script>
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
