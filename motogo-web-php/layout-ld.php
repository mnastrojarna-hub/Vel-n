<?php
// ===== MotoGo24 Web PHP — fakta pro JSON-LD v hlavičce (layout.php) z dat Velína =====
// Dřív natvrdo: cenové rozpětí 990–5000 Kč a 50 nabídek (živě jiné), vatID (firma NENÍ plátce DPH —
// app_settings.company_info.vat_payer), měny CZK/EUR/USD (platí se jen v CZK), „Telefon (24/7)“
// (podpora po telefonu Po–Pá 8–17), WhatsApp kanál i při vypnutém feature_flags.whatsapp_integration
// a chyběla samoobslužná pobočka. Vše z cache SupabaseClient (30 min); výpadek DB → bezpečné výchozí.

/** ['legalName','email','phone','taxID','vatID'?,'low','high','count','whatsapp','branches'=>[...]] */
function ldBusinessFacts() {
    static $f = null;
    if ($f !== null) return $f;
    $f = ['legalName' => 'Bc. Petra Semorádová', 'email' => 'info@motogo24.cz', 'phone' => '+420 774 256 271',
        'taxID' => '21874263', 'vatID' => '', 'low' => 0, 'high' => 0, 'count' => 0, 'whatsapp' => false, 'branches' => []];
    try {
        $sb = new SupabaseClient();
        $ci = $sb->fetchSetting('company_info');
        if (is_array($ci)) {
            foreach (['legalName' => 'name', 'email' => 'email', 'phone' => 'phone', 'taxID' => 'ico'] as $k => $src) {
                if (trim((string)($ci[$src] ?? '')) !== '') $f[$k] = trim((string)$ci[$src]);
            }
            if (!empty($ci['vat_payer']) && trim((string)($ci['dic'] ?? '')) !== '') $f['vatID'] = trim((string)$ci['dic']);
        }
        $motos = $sb->fetchMotos();
        if (is_array($motos)) {
            foreach ($motos as $m) {
                if (!is_array($m) || ($m['category'] ?? '') === 'ostatni') continue;   // vozík není motorka (jako lpFleet)
                $f['count']++;
                $lo = getMinPrice($m);
                if ($lo > 0 && ($f['low'] === 0 || $lo < $f['low'])) $f['low'] = $lo;
                foreach (['price_mon', 'price_tue', 'price_wed', 'price_thu', 'price_fri', 'price_sat', 'price_sun', 'price_weekday'] as $c) {
                    $p = (float)($m[$c] ?? 0);
                    if ($p > $f['high']) $f['high'] = $p;
                }
            }
        }
        $f['whatsapp'] = (bool)$sb->fetchFeatureFlag('whatsapp_integration');
        $br = $sb->fetchBranches();
        if (is_array($br)) $f['branches'] = array_values(array_filter($br, 'is_array'));
    } catch (\Throwable $e) { /* výchozí hodnoty */ }
    return $f;
}

