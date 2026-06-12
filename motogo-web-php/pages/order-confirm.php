<?php
// ===== MotoGo24 Web PHP — Legacy redirect na /potvrzeni =====
// Stripe success_url pro e-shop produkty teď míří přímo na /potvrzeni,
// kde polling ověří `payment_status='paid'` a jen pak ukáže děkovací stránku.
// Tato route zůstává pro starší e-mailové odkazy / cache prohlížeče.

$qs = $_SERVER['QUERY_STRING'] ?? '';
// Cíl lokalizujeme (/confirmation, /bestaetigung, …) — jinak by na cizí
// doméně vznikl řetěz 302→301 přes český slug.
$path = function_exists('i18nLocalizePath') ? i18nLocalizePath('/potvrzeni') : '/potvrzeni';
$target = $path . ($qs !== '' ? '?' . $qs : '');
header('Location: ' . $target, true, 302);
exit;
