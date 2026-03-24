// ===== DOCUMENTS-BOOKING.JS – Rental contract, protocol, invoice, overlay UI =====
// Split from original documents.js. See also: documents.js, documents-pages.js

// ===== RENTAL CONTRACT – fetch template from Velín if available =====
async function showRentalContract(bookingId){
  var data=await _getBookingDataAsync(bookingId);
  if(!data) data=_getBookingData(bookingId);
  if(!data){showT('✗',_t('common').error,_t('common').noData);return;}
  var t=_t('doc');var b=data.b,m=data.m,p=data.p,mn=data.motoName,rn=data.resNum;
  var pName=p?p.full_name:'—',pAddr=p?(p.street+', '+p.city+' '+p.zip):'—';
  var pLic=p?p.license_number:'—',pPhone=p?p.phone:'—',pEmail=p?p.email:'—';
  var mSpz=m?m.spz:'—',mVin=m?m.vin:'—';
  var isPaid=(b.payment_status==='paid');
  var statusLine=isPaid?'<div style="color:#1a8a18;font-weight:800;font-size:12px;margin:8px 0;">✓ ZAPLACENO</div>':'<div style="color:#b91c1c;font-weight:800;font-size:12px;margin:8px 0;">⏳ ČEKÁ NA PLATBU</div>';

  // Try Velín template first, with placeholder replacement (supports both {{key}} and {key})
  var tpl = typeof apiFetchDocTemplate === 'function' ? await apiFetchDocTemplate('contract') : null;
  var bodyHtml = '';
  if(tpl && tpl.content_html){
    var pIdNum = p ? (p.id_number || '') : '';
    var pLicExpiry = p && p.license_expiry ? _docDate(p.license_expiry) : '';
    var startTime = b.pickup_time || '';
    var endTime = '24:00';
    var totalWords = '';
    var pickupLoc = b.pickup_address || 'Mezná 9, 393 01 Mezná';
    var returnLoc = b.return_address || 'Mezná 9, 393 01 Mezná';
    var rentalPeriod = _docDate(b.start_date) + ' — ' + _docDate(b.end_date) + ' (' + data.days + ' dní)';
    var dailyRate = Math.round((b.total_price||0)/data.days);
    var mYear = m ? (m.year || '') : '';
    var mileageStart = b.mileage_start || '';
    var vars = {
      'company_name': COMPANY.name, 'company_address': COMPANY.sidlo,
      'company_ico': COMPANY.ic, 'company_dic': '', 'company_email': COMPANY.email,
      'customer_name': pName, 'customer_address': pAddr,
      'customer_phone': pPhone, 'customer_email': pEmail,
      'customer_license': pLic, 'customer_license_expiry': pLicExpiry,
      'customer_ico': p ? (p.ico || '') : '', 'customer_dic': p ? (p.dic || '') : '',
      'customer_id_number': pIdNum,
      'moto_model': mn, 'moto_name': mn, 'moto_spz': mSpz, 'moto_vin': mVin, 'moto_year': String(mYear),
      'start_date': _docDate(b.start_date), 'end_date': _docDate(b.end_date),
      'date_from': _docDate(b.start_date), 'date_to': _docDate(b.end_date),
      'start_time': startTime, 'end_time': endTime,
      'days': String(data.days), 'rental_period': rentalPeriod,
      'total_price': (b.total_price||0).toLocaleString('cs-CZ'),
      'total_price_words': totalWords,
      'daily_rate': dailyRate.toLocaleString('cs-CZ'),
      'extras_price': (b.extras_price||0).toLocaleString('cs-CZ'),
      'delivery_fee': (b.delivery_fee||0).toLocaleString('cs-CZ'),
      'discount': (b.discount_amount||0).toLocaleString('cs-CZ'),
      'res_number': rn, 'booking_number': rn, 'booking_id': b.id.substr(-8).toUpperCase(),
      'today': _docDate(new Date().toISOString()),
      'today_time': new Date().toLocaleTimeString('cs-CZ', {hour:'2-digit',minute:'2-digit'}),
      'pickup_location': pickupLoc, 'return_location': returnLoc,
      'mileage': String(mileageStart), 'fuel_state': '', 'technical_state': ''
    };
    bodyHtml = tpl.content_html;
    for(var k in vars){
      bodyHtml = bodyHtml.replace(new RegExp('\\{\\{'+k+'\\}\\}','g'), vars[k])
                         .replace(new RegExp('\\{'+k+'\\}','g'), vars[k]);
    }
  } else {
    bodyHtml = '<h3>'+t.contractTitle+'</h3>'+statusLine+
      '<div class="doc-parties"><div class="doc-party"><strong>'+t.lessor+':</strong><br>'+
      COMPANY.name+'<br>'+COMPANY.sidlo+'<br>IČ: '+COMPANY.ic+'<br>'+COMPANY.email+'</div>'+
      '<div class="doc-party"><strong>'+t.lessee+':</strong><br>'+
      pName+'<br>'+pAddr+'<br>'+t.phone+': '+pPhone+'<br>E-mail: '+pEmail+'<br>ŘP: '+pLic+'</div></div>'+
      '<h4>'+t.contractSubject+'</h4>'+
      '<p>'+t.contractSubjectText.replace('{moto}',mn).replace('{from}',_docDate(b.start_date))
        .replace('{to}',_docDate(b.end_date)).replace('{days}',data.days)+'</p>'+
      '<div class="doc-field" style="margin:6px 0;"><span class="doc-lbl">SPZ:</span> '+mSpz+'</div>'+
      '<div class="doc-field" style="margin:6px 0;"><span class="doc-lbl">VIN:</span> '+mVin+'</div>'+
      '<h4>'+t.contractPrice+'</h4>'+
      '<p>'+t.contractPriceText.replace('{total}',(b.total_price||0).toLocaleString('cs-CZ'))+'</p>'+
      (b.extras_price>0?'<div class="doc-field"><span class="doc-lbl">Příslušenství:</span> '+b.extras_price.toLocaleString('cs-CZ')+' Kč</div>':'')+
      (b.delivery_fee>0?'<div class="doc-field"><span class="doc-lbl">Doručení:</span> '+b.delivery_fee.toLocaleString('cs-CZ')+' Kč</div>':'')+
      (b.discount_amount>0?'<div class="doc-field"><span class="doc-lbl">Sleva:</span> -'+b.discount_amount.toLocaleString('cs-CZ')+' Kč</div>':'')+
      '<h4>'+t.contractConditions+'</h4><p>'+t.contractConditionsText+'</p>';
  }

  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
    '<h2>'+t.contractTitle+'</h2><p>'+rn+'</p></div><div class="doc-view-body">'+bodyHtml+
    '<div style="margin-top:14px;padding:10px;background:#f0fdf4;border-radius:8px;font-size:11px;color:#1a8a18;font-weight:700;">✓ Souhlas udělen při rezervaci (zaškrtnutím podmínek)</div>'+
    '</div></div>';
  _openDocOverlay(html);
}

