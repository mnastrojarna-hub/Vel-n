<?php
// ===== MotoGo24 Web PHP — Supabase REST API helper =====

class SupabaseClient {
    private $url;
    private $key;

    public function __construct() {
        $this->url = SUPABASE_URL;
        $this->key = SUPABASE_ANON_KEY;
    }

    // Generic REST API query
    public function query($table, $select = '*', $filters = [], $order = null, $single = false) {
        $url = $this->url . '/rest/v1/' . $table . '?select=' . urlencode($select);
        foreach ($filters as $col => $val) {
            $url .= '&' . $col . '=' . urlencode($val);
        }
        if ($order) {
            $url .= '&order=' . urlencode($order);
        }
        if ($single) {
            $url .= '&limit=1';
        }
        $headers = [
            'apikey: ' . $this->key,
            'Authorization: Bearer ' . $this->key,
            'Content-Type: application/json',
        ];
        if ($single) {
            $headers[] = 'Accept: application/vnd.pgrst.object+json';
        }
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($httpCode >= 400) return $single ? null : [];
        $data = json_decode($response, true);
        return $data ?: ($single ? null : []);
    }

    // RPC call
    public function rpc($function, $params = []) {
        $url = $this->url . '/rest/v1/rpc/' . $function;
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($params));
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'apikey: ' . $this->key,
            'Authorization: Bearer ' . $this->key,
            'Content-Type: application/json',
        ]);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        $response = curl_exec($ch);
        curl_close($ch);
        return json_decode($response, true);
    }

    // ===== API Methods (matching api.js) =====

    public function fetchMotos() {
        return $this->query('motorcycles', '*, branches(name, address, city, is_open)',
            ['status' => 'eq.active'], 'model');
    }

    public function fetchMotoPrices($motoId) {
        return $this->query('motorcycles',
            'price_mon,price_tue,price_wed,price_thu,price_fri,price_sat,price_sun,price_weekday,price_weekend',
            ['id' => 'eq.' . $motoId], null, true);
    }

    public function fetchMotoBookings($motoId) {
        return $this->rpc('get_moto_booked_dates', ['p_moto_id' => $motoId]);
    }

    public function fetchSetting($key) {
        $row = $this->query('app_settings', 'value', ['key' => 'eq.' . $key], null, true);
        if (!$row || !isset($row['value'])) return null;
        $v = $row['value'];
        return is_string($v) ? json_decode($v, true) : $v;
    }

    public function fetchBranches() {
        return $this->query('branches', '*', [], 'name');
    }

    public function fetchCmsPage($slug) {
        return $this->query('cms_pages', '*', ['slug' => 'eq.' . $slug], null, true);
    }

    public function fetchCmsPages($tag = null) {
        $filters = [];
        if ($tag) {
            $filters['tags'] = 'cs.{"' . $tag . '"}';
        }
        return $this->query('cms_pages', '*', $filters, 'created_at.desc');
    }

    public function fetchProducts() {
        return $this->query('products', '*', ['is_active' => 'eq.true'], 'sort_order');
    }

    public function fetchExtras() {
        return $this->query('extras_catalog', '*', [], 'name');
    }
}

// ===== Helper Functions =====

function imgUrl($src) {
    if (!$src) return '';
    if (strpos($src, 'http://') === 0 || strpos($src, 'https://') === 0 || strpos($src, 'data:') === 0) return $src;
    return SUPABASE_URL . '/storage/v1/object/public/media/' . $src;
}

function formatDate($iso) {
    if (!$iso) return '';
    $d = new DateTime($iso);
    return $d->format('j.n.Y');
}

function formatPrice($n) {
    if ($n === null || $n === '') return '';
    return number_format((float)$n, 0, ',', ' ') . ' Kč';
}

function getMinPrice($m) {
    $prices = array_filter([
        $m['price_mon'] ?? 0, $m['price_tue'] ?? 0, $m['price_wed'] ?? 0,
        $m['price_thu'] ?? 0, $m['price_fri'] ?? 0, $m['price_sat'] ?? 0,
        $m['price_sun'] ?? 0, $m['price_weekday'] ?? 0
    ], function($p) { return $p > 0; });
    return $prices ? min($prices) : 0;
}

function calcPrice($moto, $startDate, $endDate) {
    if (!$moto || !$startDate || !$endDate) return 0;
    $days = ['sun','mon','tue','wed','thu','fri','sat'];
    $total = 0;
    $d = new DateTime($startDate);
    $e = new DateTime($endDate);
    while ($d <= $e) {
        $dayName = $days[(int)$d->format('w')];
        $key = 'price_' . $dayName;
        $price = $moto[$key] ?? $moto['price_weekday'] ?? 0;
        $total += (int)$price;
        $d->modify('+1 day');
    }
    return $total;
}

function e($str) {
    return htmlspecialchars($str ?? '', ENT_QUOTES, 'UTF-8');
}
