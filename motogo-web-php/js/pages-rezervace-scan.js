// ===== MotoGo24 Web — Rezervace: Mindee OCR scan + Stripe payment =====
var MG = window.MG || {};
window.MG = MG;

// ===== MINDEE STEP (mobile: mandatory, desktop: optional) =====
MG._rezShowMindeeStep = async function(){
  // If docs not yet validated (coming from step 2 form), validate first
  if(!MG._rez._docsValidated){
    var docNum=document.getElementById('rez-doc-number');
    var licNum=document.getElementById('rez-license-number');
    var licGroup=document.getElementById('rez-license-group');
    var licExpiry=document.getElementById('rez-license-expiry');
    var licConf=document.getElementById('rez-license-confirm');
    if(!docNum||!docNum.value){alert('Vyplňte číslo dokladu totožnosti.');return;}
    if(!licGroup||!licGroup.value){alert('Vyberte skupinu řidičského oprávnění (A2, A nebo Bez ŘP).');return;}
    var _isNoLic = (licGroup.value === 'N');
    if(!_isNoLic){
      if(!licNum||!licNum.value||licNum.value.trim().length<4){alert('Číslo řidičského průkazu musí mít alespoň 4 znaky.');return;}
      if(!licExpiry||!licExpiry.value){alert('Vyplňte platnost řidičského průkazu.');return;}
      if(!MG._isLicenseExpiryValid(licExpiry.value)){alert('Řidičský průkaz musí být platný min. 14 dní od dnes.');return;}
      if(!licConf||!licConf.checked){alert('Potvrďte prosím držení platného řidičského oprávnění.');return;}
    }

    // Validace hesla (pokud nebylo nastaveno dříve)
    if(!MG._rez._passwordSet){
      var pwd=document.getElementById('rez-password');
      var pwdC=document.getElementById('rez-password-confirm');
      if(!pwd||!pwd.value||pwd.value.length<8){alert('Heslo musí mít alespoň 8 znaků.');return;}
      if(!pwdC||pwd.value!==pwdC.value){alert('Hesla se neshodují.');return;}
      MG._rez._password=pwd.value;
    }

    MG._rez._docNumber=docNum.value;
    MG._rez._licenseNumber=_isNoLic?null:licNum.value;
    if(MG._rez.formData){
      MG._rez.formData._licGroup=licGroup.value;
      MG._rez.formData._licExpiry=_isNoLic?null:(licExpiry?licExpiry.value:null);
    }
    MG._rez._docsValidated=true;

    // Save to profile
    if(MG._rez.userId){
      try{await window.sb.from('profiles').update({
        id_number:docNum.value,
        license_number:_isNoLic?null:licNum.value,
        license_group:[licGroup.value],
        license_expiry:_isNoLic?null:licExpiry.value
      }).eq('id',MG._rez.userId);}catch(e){}
    }

    // Uložit heslo přes RPC
    if(MG._rez._password && MG._rez.bookingId){
      try{await window.sb.rpc('set_web_booking_password',{
        p_booking_id:MG._rez.bookingId, p_password:MG._rez._password
      });}catch(e){console.warn('[REZ] password save error:',e);}
      MG._rez._passwordSet=true;
      delete MG._rez._password;
    }
  }

  // Reset scan flags
  MG._rez._idScanned=false;
  MG._rez._dlScanned=false;

  var isMob=MG._isMobile();

  // Show Mindee scanning UI
  var form=document.getElementById('rez-form');if(!form)return;
  var total=MG._rez.bookingAmount||0;

  // Mobile: mandatory, Desktop: optional
  var subtitle=isMob
    ?'<p style="color:#555;line-height:1.6;margin-bottom:1rem">Pro dokončení rezervace je nutné vyfotit oba doklady. Díky tomu bude vaše odbavení rychlejší a získáte přístup k autonomní pobočce.</p>'
    :'<p style="color:#555;line-height:1.6;margin-bottom:1rem">Vyfotografujte doklady pro rychlejší odbavení a možnost využít autonomní pobočku. Tento krok můžete přeskočit.</p>';

  // Mobile: payment button disabled until both docs scanned
  var payBtnDisabled=isMob?' disabled style="opacity:.5;cursor:not-allowed"':'';

  form.innerHTML=
    '<h2 style="margin-top:1rem">Ověření dokladů fotoaparátem</h2>'+subtitle+

    '<div style="background:#f9f9f9;border:1px solid #e0e0e0;border-radius:10px;padding:1rem;margin-bottom:1rem">'+
    '<div style="display:flex;align-items:center;gap:1rem;margin-bottom:.75rem">'+
    '<span style="font-size:1.5rem">&#128196;</span>'+
    '<div><h3 style="margin:0">Doklad totožnosti'+(isMob?' <span style="color:#c00">*</span>':'')+'</h3>'+
    '<p style="margin:0;font-size:.85rem;color:#555">Občanský průkaz nebo cestovní pas</p></div></div>'+
    '<div id="mindee-id-status"></div>'+
    '<button class="btn btngreen-small" onclick="MG._rezScanDoc(\'id\')" style="margin-top:.5rem">Vyfotit doklad</button></div>'+

    '<div style="background:#f9f9f9;border:1px solid #e0e0e0;border-radius:10px;padding:1rem;margin-bottom:1rem">'+
    '<div style="display:flex;align-items:center;gap:1rem;margin-bottom:.75rem">'+
    '<span style="font-size:1.5rem">&#128179;</span>'+
    '<div><h3 style="margin:0">Řidičský průkaz'+(isMob?' <span style="color:#c00">*</span>':'')+'</h3>'+
    '<p style="margin:0;font-size:.85rem;color:#555">Přední strana</p></div></div>'+
    '<div id="mindee-dl-status"></div>'+
    '<button class="btn btngreen-small" onclick="MG._rezScanDoc(\'dl\')" style="margin-top:.5rem">Vyfotit řidičský průkaz</button></div>'+

    (isMob?'<p id="mindee-mandatory-msg" style="color:#c00;font-size:.85rem;text-align:center;margin:.5rem 0">Oba doklady musí být nahrány před pokračováním k platbě.</p>':'')+

    '<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:1rem;margin-top:1.5rem">'+
    '<button class="btn btndark" onclick="MG._rezShowStep2()">&#8592; Zpět</button>'+
    '<div style="display:flex;align-items:center;gap:1rem">'+
    '<div style="background:#74FB71;color:#0b0b0b;padding:.6rem 1.2rem;border-radius:25px;font-weight:800;font-size:1.05rem">'+MG.formatPrice(total)+'</div>'+
    '<button id="mindee-pay-btn" class="btn btngreen" onclick="MG._rezSubmitPayment()"'+payBtnDisabled+'>Pokračovat k platbě</button></div></div>';
  window.scrollTo({top:form.offsetTop-80,behavior:'smooth'});
};

