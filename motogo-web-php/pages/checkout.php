<?php
// ===== MotoGo24 Web PHP — E-shop pokladna (/objednavka) =====
// Server emituje layout + i18n; obsah košíku a submit logiku řeší
// js/checkout.js (čte MGCart, volá RPC create_web_shop_order, pak
// proces-payment edge fn → Stripe Checkout). UI sjednoceno se step 1
// rezervace (.rez-section + .rez-step-num + .rez-loc-grid).

$bc = renderBreadcrumb([
    ['label' => t('breadcrumb.home'), 'href' => '/'],
    ['label' => t('breadcrumb.shop'), 'href' => '/eshop'],
    ['label' => t('cart.title'), 'href' => '/kosik'],
    t('checkout.title'),
]);

$emptyHtml = '<div class="checkout-empty" data-checkout-empty hidden>'
    . '<p>' . te('cart.empty') . '</p>'
    . '<p><a class="btn btngreen" href="' . BASE_URL . '/eshop">' . te('cart.continueShopping') . '</a></p>'
    . '</div>';

// Section 1 — kontakt (reusable inputs ze stylu rezervace)
$contactHtml = '<section class="rez-section">'
    . '<div class="rez-section-head"><span class="rez-step-num">1</span><h2>' . te('checkout.contact.title') . '</h2></div>'
    . '<p class="rez-section-sub">' . te('checkout.contact.sub') . '</p>'
    . '<div class="checkout-grid-2">'
    . '<label class="checkout-field"><span>' . te('checkout.contact.name') . ' *</span><input type="text" class="rez-input" id="co-name" name="name" autocomplete="name" required></label>'
    . '<label class="checkout-field"><span>' . te('checkout.contact.email') . ' *</span><input type="email" class="rez-input" id="co-email" name="email" autocomplete="email" required></label>'
    . '<label class="checkout-field"><span>' . te('checkout.contact.phone') . ' *</span><input type="tel" class="rez-input" id="co-phone" name="phone" autocomplete="tel" placeholder="+420 …" required></label>'
    . '</div>'
    . '</section>';

// Section 2 — doprava (3 karty: vyzvednutí / pošta / Zásilkovna)
$shippingHtml = '<section class="rez-section">'
    . '<div class="rez-section-head"><span class="rez-step-num">2</span><h2>' . te('checkout.shipping.title') . '</h2></div>'
    . '<p class="rez-section-sub">' . te('checkout.shipping.sub') . '</p>'
    . '<div class="rez-loc-grid">'
    . '<label class="rez-loc-card">'
    .   '<input type="radio" name="ship" value="pickup" data-ship-method checked>'
    .   '<div class="checkout-ship-info"><strong>' . te('checkout.shipping.pickup') . '</strong>'
    .     '<small>' . te('checkout.shipping.pickupSub') . '</small>'
    .     '<span class="checkout-ship-price">' . te('checkout.shipping.free') . '</span></div>'
    . '</label>'
    . '<label class="rez-loc-card">'
    .   '<input type="radio" name="ship" value="post" data-ship-method>'
    .   '<div class="checkout-ship-info"><strong>' . te('checkout.shipping.post') . '</strong>'
    .     '<small>' . te('checkout.shipping.postSub') . '</small>'
    .     '<span class="checkout-ship-price">' . te('checkout.shipping.postPrice') . '</span></div>'
    . '</label>'
    . '<label class="rez-loc-card">'
    .   '<input type="radio" name="ship" value="zasilkovna" data-ship-method>'
    .   '<div class="checkout-ship-info"><strong>' . te('checkout.shipping.zasilkovna') . '</strong>'
    .     '<small>' . te('checkout.shipping.zasilkovnaSub') . '</small>'
    .     '<span class="checkout-ship-price">' . te('checkout.shipping.zasilkovnaPrice') . '</span></div>'
    . '</label>'
    . '</div>'
    . '<div class="checkout-address" data-checkout-address hidden>'
    . '<div class="checkout-grid-2">'
    . '<label class="checkout-field checkout-field-wide"><span>' . te('checkout.address.street') . ' *</span><input type="text" class="rez-input" id="co-street" name="street" autocomplete="street-address"></label>'
    . '<label class="checkout-field"><span>' . te('checkout.address.zip') . ' *</span><input type="text" class="rez-input" id="co-zip" name="zip" autocomplete="postal-code" inputmode="numeric"></label>'
    . '<label class="checkout-field"><span>' . te('checkout.address.city') . ' *</span><input type="text" class="rez-input" id="co-city" name="city" autocomplete="address-level2"></label>'
    . '<label class="checkout-field"><span>' . te('checkout.address.country') . ' *</span>'
    . '<select class="rez-input" id="co-country" name="country">'
    .   '<option value="CZ" selected>' . te('checkout.address.country.cz') . '</option>'
    .   '<option value="SK">' . te('checkout.address.country.sk') . '</option>'
    .   '<option value="DE">' . te('checkout.address.country.de') . '</option>'
    .   '<option value="AT">' . te('checkout.address.country.at') . '</option>'
    .   '<option value="PL">' . te('checkout.address.country.pl') . '</option>'
    . '</select></label>'
    . '</div>'
    . '</div>'
    . '</section>';

