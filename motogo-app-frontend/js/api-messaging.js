// ===== SOS =====
async function apiCreateSosIncident(type, bookingId, lat, lng, desc, critical, motoId){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline – Supabase nepřipojen'};
  try {
    var uid = await _getUserId();
    if(!uid){
      console.error('[SOS] apiCreateSosIncident: user_id is null — session expired?');
      return {error:'Nepřihlášen – přihlaste se znovu'};
    }
    var data = {user_id: uid, type: type, status: 'reported'};
    if(bookingId) data.booking_id = bookingId;
    if(motoId) data.moto_id = motoId;
    if(lat != null && !isNaN(lat)) data.latitude = lat;
    if(lng != null && !isNaN(lng)) data.longitude = lng;
    if(desc) data.description = desc;
    var r = await window.supabase.from('sos_incidents').insert(data).select().single();
    if(r.error){
      console.error('[SOS] INSERT error:', r.error.code, r.error.message, r.error.details, r.error.hint, 'status:', r.status);
      var errMsg = r.error.message || 'Neznámá chyba';
      // Pokud je to 403/RLS error, přidej nápovědu
      if(r.status === 403 || (errMsg && errMsg.indexOf('policy') >= 0)){
        errMsg = 'Nemáte oprávnění — zkuste se odhlásit a přihlásit znovu. (' + errMsg + ')';
      }
      return {error: errMsg, code: r.error.code, details: r.error.details, status: r.status};
    }
    return r.data || {};
  } catch(e){
    console.error('[SOS] apiCreateSosIncident exception:', e);
    return {error:'Výjimka: ' + (e.message || e)};
  }
}

async function apiGetMySosIncidents(){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var uid = await _getUserId();
    if(!uid) return [];
    var r = await window.supabase.from('sos_incidents')
      .select('*')
      .eq('user_id', uid)
      .order('created_at', {ascending: false})
      .limit(10);
    return r.data || [];
  } catch(e){ return []; }
}

async function apiSosRequestReplacement(incidentId){
  _ensureSupabase();
  if(!window.supabase) return {};
  try {
    await window.supabase.from('sos_timeline').insert({
      incident_id: incidentId,
      action: 'replacement_requested',
      data: { note: 'Zákazník žádá náhradní motorku' }
    });
    return {success:true};
  } catch(e){ return {}; }
}

async function apiSosRequestTow(incidentId){
  _ensureSupabase();
  if(!window.supabase) return {};
  try {
    await window.supabase.from('sos_timeline').insert({
      incident_id: incidentId,
      action: 'tow_requested',
      data: { note: 'Zákazník žádá odtahovou službu' }
    });
    return {success:true};
  } catch(e){ return {}; }
}

async function apiSosShareLocation(incidentId, lat, lng){
  _ensureSupabase();
  if(!window.supabase) return {};
  try {
    await window.supabase.from('sos_timeline').insert({
      incident_id: incidentId,
      action: 'location_shared',
      data: { note: 'GPS: ' + lat + ', ' + lng, latitude: lat, longitude: lng }
    });
    // Update incident coordinates so Velín can see location on map
    await window.supabase.from('sos_incidents').update({
      latitude: lat, longitude: lng
    }).eq('id', incidentId);
    return {success:true};
  } catch(e){ return {}; }
}

// ===== ADMIN MESSAGES (Zprávy z velínu) =====
async function apiFetchAdminMessages(){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var uid = await _getUserId();
    if(!uid) return [];
    var r = await window.supabase.from('admin_messages')
      .select('*')
      .eq('user_id', uid)
      .order('created_at', {ascending: false})
      .limit(50);
    return r.data || [];
  } catch(e){ console.error('[API] apiFetchAdminMessages:', e); return []; }
}

async function apiMarkMessageRead(msgId){
  _ensureSupabase();
  if(!window.supabase) return;
  try {
    await window.supabase.from('admin_messages')
      .update({read: true})
      .eq('id', msgId);
  } catch(e){}
}

async function apiMarkAllMessagesRead(){
  _ensureSupabase();
  if(!window.supabase) return;
  try {
    var uid = await _getUserId();
    if(!uid) return;
    await window.supabase.from('admin_messages')
      .update({read: true})
      .eq('user_id', uid)
      .eq('read', false);
  } catch(e){}
}

async function apiGetUnreadMessageCount(){
  _ensureSupabase();
  if(!window.supabase) return 0;
  try {
    var uid = await _getUserId();
    if(!uid) return 0;
    // Count unread admin_messages (notifications)
    var r1 = await window.supabase.from('admin_messages')
      .select('id', {count: 'exact', head: true})
      .eq('user_id', uid)
      .eq('read', false);
    var notifCount = r1.count || 0;
    // Count unread thread messages via RPC (bypasses RLS)
    var threadCount = 0;
    try {
      var r2 = await window.supabase.rpc('get_unread_thread_message_count', {p_customer_id: uid});
      if(r2.data !== null && r2.data !== undefined) threadCount = r2.data;
    } catch(e2){}
    return notifCount + threadCount;
  } catch(e){ return 0; }
}

async function apiMarkThreadMessagesRead(threadId){
  _ensureSupabase();
  if(!window.supabase) return;
  try {
    // Use RPC to mark messages as read (customer can't UPDATE messages directly)
    await window.supabase.rpc('mark_thread_messages_read', {p_thread_id: threadId});
  } catch(e){ console.warn('markThreadMessagesRead failed:', e); }
}

