// ===== DOKUMENTY =====
async function apiFetchDocuments(){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var uid = await _getUserId();
    if(!uid) return [];
    var results = [];
    // 1) documents table (local auto-generated)
    var r = await window.supabase.from('documents')
      .select('*, bookings(start_date, total_price, motorcycles(model))')
      .eq('user_id', uid)
      .order('created_at', {ascending: false});
    if(r.data) r.data.forEach(function(d){
      // Skip invoice_shop from documents table — step 4 (shop_orders) handles these with correct IDs
      if(d.type === 'invoice_shop') return;
      // Dedup within documents table by file_path (sync trigger can create duplicate rows)
      // Allow multiple invoices of same type per booking (e.g. original ZF + edit ZF)
      var existingDoc = results.find(function(ex){
        return ex.file_path && d.file_path && ex.file_path === d.file_path;
      });
      if(existingDoc) return;
      var b = d.bookings;
      d.date = d.created_at;
      d.moto_name = (b && b.motorcycles) ? b.motorcycles.model : '';
      d.amount = b ? b.total_price : 0;
      d.res_num = b ? '#' + d.booking_id.substr(-8).toUpperCase() : '';
      results.push(d);
    });
    // 2) invoices table (Velín-generated)
    var ir = await window.supabase.from('invoices')
      .select('*, bookings:booking_id(start_date, total_price, motorcycles(model))')
      .eq('customer_id', uid)
      .order('created_at', {ascending: false});
    if(ir.data) ir.data.forEach(function(inv){
      // Skip shop_final invoices — step 4 (shop_orders) handles these with correct IDs
      if(inv.type === 'shop_final') return;
      var b = inv.bookings;
      var iType = inv.type === 'payment_receipt' ? 'payment_receipt'
        : (inv.type === 'proforma' || inv.type === 'advance' || inv.type === 'shop_proforma') ? 'invoice_advance'
        : 'invoice_final';
      // Dedup by invoice id or file_path (allow multiple invoices of same type per booking)
      var invFilePath = 'invoices/' + inv.id + '.html';
      var existing = results.find(function(d){
        return d.id === inv.id || (d.file_path && d.file_path === invFilePath);
      });
      if(existing){
        // Enrich existing doc entry with invoice data (source, number, total)
        if(!existing._invoice) existing._invoice = inv;
        // Always prefer invoice total over booking total_price (SOS bookings have deposit not in total_price)
        if(inv.total != null) existing.amount = inv.total;
        return;
      }
      results.push({
        id: inv.id, booking_id: inv.booking_id,
        type: iType, _invoice: inv,
        date: inv.created_at,
        moto_name: (b && b.motorcycles) ? b.motorcycles.model : '',
        amount: (inv.total != null) ? inv.total : (b ? b.total_price : 0),
        res_num: b ? '#' + inv.booking_id.substr(-8).toUpperCase() : '',
        file_name: inv.number || ''
      });
    });
    // 3) generated_documents (Velín contracts/protocols/VOP)
    var gr = await window.supabase.from('generated_documents')
      .select('*, document_templates:template_id(type, name), bookings:booking_id(start_date, total_price, motorcycles(model))')
      .eq('customer_id', uid)
      .order('created_at', {ascending: false});
    if(gr.data) gr.data.forEach(function(gd){
      var b = gd.bookings;
      var tplType = (gd.document_templates && gd.document_templates.type) || '';
      var mappedType = tplType === 'handover_protocol' ? 'protocol'
        : tplType === 'vop' ? 'vop' : 'contract';
      var hasDup = results.find(function(d){
        return d.booking_id === gd.booking_id && d.type === mappedType;
      });
      if(hasDup) return;
      results.push({
        id: gd.id, booking_id: gd.booking_id,
        type: mappedType, _genDoc: gd,
        date: gd.created_at,
        moto_name: (b && b.motorcycles) ? b.motorcycles.model : '',
        amount: b ? b.total_price : 0,
        res_num: b ? '#' + gd.booking_id.substr(-8).toUpperCase() : '',
        file_path: gd.pdf_path || ''
      });
    });
    // 4) shop_orders – faktury z e-shopu
    try {
      var sr = await window.supabase.from('shop_orders')
        .select('*, shop_order_items(*)')
        .eq('customer_id', uid)
        .in('payment_status', ['paid','pending'])
        .order('created_at', {ascending: false});
      if(sr.data) sr.data.forEach(function(so){
        var itemNames = (so.shop_order_items||[]).map(function(i){ return i.product_name; }).join(', ');
        results.push({
          id: so.id, booking_id: null,
          type: 'invoice_shop', _shopOrder: so,
          date: so.created_at,
          moto_name: '',
          shop_items: itemNames || 'Shop',
          amount: so.total || 0,
          res_num: '#OBJ-' + (so.order_number || so.id.substr(-6).toUpperCase()),
          file_name: 'Faktura objednávka ' + (so.order_number || '')
        });
      });
    } catch(se){ console.error('[API] shop_orders fetch:', se); }
    // Attach debug info for visible diagnostics
    results._debug = {
      docs: r.error ? 'ERR: '+r.error.message : (r.data||[]).length,
      invoices: ir.error ? 'ERR: '+ir.error.message : (ir.data||[]).length,
      docsTypes: (r.data||[]).map(function(d){return d.type;}),
      invTypes: (ir.data||[]).map(function(i){return i.type+'/'+i.number;})
    };
    return results;
  } catch(e){ console.error('[API] apiFetchDocuments:', e); return []; }
}

// Fetch invoices for a specific booking (from invoices table)
async function apiFetchBookingInvoices(bookingId){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var r = await window.supabase.from('invoices')
      .select('*').eq('booking_id', bookingId)
      .order('created_at', {ascending: false});
    return r.data || [];
  } catch(e){ return []; }
}

// Fetch generated documents for a specific booking
async function apiFetchBookingGenDocs(bookingId){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var r = await window.supabase.from('generated_documents')
      .select('*').eq('booking_id', bookingId)
      .order('created_at', {ascending: false});
    return r.data || [];
  } catch(e){ return []; }
}

async function apiUploadDocument(bookingId, fileData, docType){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    var r = await window.supabase.from('documents').insert({
      booking_id: bookingId,
      user_id: uid,
      type: docType,
      file_path: 'signatures/' + bookingId + '_' + docType + '.png',
      file_name: docType + '_' + bookingId.substr(-8) + '.png'
    });
    if(r.error) return {error: r.error.message};
    return {error:null};
  } catch(e){ return {error:'Chyba při nahrávání dokumentu'}; }
}

async function apiSendDocumentEmail(docId){
  // Supabase nemá email service – simulace pro UI
  try {
    var profile = await apiFetchProfile();
    var email = profile ? profile.email : 'email@email.cz';
    return {success:true, email: email};
  } catch(e){ return {success:false}; }
}

