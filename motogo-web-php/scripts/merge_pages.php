<?php
// ===== MotoGo24 — Merge pages_<lang>_a/b/c.php → pages_<lang>.php =====
// Slouci 3 dilci preklady do jednoho finalniho souboru per jazyk.
// Spusti: php motogo-web-php/scripts/merge_pages.php

$langs = ['en', 'de', 'es', 'fr', 'nl', 'pl'];
$langDir = __DIR__ . '/../lang/';

foreach ($langs as $lang) {
    $merged = ['pages' => []];
    $foundParts = 0;
    foreach (['a', 'b', 'c'] as $part) {
        $f = $langDir . 'pages_' . $lang . '_' . $part . '.php';
        if (!is_file($f)) {
            fwrite(STDERR, "[SKIP] {$lang}: missing {$f}\n");
            continue;
        }
        $data = require $f;
        if (!is_array($data) || !isset($data['pages']) || !is_array($data['pages'])) {
            fwrite(STDERR, "[WARN] {$lang} part {$part}: invalid structure\n");
            continue;
        }
        $merged['pages'] = array_merge($merged['pages'], $data['pages']);
        $foundParts++;
    }
    if ($foundParts === 0) {
        fwrite(STDERR, "[FAIL] {$lang}: no parts found, skipping\n");
        continue;
    }

    $out = "<?php\n// MotoGo24 — pages_{$lang}.php (slozeno z {$foundParts} dilcich casti)\n\n";
    $out .= "return " . _exportArray($merged, 0) . ";\n";

    $target = $langDir . 'pages_' . $lang . '.php';
    file_put_contents($target, $out);
    echo "OK: pages_{$lang}.php ({$foundParts}/3 casti, " . count($merged['pages']) . " stranek)\n";
}

function _exportArray($v, $indent = 0) {
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
            $line .= _exportArray($vv, $indent + 1);
            $lines[] = $line;
        }
        return "[\n" . implode(",\n", $lines) . ",\n" . $pad . ']';
    }
    return var_export($v, true);
}