// ===== HANDOVER PROTOCOL – fetch template from Velín if available =====
async function showDigitalProtocol(bookingId){
  if(!bookingId){
    var bks=await apiFetchMyBookings();
    if(bks.length>0) bookingId=bks[0].id;
  }
  var data=bookingId?(await _getBookingDataAsync(bookingId)||_getBookingData(bookingId)):null;
  var t=_t('doc');
  var mn=data?data.motoName:'Motorka',rn=data?data.resNum:'#RES-0000';
  var pName=data&&data.p?data.p.full_name:'—';
  var pickup=data?_docDate(data.b.start_date):'—';
  var returnD=data?_docDate(data.b.end_date):'—';
  var mSpz=data&&data.m?data.m.spz:'—';

  var tpl = typeof apiFetchDocTemplate === 'function' ? await apiFetchDocTemplate('protocol') : null;
  var bodyHtml = '';
  if(tpl && tpl.content_html){
    var mVin = data && data.m ? (data.m.vin||'') : '';
    var mileageVal = data ? (data.b.mileage_start||'') : '';
    var vars2 = {
      'company_name': COMPANY.name, 'company_address': COMPANY.sidlo,
      'customer_name': pName, 'moto_model': mn, 'moto_name': mn,
      'moto_spz': mSpz, 'moto_vin': mVin,
      'start_date': pickup, 'end_date': returnD, 'date_from': pickup, 'date_to': returnD,
      'res_number': rn, 'booking_number': rn,
      'today': _docDate(new Date().toISOString()),
      'today_time': new Date().toLocaleTimeString('cs-CZ', {hour:'2-digit',minute:'2-digit'}),
      'mileage': String(mileageVal), 'fuel_state': '', 'technical_state': ''
    };
    bodyHtml = tpl.content_html;
    for(var k2 in vars2){
      bodyHtml = bodyHtml.replace(new RegExp('\\{\\{'+k2+'\\}\\}','g'), vars2[k2])
                         .replace(new RegExp('\\{'+k2+'\\}','g'), vars2[k2]);
    }
  } else {
    var items=[
      {name:'Klíče (od motorky + od kufru)',checked:true,locked:true},
      {name:'Zelená karta',checked:true,locked:true},
      {name:'Malý technický průkaz',checked:true,locked:true},
      {name:'2× reflexní vesta',checked:true,locked:true},
      {name:'Motolékárnička',checked:true,locked:true},
      {name:'Záznam o dopravní nehodě',checked:true,locked:true},
      {name:'Kukla (nová) – zákazník si nechává',checked:true,locked:true},
      {name:'Helma řidiče',checked:true,locked:false},
      {name:'Rukavice',checked:true,locked:false},
      {name:'Bunda',checked:true,locked:false},
      {name:'Kalhoty',checked:true,locked:false}
    ];
    var checkHtml=items.map(function(it){
      var dis=it.locked?' disabled':'';
      var chk=it.checked?' checked':'';
      return '<label style="display:flex;align-items:center;gap:8px;font-size:12px;font-weight:600;cursor:'+(it.locked?'default':'pointer')+';">'+
        '<input type="checkbox" class="proto-chk"'+chk+dis+' style="accent-color:var(--green);width:15px;height:15px;"> '+it.name+'</label>';
    }).join('');
    bodyHtml = '<div class="doc-parties"><div class="doc-party"><strong>'+COMPANY.name+'</strong></div>'+
      '<div class="doc-party"><strong>'+pName+'</strong></div></div>'+
      '<div class="doc-field"><span class="doc-lbl">'+t.motorcycle+':</span> '+mn+'</div>'+
      '<div class="doc-field"><span class="doc-lbl">'+t.pickupDate+':</span> '+pickup+'</div>'+
      '<div class="doc-field"><span class="doc-lbl">'+t.returnDate+':</span> '+returnD+'</div>'+
      '<h4>'+t.protocolItems+'</h4>'+
      '<div style="display:flex;flex-direction:column;gap:7px;">'+checkHtml+'</div>'+
      '<h4 style="margin-top:14px;">'+t.protocolNotes+'</h4>'+
      '<textarea id="proto-notes" rows="3" style="width:100%;border:1.5px solid var(--g200);border-radius:8px;padding:8px;font-family:var(--font);font-size:12px;" placeholder="'+t.protocolNotesPlaceholder+'"></textarea>';
  }

  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
    '<h2>'+t.protocolTitle+'</h2><p>'+rn+'</p></div><div class="doc-view-body">'+bodyHtml+
    '<div style="margin-top:14px;padding:10px;background:#f0fdf4;border-radius:8px;font-size:11px;color:#1a8a18;font-weight:700;">✓ Souhlas udělen při rezervaci (zaškrtnutím podmínek)</div>'+
    '</div></div>';
  _openDocOverlay(html);
}

