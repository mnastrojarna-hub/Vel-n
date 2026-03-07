// ===== DOCUMENTS.JS – Contract/Invoice/Protocol generation & digital signature =====
// Auto-fills from booking + profile data, renders in-app, supports digital signature

var COMPANY={name:'MotoGo24 s.r.o.',ic:'12345678',sidlo:'Mezná 9, 393 01 Mezná',
  email:'info@motogo24.cz',tel:'+420 123 456 789',bank:'CZ65 0800 0000 0012 3456 7890',
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
    resNum:'#RES-'+new Date(b.start_date).getFullYear()+'-'+b.id.substr(-4).toUpperCase()};
}
function _getBookingData(bookingId){
  return null;
}

// ===== VOP (General Terms) =====
function showVOP(){
  var t=_t('doc');
  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
    '<h2>'+t.vopTitle+'</h2></div><div class="doc-view-body">'+
    '<h3>'+t.vopTitle+'</h3><p><strong>'+COMPANY.name+'</strong>, '+t.seat+': '+COMPANY.sidlo+', IČ: '+COMPANY.ic+'</p>'+
    '<h4>1. '+t.vopSubject+'</h4><p>'+t.vopSubjectText+'</p>'+
    '<h4>2. '+t.vopRental+'</h4><p>'+t.vopRentalText+'</p>'+
    '<h4>3. '+t.vopObligations+'</h4><p>'+t.vopObligationsText+'</p>'+
    '<h4>4. '+t.vopDeposit+'</h4><p>'+t.vopDepositText+'</p>'+
    '<h4>5. '+t.vopInsurance+'</h4><p>'+t.vopInsuranceText+'</p>'+
    '<h4>6. '+t.vopCancel+'</h4><p>'+t.vopCancelText+'</p>'+
    '<h4>7. '+t.vopFinal+'</h4><p>'+t.vopFinalText+'</p>'+
    '</div></div>';
  _openDocOverlay(html);
}

// ===== RENTAL CONTRACT =====
async function showRentalContract(bookingId){
  var data=await _getBookingDataAsync(bookingId);
  if(!data) data=_getBookingData(bookingId);
  if(!data){showT('✗',_t('common').error,_t('common').noData);return;}
  var t=_t('doc');var b=data.b,m=data.m,p=data.p,mn=data.motoName,rn=data.resNum;
  var pName=p?p.full_name:'—',pAddr=p?(p.street+', '+p.city+' '+p.zip):'—';
  var pLic=p?p.license_number:'—',pPhone=p?p.phone:'—',pEmail=p?p.email:'—';
  // Motorcycle details from DB for contract accuracy
  var mSpz=m?m.spz:'—',mVin=m?m.vin:'—';
  var isPaid=(b.payment_status==='paid');
  var statusLine=isPaid?'<div style="color:#1a8a18;font-weight:800;font-size:12px;margin:8px 0;">✓ ZAPLACENO</div>':'<div style="color:#b91c1c;font-weight:800;font-size:12px;margin:8px 0;">⏳ ČEKÁ NA PLATBU</div>';

  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
    '<h2>'+t.contractTitle+'</h2><p>'+rn+'</p></div><div class="doc-view-body">'+
    '<h3>'+t.contractTitle+'</h3>'+statusLine+
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
    '<h4>'+t.contractConditions+'</h4><p>'+t.contractConditionsText+'</p>'+
    '<div class="doc-sign-area" id="contract-sign-area">'+
    '<p style="font-size:11px;color:var(--g400);">'+t.signNote+'</p>'+
    '<canvas id="sign-canvas-contract" width="300" height="120" style="border:2px solid var(--g200);border-radius:8px;background:#fff;touch-action:none;"></canvas>'+
    '<div style="display:flex;gap:8px;margin-top:8px;">'+
    '<button class="btn-out" onclick="clearSignCanvas(\'contract\')">'+t.clearSign+'</button>'+
    '<button class="btn-g" onclick="signDocument(\'contract\',\''+bookingId+'\')">'+t.signBtn+'</button></div>'+
    '</div></div></div>';
  _openDocOverlay(html);
  setTimeout(function(){_initSignCanvas('contract');},100);
}

