<?php
// ===== MotoGo24 — AI Traffic Detection & Logging =====
// Detekuje AI crawlery podle User-Agent a loguje request do `ai_traffic_log`
// (přes Supabase REST anon — RLS politika "Service role insert" povolí nezablokovaný anon insert
// nebo přes RPC, podle toho co je k dispozici. Aktuálně přes přímý insert s anon klíčem,
// RLS politika INSERT WITH CHECK (true) tu insert dovolí všem).
//
// Logging je fire-and-forget: nezablokuje render, error tichý log do error_log.

require_once __DIR__ . '/config.php';

/**
 * Detekuje AI bota podle User-Agent. Vrací pole [bot_name, source] nebo null pro lidi.
 * @return array{0:string,1:string}|null
 */
function aiTrafficDetect($ua) {
    if (!is_string($ua) || $ua === '') return null;
    // Pořadí dle specificity — Claude-User před ClaudeBot, atd.
    $patterns = [
        // OpenAI
        ['ChatGPT-User',          'ChatGPT-User',         'crawler'],
        ['OAI-SearchBot',         'OAI-SearchBot',        'crawler'],
        ['GPTBot',                'GPTBot',               'crawler'],
        // Anthropic
        ['Claude-SearchBot',      'Claude-SearchBot',     'crawler'],
        ['Claude-User',           'Claude-User',          'crawler'],
        ['ClaudeBot',             'ClaudeBot',            'crawler'],
        ['anthropic-ai',          'anthropic-ai',         'crawler'],
        // Perplexity
        ['Perplexity-User',       'Perplexity-User',      'crawler'],
        ['PerplexityBot',         'PerplexityBot',        'crawler'],
        // Google AI
        ['Google-Extended',       'Google-Extended',      'crawler'],
        ['GoogleOther',           'GoogleOther',          'crawler'],
        // Apple
        ['Applebot-Extended',     'Applebot-Extended',    'crawler'],
        // Meta
        ['Meta-ExternalAgent',    'Meta-ExternalAgent',   'crawler'],
        ['Meta-ExternalFetcher',  'Meta-ExternalFetcher', 'crawler'],
        ['FacebookBot',           'FacebookBot',          'crawler'],
        // Ostatní
        ['Bytespider',            'Bytespider',           'crawler'],
        ['cohere-ai',             'cohere-ai',            'crawler'],
        ['DuckAssistBot',         'DuckAssistBot',        'crawler'],
        ['Amazonbot',             'Amazonbot',            'crawler'],
        ['Diffbot',               'Diffbot',              'crawler'],
        ['YouBot',                'YouBot',               'crawler'],
        ['PetalBot',              'PetalBot',             'crawler'],
        ['MistralAI-User',        'MistralAI-User',       'crawler'],
    ];
    foreach ($patterns as [$needle, $name, $source]) {
        if (stripos($ua, $needle) !== false) {
            return [$name, $source];
        }
    }
    return null;
}

/**
 * Zaloguje request do ai_traffic_log. Fire-and-forget (krátký timeout).
 * Volá se jen pokud aiTrafficDetect() vrátil bot.
 */
function aiTrafficLog($botName, $source, $path, $method, $lang, $statusCode = 200) {
    if (!function_exists('curl_init')) return;

    $ip = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '';
    if (strpos($ip, ',') !== false) $ip = trim(explode(',', $ip)[0]);
    $ipHash = $ip !== '' ? hash('sha256', $ip . '|motogo24') : null;

    $payload = [
        'source'     => $source,
        'bot_name'   => $botName,
        'user_agent' => substr($_SERVER['HTTP_USER_AGENT'] ?? '', 0, 500),
        'path'       => $path,
        'method'     => $method,
        'lang'       => $lang,
        'ip_hash'    => $ipHash,
        'status_code'=> $statusCode,
        'latency_ms' => 0,
        'outcome'    => 'view',
        'details'    => new stdClass(),
    ];

    $url = SUPABASE_URL . '/rest/v1/ai_traffic_log';
    $ch = curl_init();
    curl_setopt_array($ch, [
        CURLOPT_URL => $url,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_HTTPHEADER => [
            'apikey: ' . SUPABASE_ANON_KEY,
            'Authorization: Bearer ' . SUPABASE_ANON_KEY,
            'Content-Type: application/json',
            'Prefer: return=minimal',
        ],
        CURLOPT_TIMEOUT => 2,
        CURLOPT_CONNECTTIMEOUT => 1,
    ]);
    @curl_exec($ch);
    @curl_close($ch);
}

/**
 * One-shot helper: detekuje + loguje pokud je bot. Volá se z index.php před
 * jakýmkoliv routingem. Žádný side-effect pokud není bot.
 */
function aiTrafficMaybeLog($path, $lang) {
    $ua = $_SERVER['HTTP_USER_AGENT'] ?? '';
    $det = aiTrafficDetect($ua);
    if (!$det) return;
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    aiTrafficLog($det[0], $det[1], $path, $method, $lang, 200);
}
