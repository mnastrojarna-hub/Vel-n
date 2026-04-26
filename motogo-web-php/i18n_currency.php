<?php
// ===== MotoGo24 Web PHP — Currency layer (CZK base, display in EUR/PLN) =====
//
// Princip (Varianta A):
//   - Backend (Supabase) ukládá VŠECHNY ceny v CZK.
//   - Web zobrazuje v měně, kterou si zákazník vybere (CZK / EUR / PLN).
//   - Stripe Checkout je VŽDY v CZK — žádné FX riziko, na účet dorazí přesná
//     kalkulovaná částka. Banka zákazníka udělá konverzi na výpisu.
//
// Kurz:
//   - Zdroj: ČNB veřejné API https://api.cnb.cz/cnbapi/exrates/daily
//   - Cache: file cache (.cache/fx_rates.json), TTL 15 min — lazy refresh
//     (žádný cron). ČNB publikuje 1× denně cca 14:30 CET.
//   - Fallback chain: fresh cache → stale cache → bundled defaults.
//   - V dropdownu zobrazujeme datum vyhlášení (ČNB `validFor`) i stáří cache.
//
// Detekce měny: ?currency=xxx (uloží cookie) → cookie mg_web_currency
//   → default dle jazyka (cs→CZK, pl→PLN, ostatní→EUR).

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/i18n.php';

const CURRENCY_SUPPORTED = ['CZK', 'EUR', 'PLN'];
const CURRENCY_DEFAULT   = 'CZK';
const CURRENCY_COOKIE    = 'mg_web_currency';
const CURRENCY_CACHE_TTL = 900; // 15 minut

const CURRENCY_META = [
    'CZK' => ['symbol' => 'Kč', 'flag' => '🇨🇿', 'name' => 'Česká koruna', 'decimals' => 0],
    'EUR' => ['symbol' => '€',  'flag' => '🇪🇺', 'name' => 'Euro',          'decimals' => 2],
    'PLN' => ['symbol' => 'zł', 'flag' => '🇵🇱', 'name' => 'Polský zlotý',  'decimals' => 2],
];

// Default mapping jazyk → měna (lze změnit v UI)
const CURRENCY_LANG_DEFAULTS = [
    'cs' => 'CZK',
    'pl' => 'PLN',
    'en' => 'EUR', 'de' => 'EUR', 'es' => 'EUR', 'fr' => 'EUR', 'nl' => 'EUR',
];

// Bezpečné záchytné kurzy (CZK na 1 jednotku měny). Používá se jen když ČNB
// API selže a neexistuje ani stale cache. Záměrně lehce konzervativní —
// reálné kurzy jsou nižší, takže jakýkoliv předpočet v EUR/PLN bude zaokr.
// nahoru a my CZK garantovaně dostaneme.
const CURRENCY_FALLBACK_RATES = [
    'EUR' => 25.50, // 1 EUR ≈ 25.50 CZK
    'PLN' => 5.85,  // 1 PLN ≈ 5.85 CZK
];

/**
 * Detekuje a (případně) uloží zvolenou měnu pro aktuální request.
 */
function currencyDetect() {
    static $cached = null;
    if ($cached !== null) return $cached;

    // 1) ?currency=XXX — explicitní volba
    $fromQuery = isset($_GET['currency']) ? strtoupper(substr((string)$_GET['currency'], 0, 3)) : '';
    if ($fromQuery && in_array($fromQuery, CURRENCY_SUPPORTED, true)) {
        $secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
        if (!headers_sent()) {
            setcookie(CURRENCY_COOKIE, $fromQuery, [
                'expires'  => time() + 365 * 24 * 3600,
                'path'     => '/',
                'secure'   => $secure,
                'httponly' => false,
                'samesite' => 'Lax',
            ]);
        }
        $_COOKIE[CURRENCY_COOKIE] = $fromQuery;
        $cached = $fromQuery;
        return $cached;
    }

    // 2) Cookie
    $fromCookie = $_COOKIE[CURRENCY_COOKIE] ?? '';
    if ($fromCookie && in_array(strtoupper($fromCookie), CURRENCY_SUPPORTED, true)) {
        $cached = strtoupper($fromCookie);
        return $cached;
    }

    // 3) Default dle jazyka
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    $cached = CURRENCY_LANG_DEFAULTS[$lang] ?? CURRENCY_DEFAULT;
    return $cached;
}