// ===== INVOICE GENERATION (Czech accounting standards) =====
// invoiceId (optional 3rd param): show specific invoice by ID (for multiple ZFs/DPs per booking)
async function showInvoice(bookingId,type,invoiceId){
  if(!bookingId||bookingId==='null'||bookingId==='undefined'){
    if(invoiceId&&invoiceId!=='null'&&invoiceId!=='undefined') return showInvoiceById(invoiceId);
    showT('✗',_t('common').error,_t('common').noData);return;
  }
  var data=await _getBookingDataAsync(bookingId);
  if(!data) data=_getBookingData(bookingId);
  if(!data){
    if(invoiceId&&invoiceId!=='null'&&invoiceId!=='undefined') return showInvoiceById(invoiceId);
    showT('✗',_t('common').error,_t('common').noData);return;
  }
  var t=_t('doc');var b=data.b,p=data.p,mn=data.motoName,rn=data.resNum;

  // Load real invoice from DB — by ID or filter by type
  var isAdvance=(type==='advance');
  var isReceipt=(type==='payment_receipt');
  var dbInvoice=null;
  if(_isSupabaseReady()){
    try {
      if(invoiceId){
        var invById=await supabase.from('invoices').select('*').eq('id',invoiceId).single();
        if(invById.data) dbInvoice=invById.data;
      }
      if(!dbInvoice){
        var dbTypes=isReceipt?['payment_receipt']:isAdvance?['proforma','advance','shop_proforma']:['final','issued'];
        var invR=await supabase.from('invoices').select('*')
          .eq('booking_id',bookingId).in('type',dbTypes)
          .order('created_at',{ascending:false}).limit(1);
        if(invR.data && invR.data.length>0) dbInvoice=invR.data[0];
      }
      // For final invoices: auto-generate KF if not found (e.g. SOS-ended bookings skip trigger)
      if(!dbInvoice && type==='final' && typeof apiGenerateFinalInvoice === 'function'){
        try {
          var kfRes = await apiGenerateFinalInvoice(bookingId);
          if(!kfRes.error && kfRes.invoice_number){
            // Reload the just-created KF
            var kfR = await supabase.from('invoices').select('*')
              .eq('booking_id',bookingId).eq('type','final')
              .order('created_at',{ascending:false}).limit(1);
            if(kfR.data && kfR.data.length>0) dbInvoice=kfR.data[0];
          }
        } catch(kfe){ console.warn('[DOC] Auto-generate KF failed:', kfe); }
      }
      // Fallback: any invoice for this booking (only for non-final types)
      if(!dbInvoice && type!=='final'){
        var invR2=await supabase.from('invoices').select('*')
          .eq('booking_id',bookingId)
          .order('created_at',{ascending:false}).limit(1);
        if(invR2.data && invR2.data.length>0) dbInvoice=invR2.data[0];
      }
    } catch(e){}
  }

  // Use DB invoice data when available
  var invNum=dbInvoice?dbInvoice.number:((isReceipt?'DP':isAdvance?'ZF':'KF')+'-'+new Date(b.start_date).getFullYear()+'-'+b.id.substr(-4).toUpperCase());
  var title=isReceipt?(t.paymentReceipt||'Daňový doklad k přijaté platbě'):isAdvance?t.invoiceAdvance:t.invoiceFinal;
  var issueDate=dbInvoice&&dbInvoice.issue_date?_docDate(dbInvoice.issue_date):_docDate(isAdvance?b.start_date:b.end_date);
  var dueDate=dbInvoice&&dbInvoice.due_date?_docDate(dbInvoice.due_date):_docDate(new Date(new Date(isAdvance?b.start_date:b.end_date).getTime()+14*86400000).toISOString());
  var amt=dbInvoice?Number(dbInvoice.total||0):(b.total_price||0);
  var subtotal=dbInvoice?Number(dbInvoice.subtotal||0):(b.total_price||0);
  var taxAmt=dbInvoice?Number(dbInvoice.tax_amount||0):0;
  var pName=p?p.full_name:'—';
  var pAddr=p?[p.street,p.city,p.zip,p.country].filter(Boolean).join(', '):'—';
  var pIco=p&&p.ico?p.ico:'';
  var pDic=p&&p.dic?p.dic:'';
  var vs=dbInvoice&&dbInvoice.variable_symbol?dbInvoice.variable_symbol:invNum;
  var invStatus=dbInvoice?dbInvoice.status:'';
  var statusHtml='';
  if(invStatus==='paid') statusHtml='<div style="color:#1a8a18;font-weight:800;font-size:12px;margin:6px 0;">✓ ZAPLACENO</div>';
  else if(invStatus==='issued') statusHtml='<div style="color:#b45309;font-weight:800;font-size:12px;margin:6px 0;">⏳ VYSTAVENO — ČEKÁ NA ÚHRADU</div>';

  // Build items from DB or fallback
  var itemsHtml='';
  if(dbInvoice&&dbInvoice.items&&Array.isArray(dbInvoice.items)){
    dbInvoice.items.forEach(function(it,i){
      // Section headers (── Původní/Nová rezervace ──) — render as spanning header row
      if(it.description && it.description.indexOf('──') === 0 && (it.unit_price||0) === 0){
        itemsHtml+='<tr><td colspan="4" style="font-weight:800;font-size:12px;padding:10px 0 4px;border-bottom:2px solid var(--green,#1a8a18);color:var(--gd,#1a1a2e);">'+it.description.replace(/──/g,'').trim()+'</td></tr>';
        return;
      }
      var priceColor = (it.unit_price||0) < 0 ? 'color:#b91c1c;' : '';
      itemsHtml+='<tr><td>'+(it.description||'')+'</td><td>'+(it.qty||1)+' '+(it.qty>1?t.days:'ks')+'</td>'+
        '<td style="'+priceColor+'">'+(it.unit_price||0).toLocaleString('cs-CZ')+' Kč</td>'+
        '<td style="'+priceColor+'">'+((it.unit_price||0)*(it.qty||1)).toLocaleString('cs-CZ')+' Kč</td></tr>';
    });
  } else {
    // Reconstruct base rental price: total_price is final (base+extras+delivery-discount)
    var baseRental=(b.total_price||0)-(b.extras_price||0)-(b.delivery_fee||0)+(b.discount_amount||0);
    var dailyRate=data.days>0?Math.round(baseRental/data.days):0;
    itemsHtml='<tr><td>'+t.rentalOf+' '+mn+'</td><td>'+data.days+' '+t.days+'</td>'+
      '<td>'+dailyRate.toLocaleString('cs-CZ')+' Kč</td>'+
      '<td>'+baseRental.toLocaleString('cs-CZ')+' Kč</td></tr>';
    if(b.extras_price>0){
      itemsHtml+='<tr><td>'+t.extras+'</td><td>1</td><td>'+b.extras_price.toLocaleString('cs-CZ')+' Kč</td>'+
        '<td>'+b.extras_price.toLocaleString('cs-CZ')+' Kč</td></tr>';
    }
    if(b.delivery_fee>0){
      itemsHtml+='<tr><td>'+(t.delivery||'Doručení')+'</td><td>1</td><td>'+b.delivery_fee.toLocaleString('cs-CZ')+' Kč</td>'+
        '<td>'+b.delivery_fee.toLocaleString('cs-CZ')+' Kč</td></tr>';
    }
    if(b.discount_amount>0){
      var discLabel=b.discount_code?('Sleva (kód: '+b.discount_code+')'):(t.discount||'Sleva / voucher');
      itemsHtml+='<tr><td>'+discLabel+'</td><td>1</td><td>-'+b.discount_amount.toLocaleString('cs-CZ')+' Kč</td>'+
        '<td>-'+b.discount_amount.toLocaleString('cs-CZ')+' Kč</td></tr>';
    }
  }

  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
    '<h2>'+title+'</h2><p>'+invNum+'</p></div><div class="doc-view-body">'+
    '<div class="inv-doc-header"><strong>'+title+'</strong> '+invNum+'</div>'+statusHtml+
    '<div class="doc-parties"><div class="doc-party"><strong>'+t.supplier+':</strong><br>'+
    COMPANY.name+'<br>'+COMPANY.sidlo+'<br>IČ: '+COMPANY.ic+'</div>'+
    '<div class="doc-party"><strong>'+t.customer+':</strong><br>'+pName+'<br>'+pAddr+
    (pIco?'<br>IČO: '+pIco:'')+(pDic?'<br>DIČ: '+pDic:'')+'</div></div>'+
    '<div class="inv-meta">'+
    '<div class="doc-field"><span class="doc-lbl">'+t.issueDate+':</span> '+issueDate+'</div>'+
    '<div class="doc-field"><span class="doc-lbl">'+t.dueDate+':</span> '+dueDate+'</div>'+
    '<div class="doc-field"><span class="doc-lbl">VS:</span> '+vs+'</div>'+
    '<div class="doc-field"><span class="doc-lbl">'+t.payMethod+':</span> '+t.card+'</div>'+
    '<div class="doc-field"><span class="doc-lbl">'+t.bankAccount+':</span> '+COMPANY.bank+'</div>'+
    '<div class="doc-field"><span class="doc-lbl">Č. rezervace:</span> '+rn+'</div></div>'+
    '<table class="inv-table"><thead><tr><th>'+t.item+'</th><th>'+t.qty+'</th><th>'+t.unitPrice+'</th><th>'+t.total+'</th></tr></thead>'+
    '<tbody>'+itemsHtml+'</tbody></table>';
  if(taxAmt>0){
    html+='<div class="inv-meta" style="margin-top:8px;">'+
      '<div class="doc-field"><span class="doc-lbl">Základ:</span> '+subtotal.toLocaleString('cs-CZ')+' Kč</div>'+
      '<div class="doc-field"><span class="doc-lbl">DPH 21%:</span> '+taxAmt.toLocaleString('cs-CZ')+' Kč</div></div>';
  }
  html+='<div class="inv-total"><span>'+t.totalToPay+':</span> <strong>'+amt.toLocaleString('cs-CZ')+' Kč</strong></div>'+
    '<p style="font-size:10px;color:var(--g400);margin-top:8px;">'+COMPANY.note+'</p>'+
    '<div style="display:flex;gap:8px;margin-top:14px;">'+
    '<button class="btn-out" onclick="emailDoc(\''+bookingId+'\',\''+type+'\')">📧 '+t.sendEmail+'</button>'+
    '<button class="btn-g" onclick="_downloadInvoiceHtml(\''+bookingId+'\',\''+invNum+'\')">⬇️ '+t.downloadPDF+'</button>'+
    '</div></div></div>';
  _openDocOverlay(html);
}

