// ===== MotoGo24 Web — Rezervace: krok 1 submit + krok 2 (doklady+faktura) + QR =====
var MG = window.MG || {};
window.MG = MG;

// ===== MOBILE DETECTION =====
MG._isMobile = function(){ return /Mobi|Android|iPhone|iPad/i.test(navigator.userAgent); };

// ===== QR CODE IMAGE URL (via goqr.me API) =====
MG._qrCodeUrl = function(data){
  return 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data='+encodeURIComponent(data);
};

// ===== VALIDATION HELPERS =====
MG._isNameValid = function(v){
  if(!v||v.trim().length<2) return false;
  if(!/^[\p{Letter}\s'\-]+$/u.test(v.trim())) return false;
  if(/(.)\1{2,}/i.test(v.trim())) return false;
  return true;
};
MG._isPhoneValid = function(v){
  if(!v) return false;
  var digits=v.replace(/[\s\-()]/g,'');
  return /^\+\d{8,14}$/.test(digits);
};
MG._isLicenseExpiryValid = function(dateStr){
  if(!dateStr) return false;
  var d=new Date(dateStr);
  var min=new Date();min.setHours(0,0,0,0);min.setDate(min.getDate()+14);
  return d>=min;
};

// ===== STEP 1 SUBMIT: validate form → save customer → show step 2 =====
MG._submitReservation = async function(){
  var name=document.getElementById('rez-name'),email=document.getElementById('rez-email'),
    phone=document.getElementById('rez-phone'),street=document.getElementById('rez-street'),
    city=document.getElementById('rez-city'),zip=document.getElementById('rez-zip'),
    country=document.getElementById('rez-country'),agree=document.getElementById('rez-agree-vop');

  // Enhanced validation
  if(!name||!MG._isNameValid(name.value)){
    alert('Zadejte platné jméno a příjmení (min. 2 písmena, bez číslic).');return;}
  if(!street||!street.value||street.value.trim().length<3){
    alert('Zadejte ulici a číslo popisné (min. 3 znaky).');return;}
  if(!city||!city.value||city.value.trim().length<2){
    alert('Zadejte město (min. 2 znaky).');return;}
  if(!zip||!zip.value){
    alert('Vyplňte prosím PSČ.');return;}
  if(!email||!email.value||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.value.trim())){
    alert('Zadejte platnou e-mailovou adresu.');return;}
  if(!phone||!MG._isPhoneValid(phone.value)){
    alert('Zadejte telefon v mezinárodním formátu (např. +420 777 000 000).');return;}
  if(!agree||!agree.checked){alert('Pro pokračování musíte souhlasit s obchodními podmínkami.');return;}
  var r=MG._rez;
  if(!r.startDate||!r.endDate){alert('Vyberte prosím termín v kalendáři.');return;}
  var mId=r.motoId||r.selectedMotoId;
  if(!mId){alert('Vyberte prosím motorku.');return;}
  var ptEl=document.getElementById('rez-pickup-time');
  if(!ptEl||!ptEl.value){alert('Vyplňte prosím čas převzetí nebo přistavení motorky.');return;}
  if(!MG._rezValidatePickupTime()){
    var isDel=document.getElementById('rez-delivery')&&document.getElementById('rez-delivery').checked;
    alert(isDel?'Při přistavení je nejdříve možný čas aktuální čas + 6 hodin.':'Nejdříve možný čas převzetí je aktuální čas + 1 hodina.');return;}
  var extras=[];
  if(document.getElementById('rez-eq-passenger')&&document.getElementById('rez-eq-passenger').checked) extras.push({name:'Výbava spolujezdce',unit_price:690});
  if(document.getElementById('rez-eq-boots-rider')&&document.getElementById('rez-eq-boots-rider').checked) extras.push({name:'Boty řidič',unit_price:290});
  if(document.getElementById('rez-eq-boots-passenger')&&document.getElementById('rez-eq-boots-passenger').checked) extras.push({name:'Boty spolujezdce',unit_price:290});
  var deliveryAddr=null,returnAddr=null;
  if(document.getElementById('rez-delivery')&&document.getElementById('rez-delivery').checked)
    deliveryAddr=(document.getElementById('rez-delivery-address')||{}).value||null;
  var retO=document.getElementById('rez-return-other'),retS=document.getElementById('rez-return-same-as-delivery');
  if(retO&&retO.checked) returnAddr=(document.getElementById('rez-return-address')||{}).value||null;
  else if(retS&&retS.checked&&deliveryAddr) returnAddr=deliveryAddr;
  if(deliveryAddr) extras.push({name:'Přistavení motorky (nakládka+vykládka+doprava)',unit_price:1000});
  if(returnAddr) extras.push({name:'Vrácení motorky (nakládka+vykládka+doprava)',unit_price:1000});

  MG._rez.formData={motoId:mId,name:name.value,email:email.value,phone:phone.value,
    street:street.value,city:city.value,zip:zip.value,country:(country&&country.value)||'Česká republika',
    note:(document.getElementById('rez-note')||{}).value||'',pickupTime:ptEl.value,
    deliveryAddr:deliveryAddr,returnAddr:returnAddr,extras:extras,
    appliedCodes:(MG._rez.appliedCodes&&MG._rez.appliedCodes.length)?MG._rez.appliedCodes:[],
    discountAmt:MG._rez.discountAmt||0};

  // Save customer to DB immediately (even if they don't finish payment)
  try {
    // Prepare discount params
    var codes = MG._rez.formData.appliedCodes || [];
    var discAmt = MG._rez.formData.discountAmt || 0;
    var promoCode = null, voucherId = null;
    for(var ci=0;ci<codes.length;ci++){
      if(codes[ci].type==='promo') promoCode = codes[ci].code;
      if(codes[ci].type==='voucher') voucherId = codes[ci].id;
    }
    var rpcParams = {
      p_moto_id: mId, p_start_date: r.startDate, p_end_date: r.endDate,
      p_name: name.value, p_email: email.value, p_phone: phone.value,
      p_street: street.value||'', p_city: city.value||'', p_zip: zip.value||'',
      p_country: (country&&country.value)||'CZ',
      p_note: MG._rez.formData.note||'',
      p_pickup_time: ptEl.value ? ptEl.value+':00' : null,
      p_delivery_address: deliveryAddr, p_return_address: returnAddr,
      p_extras: extras,
      p_discount_amount: discAmt||0,
      p_discount_code: codes.length?codes.map(function(c){return c.code;}).join(', '):null,
      p_promo_code: promoCode,
      p_voucher_id: voucherId
    };
    console.log('[REZ] create_web_booking params:', rpcParams);
    var regRes = await window.sb.rpc('create_web_booking', rpcParams);
    if(regRes.error){
      console.error('[REZ] create_web_booking error:', regRes.error);
      var emsg = regRes.error.message || '';
      if(emsg.indexOf('Booking overlap') !== -1) alert('Tuto motorku pr\u00e1v\u011b rezervoval jin\u00fd z\u00e1kazn\u00edk ve stejn\u00e9m term\u00ednu. Zvolte pros\u00edm jin\u00fd term\u00edn nebo jinou motorku.');
      else if(emsg.indexOf('overlapping booking') !== -1) alert('V tomto term\u00ednu ji\u017e m\u00e1te jinou aktivn\u00ed rezervaci.');
      else alert('Chyba: '+emsg);
      if(btn){btn.disabled=false;btn.textContent='Pokra\u010dovat k platb\u011b';}
      return;
    }
    var regData = regRes.data;
    if(regData && regData.error){ alert(regData.error); return; }
    if(regData){
      MG._rez.bookingId = regData.booking_id;
      MG._rez.userId = regData.user_id;
      MG._rez.bookingAmount = regData.amount;
      // Mark registration source as web
      if(regData.user_id){
        window.sb.from('profiles').update({registration_source:'web'}).eq('id',regData.user_id).then(function(){});
      }
    }
  } catch(e){ alert('Chyba při ukládání: '+e.message); return; }

  // Schedule abandoned email after 5 minutes if payment not completed
  if(MG._rez.bookingId && MG._rez.formData){
    MG._rez._abandonedTimer = setTimeout(function(){
      // Check if still pending (not yet paid)
      if(!MG._rez._paymentDone){
        var d = MG._rez.formData;
        var moto = MG._rez.motos.find(function(m){return m.id===d.motoId;});
        fetch(window.MOTOGO_CONFIG.SUPABASE_URL+'/functions/v1/send-booking-email',{
          method:'POST',
          headers:{'Content-Type':'application/json','apikey':window.MOTOGO_CONFIG.SUPABASE_ANON_KEY},
          body:JSON.stringify({
            type:'booking_abandoned',
            booking_id:MG._rez.bookingId,
            customer_email:d.email,
            customer_name:d.name,
            motorcycle:moto?moto.model:'',
            source:'web',
            resume_link:'https://motogo24.cz/#/rezervace?resume='+MG._rez.bookingId
          })
        }).catch(function(){});
      }
    }, 5*60*1000); // 5 minut
  }

  MG._rezShowStep2();
};

// ===== STEP 2: Doklady + QR kód + Náhled faktury =====
MG._rezShowStep2 = function(){
  var form=document.getElementById('rez-form');if(!form)return;
  // Hide calendar, banner, moto select — only show on step 1
  ['rez-intro','rez-calendar','rez-date-banner','rez-avail-select','rez-moto-select'].forEach(function(id){
    var el=document.getElementById(id);if(el)el.style.display='none';
  });
  var d=MG._rez.formData,r=MG._rez;
  var moto=r.motos.find(function(m){return m.id===d.motoId;});
  var motoName=moto?moto.model:'—';
  var base=0,extT=0,disc=0,total=0,rows='';
  if(MG._rez._isResume){
    // Resume mode: use stored total from DB
    total=MG._rez.bookingAmount||0;
    rows='<tr><td style="padding:5px 0;border-bottom:1px solid #eee">Rezervace: '+motoName+'</td>'+
      '<td style="padding:5px 0;border-bottom:1px solid #eee;text-align:right">'+MG.formatPrice(total)+'</td></tr>';
  } else {
    base=(moto&&r.startDate&&r.endDate)?MG.calcPrice(moto,r.startDate,r.endDate):0;
    d.extras.forEach(function(e){extT+=e.unit_price;});
    disc=d.discountAmt||0;
    total=Math.max(0,base+extT-disc);
    rows='<tr><td style="padding:5px 0;border-bottom:1px solid #eee">Pronájem: '+motoName+'</td>'+
      '<td style="padding:5px 0;border-bottom:1px solid #eee;text-align:right">'+MG.formatPrice(base)+'</td></tr>';
    d.extras.forEach(function(e){rows+='<tr><td style="padding:5px 0;border-bottom:1px solid #eee">'+e.name+'</td>'+
      '<td style="padding:5px 0;border-bottom:1px solid #eee;text-align:right">'+MG.formatPrice(e.unit_price)+'</td></tr>';});
    if(disc>0){var cl=(d.appliedCodes||[]).map(function(c){return c.code;}).join('+');
      rows+='<tr><td style="padding:5px 0;border-bottom:1px solid #eee;color:#1a8c1a">Sleva ('+cl+')</td>'+
      '<td style="padding:5px 0;border-bottom:1px solid #eee;text-align:right;color:#1a8c1a">−'+MG.formatPrice(disc)+'</td></tr>';}
  }

  var isMob=MG._isMobile();
  var resumeLink=MG._rez.bookingId?'https://motogo24.cz/#/rezervace?resume='+MG._rez.bookingId:'';

  // QR code section (desktop only) — allows customer to continue on mobile
  var qrSection='';
  if(!isMob && resumeLink){
    qrSection='<div style="background:#f0faf5;border:2px dashed #74FB71;border-radius:12px;padding:1.5rem;margin:1.5rem 0;text-align:center">'+
      '<h3 style="margin:0 0 .5rem;color:#1a2e22">Dokončete pohodlně na mobilu</h3>'+
      '<p style="color:#555;font-size:.9rem;margin-bottom:.75rem">Naskenujte QR kód fotoaparátem telefonu:</p>'+
      '<div style="margin:.5rem 0"><img src="'+MG._qrCodeUrl(resumeLink)+'" alt="QR kód pro dokončení na mobilu" style="width:180px;height:180px;border-radius:8px;border:1px solid #e0e0e0"></div>'+
      '<div style="font-size:.85rem;color:#374151;text-align:left;display:inline-block;margin:.5rem 0">'+
      '<div style="margin:.2rem 0">&#10003; Platba přes Apple Pay / Google Pay</div>'+
      '<div style="margin:.2rem 0">&#10003; Sken dokladů fotoaparátem (rychlejší odbavení)</div>'+
      '<div style="margin:.2rem 0">&#10003; Možnost využít autonomní pobočku</div></div>'+
      '<p style="color:#9ca3af;font-size:.8rem;margin-top:.5rem">Rezervace zůstane aktivní 4 hodiny</p></div>';
  }

  // Mobile: button goes to Mindee step; Desktop: button goes to Stripe payment
  var payBtnLabel=isMob?'Ověřit doklady a zaplatit':'Pokračovat k platbě';
  var payBtnAction=isMob?'MG._rezShowMindeeStep()':'MG._rezSubmitPayment()';

  form.innerHTML=
    '<h2 style="margin-top:1rem">Ověření totožnosti a řidičského oprávnění</h2>'+
    '<p style="color:#555;line-height:1.6;margin-bottom:1rem">Pro přípravu nájemní smlouvy prosíme o vyplnění údajů z dokladu totožnosti a řidičského průkazu. Originály budou zkontrolovány při převzetí motocyklu.</p>'+
    '<h3>Doklad totožnosti</h3><div class="checkboxes" style="margin:.5rem 0">'+
    '<div><input type="radio" id="rez-doc-op" name="rez-doc-type" value="op" checked><label for="rez-doc-op">Občanský průkaz</label></div>'+
    '<div><input type="radio" id="rez-doc-pas" name="rez-doc-type" value="pas"><label for="rez-doc-pas">Cestovní pas</label></div></div>'+
    '<input type="text" id="rez-doc-number" placeholder="* Číslo dokladu" required autocomplete="off"'+(MG._rez._docNumber?' value="'+MG._rez._docNumber+'"':'')+'>'+
    '<h3 style="margin-top:1rem">Řidičský průkaz</h3>'+
    '<input type="text" id="rez-license-number" placeholder="* Číslo řidičského průkazu" required autocomplete="off"'+(MG._rez._licenseNumber?' value="'+MG._rez._licenseNumber+'"':'')+'>'+
    '<div style="display:flex;gap:.75rem;margin-top:.5rem">'+
    '<div style="flex:1"><label style="font-size:.85rem;font-weight:600;color:#374151">* Skupina ŘP</label>'+
    '<select id="rez-license-group" required style="width:100%;padding:.55rem .75rem;border:1px solid #d1d5db;border-radius:8px;font-size:.9rem;margin-top:.25rem">'+
    '<option value="">— Vyberte —</option><option value="A1">A1</option><option value="A2">A2</option><option value="A">A</option></select></div>'+
    '<div style="flex:1"><label style="font-size:.85rem;font-weight:600;color:#374151">* Platnost ŘP do</label>'+
    '<input type="date" id="rez-license-expiry" required style="width:100%;padding:.55rem .75rem;border:1px solid #d1d5db;border-radius:8px;font-size:.9rem;margin-top:.25rem"></div></div>'+
    '<div class="checkboxes" style="margin:1rem 0"><div class="agreement gr2"><input type="checkbox" id="rez-license-confirm" required'+(MG._rez._docsValidated?' checked':'')+'>'+
    '<div>* Potvrzuji, že jsem držitelem platného řidičského oprávnění a splňuji zákonné podmínky k řízení rezervovaného motocyklu.</div></div></div>'+
    qrSection+
    '<hr style="border:none;border-top:2px solid #74FB71;margin:1.5rem 0">'+
    '<h2>Náhled zálohové faktury</h2>'+
    '<div style="background:#f9f9f9;border:1px solid #e0e0e0;border-radius:10px;padding:1rem;margin-bottom:1rem">'+
    '<table style="width:100%;border-collapse:collapse;font-size:.88rem;color:#333">'+
    '<tr><td style="padding:5px 0;font-weight:700;border-bottom:1px solid #ccc">Položka</td>'+
    '<td style="padding:5px 0;font-weight:700;border-bottom:1px solid #ccc;text-align:right">Cena</td></tr>'+rows+'</table>'+
    '<div style="display:flex;justify-content:space-between;align-items:center;margin-top:10px;padding-top:10px;border-top:2px solid #1a8c1a">'+
    '<strong>Celkem k úhradě</strong><strong style="color:#1a8c1a">'+MG.formatPrice(total)+'</strong></div></div>'+
    '<div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:10px;padding:.75rem;margin-bottom:1rem;font-size:.85rem;color:#374151">'+
    '<strong>Odběratel:</strong> '+d.name+' | '+d.email+' | '+(d.phone||'')+'<br>'+
    (d.street?d.street+', ':'')+(d.zip?d.zip+' ':'')+(d.city||'')+'<br>'+
    '<strong>Motorka:</strong> '+motoName+' | <strong>Termín:</strong> '+MG.formatDate(r.startDate)+' – '+MG.formatDate(r.endDate)+
    (d.deliveryAddr?'<br><strong>Přistavení:</strong> '+d.deliveryAddr:'')+
    (d.returnAddr?'<br><strong>Vrácení:</strong> '+d.returnAddr:'')+'</div>'+
    '<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:1rem;margin-top:1rem">'+
    (MG._rez._isResume?'<a class="btn btndark" href="#/rezervace">&#8592; Nová rezervace</a>':
    '<button class="btn btndark" onclick="MG._rezBackToStep1()">&#8592; Zpět</button>')+
    '<div style="display:flex;align-items:center;gap:1rem">'+
    '<div style="background:#74FB71;color:#0b0b0b;padding:.6rem 1.2rem;border-radius:25px;font-weight:800;font-size:1.05rem">'+MG.formatPrice(total)+'</div>'+
    '<button class="btn btngreen" onclick="'+payBtnAction+'">'+payBtnLabel+'</button></div></div>';
  window.scrollTo({top:form.offsetTop-80,behavior:'smooth'});
};

// ===== BACK TO STEP 1 =====
MG._rezBackToStep1 = function(){
  var form=document.getElementById('rez-form');if(!form)return;
  // Show calendar elements again
  ['rez-intro','rez-calendar','rez-date-banner','rez-moto-select'].forEach(function(id){
    var el=document.getElementById(id);if(el)el.style.display='';
  });
  form.outerHTML=MG._rezFormHtml();MG._rezInitFormEvents();
  var d=MG._rez.formData;if(!d)return;
  var f=function(id,v){var e=document.getElementById(id);if(e&&v)e.value=v;};
  f('rez-name',d.name);f('rez-email',d.email);f('rez-phone',d.phone);
  f('rez-street',d.street);f('rez-city',d.city);f('rez-zip',d.zip);
  f('rez-country',d.country);f('rez-note',d.note);f('rez-pickup-time',d.pickupTime);
  MG._rezUpdatePrice();
};

// Mindee scan + Stripe payment → pages-rezervace-scan.js