/**
 * Cache adresář — preferuje project-local, fallback na sys temp.
 * Vrací null, pokud nelze nikde zapisovat (pak cache vypneme).
 */
function _currencyCacheDir() {
    static $dir = null;
    static $resolved = false;
    if ($resolved) return $dir;
    $resolved = true;
    foreach ([__DIR__ . '/.cache', sys_get_temp_dir() . '/motogo_cache'] as $cand) {
        if (is_dir($cand) && is_writable($cand)) { $dir = $cand; return $dir; }
        if (!is_dir($cand) && @mkdir($cand, 0755, true) && is_writable($cand)) { $dir = $cand; return $dir; }
    }
    return null;
}

/**
 * Stáhne aktuální kurzy z ČNB API a vrátí pole nebo null při chybě.
 * Formát výstupu: {fetched_at, valid_for, rates: {EUR: 25.40, PLN: 5.82}, source: 'CNB'}
 *
 * Kurzy jsou normalizované na "kolik CZK za 1 jednotku zahraniční měny".
 */
function _currencyFetchFromCNB() {
    if (!function_exists('curl_init')) return null;
    try {
        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL            => 'https://api.cnb.cz/cnbapi/exrates/daily?lang=EN',
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER     => ['Accept: application/json'],
            CURLOPT_TIMEOUT        => 4,
            CURLOPT_CONNECTTIMEOUT => 2,
            CURLOPT_USERAGENT      => 'MotoGo24/1.0 (+https://motogo24.com)',
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_MAXREDIRS      => 2,
        ]);
        $resp = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($code < 200 || $code >= 300 || !$resp) return null;

        $data = json_decode($resp, true);
        if (!is_array($data) || !isset($data['rates']) || !is_array($data['rates'])) return null;

        $rates = [];
        $validFor = null;
        foreach ($data['rates'] as $row) {
            $code3 = strtoupper($row['currencyCode'] ?? '');
            if (!in_array($code3, ['EUR', 'PLN'], true)) continue;
            $rate = (float)($row['rate'] ?? 0);
            $amount = (float)($row['amount'] ?? 1);
            if ($amount <= 0 || $rate <= 0) continue;
            // ČNB vrací např. EUR amount=1, rate=24.31 → 1 EUR = 24.31 CZK
            $rates[$code3] = $rate / $amount;
            if (!$validFor && !empty($row['validFor'])) $validFor = $row['validFor'];
        }
        if (empty($rates['EUR']) || empty($rates['PLN'])) return null;

        return [
            'fetched_at' => time(),
            'valid_for'  => $validFor, // YYYY-MM-DD
            'rates'      => $rates,
            'source'     => 'CNB',
            'stale'      => false,
        ];
    } catch (\Throwable $e) {
        @error_log('[MotoGo24] CNB FX fetch failed: ' . $e->getMessage());
        return null;
    }
}

/**
 * Vrací aktuální FX kurzy. Lazy refresh:
 *   - fresh cache (≤ TTL) → vrátíme rovnou
 *   - jinak: pokus o fetch z ČNB → uložíme do cache
 *   - pokud ČNB selže: vrátíme stale cache (s flagem stale=true)
 *   - pokud není ani stale cache: vrátíme bundled defaults
 *
 * Výstup:
 *   {rates: {EUR: 24.31, PLN: 5.65}, fetched_at, valid_for, source, stale}
 */
function currencyRates() {
    static $memo = null;
    if ($memo !== null) return $memo;

    $dir = _currencyCacheDir();
    $file = $dir ? ($dir . '/fx_rates.json') : null;

    // 1) Fresh cache?
    if ($file && file_exists($file) && filemtime($file) >= time() - CURRENCY_CACHE_TTL) {
        $raw = @file_get_contents($file);
        $data = $raw ? json_decode($raw, true) : null;
        if (is_array($data) && !empty($data['rates']['EUR']) && !empty($data['rates']['PLN'])) {
            $memo = $data;
            return $memo;
        }
    }

    // 2) Pokus o fetch z ČNB
    $fresh = _currencyFetchFromCNB();
    if ($fresh) {
        if ($file) @file_put_contents($file, json_encode($fresh), LOCK_EX);
        $memo = $fresh;
        return $memo;
    }

    // 3) Stale cache (i prošlá je lepší než bundled defaults)
    if ($file && file_exists($file)) {
        $raw = @file_get_contents($file);
        $data = $raw ? json_decode($raw, true) : null;
        if (is_array($data) && !empty($data['rates']['EUR']) && !empty($data['rates']['PLN'])) {
            $data['stale'] = true;
            $memo = $data;
            return $memo;
        }
    }

    // 4) Bundled defaults — last resort
    $memo = [
        'fetched_at' => 0,
        'valid_for'  => null,
        'rates'      => CURRENCY_FALLBACK_RATES,
        'source'     => 'fallback',
        'stale'      => true,
    ];
    return $memo;
}