// ===== SCAN DOCUMENT (camera capture → Mindee OCR) =====
MG._rezScanDoc = function(docType){
  var input=document.createElement('input');
  input.type='file'; input.accept='image/*';
  input.setAttribute('capture','environment');
  input.style.display='none';
  document.body.appendChild(input);

  input.onchange=function(){
    var file=input.files&&input.files[0];
    document.body.removeChild(input);
    if(!file)return;
    var statusId='mindee-'+(docType==='id'?'id':'dl')+'-status';
    var statusEl=document.getElementById(statusId);
    if(statusEl) statusEl.innerHTML='<div style="color:#999;padding:.5rem 0">&#9203; Zpracovávám dokument...</div>';

    var reader=new FileReader();
    reader.onload=function(){
      var img=new Image();
      img.onload=function(){
        var canvas=document.createElement('canvas');
        var maxW=1600,w=img.width,h=img.height;
        if(w>maxW){h=Math.round(h*maxW/w);w=maxW;}
        canvas.width=w;canvas.height=h;
        canvas.getContext('2d').drawImage(img,0,0,w,h);
        var base64=canvas.toDataURL('image/jpeg',0.8).split(',')[1];
        MG._rezProcessOcr(base64,docType);
      };
      img.src=reader.result;
    };
    reader.readAsDataURL(file);
  };
  input.click();
};

