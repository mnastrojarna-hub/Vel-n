// ===== MotoGo24 Web — Rezervace kroky 1-3 + Stripe =====
var MG = window.MG || {};
window.MG = MG;

// ===== STEP 1: SUBMIT FORM → show identity verification =====
MG._submitReservation = function(){
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
  var retOther=document.getElementById('rez-return-other');
  var retSameAsDel=document.getElementById('rez-return-same-as-delivery');
  if(retOther&&retOther.checked) returnAddr=(document.getElementById('rez-return-address')||{}).value||null;
  else if(retSameAsDel&&retSameAsDel.checked&&deliveryAddr) returnAddr=deliveryAddr;
  if(deliveryAddr) extras.push({name:'Přistavení motorky (nakládka + vykládka + doprava)',price:1000});
  if(returnAddr) extras.push({name:'Vrácení motorky (nakládka + vykládka + doprava)',price:1000});
  MG._rez.formData={motoId:mId,name:name.value,email:email.value,phone:phone.value,
    street:street.value,city:city.value,zip:zip.value,country:(country&&country.value)||'Česká republika',
    note:(document.getElementById('rez-note')||{}).value||'',pickupTime:ptEl.value,
    deliveryAddr:deliveryAddr,returnAddr:returnAddr,extras:extras,
    appliedCodes:MG._rez.appliedCodes||[],discountAmt:MG._rez.discountAmt||0};
  MG._rezShowStep2();
};

// ===== STEP 2: Ověření totožnosti =====
MG._rezShowStep2 = function(){
  var form=document.getElementById('rez-form');if(!form)return;
  form.innerHTML='<h2 style="margin-top:1rem">Ověření totožnosti a řidičského oprávnění</h2>'+
    '<p style="color:#555;line-height:1.6;margin-bottom:1.5rem">Pro přípravu nájemní smlouvy a urychlení předání motocyklu prosíme o vyplnění údajů z dokladu totožnosti a řidičského průkazu. Originály dokladů budou zkontrolovány při osobním převzetí motocyklu.</p>'+
    '<h3>Doklad totožnosti</h3><div class="checkboxes" style="margin:.75rem 0">'+
    '<div><input type="radio" id="rez-doc-op" name="rez-doc-type" value="op" checked><label for="rez-doc-op">Občanský průkaz</label></div>'+
    '<div><input type="radio" id="rez-doc-pas" name="rez-doc-type" value="pas"><label for="rez-doc-pas">Cestovní pas</label></div></div>'+
    '<input type="text" id="rez-doc-number" placeholder="* Číslo dokladu" required>'+
    '<h3 style="margin-top:1.5rem">Řidičský průkaz</h3>'+
    '<input type="text" id="rez-license-number" placeholder="* Číslo řidičského průkazu" required>'+
    '<div class="checkboxes" style="margin:1.5rem 0"><div class="agreement gr2"><input type="checkbox" id="rez-license-confirm" required>'+
    '<div>* Potvrzuji, že jsem držitelem platného řidičského oprávnění a splňuji zákonné podmínky k řízení rezervovaného motocyklu.</div></div></div>'+
    '<div class="dfcs" style="flex-wrap:wrap;gap:1rem;margin-top:1rem">'+
    '<button class="btn btndark" onclick="MG._rezBackToStep1()">← Zpět</button>'+
    '<button class="btn btngreen" onclick="MG._rezSubmitStep2()">Pokračovat v rezervaci</button></div>';
  window.scrollTo({top:form.offsetTop-80,behavior:'smooth'});
};

MG._rezSubmitStep2 = function(){
  var docNum=document.getElementById('rez-doc-number'),licNum=document.getElementById('rez-license-number'),licConf=document.getElementById('rez-license-confirm');
  if(!docNum||!docNum.value){alert('Vyplňte číslo dokladu totožnosti.');return;}
  if(!licNum||!licNum.value){alert('Vyplňte číslo řidičského průkazu.');return;}
  if(!licConf||!licConf.checked){alert('Potvrďte prosím držení platného řidičského oprávnění.');return;}
  var docType=document.querySelector('input[name="rez-doc-type"]:checked');
  MG._rez.identity={docType:docType?docType.value:'op',docNumber:docNum.value,licenseNumber:licNum.value};
  MG._rezShowStep3();
};

MG._rezBackToStep1 = function(){
  var form=document.getElementById('rez-form');if(!form)return;
  form.outerHTML=MG._rezFormHtml();MG._rezInitFormEvents();
  var d=MG._rez.formData;
  if(d){var f=function(id,v){var e=document.getElementById(id);if(e&&v)e.value=v;};
    f('rez-name',d.name);f('rez-email',d.email);f('rez-phone',d.phone);
    f('rez-street',d.street);f('rez-city',d.city);f('rez-zip',d.zip);
    f('rez-country',d.country);f('rez-note',d.note);f('rez-pickup-time',d.pickupTime);}
  MG._rezUpdatePrice();
};

