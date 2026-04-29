<?php
// ===== MotoGo24 Web PHP — Upravit rezervaci =====
// PHP renderuje shell + i18n payload, JS řeší login + edit/cancel/extend/shorten flow.

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('breadcrumb.editReservation')]);

// Předvyplnění z query stringu (např. po kliku z e-mailu).
$bookingId = $_GET['booking'] ?? '';
$resetToken = $_GET['reset'] ?? '';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent pcontent">' .
    '<div id="edit-rez-app"><div class="loading-overlay"><span class="spinner"></span> ' . te('editRez.loading') . '</div></div>' .
    '</div></div></main>';

// i18n payload pro JS — všechny editRez.* + rez.alert.* + storno klíče.
$keys = [
    'editRez.h1','editRez.intro','editRez.loading',
    'editRez.login.title','editRez.login.help','editRez.login.email','editRez.login.password',
    'editRez.login.submit','editRez.login.submitting','editRez.login.error',
    'editRez.login.forgot','editRez.login.tip',
    'editRez.forgot.title','editRez.forgot.help','editRez.forgot.bookingId','editRez.forgot.email',
    'editRez.forgot.submit','editRez.forgot.submitting','editRez.forgot.success','editRez.forgot.error','editRez.forgot.back',
    'editRez.reset.title','editRez.reset.help','editRez.reset.password','editRez.reset.password2',
    'editRez.reset.submit','editRez.reset.submitting','editRez.reset.success','editRez.reset.error',
    'editRez.reset.tooShort','editRez.reset.mismatch',
    'editRez.list.title','editRez.list.shopTitle','editRez.list.vouchersTitle',
    'editRez.list.empty','editRez.list.openNew','editRez.list.choose','editRez.logout',
    'editRez.status.pending','editRez.status.reserved','editRez.status.active','editRez.status.completed','editRez.status.cancelled',
    'editRez.filter.all','editRez.filter.active','editRez.filter.upcoming','editRez.filter.completed','editRez.filter.cancelled',
    'editRez.shopStatus.new','editRez.shopStatus.confirmed','editRez.shopStatus.processing','editRez.shopStatus.shipped',
    'editRez.shopStatus.delivered','editRez.shopStatus.cancelled','editRez.shopStatus.returned','editRez.shopStatus.refunded',
    'editRez.voucherStatus.active','editRez.voucherStatus.redeemed','editRez.voucherStatus.expired','editRez.voucherStatus.cancelled',
    'editRez.doc.title','editRez.doc.empty','editRez.doc.download','editRez.doc.notAvailable','editRez.doc.close',
    'editRez.doc.type.proforma','editRez.doc.type.advance','editRez.doc.type.final','editRez.doc.type.issued',
    'editRez.doc.type.payment_receipt','editRez.doc.type.shop_proforma','editRez.doc.type.shop_final',
    'editRez.doc.type.credit_note','editRez.doc.type.contract','editRez.doc.type.vop','editRez.doc.type.protocol',
    'editRez.doc.type.invoice_advance','editRez.doc.type.invoice_final','editRez.doc.type.invoice_shop',
    'editRez.doc.type.unknown',
    'editRez.detail.title','editRez.detail.bookingId','editRez.detail.moto','editRez.detail.dates',
    'editRez.detail.pickup','editRez.detail.return','editRez.detail.totalPaid','editRez.detail.daysCount',
    'editRez.tab.detail','editRez.tab.extend','editRez.tab.shorten','editRez.tab.cancel',
    'editRez.tab.moto','editRez.tab.location','editRez.tab.docs',
    'editRez.doc.help','editRez.moto.title','editRez.moto.help','editRez.loc.title','editRez.loc.help',
    'editRez.moto.licReq','editRez.moto.licenseInsufficient','editRez.moto.notAvailable',
    'editRez.moto.noOptions','editRez.moto.confirm',
    'editRez.change.success','editRez.change.successWithRefund','editRez.err.activeMotoLocked',
    'editRez.postStripe.applying','editRez.postStripe.error',
    'editRez.loc.pickup','editRez.loc.return','editRez.loc.atRental','editRez.loc.delivery','editRez.loc.deliveryReturn',
    'editRez.loc.addrPlaceholder','editRez.loc.mapBtn','editRez.loc.routing','editRez.loc.geocodeFail',
    'editRez.loc.noPriceChange','editRez.loc.cta','editRez.loc.confirm','editRez.loc.pickOnMap','editRez.loc.pickConfirm',
    'editRez.extend.title','editRez.extend.help','editRez.extend.helpUpcoming','editRez.extend.helpActive',
    'editRez.extend.newStart','editRez.extend.newEnd','editRez.extend.priceDiff','editRez.extend.cta',
    'editRez.extend.unavailable','editRez.extend.noChange','editRez.extend.creating',
    'editRez.shorten.title','editRez.shorten.help','editRez.shorten.helpUpcoming','editRez.shorten.helpActive',
    'editRez.shorten.refund','editRez.shorten.refundZero','editRez.shorten.cta','editRez.shorten.confirming',
    'editRez.shorten.success','editRez.shorten.reasonLabel',
    'editRez.cancel.title','editRez.cancel.warn','editRez.cancel.refundLabel','editRez.cancel.reasonLabel',
    'editRez.cancel.reasonPlaceholder','editRez.cancel.cta','editRez.cancel.confirming','editRez.cancel.success',
    'editRez.cancel.confirmTitle','editRez.cancel.confirmYes','editRez.cancel.confirmNo',
    'editRez.storno.title','editRez.storno.tier1','editRez.storno.tier2','editRez.storno.tier3','editRez.storno.note',
    'editRez.err.generic','editRez.err.notFound','editRez.err.wrongStatus','editRez.err.notPaid',
    'editRez.err.activeStartLocked','editRez.err.invalidRange','editRez.err.notShortening',
    'editRez.err.notExtending','editRez.err.cantEdit','editRez.err.serverDown','editRez.err.emailNotConfirmed',
];
$i18n = [];
foreach ($keys as $k) {
    $v = t($k);
    if (is_string($v)) $i18n[$k] = $v;
}

