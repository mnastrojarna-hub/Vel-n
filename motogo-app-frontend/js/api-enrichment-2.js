
// Dynamicky naplní dropdown poboček z MOTOS dat + DB
async function _populateBranchFilter(){
  var sel = document.getElementById('f-branch-home');
  var selSearch = document.getElementById('f-branch');
  // Sbírej unikátní pobočky z MOTOS
  var branches = {};
  MOTOS.forEach(function(m){
    if(m._db && m._db.branch_id && m._db.branch_name){
      branches[m._db.branch_id] = {name: m._db.branch_name, address: m._db.branch_address||'', is_open: m._db.branch_is_open};
    }
  });
  // Doplň z DB všechny pobočky (i ty bez motorek)
  if(window.supabase){
    try {
      var r = await window.supabase.from('branches').select('id, name, address, city, is_open').order('name');
      if(r.data){
        r.data.forEach(function(b){
          if(!branches[b.id]) branches[b.id] = {name: b.name, address: b.address||'', city: b.city||'', is_open: b.is_open};
          else { branches[b.id].is_open = b.is_open; branches[b.id].city = b.city||''; }
        });
      }
    } catch(e){}
  }
  var ids = Object.keys(branches);
  if(!ids.length) return;
  // Home filter
  if(sel){
    var curVal = sel.value;
    sel.innerHTML = '<option value="">🏪 Všechny pobočky</option>';
    ids.forEach(function(id){
      var b = branches[id];
      var label = b.name + (b.city ? ', '+b.city : '') + (b.is_open===false ? ' (zavřená)' : '');
      var opt = document.createElement('option');
      opt.value = id;
      opt.textContent = label;
      sel.appendChild(opt);
    });
    if(curVal) sel.value = curVal;
  }
  // Search filter
  if(selSearch){
    var curVal2 = selSearch.value;
    selSearch.innerHTML = '<option value="">🏪 Všechny pobočky</option>';
    ids.forEach(function(id){
      var b = branches[id];
      var label = b.name + (b.address ? ', '+b.address : '') + (b.is_open===false ? ' (zavřená)' : '');
      var opt = document.createElement('option');
      opt.value = id;
      opt.textContent = label;
      selSearch.appendChild(opt);
    });
    if(curVal2) selSearch.value = curVal2;
  }
}

// ===== AUTO-GENERATE PROTOCOL ON RENTAL START DATE =====
async function apiAutoGenerateProtocolForToday(){
  if(!window.supabase) return;
  try {
    var uid = await _getUserId();
    if(!uid) return;
    var today = new Date().toISOString().slice(0,10);
    // Find bookings starting today that don't have a protocol yet
    var bks = await window.supabase.from('bookings').select('id')
      .eq('user_id', uid).eq('payment_status','paid')
      .gte('start_date', today + 'T00:00:00')
      .lte('start_date', today + 'T23:59:59');
    if(!bks.data) return;
    for(var i=0;i<bks.data.length;i++){
      var bid = bks.data[i].id;
      var existing = await window.supabase.from('documents').select('id')
        .eq('booking_id', bid).eq('user_id', uid).eq('type','protocol').limit(1);
      if(existing.data && existing.data.length > 0) continue;
      await window.supabase.from('documents').insert({
        booking_id: bid, user_id: uid, type: 'protocol',
        file_name: 'Předávací protokol.pdf',
        file_path: 'protocols/' + bid + '_protocol.html'
      });
    }
  } catch(e){ console.warn('[API] protocolAutoGen:', e); }
}