// ===== PROCESS OCR via scan-document edge function =====
MG._rezProcessOcr = async function(base64,docType){
  var statusEl=document.getElementById('mindee-'+(docType==='id'?'id':'dl')+'-status');
  try{
    var res=await fetch(window.MOTOGO_CONFIG.SUPABASE_URL+'/functions/v1/scan-document',{
      method:'POST',
      headers:{'Content-Type':'application/json','apikey':window.MOTOGO_CONFIG.SUPABASE_ANON_KEY},
      body:JSON.stringify({image_base64:base64,document_type:docType==='id'?'id':'dl',user_id:MG._rez.userId||null})
    });
    var data=await res.json();
    if(data.fields&&Object.keys(data.fields).length>0){
      var f=data.fields;
      var info=docType==='id'?(f.idNumber?'č. '+f.idNumber:''):(f.licenseNumber?'č. '+f.licenseNumber:'');
      if(statusEl) statusEl.innerHTML='<div style="color:#1a8c1a;padding:.5rem 0">&#10004; Doklad rozpoznán'+(info?' — '+info:'')+'</div>';

      // Mark doc as scanned
      if(docType==='id') MG._rez._idScanned=true;
      if(docType==='dl') MG._rez._dlScanned=true;
      MG._rezCheckMandatoryDocs();

      // Save OCR results to profile
      if(MG._rez.userId){
        var upd={};
        if(docType==='id'&&f.idNumber){upd.id_number=f.idNumber;upd.id_verified_at=new Date().toISOString();}
        if(docType==='dl'&&f.licenseNumber){upd.license_number=f.licenseNumber;upd.license_verified_at=new Date().toISOString();}
        if(Object.keys(upd).length) await window.sb.from('profiles').update(upd).eq('id',MG._rez.userId);
      }

      // Upload document photo to storage
      if(MG._rez.userId){
        var docTypeStr=docType==='id'?'id_card':'drivers_license';
        var blob=MG._rezB64toBlob(base64,'image/jpeg');
        await window.sb.storage.from('documents').upload(
          MG._rez.userId+'/'+docTypeStr+'_'+Date.now()+'.jpg',blob
        ).catch(function(){});
        await window.sb.from('documents').insert({
          user_id:MG._rez.userId,type:docTypeStr,
          name:docType==='id'?'Doklad totožnosti (web sken)':'Řidičský průkaz (web sken)'
        }).catch(function(){});
      }
    } else {
      if(statusEl) statusEl.innerHTML='<div style="color:#e67e22;padding:.5rem 0">&#9888; Nepodařilo se rozpoznat — zkuste to znovu</div>';
    }
  }catch(e){
    if(statusEl) statusEl.innerHTML='<div style="color:#e67e22;padding:.5rem 0">&#9888; Chyba zpracování — zkuste to znovu</div>';
  }
};

// ===== CHECK MANDATORY DOCS (mobile: enable pay button when both scanned) =====
MG._rezCheckMandatoryDocs = function(){
  if(!MG._isMobile()) return;
  var btn=document.getElementById('mindee-pay-btn');
  var msg=document.getElementById('mindee-mandatory-msg');
  if(MG._rez._idScanned && MG._rez._dlScanned){
    if(btn){btn.disabled=false;btn.style.opacity='1';btn.style.cursor='pointer';}
    if(msg) msg.innerHTML='<span style="color:#1a8c1a">&#10004; Oba doklady nahrány — můžete pokračovat k platbě.</span>';
  }
};

// ===== UPLOAD DOCUMENT FROM FILE (web step 2 — optional) =====
MG._rezUploadDoc = function(docType){
  var input=document.createElement('input');
  input.type='file'; input.accept='image/*,.pdf';
  input.style.display='none';
  document.body.appendChild(input);

  input.onchange=function(){
    var file=input.files&&input.files[0];
    document.body.removeChild(input);
    if(!file)return;
    var statusId='webdoc-'+(docType==='id'?'id':'dl')+'-status';
    var statusEl=document.getElementById(statusId);
    if(statusEl) statusEl.innerHTML='<div style="color:#999;padding:.5rem 0">&#9203; Zpracovávám dokument...</div>';

    // For images, resize and send to Mindee OCR
    if(file.type.indexOf('image')!==-1){
      var reader=new FileReader();
      reader.onload=function(){
        var img=new Image();
        img.onload=function(){
          var canvas=document.createElement('canvas');
          var maxW=1600,w=img.width,h=img.height;
          if(w>maxW){h=Math.round(h*maxW/w);w=maxW;}
          canvas.width=w;canvas.height=h;
          canvas.getContext('2d').drawImage(img,0,0,w,h);
          var base64=canvas.toDataURL('image/jpeg',0.8).split(',')[1];
          MG._rezProcessWebDocOcr(base64,docType);
        };
        img.src=reader.result;
      };
      reader.readAsDataURL(file);
    } else {
      // PDF or other — just upload to storage without OCR
      MG._rezUploadDocFile(file,docType);
    }
  };
  input.click();
};

