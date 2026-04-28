<?php
// ===== MotoGo24 Web PHP — Supabase REST API klient =====

require_once __DIR__ . '/config.php';

class SupabaseClient {
    private $url;
    private $key;
    private $cacheDir;
    private $cacheTtl = 300; // 5 minut

    public function __construct() {
        $this->url = SUPABASE_URL;
        $this->key = SUPABASE_ANON_KEY;
        // Preferuj project-local cache (funguje i bez /tmp write perms),
        // fallback na system temp.
        $candidates = [__DIR__ . '/.cache', sys_get_temp_dir() . '/motogo_cache'];
        $this->cacheDir = null;
        foreach ($candidates as $dir) {
            if (is_dir($dir) && is_writable($dir)) { $this->cacheDir = $dir; break; }
            if (!is_dir($dir) && @mkdir($dir, 0755, true) && is_writable($dir)) { $this->cacheDir = $dir; break; }
        }
        // pokud oba selžou, cache se vypne (is_null check v cacheGet/Set)
    }

    /**
     * Čte z file cache. Vrací null pokud cache neexistuje nebo expiroval.
     */
    private function cacheGet($key) {
        if (!$this->cacheDir) return null;
        $file = $this->cacheDir . '/' . md5($key) . '.json';
        if (!file_exists($file)) return null;
        if (filemtime($file) < time() - $this->cacheTtl) {
            @unlink($file);
            return null;
        }
        $data = @file_get_contents($file);
        return $data !== false ? json_decode($data, true) : null;
    }

    /**
     * Zapíše do file cache.
     */
    private function cacheSet($key, $data) {
        if (!$this->cacheDir) return;
        $file = $this->cacheDir . '/' . md5($key) . '.json';
        @file_put_contents($file, json_encode($data), LOCK_EX);
    }

    /**
     * Obecný GET dotaz na Supabase REST API.
     * @param string $table Název tabulky
     * @param string $select SELECT klauzule (default '*')
     * @param array $filters Pole filtrů ['column=eq.value', ...]
     * @param string|null $order ORDER klauzule (např. 'model.asc')
     * @return array Vrací pole výsledků
     */
    public function query($table, $select = '*', $filters = [], $order = null) {
        $params = ['select' => $select];
        if ($order) {
            $params['order'] = $order;
        }

        $queryString = http_build_query($params);
        // Filtry přidáme ručně (Supabase REST API formát)
        foreach ($filters as $filter) {
            $queryString .= '&' . $filter;
        }

        $url = $this->url . '/rest/v1/' . $table . '?' . $queryString;
        return $this->_get($url);
    }

    /**
     * Volání RPC funkce.
     * @param string $function Název funkce
     * @param array $params Parametry funkce
     * @return mixed Výsledek
     */
    public function rpc($function, $params = []) {
        $url = $this->url . '/rest/v1/rpc/' . $function;
        return $this->_post($url, $params);
    }

    /**
     * GET request s curl.
     */
    private function _get($url) {
        if (!function_exists('curl_init')) {
            @error_log('[MotoGo24] curl extension nedostupné');
            return [];
        }
        try {
            $ch = curl_init();
            curl_setopt_array($ch, [
                CURLOPT_URL => $url,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_HTTPHEADER => [
                    'apikey: ' . $this->key,
                    'Authorization: Bearer ' . $this->key,
                    'Accept: application/json',
                ],
                CURLOPT_TIMEOUT => 8,
                CURLOPT_CONNECTTIMEOUT => 3,
            ]);
            $response = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            if ($httpCode >= 200 && $httpCode < 300 && $response) {
                $decoded = json_decode($response, true);
                return is_array($decoded) ? $decoded : [];
            }
        } catch (\Throwable $e) {
            @error_log('[MotoGo24] GET failed: ' . $e->getMessage());
        }
        return [];
    }

    /**
     * POST request s curl.
     */
    private function _post($url, $data = []) {
        if (!function_exists('curl_init')) {
            @error_log('[MotoGo24] curl extension nedostupné');
            return [];
        }
        try {
            $ch = curl_init();
            curl_setopt_array($ch, [
                CURLOPT_URL => $url,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_POST => true,
                CURLOPT_POSTFIELDS => json_encode($data),
                CURLOPT_HTTPHEADER => [
                    'apikey: ' . $this->key,
                    'Authorization: Bearer ' . $this->key,
                    'Content-Type: application/json',
                    'Accept: application/json',
                ],
                CURLOPT_TIMEOUT => 8,
                CURLOPT_CONNECTTIMEOUT => 3,
            ]);
            $response = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            if ($httpCode >= 200 && $httpCode < 300 && $response) {
                $decoded = json_decode($response, true);
                return is_array($decoded) ? $decoded : [];
            }
        } catch (\Throwable $e) {
            @error_log('[MotoGo24] POST failed: ' . $e->getMessage());
        }
        return [];
    }

