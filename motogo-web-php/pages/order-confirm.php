<?php
// ===== MotoGo24 Web PHP — Potvrzení e-shop objednávky =====
// Stránka po úspěšném vytvoření objednávky (Stripe success URL).
// Server si dotáhne shop_orders přes service role (placeholder zatím
// zobrazí jen číslo objednávky z URL — kompletní info dorazí v emailu
// a do "Moje objednávky" pro přihlášené).

$orderId = $_GET['order_id'] ?? '';

$bc = renderBreadcrumb([
    ['label' => t('breadcrumb.home'), 'href' => '/'],
    ['label' => t('breadcrumb.shop'), 'href' => '/eshop'],
    t('checkout.confirm.title'),
]);

$shortId = $orderId ? strtoupper(substr($orderId, -8)) : '';
$body = '<div class="checkout-confirm">'
    . '<div class="checkout-confirm-icon" aria-hidden="true">✓</div>'
    . '<h1>' . te('checkout.confirm.heading') . '</h1>'
    . '<p class="checkout-confirm-lead">' . te('checkout.confirm.lead') . '</p>'
    . ($shortId ? '<p class="checkout-confirm-id">' . te('checkout.confirm.orderNumber') . ': <strong>#' . htmlspecialchars($shortId) . '</strong></p>' : '')
    . '<ul class="checkout-confirm-next">'
    .   '<li>' . te('checkout.confirm.next1') . '</li>'
    .   '<li>' . te('checkout.confirm.next2') . '</li>'
    .   '<li>' . te('checkout.confirm.next3') . '</li>'
    . '</ul>'
    . '<p class="checkout-confirm-actions">'
    .   '<a class="btn btngreen" href="' . BASE_URL . '/eshop">' . te('checkout.confirm.continueShopping') . '</a>'
    .   '&nbsp;<a class="btn btndark" href="' . BASE_URL . '/">' . te('checkout.confirm.home') . '</a>'
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

renderPage(t('checkout.confirm.title') . ' | ' . t('shop.title'), $content . $confirmJs, '/objednavka/dokoncit', [
    'description' => t('checkout.confirm.lead'),
    'robots' => 'noindex, nofollow',
]);
