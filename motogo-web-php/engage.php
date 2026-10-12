<?php
// ===== MotoGo24 — /api/engage (kvalifikovaná návštěva + kalkulačka) =====
// Přijme beacon z js/engage.js a zapíše 1 řádek do `web_engagement`
// (Supabase REST anon, RLS INSERT). Velín → Analýza → Web funnel z toho
// počítá „Návštěvy (≥5 s)“ a „Použili kalkulačku“ vs. zahájené rezervace.
//
// STRIKTNĚ JEN LIDÉ — beacon musí projít všemi filtry:
//   klient (engage.js): běžící JS, ≥5 s viditelné karty, skutečná interakce
//     (isTrusted myš/dotyk/klávesa), ne navigator.webdriver ani headless UA;
//   server (zde): POST same-origin, známá doména motogo24.*, UA reálného
//     prohlížeče (stejné filtry jako visitor_traffic.php), ne AI crawler.
// Cookieless: visitor_hash = visitorDailyHash() (IP+UA+den, jako visitor_log);
// duplicitu (člověk × den × událost) zahodí unikátní index v DB.
// Odpověď je vždy 204 (nic neprozrazuje), zápis až po odeslání odpovědi.

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/visitor_traffic.php';

header('Cache-Control: no-store');
header('X-Robots-Tag: noindex');

function engageDone() { http_response_code(204); exit; }

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') engageDone();

$host = strtolower(preg_replace('/^www\./', '', $_SERVER['HTTP_HOST'] ?? ''));
if (!visitorHostAllowed($host)) engageDone();

// Same-origin: Origin (pokud je) musí být náš host; Sec-Fetch-Site (pokud je) same-origin.
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if ($origin !== '' && strtolower(preg_replace('/^www\./', '', (string) parse_url($origin, PHP_URL_HOST))) !== $host) engageDone();
$sfs = $_SERVER['HTTP_SEC_FETCH_SITE'] ?? '';
if ($sfs !== '' && $sfs !== 'same-origin') engageDone();

$ua = $_SERVER['HTTP_USER_AGENT'] ?? '';
if (function_exists('aiTrafficDetect') && aiTrafficDetect($ua)) engageDone();
if (visitorIsBot($ua) || !visitorIsHumanBrowser($ua)) engageDone();

$body = json_decode((string) file_get_contents('php://input', false, null, 0, 2048), true);
$event = is_array($body) ? ($body['e'] ?? '') : '';
if ($event !== 'visit' && $event !== 'calc') engageDone();
$p = is_array($body) && is_string($body['p'] ?? null) ? $body['p'] : '/';
if ($p === '' || $p[0] !== '/') $p = '/';

$hash = visitorDailyHash($ua);
if ($hash === null) engageDone();

$payload = [
    'source'       => 'web',
    'event'        => $event,
    'visitor_hash' => $hash,
    'host'         => substr($host, 0, 100),
    'path'         => substr($p, 0, 300),
    'device'       => visitorDevice($ua),
    'lang'         => substr(function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs', 0, 10),
];

http_response_code(204);
if (function_exists('fastcgi_finish_request')) @fastcgi_finish_request();
if (!function_exists('curl_init')) exit;

$ch = curl_init();
curl_setopt_array($ch, [
    CURLOPT_URL => SUPABASE_URL . '/rest/v1/web_engagement',
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => json_encode($payload),
    CURLOPT_HTTPHEADER => [
        'apikey: ' . SUPABASE_ANON_KEY,
        'Authorization: Bearer ' . SUPABASE_ANON_KEY,
        'Content-Type: application/json',
        'Prefer: return=minimal',
    ],
    CURLOPT_TIMEOUT => 3,
    CURLOPT_CONNECTTIMEOUT => 2,
]);
@curl_exec($ch); // 409 = už dnes zapsáno (unikátní index) — v pořádku
@curl_close($ch);
exit;
