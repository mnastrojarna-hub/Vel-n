<?php
// ===== MotoGo24 Web PHP — Legacy redirect na /potvrzeni =====
// Stripe success_url pro e-shop produkty teď míří přímo na /potvrzeni,
// kde polling ověří `payment_status='paid'` a jen pak ukáže děkovací stránku.
// Tato route zůstává pro starší e-mailové odkazy / cache prohlížeče.

$qs = $_SERVER['QUERY_STRING'] ?? '';
$target = '/potvrzeni' . ($qs !== '' ? '?' . $qs : '');
header('Location: ' . $target, true, 302);
exit;
