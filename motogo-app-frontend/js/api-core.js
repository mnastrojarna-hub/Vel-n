// ===== API.JS – Supabase API vrstva pro MotoGo24 =====
// Všechny api* funkce volané z UI. Vyžaduje supabaseClient.js (window.supabase).

// ===== REALTIME SINGLETON =====
var _bannerChannel = null;
function cleanupRealtimeChannels(){
  if(_bannerChannel && window.supabase){
    try { window.supabase.removeChannel(_bannerChannel); } catch(e){}
    _bannerChannel = null;
  }
}

// ===== HEADER BANNER =====
function _applyBannerConfig(cfg){
  if(!cfg || !cfg.enabled || !cfg.text) {
    // Banner disabled — skrýt pokud byl viditelný
    var elOff = document.getElementById('header-banner');
    if(elOff) elOff.style.display = 'none';
    document.documentElement.classList.remove('has-banner');
    return;
  }
  var el = document.getElementById('header-banner');
  var track = document.getElementById('header-banner-track');
  if(!el || !track) return;
  var txt = cfg.text;
  track.innerHTML = '<span>' + txt + '</span><span>' + txt + '</span><span>' + txt + '</span><span>' + txt + '</span>';
  el.style.display = 'flex';
  if(cfg.bg) el.style.background = cfg.bg;
  if(cfg.color) track.style.color = cfg.color;
  document.documentElement.classList.add('has-banner');
}

async function apiFetchHeaderBanner(){
  if(!window.supabase) return;
  try {
    var r = await window.supabase.from('app_settings').select('value').eq('key','header_banner').maybeSingle();
    if(!r.data || !r.data.value) return;
    var cfg = typeof r.data.value === 'string' ? JSON.parse(r.data.value) : r.data.value;
    _applyBannerConfig(cfg);

    // Realtime subscription (singleton) — banner se aktualizuje okamžitě
    if(!_bannerChannel){
      try {
        _bannerChannel = window.supabase.channel('header-banner-changes')
          .on('postgres_changes', {event: '*', schema: 'public', table: 'app_settings', filter: 'key=eq.header_banner'}, function(payload){
            try {
              var newVal = payload.new && payload.new.value;
              if(!newVal) return;
              var newCfg = typeof newVal === 'string' ? JSON.parse(newVal) : newVal;
              _applyBannerConfig(newCfg);
            } catch(re){ console.warn('[API] banner realtime:', re); }
          })
          .subscribe();
      } catch(se){ /* realtime optional */ }
    }
  } catch(e){ console.warn('[API] banner:', e); }
}

// ===== HELPERS =====
function _ensureSupabase(){
  if(!window.supabase) console.warn('[API] Supabase není připojen');
}

async function _getUserId(){
  try {
    var r = await window.supabase.auth.getUser();
    return (r.data && r.data.user) ? r.data.user.id : null;
  } catch(e){ return null; }
}

// ===== PROFIL =====
async function apiFetchProfile(){
  _ensureSupabase();
  if(!window.supabase) return null;
  try {
    var uid = await _getUserId();
    if(!uid) return null;
    var r = await window.supabase.from('profiles').select('*').eq('id', uid).single();
    if(r.data){
      // Doplň email z auth
      var u = await window.supabase.auth.getUser();
      if(u.data && u.data.user) r.data.email = u.data.user.email;
    }
    return r.data || null;
  } catch(e){ console.error('[API] apiFetchProfile:', e); return null; }
}

async function apiUpdateProfile(data){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    var r = await window.supabase.from('profiles').update(data).eq('id', uid);
    if(r.error) return {error: r.error.message};
    return {error:null};
  } catch(e){ return {error:'Chyba při ukládání profilu'}; }
}

// ===== MOTORKY =====
async function apiFetchMotos(){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var r = await window.supabase.from('motorcycles').select('*, branches(name, address, city, is_open)').eq('status','active');
    return r.data || [];
  } catch(e){ console.error('[API] apiFetchMotos:', e); return []; }
}

// ===== SOS REPLACEMENT FAB CHECK (only during active replacement flow) =====
async function apiCheckPendingSosReplacement(){
  _ensureSupabase();
  if(!window.supabase) return null;
  try {
    var uid = await _getUserId();
    if(!uid) return null;
    // FAB only when replacement is in progress (selecting motorcycle or pending payment)
    // After payment/free selection (status: paid/delivered) → FAB disappears
    var r = await window.supabase.from('sos_incidents')
      .select('id, type, status, replacement_status, replacement_data, booking_id, original_moto_id, customer_fault')
      .eq('user_id', uid)
      .in('replacement_status', ['selecting', 'pending_payment'])
      .not('status', 'in', '("resolved","closed")')
      .order('created_at', {ascending: false})
      .limit(1);
    if(r.data && r.data.length > 0) return r.data[0];
    return null;
  } catch(e){ console.error('[API] apiCheckPendingSosReplacement:', e); return null; }
}