$js = '<script>
window.MOTOGO_CONFIG = {
  SUPABASE_URL: ' . json_encode(SUPABASE_URL) . ',
  SUPABASE_ANON_KEY: ' . json_encode(SUPABASE_ANON_KEY) . ',
  LANG: ' . json_encode(function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs') . ',
  CURRENCY: ' . json_encode(function_exists('currencyJsConfig') ? currencyJsConfig() : ['current'=>'CZK','rates'=>[]], JSON_UNESCAPED_UNICODE) . '
};
window.MG_I18N = Object.assign(window.MG_I18N || {}, ' . json_encode($i18n, JSON_UNESCAPED_UNICODE) . ');
window.EDIT_REZ_PARAMS = {
  bookingId: ' . json_encode($bookingId) . ',
  resetToken: ' . json_encode($resetToken) . '
};
// Pre-init MG._rez prázdného placeholderu — pages-rezervace-pricing.js
// (který reusneme pro Mapy.cz helpery) sahá na MG._rez.appliedCodes
// během top-level inicializace. Bez tohoto placeholderu se cely JS rozbije.
var MG = window.MG || {};
window.MG = MG;
if (!MG._rez) MG._rez = { appliedCodes: [], discountAmt: 0, motos: [], allBookings: {}, sizes: { rider:{}, passenger:{} } };
if (typeof MG.t !== "function") {
  MG.t = function(k, p){
    var dict = window.MG_I18N || {};
    var s = (typeof dict[k] === "string") ? dict[k] : k;
    if (p && typeof s === "string") Object.keys(p).forEach(function(x){ s = s.split("{"+x+"}").join(String(p[x])); });
    return s;
  };
}
</script>
<script src="' . assetUrl('/js/supabase-sdk.js') . '"></script>
<script src="' . assetUrl('/js/supabase-init.js') . '"></script>
<script src="' . assetUrl('/js/api.js') . '"></script>
<script src="' . assetUrl('/js/components.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-calendar.js') . '"></script>
<script src="' . assetUrl('/js/pages-rezervace-pricing.js') . '"></script>
<script src="' . assetUrl('/js/pages-upravit-rezervaci.js') . '"></script>
<script>
(function(){
  function tryInit(){
    if(window.sb && window.MG && MG._editRezInit){ MG._editRezInit(); }
    else { setTimeout(tryInit, 100); }
  }
  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", function(){ setTimeout(tryInit, 100); });
  } else { setTimeout(tryInit, 100); }
})();
</script>';

renderPage(t('editRez.title'), $content . $js, '/upravit-rezervaci', [
    'description' => t('editRez.description'),
    'robots' => 'noindex,nofollow',
]);