    // ===== MOTORKY =====
    public function fetchMotos() {
        $cached = $this->cacheGet('motos');
        if ($cached !== null) return $cached;
        $data = $this->query(
            'motorcycles',
            '*,branches(name,address,city,is_open)',
            ['status=eq.active'],
            'model.asc'
        );

        // Sjednotit s nejbližším volným datem (RPC bypassuje RLS na bookings).
        // Pokud RPC chybí nebo selže, motorky se zobrazí bez data → fallback "Dostupné dnes".
        if (!empty($data)) {
            $avail = $this->rpc('get_motos_availability_status', []);
            if (is_array($avail) && !empty($avail)) {
                $byId = [];
                foreach ($avail as $row) {
                    if (!empty($row['moto_id'])) {
                        $byId[$row['moto_id']] = $row['next_available_date'] ?? null;
                    }
                }
                foreach ($data as &$m) {
                    $mid = $m['id'] ?? null;
                    if ($mid && array_key_exists($mid, $byId)) {
                        $m['next_available_date'] = $byId[$mid];
                    }
                }
                unset($m);
            }
        }

        $this->cacheSet('motos', $data);
        return $data;
    }

    // ===== DENNÍ CENY =====
    public function fetchMotoPrices($motoId) {
        $result = $this->query(
            'motorcycles',
            'price_mon,price_tue,price_wed,price_thu,price_fri,price_sat,price_sun,price_weekday,price_weekend',
            ['id=eq.' . $motoId]
        );
        return $result ? ($result[0] ?? null) : null;
    }

    // ===== DOSTUPNOST (RPC — bypasses RLS safely) =====
    public function fetchMotoBookings($motoId) {
        return $this->rpc('get_moto_booked_dates', ['p_moto_id' => $motoId]);
    }

    // ===== APP SETTINGS =====
    public function fetchSetting($key) {
        $cacheKey = 'setting_' . $key;
        $cached = $this->cacheGet($cacheKey);
        if ($cached !== null) return $cached['v'] ?? null;

        $result = $this->query('app_settings', 'value', ['key=eq.' . $key]);
        if (!$result || !isset($result[0]['value'])) {
            $this->cacheSet($cacheKey, ['v' => null]);
            return null;
        }
        $v = $result[0]['value'];
        if (is_string($v)) {
            $decoded = json_decode($v, true);
            $v = ($decoded !== null) ? $decoded : $v;
        }
        $this->cacheSet($cacheKey, ['v' => $v]);
        return $v;
    }

    /**
     * Načte CMS konfiguraci stránky (site.<page>) s fallback na defaults.
     * Defaults se rekurzivně mergují s jazykovým overlay a DB hodnotami.
     *
     * Pořadí merge (pozdější přepisuje dřívější):
     *   1) $defaults (CS — z PHP / data/*.php)
     *   2) jazykový overlay z dictionary: t('pages.<page>') (z lang/pages_<lang>.php)
     *   3) DB 'site.<page>' (CS overlay z app_settings)
     *   4) DB 'site.<page>.<lang>' (per-language overlay z app_settings)
     *
     * @param string $page Slug stránky (např. 'home', 'pujcovna', 'jak_pujcit_cena')
     * @param array $defaults Výchozí obsah v CS
     * @return array Finální obsah pro stránku v aktuálním jazyce
     */
    public function siteContent($page, $defaults = []) {
        $merged = $defaults;
        $lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';

        // 1) Jazykový overlay z dictionary souboru (lang/pages_<lang>.php) — pro non-CS jazyky
        if ($lang && $lang !== 'cs' && function_exists('t')) {
            $langOverlay = t('pages.' . $page);
            if (is_array($langOverlay)) {
                $merged = self::deepMerge($merged, $langOverlay);
            }
        }

        // 2) Základní (CS) DB override
        $db = $this->fetchSetting('site.' . $page);
        if (is_array($db) && !empty($db)) {
            $merged = self::deepMerge($merged, $db);
        }

        // 3) Per-language DB override (např. site.home.en)
        if ($lang && $lang !== 'cs') {
            $dbLang = $this->fetchSetting('site.' . $page . '.' . $lang);
            if (is_array($dbLang) && !empty($dbLang)) {
                $merged = self::deepMerge($merged, $dbLang);
            }
        }

        return $merged;
    }

    /**
     * Rekurzivní merge 2 polí — klíč z $b přepíše klíč z $a.
     * Asociativní pole se mergují, číselná (seznamy) se přepisují celé.
     */
    private static function deepMerge($a, $b) {
        if (!is_array($a)) return $b;
        if (!is_array($b)) return $b;
        if (self::isList($b)) return $b;
        $out = $a;
        foreach ($b as $k => $v) {
            $out[$k] = (isset($a[$k]) && is_array($a[$k]) && is_array($v))
                ? self::deepMerge($a[$k], $v)
                : $v;
        }
        return $out;
    }