/** Fragmenty JSON-LD: priceRange, AggregateOffer, ServiceChannel telefon/WhatsApp, department (další pobočky). */
function ldBusinessJson($siteOrigin) {
    $f = ldBusinessFacts();
    $j = function ($v) { return json_encode($v, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES); };
    $kc = function ($n) { return number_format(round($n), 0, ',', ' '); };
    $out = [
        'legalName' => $j($f['legalName']), 'email' => $j($f['email']), 'phone' => $j($f['phone']), 'taxID' => $j($f['taxID']),
        'vat' => $f['vatID'] !== '' ? ',"vatID":' . $j($f['vatID']) : '',
        'priceRange' => $f['low'] > 0 && $f['high'] > 0 ? ',"priceRange":' . $j($kc($f['low']) . ' – ' . $kc($f['high']) . ' ' . t('ld.priceUnit')) : '',
        'offers' => $f['low'] > 0 && $f['high'] > 0
            ? ',"offers":' . $j(['@type' => 'AggregateOffer', 'priceCurrency' => 'CZK', 'lowPrice' => (string)round($f['low']), 'highPrice' => (string)round($f['high']),
                'offerCount' => $f['count'], 'availability' => 'https://schema.org/InStock', 'seller' => ['@id' => $siteOrigin . '/#organization']])
            : '',
        'channels' => ',' . $j(['@type' => 'ServiceChannel', 'servicePhone' => $f['phone'], 'name' => t('ld.channelPhone')])
            . ($f['whatsapp'] ? ',' . $j(['@type' => 'ServiceChannel', 'serviceUrl' => 'https://wa.me/' . preg_replace('/\D+/', '', $f['phone']), 'name' => 'WhatsApp']) : ''),
        'department' => '',
    ];
    // Hlavní adresa = Mezná (address/geo v layout.php); další otevřené pobočky jako department
    $dep = [];
    foreach ($f['branches'] as $b) {
        if (($b['id'] ?? '') === '11111111-1111-1111-1111-111111111111' || empty($b['name'])) continue;
        $d = ['@type' => 'AutomotiveBusiness', 'name' => (string)$b['name'],
            'address' => array_filter(['@type' => 'PostalAddress', 'streetAddress' => (string)($b['address'] ?? ''), 'addressLocality' => (string)($b['city'] ?? ''),
                'postalCode' => (string)($b['zip'] ?? ''), 'addressCountry' => 'CZ'], 'strlen'),
            'telephone' => (string)($b['phone'] ?? $f['phone'])];
        if (is_numeric($b['gps_lat'] ?? null) && is_numeric($b['gps_lng'] ?? null)) {
            $d['geo'] = ['@type' => 'GeoCoordinates', 'latitude' => (float)$b['gps_lat'], 'longitude' => (float)$b['gps_lng']];
        }
        $dep[] = $d;
    }
    if ($dep) $out['department'] = ',"department":' . $j($dep);
    return $out;
}

/** Nejnižší / nejvyšší denní cena flotily (bez vozíku) a počet motorek — pro JSON-LD ostatních stránek. */
function ldPriceLow() { $f = ldBusinessFacts(); return $f['low'] > 0 ? (int)round($f['low']) : 990; }
function ldPriceHigh() { $f = ldBusinessFacts(); return $f['high'] > 0 ? (int)round($f['high']) : 5000; }
function ldOfferCount() { $f = ldBusinessFacts(); return max(1, (int)$f['count']); }

/** „Řidičský průkaz (skupina A, A1, A2 nebo B; dětské motorky bez ŘP)“ ze skupin ŘP flotily (license_groups /
 *  license_required, bez vozíku) — dřív natvrdo „A1/A2/A nebo B pro dětské“ (dětské jsou 'N' = bez ŘP). */
function ldLicenseSupply() {
    static $t = null;
    if ($t !== null) return $t;
    $g = []; $kids = false;
    try {
        foreach ((array)(new SupabaseClient())->fetchMotos() as $m) {
            if (!is_array($m) || ($m['category'] ?? '') === 'ostatni') continue;
            $list = is_array($m['license_groups'] ?? null) && $m['license_groups'] ? $m['license_groups'] : [($m['license_required'] ?? '')];
            foreach ($list as $x) { $x = strtoupper(trim((string)$x)); if ($x === 'N') $kids = true; elseif ($x !== '') $g[$x] = 1; }
        }
    } catch (\Throwable $e) { /* výchozí níže */ }
    $order = ['AM' => 0, 'A1' => 1, 'A2' => 2, 'A' => 3, 'B' => 4];
    $g = array_keys($g);
    usort($g, function ($a, $b) use ($order) { return ($order[$a] ?? 9) <=> ($order[$b] ?? 9); });
    if (!$g) return $t = t('ld.licenseAny');
    $last = array_pop($g);
    return $t = t('ld.license', ['groups' => ($g ? implode(', ', $g) . t('ld.licenseOr') : '') . $last . ($kids ? t('ld.licenseKids') : '')]);
}
