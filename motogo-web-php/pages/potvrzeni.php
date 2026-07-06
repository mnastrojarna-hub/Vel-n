<?php
// ===== MotoGo24 Web PHP — Děkovací stránka po platbě =====
// Společná stránka pro 3 toky (rezervace, e-shop poukaz, free booking).
// PHP renderuje lokalizovaný shell + posílá překlady do JS;
// JS pollne Supabase a doplní dynamická data (jméno, termín, kód poukazu, atd.).

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

// Cílové URL pro tlačítka — RELATIVNÍ, stejná konvence jako logo/menu/patička
// (layout.php používá všude `BASE_URL . '/...'`). Dřív se tu sázelo absolutní
// `siteCanonicalUrl()` (kanonická doména www.motogo24.cz), jenže to z děkovací
// stránky dělalo cross-host skok (apex vs. www, příp. jazyková cookie), který na
// produkci skončil „Stránka nenalezena" (router dostal request na jiný host).
// Relativní cesta drží uživatele na stejném hostu jako zbytek navigace, jazyk se
// dál řeší přes cookie/doménu, a tlačítko „Zpět na úvod" už nikdy nespadne na 404.
$lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
// Cesty lokalizujeme na slug aktuálního jazyka (/shop, /panier, /reserva, …)
// — JS je sází přímo do href, ušetříme 301 hop přes český slug.
$lpp = function ($p) { return function_exists('i18nLocalizePath') ? i18nLocalizePath($p) : $p; };
$homeUrl = BASE_URL . '/';
$shopUrl = BASE_URL . $lpp('/eshop');
$cartUrl = BASE_URL . $lpp('/kosik');
$rezUrl  = BASE_URL . $lpp('/rezervace');
$localeMap = ['cs' => 'cs-CZ', 'en' => 'en-GB', 'de' => 'de-DE', 'es' => 'es-ES', 'fr' => 'fr-FR', 'nl' => 'nl-NL', 'pl' => 'pl-PL', 'uk' => 'uk-UA'];
$jsLocale = $localeMap[$lang] ?? 'cs-CZ';

