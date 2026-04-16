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
