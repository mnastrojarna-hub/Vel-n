// ===== MotoGo24 Web — Rezervace: krok 2 (doklady+faktura) + Stripe =====
var MG = window.MG || {};
window.MG = MG;

// ===== STEP 1 SUBMIT: validate form → save customer → show step 2 =====
MG._submitReservation = async function(){
  var name=document.getElementById('rez-name'),email=document.getElementById('rez-email'),
    phone=document.getElementById('rez-phone'),street=document.getElementById('rez-street'),
    city=document.getElementById('rez-city'),zip=document.getElementById('rez-zip'),
    country=document.getElementById('rez-country'),agree=document.getElementById('rez-agree-vop');
  if(!name||!name.value||!email||!email.value||!phone||!phone.value||!(street&&street.value)||!(city&&city.value)||!(zip&&zip.value)){
    alert('Vyplňte prosím všechna povinná pole.');return;}
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
  if(document.getElementById('rez-eq-passenger')&&document.getElementById('rez-eq-passenger').checked) extras.push({name:'Výbava spolujezdce',price:690});
  if(document.getElementById('rez-eq-boots-rider')&&document.getElementById('rez-eq-boots-rider').checked) extras.push({name:'Boty řidič',price:290});
  if(document.getElementById('rez-eq-boots-passenger')&&document.getElementById('rez-eq-boots-passenger').checked) extras.push({name:'Boty spolujezdce',price:290});
  var deliveryAddr=null,returnAddr=null;
  if(document.getElementById('rez-delivery')&&document.getElementById('rez-delivery').checked)
    deliveryAddr=(document.getElementById('rez-delivery-address')||{}).value||null;
  var retO=document.getElementById('rez-return-other'),retS=document.getElementById('rez-return-same-as-delivery');
  if(retO&&retO.checked) returnAddr=(document.getElementById('rez-return-address')||{}).value||null;
  else if(retS&&retS.checked&&deliveryAddr) returnAddr=deliveryAddr;
  if(deliveryAddr) extras.push({name:'Přistavení motorky (nakládka+vykládka+doprava)',price:1000});
  if(returnAddr) extras.push({name:'Vrácení motorky (nakládka+vykládka+doprava)',price:1000});

  MG._rez.formData={motoId:mId,name:name.value,email:email.value,phone:phone.value,
    street:street.value,city:city.value,zip:zip.value,country:(country&&country.value)||'Česká republika',
    note:(document.getElementById('rez-note')||{}).value||'',pickupTime:ptEl.value,
    deliveryAddr:deliveryAddr,returnAddr:returnAddr,extras:extras,
    appliedCodes:(MG._rez.appliedCodes&&MG._rez.appliedCodes.length)?MG._rez.appliedCodes:[],
    discountAmt:MG._rez.discountAmt||0};

  // Save customer to DB immediately (even if they don't finish payment)
  try {
    var rpcParams = {
      p_moto_id: mId, p_start_date: r.startDate, p_end_date: r.endDate,
      p_name: name.value, p_email: email.value, p_phone: phone.value,
      p_street: street.value||'', p_city: city.value||'', p_zip: zip.value||'',
      p_country: (country&&country.value)||'CZ',
      p_note: (MG._rez.formData.note||'') + (ptEl.value ? '\nČas převzetí: '+ptEl.value : ''),
      p_pickup_time: ptEl.value ? ptEl.value+':00' : null,
      p_delivery_address: deliveryAddr, p_return_address: returnAddr,
      p_extras: extras
    };
    console.log('[REZ] create_web_booking params:', rpcParams);
    var regRes = await window.sb.rpc('create_web_booking', rpcParams);
    if(regRes.error){ console.error('[REZ] create_web_booking error:', regRes.error); alert('Chyba: '+regRes.error.message); return; }
    var regData = regRes.data;
    if(regData && regData.error){ alert(regData.error); return; }
    if(regData){
      MG._rez.bookingId = regData.booking_id;
      MG._rez.userId = regData.user_id;
      MG._rez.bookingAmount = regData.amount;
    }
  } catch(e){ alert('Chyba při ukládání: '+e.message); return; }

  MG._rezShowStep2();
};

