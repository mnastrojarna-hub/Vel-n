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
          '&#9989; Doklady ov\u011b\u0159eny</span>';
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
          '&#128196; Doklady neov\u011b\u0159eny</span>';
      }
    }

    // Documents section
    renderDocuments();
  } catch(e){ console.error('renderProfile error:', e); }
}

// ===== POBO\u010cKY =====
var _branchesLoaded = false;
async function loadBranches(){
  if(_branchesLoaded) return;
  _branchesLoaded = true;
  renderBranches();
}

async function renderBranches(){
  var wrap = document.getElementById('branches-list');
  if(!wrap) return;
  if(!window.supabase){
    wrap.innerHTML = '<div style="padding:8px;font-size:12px;color:var(--g400);">Pobo\u010dky nejsou dostupn\u00e9 offline</div>';
    return;
  }
  try {
    var r = await window.supabase.from('branches').select('id, name, address, city, gps_lat, gps_lng, is_open, type').order('name');
    if(!r.data || r.data.length === 0){
      wrap.innerHTML = '<div style="padding:12px;text-align:center;font-size:12px;color:var(--g400);">\u017d\u00e1dn\u00e9 pobo\u010dky</div>';
      return;
    }
    var html = '';
    r.data.forEach(function(b){
      var statusColor = b.is_open ? '#16a34a' : '#b91c1c';
      var statusText = b.is_open ? 'Nonstop' : 'Zav\u0159eno';
      var typeLabel = b.type ? ' \u00b7 ' + b.type : '';
      var hasGps = b.gps_lat && b.gps_lng;
      var gpsText = hasGps ? '<div style="font-size:10px;color:var(--g400);margin-top:2px;">GPS: '+Number(b.gps_lat).toFixed(5)+', '+Number(b.gps_lng).toFixed(5)+'</div>' : '';
      var navBtn = hasGps ? '<button onclick="event.stopPropagation();navigateToBranch('+b.gps_lat+','+b.gps_lng+',\''+_escHtml(b.name)+'\')" style="background:var(--green);color:#fff;border:none;border-radius:50px;padding:8px 16px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:5px;margin-top:8px;width:100%;">\ud83d\udccd Navigovat</button>' : '';
      var addrBtn = '<button onclick="event.stopPropagation();navigateToAddress(\''+_escHtml((b.address||'')+', '+(b.city||''))+'\')" style="background:var(--gp);color:var(--gd);border:1px solid var(--green);border-radius:50px;padding:8px 16px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:5px;margin-top:6px;width:100%;">\ud83d\uddfa\ufe0f Otev\u0159\u00edt v map\u00e1ch</button>';
      html += '<div style="background:#fff;border-radius:var(--rsm);padding:12px;margin-bottom:8px;border:1px solid var(--g200);">' +
        '<div style="display:flex;align-items:center;gap:10px;margin-bottom:4px;">' +
        '<div style="font-size:24px;">\ud83c\udfea</div>' +
        '<div style="flex:1;"><div style="font-size:14px;font-weight:800;color:var(--black);">'+b.name+'</div>' +
        '<div style="font-size:11px;color:var(--g400);font-weight:500;">'+((b.address||'')+(b.city?', '+b.city:''))+typeLabel+'</div>' +
        gpsText + '</div>' +
        '<span style="font-size:10px;font-weight:800;color:'+statusColor+';background:'+(b.is_open?'#dcfce7':'#fee2e2')+';padding:3px 8px;border-radius:10px;">'+statusText+'</span></div>' +
        (hasGps ? navBtn : addrBtn) +
        '</div>';
    });
    wrap.innerHTML = html;
  } catch(e){ wrap.innerHTML = '<div style="padding:8px;font-size:12px;color:var(--red);">Chyba p\u0159i na\u010d\u00edt\u00e1n\u00ed pobo\u010dek</div>'; }
}

function _escHtml(s){ return (s||'').replace(/'/g,"\\'").replace(/"/g,'&quot;'); }

function navigateToBranch(lat, lng, name){
  var url = 'https://www.google.com/maps/dir/?api=1&destination='+lat+','+lng;
  if(window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Browser){
    window.Capacitor.Plugins.Browser.open({ url: url });
  } else {
    window.open(url, '_blank');
  }
}

function navigateToAddress(address){
  var url = 'https://www.google.com/maps/dir/?api=1&destination='+encodeURIComponent(address);
  if(window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Browser){
    window.Capacitor.Plugins.Browser.open({ url: url });
  } else {
    window.open(url, '_blank');
  }
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
      showT('\u2717',_t('common').error,result.error);
      return;
    }
    showT('\u2713',_t('common').profileSaved,_t('common').changesSaved);
    renderUserData();
  } catch(e){ console.error('doSaveProfile error:', e); showT('\u2717',_t('common').error,_t('common').saveFailed); }
}

