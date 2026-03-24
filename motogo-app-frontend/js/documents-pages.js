// ===== DOCUMENTS-PAGES.JS – Contracts page, invoices page, shop orders, manual viewer, search =====
// Split from original documents.js. See also: documents.js, documents-booking.js

// ===== ENHANCED renderContracts with document viewing + filter & sort =====
var _conAllDocs=null;
async function renderContractsPage(){
  var wrap=document.getElementById('s-contracts');
  if(!wrap)return;
  var t=_t('doc');
  var loadEl=document.getElementById('contracts-loading');

  // Fetch only once, reuse on filter/sort change
  if(!_conAllDocs){
    var docs=await apiFetchDocuments();
    _conAllDocs=[];
    // Add VOP as a virtual entry (always present)
    _conAllDocs.push({type:'vop',date:new Date().toISOString(),moto_name:'',res_num:'',booking_id:null,_isVop:true});
    docs.forEach(function(d){
      if(d.type==='contract'||d.type==='protocol'||d.type==='vop') _conAllDocs.push(d);
    });
  }
  if(loadEl) loadEl.style.display='none';

  var items=_conAllDocs.slice();

  // Apply type filter
  var typeF=(document.getElementById('con-type-filter')||{}).value||'';
  if(typeF) items=items.filter(function(d){return d.type===typeF;});

  // Apply sort
  var sortV=(document.getElementById('con-sort')||{}).value||'date_desc';
  var asc=sortV==='date_asc';
  items.sort(function(a,b){var da=new Date(a.date||0),db=new Date(b.date||0);return asc?da-db:db-da;});

  var html='<div style="padding:10px 20px 0;">'+
    '<div style="background:var(--gp);border-radius:var(--r);padding:13px;margin-bottom:10px;font-size:12px;color:var(--gd);line-height:1.6;">🔒 '+t.gdprNote+'</div></div>'+
    '<div style="padding:0 20px;">';

  if(items.length===0){
    html+='<div style="text-align:center;padding:20px;color:var(--g400);font-size:12px;">Žádné dokumenty odpovídající filtru.</div>';
  }

  items.forEach(function(d){
    if(d._isVop){
      html+='<div class="bcard" style="margin:0 0 10px;cursor:pointer;" onclick="showVOP()">'+
        '<div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:var(--gp);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;">📜</div>'+
        '<div style="flex:1;"><div style="font-size:13px;font-weight:800;">'+t.vopTitle+'</div>'+
        '<div style="font-size:11px;color:var(--g400);margin-top:2px;">'+COMPANY.name+'</div></div></div></div>';
    } else if(d.type==='contract'){
      html+='<div class="bcard" style="margin:0 0 10px;cursor:pointer;" onclick="showRentalContract(\''+d.booking_id+'\')">'+
        '<div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:var(--gp);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;">📋</div>'+
        '<div style="flex:1;"><div style="font-size:13px;font-weight:800;">'+(t.contractLabel||'Smlouva')+' – '+(d.moto_name||'')+'</div>'+
        '<div style="font-size:11px;color:var(--g400);margin-top:2px;">'+(d.res_num||'')+' · '+_docDate(d.date)+'</div></div></div></div>';
    } else if(d.type==='protocol'){
      html+='<div class="bcard" style="margin:0 0 10px;cursor:pointer;" onclick="showDigitalProtocol(\''+d.booking_id+'\')">'+
        '<div style="display:flex;align-items:center;gap:12px;"><div style="width:40px;height:40px;background:#fef3c7;border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;">📋</div>'+
        '<div style="flex:1;"><div style="font-size:13px;font-weight:800;">'+(t.protocolLabel||'Předávací protokol')+' – '+(d.moto_name||'')+'</div>'+
        '<div style="font-size:11px;color:var(--g400);margin-top:2px;">'+(d.res_num||'')+' · '+_docDate(d.date)+'</div></div></div></div>';
    }
  });

  html+='</div>';
  var contentEl=document.getElementById('contracts-content');
  if(contentEl) contentEl.innerHTML=html;
  else wrap.innerHTML=html;
}
// Reset cached contracts data on screen entry
function _conResetCache(){_conAllDocs=null;}

