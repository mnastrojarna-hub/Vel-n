// ===== MotoGo24 Web — API vrstva =====
// Veřejné (anon) API pro web — bez autentizace, jen čtení.

var MG = window.MG || {};
window.MG = MG;

// ===== MOTORKY =====
MG.fetchMotos = async function(){
  if(!window.sb) return [];
  try {
    var r = await window.sb.from('motorcycles')
      .select('*, branches(name, address, city, is_open)')
      .eq('status','active')
      .order('model');
    return r.data || [];
  } catch(e){ console.error('[API] fetchMotos:', e); return []; }
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

// ===== DOSTUPNOST (bookings overlap check) =====
MG.fetchMotoBookings = async function(motoId){
  if(!window.sb) return [];
  try {
    var today = new Date().toISOString().split('T')[0];
    var r = await window.sb.from('bookings')
      .select('start_date,end_date,status')
      .eq('moto_id', motoId)
      .in('status', ['pending','reserved','active'])
      .gte('end_date', today)
      .order('start_date');
    return r.data || [];
  } catch(e){ return []; }
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
    var r = await window.sb.from('branches')
      .select('*').order('name');
    return r.data || [];
  } catch(e){ return []; }
};

// ===== CMS PAGES =====
MG.fetchCmsPage = async function(slug){
  if(!window.sb) return null;
  try {
    var r = await window.sb.from('cms_pages')
      .select('*').eq('slug', slug).maybeSingle();
    return r.data || null;
  } catch(e){ return null; }
};

MG.fetchCmsPages = async function(tag){
  if(!window.sb) return [];
  try {
    var q = window.sb.from('cms_pages').select('*').order('created_at',{ascending:false});
    if(tag) q = q.contains('tags', [tag]);
    var r = await q;
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

// ===== RECENZE =====
MG.fetchReviews = async function(){
  if(!window.sb) return [];
  try {
    var r = await window.sb.from('reviews')
      .select('*').order('created_at',{ascending:false}).limit(10);
    return r.data || [];
  } catch(e){ return []; }
};

// ===== EXTRAS CATALOG =====
MG.fetchExtras = async function(){
  if(!window.sb) return [];
  try {
    var r = await window.sb.from('extras_catalog')
      .select('*').order('name');
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