// ===== AUTO-GENERATE FINAL INVOICE FOR ENDED BOOKINGS =====
async function apiAutoGenerateFinalInvoiceForEnded(){
  if(!window.supabase) return;
  try {
    var uid = await _getUserId();
    if(!uid) return;
    var today = new Date().toISOString().slice(0,10);
    // Find completed/active/reserved bookings that are paid and ended (end_date < today or status=completed)
    var bks = await window.supabase.from('bookings').select('id, status, end_date')
      .eq('user_id', uid).eq('payment_status','paid')
      .in('status', ['completed','active','reserved'])
      .lte('end_date', today + 'T23:59:59');
    if(!bks.data) return;
    for(var i=0;i<bks.data.length;i++){
      var b = bks.data[i];
      // Only process if status=completed or end_date < today
      var endDate = new Date(b.end_date); endDate.setHours(0,0,0,0);
      var todayDate = new Date(today); todayDate.setHours(0,0,0,0);
      if(b.status !== 'completed' && endDate >= todayDate) continue;
      // Check if final invoice exists
      var existing = await window.supabase.from('invoices').select('id')
        .eq('booking_id', b.id).eq('type','final').limit(1);
      if(existing.data && existing.data.length > 0) continue;
      await apiGenerateFinalInvoice(b.id);
    }
  } catch(e){ console.warn('[API] finalInvoiceAutoGen:', e); }
}

// ===== FETCH DOCUMENT TEMPLATE (from Velín-uploaded PDFs) =====
async function apiFetchDocTemplate(templateType){
  if(!window.supabase) return null;
  // Map legacy type names to DB template types
  var typeMap = { 'contract': 'rental_contract', 'protocol': 'handover_protocol' };
  var dbType = typeMap[templateType] || templateType;
  try {
    var r = await window.supabase.from('document_templates')
      .select('content_html, name, version')
      .eq('type', dbType).eq('active', true)
      .order('version', {ascending:false}).limit(1);
    return (r.data && r.data[0]) || null;
  } catch(e){ return null; }
}

// ===== OCR: Auto-save scanned document data to profile =====
async function apiSaveOcrToProfile(ocrData){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};

    // Parse Czech date "D. M. YYYY" to ISO
    function czToIso(v){
      if(!v) return null;
      v = v.trim();
      if(/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
      var m = v.match(/^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$/);
      if(m) return m[3]+'-'+('0'+m[2]).slice(-2)+'-'+('0'+m[1]).slice(-2);
      return null;
    }

    var update = {};
    if(ocrData.firstName && ocrData.lastName){
      update.full_name = ocrData.firstName + ' ' + ocrData.lastName;
    }
    if(ocrData.dob){
      var isoDob = czToIso(ocrData.dob);
      if(isoDob) update.date_of_birth = isoDob;
    }
    if(ocrData.street) update.street = ocrData.street;
    if(ocrData.city) update.city = ocrData.city;
    if(ocrData.zip) update.zip = ocrData.zip;
    if(ocrData.idNumber) update.id_number = ocrData.idNumber;
    if(ocrData.licenseNumber) update.license_number = ocrData.licenseNumber;
    if(ocrData.licenseExpiry){
      var isoExp = czToIso(ocrData.licenseExpiry);
      if(isoExp) update.license_expiry = isoExp;
    }
    if(ocrData.licenseCategory){
      var cats = ocrData.licenseCategory.split(/[,\s]+/).filter(Boolean);
      if(cats.length > 0) update.license_group = cats;
    }

    if(Object.keys(update).length === 0) return {error:null, updated: 0};

    console.log('[API] apiSaveOcrToProfile: updating', Object.keys(update).length, 'fields:', Object.keys(update));
    var r = await window.supabase.from('profiles').update(update).eq('id', uid);
    if(r.error) return {error: r.error.message};
    return {error:null, updated: Object.keys(update).length};
  } catch(e){ console.error('[API] apiSaveOcrToProfile:', e); return {error:'Chyba při ukládání OCR dat'}; }
}