// ===== HANDOVER PROTOCOL =====
async function showDigitalProtocol(bookingId){
  if(!bookingId){
    // Try to find from current context
    var bks=await apiFetchMyBookings();
    if(bks.length>0) bookingId=bks[0].id;
  }
  var data=bookingId?(await _getBookingDataAsync(bookingId)||_getBookingData(bookingId)):null;
  var t=_t('doc');
  var mn=data?data.motoName:'Motorka',rn=data?data.resNum:'#RES-0000';
  var pName=data&&data.p?data.p.full_name:'—';
  var pickup=data?_docDate(data.b.start_date):'—';
  var returnD=data?_docDate(data.b.end_date):'—';

  var items=['Klíče (od motorky + od kufru)','Zelená karta','Malý technický průkaz',
    '2× reflexní vesta','Motolékárnička','Záznam o dopravní nehodě','Kukla (nová)',
    'Helma řidiče','Rukavice','Bunda','Kalhoty'];
  var checkHtml=items.map(function(it,i){
    return '<label style="display:flex;align-items:center;gap:8px;font-size:12px;font-weight:600;cursor:pointer;">'+
      '<input type="checkbox" class="proto-chk" style="accent-color:var(--green);width:15px;height:15px;"> '+it+'</label>';
  }).join('');

  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
    '<h2>'+t.protocolTitle+'</h2><p>'+rn+'</p></div><div class="doc-view-body">'+
    '<div class="doc-parties"><div class="doc-party"><strong>'+COMPANY.name+'</strong></div>'+
    '<div class="doc-party"><strong>'+pName+'</strong></div></div>'+
    '<div class="doc-field"><span class="doc-lbl">'+t.motorcycle+':</span> '+mn+'</div>'+
    '<div class="doc-field"><span class="doc-lbl">'+t.pickupDate+':</span> '+pickup+'</div>'+
    '<div class="doc-field"><span class="doc-lbl">'+t.returnDate+':</span> '+returnD+'</div>'+
    '<h4>'+t.protocolItems+'</h4>'+
    '<div style="display:flex;flex-direction:column;gap:7px;">'+checkHtml+'</div>'+
    '<h4 style="margin-top:14px;">'+t.protocolNotes+'</h4>'+
    '<textarea id="proto-notes" rows="3" style="width:100%;border:1.5px solid var(--g200);border-radius:8px;padding:8px;font-family:var(--font);font-size:12px;" placeholder="'+t.protocolNotesPlaceholder+'"></textarea>'+
    '<div class="doc-sign-area" id="protocol-sign-area">'+
    '<p style="font-size:11px;color:var(--g400);">'+t.signNote+'</p>'+
    '<canvas id="sign-canvas-protocol" width="300" height="120" style="border:2px solid var(--g200);border-radius:8px;background:#fff;touch-action:none;"></canvas>'+
    '<div style="display:flex;gap:8px;margin-top:8px;">'+
    '<button class="btn-out" onclick="clearSignCanvas(\'protocol\')">'+t.clearSign+'</button>'+
    '<button class="btn-g" onclick="signDocument(\'protocol\',\''+(bookingId||'')+'\')">'+t.signBtn+'</button></div>'+
    '</div></div></div>';
  _openDocOverlay(html);
  setTimeout(function(){_initSignCanvas('protocol');},100);
}