// Dictionary předáme JS — JS pak nahrazuje {placeholdery} ručně
$confirmI18n = [
    'lang'                => $lang,
    'jsLocale'            => $jsLocale,
    'homeUrl'             => $homeUrl,
    'shopUrl'             => $shopUrl,
    'cartUrl'             => $cartUrl,
    'rezUrl'              => $rezUrl,
    'verifying'           => t('confirm.verifying'),
    'successBookingTitle' => t('confirm.success.bookingTitle'),
    'successOrderTitle'   => t('confirm.success.orderTitle'),
    'successVoucherTitle' => t('confirm.success.voucherTitle'),
    'thanks'              => t('confirm.success.thanks'),
    'thanksAnon'          => t('confirm.success.thanksAnon'),
    'summaryTitle'        => t('confirm.success.summaryTitle'),
    'period'              => t('confirm.success.period'),
    'total'               => t('confirm.success.total'),
    'paid'                => t('confirm.success.paid'),
    'email'               => t('confirm.success.email'),
    'orderNumber'         => t('confirm.success.orderNumber'),
    'bookingNumber'       => t('confirm.success.bookingNumber'),
    'voucherCode'         => t('confirm.success.voucherCode'),
    'validUntil'          => t('confirm.success.validUntil'),
    'emailSentBooking'    => t('confirm.success.emailSentBooking'),
    'emailSentOrder'      => t('confirm.success.emailSentOrder'),
    'emailSentVoucher'    => t('confirm.success.emailSentVoucher'),
    'nextTitle'           => t('confirm.success.nextTitle'),
    'nextBookingDocs'     => t('confirm.success.nextBookingDocs'),
    'nextBookingDocsDone' => t('confirm.success.nextBookingDocsDone'),
    'nextBookingDocsMissing' => t('confirm.success.nextBookingDocsMissing'),
    'docsLabel'           => t('confirm.success.docsLabel'),
    'docsVerified'        => t('confirm.success.docsVerified'),
    'docsNotVerified'     => t('confirm.success.docsNotVerified'),
    'editReservation'     => t('confirm.success.editReservation'),
    'nextBookingCodes'    => t('confirm.success.nextBookingCodes'),
    'nextBookingCodesDone' => t('confirm.success.nextBookingCodesDone'),
    'nextBookingPickup'   => t('confirm.success.nextBookingPickup'),
    'nextOrderShip'       => t('confirm.success.nextOrderShip'),
    'nextVoucherEmail'    => t('confirm.success.nextVoucherEmail'),
    'nextVoucherPrint'    => t('confirm.success.nextVoucherPrint'),
    'nextContact'         => t('confirm.success.nextContact'),
    'seeYouSoon'          => t('confirm.success.seeYouSoon'),
    'backHome'            => t('confirm.success.backHome'),
    'continueShopping'    => t('confirm.success.continueShopping'),
    'pendingTitle'        => t('confirm.pending.title'),
    'pendingText1'        => t('confirm.pending.text1'),
    'pendingText2'        => t('confirm.pending.text2'),
    'pendingNextTitle'    => t('confirm.pending.nextTitle'),
    'pendingNextStep1'    => t('confirm.pending.nextStep1'),
    'pendingNextStep2'    => t('confirm.pending.nextStep2'),
    'pendingNextStep3'    => t('confirm.pending.nextStep3'),
    'pendingFailIntro'    => t('confirm.pending.failIntro'),
    'pendingReason1'      => t('confirm.pending.reason1'),
    'pendingReason2'      => t('confirm.pending.reason2'),
    'pendingReason3'      => t('confirm.pending.reason3'),
    'pendingReason4'      => t('confirm.pending.reason4'),
    'pendingReason5'      => t('confirm.pending.reason5'),
    'pendingReason6'      => t('confirm.pending.reason6'),
    'retryPayment'        => t('confirm.pending.retry'),
    'errorTitle'          => t('confirm.error.title'),
    'errorContactPrefix'  => t('confirm.error.contactPrefix'),
    'errorContactPhone'   => t('confirm.error.contactPhone'),
    'errorTryAgain'       => t('confirm.error.tryAgain'),
    'errorMissingId'      => t('confirm.error.missingId'),
    // QR/převod — děkovací stránka po nahrání dokladů (platba ještě nepotvrzena)
    'qrDocsTitle'         => t('confirm.qrdocs.title'),
    'qrDocsTitleWait'     => t('confirm.qrdocs.titleWait'),
    'qrDocsLead'          => t('confirm.qrdocs.lead'),
    'qrDocsLeadNumbers'   => t('confirm.qrdocs.leadNumbers'),
    'qrDocsLeadNoDocs'    => t('confirm.qrdocs.leadNoDocs'),
    'qrDocsPayInfo'       => t('confirm.qrdocs.payInfo'),
    'qrDocsEmailInfo'     => t('confirm.qrdocs.emailInfo'),
    'qrDocsCodesInfo'     => t('confirm.qrdocs.codesInfo'),
    // Stránka C — „Platba přijata → pokračuj na krok 4 (doklady)" (Stripe, chybí doklady)
    'paydocsTitle'        => t('confirm.paydocs.title'),
    'paydocsLead'         => t('confirm.paydocs.lead'),
    'paydocsLeadAnon'     => t('confirm.paydocs.leadAnon'),
    'paydocsEmailInfo'    => t('confirm.paydocs.emailInfo'),
    'paydocsStep1'        => t('confirm.paydocs.step1'),
    'paydocsStep2'        => t('confirm.paydocs.step2'),
    'paydocsStep3'        => t('confirm.paydocs.step3'),
    'paydocsContinueDocs' => t('confirm.paydocs.continueDocs'),
    'paydocsLater'        => t('confirm.paydocs.later'),
];