// Enhanced invoices page with clickable items + filter & sort
var _invAllDocs=null;
async function renderInvoicesPage(){
  var wrap=document.getElementById('invoices-list');
  if(!wrap)return;
  var t=_t('doc');
  // Fetch only once, reuse on filter/sort change
  if(!_invAllDocs){
    var docs=await apiFetchDocuments();
    _invAllDocs=docs.filter(function(d){return d.type==='invoice_advance'||d.type==='invoice_final'||d.type==='invoice_shop'||d.type==='payment_receipt'||d.type==='invoice';});
  }
  var invoices=_invAllDocs.slice();

  // Apply type filter
  var typeF=(document.getElementById('inv-type-filter')||{}).value||'';
  if(typeF) invoices=invoices.filter(function(d){return d.type===typeF;});

  // Apply sort
  var sortV=(document.getElementById('inv-sort')||{}).value||'date_desc';
  var asc=sortV==='date_asc';
  invoices.sort(function(a,b){var da=new Date(a.date||0),db=new Date(b.date||0);return asc?da-db:db-da;});

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

  var sortedYears=Object.keys(years).sort(function(a,b){return asc?a-b:b-a;});
  var html='';
  sortedYears.forEach(function(yr){
    html+='<div class="msec-t" style="padding:'+(html?'12':'0')+'px 0 8px;">'+yr+'</div>';
    years[yr].forEach(function(d){
      var isShop=(d.type==='invoice_shop');
      var isReceipt=(d.type==='payment_receipt');
      var icon=isShop?'🛒':isReceipt?'✅':(d.type==='invoice_advance'?'🧾':'💰');
      var inv = d._invoice || null;
      var isEdit = inv && inv.source === 'edit';
      var label=isShop?(t.shopInvoice||'Faktura – Shop'):isReceipt?(t.paymentReceipt||'Doklad k platbě'):(d.type==='invoice_advance'?t.invoiceAdvance:t.invoiceFinal);
      if(isEdit) label = (isReceipt?'Doklad k platbě – úprava':'Zálohová faktura – úprava');
      var invType=isReceipt?'payment_receipt':(d.type==='invoice_advance'?'advance':'final');
      var amt=d.amount?d.amount.toLocaleString('cs-CZ')+' Kč':'';
      var itemName=isShop?(d.shop_items||'Shop'):(d.moto_name||'');
      var invId = (inv && inv.id) ? inv.id : d.id;
      var onclick=isShop?'showShopOrderDetail(\''+d.id+'\')':
        (d.booking_id?'showInvoice(\''+d.booking_id+'\',\''+invType+'\',\''+(invId||'')+'\')':'showInvoiceById(\''+(invId||d.id)+'\')');
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
// Reset cached invoice data on screen entry
function _invResetCache(){_invAllDocs=null;}

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
    if(typeof _openExternalUrl === 'function'){ _openExternalUrl(m.manual); }
    else { window.open(m.manual, '_blank'); }
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

// ===== VIEW MANUAL (in-app overlay) =====
function _buildManualHtml(m){
  var sp=(m.specs||[]).map(function(s){return '<tr><td style="padding:4px 10px 4px 0;font-weight:600;color:var(--g600);white-space:nowrap;">'+s.l+'</td><td style="padding:4px 0;">'+s.v+'</td></tr>';}).join('');
  var ft=(m.feats||[]).map(function(f){return '<li style="margin-bottom:4px;">'+f+'</li>';}).join('');
  return '<div class="manual-content" style="padding:0 20px 20px;font-size:13px;line-height:1.8;color:var(--black);">'+
    '<h2 style="font-size:16px;margin:0 0 4px;">'+m.name+'</h2>'+
    '<div style="font-size:11px;color:var(--g400);margin-bottom:14px;">MotoGo24 · Návod k obsluze</div>'+
    '<h3 style="font-size:13px;font-weight:800;color:var(--gd);margin:14px 0 6px;">1. Základní informace</h3>'+
    '<table style="font-size:12px;border-collapse:collapse;">'+
    '<tr><td style="padding:4px 10px 4px 0;font-weight:600;">Model</td><td>'+m.name+'</td></tr>'+
    '<tr><td style="padding:4px 10px 4px 0;font-weight:600;">Umístění</td><td>'+(m.loc||'—')+'</td></tr>'+
    '<tr><td style="padding:4px 10px 4px 0;font-weight:600;">Kategorie ŘP</td><td>'+(m.rp||'—')+'</td></tr>'+
    '<tr><td style="padding:4px 10px 4px 0;font-weight:600;">Výkon</td><td>'+(m.vykon||'—')+' kW</td></tr>'+
    '</table>'+
    '<h3 style="font-size:13px;font-weight:800;color:var(--gd);margin:14px 0 6px;">2. Popis</h3>'+
    '<p style="margin:0;">'+(m.desc||'')+'</p>'+
    '<h3 style="font-size:13px;font-weight:800;color:var(--gd);margin:14px 0 6px;">3. Technické specifikace</h3>'+
    '<table style="font-size:12px;border-collapse:collapse;">'+sp+'</table>'+
    '<h3 style="font-size:13px;font-weight:800;color:var(--gd);margin:14px 0 6px;">4. Vlastnosti a využití</h3>'+
    '<ul style="margin:0;padding-left:18px;font-size:12px;">'+ft+'</ul>'+
    '<h3 style="font-size:13px;font-weight:800;color:var(--gd);margin:14px 0 6px;">5. Před jízdou</h3>'+
    '<ul style="margin:0;padding-left:18px;font-size:12px;">'+
    '<li>Zkontrolujte hladinu oleje a brzdové kapaliny</li>'+
    '<li>Ověřte tlak v pneumatikách (dle štítku na rámu)</li>'+
    '<li>Zkontrolujte funkčnost světel a směrovek</li>'+
    '<li>Nastavte zrcátka a páčky dle sebe</li>'+
    '<li>Vždy noste homologovanou přilbu a rukavice</li></ul>'+
    '<h3 style="font-size:13px;font-weight:800;color:var(--gd);margin:14px 0 6px;">6. Ovládací prvky</h3>'+
    '<table style="font-size:12px;border-collapse:collapse;">'+
    '<tr><td style="padding:4px 10px 4px 0;font-weight:600;">Levá rukojeť</td><td>Spojka · Přepínač světel · Směrovky</td></tr>'+
    '<tr><td style="padding:4px 10px 4px 0;font-weight:600;">Pravá rukojeť</td><td>Přední brzda · Plyn · Startér</td></tr>'+
    '<tr><td style="padding:4px 10px 4px 0;font-weight:600;">Levá noha</td><td>Řazení (1-N-2-3-4-5-6)</td></tr>'+
    '<tr><td style="padding:4px 10px 4px 0;font-weight:600;">Pravá noha</td><td>Zadní brzda</td></tr></table>'+
    '<h3 style="font-size:13px;font-weight:800;color:var(--gd);margin:14px 0 6px;">7. Po jízdě</h3>'+
    '<ul style="margin:0;padding-left:18px;font-size:12px;">'+
    '<li>Zamkněte řídítka</li>'+
    '<li>Klíče odevzdejte na pobočce</li>'+
    '<li>Nahlaste případné závady</li></ul>'+
    '<h3 style="font-size:13px;font-weight:800;color:var(--gd);margin:14px 0 6px;">8. Nouzové kontakty</h3>'+
    '<p style="margin:0;font-size:12px;">MotoGo24: +420 774 256 271 (24/7)<br>E-mail: info@motogo24.cz</p>'+
    '<div style="margin-top:20px;font-size:10px;color:var(--g400);text-align:center;">© 2026 MotoGo24 · Mezná 9</div>'+
    '</div>';
}

function viewManual(m){
  // PDF URL — open externally
  if(m.manual && (m.manual.startsWith('http://') || m.manual.startsWith('https://'))){
    if(typeof _openExternalUrl === 'function'){ _openExternalUrl(m.manual); }
    else { window.open(m.manual, '_blank'); }
    return;
  }
  var body=_buildManualHtml(m);
  var html='<div style="position:sticky;top:0;z-index:10;background:#fff;padding:14px 20px;border-bottom:1px solid var(--g200);display:flex;align-items:center;justify-content:space-between;">'+
    '<div style="font-size:15px;font-weight:800;">📖 '+m.name+'</div>'+
    '<button onclick="closeDocView()" style="background:none;border:none;font-size:22px;cursor:pointer;padding:4px;">✕</button></div>'+
    body;
  _openDocOverlay(html);
}

function searchManual(m){
  // PDF URL — can't search locally, open externally
  if(m.manual && (m.manual.startsWith('http://') || m.manual.startsWith('https://'))){
    if(typeof _openExternalUrl === 'function'){ _openExternalUrl(m.manual); }
    else { window.open(m.manual, '_blank'); }
    return;
  }
  var body=_buildManualHtml(m);
  var html='<div style="position:sticky;top:0;z-index:10;background:#fff;padding:10px 20px;border-bottom:1px solid var(--g200);">'+
    '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px;">'+
    '<div style="font-size:15px;font-weight:800;">🔍 '+m.name+'</div>'+
    '<button onclick="closeDocView()" style="background:none;border:none;font-size:22px;cursor:pointer;padding:4px;">✕</button></div>'+
    '<div style="display:flex;gap:8px;align-items:center;">'+
    '<input id="manual-search-input" type="text" placeholder="Hledat v návodu…" style="flex:1;padding:9px 12px;border:2px solid var(--g200);border-radius:var(--rsm);font-family:var(--font);font-size:13px;outline:none;" oninput="_doManualSearch()">'+
    '<div id="manual-search-count" style="font-size:11px;color:var(--g400);white-space:nowrap;min-width:40px;text-align:right;"></div>'+
    '</div></div>'+
    '<div id="manual-search-body">'+body+'</div>';
  _openDocOverlay(html);
  setTimeout(function(){var inp=document.getElementById('manual-search-input');if(inp)inp.focus();},100);
}

var _manualSearchOrigHtml='';
function _doManualSearch(){
  var inp=document.getElementById('manual-search-input');
  var body=document.getElementById('manual-search-body');
  var countEl=document.getElementById('manual-search-count');
  if(!inp||!body)return;
  // Cache original HTML on first search
  if(!_manualSearchOrigHtml){_manualSearchOrigHtml=body.innerHTML;}
  var q=inp.value.trim();
  if(!q){body.innerHTML=_manualSearchOrigHtml;if(countEl)countEl.textContent='';return;}
  // Reset to original and highlight matches
  var html=_manualSearchOrigHtml;
  // Escape regex special chars
  var esc=q.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  var re=new RegExp('(>)([^<]*?)(' + esc + ')','gi');
  var count=0;
  // Highlight within text nodes only (between > and <)
  html=html.replace(/>([^<]*)</g, function(match, text){
    var replaced=text.replace(new RegExp('(' + esc + ')','gi'), function(m){
      count++;
      return '<mark style="background:#74FB71;color:var(--black);padding:1px 2px;border-radius:2px;">'+m+'</mark>';
    });
    return '>'+replaced+'<';
  });
  body.innerHTML=html;
  if(countEl)countEl.textContent=count>0?count+' ×':'0';
  // Scroll to first match
  if(count>0){var first=body.querySelector('mark');if(first)first.scrollIntoView({behavior:'smooth',block:'center'});}
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