// ===== CAPTURE DOCUMENT WITH CAMERA (web step 2) =====
MG._rezCaptureDoc = function(docType){
  var input=document.createElement('input');
  input.type='file'; input.accept='image/*';
  input.setAttribute('capture','environment');
  input.style.display='none';
  document.body.appendChild(input);

  input.onchange=function(){
    var file=input.files&&input.files[0];
    document.body.removeChild(input);
    if(!file)return;
    var statusId='webdoc-'+(docType==='id'?'id':'dl')+'-status';
    var statusEl=document.getElementById(statusId);
    if(statusEl) statusEl.innerHTML='<div style="color:#999;padding:.5rem 0">&#9203; Zpracovávám dokument...</div>';

    var reader=new FileReader();
    reader.onload=function(){
      var img=new Image();
      img.onload=function(){
        var canvas=document.createElement('canvas');
        var maxW=1600,w=img.width,h=img.height;
        if(w>maxW){h=Math.round(h*maxW/w);w=maxW;}
        canvas.width=w;canvas.height=h;
        canvas.getContext('2d').drawImage(img,0,0,w,h);
        var base64=canvas.toDataURL('image/jpeg',0.8).split(',')[1];
        MG._rezProcessWebDocOcr(base64,docType);
      };
      img.src=reader.result;
    };
    reader.readAsDataURL(file);
  };
  input.click();
};

// ===== PROCESS WEB DOC OCR (for step 2 optional upload) =====
MG._rezProcessWebDocOcr = async function(base64,docType){
  var statusEl=document.getElementById('webdoc-'+(docType==='id'?'id':'dl')+'-status');
  try{
    var res=await fetch(window.MOTOGO_CONFIG.SUPABASE_URL+'/functions/v1/scan-document',{
      method:'POST',
      headers:{'Content-Type':'application/json','apikey':window.MOTOGO_CONFIG.SUPABASE_ANON_KEY},
      body:JSON.stringify({image_base64:base64,document_type:docType==='id'?'id':'dl',user_id:MG._rez.userId||null})
    });
    var data=await res.json();
    if(data.fields&&Object.keys(data.fields).length>0){
      var f=data.fields;
      var info=docType==='id'?(f.idNumber?'č. '+f.idNumber:''):(f.licenseNumber?'č. '+f.licenseNumber:'');
      if(statusEl) statusEl.innerHTML='<div style="color:#1a8c1a;padding:.5rem 0">&#10004; Doklad rozpoznán'+(info?' — '+info:'')+'</div>';

      // Auto-fill form fields from OCR
      if(docType==='id'&&f.idNumber){
        var dn=document.getElementById('rez-doc-number');if(dn)dn.value=f.idNumber;
      }
      if(docType==='dl'){
        if(f.licenseNumber){var ln=document.getElementById('rez-license-number');if(ln)ln.value=f.licenseNumber;}
        if(f.licenseCategory){var lg=document.getElementById('rez-license-group');if(lg)lg.value=f.licenseCategory.toUpperCase();}
        if(f.licenseExpiry){var le=document.getElementById('rez-license-expiry');if(le)le.value=f.licenseExpiry;}
      }

      // Save OCR to profile + upload to storage
      if(MG._rez.userId){
        var upd={};
        if(docType==='id'&&f.idNumber){upd.id_number=f.idNumber;upd.id_verified_at=new Date().toISOString();}
        if(docType==='dl'&&f.licenseNumber){upd.license_number=f.licenseNumber;upd.license_verified_at=new Date().toISOString();}
        if(Object.keys(upd).length) await window.sb.from('profiles').update(upd).eq('id',MG._rez.userId);
        var docTypeStr=docType==='id'?'id_card':'drivers_license';
        var blob=MG._rezB64toBlob(base64,'image/jpeg');
        await window.sb.storage.from('documents').upload(
          MG._rez.userId+'/'+docTypeStr+'_'+Date.now()+'.jpg',blob
        ).catch(function(){});
        await window.sb.from('documents').insert({
          user_id:MG._rez.userId,type:docTypeStr,
          name:docType==='id'?'Doklad totožnosti (web upload)':'Řidičský průkaz (web upload)'
        }).catch(function(){});
      }
    } else {
      if(statusEl) statusEl.innerHTML='<div style="color:#e67e22;padding:.5rem 0">&#9888; Nepodařilo se rozpoznat — zkuste jiný snímek nebo vyplňte údaje ručně</div>';
    }
  }catch(e){
    if(statusEl) statusEl.innerHTML='<div style="color:#e67e22;padding:.5rem 0">&#9888; Chyba zpracování — vyplňte údaje ručně</div>';
  }
};