// ===== STEP 2: Doklady + Náhled faktury (sloučeno) =====
MG._rezShowStep2 = function(){
  var form=document.getElementById('rez-form');if(!form)return;
  // Hide calendar, banner, moto select — only show on step 1
  ['rez-calendar','rez-date-banner','rez-avail-select','rez-moto-select'].forEach(function(id){
    var el=document.getElementById(id);if(el)el.style.display='none';
  });
  var d=MG._rez.formData,r=MG._rez;
  var moto=r.motos.find(function(m){return m.id===d.motoId;});
  var motoName=moto?moto.model:'—';
  var base=(moto&&r.startDate&&r.endDate)?MG.calcPrice(moto,r.startDate,r.endDate):0;
  var extT=0;d.extras.forEach(function(e){extT+=e.price;});
  var disc=d.discountAmt||0;
  var total=Math.max(0,base+extT-disc);

  // Invoice rows
  var rows='<tr><td style="padding:5px 0;border-bottom:1px solid #eee">Pronájem: '+motoName+'</td>'+
    '<td style="padding:5px 0;border-bottom:1px solid #eee;text-align:right">'+MG.formatPrice(base)+'</td></tr>';
  d.extras.forEach(function(e){rows+='<tr><td style="padding:5px 0;border-bottom:1px solid #eee">'+e.name+'</td>'+
    '<td style="padding:5px 0;border-bottom:1px solid #eee;text-align:right">'+MG.formatPrice(e.price)+'</td></tr>';});
  if(disc>0){var cl=(d.appliedCodes||[]).map(function(c){return c.code;}).join('+');
    rows+='<tr><td style="padding:5px 0;border-bottom:1px solid #eee;color:#1a8c1a">Sleva ('+cl+')</td>'+
    '<td style="padding:5px 0;border-bottom:1px solid #eee;text-align:right;color:#1a8c1a">−'+MG.formatPrice(disc)+'</td></tr>';}

  form.innerHTML=
    '<h2 style="margin-top:1rem">Ověření totožnosti a řidičského oprávnění</h2>'+
    '<p style="color:#555;line-height:1.6;margin-bottom:1rem">Pro přípravu nájemní smlouvy prosíme o vyplnění údajů z dokladu totožnosti a řidičského průkazu. Originály budou zkontrolovány při převzetí motocyklu.</p>'+
    '<h3>Doklad totožnosti</h3><div class="checkboxes" style="margin:.5rem 0">'+
    '<div><input type="radio" id="rez-doc-op" name="rez-doc-type" value="op" checked><label for="rez-doc-op">Občanský průkaz</label></div>'+
    '<div><input type="radio" id="rez-doc-pas" name="rez-doc-type" value="pas"><label for="rez-doc-pas">Cestovní pas</label></div></div>'+
    '<input type="text" id="rez-doc-number" placeholder="* Číslo dokladu" required autocomplete="off">'+
    '<h3 style="margin-top:1rem">Řidičský průkaz</h3>'+
    '<input type="text" id="rez-license-number" placeholder="* Číslo řidičského průkazu" required autocomplete="off">'+
    '<div class="checkboxes" style="margin:1rem 0"><div class="agreement gr2"><input type="checkbox" id="rez-license-confirm" required>'+
    '<div>* Potvrzuji, že jsem držitelem platného řidičského oprávnění a splňuji zákonné podmínky k řízení rezervovaného motocyklu.</div></div></div>'+
    '<hr style="border:none;border-top:2px solid #74FB71;margin:1.5rem 0">'+
    '<h2>Náhled zálohové faktury</h2>'+
    '<div style="background:#f9f9f9;border:1px solid #e0e0e0;border-radius:10px;padding:1rem;margin-bottom:1rem">'+
    '<table style="width:100%;border-collapse:collapse;font-size:.88rem;color:#333">'+
    '<tr><td style="padding:5px 0;font-weight:700;border-bottom:1px solid #ccc">Položka</td>'+
    '<td style="padding:5px 0;font-weight:700;border-bottom:1px solid #ccc;text-align:right">Cena</td></tr>'+rows+'</table>'+
    '<div style="display:flex;justify-content:space-between;align-items:center;margin-top:10px;padding-top:10px;border-top:2px solid #1a8c1a">'+
    '<strong>Celkem k úhradě</strong><strong style="color:#1a8c1a">'+MG.formatPrice(total)+'</strong></div></div>'+
    '<div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:10px;padding:.75rem;margin-bottom:1rem;font-size:.85rem;color:#374151">'+
    '<strong>Odběratel:</strong> '+d.name+' | '+d.email+' | '+d.phone+'<br>'+
    d.street+', '+d.zip+' '+d.city+'<br>'+
    '<strong>Motorka:</strong> '+motoName+' | <strong>Termín:</strong> '+MG.formatDate(r.startDate)+' – '+MG.formatDate(r.endDate)+
    (d.deliveryAddr?'<br><strong>Přistavení:</strong> '+d.deliveryAddr:'')+
    (d.returnAddr?'<br><strong>Vrácení:</strong> '+d.returnAddr:'')+'</div>'+
    '<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:1rem;margin-top:1rem">'+
    '<button class="btn btndark" onclick="MG._rezBackToStep1()">← Zpět</button>'+
    '<div style="display:flex;align-items:center;gap:1rem">'+
    '<div style="background:#74FB71;color:#0b0b0b;padding:.6rem 1.2rem;border-radius:25px;font-weight:800;font-size:1.05rem">'+MG.formatPrice(total)+'</div>'+
    '<button class="btn btngreen" onclick="MG._rezSubmitPayment()">Pokračovat k platbě</button></div></div>';
  window.scrollTo({top:form.offsetTop-80,behavior:'smooth'});
};

