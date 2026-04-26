// ===== MotoGo24 Web — API vrstva =====
// Veřejné (anon) API pro web — bez autentizace, jen čtení.

var MG = window.MG || {};
window.MG = MG;

// ===== MOTORKY =====
MG.fetchMotos = async function(){
  if(!window.sb){ console.warn('[API] sb not ready'); return []; }
  try {
    var r = await window.sb.from('motorcycles')
      .select('*, branches(name, address, city, is_open)')
      .eq('status','active')
      .order('model');
    if(r.error){ console.error('[API] fetchMotos error:', r.error); return []; }
    console.log('[API] fetchMotos:', (r.data||[]).length, 'motorek');
    return r.data || [];
  } catch(e){ console.error('[API] fetchMotos exception:', e); return []; }
};

// ===== DENNÍ CENY =====
MG.fetchMotoPrices = async function(motoId){
  if(!window.sb) return null;
  try {
    var r = await window.sb.from('motorcycles')
      .select('price_mon,price_tue,price_wed,price_thu,price_fri,price_sat,price_sun,price_weekday,price_weekend')
      .eq('id', motoId).single();
    return r.data || null;
  } catch(e){ return null; }
};

// ===== DOSTUPNOST (bookings via RPC — bypasses RLS safely) =====
MG.fetchMotoBookings = async function(motoId){
  if(!window.sb) return [];
  try {
    var r = await window.sb.rpc('get_moto_booked_dates', { p_moto_id: motoId });
    if(r.error){
      console.warn('[API] get_moto_booked_dates error:', r.error.message);
      return [];
    }
    return r.data || [];
  } catch(e){ console.error('[API] fetchMotoBookings exception:', e); return []; }
};

// ===== APP SETTINGS =====
MG.fetchSetting = async function(key){
  if(!window.sb) return null;
  try {
    var r = await window.sb.from('app_settings')
      .select('value').eq('key', key).maybeSingle();
    if(!r.data) return null;
    var v = r.data.value;
    return typeof v === 'string' ? JSON.parse(v) : v;
  } catch(e){ return null; }
};

// ===== POBOČKY =====
MG.fetchBranches = async function(){
  if(!window.sb) return [];
  try {
    var r = await window.sb.from('branches').select('*').order('name');
    return r.data || [];
  } catch(e){ return []; }
};

// ===== CMS PAGES =====
MG.fetchCmsPage = async function(slug){
  if(!window.sb) return null;
  try {
    var r = await window.sb.from('cms_pages')
      .select('*').eq('slug', slug).eq('published', true).maybeSingle();
    if(r.error){ console.warn('[API] fetchCmsPage error:', r.error); return null; }
    return r.data || null;
  } catch(e){ return null; }
};

MG.fetchCmsPages = async function(tag){
  if(!window.sb) return [];
  try {
    var q = window.sb.from('cms_pages').select('*').eq('published', true).order('created_at',{ascending:false});
    if(tag) q = q.contains('tags', [tag]);
    var r = await q;
    if(r.error){ console.warn('[API] fetchCmsPages error:', r.error); return []; }
    return r.data || [];
  } catch(e){ return []; }
};

// ===== PRODUKTY (vouchers/shop) =====
MG.fetchProducts = async function(){
  if(!window.sb) return [];
  try {
    var r = await window.sb.from('products')
      .select('*').eq('is_active', true).order('sort_order');
    return r.data || [];
  } catch(e){ return []; }
};

// ===== EXTRAS CATALOG =====
MG.fetchExtras = async function(){
  if(!window.sb) return [];
  try {
    var r = await window.sb.from('extras_catalog').select('*').order('name');
    return r.data || [];
  } catch(e){ return []; }
};

// ===== PRICE CALCULATION =====
MG.calcPrice = function(moto, startDate, endDate){
  if(!moto || !startDate || !endDate) return 0;
  var s = new Date(startDate);
  var e = new Date(endDate);
  var total = 0;
  var days = ['sun','mon','tue','wed','thu','fri','sat'];
  var d = new Date(s);
  while(d <= e){
    var dayName = days[d.getDay()];
    var key = 'price_' + dayName;
    var price = moto[key] || moto.price_weekday || 0;
    total += Number(price);
    d.setDate(d.getDate() + 1);
  }
  return total;
};

// ===== DATE HELPERS =====
MG.formatDate = function(iso){
  if(!iso) return '';
  var d = new Date(iso);
  return d.getDate() + '.' + (d.getMonth()+1) + '.' + d.getFullYear();
};

// CURRENCY layer — vstup je VŽDY v CZK (z DB), výstup ve zvolené měně.
// Konfiguraci nastavuje PHP přes window.MOTOGO_CONFIG.CURRENCY:
//   { current: 'EUR', rates: {EUR: 24.31, PLN: 5.65}, meta: {...} }
MG._curMeta = {
  CZK: { symbol: 'Kč', decimals: 0, locale: 'cs-CZ' },
  EUR: { symbol: '€', decimals: 2, locale: 'cs-CZ' },
  PLN: { symbol: 'zł', decimals: 2, locale: 'cs-CZ' }
};

MG.currentCurrency = function(){
  try { return (window.MOTOGO_CONFIG && window.MOTOGO_CONFIG.CURRENCY && window.MOTOGO_CONFIG.CURRENCY.current) || 'CZK'; }
  catch(e){ return 'CZK'; }
};

MG.fxRate = function(code){
  try {
    var c = (code||'').toUpperCase();
    if (c === 'CZK') return 1;
    var rates = window.MOTOGO_CONFIG && window.MOTOGO_CONFIG.CURRENCY && window.MOTOGO_CONFIG.CURRENCY.rates;
    return (rates && rates[c]) ? Number(rates[c]) : 0;
  } catch(e){ return 0; }
};

// Konverze CZK → cílová měna. CZK→CZK = identita.
MG.convertFromCzk = function(czk, targetCurrency){
  if (czk === null || czk === undefined || czk === '') return null;
  var cur = (targetCurrency || MG.currentCurrency()).toUpperCase();
  if (cur === 'CZK') return Number(czk);
  var rate = MG.fxRate(cur);
  if (!rate) return Number(czk);
  return Number(czk) / rate;
};

// Formátuje CZK částku ve zvolené měně. Vstup VŽDY v CZK.
MG.formatPrice = function(czk, opts){
  if (!czk && czk !== 0) return '';
  opts = opts || {};
  var cur = (opts.currency || MG.currentCurrency()).toUpperCase();
  var meta = MG._curMeta[cur] || MG._curMeta.CZK;
  var value = MG.convertFromCzk(czk, cur);
  if (value === null) return '';
  var formatted = Number(value).toLocaleString(meta.locale, {
    minimumFractionDigits: meta.decimals,
    maximumFractionDigits: meta.decimals
  });
  if (opts.withSymbol === false) return formatted;
  return formatted + ' ' + meta.symbol;
};

// Vždy vrátí formátovanou částku v CZK (pro Stripe info, faktury apod.)
MG.formatPriceCzk = function(czk){
  if (!czk && czk !== 0) return '';
  return Number(czk).toLocaleString('cs-CZ') + ' Kč';
};

// ===== MIN PRICE HELPER =====
MG.getMinPrice = function(m){
  var prices = [m.price_mon,m.price_tue,m.price_wed,m.price_thu,m.price_fri,m.price_sat,m.price_sun,m.price_weekday].filter(function(p){ return p && p > 0; });
  return prices.length ? Math.min.apply(null, prices) : 0;
};