// ===== INVOICE GENERATION (Czech accounting standards) =====
async function showInvoice(bookingId,type){
  var data=await _getBookingDataAsync(bookingId);
  if(!data) data=_getBookingData(bookingId);
  if(!data){showT('✗',_t('common').error,_t('common').noData);return;}
  var t=_t('doc');var b=data.b,p=data.p,mn=data.motoName,rn=data.resNum;

  // Try to load real invoice from DB first
  var dbInvoice=null;
  if(_isSupabaseReady()){
    try {
      var invR=await supabase.from('invoices').select('*').eq('booking_id',bookingId).order('created_at',{ascending:false}).limit(1).single();
      if(invR.data) dbInvoice=invR.data;
    } catch(e){}
  }

  var isAdvance=(type==='advance');
  var invNum=dbInvoice?dbInvoice.number:((isAdvance?'ZF':'KF')+'-'+new Date(b.start_date).getFullYear()+'-'+b.id.substr(-4).toUpperCase());
  var title=isAdvance?t.invoiceAdvance:t.invoiceFinal;
  var issueDate=_docDate(isAdvance?b.start_date:b.end_date);
  var dueDate=_docDate(new Date(new Date(isAdvance?b.start_date:b.end_date).getTime()+14*86400000).toISOString());
  var amt=b.total_price||0;
  var pName=p?p.full_name:'—',pAddr=p?(p.street+', '+p.city+' '+p.zip):'—';

  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
    '<h2>'+title+'</h2><p>'+invNum+'</p></div><div class="doc-view-body">'+
    '<div class="inv-doc-header"><strong>'+title+'</strong> '+invNum+'</div>'+
    '<div class="doc-parties"><div class="doc-party"><strong>'+t.supplier+':</strong><br>'+
    COMPANY.name+'<br>'+COMPANY.sidlo+'<br>IČ: '+COMPANY.ic+'</div>'+
    '<div class="doc-party"><strong>'+t.customer+':</strong><br>'+pName+'<br>'+pAddr+'</div></div>'+
    '<div class="inv-meta">'+
    '<div class="doc-field"><span class="doc-lbl">'+t.issueDate+':</span> '+issueDate+'</div>'+
    '<div class="doc-field"><span class="doc-lbl">'+t.dueDate+':</span> '+dueDate+'</div>'+
    '<div class="doc-field"><span class="doc-lbl">'+t.payMethod+':</span> '+t.card+'</div>'+
    '<div class="doc-field"><span class="doc-lbl">'+t.bankAccount+':</span> '+COMPANY.bank+'</div></div>'+
    '<table class="inv-table"><thead><tr><th>'+t.item+'</th><th>'+t.qty+'</th><th>'+t.unitPrice+'</th><th>'+t.total+'</th></tr></thead>'+
    '<tbody><tr><td>'+t.rentalOf+' '+mn+'</td><td>'+data.days+' '+t.days+'</td>'+
    '<td>'+Math.round(amt/data.days).toLocaleString('cs-CZ')+' Kč</td>'+
    '<td>'+amt.toLocaleString('cs-CZ')+' Kč</td></tr>';
  if(b.extras_price>0){
    html+='<tr><td>'+t.extras+'</td><td>1</td><td>'+b.extras_price.toLocaleString('cs-CZ')+' Kč</td>'+
      '<td>'+b.extras_price.toLocaleString('cs-CZ')+' Kč</td></tr>';
    amt+=b.extras_price;
  }
  html+='</tbody></table>'+
    '<div class="inv-total"><span>'+t.totalToPay+':</span> <strong>'+amt.toLocaleString('cs-CZ')+' Kč</strong></div>'+
    '<p style="font-size:10px;color:var(--g400);margin-top:8px;">'+COMPANY.note+'</p>'+
    '<div style="display:flex;gap:8px;margin-top:14px;">'+
    '<button class="btn-out" onclick="emailDoc(\''+bookingId+'\',\''+type+'\')">📧 '+t.sendEmail+'</button>'+
    '<button class="btn-g" onclick="showT(\'⬇️\',\'PDF\',\''+invNum+'.pdf\')">⬇️ '+t.downloadPDF+'</button>'+
    '</div></div></div>';
  _openDocOverlay(html);
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

var _signCtx={};
function _initSignCanvas(id){
  var c=document.getElementById('sign-canvas-'+id);
  if(!c)return;
  var ctx=c.getContext('2d');
  ctx.lineWidth=2;ctx.lineCap='round';ctx.strokeStyle='#1a1a2e';
  _signCtx[id]={canvas:c,ctx:ctx,drawing:false};
  c.addEventListener('pointerdown',function(e){_signCtx[id].drawing=true;ctx.beginPath();ctx.moveTo(e.offsetX,e.offsetY);});
  c.addEventListener('pointermove',function(e){if(!_signCtx[id].drawing)return;ctx.lineTo(e.offsetX,e.offsetY);ctx.stroke();});
  c.addEventListener('pointerup',function(){_signCtx[id].drawing=false;});
}

function clearSignCanvas(id){
  var s=_signCtx[id];
  if(s) s.ctx.clearRect(0,0,s.canvas.width,s.canvas.height);
}

async function signDocument(type,bookingId){
  var s=_signCtx[type];
  if(!s){showT('✗',_t('common').error,_t('common').sigNotFound);return;}
  var blank=document.createElement('canvas');
  blank.width=s.canvas.width;blank.height=s.canvas.height;
  if(s.canvas.toDataURL()===blank.toDataURL()){
    showT('⚠️',_t('doc').signRequired,_t('doc').signFirst);return;
  }
  var sigData=s.canvas.toDataURL('image/png');
  if(bookingId) await apiUploadDocument(bookingId,sigData,type==='protocol'?'protocol':'contract');
  showT('✓',_t('doc').signed,_t('doc').savedOK);
  setTimeout(closeDocView,1200);
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
    '<div style="padding:10px 20px 0;"><div style="background:var(--gp);border-radius:var(--r);padding:13px;margin-bottom:10px;font-size:12px;color:var(--gd);line-height:1.6;">🔒 '+t.gdprNote+'</div></div>'+
    '<div style="padding:0 20px;">';

  // VOP – always show general link
  html+='<div class="bcard" style="margin:0 0 10px;cursor:pointer;" onclick="showVOP()">'+
    '<div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:var(--gp);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;">📜</div>'+
    '<div style="flex:1;"><div style="font-size:13px;font-weight:800;">'+t.vopTitle+'</div>'+
    '<div style="font-size:11px;color:var(--g400);margin-top:2px;">'+COMPANY.name+'</div></div></div></div>';

  // Per-booking VOP copies
  vops.forEach(function(d){
    html+='<div class="bcard" style="margin:0 0 10px;cursor:pointer;" onclick="showVOP()">'+
      '<div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:#e0f2fe;border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;">📜</div>'+
      '<div style="flex:1;"><div style="font-size:13px;font-weight:800;">VOP – '+(d.moto_name||'Rezervace')+'</div>'+
      '<div style="font-size:11px;color:var(--g400);margin-top:2px;">'+(d.res_num||'')+' · '+_docDate(d.date)+'</div></div></div></div>';
  });

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
  var invoices=docs.filter(function(d){return d.type==='invoice_advance'||d.type==='invoice_final';});

  if(invoices.length===0){
    wrap.innerHTML='<div style="text-align:center;padding:30px;color:var(--g400);">'+t.noInvoices+'</div>';
    return;
  }

  var years={};
  invoices.forEach(function(d){
    var y=new Date(d.date).getFullYear();
    if(!years[y])years[y]=[];
    years[y].push(d);
  });

  var html='';
  Object.keys(years).sort(function(a,b){return b-a;}).forEach(function(yr){
    html+='<div class="msec-t" style="padding:'+(html?'12':'0')+'px 0 8px;">'+yr+'</div>';
    years[yr].forEach(function(d){
      var icon=d.type==='invoice_advance'?'🧾':'💰';
      var label=d.type==='invoice_advance'?t.invoiceAdvance:t.invoiceFinal;
      var invType=d.type==='invoice_advance'?'advance':'final';
      var amt=d.amount?d.amount.toLocaleString('cs-CZ')+' Kč':'';
      html+='<div class="inv-item" onclick="showInvoice(\''+d.booking_id+'\',\''+invType+'\')">'+
        '<div class="inv-icon">'+icon+'</div>'+
        '<div class="inv-info"><div class="inv-name">'+d.moto_name+' · '+label+'</div>'+
        '<div class="inv-sub">'+d.res_num+' · '+_docDate(d.date)+'</div></div>'+
        '<div>'+(amt?'<div class="inv-amt">'+amt+'</div>':'')+
        '<div style="font-size:10px;color:var(--g400);text-align:right;margin-top:2px;">PDF ⬇️ · 📧</div></div></div>';
    });
  });
  wrap.innerHTML=html;
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
