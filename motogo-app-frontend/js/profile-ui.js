// ===== PROFILE-UI.JS – Profile screen rendering and editing =====

async function renderProfile(){
  try {
    var profile = await apiFetchProfile();
    if(!profile) return;

    // Format ISO date to Czech format
    function fmtIso(v){if(!v)return '';if(/\d{4}-\d{2}-\d{2}/.test(v)){var p=v.split('-');return parseInt(p[2])+'. '+parseInt(p[1])+'. '+p[0];}return v;}
    // Fill profile fields
    var fields = {
      'profile-name': profile.full_name,
      'profile-email': profile.email,
      'profile-phone': profile.phone,
      'profile-dob': fmtIso(profile.date_of_birth),
      'profile-street': profile.street,
      'profile-city': profile.city,
      'profile-zip': profile.zip,
      'profile-license-num': profile.license_number,
      'profile-license-expiry': fmtIso(profile.license_expiry),
      'profile-license-group': Array.isArray(profile.license_group) ? profile.license_group.join(', ') : (profile.license_group || '')
    };

    for(var id in fields){
      var el = document.getElementById(id);
      if(el){
        if(el.tagName === 'INPUT' || el.tagName === 'SELECT') el.value = fields[id] || '';
        else el.textContent = fields[id] || '';
      }
    }

    // Profile header
    var headerName = document.getElementById('profile-header-name');
    if(headerName) headerName.textContent = profile.full_name || '';
    var headerEmail = document.getElementById('profile-header-email');
    if(headerEmail) headerEmail.textContent = profile.email || '';
    var headerInitials = document.getElementById('profile-header-initials');
    if(headerInitials){
      headerInitials.textContent = (profile.full_name || 'NN').split(' ').map(function(n){ return n.charAt(0).toUpperCase(); }).join('');
    }

    // Verification badge
    var vBadge = document.getElementById('profile-docs-badge');
    if(vBadge){
      if(profile.docs_verified_at){
        vBadge.style.display = '';
        vBadge.innerHTML = '<span style="display:inline-flex;align-items:center;gap:6px;' +
          'background:#dcfce7;color:#166534;border:1px solid #86efac;border-radius:20px;' +
          'padding:6px 14px;font-size:12px;font-weight:700;">' +
          '&#9989; Doklady ověřeny</span>';
      } else if(profile.docs_verification_status === 'mismatch'){
        vBadge.style.display = '';
        vBadge.innerHTML = '<span style="display:inline-flex;align-items:center;gap:6px;' +
          'background:#fef3c7;color:#92400e;border:1px solid #f59e0b;border-radius:20px;' +
          'padding:6px 14px;font-size:12px;font-weight:700;">' +
          '&#9888;&#65039; Rozpory v dokladech</span>';
      } else {
        vBadge.style.display = '';
        vBadge.innerHTML = '<span style="display:inline-flex;align-items:center;gap:6px;' +
          'background:#f3f4f6;color:#6b7280;border:1px solid #d1d5db;border-radius:20px;' +
          'padding:6px 14px;font-size:12px;font-weight:700;">' +
          '&#128196; Doklady neověřeny</span>';
      }
    }

    // Documents section
    renderDocuments();
  } catch(e){ console.error('renderProfile error:', e); }
}

