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
      .select('*').eq('slug', slug).maybeSingle();
    if(r.error){ console.warn('[API] fetchCmsPage error:', r.error); return null; }
    return r.data || null;
  } catch(e){ return null; }
};

MG.fetchCmsPages = async function(tag){
  if(!window.sb) return [];
  try {
    var q = window.sb.from('cms_pages').select('*').order('created_at',{ascending:false});
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

MG.formatPrice = function(n){
  if(!n && n !== 0) return '';
  return Number(n).toLocaleString('cs-CZ') + ' Kč';
};

// ===== MIN PRICE HELPER =====
MG.getMinPrice = function(m){
  var prices = [m.price_mon,m.price_tue,m.price_wed,m.price_thu,m.price_fri,m.price_sat,m.price_sun,m.price_weekday].filter(function(p){ return p && p > 0; });
  return prices.length ? Math.min.apply(null, prices) : 0;
};
