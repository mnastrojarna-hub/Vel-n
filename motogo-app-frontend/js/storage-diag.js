// ===== STORAGE-DIAG.JS – Storage & cache diagnostics overlay =====
// Shows localStorage, Cache API, and storage estimate. Accessible from Profile → Úložiště.

function _fmtBytes(b){
  if(b<1024) return b+' B';
  if(b<1048576) return (b/1024).toFixed(1)+' KB';
  return (b/1048576).toFixed(2)+' MB';
}

async function showStorageDiag(){
  var ov=document.createElement('div');
  ov.id='storage-diag-overlay';
  ov.style.cssText='position:fixed;top:0;left:0;right:0;bottom:0;z-index:99998;background:#f5f5f7;overflow-y:auto;';

  var html='<div style="background:linear-gradient(135deg,#1a2e22,#2d5a3c);padding:env(safe-area-inset-top,20px) 20px 18px;">'+
    '<div style="display:flex;align-items:center;justify-content:space-between;">'+
    '<button onclick="document.getElementById(\'storage-diag-overlay\').remove()" style="background:rgba(255,255,255,.15);border:none;border-radius:12px;padding:8px 14px;color:#fff;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">← Zpět</button>'+
    '<span style="font-size:12px;color:rgba(255,255,255,.6);">💾 Diagnostika</span></div>'+
    '<div style="font-size:18px;font-weight:900;color:#fff;margin-top:10px;">Úložiště a cache</div>'+
    '</div><div style="padding:14px 20px 20px;" id="sd-content"><div style="text-align:center;padding:30px;color:var(--g400);">⏳ Analyzuji...</div></div>';
  ov.innerHTML=html;
  document.querySelector('.phone').appendChild(ov);

  // Collect data
  var sections=[];
  var totalBytes=0;

  // 1. localStorage
  var lsItems=[];
  var lsTotal=0;
  try{
    for(var i=0;i<localStorage.length;i++){
      var k=localStorage.key(i);
      var v=localStorage.getItem(k)||'';
      var sz=k.length+v.length;
      lsTotal+=sz*2; // UTF-16
      lsItems.push({key:k,size:sz*2,preview:v.substr(0,80)});
    }
    lsItems.sort(function(a,b){return b.size-a.size;});
  }catch(e){}
  totalBytes+=lsTotal;

  var lsHtml='<div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;">localStorage — '+_fmtBytes(lsTotal)+' ('+lsItems.length+' klíčů)</div>';
  lsItems.forEach(function(it){
    var bar=Math.min(100,Math.round(it.size/Math.max(lsTotal,1)*100));
    lsHtml+='<div style="margin-bottom:6px;">'+
      '<div style="display:flex;justify-content:space-between;font-size:11px;font-weight:700;color:var(--black);">'+
      '<span style="font-family:monospace;word-break:break-all;">'+it.key+'</span>'+
      '<span style="flex-shrink:0;margin-left:8px;color:var(--g400);">'+_fmtBytes(it.size)+'</span></div>'+
      '<div style="height:4px;background:var(--g100);border-radius:2px;margin-top:2px;">'+
      '<div style="height:4px;background:var(--green);border-radius:2px;width:'+bar+'%;"></div></div>'+
      '<div style="font-size:9px;color:var(--g400);margin-top:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">'+it.preview.replace(/</g,'&lt;')+'</div></div>';
  });
  sections.push({title:'localStorage',html:lsHtml});

  // 2. Cache API (Service Worker)
  var cacheHtml='';
  var cacheTotal=0;
  try{
    if(window.caches){
      var names=await caches.keys();
      for(var ci=0;ci<names.length;ci++){
        var c=await caches.open(names[ci]);
        var keys=await c.keys();
        var cSize=0;
        var entries=[];
        for(var ki=0;ki<keys.length;ki++){
          try{
            var resp=await c.match(keys[ki]);
            if(resp){
              var blob=await resp.clone().blob();
              cSize+=blob.size;
              entries.push({url:keys[ki].url.split('/').pop()||keys[ki].url,size:blob.size});
            }
          }catch(e){}
        }
        cacheTotal+=cSize;
        entries.sort(function(a,b){return b.size-a.size;});
        cacheHtml+='<div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;">'+names[ci]+' — '+_fmtBytes(cSize)+' ('+keys.length+' souborů)</div>';
        entries.slice(0,15).forEach(function(e){
          var bar=Math.min(100,Math.round(e.size/Math.max(cSize,1)*100));
          cacheHtml+='<div style="margin-bottom:4px;">'+
            '<div style="display:flex;justify-content:space-between;font-size:10px;">'+
            '<span style="font-family:monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:65%;">'+e.url+'</span>'+
            '<span style="color:var(--g400);flex-shrink:0;">'+_fmtBytes(e.size)+'</span></div>'+
            '<div style="height:3px;background:var(--g100);border-radius:2px;margin-top:1px;">'+
            '<div style="height:3px;background:#635BFF;border-radius:2px;width:'+bar+'%;"></div></div></div>';
        });
        if(entries.length>15) cacheHtml+='<div style="font-size:10px;color:var(--g400);margin-bottom:8px;">...a dalších '+(entries.length-15)+' souborů</div>';
      }
    }
  }catch(e){ cacheHtml='<div style="font-size:11px;color:var(--red);">Chyba: '+e.message+'</div>'; }
  totalBytes+=cacheTotal;
  if(cacheHtml) sections.push({title:'Service Worker Cache',html:cacheHtml});

  // 3. navigator.storage.estimate
  var estHtml='';
  try{
    if(navigator.storage && navigator.storage.estimate){
      var est=await navigator.storage.estimate();
      var used=est.usage||0;
      var quota=est.quota||0;
      var pct=quota>0?Math.round(used/quota*100):0;
      estHtml='<div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;">Celkové úložiště prohlížeče</div>'+
        '<div style="display:flex;justify-content:space-between;font-size:13px;font-weight:800;color:var(--black);margin-bottom:4px;">'+
        '<span>Použito: '+_fmtBytes(used)+'</span><span>Kvóta: '+_fmtBytes(quota)+'</span></div>'+
        '<div style="height:8px;background:var(--g100);border-radius:4px;">'+
        '<div style="height:8px;background:'+(pct>80?'var(--red)':'var(--green)')+';border-radius:4px;width:'+pct+'%;"></div></div>'+
        '<div style="font-size:10px;color:var(--g400);margin-top:2px;">'+pct+'% využito</div>';
      totalBytes=used; // override with real estimate
    }
  }catch(e){}
  if(estHtml) sections.push({title:'Storage Estimate',html:estHtml});

  // Render
  var out='<div style="background:#fff;border-radius:16px;padding:16px;box-shadow:0 2px 12px rgba(0,0,0,.06);margin-bottom:12px;text-align:center;">'+
    '<div style="font-size:28px;font-weight:900;color:var(--black);">'+_fmtBytes(totalBytes)+'</div>'+
    '<div style="font-size:11px;color:var(--g400);margin-top:2px;">celkem využito</div></div>';

  sections.forEach(function(s){
    out+='<div style="background:#fff;border-radius:16px;padding:14px 16px;box-shadow:0 2px 12px rgba(0,0,0,.06);margin-bottom:12px;">'+s.html+'</div>';
  });

  out+='<button onclick="_clearAppCache()" style="width:100%;background:var(--red,#dc2626);color:#fff;border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;margin-bottom:8px;">🗑️ Vyčistit cache</button>';
  out+='<button onclick="_clearLocalStorage()" style="width:100%;background:var(--g100);color:var(--black);border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;margin-bottom:20px;">🧹 Vyčistit localStorage (zachová přihlášení)</button>';

  document.getElementById('sd-content').innerHTML=out;
}

