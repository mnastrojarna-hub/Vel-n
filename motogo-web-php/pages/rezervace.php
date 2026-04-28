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

// Supabase SDK + konfigurace + JS moduly pro rezervaci
$rezervaceJs = '<script>
window.MOTOGO_CONFIG = {
  SUPABASE_URL: ' . json_encode(SUPABASE_URL) . ',
  SUPABASE_ANON_KEY: ' . json_encode(SUPABASE_ANON_KEY) . ',
  LANG: ' . json_encode(function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs') . ',
  CURRENCY: ' . json_encode(function_exists('currencyJsConfig') ? currencyJsConfig() : ['current'=>'CZK','rates'=>[]], JSON_UNESCAPED_UNICODE) . '
};
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
