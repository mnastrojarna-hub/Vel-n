<?php
// ===== MotoGo24 Web PHP — Děkovací stránka po nákupu v e-shopu =====
// Stránka po úspěšném zaplacení produktové objednávky (Stripe success URL pro
// shop produkty). Číslo objednávky vezmeme z URL, plné info dorazí e-mailem.

$orderId = $_GET['order_id'] ?? '';

$bc = renderBreadcrumb([
    ['label' => t('breadcrumb.home'), 'href' => '/'],
    ['label' => t('breadcrumb.shop'), 'href' => '/eshop'],
    t('breadcrumb.confirmationOrder'),
]);

$shortId = $orderId ? strtoupper(substr($orderId, -8)) : '';

// Lokalizované URL — stay v aktuálním jazyce a doméně (cs → .cz, ostatní → .com)
$homeUrl = function_exists('siteCanonicalUrl') ? siteCanonicalUrl('/') : BASE_URL . '/';
$shopUrl = function_exists('siteCanonicalUrl') ? siteCanonicalUrl('/eshop') : BASE_URL . '/eshop';

$body = '<div class="confirm-page confirm-success">'
    . '<div class="confirm-icon" aria-hidden="true">✔</div>'
    . '<h1>' . te('confirm.success.orderTitle') . '</h1>'
    . '<p class="confirm-lead">' . te('confirm.success.thanksAnon') . '</p>'
    . ($shortId ? '<p class="confirm-summary-id">' . te('confirm.success.orderNumber') . ': <strong>#' . htmlspecialchars($shortId) . '</strong></p>' : '')
    . '<p class="confirm-emailed">' . te('confirm.success.emailSentOrder') . '</p>'
    . '<div class="confirm-next">'
    .   '<h3>' . te('confirm.success.nextTitle') . '</h3>'
    .   '<ol>'
    .     '<li>' . te('confirm.success.nextOrderShip') . '</li>'
    .     '<li>' . te('confirm.success.nextContact') . '</li>'
    .   '</ol>'
    . '</div>'
    . '<p class="confirm-actions" style="margin-top:1.5rem">'
    .   '<a class="btn btngreen" href="' . htmlspecialchars($shopUrl) . '">' . te('confirm.success.continueShopping') . '</a>'
    .   '&nbsp;<a class="btn btndark" href="' . htmlspecialchars($homeUrl) . '">' . te('confirm.success.backHome') . '</a>'
    . '</p>'
    . '</div>';

$content = '<main id="content"><div class="container">' . $bc
    . '<article class="ccontent pcontent">' . $body . '</article>'
    . '</div></main>';

// JS: vyčistit košík (pokud zůstal nevyčištěný např. při refreshi)
$confirmJs = '<script>
(function(){
  try { localStorage.removeItem("motogo_cart"); } catch(e){}
  try {
    document.dispatchEvent(new CustomEvent("motogo:cart:changed", {detail:{items:[]}}));
  } catch(e){}
})();
</script>';

renderPage(t('confirm.titleOrder'), $content . $confirmJs, '/objednavka/dokoncit', [
    'description' => t('confirm.success.emailSentOrder'),
    'robots' => 'noindex, nofollow',
]);