// ===== STEP 3: Náhled zálohové faktury =====
MG._rezShowStep3 = function(){
  var form=document.getElementById('rez-form');if(!form)return;
  var d=MG._rez.formData,r=MG._rez;
  var moto=r.motos.find(function(m){return m.id===d.motoId;});
  var motoName=moto?moto.model:'—';
  var base=(moto&&r.startDate&&r.endDate)?MG.calcPrice(moto,r.startDate,r.endDate):0;
  var extrasTotal=0;d.extras.forEach(function(e){extrasTotal+=e.price;});
  var discAmt=d.discountAmt||0;
  var total=Math.max(0,base+extrasTotal-discAmt);
  var rows='<tr><td style="padding:6px 0;border-bottom:1px solid #eee">Pronájem motocyklu '+motoName+'</td>'+
    '<td style="padding:6px 0;border-bottom:1px solid #eee;text-align:right;white-space:nowrap">'+MG.formatPrice(base)+'</td></tr>';
  d.extras.forEach(function(e){rows+='<tr><td style="padding:6px 0;border-bottom:1px solid #eee">'+e.name+'</td>'+
    '<td style="padding:6px 0;border-bottom:1px solid #eee;text-align:right;white-space:nowrap">'+MG.formatPrice(e.price)+'</td></tr>';});
  if(discAmt>0){var cl=d.appliedCodes.map(function(c){return c.code;}).join(' + ');
    rows+='<tr><td style="padding:6px 0;border-bottom:1px solid #eee;color:#1a8c1a">Sleva ('+cl+')</td>'+
    '<td style="padding:6px 0;border-bottom:1px solid #eee;text-align:right;color:#1a8c1a;white-space:nowrap">−'+MG.formatPrice(discAmt)+'</td></tr>';}
  form.innerHTML='<h2 style="margin-top:1rem">Náhled zálohové faktury</h2>'+
    '<p style="color:#555;margin-bottom:1rem">Zkontrolujte prosím údaje před pokračováním k platbě.</p>'+
    '<div style="background:#f9f9f9;border:1px solid #e0e0e0;border-radius:10px;padding:1.25rem;margin-bottom:1.5rem">'+
    '<table style="width:100%;border-collapse:collapse;font-size:.9rem;color:#333">'+
    '<tr><td style="padding:6px 0;font-weight:700;border-bottom:1px solid #ccc">Položka</td>'+
    '<td style="padding:6px 0;font-weight:700;border-bottom:1px solid #ccc;text-align:right">Cena</td></tr>'+rows+'</table>'+
    '<div style="display:flex;justify-content:space-between;align-items:center;margin-top:12px;padding-top:12px;border-top:2px solid #1a8c1a">'+
    '<strong style="font-size:1.1rem">Celkem k úhradě</strong>'+
    '<strong style="font-size:1.1rem;color:#1a8c1a">'+MG.formatPrice(total)+'</strong></div></div>'+
    '<div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:10px;padding:1rem;margin-bottom:1.5rem;font-size:.88rem;color:#374151">'+
    '<strong>Odběratel:</strong> '+d.name+'<br>'+d.street+', '+d.zip+' '+d.city+'<br>'+d.email+' | '+d.phone+'<br>'+
    '<strong>Motorka:</strong> '+motoName+'<br><strong>Termín:</strong> '+MG.formatDate(r.startDate)+' – '+MG.formatDate(r.endDate)+'<br>'+
    '<strong>Čas převzetí:</strong> '+d.pickupTime+
    (d.deliveryAddr?'<br><strong>Přistavení na:</strong> '+d.deliveryAddr:'')+
    (d.returnAddr?'<br><strong>Vrácení na:</strong> '+d.returnAddr:'')+'</div>'+
    '<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:1rem;margin-top:1rem">'+
    '<button class="btn btndark" onclick="MG._rezShowStep2()">← Zpět</button>'+
    '<div style="display:flex;align-items:center;gap:1rem"><div style="background:#74FB71;color:#0b0b0b;padding:.6rem 1.2rem;border-radius:25px;font-weight:800;font-size:1.05rem">'+MG.formatPrice(total)+'</div>'+
    '<button class="btn btngreen" onclick="MG._rezSubmitPayment()">Pokračovat k platbě</button></div></div>';
  window.scrollTo({top:form.offsetTop-80,behavior:'smooth'});
};

// ===== STRIPE CHECKOUT =====
MG._rezSubmitPayment = async function(){
  var d=MG._rez.formData,r=MG._rez,id=MG._rez.identity;
  var btn=document.querySelector('#rez-form .btn.btngreen');
  if(btn){btn.disabled=true;btn.textContent='Zpracovávám...';}
  try{
    var res=await window.sb.rpc('create_web_booking',{p_moto_id:d.motoId,
      p_start_date:r.startDate,p_end_date:r.endDate,p_name:d.name,p_email:d.email,p_phone:d.phone,
      p_street:d.street,p_city:d.city,p_zip:d.zip,p_country:d.country,p_note:d.note,
      p_pickup_time:d.pickupTime,p_delivery_address:d.deliveryAddr,p_return_address:d.returnAddr,p_extras:d.extras});
    if(res.error){alert('Chyba: '+res.error.message);if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}return;}
    var data=res.data;if(data.error){alert(data.error);if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}return;}
    if(data.user_id&&id){window.sb.from('profiles').update({id_number:id.docNumber,license_number:id.licenseNumber}).eq('id',data.user_id).then(function(){});}
    var payRes=await fetch(window.MOTOGO_CONFIG.SUPABASE_URL+'/functions/v1/process-payment',{method:'POST',
      headers:{'Content-Type':'application/json','apikey':window.MOTOGO_CONFIG.SUPABASE_ANON_KEY},
      body:JSON.stringify({booking_id:data.booking_id,amount:data.amount,type:'booking',source:'web',mode:'checkout'})});
    var payData=await payRes.json();
    if(payData.error){alert('Chyba platby: '+payData.error);if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}return;}
    if(payData.checkout_url){window.location.href=payData.checkout_url;}
    else{alert('Nepodařilo se vytvořit platební relaci.');if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}}
  }catch(e){console.error('[REZ] Payment error:',e);alert('Došlo k chybě.');if(btn){btn.disabled=false;btn.textContent='Pokračovat k platbě';}}
};
