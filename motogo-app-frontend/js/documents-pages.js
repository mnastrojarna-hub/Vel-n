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