/**
 * Konvertuje CZK částku na zvolenou měnu. CZK → CZK = identita.
 */
function currencyConvert($czk, $targetCurrency = null) {
    if ($czk === null || $czk === '') return null;
    $cur = strtoupper($targetCurrency ?: currencyDetect());
    if ($cur === 'CZK') return (float)$czk;
    $rates = currencyRates()['rates'];
    if (empty($rates[$cur])) return (float)$czk; // safety net
    return (float)$czk / (float)$rates[$cur];
}

/**
 * Zformátuje CZK částku v aktuálně zvolené měně.
 * Použití: money(1500) → "1 500 Kč" / "59 €" / "256 zł" podle nastavení.
 *
 * @param float|int|string|null $czk Částka v CZK
 * @param array $opts Volby: ['currency' => 'EUR'|'PLN'|'CZK', 'with_symbol' => true]
 * @return string
 */
function money($czk, $opts = []) {
    if ($czk === null || $czk === '') return '';
    $cur = strtoupper($opts['currency'] ?? currencyDetect());
    $meta = CURRENCY_META[$cur] ?? CURRENCY_META['CZK'];
    $value = currencyConvert($czk, $cur);
    if ($value === null) return '';

    // Zaokrouhlení podle decimals (CZK celé, EUR/PLN na 2 desetinná)
    $formatted = number_format((float)$value, $meta['decimals'], ',', "\u{00A0}");
    if (!isset($opts['with_symbol']) || $opts['with_symbol']) {
        // CZK: "1 500 Kč" (suffix), EUR: "59,00 €" (suffix), PLN: "256,00 zł" (suffix)
        return $formatted . "\u{00A0}" . $meta['symbol'];
    }
    return $formatted;
}

/** HTML-safe varianta money() */
function moneyHtml($czk, $opts = []) {
    return htmlspecialchars(money($czk, $opts), ENT_QUOTES | ENT_HTML5, 'UTF-8');
}

/**
 * Vrátí text s informací o kurzu pro konkrétní měnu vůči CZK.
 * Např. "1 € = 24,31 Kč (ČNB, 25. 4. 2026)".
 */
function currencyRateLine($currency) {
    $cur = strtoupper($currency);
    if ($cur === 'CZK') return '';
    $info = currencyRates();
    $rate = $info['rates'][$cur] ?? null;
    if (!$rate) return '';
    $rateStr = number_format($rate, 3, ',', "\u{00A0}");
    $sym = CURRENCY_META[$cur]['symbol'] ?? $cur;
    $when = '';
    if (!empty($info['valid_for'])) {
        try {
            $d = new DateTime($info['valid_for']);
            $when = ' · ' . (int)$d->format('j') . '. ' . (int)$d->format('n') . '. ' . $d->format('Y');
        } catch (\Throwable $e) {}
    }
    $src = $info['source'] === 'CNB' ? 'ČNB' : t('currency.source.fallback');
    $stale = !empty($info['stale']) ? ' ⚠' : '';
    return '1 ' . $sym . ' = ' . $rateStr . "\u{00A0}Kč · " . $src . $when . $stale;
}

/**
 * Vyrenderuje currency switcher (analog renderLanguageSwitcher).
 * V dropdownu zobrazí aktuální kurz a datum vyhlášení od ČNB.
 */