// ===== UPLOAD DOC FILE (PDF, non-image) =====
MG._rezUploadDocFile = async function(file,docType){
  var statusEl=document.getElementById('webdoc-'+(docType==='id'?'id':'dl')+'-status');
  try{
    if(MG._rez.userId){
      var docTypeStr=docType==='id'?'id_card':'drivers_license';
      var ext=file.name.split('.').pop()||'pdf';
      await window.sb.storage.from('documents').upload(
        MG._rez.userId+'/'+docTypeStr+'_'+Date.now()+'.'+ext,file
      ).catch(function(){});
      await window.sb.from('documents').insert({
        user_id:MG._rez.userId,type:docTypeStr,
        name:docType==='id'?'Doklad totožnosti (web upload)':'Řidičský průkaz (web upload)'
      }).catch(function(){});
      if(statusEl) statusEl.innerHTML='<div style="color:#1a8c1a;padding:.5rem 0">&#10004; Soubor nahrán</div>';
    } else {
      if(statusEl) statusEl.innerHTML='<div style="color:#e67e22;padding:.5rem 0">&#9888; Nelze nahrát — vyplňte údaje ručně</div>';
    }
  }catch(e){
    if(statusEl) statusEl.innerHTML='<div style="color:#e67e22;padding:.5rem 0">&#9888; Chyba nahrávání</div>';
  }
};

// ===== BASE64 TO BLOB =====
MG._rezB64toBlob = function(b64,mime){
  var bytes=atob(b64),arr=[];
  for(var i=0;i<bytes.length;i+=512){
    var slice=bytes.slice(i,i+512),nums=new Array(slice.length);
    for(var j=0;j<slice.length;j++) nums[j]=slice.charCodeAt(j);
    arr.push(new Uint8Array(nums));
  }
  return new Blob(arr,{type:mime});
};