// Section 3 — souhrn objednávky + tlačítko
$summaryHtml = '<section class="rez-section">'
    . '<div class="rez-section-head"><span class="rez-step-num">3</span><h2>' . te('checkout.summary.title') . '</h2></div>'
    . '<div class="checkout-summary-list" data-checkout-items></div>'
    . '<dl class="cart-totals checkout-totals">'
    . '<div class="cart-row"><dt>' . te('cart.subtotal') . '</dt><dd data-checkout-subtotal>—</dd></div>'
    . '<div class="cart-row"><dt>' . te('cart.shipping') . '</dt><dd data-checkout-shipping>—</dd></div>'
    . '<div class="cart-row cart-total-row"><dt>' . te('cart.total') . '</dt><dd data-checkout-total>—</dd></div>'
    . '</dl>'
    . '<label class="checkout-field"><span>' . te('checkout.notes') . '</span>'
    . '<textarea class="rez-input checkout-notes" id="co-notes" name="notes" rows="2" placeholder="' . te('checkout.notesPlaceholder') . '"></textarea></label>'
    . '<p class="checkout-error" data-checkout-error hidden></p>'
    . '<div class="rez-step2-actions">'
    .   '<a class="btn btngrey" href="' . BASE_URL . '/kosik">&larr; ' . te('checkout.backToCart') . '</a>'
    .   '<div class="rez-step2-pay">'
    .     '<span class="rez-step2-amount" data-checkout-pay>—</span>'
    .     '<button type="submit" class="btn btngreen" data-checkout-submit>' . te('checkout.pay') . '</button>'
    .   '</div>'
    . '</div>'
    . '</section>';

$formHtml = '<form id="checkout-form" data-checkout-form onsubmit="return false;" novalidate>'
    . $contactHtml . $shippingHtml . $summaryHtml
    . '</form>';

$loadingHtml = '<div class="checkout-loading" data-checkout-loading><span class="spinner"></span> ' . te('cart.loading') . '</div>';

$content = '<main id="content"><div class="container">' . $bc
    . '<article class="checkout-page ccontent pcontent">'
    . '<h1>' . te('checkout.title') . '</h1>'
    . '<p class="checkout-intro">' . te('checkout.intro') . '</p>'
    . $loadingHtml
    . $emptyHtml
    . '<div data-checkout-content hidden>' . $formHtml . '</div>'
    . '</article>'
    . '</div></main>';

// JS: Supabase SDK + checkout.js
$checkoutJs = '<script>
window.MOTOGO_CONFIG = window.MOTOGO_CONFIG || {};
window.MOTOGO_CONFIG.SUPABASE_URL = ' . json_encode(SUPABASE_URL) . ';
window.MOTOGO_CONFIG.SUPABASE_ANON_KEY = ' . json_encode(SUPABASE_ANON_KEY) . ';
window.MOTOGO_CONFIG.LANG = ' . json_encode(function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs') . ';
</script>
<script src="' . assetUrl('/js/supabase-sdk.js') . '"></script>
<script src="' . assetUrl('/js/supabase-init.js') . '"></script>
<script src="' . assetUrl('/js/checkout.js') . '" defer></script>';

renderPage(t('checkout.title') . ' | ' . t('shop.title'), $content . $checkoutJs, '/objednavka', [
    'description' => mb_substr(t('checkout.intro'), 0, 160),
    'robots' => 'noindex, follow',
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'),  'url' => 'https://motogo24.cz/'],
        ['name' => t('breadcrumb.shop'),  'url' => 'https://motogo24.cz/eshop'],
        ['name' => t('cart.title'),       'url' => 'https://motogo24.cz/kosik'],
        ['name' => t('checkout.title'),   'url' => 'https://motogo24.cz/objednavka'],
    ],
]);
