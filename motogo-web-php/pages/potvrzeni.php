<?php
// ===== MotoGo24 Web PHP — Potvrzení rezervace/objednávky =====
// PHP renderuje HTML shell, JS polluje stav platby přes Supabase

// Zjistíme typ potvrzení z query parametru
$sessionId = $_GET['session_id'] ?? '';
$orderId = $_GET['order_id'] ?? '';
$bookingId = $_GET['booking_id'] ?? '';
$isShop = !empty($orderId);

$bcLabel = $isShop ? t('breadcrumb.confirmationOrder') : t('breadcrumb.confirmation');
$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], $bcLabel]);

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><div id="confirm-content">' .
    '<div class="loading-overlay"><span class="spinner"></span> ' . te('confirm.verifying') . '</div>' .
    '</div></div></div></main>';

// Supabase SDK + JS pro polling
$potvrzeniJs = '<script>
window.MOTOGO_CONFIG = {
  SUPABASE_URL: ' . json_encode(SUPABASE_URL) . ',
  SUPABASE_ANON_KEY: ' . json_encode(SUPABASE_ANON_KEY) . ',
  CURRENCY: ' . json_encode(function_exists('currencyJsConfig') ? currencyJsConfig() : ['current'=>'CZK','rates'=>[]], JSON_UNESCAPED_UNICODE) . '
};
</script>
<script src="' . assetUrl('/js/supabase-sdk.js') . '"></script>
<script src="' . assetUrl('/js/supabase-init.js') . '"></script>
<script src="' . assetUrl('/js/api.js') . '"></script>
<script src="' . assetUrl('/js/pages-potvrzeni.js') . '"></script>';

$pageTitle = $isShop ? t('confirm.titleOrder') : t('confirm.titleBooking');
renderPage($pageTitle, $content . $potvrzeniJs, '/potvrzeni', [
    'robots' => 'noindex,nofollow',
]);