// ===== OCR: Upload scanned document photo to Supabase storage =====
async function apiUploadDocPhoto(base64Data, docType){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};

    // Convert base64 to Blob
    var clean = base64Data;
    if(clean.indexOf(',') !== -1) clean = clean.split(',')[1];
    var byteChars = atob(clean);
    var byteArr = new Uint8Array(byteChars.length);
    for(var i = 0; i < byteChars.length; i++) byteArr[i] = byteChars.charCodeAt(i);
    var blob = new Blob([byteArr], {type:'image/jpeg'});

    var filePath = 'user-docs/' + uid + '/' + docType + '_' + Date.now() + '.jpg';

    var r = await window.supabase.storage.from('documents').upload(filePath, blob, {
      contentType: 'image/jpeg',
      upsert: true
    });

    if(r.error){
      console.warn('[API] apiUploadDocPhoto storage error:', r.error.message);
      return {error: r.error.message, filePath: null};
    }

    // Store reference in documents table
    // Types must match Velín verification: drivers_license, id_card, passport
    var docTypeMap = {
      'id_front': 'id_card', 'id_back': 'id_card',
      'dl_front': 'drivers_license', 'dl_back': 'drivers_license',
      'passport_front': 'passport'
    };
    await window.supabase.from('documents').insert({
      user_id: uid,
      type: docTypeMap[docType] || 'document',
      file_path: filePath,
      file_name: docType + '.jpg'
    });

    return {error: null, filePath: filePath};
  } catch(e){ console.error('[API] apiUploadDocPhoto:', e); return {error:'Upload failed'}; }
}

