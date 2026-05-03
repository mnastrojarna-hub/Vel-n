<?php
// ===== MotoGo24 — CLI překladač pages_<lang>.php přes Anthropic API =====
//
// Najde sub-pages v pages_cs.php (master), porovná s pages_<lang>.php,
// a u kterých chybí > THRESHOLD klíčů přeloží celou sub-page přes Anthropic
// (claude-haiku-4-5-20251001, stejný model jako edge fn translate-content).
// Po překladu deep-merguje výsledek a zapíše zpět.
//
// Spuštění (vyžaduje export ANTHROPIC_API_KEY=sk-ant-…):
//   php motogo-web-php/scripts/translate_pages.php [lang|all] [--force]
//   --force  => přeloží i sub-pages, které mají dostatek klíčů (přepíše)
//
// Tip: úspory tokenů — nepřekládá pole, kde už target existuje a má stejný
// počet listů jako CS. `--force` to přebije.

if (PHP_SAPI !== 'cli') { fwrite(STDERR, "Run from CLI only\n"); exit(1); }

$apiKey = getenv('ANTHROPIC_API_KEY');
if (!$apiKey) { fwrite(STDERR, "Missing ANTHROPIC_API_KEY env var\n"); exit(1); }

$args = array_slice($argv, 1);
$langArg = $args[0] ?? 'all';
$force = in_array('--force', $args, true);

$ALL_LANGS = ['en', 'de', 'es', 'fr', 'nl', 'pl'];
$LANG_NAMES = [
    'en' => 'English', 'de' => 'German (Deutsch)', 'es' => 'Spanish (Español)',
    'fr' => 'French (Français)', 'nl' => 'Dutch (Nederlands)', 'pl' => 'Polish (Polski)',
];
$targetLangs = $langArg === 'all' ? $ALL_LANGS : [$langArg];
foreach ($targetLangs as $l) {
    if (!isset($LANG_NAMES[$l])) { fwrite(STDERR, "Unknown lang: $l\n"); exit(1); }
}

$LANG_DIR = __DIR__ . '/../lang/';
$MODEL = 'claude-haiku-4-5-20251001';
$COVERAGE_THRESHOLD = 0.6; // pod tímhle (60%) se sub-page přeloží znovu

$cs = require $LANG_DIR . 'pages_cs.php';
$csPages = $cs['pages'] ?? $cs;
if (!is_array($csPages)) { fwrite(STDERR, "pages_cs.php not array\n"); exit(1); }

foreach ($targetLangs as $lang) {
    $langName = $LANG_NAMES[$lang];
    $targetFile = $LANG_DIR . 'pages_' . $lang . '.php';
    $existing = is_file($targetFile) ? require $targetFile : [];
    $existingPages = $existing['pages'] ?? $existing;
    if (!is_array($existingPages)) $existingPages = [];

    echo "\n=== $lang ($langName) ===\n";

    foreach ($csPages as $pageKey => $csPage) {
        $existingPage = $existingPages[$pageKey] ?? null;
        $coverage = computeCoverage($csPage, $existingPage);
        $csLeaves = countLeaves($csPage);

        if (!$force && $coverage >= $COVERAGE_THRESHOLD) {
            printf("  [SKIP] %-32s coverage %3.0f%% (%d listů)\n", $pageKey, $coverage * 100, $csLeaves);
            continue;
        }

        printf("  [TRANSLATE] %-26s coverage %3.0f%% → %s (%d listů)\n",
            $pageKey, $coverage * 100, $lang, $csLeaves);

        try {
            $translated = translateTree($csPage, $lang, $langName, $apiKey, $MODEL);
            // Deep-merge přes existující — v případě, že existující měl ručně laděné překlady, držíme nově přeložené (pages.* vždy fresh).
            $existingPages[$pageKey] = deepMerge($existingPage ?: [], $translated);
            // Mezikrokový zápis ať se neztrácí progres
            writePages($targetFile, $existingPages, $lang);
            sleep(1); // šetrné rate-limiting
        } catch (Throwable $e) {
            fwrite(STDERR, "    ERROR: " . $e->getMessage() . "\n");
        }
    }
}

echo "\nHotovo.\n";

// =================== Helpers ===================

function countLeaves($v) {
    if (!is_array($v)) return 1;
    $n = 0; foreach ($v as $vv) $n += countLeaves($vv); return $n;
}

function computeCoverage($cs, $existing) {
    if ($existing === null || !is_array($existing)) return 0.0;
    $csLeaves = countLeaves($cs);
    if ($csLeaves === 0) return 1.0;
    $exLeaves = countLeaves($existing);
    return min(1.0, $exLeaves / $csLeaves);
}