// ===== DOCS SCREEN — show verification status from DB =====
async function renderDocsScreenStatus(){
  var banner=document.getElementById('docs-verified-banner');
  var unverified=document.getElementById('docs-unverified-section');
  if(!banner||!unverified) return;
  if(!_isSupabaseReady()){banner.style.display='none';unverified.style.display='';return;}
  try {
    var uid=await _getUserId();if(!uid)return;
    var r=await window.supabase.from('profiles')
      .select('id_verified_at,id_verified_until,license_verified_at,license_verified_until,passport_verified_at,passport_verified_until,license_expiry,license_number')
      .eq('id',uid).maybeSingle();
    if(!r||!r.data){banner.style.display='none';unverified.style.display='';return;}
    var p=r.data,today=new Date().toISOString().slice(0,10);
    var hasId=p.id_verified_at&&(!p.id_verified_until||p.id_verified_until>=today);
    var hasPas=p.passport_verified_at&&(!p.passport_verified_until||p.passport_verified_until>=today);
    var hasLic=p.license_verified_at&&(!p.license_verified_until||p.license_verified_until>=today);
    var idOk=hasId||hasPas;
    var allOk=idOk&&hasLic;
    if(allOk){
      // Format dates
      function fmtD(d){if(!d)return'—';var p=d.split('-');return parseInt(p[2])+'.'+parseInt(p[1])+'.'+p[0];}
      var licUntil=p.license_verified_until||p.license_expiry||'—';
      var idUntil=hasId?p.id_verified_until:p.passport_verified_until;
      banner.style.display='block';
      banner.innerHTML='<div style="margin:12px 20px 0;background:#ecfdf5;border:2px solid #6ee7b7;border-radius:var(--r);padding:16px;text-align:center;">'+
        '<div style="font-size:36px;margin-bottom:6px;">✅</div>'+
        '<div style="font-size:16px;font-weight:900;color:#065f46;margin-bottom:4px;">Doklady ověřeny</div>'+
        '<div style="font-size:12px;color:#047857;line-height:1.7;">'+
        (hasId?'🪪 OP ověřen':'📕 Pas ověřen')+(idUntil?' — platnost do <strong>'+fmtD(idUntil)+'</strong>':'')+'<br>'+
        '🏍️ ŘP ověřen — platnost do <strong>'+fmtD(licUntil)+'</strong></div>'+
        '<div style="font-size:11px;color:#059669;margin-top:8px;line-height:1.5;">Vaše doklady jsou evidovány v systému.<br>Po reinstalaci ani aktualizaci aplikace je nemusíte znovu nahrávat.</div>'+
        '</div>';
      unverified.style.display='none';
      localStorage.setItem('mg_docs_verified','1');
    } else {
      banner.style.display='none';
      unverified.style.display='';
      // Show partial status if some docs are verified
      if(idOk||hasLic){
        var partial='<div style="margin:12px 20px 0;background:#fefce8;border:1px solid #fde047;border-radius:var(--rsm);padding:11px 13px;">'+
          '<div style="font-size:13px;font-weight:700;color:#854d0e;margin-bottom:3px;">📋 Částečně ověřeno</div>'+
          '<div style="font-size:12px;color:#a16207;line-height:1.6;">'+(idOk?'✅ Doklad totožnosti OK':'❌ Chybí doklad totožnosti')+' · '+(hasLic?'✅ ŘP OK':'❌ Chybí řidičský průkaz')+'</div></div>';
        banner.style.display='block';banner.innerHTML=partial;
      }
    }
  }catch(e){console.warn('[DOCS] renderDocsScreenStatus:',e);}
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
      var typeLabels = {contract:'\ud83d\udcc4 '+_t('doc').contractLabel, protocol:'\ud83d\udccb '+_t('doc').protocolLabel, invoice:'\ud83e\uddfe '+_t('doc').invoiceFinal.split(' ')[0],
        vop:'\ud83d\udcdc VOP', license_photo:'\ud83c\udfcd\ufe0f', id_photo:'\ud83e\udea3', document:'\ud83d\udcce'};
      return '<div style="display:flex;align-items:center;gap:10px;padding:8px 0;border-bottom:1px solid var(--g100);">' +
        '<div style="font-size:20px;">' + (typeLabels[d.type] ? typeLabels[d.type].split(' ')[0] : '\ud83d\udcce') + '</div>' +
        '<div style="flex:1;"><div style="font-size:12px;font-weight:700;">' + (d.file_name || d.type) + '</div>' +
        '<div style="font-size:10px;color:var(--g400);">' + (d.created_at ? new Date(d.created_at).toLocaleDateString('cs-CZ') : '') + '</div></div></div>';
    }).join('');
  } catch(e){ console.error('renderDocuments error:', e); }
}