// Mapa jsKey → CMS klíč (bez prefixu `web.layout.`) pro inline edit přes
// cms-admin.js. Stejné pořadí/keys jako $confirmI18n; cms-admin.js si na webu
// najde elementy přes `data-cms-key="web.layout.<value>"` a obalí inline editor.
$confirmCmsKeys = [
    'verifying'           => 'confirm.verifying',
    'successBookingTitle' => 'confirm.success.bookingTitle',
    'successOrderTitle'   => 'confirm.success.orderTitle',
    'successVoucherTitle' => 'confirm.success.voucherTitle',
    'thanks'              => 'confirm.success.thanks',
    'thanksAnon'          => 'confirm.success.thanksAnon',
    'summaryTitle'        => 'confirm.success.summaryTitle',
    'period'              => 'confirm.success.period',
    'total'               => 'confirm.success.total',
    'paid'                => 'confirm.success.paid',
    'email'               => 'confirm.success.email',
    'orderNumber'         => 'confirm.success.orderNumber',
    'bookingNumber'       => 'confirm.success.bookingNumber',
    'voucherCode'         => 'confirm.success.voucherCode',
    'validUntil'          => 'confirm.success.validUntil',
    'emailSentBooking'    => 'confirm.success.emailSentBooking',
    'emailSentOrder'      => 'confirm.success.emailSentOrder',
    'emailSentVoucher'    => 'confirm.success.emailSentVoucher',
    'nextTitle'           => 'confirm.success.nextTitle',
    'nextBookingDocs'     => 'confirm.success.nextBookingDocs',
    'nextBookingDocsDone' => 'confirm.success.nextBookingDocsDone',
    'nextBookingDocsMissing' => 'confirm.success.nextBookingDocsMissing',
    'docsLabel'           => 'confirm.success.docsLabel',
    'docsVerified'        => 'confirm.success.docsVerified',
    'docsNotVerified'     => 'confirm.success.docsNotVerified',
    'editReservation'     => 'confirm.success.editReservation',
    'nextBookingCodes'    => 'confirm.success.nextBookingCodes',
    'nextBookingCodesDone' => 'confirm.success.nextBookingCodesDone',
    'nextBookingPickup'   => 'confirm.success.nextBookingPickup',
    'nextOrderShip'       => 'confirm.success.nextOrderShip',
    'nextVoucherEmail'    => 'confirm.success.nextVoucherEmail',
    'nextVoucherPrint'    => 'confirm.success.nextVoucherPrint',
    'nextContact'         => 'confirm.success.nextContact',
    'seeYouSoon'          => 'confirm.success.seeYouSoon',
    'backHome'            => 'confirm.success.backHome',
    'continueShopping'    => 'confirm.success.continueShopping',
    'pendingTitle'        => 'confirm.pending.title',
    'pendingText1'        => 'confirm.pending.text1',
    'pendingText2'        => 'confirm.pending.text2',
    'pendingNextTitle'    => 'confirm.pending.nextTitle',
    'pendingNextStep1'    => 'confirm.pending.nextStep1',
    'pendingNextStep2'    => 'confirm.pending.nextStep2',
    'pendingNextStep3'    => 'confirm.pending.nextStep3',
    'pendingFailIntro'    => 'confirm.pending.failIntro',
    'pendingReason1'      => 'confirm.pending.reason1',
    'pendingReason2'      => 'confirm.pending.reason2',
    'pendingReason3'      => 'confirm.pending.reason3',
    'pendingReason4'      => 'confirm.pending.reason4',
    'pendingReason5'      => 'confirm.pending.reason5',
    'pendingReason6'      => 'confirm.pending.reason6',
    'retryPayment'        => 'confirm.pending.retry',
    'errorTitle'          => 'confirm.error.title',
    'errorContactPrefix'  => 'confirm.error.contactPrefix',
    'errorContactPhone'   => 'confirm.error.contactPhone',
    'errorTryAgain'       => 'confirm.error.tryAgain',
    'errorMissingId'      => 'confirm.error.missingId',
    'qrDocsTitle'         => 'confirm.qrdocs.title',
    'qrDocsTitleWait'     => 'confirm.qrdocs.titleWait',
    'qrDocsLead'          => 'confirm.qrdocs.lead',
    'qrDocsLeadNumbers'   => 'confirm.qrdocs.leadNumbers',
    'qrDocsLeadNoDocs'    => 'confirm.qrdocs.leadNoDocs',
    'qrDocsPayInfo'       => 'confirm.qrdocs.payInfo',
    'qrDocsEmailInfo'     => 'confirm.qrdocs.emailInfo',
    'qrDocsCodesInfo'     => 'confirm.qrdocs.codesInfo',
    'paydocsTitle'        => 'confirm.paydocs.title',
    'paydocsLead'         => 'confirm.paydocs.lead',
    'paydocsLeadAnon'     => 'confirm.paydocs.leadAnon',
    'paydocsEmailInfo'    => 'confirm.paydocs.emailInfo',
    'paydocsStep1'        => 'confirm.paydocs.step1',
    'paydocsStep2'        => 'confirm.paydocs.step2',
    'paydocsStep3'        => 'confirm.paydocs.step3',
    'paydocsContinueDocs' => 'confirm.paydocs.continueDocs',
    'paydocsLater'        => 'confirm.paydocs.later',
];