async function doSaveProfile(){
  try {
    // Parse Czech date "D. M. YYYY" back to ISO "YYYY-MM-DD"
    function parseCzDate(v){
      if(!v) return null;
      v = v.trim();
      if(/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
      var m = v.match(/^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$/);
      if(m) return m[3]+'-'+('0'+m[2]).slice(-2)+'-'+('0'+m[1]).slice(-2);
      return null;
    }
    var data = {
      full_name: (document.getElementById('profile-name') || {}).value || '',
      phone: (document.getElementById('profile-phone') || {}).value || '',
      street: (document.getElementById('profile-street') || {}).value || '',
      city: (document.getElementById('profile-city') || {}).value || '',
      zip: (document.getElementById('profile-zip') || {}).value || '',
      license_number: (document.getElementById('profile-license-num') || {}).value || '',
      license_group: (function(){ var v = (document.getElementById('profile-license-group') || {}).value || ''; return v ? v.split(/[,\s]+/).filter(Boolean) : []; })()
    };
    var dob = parseCzDate((document.getElementById('profile-dob') || {}).value);
    if(dob) data.date_of_birth = dob;
    var licExp = parseCzDate((document.getElementById('profile-license-expiry') || {}).value);
    if(licExp) data.license_expiry = licExp;

    var result = await apiUpdateProfile(data);
    if(result.error){
      showT('✗',_t('common').error,result.error);
      return;
    }
    showT('✓',_t('common').profileSaved,_t('common').changesSaved);
    renderUserData();
  } catch(e){ console.error('doSaveProfile error:', e); showT('✗',_t('common').error,_t('common').saveFailed); }
}

async function renderDocuments(){
  try {
    var docsWrap = document.getElementById('profile-documents');
    if(!docsWrap) return;

    var docs = await apiFetchDocuments();
    if(!docs || docs.length === 0){
      docsWrap.innerHTML = '<div style="font-size:12px;color:var(--g400);padding:8px 0;">'+_t('common').noDocs+'</div>';
      return;
    }

    docsWrap.innerHTML = docs.map(function(d){
      var typeLabels = {contract:'📄 '+_t('doc').contractLabel, protocol:'📋 '+_t('doc').protocolLabel, invoice:'🧾 '+_t('doc').invoiceFinal.split(' ')[0],
        vop:'📜 VOP', license_photo:'🏍️', id_photo:'🪪', document:'📎'};
      return '<div style="display:flex;align-items:center;gap:10px;padding:8px 0;border-bottom:1px solid var(--g100);">' +
        '<div style="font-size:20px;">' + (typeLabels[d.type] ? typeLabels[d.type].split(' ')[0] : '📎') + '</div>' +
        '<div style="flex:1;"><div style="font-size:12px;font-weight:700;">' + (d.file_name || d.type) + '</div>' +
        '<div style="font-size:10px;color:var(--g400);">' + (d.created_at ? new Date(d.created_at).toLocaleDateString('cs-CZ') : '') + '</div></div></div>';
    }).join('');
  } catch(e){ console.error('renderDocuments error:', e); }
}

async function doDeleteAccount(){
  try {
    if(!confirm(_t('common').deleteAccount)) return;
    if(!confirm(_t('common').deleteConfirm)) return;

    if(_isSupabaseReady()){
      try {
        var session = await _getSession();
        if(session && session.user_id){
          await supabase.from('profiles').delete().eq('id', session.user_id);
        }
        await supabase.auth.signOut();
      } catch(e){ console.error('doDeleteAccount supabase error:', e); }
    }

    try { localStorage.removeItem('mg_current_session'); } catch(e){}
    showT('✓',_t('common').accountDeleted,_t('common').dataRemoved);
    setTimeout(function(){ goTo('s-login'); }, 1000);
  } catch(e){ console.error('doDeleteAccount error:', e); showT('✗',_t('common').error,_t('common').deleteFailed); }
}

async function renderInvoices(){
  try {
    var wrap = document.getElementById('invoices-list');
    if(!wrap) return;
    var docs = await apiFetchDocuments();
    // Filter only invoice types
    var invoices = (docs || []).filter(function(d){
      return d.type === 'invoice_advance' || d.type === 'invoice_final' || d.type === 'payment_receipt';
    });
    if(invoices.length === 0){
      wrap.innerHTML = '<div style="text-align:center;padding:30px;color:var(--g400);">'+(_t('common').noDocuments||'Zatím žádné faktury')+'</div>';
      return;
    }
    var years = {};
    invoices.forEach(function(d){
      var y = new Date(d.created_at || d.date).getFullYear();
      if(!years[y]) years[y] = [];
      years[y].push(d);
    });
    var html = '';
    Object.keys(years).sort(function(a,b){return b-a;}).forEach(function(yr){
      html += '<div class="msec-t" style="padding:'+(html?'12':'0')+'px 0 8px;">'+yr+'</div>';
      years[yr].forEach(function(d){
        var dateFmt = new Date(d.date || d.created_at).toLocaleDateString('cs-CZ');
        var isReceipt = d.type === 'payment_receipt';
        var icon = isReceipt ? '✅' : (d.type === 'invoice_advance' ? '🧾' : '💰');
        var label = isReceipt ? (_t('doc').paymentReceipt||'Doklad k platbě') : (d.type === 'invoice_advance' ? (_t('doc').invoiceAdvance||'Zálohová faktura') : (_t('doc').invoiceFinal||'Faktura'));
        var amt = d.amount ? d.amount.toLocaleString('cs-CZ') + ' Kč' : '';
        var invType = isReceipt ? 'payment_receipt' : (d.type === 'invoice_advance' ? 'advance' : 'final');
        html += '<div class="inv-item" onclick="showInvoice(\''+d.booking_id+'\',\''+invType+'\')">' +
          '<div class="inv-icon">'+icon+'</div>' +
          '<div class="inv-info"><div class="inv-name">'+(d.moto_name||'')+' · '+label+'</div>' +
          '<div class="inv-sub">'+(d.res_num||'')+' · '+dateFmt+'</div></div>' +
          '<div>'+(amt?'<div class="inv-amt">'+amt+'</div>':'')+
          '<div style="font-size:10px;color:var(--g400);text-align:right;margin-top:2px;">PDF ⬇️ · 📧</div></div></div>';
      });
    });
    wrap.innerHTML = html;
  } catch(e){ console.error('renderInvoices error:', e); }
}

async function downloadDoc(docId){
  showT('⬇️',_t('common').downloadDoc,_t('common').openPDF);
  // Simulate email send
  var result = await apiSendDocumentEmail(docId);
  if(result.success){
    setTimeout(function(){
      showT('📧',_t('common').sentToEmail,result.email);
    }, 1500);
  }
}
