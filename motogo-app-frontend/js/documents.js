// ===== DOCUMENTS.JS – Contract/Invoice/Protocol generation & digital signature =====
// Auto-fills from booking + profile data, renders in-app, supports digital signature

var COMPANY={name:'Bc. Petra Semorádová',ic:'21874263',sidlo:'Mezná 9, 393 01 Mezná',
  email:'info@motogo24.cz',tel:'+420 774 256 271',bank:'670100-2225851630/6210',
  note:'Nejsme plátci DPH dle §6 zákona č. 235/2004 Sb.'};

function _docDate(iso){
  var d=new Date(iso);
  return d.getDate()+'.'+(d.getMonth()+1)+'.'+d.getFullYear();
}

async function _getBookingDataAsync(bookingId){
  var b=null,m=null,p=null;
  if(_isSupabaseReady()){
    try {
      var result=await supabase.from('bookings').select('*, motorcycles(*), profiles(*)').eq('id',bookingId).single();
      if(result.data){
        b=result.data;
        m=result.data.motorcycles||null;
        p=result.data.profiles||null;
      }
    } catch(e){}
  }
  if(!b) return null;
  if(!p) p=await apiFetchProfile();
  var days=Math.max(1,Math.round((new Date(b.end_date)-new Date(b.start_date))/86400000)+1);
  return {b:b,m:m,p:p,days:days,
    motoName:m?(m.model||m.name):'Motorka',
    resNum:'#'+b.id.substr(-8).toUpperCase()};
}
function _getBookingData(bookingId){
  return null;
}

// ===== VOP (General Terms) – fetch from Velín template if available =====
async function showVOP(){
  var t=_t('doc');
  var tpl = typeof apiFetchDocTemplate === 'function' ? await apiFetchDocTemplate('vop') : null;
  var bodyHtml = '';
  if(tpl && tpl.content_html){
    bodyHtml = tpl.content_html;
  } else {
    bodyHtml = '<h3>'+t.vopTitle+'</h3><p><strong>'+COMPANY.name+'</strong>, '+t.seat+': '+COMPANY.sidlo+', IČ: '+COMPANY.ic+'</p>'+
      '<h4>1. '+t.vopSubject+'</h4><p>'+t.vopSubjectText+'</p>'+
      '<h4>2. '+t.vopRental+'</h4><p>'+t.vopRentalText+'</p>'+
      '<h4>3. '+t.vopObligations+'</h4><p>'+t.vopObligationsText+'</p>'+
      '<h4>4. '+t.vopDeposit+'</h4><p>'+t.vopDepositText+'</p>'+
      '<h4>5. '+t.vopInsurance+'</h4><p>'+t.vopInsuranceText+'</p>'+
      '<h4>6. '+t.vopCancel+'</h4><p>'+t.vopCancelText+'</p>'+
      '<h4>7. '+t.vopFinal+'</h4><p>'+t.vopFinalText+'</p>';
  }
  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
    '<h2>'+t.vopTitle+'</h2></div><div class="doc-view-body">'+bodyHtml+'</div></div>';
  _openDocOverlay(html);
}

// ===== CONTRACT PREVIEW (no booking data – just the template) =====
async function showContractPreview(){
  var t=_t('doc');
  var tpl = typeof apiFetchDocTemplate === 'function' ? await apiFetchDocTemplate('contract') : null;
  var bodyHtml = '';
  if(tpl && tpl.content_html){
    bodyHtml = tpl.content_html;
    // Replace placeholders with generic labels
    bodyHtml = bodyHtml.replace(/\{\{[^}]+\}\}/g, '___').replace(/\{[^}]+\}/g, '___');
  } else {
    bodyHtml = '<h3>'+t.contractTitle+'</h3>'+
      '<div class="doc-parties"><div class="doc-party"><strong>'+t.lessor+':</strong><br>'+
      COMPANY.name+'<br>'+COMPANY.sidlo+'<br>IČ: '+COMPANY.ic+'<br>'+COMPANY.email+'</div>'+
      '<div class="doc-party"><strong>'+t.lessee+':</strong><br>(doplní se při rezervaci)</div></div>'+
      '<h4>'+t.contractSubject+'</h4><p>Pronajímatel přenechává nájemci k užívání motorové vozidlo dle rezervace.</p>'+
      '<h4>'+t.contractPrice+'</h4><p>Cena dle platného ceníku.</p>'+
      '<h4>'+t.contractConditions+'</h4><p>'+t.contractConditionsText+'</p>';
  }
  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
    '<h2>'+t.contractTitle+'</h2><p>Náhled vzorové smlouvy</p></div><div class="doc-view-body">'+bodyHtml+'</div></div>';
  _openDocOverlay(html);
}