// ===== BACK TO STEP 1 =====
MG._rezBackToStep1 = function(){
  var form=document.getElementById('rez-form');if(!form)return;
  // Show calendar elements again
  ['rez-calendar','rez-date-banner','rez-moto-select'].forEach(function(id){
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

// ===== STRIPE CHECKOUT (booking already created in step 1) =====
MG._rezSubmitPayment = async function(){
  var docNum=document.getElementById('rez-doc-number');
  var licNum=document.getElementById('rez-license-number');
  var licConf=document.getElementById('rez-license-confirm');
  if(!docNum||!docNum.value){alert('Vyplňte číslo dokladu totožnosti.');return;}
  if(!licNum||!licNum.value){alert('Vyplňte číslo řidičského průkazu.');return;}
  if(!licConf||!licConf.checked){alert('Potvrďte prosím držení platného řidičského oprávnění.');return;}

  var btn=document.querySelector('#rez-form .btn.btngreen');
  if(btn){btn.disabled=true;btn.textContent='Zpracovávám...';}

  // Save identity docs to profile
  if(MG._rez.userId){
    try{await window.sb.from('profiles').update({
      id_number:docNum.value, license_number:licNum.value
    }).eq('id',MG._rez.userId);}catch(e){}
  }

  // Booking already created in step 1 — just call Stripe
  var bookingId=MG._rez.bookingId;
  var amount=MG._rez.bookingAmount;
  if(!bookingId){alert('Chyba: rezervace nebyla vytvořena. Zkuste znovu.');if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}return;}

  try{
    var payRes=await fetch(window.MOTOGO_CONFIG.SUPABASE_URL+'/functions/v1/process-payment',{method:'POST',
      headers:{'Content-Type':'application/json','apikey':window.MOTOGO_CONFIG.SUPABASE_ANON_KEY},
      body:JSON.stringify({booking_id:bookingId,amount:amount,type:'booking',source:'web',mode:'checkout'})});
    var payData=await payRes.json();
    if(payData.error){alert('Chyba platby: '+payData.error);if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}return;}
    if(payData.checkout_url){window.location.href=payData.checkout_url;}
    else{alert('Nepodařilo se vytvořit platbu.');if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}}
  }catch(e){console.error('[REZ]',e);alert('Došlo k chybě.');if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}}
};
