<?php
// ===== MotoGo24 Web PHP — E-shop košík =====
// Server emituje jen layout + i18n labely; obsah košíku se vykresluje
// z localStorage v js/cart.js (`MGCart.renderCartPage`). Tím přežije
// košík refresh, zůstává guest-friendly a šetří DB requesty.

$bc = renderBreadcrumb([
    ['label' => t('breadcrumb.home'), 'href' => '/'],
    ['label' => t('breadcrumb.shop'), 'href' => '/eshop'],
    t('cart.title'),
]);

$emptyState = '<div class="cart-empty" data-cart-empty hidden>'
    . '<p>' . te('cart.empty') . '</p>'
    . '<p><a class="btn btngreen" href="' . BASE_URL . '/eshop">' . te('cart.continueShopping') . '</a></p>'
    . '</div>';

$listState = '<div class="cart-loaded" data-cart-loaded hidden>'
    . '<div class="cart-grid">'
    . '<div class="cart-items" data-cart-items></div>'
    . '<aside class="cart-summary" aria-label="' . te('cart.summaryAria') . '">'
    . '<h2>' . te('cart.summaryTitle') . '</h2>'
    . '<dl class="cart-totals">'
    . '<div class="cart-row"><dt>' . te('cart.subtotal') . '</dt><dd data-cart-subtotal>—</dd></div>'
    . '<div class="cart-row cart-total-row"><dt>' . te('cart.totalNow') . '</dt><dd data-cart-total>—</dd></div>'
    . '</dl>'
    . '<p class="cart-note">' . te('cart.shippingNote') . '</p>'
    . '<p class="cart-actions">'
    . '<a class="btn btngreen cart-checkout-btn" href="' . BASE_URL . '/objednavka" data-cart-checkout>' . te('cart.checkout') . '</a>'
    . '</p>'
    . '<p class="cart-continue"><a href="' . BASE_URL . '/eshop">&larr; ' . te('cart.continueShopping') . '</a></p>'
    . '</aside>'
    . '</div>'
    . '</div>';

$loadingState = '<div class="cart-loading" data-cart-loading><span class="spinner"></span> ' . te('cart.loading') . '</div>';

$content = '<main id="content"><div class="container">' . $bc
    . '<article class="cart-page ccontent">'
    . '<h1>' . te('cart.title') . '</h1>'
    . $loadingState . $emptyState . $listState
    . '</article>'
    . '</div></main>';

renderPage(t('cart.title') . ' | ' . t('shop.title'), $content, '/kosik', [
    'description' => mb_substr(t('cart.title') . ' — ' . t('shop.intro'), 0, 160),
    'robots' => 'noindex, follow',
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => 'https://motogo24.cz/'],
        ['name' => t('breadcrumb.shop'), 'url' => 'https://motogo24.cz/eshop'],
        ['name' => t('cart.title'), 'url' => 'https://motogo24.cz/kosik'],
    ],
]);