// Show invoice by ID only (no booking_id available — e.g. orphaned ZF from incomplete reservation)
async function showInvoiceById(invoiceId){
  if(!_isSupabaseReady()){showT('✗',_t('common').error,'Offline');return;}
  var t=_t('doc');
  try {
    var invR=await supabase.from('invoices').select('*').eq('id',invoiceId).single();
    var dbInvoice=invR.data;
    if(!dbInvoice){showT('✗',t.error||'Chyba','Faktura nenalezena');return;}
    var isReceipt=dbInvoice.type==='payment_receipt';
    var isAdvance=dbInvoice.type==='proforma'||dbInvoice.type==='advance'||dbInvoice.type==='shop_proforma';
    // If we have a booking_id, try to show with full booking context
    if(dbInvoice.booking_id){
      var bkData=await _getBookingDataAsync(dbInvoice.booking_id);
      if(bkData){
        var invType=isReceipt?'payment_receipt':isAdvance?'advance':'final';
        return showInvoice(dbInvoice.booking_id,invType,invoiceId);
      }
    }
    var p=await apiFetchProfile();
    var pName=p?p.full_name:'—';
    var pAddr=p?[p.street,p.city,p.zip,p.country].filter(Boolean).join(', '):'—';
    var invNum=dbInvoice.number||invoiceId.substr(-8).toUpperCase();
    var title=isReceipt?(t.paymentReceipt||'Doklad k platbě'):isAdvance?t.invoiceAdvance:t.invoiceFinal;
    var amt=Number(dbInvoice.total||0);
    var itemsHtml='';
    if(dbInvoice.items&&Array.isArray(dbInvoice.items)){
      dbInvoice.items.forEach(function(it){
        if(it.description&&it.description.indexOf('──')===0&&(it.unit_price||0)===0){
          itemsHtml+='<tr><td colspan="4" style="font-weight:800;font-size:12px;padding:10px 0 4px;border-bottom:2px solid var(--green,#1a8a18);">'+it.description.replace(/──/g,'').trim()+'</td></tr>';
          return;
        }
        itemsHtml+='<tr><td>'+(it.description||'')+'</td><td>'+(it.qty||1)+' ks</td>'+
          '<td>'+(it.unit_price||0).toLocaleString('cs-CZ')+' Kč</td>'+
          '<td>'+((it.unit_price||0)*(it.qty||1)).toLocaleString('cs-CZ')+' Kč</td></tr>';
      });
    }
    var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
      '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
      '<h2>'+title+'</h2><p>'+invNum+'</p></div><div class="doc-view-body">'+
      '<div class="inv-doc-header"><strong>'+title+'</strong> '+invNum+'</div>'+
      '<div class="doc-parties"><div class="doc-party"><strong>'+t.supplier+':</strong><br>'+
      COMPANY.name+'<br>'+COMPANY.sidlo+'<br>IČ: '+COMPANY.ic+'</div>'+
      '<div class="doc-party"><strong>'+t.customer+':</strong><br>'+pName+'<br>'+pAddr+'</div></div>'+
      '<div class="inv-meta">'+
      '<div class="doc-field"><span class="doc-lbl">'+t.issueDate+':</span> '+(dbInvoice.issue_date?_docDate(dbInvoice.issue_date):'—')+'</div>'+
      '<div class="doc-field"><span class="doc-lbl">'+t.dueDate+':</span> '+(dbInvoice.due_date?_docDate(dbInvoice.due_date):'—')+'</div>'+
      (dbInvoice.variable_symbol?'<div class="doc-field"><span class="doc-lbl">VS:</span> '+dbInvoice.variable_symbol+'</div>':'')+
      '</div>';
    if(itemsHtml) html+='<table class="inv-table"><thead><tr><th>'+t.item+'</th><th>'+t.qty+'</th><th>'+t.unitPrice+'</th><th>'+t.total+'</th></tr></thead><tbody>'+itemsHtml+'</tbody></table>';
    html+='<div class="inv-total"><span>'+t.totalToPay+':</span> <strong>'+amt.toLocaleString('cs-CZ')+' Kč</strong></div>'+
      '<p style="font-size:10px;color:var(--g400);margin-top:8px;">'+COMPANY.note+'</p>'+
      '</div></div>';
    _openDocOverlay(html);
  } catch(e){console.error('showInvoiceById:',e);showT('✗',_t('common').error,'Chyba');}
}

