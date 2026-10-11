<?php
/**
 * MotoGo24 — horní informační pruh webu (stejný banner jako v appce).
 *
 * Zdroj: app_settings.header_banner (edituje Velín → Dashboard → „Banner“):
 *   { enabled: bool, text: string (CZ), bg: "#rrggbb", color: "#rrggbb",
 *     translations?: { en: string, de: …, uk: … },   // auto-překlad z Velínu
 *     translations_src?: "fnv1a32:xxxxxxxx" }         // otisk CZ textu, ze kterého
 *                                                     // překlady vznikly
 * Překlad se použije jen když je ČERSTVÝ (translations_src == otisk aktuálního
 * `text`) — po změně CZ textu, dokud Velín nedopřeloží, se ukáže čeština.
 * Otisk = FNV-1a 32 bit nad UTF-8 bajty `text` přesně jak je uložen, zápis
 * "fnv1a32:" + 8 hex číslic malými písmeny. Stejně ho počítá Velín
 * (src/pages/bannerI18n.js) i appka (lib/core/banner_provider.dart).
 *
 * Data přes SupabaseClient->fetchSetting() (file-cache 30 min, Velín po uložení
 * volá purgeWebCache). Styly jsou inline atributy → validní HTML, žádný
 * request navíc, žádný layout shift (pruh je v HTML od prvního vykreslení).
 * Prvek je statický (bez position/z-index) → nepřekrývá sticky hlavičku ani
 * mobilní menu, při scrollu prostě odjede nahoru.
 */

const MG_TOPBANNER_DEFAULT_BG = '#1a2e22';
const MG_TOPBANNER_DEFAULT_FG = '#74fb71';

/** Otisk CZ textu banneru (FNV-1a 32 bit nad UTF-8 bajty). */
function mgBannerFingerprint($text) {
    $s = (string)$text;
    $h = 0x811c9dc5;
    $n = strlen($s);
    for ($i = 0; $i < $n; $i++) {
        $h ^= ord($s[$i]);
        $h = ($h * 0x01000193) & 0xFFFFFFFF;
    }
    return 'fnv1a32:' . sprintf('%08x', $h);
}

/**
 * Text banneru v jazyce $lang: čerstvý překlad, jinak český originál.
 * $isCs = true, když se vrací čeština (pro lang="cs" u cizojazyčné stránky).
 */
function mgBannerLocalizedText(array $b, $lang, &$isCs = null) {
    $isCs = true;
    $cs = trim((string)($b['text'] ?? ''));
    if ($lang === 'cs' || $cs === '') return $cs;
    $tr = $b['translations'] ?? null;
    if (!is_array($tr) || !isset($tr[$lang]) || !is_string($tr[$lang])) return $cs;
    if (($b['translations_src'] ?? '') !== mgBannerFingerprint((string)($b['text'] ?? ''))) return $cs;
    $t = trim($tr[$lang]);
    if ($t === '') return $cs;
    $isCs = false;
    return $t;
}

/** '#abc' / '#aabbcc' → '#aabbcc' (lowercase), jinak null. */
function mgBannerHex($v) {
    if (!is_string($v)) return null;
    $v = strtolower(trim($v));
    if (preg_match('/^#([0-9a-f])([0-9a-f])([0-9a-f])$/', $v, $m)) {
        return '#' . $m[1] . $m[1] . $m[2] . $m[2] . $m[3] . $m[3];
    }
    return preg_match('/^#[0-9a-f]{6}$/', $v) ? $v : null;
}

/** Relativní jas dle WCAG 2.x. */
function mgBannerLuminance($hex) {
    $c = [];
    foreach ([1, 3, 5] as $i) {
        $x = hexdec(substr($hex, $i, 2)) / 255;
        $c[] = $x <= 0.03928 ? $x / 12.92 : pow(($x + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * $c[0] + 0.7152 * $c[1] + 0.0722 * $c[2];
}

function mgBannerContrast($a, $b) {
    $la = mgBannerLuminance($a);
    $lb = mgBannerLuminance($b);
    return (max($la, $lb) + 0.05) / (min($la, $lb) + 0.05);
}

/**
 * Barvy z Velínu s garancí čitelnosti: pokud kontrast textu vůči pozadí
 * klesne pod 4.5:1 (WCAG AA), použije se bílá nebo tmavě zelená — ta, která
 * má vůči pozadí vyšší kontrast.
 * @return array [bg, fg]
 */
function mgBannerColors(array $b) {
    $bg = mgBannerHex($b['bg'] ?? null) ?: MG_TOPBANNER_DEFAULT_BG;
    $fg = mgBannerHex($b['color'] ?? null) ?: MG_TOPBANNER_DEFAULT_FG;
    if (mgBannerContrast($bg, $fg) < 4.5) {
        $fg = mgBannerContrast($bg, '#ffffff') >= mgBannerContrast($bg, '#0f1a14') ? '#ffffff' : '#0f1a14';
    }
    return [$bg, $fg];
}

/** Načte app_settings.header_banner (cache 30 min). Chyba → null (bez pruhu). */
function mgBannerFetch() {
    if (!class_exists('SupabaseClient')) return null;
    try {
        $v = (new SupabaseClient())->fetchSetting('header_banner');
    } catch (\Throwable $e) {
        return null;
    }
    return is_array($v) ? $v : null;
}

/**
 * HTML pruhu nad hlavičkou. $banner = null → načte z DB (předání pole slouží
 * jen testům). Vypnutý banner nebo prázdný text → ''.
 */
function renderTopBanner($banner = null) {
    $b = $banner === null ? mgBannerFetch() : $banner;
    if (!is_array($b) || empty($b['enabled']) || $b['enabled'] === 'false') return '';
    $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
    $text = mgBannerLocalizedText($b, $lang, $isCs);
    if ($text === '') return '';
    $isCsFallback = ($lang !== 'cs' && $isCs);
    [$bg, $fg] = mgBannerColors($b);
    $labels = [
        'cs' => 'Oznámení', 'en' => 'Announcement', 'de' => 'Hinweis', 'es' => 'Aviso',
        'fr' => 'Annonce', 'nl' => 'Mededeling', 'pl' => 'Ogłoszenie', 'uk' => 'Оголошення',
    ];
    $label = $labels[$lang] ?? $labels['cs'];
    $esc = function ($s) { return htmlspecialchars((string)$s, ENT_QUOTES | ENT_HTML5, 'UTF-8'); };

    return '<div class="mg-topbanner" role="region" aria-label="' . $esc($label) . '" style="'
        . 'background:' . $bg . ';color:' . $fg . ';'
        . 'font-family:Montserrat,\'Segoe UI\',sans-serif;font-weight:700;'
        . 'font-size:clamp(.75rem,.68rem + .4vw,.875rem);line-height:1.35;letter-spacing:.01em;'
        . 'text-align:center;padding:.42rem max(1rem,env(safe-area-inset-right)) .42rem max(1rem,env(safe-area-inset-left));'
        . 'border-bottom:1px solid rgba(128,128,128,.28)">'
        . '<p style="margin:0 auto;max-width:1200px;overflow-wrap:anywhere"'
        . ($isCsFallback ? ' lang="cs"' : '') . '>' . $esc($text) . '</p>'
        . '</div>';
}