// Per-type varianty stavu „Pending" (rezervace / objednávka / poukaz) + samostatný
// stav „Neúspěšná platba" (zobrazí se jen když Stripe platbu definitivně odmítne).
// Fallback: pokud konkrétní per-type / failed klíč není ve Velínu přepsaný,
// použije se obecný `confirm.pending.*`. Díky tomu úprava jedné varianty ve Velínu
// neovlivní ostatní, ale neupravené varianty zůstávají konzistentní.
$tFallback = function ($key, $fallbackKey) {
    $v = t($key);
    return ($v === $key) ? t($fallbackKey) : $v;
};
$pendingSuffixes = ['title', 'text1', 'text2', 'nextTitle', 'nextStep1', 'nextStep2', 'nextStep3', 'failIntro', 'reason1', 'reason2', 'reason3', 'reason4', 'reason5', 'reason6', 'retry'];
foreach (['booking' => 'Booking', 'order' => 'Order', 'voucher' => 'Voucher'] as $type => $cap) {
    foreach ($pendingSuffixes as $suf) {
        $jsKey = 'pending' . $cap . ucfirst($suf);
        $confirmI18n[$jsKey] = $tFallback("confirm.pending.$type.$suf", "confirm.pending.$suf");
        $confirmCmsKeys[$jsKey] = "confirm.pending.$type.$suf";
    }
}
foreach ($pendingSuffixes as $suf) {
    $jsKey = 'failed' . ucfirst($suf);
    $confirmI18n[$jsKey] = $tFallback("confirm.failed.$suf", "confirm.pending.$suf");
    $confirmCmsKeys[$jsKey] = "confirm.failed.$suf";
}

// Supabase SDK + JS pro polling
$potvrzeniJs = '<script>
window.MOTOGO_CONFIG = {
  SUPABASE_URL: ' . json_encode(SUPABASE_URL) . ',
  SUPABASE_ANON_KEY: ' . json_encode(SUPABASE_ANON_KEY) . ',
  CURRENCY: ' . json_encode(function_exists('currencyJsConfig') ? currencyJsConfig() : ['current'=>'CZK','rates'=>[]], JSON_UNESCAPED_UNICODE) . '
};
window.MOTOGO_CONFIRM_I18N = ' . json_encode($confirmI18n, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . ';
window.MOTOGO_CONFIRM_CMS_KEYS = ' . json_encode($confirmCmsKeys, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . ';
</script>
<script src="' . assetUrl('/js/supabase-sdk.js') . '"></script>
<script src="' . assetUrl('/js/supabase-init.js') . '"></script>
<script src="' . assetUrl('/js/api.js') . '"></script>
<script src="' . assetUrl('/js/pages-potvrzeni.js') . '"></script>';

$pageTitle = $isShop ? t('confirm.titleOrder') : t('confirm.titleBooking');
renderPage($pageTitle, $content . $potvrzeniJs, '/potvrzeni', [
    'robots' => 'noindex,nofollow',
]);
