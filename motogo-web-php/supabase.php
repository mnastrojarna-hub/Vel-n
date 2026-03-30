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
        $this->cacheDir = sys_get_temp_dir() . '/motogo_cache';
        if (!is_dir($this->cacheDir)) {
            @mkdir($this->cacheDir, 0755, true);
        }
    }

    /**
     * Čte z file cache. Vrací null pokud cache neexistuje nebo expiroval.
     */
    private function cacheGet($key) {
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
        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                'apikey: ' . $this->key,
                'Authorization: Bearer ' . $this->key,
                'Accept: application/json',
            ],
            CURLOPT_TIMEOUT => 15,
        ]);
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($httpCode >= 200 && $httpCode < 300 && $response) {
            return json_decode($response, true) ?: [];
        }
        return [];
    }

    /**
     * POST request s curl.
     */
    private function _post($url, $data = []) {
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
            CURLOPT_TIMEOUT => 15,
        ]);
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($httpCode >= 200 && $httpCode < 300 && $response) {
            return json_decode($response, true) ?: [];
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
        $result = $this->query('app_settings', 'value', ['key=eq.' . $key]);
        if (!$result || !isset($result[0]['value'])) return null;
        $v = $result[0]['value'];
        if (is_string($v)) {
            $decoded = json_decode($v, true);
            return $decoded !== null ? $decoded : $v;
        }
        return $v;
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
    public function fetchCmsPage($slug) {
        $cacheKey = 'cms_' . $slug;
        $cached = $this->cacheGet($cacheKey);
        if ($cached !== null) return $cached;
        $result = $this->query('cms_pages', '*', ['slug=eq.' . $slug]);
        $data = $result ? ($result[0] ?? null) : null;
        if ($data) $this->cacheSet($cacheKey, $data);
        return $data;
    }

    public function fetchCmsPages($tag = null) {
        $cacheKey = 'cms_pages' . ($tag ? '_' . $tag : '');
        $cached = $this->cacheGet($cacheKey);
        if ($cached !== null) return $cached;
        $filters = [];
        if ($tag) {
            $filters[] = 'tags=cs.{' . $tag . '}';
        }
        $data = $this->query('cms_pages', '*', $filters, 'created_at.desc');
        $this->cacheSet($cacheKey, $data);
        return $data;
    }

    // ===== PRODUKTY =====
    public function fetchProducts() {
        return $this->query('products', '*', ['is_active=eq.true'], 'sort_order.asc');
    }

    // ===== EXTRAS CATALOG =====
    public function fetchExtras() {
        return $this->query('extras_catalog', '*', [], 'name.asc');
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
 * Formátuje cenu v Kč.
 */
function formatPrice($n) {
    if ($n === null || $n === '') return '';
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
