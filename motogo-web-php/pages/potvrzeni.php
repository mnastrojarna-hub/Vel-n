<?php
// ===== MotoGo24 Web PHP — Potvrzení rezervace/objednávky =====
// PHP renderuje HTML shell, JS polluje stav platby přes Supabase

// Zjistíme typ potvrzení z query parametru
$sessionId = $_GET['session_id'] ?? '';
$orderId = $_GET['order_id'] ?? '';
$bookingId = $_GET['booking_id'] ?? '';
$isShop = !empty($orderId);

$bcLabel = $isShop ? 'Potvrzení objednávky' : 'Potvrzení rezervace';
$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], $bcLabel]);

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><div id="confirm-content">' .
    '<div class="loading-overlay"><span class="spinner"></span> Ověřujeme platbu...</div>' .
    '</div></div></div></main>';

// Supabase SDK + JS pro polling
$potvrzeniJs = '<script>
window.MOTOGO_CONFIG = {
  SUPABASE_URL: ' . json_encode(SUPABASE_URL) . ',
  SUPABASE_ANON_KEY: ' . json_encode(SUPABASE_ANON_KEY) . '
};
</script>
<script src="' . BASE_URL . '/js/supabase-sdk.js"></script>
<script src="' . BASE_URL . '/js/supabase-init.js"></script>
<script src="' . BASE_URL . '/js/api.js"></script>
<script src="' . BASE_URL . '/js/pages-potvrzeni.js"></script>';

renderPage($bcLabel . ' – Motogo24', $content . $potvrzeniJs, '/potvrzeni');