// Download invoice as HTML file generated from current view
async function _downloadInvoiceHtml(bookingId,invNum){
  // Get the currently displayed invoice HTML from overlay
  var ov=document.getElementById('doc-overlay');
  if(ov && ov.style.display!=='none'){
    var body=ov.querySelector('.doc-view-body');
    if(body){
      var htmlContent='<!DOCTYPE html><html><head><meta charset="utf-8">'+
        '<title>'+invNum+'</title>'+
        '<style>body{font-family:Arial,sans-serif;padding:20px;max-width:800px;margin:0 auto;}'+
        'table{width:100%;border-collapse:collapse;margin:12px 0;}th,td{border:1px solid #ddd;padding:8px;text-align:left;}'+
        'th{background:#f5f5f5;font-weight:700;}.doc-parties{display:flex;gap:20px;margin:12px 0;}'+
        '.doc-party{flex:1;padding:10px;background:#f9f9f9;border-radius:6px;font-size:13px;line-height:1.6;}'+
        '.doc-field{font-size:13px;margin:4px 0;}.doc-lbl{font-weight:700;color:#555;}'+
        '.inv-total{font-size:18px;font-weight:900;text-align:right;margin:16px 0;padding:12px;background:#f0fdf4;border-radius:8px;}</style></head>'+
        '<body>'+body.innerHTML.replace(/<button[^>]*>.*?<\/button>/gi,'')+'</body></html>';
      var blob=new Blob([htmlContent],{type:'text/html;charset=utf-8'});
      var url=URL.createObjectURL(blob);
      var a=document.createElement('a');a.href=url;
      a.download='faktura_'+invNum+'.html';
      document.body.appendChild(a);a.click();
      document.body.removeChild(a);URL.revokeObjectURL(url);
      showT('✓',_t('common').downloaded||'Staženo',invNum);
      return;
    }
  }
  showT('⚠️','PDF','Nejprve otevřete fakturu');
}

async function emailDoc(bookingId,type){
  var result=await apiSendDocumentEmail('doc-'+type+'-'+bookingId);
  if(result.success) showT('📧',_t('doc').emailSent,result.email);
  else showT('✗',_t('common').error,_t('common').failedSend);
}

// ===== OVERLAY & SIGNATURE CANVAS =====
function _openDocOverlay(html){
  var ov=document.getElementById('doc-overlay');
  if(!ov){
    ov=document.createElement('div');ov.id='doc-overlay';
    ov.style.cssText='position:fixed;top:0;left:0;right:0;bottom:0;z-index:9999;background:#fff;overflow-y:auto;';
    document.querySelector('.phone').appendChild(ov);
  }
  ov.innerHTML=html;ov.style.display='block';
}

function closeDocView(){
  var ov=document.getElementById('doc-overlay');
  if(ov) ov.style.display='none';
}
