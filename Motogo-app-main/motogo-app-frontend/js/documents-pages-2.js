
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