function apiSubscribeAdminMessages(callback){
  if(!window.supabase) return null;
  _getUserId().then(function(uid){
    if(!uid) return;
    window.supabase
      .channel('admin_messages_' + uid)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'admin_messages',
        filter: 'user_id=eq.' + uid
      }, function(payload){
        if(payload.new) callback(payload.new);
      })
      .subscribe();
  });
}

// ===== REALTIME SUBSCRIPTIONS — auto-update when admin changes data =====
var _realtimeChannel = null;
var _realtimeRefreshTimer = null;

function apiSubscribeRealtimeUpdates(){
  if(!window.supabase) return;
  if(_realtimeChannel) return; // already subscribed

  _realtimeChannel = window.supabase
    .channel('motogo-realtime')
    .on('postgres_changes', {
      event: '*', schema: 'public', table: 'motorcycles'
    }, function(payload){
      _scheduleRealtimeRefresh('motos');
    })
    .on('postgres_changes', {
      event: '*', schema: 'public', table: 'bookings'
    }, function(payload){
      _scheduleRealtimeRefresh('bookings');
    })
    .on('postgres_changes', {
      event: '*', schema: 'public', table: 'moto_day_prices'
    }, function(payload){
      _scheduleRealtimeRefresh('motos');
    })
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'documents'
    }, function(payload){
    })
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'invoices'
    }, function(payload){
    })
    .on('postgres_changes', {
      event: '*', schema: 'public', table: 'sos_incidents'
    }, function(payload){
      _scheduleRealtimeRefresh('sos');
    })
    .subscribe();
}

function _scheduleRealtimeRefresh(type){
  // Debounce: wait 500ms then refresh to batch rapid changes
  if(_realtimeRefreshTimer) clearTimeout(_realtimeRefreshTimer);
  _realtimeRefreshTimer = setTimeout(function(){
    _realtimeRefreshTimer = null;
    if(type === 'motos' || type === 'all'){
      if(typeof enrichMOTOS === 'function'){
        enrichMOTOS().then(function(){
          if(typeof initMotoAvailability === 'function') initMotoAvailability();
          if(typeof applyFilters === 'function') applyFilters();
        });
      }
    }
    if(type === 'bookings' || type === 'all'){
      if(typeof renderMyReservations === 'function' && typeof cur !== 'undefined' && cur === 's-res'){
        renderMyReservations();
      }
      if(typeof _currentResId !== 'undefined' && _currentResId && typeof cur !== 'undefined' && cur === 's-res-detail'){
        if(typeof openResDetailById === 'function') openResDetailById(_currentResId);
      }
    }
  }, 500);
}

// Periodic background refresh (every 4 seconds) as fallback
var _bgRefreshInterval = null;
function apiStartBackgroundRefresh(){
  if(_bgRefreshInterval) return;
  _bgRefreshInterval = setInterval(function(){
    if(typeof enrichMOTOS === 'function'){
      enrichMOTOS().then(function(){
        if(typeof initMotoAvailability === 'function') initMotoAvailability();
      });
    }
  }, 4000);
}

function apiStopBackgroundRefresh(){
  if(_bgRefreshInterval){ clearInterval(_bgRefreshInterval); _bgRefreshInterval = null; }
}

// ===== PROMO KÓDY — zalogování použití při platbě =====
async function apiUsePromoCode(code, bookingId, baseAmount){
  _ensureSupabase();
  if(!window.supabase || !code) return {valid:false};
  try {
    var r = await window.supabase.rpc('use_promo_code', {
      p_code: code,
      p_booking_id: bookingId || null,
      p_base_amount: baseAmount || 0
    });
    if(r.data) return r.data;
    if(r.error) console.warn('[API] usePromoCode error:', r.error.message);
    return {valid:false};
  } catch(e){ console.error('[API] apiUsePromoCode:', e); return {valid:false}; }
}

// ===== CUSTOMER → ADMIN ZPRÁVY =====
async function apiSendCustomerMessage(threadId, content){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    var profile = await apiFetchProfile();
    var senderName = profile ? profile.full_name : 'Zákazník';
    var r = await window.supabase.from('messages').insert({
      thread_id: threadId,
      direction: 'customer',
      sender_name: senderName,
      content: content
    });
    if(r.error) return {error: r.error.message};
    // Update thread last_message_at
    await window.supabase.from('message_threads').update({
      last_message_at: new Date().toISOString(),
      status: 'open'
    }).eq('id', threadId);
    return {error:null};
  } catch(e){ return {error:'Chyba při odesílání zprávy'}; }
}

async function apiFetchMyThreads(){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var uid = await _getUserId();
    if(!uid) return [];
    var r = await window.supabase.from('message_threads')
      .select('*, messages(id, content, direction, read_at, created_at)')
      .eq('customer_id', uid)
      .order('last_message_at', {ascending: false});
    return r.data || [];
  } catch(e){ console.error('[API] apiFetchMyThreads:', e); return []; }
}

// ===== ENRICHMENT: propojení lokálního katalogu s Supabase =====

// Originální kopie MOTOS — uloží se při prvním volání enrichMOTOS.
// Díky tomu lze enrichMOTOS volat opakovaně (návrat na home/search)
// bez ztráty motorek co byly mezitím znovu aktivovány.
var _MOTOS_ORIG = null;

/**
 * Obohatí globální pole MOTOS o data ze Supabase.
 * Přiřadí _db objekt (UUID, status, ceny, km) ke každé motorce.
 * Odstraní z MOTOS motorky co nejsou v DB jako 'active'.
 * Bezpečné volat opakovaně — vždy staví z _MOTOS_ORIG.
 */