function renderCurrencySwitcher() {
    $current = currencyDetect();
    $curMeta = CURRENCY_META[$current] ?? CURRENCY_META[CURRENCY_DEFAULT];
    $info = currencyRates();

    // URL bez ?currency=
    $reqUri = $_SERVER['REQUEST_URI'] ?? '/';
    $parts = parse_url($reqUri);
    $path = $parts['path'] ?? '/';
    $existingQuery = [];
    if (!empty($parts['query'])) {
        parse_str($parts['query'], $existingQuery);
        unset($existingQuery['currency']);
    }
    $baseQuery = !empty($existingQuery) ? ('&' . http_build_query($existingQuery)) : '';

    // Header dropdownu — informace o aktuálním kurzu (vždy vidět při otevření)
    $headerHtml = '<li class="cur-header" role="presentation">'
        . '<div class="cur-header-title">' . te('currency.rate.title') . '</div>'
        . '<div class="cur-header-line">1 € = ' . htmlspecialchars(number_format($info['rates']['EUR'] ?? 0, 3, ',', "\u{00A0}")) . "\u{00A0}Kč</div>"
        . '<div class="cur-header-line">1 zł = ' . htmlspecialchars(number_format($info['rates']['PLN'] ?? 0, 3, ',', "\u{00A0}")) . "\u{00A0}Kč</div>";
    if (!empty($info['valid_for'])) {
        try {
            $d = new DateTime($info['valid_for']);
            $dateStr = (int)$d->format('j') . '. ' . (int)$d->format('n') . '. ' . $d->format('Y');
            $srcName = ($info['source'] === 'CNB') ? 'ČNB' : te('currency.source.fallback');
            $stale = !empty($info['stale']) ? ' ⚠' : '';
            $headerHtml .= '<div class="cur-header-source">' . te('currency.rate.source') . ': '
                . htmlspecialchars($srcName) . ' · ' . htmlspecialchars($dateStr) . $stale . '</div>';
        } catch (\Throwable $e) {}
    } elseif (!empty($info['stale'])) {
        $headerHtml .= '<div class="cur-header-source cur-stale">⚠ ' . te('currency.rate.stale') . '</div>';
    }
    $headerHtml .= '</li><li class="cur-divider" role="presentation"></li>';

    // Položky
    $items = '';
    foreach (CURRENCY_SUPPORTED as $code) {
        $meta = CURRENCY_META[$code];
        $href = htmlspecialchars($path . '?currency=' . $code . $baseQuery);
        $isActive = ($code === $current);
        $cls = 'cur-item' . ($isActive ? ' active' : '');
        $check = $isActive ? '<span class="cur-check" aria-hidden="true">✓</span>' : '';
        // Mini info v položce: u CZK nic, u EUR/PLN aktuální kurz
        $sub = '';
        if ($code !== 'CZK' && !empty($info['rates'][$code])) {
            $rateStr = number_format($info['rates'][$code], 3, ',', "\u{00A0}");
            $sub = '<span class="cur-sub">1 ' . $meta['symbol'] . ' = ' . $rateStr . "\u{00A0}Kč</span>";
        }
        $items .= '<li><a class="' . $cls . '" href="' . $href . '" hreflang="" lang="">'
            . '<span class="cur-flag" aria-hidden="true">' . $meta['flag'] . '</span>'
            . '<span class="cur-name"><span class="cur-code">' . $code . '</span>'
            . '<span class="cur-label">' . htmlspecialchars($meta['name']) . '</span>'
            . $sub . '</span>'
            . $check
            . '</a></li>';
    }

    return '<div class="cur-switcher" data-cur-switcher>'
        . '<button type="button" class="cur-toggle" aria-haspopup="true" aria-expanded="false" aria-label="' . te('currency.select') . '" title="' . te('currency.select') . '">'
            . '<span class="cur-flag" aria-hidden="true">' . $curMeta['flag'] . '</span>'
            . '<span class="cur-code">' . htmlspecialchars($current) . '</span>'
            . '<span class="cur-arrow" aria-hidden="true">▾</span>'
        . '</button>'
        . '<ul class="cur-dropdown" role="menu">' . $headerHtml . $items . '</ul>'
    . '</div>';
}

/**
 * Vrátí pole pro JavaScript bootstrap (aby JS viděl stejné kurzy jako PHP).
 * Použití: window.MOTOGO_CONFIG.CURRENCY = currencyJsConfig();
 */
function currencyJsConfig() {
    $info = currencyRates();
    return [
        'current'   => currencyDetect(),
        'rates'     => $info['rates'],          // CZK na 1 jednotku
        'valid_for' => $info['valid_for'] ?? null,
        'source'    => $info['source'] ?? 'CNB',
        'stale'     => !empty($info['stale']),
        'meta'      => CURRENCY_META,
    ];
}