// ===== OCR: Verify customer documents (cross-check OP vs ŘP vs profile) =====
async function apiVerifyDocs(ocrData){
  _ensureSupabase();
  if(!window.supabase) return {success:false, error:'Offline'};
  try {
    // Parse Czech date to ISO
    function czToIso(v){
      if(!v) return null;
      v = v.trim();
      if(/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
      var m = v.match(/^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$/);
      if(m) return m[3]+'-'+('0'+m[2]).slice(-2)+'-'+('0'+m[1]).slice(-2);
      return null;
    }
    var name = '';
    if(ocrData.firstName && ocrData.lastName) name = ocrData.firstName+' '+ocrData.lastName;
    var r = await window.supabase.rpc('verify_customer_docs', {
      p_ocr_name: name || null,
      p_ocr_dob: czToIso(ocrData.dob) || null,
      p_ocr_id_number: ocrData.idNumber || null,
      p_ocr_license_number: ocrData.licenseNumber || null,
      p_ocr_license_category: ocrData.licenseCategory || null,
      p_ocr_license_expiry: czToIso(ocrData.licenseExpiry) || null
    });
    if(r.error) return {success:false, error:r.error.message};
    var data = typeof r.data === 'string' ? JSON.parse(r.data) : r.data;
    return data;
  } catch(e){ console.error('[API] apiVerifyDocs:', e); return {success:false, error:'Chyba verifikace'}; }
}

// ===== Check license compatibility for a motorcycle =====
// Hierarchie ŘP: A > A2 > A1 > AM, B samostatně, N = bez ŘP (dětské)
var LICENSE_COVERS = {
  'A':  ['A','A2','A1','AM'],
  'A2': ['A2','A1','AM'],
  'A1': ['A1','AM'],
  'AM': ['AM'],
  'B':  ['B','AM']
};
async function apiCheckLicenseForMoto(motoId, endDate){
  _ensureSupabase();
  if(!window.supabase) return {allowed:true};
  try {
    var moto = await window.supabase.from('motorcycles').select('license_required').eq('id', motoId).single();
    if(!moto.data) return {allowed:true};
    var required = moto.data.license_required;
    if(!required || required === 'N') return {allowed:true};
    var profile = await apiFetchProfile();
    if(!profile || !profile.license_group) return {allowed:false, reason:'Nemáte vyplněný řidičský průkaz'};

    // Check license expiry vs booking end date
    if(profile.license_expiry && endDate){
      var expiry = new Date(profile.license_expiry);
      var bookingEnd = new Date(endDate);
      expiry.setHours(0,0,0,0);
      bookingEnd.setHours(0,0,0,0);
      if(expiry < bookingEnd){
        return {allowed:false, reason:'Platnost řidičského průkazu vyprší ' +
          expiry.toLocaleDateString('cs-CZ') + ' — před koncem rezervace'};
      }
    } else if(!profile.license_expiry){
      return {allowed:false, reason:'Nemáte vyplněnou platnost řidičského průkazu'};
    }

    var groups = profile.license_group;
    for(var i = 0; i < groups.length; i++){
      var covers = LICENSE_COVERS[groups[i]];
      if(covers && covers.indexOf(required) !== -1) return {allowed:true};
    }
    return {allowed:false, reason:'Pro tuto motorku potřebujete skupinu ' + required};
  } catch(e){ return {allowed:false, reason:'Chyba kontroly oprávnění'}; }
}

// ===== Persistent doc verification — save to DB (not just localStorage) =====
// Called after successful Mindee scan + verify. Stores verification dates in profiles.
async function apiSaveDocVerification(ocrData, scannedTypes){
  _ensureSupabase();
  if(!window.supabase) return;
  try {
    var uid = await _getUserId();
    if(!uid) return;

    function czToIso(v){
      if(!v) return null; v = v.trim();
      if(/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
      var m = v.match(/^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$/);
      if(m) return m[3]+'-'+('0'+m[2]).slice(-2)+'-'+('0'+m[1]).slice(-2);
      return null;
    }

    var update = {};
    var now = new Date().toISOString();
    var types = scannedTypes || [];

    // OP verified
    if(types.indexOf('id_front') !== -1 || types.indexOf('id_back') !== -1){
      update.id_verified_at = now;
      if(ocrData.expiryDate || ocrData.licenseExpiry){
        var exp = czToIso(ocrData.expiryDate) || czToIso(ocrData.licenseExpiry);
        if(exp) update.id_verified_until = exp;
      }
    }
    // Passport verified
    if(types.indexOf('passport_front') !== -1){
      update.passport_verified_at = now;
      if(ocrData.expiryDate){
        var pExp = czToIso(ocrData.expiryDate);
        if(pExp) update.passport_verified_until = pExp;
      }
    }
    // ŘP verified
    if(types.indexOf('dl_front') !== -1 || types.indexOf('dl_back') !== -1){
      update.license_verified_at = now;
      if(ocrData.licenseExpiry || ocrData.expiryDate){
        var lExp = czToIso(ocrData.licenseExpiry) || czToIso(ocrData.expiryDate);
        if(lExp) update.license_verified_until = lExp;
      }
    }

    if(Object.keys(update).length > 0){
      console.log('[API] apiSaveDocVerification:', Object.keys(update));
      await window.supabase.from('profiles').update(update).eq('id', uid);
    }
  } catch(e){ console.warn('[API] apiSaveDocVerification error:', e); }
}

// Check if docs are verified from DB (persistent, survives logout)
async function apiCheckDocsVerified(){
  _ensureSupabase();
  if(!window.supabase) return false;
  try {
    var uid = await _getUserId();
    if(!uid) return false;
    var r = await window.supabase.from('profiles')
      .select('id_verified_at, id_verified_until, license_verified_at, license_verified_until, passport_verified_at, passport_verified_until')
      .eq('id', uid).maybeSingle();
    if(!r || !r.data) return false;
    var p = r.data;
    var today = new Date().toISOString().slice(0,10);
    var hasId = p.id_verified_at && (!p.id_verified_until || p.id_verified_until >= today);
    var hasPassport = p.passport_verified_at && (!p.passport_verified_until || p.passport_verified_until >= today);
    var hasLicense = p.license_verified_at && (!p.license_verified_until || p.license_verified_until >= today);
    var verified = (hasId || hasPassport) && hasLicense;
    // Sync to localStorage for offline/quick checks
    if(verified) localStorage.setItem('mg_docs_verified','1');
    else localStorage.removeItem('mg_docs_verified');
    return verified;
  } catch(e){ return false; }
}