async function _clearAppCache(){
  if(!confirm('Smazat Service Worker cache? Aplikace se příště načte ze sítě.')) return;
  try{
    if(window.caches){
      var names=await caches.keys();
      for(var i=0;i<names.length;i++) await caches.delete(names[i]);
    }
    if(navigator.serviceWorker){
      var regs=await navigator.serviceWorker.getRegistrations();
      for(var i=0;i<regs.length;i++) await regs[i].unregister();
    }
    showT('✓','Cache smazána','Aplikace se příště načte ze sítě');
    showStorageDiag(); // refresh
  }catch(e){ showT('✗','Chyba',e.message); }
}

function _clearLocalStorage(){
  if(!confirm('Smazat localStorage? Přihlášení zůstane zachováno.')) return;
  try{
    var keep=['mg_current_session','mg_bio_user','mg_bio_enabled','mg_saved_email','mg_lang','mg_perms'];
    var saved={};
    keep.forEach(function(k){ var v=localStorage.getItem(k); if(v!==null) saved[k]=v; });
    localStorage.clear();
    for(var k in saved) localStorage.setItem(k,saved[k]);
    showT('✓','localStorage vyčištěn','Zachováno přihlášení a jazyk');
    showStorageDiag(); // refresh
  }catch(e){ showT('✗','Chyba',e.message); }
}
