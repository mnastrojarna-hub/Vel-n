
// Generate final (konečná) invoice — called after ride end, summarizes all DPs
async function apiGenerateFinalInvoice(bookingId){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    // Check if KF already exists for this booking (prevent duplicates)
    var existingKf = await window.supabase.from('invoices').select('id, number')
      .eq('booking_id', bookingId).eq('type', 'final').limit(1);
    if(existingKf.data && existingKf.data.length > 0){
      return {error: null, invoice_number: existingKf.data[0].number, existing: true};
    }
    var br = await window.supabase.from('bookings')
      .select('*, motorcycles('+_MOTO_PRICE_COLS+')')
      .eq('id', bookingId).single();
    if(br.error || !br.data){ console.error('[API] KF booking query failed:', br.error ? br.error.message : 'no data'); return {error:'Booking not found: '+(br.error?br.error.message:'no data')}; }
    var b = br.data, m = br.data.motorcycles || {};
    // Fetch all DP (payment_receipt) for this booking — only DP are tax documents
    var dpR = await window.supabase.from('invoices').select('*')
      .eq('booking_id', bookingId).eq('type', 'payment_receipt')
      .neq('status', 'cancelled')
      .order('created_at', {ascending: true});
    var receipts = dpR.data || [];
    var yr = new Date().getFullYear();
    var lr = await window.supabase.from('invoices').select('number')
      .like('number', 'KF-' + yr + '-%').order('number', {ascending:false}).limit(1);
    var seq = 1;
    if(lr.data && lr.data.length > 0){
      var mt = lr.data[0].number.match(/-(\d+)$/);
      if(mt) seq = parseInt(mt[1], 10) + 1;
    }
    var invNum = 'KF-' + yr + '-' + String(seq).padStart(4, '0');
    var items = _buildBookingItems(b, m);
    var serviceTotal = _calcItemsTotal(items);
    // If total_price > service total (due to storno-absorbed shortening), add storno fee line
    var bookingTotal = Number(b.total_price || 0);
    if(bookingTotal > serviceTotal && serviceTotal > 0){
      var retainedAmount = Math.round(bookingTotal - serviceTotal);
      items.push({description: 'Storno poplatek (dle storno podmínek)', qty: 1, unit_price: retainedAmount});
    }
    // Deduct ALL DP (daňové doklady k platbě): reservation, edits, SOS
    receipts.forEach(function(a){
      items.push({description: 'Odpočet dle DP ' + a.number, qty: 1, unit_price: -Number(a.total || 0)});
    });
    var subtotal = _calcItemsTotal(items);
    var tax = 0; // Neplátce DPH
    var total = subtotal;
    var issueDate = new Date().toISOString().slice(0, 10);
    var inv = await window.supabase.from('invoices').insert({
      number: invNum, type: 'final', customer_id: uid, booking_id: bookingId,
      items: items, subtotal: subtotal, tax_amount: tax, total: total,
      issue_date: issueDate, due_date: issueDate, status: 'paid',
      variable_symbol: invNum, source: 'final_summary'
    }).select().single();
    if(inv.error){ console.error('[API] Final invoice INSERT FAILED:', inv.error.message, inv.error.details, inv.error.hint); return {error: inv.error.message}; }
    // Insert into documents table for app display (type is TEXT column, accepts any value)
    try {
      var docR = await window.supabase.from('documents').insert({
        booking_id: bookingId, user_id: uid, type: 'invoice_final',
        file_name: 'Konečná faktura ' + invNum + '.pdf',
        file_path: 'invoices/' + (inv.data ? inv.data.id : bookingId) + '.html'
      });
      if(docR.error) console.warn('[API] KF doc insert err:', docR.error.message);
    } catch(de){ console.warn('[API] KF doc insert exception:', de); }
    return {error: null, invoice_number: invNum};
  } catch(e){ console.error('[API] finalInvoice:', e); return {error: e.message}; }
}