function deepMerge($a, $b) {
    if (!is_array($a)) return $b;
    if (!is_array($b)) return $b;
    $isList = function ($arr) {
        if (function_exists('array_is_list')) return array_is_list($arr);
        $i = 0; foreach ($arr as $k => $_) if ($k !== $i++) return false; return true;
    };
    if ($isList($a) || $isList($b)) return $b;
    $out = $a;
    foreach ($b as $k => $v) {
        $out[$k] = isset($out[$k]) ? deepMerge($out[$k], $v) : $v;
    }
    return $out;
}

function translateTree($tree, $lang, $langName, $apiKey, $model) {
    $jsonInput = json_encode($tree, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($jsonInput === false) throw new RuntimeException('JSON encode failed');

    $system = implode("\n", [
        "You are a professional Czech-to-$langName translator for MotoGo24 — a Czech motorcycle rental company.",
        'Translate the provided JSON tree of Czech text values. Output STRICTLY a valid JSON object with the SAME structure (same keys, same array nesting, same array indices) and translated string values.',
        '',
        'STRICT RULES:',
        "- Output language: $langName ($lang). Natural, native, fluent.",
        '- Preserve ALL HTML tags, attributes, structure, inline formatting EXACTLY (e.g. <p>, <h2>, <strong>, <a href="...">, <ul>, <li>, <img>, <br>).',
        '- DO NOT translate or change: URLs (incl. /jak-pujcit/...), email addresses, phone numbers, prices in Kč/EUR, IČO, DIČ, SPZ, VIN, brand names (Honda, Yamaha, BMW, Suzuki, Kawasaki, Ducati...), product SKUs, postal codes, GPS coordinates, file paths to icons (gfx/...svg), CSS classes (btn, btndark...), aria-labels stay translated.',
        '- Keep the company name "MotoGo24" unchanged.',
        '- Keep currency "Kč" as is (not "CZK", not converted).',
        '- Keep Czech proper nouns and place names (Mezná, Vysočina, Praha, Pelhřimov) unchanged.',
        '- Keep template placeholders like {placeholder}, {{var}}, %s, %d unchanged.',
        '- DO NOT translate keys, only values. Keep all booleans, numbers, nulls intact.',
        '- For arrays-of-objects (e.g. process steps, FAQ items), preserve the array order and length.',
        '- Do NOT add commentary, do NOT add markdown fences. Output ONLY the raw JSON object.',
    ]);

    $body = json_encode([
        'model' => $model,
        'max_tokens' => 8192,
        'system' => $system,
        'messages' => [['role' => 'user', 'content' => $jsonInput]],
    ], JSON_UNESCAPED_UNICODE);

    $ch = curl_init('https://api.anthropic.com/v1/messages');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'x-api-key: ' . $apiKey,
            'anthropic-version: 2023-06-01',
            'content-type: application/json',
        ],
        CURLOPT_POSTFIELDS => $body,
        CURLOPT_TIMEOUT => 120,
    ]);
    $resp = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    if ($resp === false) throw new RuntimeException('curl: ' . curl_error($ch));
    curl_close($ch);
    if ($code !== 200) throw new RuntimeException("Anthropic API $code: " . substr($resp, 0, 300));

    $data = json_decode($resp, true);
    $text = trim($data['content'][0]['text'] ?? '');
    if ($text === '') throw new RuntimeException('Empty model response');

    $parsed = json_decode($text, true);
    if (!is_array($parsed)) {
        // Tolerantní fallback — vyříznout JSON blok
        $start = strpos($text, '{');
        $end = strrpos($text, '}');
        if ($start === false || $end === false || $end <= $start) {
            throw new RuntimeException('Invalid JSON from model: ' . substr($text, 0, 200));
        }
        $parsed = json_decode(substr($text, $start, $end - $start + 1), true);
        if (!is_array($parsed)) throw new RuntimeException('Invalid JSON (fallback) from model');
    }
    return $parsed;
}

function writePages($targetFile, $pagesArr, $lang) {
    $out = "<?php\n// MotoGo24 — pages_{$lang}.php (auto-translated by translate_pages.php)\n\n";
    $out .= "return " . exportArray(['pages' => $pagesArr], 0) . ";\n";
    file_put_contents($targetFile, $out);
}

function exportArray($v, $indent = 0) {
    $pad = str_repeat('    ', $indent);
    if (is_array($v)) {
        if (empty($v)) return '[]';
        $isList = function_exists('array_is_list') ? array_is_list($v) : (function ($a) {
            $i = 0; foreach ($a as $k => $_) if ($k !== $i++) return false; return true;
        })($v);
        $lines = [];
        foreach ($v as $k => $vv) {
            $line = $pad . '    ';
            if (!$isList) $line .= var_export((string)$k, true) . ' => ';
            $line .= exportArray($vv, $indent + 1);
            $lines[] = $line;
        }
        return "[\n" . implode(",\n", $lines) . ",\n" . $pad . ']';
    }
    return var_export($v, true);
}