// ===== GDPR – fetch from Velín template if available =====
async function showGDPR(){
  var t=_t('doc');
  var tpl = typeof apiFetchDocTemplate === 'function' ? await apiFetchDocTemplate('gdpr') : null;
  var bodyHtml = '';
  if(tpl && tpl.content_html){
    bodyHtml = tpl.content_html;
  } else {
    bodyHtml = '<h3>Zpracování osobních údajů (GDPR)</h3>'+
      '<p><strong>Správce:</strong> '+COMPANY.name+', '+COMPANY.sidlo+', IČ: '+COMPANY.ic+'</p>'+
      '<h4>1. Účel zpracování</h4><p>Osobní údaje jsou zpracovávány za účelem plnění smlouvy o pronájmu motorového vozidla, vystavení daňových dokladů a zajištění bezpečnosti provozu.</p>'+
      '<h4>2. Rozsah údajů</h4><p>Jméno, příjmení, datum narození, adresa, e-mail, telefon, číslo řidičského průkazu, platnost ŘP, kategorie ŘP.</p>'+
      '<h4>3. Právní základ</h4><p>Plnění smlouvy (čl. 6 odst. 1 písm. b) GDPR), plnění právní povinnosti (čl. 6 odst. 1 písm. c) GDPR), oprávněný zájem správce (čl. 6 odst. 1 písm. f) GDPR).</p>'+
      '<h4>4. Doba uchování</h4><p>Po dobu trvání smluvního vztahu a dále po dobu stanovenou právními předpisy (zejména daňové a účetní předpisy).</p>'+
      '<h4>5. Práva subjektu údajů</h4><p>Máte právo na přístup k údajům, opravu, výmaz, omezení zpracování, přenositelnost a právo vznést námitku. Kontakt: '+COMPANY.email+'</p>'+
      '<h4>6. Dozorový úřad</h4><p>Úřad pro ochranu osobních údajů, Pplk. Sochora 27, 170 00 Praha 7, www.uoou.cz</p>';
  }
  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+(t.back||'Zpět')+'</div></div>'+
    '<h2>Zpracování osobních údajů</h2></div><div class="doc-view-body">'+bodyHtml+'</div></div>';
  _openDocOverlay(html);
}

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
  var data=await _getBookingDataAsync(bookingId);
  if(!data) data=_getBookingData(bookingId);
  if(!data){showT('✗',_t('common').error,_t('common').noData);return;}
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
      // Fallback: any invoice for this booking
      if(!dbInvoice){
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


// ===== ENHANCED renderContracts with document viewing =====
async function renderContractsPage(){
  var wrap=document.getElementById('s-contracts');
  if(!wrap)return;
  var t=_t('doc');
  var docs=await apiFetchDocuments();
  var contracts=docs.filter(function(d){return d.type==='contract';});
  var protocols=docs.filter(function(d){return d.type==='protocol';});
  var vops=docs.filter(function(d){return d.type==='vop';});

  var html='<div class="topbar"><div class="back-row" onclick="histBack()"><div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
    '<h2>'+t.docsTitle+'</h2><p>'+t.docsSubtitle+'</p></div>'+
    '<div style="padding:10px 20px 0;">'+
    '<div style="background:var(--gp);border-radius:var(--r);padding:13px;margin-bottom:10px;font-size:12px;color:var(--gd);line-height:1.6;">🔒 '+t.gdprNote+'</div></div>'+
    '<div style="padding:0 20px;">';

  // VOP – show only once (general link, no per-booking duplicates)
  html+='<div class="bcard" style="margin:0 0 10px;cursor:pointer;" onclick="showVOP()">'+
    '<div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:var(--gp);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;">📜</div>'+
    '<div style="flex:1;"><div style="font-size:13px;font-weight:800;">'+t.vopTitle+'</div>'+
    '<div style="font-size:11px;color:var(--g400);margin-top:2px;">'+COMPANY.name+'</div></div></div></div>';

  // Contracts
  contracts.forEach(function(d){
    html+='<div class="bcard" style="margin:0 0 10px;cursor:pointer;" onclick="showRentalContract(\''+d.booking_id+'\')">'+
      '<div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:var(--gp);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;">📋</div>'+
      '<div style="flex:1;"><div style="font-size:13px;font-weight:800;">'+(t.contractLabel||'Smlouva')+' – '+(d.moto_name||'')+'</div>'+
      '<div style="font-size:11px;color:var(--g400);margin-top:2px;">'+(d.res_num||'')+' · '+_docDate(d.date)+'</div></div></div></div>';
  });

  // Protocols
  protocols.forEach(function(d){
    html+='<div class="bcard" style="margin:0 0 10px;cursor:pointer;" onclick="showDigitalProtocol(\''+d.booking_id+'\')">'+
      '<div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:#fef3c7;border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;">📋</div>'+
      '<div style="flex:1;"><div style="font-size:13px;font-weight:800;">'+(t.protocolLabel||'Předávací protokol')+' – '+(d.moto_name||'')+'</div>'+
      '<div style="font-size:11px;color:var(--g400);margin-top:2px;">'+(d.res_num||'')+' · '+_docDate(d.date)+'</div></div></div></div>';
  });

  if(contracts.length===0 && protocols.length===0 && vops.length===0){
    html+='<div style="text-align:center;padding:20px;color:var(--g400);font-size:12px;">Zatím žádné dokumenty. Dokumenty se automaticky vygenerují po zaplacení rezervace.</div>';
  }

  html+='</div>';
  wrap.innerHTML=html;
}

// Enhanced invoices page with clickable items
async function renderInvoicesPage(){
  var wrap=document.getElementById('invoices-list');
  if(!wrap)return;
  var t=_t('doc');
  var docs=await apiFetchDocuments();
  var invoices=docs.filter(function(d){return d.type==='invoice_advance'||d.type==='invoice_final'||d.type==='invoice_shop'||d.type==='payment_receipt'||d.type==='invoice';});

  var diagHtml='';

  if(invoices.length===0){
    wrap.innerHTML=diagHtml+'<div style="text-align:center;padding:30px;color:var(--g400);">'+t.noInvoices+'</div>';
    return;
  }

  var years={};
  invoices.forEach(function(d){
    var y=new Date(d.date).getFullYear();
    if(!years[y])years[y]=[];
    years[y].push(d);
  });

  var html=diagHtml;
  Object.keys(years).sort(function(a,b){return b-a;}).forEach(function(yr){
    html+='<div class="msec-t" style="padding:'+(html?'12':'0')+'px 0 8px;">'+yr+'</div>';
    years[yr].forEach(function(d){
      var isShop=(d.type==='invoice_shop');
      var isReceipt=(d.type==='payment_receipt');
      var icon=isShop?'🛒':isReceipt?'✅':(d.type==='invoice_advance'?'🧾':'💰');
      // Distinguish edit invoices from original ones
      var inv = d._invoice || null;
      var isEdit = inv && inv.source === 'edit';
      var label=isShop?(t.shopInvoice||'Faktura – Shop'):isReceipt?(t.paymentReceipt||'Doklad k platbě'):(d.type==='invoice_advance'?t.invoiceAdvance:t.invoiceFinal);
      if(isEdit) label = (isReceipt?'Doklad k platbě – úprava':'Zálohová faktura – úprava');
      var invType=isReceipt?'payment_receipt':(d.type==='invoice_advance'?'advance':'final');
      var amt=d.amount?d.amount.toLocaleString('cs-CZ')+' Kč':'';
      var itemName=isShop?(d.shop_items||'Shop'):(d.moto_name||'');
      var invId = (inv && inv.id) ? inv.id : d.id;
      var onclick=isShop?'showShopOrderDetail(\''+d.id+'\')':'showInvoice(\''+d.booking_id+'\',\''+invType+'\',\''+(invId||'')+'\')';
      html+='<div class="inv-item" onclick="'+onclick+'">'+
        '<div class="inv-icon">'+icon+'</div>'+
        '<div class="inv-info"><div class="inv-name">'+itemName+' · '+label+'</div>'+
        '<div class="inv-sub">'+(inv&&inv.number?inv.number+' · ':'')+d.res_num+' · '+_docDate(d.date)+'</div></div>'+
        '<div>'+(amt?'<div class="inv-amt">'+amt+'</div>':'')+
        '<div style="font-size:10px;color:var(--g400);text-align:right;margin-top:2px;">PDF ⬇️ · 📧</div></div></div>';
    });
  });
  wrap.innerHTML=html;
}

// ===== SHOP ORDER DETAIL (invoice view for shop purchases) =====
async function showShopOrderDetail(orderId){
  if(!_isSupabaseReady()){showT('✗',_t('common').error,'Offline');return;}
  try {
    var r=await supabase.from('shop_orders').select('*, shop_order_items(*)').eq('id',orderId).single();
    if(!r.data){
      // Fallback: orderId might be a document or invoice ID — try to find the real order
      var inv=await supabase.from('invoices').select('order_id').eq('id',orderId).single();
      if(inv.data && inv.data.order_id){
        r=await supabase.from('shop_orders').select('*, shop_order_items(*)').eq('id',inv.data.order_id).single();
      }
      if(!r.data){
        var doc=await supabase.from('documents').select('booking_id').eq('id',orderId).single();
        if(doc.data && doc.data.booking_id){
          inv=await supabase.from('invoices').select('order_id').eq('booking_id',doc.data.booking_id).eq('type','shop_final').single();
          if(inv.data && inv.data.order_id){
            r=await supabase.from('shop_orders').select('*, shop_order_items(*)').eq('id',inv.data.order_id).single();
          }
        }
      }
    }
    if(!r.data){showT('✗',_t('common').error,'Objednávka nenalezena');return;}
    var o=r.data,t=_t('doc');
    var p=await apiFetchProfile();
    var pName=p?p.full_name:'—';
    var pAddr=p?[p.street,p.city,p.zip].filter(Boolean).join(', '):'—';
    var itemsHtml=(o.shop_order_items||[]).map(function(it){
      return '<tr><td>'+(it.product_name||'')+'</td><td>'+(it.quantity||1)+' ks</td>'+
        '<td>'+(it.unit_price||0).toLocaleString('cs-CZ')+' Kč</td>'+
        '<td>'+(it.total_price||0).toLocaleString('cs-CZ')+' Kč</td></tr>';
    }).join('');
    var invNum='OBJ-'+(o.order_number||o.id.substr(-6).toUpperCase());
    var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
      '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
      '<h2>'+(t.shopInvoice||'Faktura – Shop')+'</h2><p>'+invNum+'</p></div><div class="doc-view-body">'+
      '<div class="inv-doc-header"><strong>'+(t.shopInvoice||'Faktura – Shop')+'</strong> '+invNum+'</div>'+
      '<div class="doc-parties"><div class="doc-party"><strong>'+t.supplier+':</strong><br>'+
      COMPANY.name+'<br>'+COMPANY.sidlo+'<br>IČ: '+COMPANY.ic+'</div>'+
      '<div class="doc-party"><strong>'+t.customer+':</strong><br>'+pName+'<br>'+pAddr+'</div></div>'+
      '<div class="inv-meta">'+
      '<div class="doc-field"><span class="doc-lbl">'+t.issueDate+':</span> '+_docDate(o.created_at)+'</div>'+
      '<div class="doc-field"><span class="doc-lbl">Stav:</span> '+(o.payment_status==='paid'?'✓ Zaplaceno':'⏳ Čeká na platbu')+'</div>';
    if(o.shipping_address) html+='<div class="doc-field"><span class="doc-lbl">Doručení:</span> '+o.shipping_address+'</div>';
    html+='</div><table class="inv-table"><thead><tr><th>'+t.item+'</th><th>'+t.qty+'</th><th>'+t.unitPrice+'</th><th>'+t.total+'</th></tr></thead>'+
      '<tbody>'+itemsHtml+'</tbody></table>';
    if(o.shipping_cost>0) html+='<div class="doc-field" style="margin:6px 0;"><span class="doc-lbl">Doprava:</span> '+o.shipping_cost.toLocaleString('cs-CZ')+' Kč</div>';
    if(o.discount>0) html+='<div class="doc-field" style="margin:6px 0;"><span class="doc-lbl">Sleva:</span> -'+o.discount.toLocaleString('cs-CZ')+' Kč</div>';
    html+='<div class="inv-total"><span>'+t.totalToPay+':</span> <strong>'+(o.total||0).toLocaleString('cs-CZ')+' Kč</strong></div>'+
      '<p style="font-size:10px;color:var(--g400);margin-top:8px;">'+COMPANY.note+'</p>'+
      '</div></div>';
    _openDocOverlay(html);
  } catch(e){console.error('showShopOrderDetail:',e);showT('✗',_t('common').error,'Chyba');}
}

// ===== DOWNLOAD MANUAL =====
function downloadManual(m){
  // Pokud je manual_url z Velínu (PDF z Supabase storage), otevři přímo
  if(m.manual && (m.manual.startsWith('http://') || m.manual.startsWith('https://'))){
    showT('📖','Otevírám PDF…',m.name);
    if(window.cordova && window.cordova.InAppBrowser){
      window.cordova.InAppBrowser.open(m.manual, '_system');
    } else {
      window.open(m.manual, '_blank');
    }
    return;
  }
  showT('⬇️',_t('common').downloading,'...');
  var sp=(m.specs||[]).map(function(s){return s.l+': '+s.v;}).join('\n');
  var ft=(m.feats||[]).join('\n- ');
  var txt='====================================\n'+
    '  NÁVOD K OBSLUZE – '+m.name+'\n'+
    '  MotoGo24 s.r.o.\n'+
    '====================================\n\n'+
    '1. ZÁKLADNÍ INFORMACE\n'+
    '  Model: '+m.name+'\n'+
    '  Umístění: '+(m.loc||'')+'\n'+
    '  Kategorie ŘP: '+(m.rp||'')+'\n'+
    '  Výkon: '+(m.vykon||'')+' kW\n\n'+
    '2. POPIS\n  '+(m.desc||'')+'\n\n'+
    '3. TECHNICKÉ SPECIFIKACE\n'+sp+'\n\n'+
    '4. VLASTNOSTI A VYUŽITÍ\n- '+ft+'\n\n'+
    '5. PŘED JÍZDOU\n'+
    '  - Zkontrolujte hladinu oleje a brzdové kapaliny\n'+
    '  - Ověřte tlak v pneumatikách (dle štítku na rámu)\n'+
    '  - Zkontrolujte funkčnost světel a směrovek\n'+
    '  - Nastavte zrcátka a páčky dle sebe\n'+
    '  - Vždy noste homologovanou přilbu a rukavice\n\n'+
    '6. OVLÁDACÍ PRVKY\n'+
    '  Levá rukojeť: Spojka · Přepínač světel · Směrovky\n'+
    '  Pravá rukojeť: Přední brzda · Plyn · Startér\n'+
    '  Levá noha: Řazení (1-N-2-3-4-5-6)\n'+
    '  Pravá noha: Zadní brzda\n\n'+
    '7. PO JÍZDĚ\n'+
    '  - Zamkněte řídítka\n'+
    '  - Klíče odevzdejte na pobočce\n'+
    '  - Nahlaste případné závady\n\n'+
    '8. NOUZOVÉ KONTAKTY\n'+
    '  MotoGo24: +420 774 256 271 (24/7)\n'+
    '  E-mail: info@motogo24.cz\n\n'+
    '© 2026 MotoGo24 s.r.o. · Mezná 9\n';
  var blob=new Blob([txt],{type:'text/plain;charset=utf-8'});
  var url=URL.createObjectURL(blob);
  var a=document.createElement('a');
  a.href=url;a.download=(m.manual||m.name+'_Navod')+'.txt';
  document.body.appendChild(a);a.click();
  document.body.removeChild(a);URL.revokeObjectURL(url);
  setTimeout(function(){showT('✓',_t('common').downloaded,m.manual||m.name);},600);
}

// ===== GENERIC DOC DOWNLOAD =====
async function generateDocDownload(title,filename){
  showT('⬇️',_t('common').downloading,title);
  var profile=typeof apiFetchProfile==='function'?await apiFetchProfile():{};
  var now=new Date().toLocaleString('cs-CZ');
  var txt='====================================\n'+
    '  '+title.toUpperCase()+'\n'+
    '  MotoGo24 s.r.o.\n'+
    '====================================\n\n'+
    'Datum: '+now+'\n'+
    'Klient: '+(profile.full_name||'—')+'\n'+
    'E-mail: '+(profile.email||'—')+'\n'+
    'Telefon: '+(profile.phone||'—')+'\n\n'+
    'Dodavatel: '+COMPANY.name+'\n'+
    'IČ: '+COMPANY.ic+'\n'+
    'Sídlo: '+COMPANY.sidlo+'\n'+
    'Banka: '+COMPANY.bank+'\n\n'+
    COMPANY.note+'\n\n'+
    '====================================\n'+
    '  Dokument vygenerován aplikací MotoGo24\n'+
    '====================================\n';
  var blob=new Blob([txt],{type:'text/plain;charset=utf-8'});
  var url=URL.createObjectURL(blob);
  var a=document.createElement('a');
  a.href=url;a.download=filename;
  document.body.appendChild(a);a.click();
  document.body.removeChild(a);URL.revokeObjectURL(url);
  setTimeout(function(){showT('✓',_t('common').downloaded,title);},600);
}

// ===== SEND DOC VIA EMAIL =====
async function sendDocEmail(title){
  var profile=typeof apiFetchProfile==='function'?await apiFetchProfile():{};
  var email=profile.email||'jan.novak@email.cz';
  showT('📧',_t('common').sending,title);
  setTimeout(function(){showT('✓',_t('common').sent,_t('doc').emailSent+' '+email);},1200);
}
