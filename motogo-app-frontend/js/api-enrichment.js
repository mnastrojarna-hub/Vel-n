async function enrichMOTOS(){
  if(typeof MOTOS === 'undefined' || !window.supabase) return;
  try {
    // Ulož originál při prvním volání
    if(!_MOTOS_ORIG){
      _MOTOS_ORIG = MOTOS.map(function(m){
        return JSON.parse(JSON.stringify(m));
      });
    }

    // Načti VŠECHNY motorky z DB
    var r = await window.supabase
      .from('motorcycles')
      .select('id, model, status, mileage, year, category, price_weekday, price_weekend, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, branch_id, image_url, images, stk_valid_until, engine_type, engine_cc, power_kw, power_hp, torque_nm, weight_kg, fuel_tank_l, seat_height_mm, license_required, has_abs, has_asc, description, ideal_usage, features, manual_url, branches(name, address, city, is_open)');
    var dbMotos = (r.data || []);

    // Vytvoř mapu podle normalizovaného jména
    var dbMap = {};
    dbMotos.forEach(function(dm){
      var key = dm.model.toLowerCase().replace(/\s+/g, '');
      dbMap[key] = dm;
    });

    // Přebuduj MOTOS z originálu — jen aktivní motorky
    var fresh = [];
    for(var i = 0; i < _MOTOS_ORIG.length; i++){
      var m = JSON.parse(JSON.stringify(_MOTOS_ORIG[i]));
      var key = m.name.toLowerCase().replace(/\s+/g, '');
      var db = dbMap[key];

      // Motorka není v DB nebo není active → přeskoč
      if(!db || db.status !== 'active') continue;
      // Pobočka je zavřená → přeskoč
      if(db.branches && db.branches.is_open === false) continue;

      // Přiřaď _db objekt
      m._db = {
        id: db.id,
        status: db.status,
        mileage: db.mileage,
        branch_id: db.branch_id,
        branch_name: db.branches ? db.branches.name : null,
        branch_address: db.branches ? db.branches.address : null,
        branch_city: db.branches ? db.branches.city : null,
        branch_is_open: db.branches ? db.branches.is_open : null,
        image_url: db.image_url,
        images: db.images,
        stk_valid_until: db.stk_valid_until,
      };

      // Fotky z Velínu (Supabase storage) mají přednost před statickými
      if(db.image_url) m.img = db.image_url;
      if(db.images && db.images.length) m.imgs = db.images;

      // Aktualizuj specs z DB (pokud jsou vyplněny ve Velínu)
      if(db.engine_type || db.power_kw || db.torque_nm || db.weight_kg){
        var dbSpecs = [];
        if(db.engine_type || db.engine_cc) dbSpecs.push({l:'Motor', v: (db.engine_cc ? db.engine_cc+' cc ' : '')+(db.engine_type||'')});
        if(db.power_kw) dbSpecs.push({l:'Výkon', v: db.power_kw+' kW'+(db.power_hp ? ' / '+db.power_hp+' k' : '')});
        if(db.torque_nm) dbSpecs.push({l:'Točivý moment', v: db.torque_nm+' Nm'});
        if(db.weight_kg) dbSpecs.push({l:'Hmotnost', v: db.weight_kg+' kg'});
        if(db.fuel_tank_l) dbSpecs.push({l:'Nádrž', v: db.fuel_tank_l+' L'});
        if(db.seat_height_mm) dbSpecs.push({l:'Sedlo', v: db.seat_height_mm+' mm'});
        if(db.license_required) dbSpecs.push({l:'ŘP kategorie', v: db.license_required});
        var absAsc = [];
        if(db.has_abs !== null) absAsc.push(db.has_abs ? 'ABS' : '—');
        if(db.has_asc !== null) absAsc.push(db.has_asc ? 'ASC' : '—');
        if(absAsc.length) dbSpecs.push({l:'ABS / ASC', v: absAsc.join(' / ')});
        if(dbSpecs.length > 0) m.specs = dbSpecs;
      }
      // Aktualizuj kategorii, ŘP a výkon z DB (přepiš hardcoded)
      if(db.category){ var _nc=db.category.toLowerCase().replace(/[íé]/g,function(c){return c==='í'?'i':'e';}); m.cat=_nc; }
      if(db.license_required) m.rp = db.license_required;
      if(db.power_kw) m.vykon = db.power_kw;

      if(db.description) m.desc = db.description;
      if(db.ideal_usage && db.ideal_usage.length) m.vyuziti = db.ideal_usage;
      if(db.features && db.features.length) m.feats = db.features;
      if(db.manual_url) m.manual = db.manual_url;

      // Aktualizuj pobočku z DB (přepiš hardcoded loc)
      if(db.branches){
        m.loc = (db.branches.address || '') + ', ' + (db.branches.city || '') + (db.year ? ' · ' + db.year : '');
        m.branch = db.branch_id;
        m._db.branch_name = db.branches.name;
        m._db.branch_address = db.branches.address;
        m._db.branch_city = db.branches.city;
      }

      // Aktualizuj ceny z DB (přepiš hardcoded pricing)
      if(db.price_weekday || db.price_weekend){
        m.pricing = {
          po: Number(db.price_mon || db.price_weekday) || m.pricing.po,
          ut: Number(db.price_tue || db.price_weekday) || m.pricing.ut,
          st: Number(db.price_wed || db.price_weekday) || m.pricing.st,
          ct: Number(db.price_thu || db.price_weekday) || m.pricing.ct,
          pa: Number(db.price_fri || db.price_weekend) || m.pricing.pa,
          so: Number(db.price_sat || db.price_weekend) || m.pricing.so,
          ne: Number(db.price_sun || db.price_weekend) || m.pricing.ne,
        };
      }

      fresh.push(m);
    }

    // Přidej motorky z DB které NEMAJÍ lokální protějšek (přidány přes Velín)
    var usedKeys = {};
    for(var ui = 0; ui < fresh.length; ui++){
      usedKeys[fresh[ui].name.toLowerCase().replace(/\s+/g, '')] = true;
    }
    dbMotos.forEach(function(db){
      if(db.status !== 'active') return;
      var key = db.model.toLowerCase().replace(/\s+/g, '');
      if(usedKeys[key]) return; // již máme z lokálních dat
      // Vytvoř novou motorku čistě z DB dat
      var nm = {
        id: 'db-' + db.id.substr(0,8),
        name: db.model,
        loc: (db.branches ? db.branches.address + ', ' + db.branches.city : 'Mezná') + (db.year ? ' · ' + db.year : ''),
        img: db.image_url || '',
        imgs: db.images && db.images.length ? db.images : (db.image_url ? [db.image_url] : []),
        avail: true,
        cat: (db.category || 'cestovni').toLowerCase().replace(/[íé]/g,function(c){return c==='í'?'i':'e';}),
        rp: db.license_required || 'A',
        vykon: db.power_kw || 0,
        desc: db.description || db.model,
        specs: [],
        feats: db.features || [],
        vyuziti: db.ideal_usage || [],
        pricing: {
          po: Number(db.price_mon || db.price_weekday) || 2000,
          ut: Number(db.price_tue || db.price_weekday) || 2000,
          st: Number(db.price_wed || db.price_weekday) || 2000,
          ct: Number(db.price_thu || db.price_weekday) || 2000,
          pa: Number(db.price_fri || db.price_weekend) || 2500,
          so: Number(db.price_sat || db.price_weekend) || 2500,
          ne: Number(db.price_sun || db.price_weekend) || 2500,
        },
        branch: db.branch_id || 'mezna',
        manual: db.manual_url || '',
        price: (Number(db.price_weekday) || 2000).toLocaleString('cs-CZ') + ' Kč',
        _db: {
          id: db.id,
          status: db.status,
          mileage: db.mileage,
          branch_id: db.branch_id,
          branch_name: db.branches ? db.branches.name : null,
          branch_address: db.branches ? db.branches.address : null,
          branch_city: db.branches ? db.branches.city : null,
          image_url: db.image_url,
          images: db.images,
          stk_valid_until: db.stk_valid_until,
        }
      };
      // Build specs
      var ds = [];
      if(db.engine_type || db.engine_cc) ds.push({l:'Motor', v: (db.engine_cc ? db.engine_cc+' cc ' : '')+(db.engine_type||'')});
      if(db.power_kw) ds.push({l:'Výkon', v: db.power_kw+' kW'+(db.power_hp ? ' / '+db.power_hp+' k' : '')});
      if(db.torque_nm) ds.push({l:'Točivý moment', v: db.torque_nm+' Nm'});
      if(db.weight_kg) ds.push({l:'Hmotnost', v: db.weight_kg+' kg'});
      if(db.fuel_tank_l) ds.push({l:'Nádrž', v: db.fuel_tank_l+' L'});
      if(db.seat_height_mm) ds.push({l:'Sedlo', v: db.seat_height_mm+' mm'});
      if(db.license_required) ds.push({l:'ŘP kategorie', v: db.license_required});
      var absAsc = [];
      if(db.has_abs !== null) absAsc.push(db.has_abs ? 'ABS' : '—');
      if(db.has_asc !== null) absAsc.push(db.has_asc ? 'ASC' : '—');
      if(absAsc.length) ds.push({l:'ABS / ASC', v: absAsc.join(' / ')});
      nm.specs = ds;
      fresh.push(nm);
    });

    // Nahraď MOTOS čerstvým polem (in-place pro zachování reference)
    MOTOS.length = 0;
    for(var j = 0; j < fresh.length; j++) MOTOS.push(fresh[j]);

    window._enrichMOTOSDone = true;
  } catch(e){
    console.error('[API] enrichMOTOS chyba:', e);
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
    await window.supabase.from('documents').insert({
      user_id: uid,
      type: docType === 'id_front' || docType === 'id_back' ? 'id_photo' :
            docType === 'dl_front' || docType === 'dl_back' ? 'license_photo' :
            docType === 'passport_front' ? 'id_photo' : 'document',
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
    var groups = profile.license_group;
    for(var i = 0; i < groups.length; i++){
      var covers = LICENSE_COVERS[groups[i]];
      if(covers && covers.indexOf(required) !== -1) return {allowed:true};
    }
    return {allowed:false, reason:'Pro tuto motorku potřebujete skupinu ' + required};
  } catch(e){ return {allowed:false, reason:'Chyba kontroly oprávnění'}; }
}