    /** Bezpečný list-check (nepoužívá range(), které má edge-case na prázdném poli). */
    private static function isList($arr) {
        if (!is_array($arr)) return false;
        if (function_exists('array_is_list')) return array_is_list($arr);
        if (empty($arr)) return true;
        $i = 0;
        foreach ($arr as $k => $_) {
            if ($k !== $i++) return false;
        }
        return true;
    }

    // ===== POBOČKY =====
    public function fetchBranches() {
        $cached = $this->cacheGet('branches');
        if ($cached !== null) return $cached;
        $data = $this->query('branches', '*', [], 'name.asc');
        $this->cacheSet('branches', $data);
        return $data;
    }

    // ===== CMS PAGES =====
    // Bez cache — blog/CMS musí reagovat okamžitě po uložení/smazání ve Velínu.
    public function fetchCmsPage($slug) {
        $result = $this->query('cms_pages', '*', ['slug=eq.' . $slug, 'published=eq.true']);
        return $result ? ($result[0] ?? null) : null;
    }

    public function fetchCmsPages($tag = null) {
        $filters = ['published=eq.true'];
        if ($tag) {
            $filters[] = 'tags=cs.{' . $tag . '}';
        }
        return $this->query('cms_pages', '*', $filters, 'created_at.desc');
    }

    // ===== PRODUKTY =====
    public function fetchProducts() {
        $cached = $this->cacheGet('products_active');
        if ($cached !== null) return $cached;
        $data = $this->query('products', '*', ['is_active=eq.true'], 'sort_order.asc');
        $this->cacheSet('products_active', $data);
        return $data;
    }

    public function fetchProduct($id) {
        if (!$id) return null;
        $cacheKey = 'product_' . $id;
        $cached = $this->cacheGet($cacheKey);
        if ($cached !== null) return $cached;
        $result = $this->query('products', '*', ['id=eq.' . $id]);
        $data = $result ? ($result[0] ?? null) : null;
        if ($data) $this->cacheSet($cacheKey, $data);
        return $data;
    }

    // ===== EXTRAS CATALOG =====
    public function fetchExtras() {
        return $this->query('extras_catalog', '*', [], 'name.asc');
    }

    // ===== REVIEWS (veřejné recenze na web) =====
    public function fetchPublicReviews($limit = 6) {
        $cached = $this->cacheGet('reviews_public_' . $limit);
        if ($cached !== null) return $cached;
        // Bez závislosti na konkrétní struktuře: vezmeme všechny, order by created_at desc
        $data = $this->query(
            'reviews',
            'id,rating,comment,author_name,created_at',
            [],
            'created_at.desc'
        );
        if (!is_array($data)) $data = [];
        // Pouze s textem
        $data = array_values(array_filter($data, function ($r) {
            return !empty($r['comment']) && strlen(trim($r['comment'])) > 10;
        }));
        if ($limit > 0) $data = array_slice($data, 0, $limit);
        $this->cacheSet('reviews_public_' . $limit, $data);
        return $data;
    }
}

// ===== HELPER FUNKCE =====

/**
 * Vypočítá cenu pronájmu dle denních cen (inkluzivní start+end).
 */
function calcPrice($moto, $startDate, $endDate) {
    if (!$moto || !$startDate || !$endDate) return 0;
    $days = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
    $total = 0;
    $d = new DateTime($startDate);
    $end = new DateTime($endDate);
    while ($d <= $end) {
        $dayName = $days[(int)$d->format('w')];
        $key = 'price_' . $dayName;
        $price = $moto[$key] ?? $moto['price_weekday'] ?? 0;
        $total += (float)$price;
        $d->modify('+1 day');
    }
    return $total;
}

/**
 * Formátuje datum do D.M.YYYY.
 */
function formatDate($iso) {
    if (!$iso) return '';
    $d = new DateTime($iso);
    return (int)$d->format('j') . '.' . (int)$d->format('n') . '.' . $d->format('Y');
}

/**
 * Formátuje cenu (vstup vždy v CZK z DB) ve zvolené měně zákazníka.
 * Deleguje na money() z i18n_currency.php — stejný výstup jako historický
 * "1 500 Kč" pro CZK, jinak konvertuje přes aktuální ČNB kurz.
 */
function formatPrice($n) {
    if ($n === null || $n === '') return '';
    if (function_exists('money')) return money($n);
    return number_format((float)$n, 0, ',', ' ') . ' Kč';
}

/**
 * Vrací minimální denní cenu motorky.
 */
function getMinPrice($m) {
    $prices = array_filter([
        $m['price_mon'] ?? 0,
        $m['price_tue'] ?? 0,
        $m['price_wed'] ?? 0,
        $m['price_thu'] ?? 0,
        $m['price_fri'] ?? 0,
        $m['price_sat'] ?? 0,
        $m['price_sun'] ?? 0,
        $m['price_weekday'] ?? 0,
    ], function($p) { return $p && $p > 0; });
    return $prices ? min($prices) : 0;
}