// Generate payment receipt (doklad k přijaté platbě) — issued alongside ZF after payment
// editCtx (optional for source=edit): same as apiGenerateAdvanceInvoice
async function apiGeneratePaymentReceipt(bookingId, amount, source, editCtx){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  // Skip DP generation for zero-amount operations (free modifications, SOS without payment)
  if(source === 'edit' && amount === 0) return {error: null, skipped: true};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    // Dedup: check if a DP with same source already exists for this booking
    var existingDp = await window.supabase.from('invoices').select('id, number')
      .eq('booking_id', bookingId).eq('type', 'payment_receipt').eq('source', source || 'booking')
      .neq('status', 'cancelled').limit(1);
    if(existingDp.data && existingDp.data.length > 0){
      return {error: null, receipt_number: existingDp.data[0].number, existing: true};
    }
    var br = await window.supabase.from('bookings')
      .select('*, motorcycles('+_MOTO_PRICE_COLS+')')
      .eq('id', bookingId).single();
    if(br.error || !br.data){ console.error('[API] DP booking query failed:', br.error ? br.error.message : 'no data'); return {error:'Booking not found: '+(br.error?br.error.message:'no data')}; }
    var b = br.data, m = br.data.motorcycles || {};
    var yr = new Date().getFullYear();
    var lr = await window.supabase.from('invoices').select('number')
      .like('number', 'DP-' + yr + '-%').order('number', {ascending:false}).limit(1);
    var seq = 1;
    if(lr.data && lr.data.length > 0){
      var mt = lr.data[0].number.match(/-(\d+)$/);
      if(mt) seq = parseInt(mt[1], 10) + 1;
    }
    var dpNum = 'DP-' + yr + '-' + String(seq).padStart(4, '0');
    var items, subtotal;
    if(source === 'edit' && editCtx){
      items = _buildEditItems(editCtx, b, m);
      subtotal = _calcItemsTotal(items);
    } else if(source === 'edit'){
      var mName = m.model || 'motorky';
      items = [{description:(amount<0?'Vrácení za zkrácení':'Doplatek za prodloužení')+' rezervace – '+mName, qty:1, unit_price:amount}];
      subtotal = amount;
    } else if(source === 'sos'){
      items = [{description:'SOS incident – ' + (m.model||'motorky'), qty:1, unit_price:amount}];
      subtotal = amount;
    } else {
      items = _buildBookingItems(b, m);
      subtotal = _calcItemsTotal(items);
    }
    var tax = 0; // Neplátce DPH
    var total = subtotal;
    var issueDate = new Date().toISOString().slice(0, 10);
    var inv = await window.supabase.from('invoices').insert({
      number: dpNum, type: 'payment_receipt', customer_id: uid, booking_id: bookingId,
      items: items, subtotal: subtotal, tax_amount: tax, total: total,
      issue_date: issueDate, due_date: issueDate, status: 'paid',
      variable_symbol: dpNum, source: source || 'booking'
    }).select().single();
    if(inv.error){ console.error('[API] Payment receipt INSERT FAILED:', inv.error.message, inv.error.details, inv.error.hint); return {error: inv.error.message}; }
    // Insert into documents table for app display (type is TEXT column, accepts any value)
    try {
      var docR = await window.supabase.from('documents').insert({
        booking_id: bookingId, user_id: uid, type: 'payment_receipt',
        file_name: 'Doklad k přijaté platbě ' + dpNum + '.pdf',
        file_path: 'invoices/' + (inv.data ? inv.data.id : bookingId) + '.html'
      });
      if(docR.error) console.warn('[API] DP doc insert err:', docR.error.message);
    } catch(de){ console.warn('[API] DP doc insert exception:', de); }
    return {error: null, receipt_number: dpNum};
  } catch(e){ console.error('[API] paymentReceipt:', e); return {error: e.message}; }
}

// Legacy alias
var apiAutoGenerateInvoice = apiGenerateAdvanceInvoice;

// force=true: delete existing contract/vop and regenerate (used after booking modification)
async function apiAutoGenerateBookingDocs(bookingId, force){
  _ensureSupabase();
  if(!window.supabase) return;
  try {
    var uid = await _getUserId();
    if(!uid) return;
    // Check if docs already exist for this booking
    var existing = await window.supabase.from('documents')
      .select('id, type').eq('booking_id', bookingId).eq('user_id', uid)
      .in('type', ['contract', 'vop']);
    var existingTypes = (existing.data || []).map(function(d){ return d.type; });

    // Force mode: delete old contract/vop so new ones are generated with updated data
    if(force && existing.data && existing.data.length > 0){
      for(var di=0; di<existing.data.length; di++){
        await window.supabase.from('documents').delete().eq('id', existing.data[di].id);
      }
      // Also delete from generated_documents
      await window.supabase.from('generated_documents').delete().eq('booking_id', bookingId);
      existingTypes = [];
    }

    // Generate contract via edge function (creates generated_documents + syncs to documents via trigger)
    if(existingTypes.indexOf('contract') === -1){
      var contractOk = false;
      try {
        var cRes = await window.supabase.functions.invoke('generate-document', {
          body: { template_slug: 'rental_contract', booking_id: bookingId }
        });
        if(cRes.error){ throw new Error(cRes.error.message || 'Edge function error'); }
        // Check response body for success
        var cBody = cRes.data;
        if(typeof cBody === 'string'){ try { cBody = JSON.parse(cBody); } catch(pe){} }
        if(cBody && cBody.error){ throw new Error(cBody.error); }
        contractOk = true;
      } catch(e){
        console.warn('[API] Contract edge fn failed:', e.message, '— inserting direct fallback');
        try {
          await window.supabase.from('documents').insert({
            booking_id: bookingId, user_id: uid, type: 'contract',
            file_name: 'Smlouva o pronájmu.pdf',
            file_path: 'contracts/' + bookingId + '_contract.html'
          });
        } catch(e2){ console.warn('[API] Contract fallback insert failed:', e2.message); }
      }
    }
    // Generate VOP via edge function
    if(existingTypes.indexOf('vop') === -1){
      var vopOk = false;
      try {
        var vRes = await window.supabase.functions.invoke('generate-document', {
          body: { template_slug: 'vop', booking_id: bookingId }
        });
        if(vRes.error){ throw new Error(vRes.error.message || 'Edge function error'); }
        var vBody = vRes.data;
        if(typeof vBody === 'string'){ try { vBody = JSON.parse(vBody); } catch(pe){} }
        if(vBody && vBody.error){ throw new Error(vBody.error); }
        vopOk = true;
      } catch(e){
        console.warn('[API] VOP edge fn failed:', e.message, '— inserting direct fallback');
        try {
          await window.supabase.from('documents').insert({
            booking_id: bookingId, user_id: uid, type: 'vop',
            file_name: 'Všeobecné obchodní podmínky.pdf',
            file_path: 'documents/vop_current.html'
          });
        } catch(e2){ console.warn('[API] VOP fallback insert failed:', e2.message); }
      }
    }
  } catch(e){ console.error('[API] autoGenerateBookingDocs:', e); }
}

