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
  var btn=document.querySelector('#rez-form .btn.btngreen');
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
  // Fee = 1000 Kč + 40 Kč/km (km = vzdalenost od pobocky Mezna 9, spoctena pres Mapy.cz)
  if(deliveryAddr){
    var dKm = MG._rez.deliveryDistanceKm;
    var dFee = MG._calcDeliveryFee(dKm);
    var dLbl = (typeof dKm==='number') ? ' ('+MG.formatPrice(1000)+' + '+MG.formatPrice(40)+' × '+dKm.toFixed(1).replace('.',',')+' km)' : '';
    extras.push({name:'Přistavení motorky'+dLbl,unit_price:dFee});
  }
  if(returnAddr){
    var rKm = (retS&&retS.checked) ? MG._rez.deliveryDistanceKm : MG._rez.returnDistanceKm;
    var rFee = MG._calcDeliveryFee(rKm);
    var rLbl = (typeof rKm==='number') ? ' ('+MG.formatPrice(1000)+' + '+MG.formatPrice(40)+' × '+rKm.toFixed(1).replace('.',',')+' km)' : '';
    extras.push({name:'Vrácení motorky'+rLbl,unit_price:rFee});
  }

  // Collect sizes from new chip UI
  var rs = (MG._rez.sizes && MG._rez.sizes.rider) || {};
  var ps = (MG._rez.sizes && MG._rez.sizes.passenger) || {};
  // If "own gear" toggled — clear rider sizes (force rental skipped)
  var ownGearEl = document.getElementById('rez-own-gear');
  if(ownGearEl && ownGearEl.checked){ rs = {}; }

  MG._rez.formData={motoId:mId,name:name.value,email:email.value,phone:phone.value,
    street:street.value,city:city.value,zip:zip.value,country:(country&&country.value)||'Česká republika',
    note:'',pickupTime:ptEl.value,
    deliveryAddr:deliveryAddr,returnAddr:returnAddr,extras:extras,
    appliedCodes:(MG._rez.appliedCodes&&MG._rez.appliedCodes.length)?MG._rez.appliedCodes:[],
    discountAmt:MG._rez.discountAmt||0,
    riderSizes: rs, passengerSizes: ps};

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
      p_note: '',
      p_pickup_time: ptEl.value ? ptEl.value+':00' : null,
      p_delivery_address: deliveryAddr, p_return_address: returnAddr,
      p_extras: extras,
      p_discount_amount: discAmt||0,
      p_discount_code: codes.length?codes.map(function(c){return c.code;}).join(', '):null,
      p_promo_code: promoCode,
      p_voucher_id: voucherId,
      p_license_group: (document.getElementById('rez-license-group')||{}).value||null,
      // Driver gear sizes (RPC supports since 2026-04-11)
      p_helmet_size: rs.helmet||null,
      p_jacket_size: rs.jacket||null,
      p_pants_size:  rs.pants||null,
      p_boots_size:  rs.boots||null,
      p_gloves_size: rs.gloves||null
    };
    // Passenger gear sizes — pošli jen pokud je RPC rozšířený (po aplikaci SQL migrace)
    var hasPassengerSizes = !!(ps.helmet||ps.jacket||ps.gloves||ps.boots);
    if(hasPassengerSizes){
      rpcParams.p_passenger_helmet_size = ps.helmet||null;
      rpcParams.p_passenger_jacket_size = ps.jacket||null;
      rpcParams.p_passenger_gloves_size = ps.gloves||null;
      rpcParams.p_passenger_boots_size  = ps.boots||null;
    }
    // Cas vraceni — uloz jen pokud se vraci mimo provozovnu
    // (return-other = vlastni adresa vraceni, nebo delivery + same-as-delivery = vraci na adrese pristaveni)
    var isReturnOffsite = (retO && retO.checked) ||
      (document.getElementById('rez-delivery') && document.getElementById('rez-delivery').checked &&
       retS && retS.checked);
    if(isReturnOffsite){
      var rtEl = document.getElementById('rez-return-time');
      if(rtEl && rtEl.value) rpcParams.p_return_time = rtEl.value;
    }
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
    if(regData && regData.error){
      alert(regData.error);
      if(btn){btn.disabled=false;btn.textContent='Pokra\u010dovat k platb\u011b';}
      return;
    }
    if(regData){
      MG._rez.bookingId = regData.booking_id;
      MG._rez.userId = regData.user_id;
      MG._rez.bookingAmount = regData.amount;
      // Uložit stav formuláře do sessionStorage (přežije navigaci zpět)
      try { sessionStorage.setItem('mg_rez_form', JSON.stringify({
        formData: MG._rez.formData, bookingId: MG._rez.bookingId,
        userId: MG._rez.userId, bookingAmount: MG._rez.bookingAmount,
        startDate: MG._rez.startDate, endDate: MG._rez.endDate,
        motoId: MG._rez.motoId, appliedCodes: MG._rez.appliedCodes,
        discountAmt: MG._rez.discountAmt,
        sizes: MG._rez.sizes,
        _docNumber: MG._rez._docNumber, _licenseNumber: MG._rez._licenseNumber,
        _docsValidated: MG._rez._docsValidated,
        _passwordSet: MG._rez._passwordSet||false
      })); } catch(e2){}
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
            resume_link:'https://motogo24.com/rezervace?resume='+MG._rez.bookingId
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
  ['rez-intro','rez-step-moto','rez-step-cal','rez-calendar','rez-date-banner','rez-avail-select','rez-moto-select'].forEach(function(id){
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
  // TEST: QR cílí na motogo24.com pro ověření Apple Pay / Google Pay flow přes Stripe na mobilu
  var resumeLink=MG._rez.bookingId?'https://motogo24.com/rezervace?resume='+MG._rez.bookingId:'';

  // QR code section (desktop only) — allows customer to continue on mobile
  var qrSection='';
  if(!isMob && resumeLink){
    qrSection='<div style="background:#f0faf5;border:2px dashed #74FB71;border-radius:10px;padding:.75rem 1rem;margin:.75rem 0;display:flex;align-items:center;gap:1rem;flex-wrap:wrap">'+
      '<div style="flex-shrink:0"><img src="'+MG._qrCodeUrl(resumeLink)+'" alt="QR kód" style="width:100px;height:100px;border-radius:8px;border:1px solid #e0e0e0"></div>'+
      '<div style="flex:1;min-width:200px">'+
      '<h3 style="margin:0 0 .2rem;color:#1a2e22;font-size:.9rem">Dokončete na mobilu</h3>'+
      '<div style="font-size:.78rem;color:#374151;line-height:1.5">'+
      '<div>&#10003; Apple Pay / Google Pay</div>'+
      '<div>&#10003; Sken dokladů fotoaparátem</div>'+
      '<div>&#10003; Autonomní pobočka</div></div>'+
      '<p style="color:#9ca3af;font-size:.75rem;margin:.3rem 0 0">QR platný 4 hodiny</p></div></div>';
  }

  // Mobile: button goes to Mindee step; Desktop: button goes to Stripe payment
  var payBtnLabel=isMob?'Ověřit doklady a zaplatit':'Pokračovat k platbě';
  var payBtnAction=isMob?'MG._rezShowMindeeStep()':'MG._rezSubmitPayment()';

  form.innerHTML=
    '<h2 style="margin-top:.5rem;margin-bottom:.3rem">Ověření totožnosti a řidičského oprávnění</h2>'+
    '<p style="color:#555;line-height:1.5;margin-bottom:.5rem;font-size:.9rem">Pro přípravu nájemní smlouvy vyplňte údaje z dokladu totožnosti a řidičského průkazu.</p>'+
    '<h3 style="margin-bottom:.2rem">Doklad totožnosti</h3><div class="checkboxes" style="margin:.3rem 0">'+
    '<div><input type="radio" id="rez-doc-op" name="rez-doc-type" value="op" checked><label for="rez-doc-op">Občanský průkaz</label></div>'+
    '<div><input type="radio" id="rez-doc-pas" name="rez-doc-type" value="pas"><label for="rez-doc-pas">Cestovní pas</label></div></div>'+
    '<input type="text" id="rez-doc-number" placeholder="* Číslo dokladu" required autocomplete="off"'+(MG._rez._docNumber?' value="'+MG._rez._docNumber+'"':'')+'>'+
    '<h3 style="margin-top:.5rem;margin-bottom:.2rem">Řidičský průkaz</h3>'+
    '<div id="rez-license-num-wrap"><input type="text" id="rez-license-number" placeholder="* Číslo řidičského průkazu" autocomplete="off"'+(MG._rez._licenseNumber?' value="'+MG._rez._licenseNumber+'"':'')+'></div>'+
    '<div style="margin-top:.5rem">'+
    '<label style="font-size:.85rem;font-weight:600;color:#374151;display:block;margin-bottom:.35rem">* Skupina ŘP</label>'+
    '<div id="rez-license-group-chips" style="display:flex;gap:.5rem;flex-wrap:wrap">'+
    '<button type="button" class="lic-chip" data-val="A2">A2</button>'+
    '<button type="button" class="lic-chip" data-val="A">A</button>'+
    '<button type="button" class="lic-chip" data-val="N">Bez ŘP</button>'+
    '</div>'+
    '<input type="hidden" id="rez-license-group" value="">'+
    '</div>'+
    '<div id="rez-license-expiry-wrap" style="margin-top:.75rem">'+
    '<label style="font-size:.85rem;font-weight:600;color:#374151;display:block;margin-bottom:.35rem">* Platnost ŘP do</label>'+
    '<div style="display:flex;gap:.4rem;align-items:center">'+
    '<select id="rez-lic-day" class="lic-date-sel" style="flex:1;padding:.55rem .5rem;border:1px solid #d1d5db;border-radius:8px;font-size:.95rem;background:#fff;font-weight:600"></select>'+
    '<select id="rez-lic-month" class="lic-date-sel" style="flex:1.6;padding:.55rem .5rem;border:1px solid #d1d5db;border-radius:8px;font-size:.95rem;background:#fff;font-weight:600"></select>'+
    '<select id="rez-lic-year" class="lic-date-sel" style="flex:1.2;padding:.55rem .5rem;border:1px solid #d1d5db;border-radius:8px;font-size:.95rem;background:#fff;font-weight:600"></select>'+
    '</div>'+
    '<div style="display:flex;gap:.4rem;flex-wrap:wrap;margin-top:.4rem">'+
    '<button type="button" class="lic-quick" data-years="5">+5 let</button>'+
    '<button type="button" class="lic-quick" data-years="10">+10 let</button>'+
    '<button type="button" class="lic-quick" data-years="15">+15 let</button>'+
    '</div>'+
    '<input type="hidden" id="rez-license-expiry" value="">'+
    '</div>'+
    '<div id="rez-license-confirm-wrap" class="checkboxes" style="margin:1rem 0"><div class="agreement gr2"><input type="checkbox" id="rez-license-confirm"'+(MG._rez._docsValidated?' checked':'')+'>'+
    '<div>* Potvrzuji, že jsem držitelem platného řidičského oprávnění a splňuji zákonné podmínky k řízení rezervovaného motocyklu.</div></div></div>'+

    // Optional document upload section (web)
    (!isMob?
    '<div style="background:#f0faf5;border:1px solid #d4e8e0;border-radius:10px;padding:1rem;margin:1.5rem 0">'+
    '<h3 style="margin:0 0 .5rem">Nahrání dokladů <span style="font-size:.8rem;color:#888;font-weight:400">(nepovinné)</span></h3>'+
    '<p style="color:#555;font-size:.85rem;line-height:1.5;margin-bottom:.75rem">Můžete nahrát fotografie dokladů pro rychlejší odbavení. Snímky budou automaticky rozpoznány a údaje doplněny do formuláře.</p>'+

    '<div style="display:flex;gap:1rem;flex-wrap:wrap">'+
    '<div style="flex:1;min-width:240px;background:#fff;border:1px solid #e0e0e0;border-radius:8px;padding:.75rem">'+
    '<div style="font-weight:600;margin-bottom:.5rem">&#128196; Doklad totožnosti</div>'+
    '<div id="webdoc-id-status"></div>'+
    '<div style="display:flex;gap:.5rem;flex-wrap:wrap;margin-top:.5rem">'+
    '<button class="btn btngreen-small" onclick="MG._rezUploadDoc(\'id\')" style="font-size:.8rem">Nahrát soubor</button>'+
    '<button class="btn btngreen-small" onclick="MG._rezCaptureDoc(\'id\')" style="font-size:.8rem">Vyfotit</button></div></div>'+

    '<div style="flex:1;min-width:240px;background:#fff;border:1px solid #e0e0e0;border-radius:8px;padding:.75rem">'+
    '<div style="font-weight:600;margin-bottom:.5rem">&#128179; Řidičský průkaz</div>'+
    '<div id="webdoc-dl-status"></div>'+
    '<div style="display:flex;gap:.5rem;flex-wrap:wrap;margin-top:.5rem">'+
    '<button class="btn btngreen-small" onclick="MG._rezUploadDoc(\'dl\')" style="font-size:.8rem">Nahrát soubor</button>'+
    '<button class="btn btngreen-small" onclick="MG._rezCaptureDoc(\'dl\')" style="font-size:.8rem">Vyfotit</button></div></div>'+
    '</div></div>':'')+

    '<div style="background:#f0faf5;border:1px solid #74FB71;border-radius:10px;padding:.75rem 1rem;margin:.75rem 0">'+
    '<h3 style="margin:0 0 .3rem;font-size:.9rem;color:#1a3a2a">Heslo pro správu rezervace</h3>'+
    '<p style="color:#555;font-size:.82rem;margin:0 0 .5rem">Pro úpravu rezervace a přihlášení do aplikace MotoGo24.</p>'+
    '<div class="gr2" style="margin:0"><input type="password" id="rez-password" name="new-password" placeholder="* Heslo (min. 8 znaků)" required autocomplete="new-password" minlength="8" style="border-color:#74FB71"'+(MG._rez._passwordSet?' value="********" disabled':'')+'>'+
    '<input type="password" id="rez-password-confirm" name="new-password" placeholder="* Potvrzení hesla" required autocomplete="new-password" minlength="8" style="border-color:#74FB71"'+(MG._rez._passwordSet?' value="********" disabled':'')+'></div></div>'+
    qrSection+
    '<hr style="border:none;border-top:2px solid #74FB71;margin:.75rem 0">'+
    '<h2 style="margin-bottom:.3rem">Náhled zálohové faktury</h2>'+
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
    (MG._rez._isResume?'<a class="btn btndark" href="/rezervace">&#8592; Nová rezervace</a>':
    '<button class="btn btndark" onclick="MG._rezBackToStep1()">&#8592; Zpět</button>')+
    '<div style="display:flex;align-items:center;gap:1rem">'+
    '<div style="background:#74FB71;color:#0b0b0b;padding:.6rem 1.2rem;border-radius:25px;font-weight:800;font-size:1.05rem">'+MG.formatPrice(total)+'</div>'+
    '<button class="btn btngreen" onclick="'+payBtnAction+'">'+payBtnLabel+'</button></div></div>';
  MG._rezInitLicenseUI();
  window.scrollTo({top:form.offsetTop-80,behavior:'smooth'});
};

// ===== LICENSE UI: chips for group + custom date picker =====
MG._rezInitLicenseUI = function(){
  // Inject styles once
  if(!document.getElementById('mg-lic-styles')){
    var st=document.createElement('style'); st.id='mg-lic-styles';
    st.textContent =
      '.lic-chip{padding:.55rem 1rem;border:1.5px solid #d1d5db;background:#fff;border-radius:999px;font-size:.95rem;font-weight:700;cursor:pointer;color:#374151;transition:all .15s;min-width:72px}'+
      '.lic-chip:hover{border-color:#74FB71;background:#f0faf5}'+
      '.lic-chip.active{background:#74FB71;border-color:#1a8c1a;color:#0b0b0b;box-shadow:0 1px 4px rgba(26,140,26,.25)}'+
      '.lic-quick{padding:.35rem .75rem;border:1px solid #d1d5db;background:#f9fafb;border-radius:6px;font-size:.8rem;font-weight:600;cursor:pointer;color:#374151;transition:all .15s}'+
      '.lic-quick:hover{border-color:#74FB71;background:#f0faf5;color:#1a8c1a}'+
      '.lic-date-sel:focus{outline:none;border-color:#74FB71;box-shadow:0 0 0 3px rgba(116,251,113,.25)}';
    document.head.appendChild(st);
  }

  // ---- Group chips ----
  var hidden = document.getElementById('rez-license-group');
  var expiryWrap = document.getElementById('rez-license-expiry-wrap');
  var chips = document.querySelectorAll('#rez-license-group-chips .lic-chip');
  var pre = (MG._rez && MG._rez.formData && MG._rez.formData._licGroup) || '';
  var numWrap = document.getElementById('rez-license-num-wrap');
  var confirmWrap = document.getElementById('rez-license-confirm-wrap');
  function applyGroup(val){
    hidden.value = val;
    chips.forEach(function(c){ c.classList.toggle('active', c.dataset.val === val); });
    var hide = (val === 'N');
    if(expiryWrap) expiryWrap.style.display = hide ? 'none' : '';
    if(numWrap) numWrap.style.display = hide ? 'none' : '';
    if(confirmWrap) confirmWrap.style.display = hide ? 'none' : '';
  }
  chips.forEach(function(c){
    c.addEventListener('click', function(){ applyGroup(c.dataset.val); });
  });
  if(pre) applyGroup(pre);

  // ---- Date selects ----
  var dSel=document.getElementById('rez-lic-day');
  var mSel=document.getElementById('rez-lic-month');
  var ySel=document.getElementById('rez-lic-year');
  var hiddenExp=document.getElementById('rez-license-expiry');
  if(!dSel||!mSel||!ySel) return;

  var now=new Date(); var thisYear=now.getFullYear();
  var monthNames=['leden','únor','březen','duben','květen','červen','červenec','srpen','září','říjen','listopad','prosinec'];

  function opt(val,label,sel){ var o=document.createElement('option'); o.value=val; o.textContent=label; if(sel) o.selected=true; return o; }

  // Day select
  dSel.appendChild(opt('','Den',true));
  for(var i=1;i<=31;i++) dSel.appendChild(opt(i, i<10?('0'+i):(''+i)));
  // Month select
  mSel.appendChild(opt('','Měsíc',true));
  for(var m=1;m<=12;m++){ var lbl=(m<10?('0'+m):(''+m))+' — '+monthNames[m-1]; mSel.appendChild(opt(m, lbl)); }
  // Year select (this year .. this year + 20)
  ySel.appendChild(opt('','Rok',true));
  for(var y=thisYear; y<=thisYear+20; y++) ySel.appendChild(opt(y, y));

  function syncExpiry(){
    var d=dSel.value, m=mSel.value, y=ySel.value;
    if(!d||!m||!y){ hiddenExp.value=''; return; }
    var iso = y+'-'+(m<10?('0'+m):(''+m))+'-'+(d<10?('0'+d):(''+d));
    var test=new Date(iso);
    if(isNaN(test.getTime())){ hiddenExp.value=''; return; }
    if(test.getFullYear()!=y || (test.getMonth()+1)!=parseInt(m,10) || test.getDate()!=parseInt(d,10)){
      hiddenExp.value=''; return;
    }
    hiddenExp.value = iso;
  }
  [dSel,mSel,ySel].forEach(function(s){ s.addEventListener('change', syncExpiry); });

  // Quick "+N let" buttons → set today + N years
  document.querySelectorAll('.lic-quick').forEach(function(b){
    b.addEventListener('click', function(){
      var yrs=parseInt(b.dataset.years,10)||0;
      var t=new Date(); t.setFullYear(t.getFullYear()+yrs);
      dSel.value=t.getDate(); mSel.value=t.getMonth()+1; ySel.value=t.getFullYear();
      syncExpiry();
    });
  });

  // Restore previous value if any
  var prev = (MG._rez && MG._rez.formData && MG._rez.formData._licExpiry) || '';
  if(prev && /^\d{4}-\d{2}-\d{2}$/.test(prev)){
    var pp=prev.split('-');
    ySel.value=parseInt(pp[0],10); mSel.value=parseInt(pp[1],10); dSel.value=parseInt(pp[2],10);
    syncExpiry();
  }
};

// ===== BACK TO STEP 1 =====
MG._rezBackToStep1 = function(){
  var form=document.getElementById('rez-form');if(!form)return;
  // Show calendar elements again
  ['rez-intro','rez-step-moto','rez-step-cal','rez-calendar','rez-date-banner','rez-moto-select'].forEach(function(id){
    var el=document.getElementById(id);if(el)el.style.display='';
  });
  form.outerHTML=MG._rezFormHtml();MG._rezInitFormEvents();
  var d=MG._rez.formData;if(!d)return;
  var f=function(id,v){var e=document.getElementById(id);if(e&&v)e.value=v;};
  f('rez-name',d.name);f('rez-email',d.email);f('rez-phone',d.phone);
  f('rez-street',d.street);f('rez-city',d.city);f('rez-zip',d.zip);
  f('rez-country',d.country);f('rez-pickup-time',d.pickupTime);
  // Trigger pickup-time chip highlight (zachova default 09:00 i puvodni vyber)
  var ptInpB = document.getElementById('rez-pickup-time');
  if(ptInpB && ptInpB.value){ ptInpB.dispatchEvent(new Event('change',{bubbles:true})); }

  // Restore sizes UI
  MG._rezRestoreSizesUI();
  MG._rezUpdatePrice();
};

// ===== RESTORE SIZES UI from MG._rez.sizes =====
MG._rezRestoreSizesUI = function(){
  var s = MG._rez.sizes || {rider:{}, passenger:{}};
  // Tick parent gear card if any size selected
  var groups = {
    'rez-eq-rider-gear': ['rider', ['helmet','jacket','gloves','pants']],
    'rez-eq-passenger':  ['passenger', ['helmet','jacket','gloves']],
    'rez-eq-boots-rider': ['rider', ['boots']],
    'rez-eq-boots-passenger': ['passenger', ['boots']]
  };
  Object.keys(groups).forEach(function(cbId){
    var grp = groups[cbId][0], keys = groups[cbId][1];
    var hasAny = keys.some(function(k){ return (s[grp]||{})[k]; });
    var cb = document.getElementById(cbId);
    if(cb && hasAny){ cb.checked = true; var card = cb.closest('.gear-card'); if(card) card.classList.add('open'); }
  });
  // Mark active chips
  document.querySelectorAll('.size-chips').forEach(function(g){
    var grp = g.dataset.group, key = g.dataset.key;
    var sel = (s[grp]||{})[key];
    if(!sel) return;
    g.querySelectorAll('.size-chip').forEach(function(b){
      if(b.dataset.size === sel) b.classList.add('active');
    });
    var head = g.previousElementSibling;
    if(head){ var pick = head.querySelector('.size-pick'); if(pick){ pick.textContent = sel; pick.dataset.empty='0'; } }
  });
};

// Mindee scan + Stripe payment → pages-rezervace-scan.js