// ===== STRIPE CHECKOUT (skip doc validation if done in Mindee step) =====
MG._rezSubmitPayment = async function(){
  if(!MG._rez._docsValidated){
    var docNum=document.getElementById('rez-doc-number');
    var licNum=document.getElementById('rez-license-number');
    var licGroup=document.getElementById('rez-license-group');
    var licExpiry=document.getElementById('rez-license-expiry');
    var licConf=document.getElementById('rez-license-confirm');
    if(!docNum||!docNum.value){alert('Vyplňte číslo dokladu totožnosti.');return;}
    if(!licGroup||!licGroup.value){alert('Vyberte skupinu řidičského oprávnění (A2, A nebo Bez ŘP).');return;}
    var _isNoLic = (licGroup.value === 'N');
    if(!_isNoLic){
      if(!licNum||!licNum.value||licNum.value.trim().length<4){alert('Číslo řidičského průkazu musí mít alespoň 4 znaky.');return;}
      if(!licExpiry||!licExpiry.value){alert('Vyplňte platnost řidičského průkazu.');return;}
      if(!MG._isLicenseExpiryValid(licExpiry.value)){alert('Řidičský průkaz musí být platný min. 14 dní od dnes.');return;}
      if(!licConf||!licConf.checked){alert('Potvrďte prosím držení platného řidičského oprávnění.');return;}
    }

    // Validace hesla (pokud nebylo nastaveno dříve)
    if(!MG._rez._passwordSet){
      var pwd=document.getElementById('rez-password');
      var pwdC=document.getElementById('rez-password-confirm');
      if(!pwd||!pwd.value||pwd.value.length<8){alert('Heslo musí mít alespoň 8 znaků.');return;}
      if(!pwdC||pwd.value!==pwdC.value){alert('Hesla se neshodují.');return;}
      MG._rez._password=pwd.value;
    }

    // Kontrola ŘP skupiny vs. motorka (jen pokud motorka vyžaduje ŘP)
    var _moto = MG._rez.motos ? MG._rez.motos.find(function(m){return m.id===(MG._rez.formData||{}).motoId;}) : null;
    if(_moto && _moto.license_required && _moto.license_required !== 'N'){
      var _lg = licGroup.value.toUpperCase();
      var _allowed = {A:['A','A2','A1','AM'],A2:['A2','A1','AM']};
      var _ok = _allowed[_lg] || [];
      if(_ok.indexOf(_moto.license_required) === -1){
        alert('Pro tuto motorku potřebujete ŘP skupiny ' + _moto.license_required + '. Vaše skupina: ' + (_lg==='N'?'Bez ŘP':_lg));
        return;
      }
    }

    if(MG._rez.formData){
      MG._rez.formData._licGroup=licGroup.value;
      MG._rez.formData._licExpiry=_isNoLic?null:(licExpiry?licExpiry.value:null);
    }

    if(MG._rez.userId){
      try{await window.sb.from('profiles').update({
        id_number:docNum.value,
        license_number:_isNoLic?null:licNum.value,
        license_group:[licGroup.value],
        license_expiry:_isNoLic?null:licExpiry.value
      }).eq('id',MG._rez.userId);}catch(e){}
    }

    // Uložit heslo přes RPC (aktualizace auth.users)
    if(MG._rez._password && MG._rez.bookingId){
      try{await window.sb.rpc('set_web_booking_password',{
        p_booking_id:MG._rez.bookingId, p_password:MG._rez._password
      });}catch(e){console.warn('[REZ] password save error:',e);}
      MG._rez._passwordSet=true;
      delete MG._rez._password;
    }
  }

  var btn=document.querySelector('#rez-form .btn.btngreen');
  if(btn){btn.disabled=true;btn.textContent='Zpracovávám...';}

  var bookingId=MG._rez.bookingId;
  var amount=MG._rez.bookingAmount;
  if(!bookingId){alert('Chyba: rezervace nebyla vytvořena. Zkuste znovu.');if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}return;}

  try{
    var payRes=await fetch(window.MOTOGO_CONFIG.SUPABASE_URL+'/functions/v1/process-payment',{method:'POST',
      headers:{'Content-Type':'application/json','apikey':window.MOTOGO_CONFIG.SUPABASE_ANON_KEY},
      body:JSON.stringify({booking_id:bookingId,amount:amount,type:'booking',source:'web',mode:'checkout'})});
    var payData=await payRes.json();
    if(payData.error){
      var emsg = payData.error || '';
      if(emsg.indexOf('Booking overlap') !== -1) alert('Tuto motorku pr\u00e1v\u011b rezervoval jin\u00fd z\u00e1kazn\u00edk ve stejn\u00e9m term\u00ednu. Zvolte pros\u00edm jin\u00fd term\u00edn nebo jinou motorku.');
      else if(emsg.indexOf('overlapping booking') !== -1) alert('V tomto term\u00ednu ji\u017e m\u00e1te jinou aktivn\u00ed rezervaci.');
      else alert('Chyba platby: '+emsg);
      if(btn){btn.disabled=false;btn.textContent='Pokra\u010dovat k platb\u011b';}return;
    }
    // 100% sleva — potvrzeno bez Stripe
    if(payData.success && payData.free){
      MG._rez._paymentDone=true;
      try{sessionStorage.removeItem('mg_rez_form');}catch(e){}
      alert('Rezervace potvrzena! 100% sleva \u2014 platba nen\u00ed pot\u0159eba.');
      window.location.href='/potvrzeni?booking_id='+bookingId;
      return;
    }
    if(payData.checkout_url){
      MG._rez._paymentDone=true;
      try{sessionStorage.removeItem('mg_rez_form');}catch(e){}
      if(MG._rez._abandonedTimer) clearTimeout(MG._rez._abandonedTimer);
      window.location.href=payData.checkout_url;
    }
    else{alert('Nepodařilo se vytvořit platbu.');if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}}
  }catch(e){console.error('[REZ]',e);alert('Došlo k chybě.');if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}}
};
