<?php
// ===== MotoGo24 Web PHP — Koupit dárkový poukaz (objednávkový formulář) =====

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Poukazy', 'href' => '/poukazy'], 'Koupit dárkový poukaz']);

$form = '<div class="gift-voucher-order">' .
    '<h2>Dárkový poukaz Motogo24</h2>' .
    '<p>Darujte zážitek z jízdy na motorce! Poukaz je platný 3 roky a lze jej uplatnit při rezervaci na tomto webu.</p>' .
    '<form id="giftVoucherForm" method="POST" action="">' .

    '<h3>Vaše kontaktní údaje</h3>' .
    '<input type="text" name="senderName" id="gv-name" placeholder="* Jméno a příjmení" required maxlength="255" autocomplete="name">' .
    '<div class="gr2">' .
        '<input type="email" name="senderEmail" id="gv-email" placeholder="* E-mail" required maxlength="255" autocomplete="email">' .
        '<input type="tel" name="senderPhone" id="gv-phone" placeholder="Telefon (+420...)" maxlength="20" autocomplete="tel">' .
    '</div>' .
    '<div class="gr2">' .
        '<input type="text" name="senderStreet" id="gv-street" placeholder="Ulice, č.p." maxlength="255" autocomplete="street-address">' .
        '<input type="text" name="senderZipCode" id="gv-zip" placeholder="PSČ" maxlength="10" autocomplete="postal-code">' .
    '</div>' .
    '<div class="gr2">' .
        '<input type="text" name="senderCity" id="gv-city" placeholder="Město" maxlength="255" autocomplete="address-level2">' .
        '<input type="text" name="senderCountry" id="gv-country" placeholder="Stát" maxlength="2" value="CZ" autocomplete="country">' .
    '</div>' .
    '<div class="gr2">' .
        '<input type="text" name="senderCompany" id="gv-company" placeholder="Firma (volitelně)" maxlength="255" autocomplete="organization">' .
        '<input type="text" name="senderICO" id="gv-ico" placeholder="IČO (volitelně)" maxlength="20">' .
    '</div>' .

    '<div class="gv-values">' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="300" checked> 300 Kč</label>' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="500"> 500 Kč</label>' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="1000"> 1 000 Kč</label>' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="2000"> 2 000 Kč</label>' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="5000"> 5 000 Kč</label>' .
    '</div>' .
    '<div class="gv-custom-value">' .
        '<label>Jiná částka (Kč): <input type="number" name="customValue" id="gv-custom" min="100" max="50000" step="1" placeholder="Zadejte částku"></label>' .
    '</div>' .

    '<h3>Doplňky</h3>' .
    '<div class="gv-equipments">' .
        '<label class="gv-equipment-btn">' .
            '<input type="checkbox" name="equipmentId[]" id="gv-print" value="print" data-price="180">' .
            '<div><strong>Fyzický poukaz</strong><br><small>Tisk a poštovné</small></div>' .
            '<span class="gv-eq-price">+180 Kč</span>' .
        '</label>' .
    '</div>' .

    '<div class="gv-price-preview" id="gvPricePreview">' .
        'Celková cena: <strong id="gvTotalPrice">300 Kč</strong>' .
    '</div>' .

    '<div class="checkboxes">' .
        '<div class="agreement gr2">' .
            '<input type="checkbox" id="gvAgreement" name="gvAgreement">' .
            '<div><label for="gvAgreement">* Souhlasím s <a href="' . BASE_URL . '/obchodni-podminky" target="_blank">obchodními podmínkami</a></label></div>' .
        '</div>' .
    '</div>' .

    '<div class="dfcs"><div></div><div>' .
        '<button type="submit" id="gvSubmitBtn" class="btn btngreen">Pokračovat k platbě</button>' .
    '</div></div>' .
    '</form></div>';

$content = '<main id="content"><section aria-label="Koupit dárkový poukaz" class="container">' .
    $bc . '<div class="pcontent">' . $form . '</div></section></main>';

$js = '<script>
var SUPABASE_URL=' . json_encode(SUPABASE_URL) . ';
var SUPABASE_ANON_KEY=' . json_encode(SUPABASE_ANON_KEY) . ';
(function(){
var radios=document.querySelectorAll("input[name=value]");
var custom=document.getElementById("gv-custom");
var printCb=document.getElementById("gv-print");
var totalEl=document.getElementById("gvTotalPrice");

function fmt(n){return Number(n).toLocaleString("cs-CZ")+" Kč";}
function getAmount(){
  if(custom&&custom.value&&Number(custom.value)>0)return Number(custom.value);
  var r=document.querySelector("input[name=value]:checked");
  return r?Number(r.value):0;
}
function update(){
  var a=getAmount();
  var eq=printCb&&printCb.checked?180:0;
  totalEl.textContent=fmt(a+eq);
}

radios.forEach(function(r){r.addEventListener("change",function(){
  if(custom)custom.value="";update();
});});
if(custom)custom.addEventListener("input",function(){
  radios.forEach(function(r){r.checked=false;});update();
});
if(printCb)printCb.addEventListener("change",update);

var form=document.getElementById("giftVoucherForm");
form.addEventListener("submit",function(e){
  e.preventDefault();
  var amount=getAmount();
  if(amount<100){alert("Zadejte hodnotu poukazu (min. 100 Kč).");return;}
  var name=document.getElementById("gv-name").value.trim();
  var email=document.getElementById("gv-email").value.trim();
  if(!name||!email){alert("Vyplňte jméno a e-mail.");return;}
  var agr=document.getElementById("gvAgreement");
  if(!agr||!agr.checked){alert("Musíte souhlasit s obchodními podmínkami.");return;}

  var isPrint=printCb&&printCb.checked;
  var printFee=isPrint?180:0;
  var total=amount+printFee;
  var phone=(document.getElementById("gv-phone").value||"").trim();
  var street=(document.getElementById("gv-street").value||"").trim();
  var zip=(document.getElementById("gv-zip").value||"").trim();
  var city=(document.getElementById("gv-city").value||"").trim();
  var addr=street&&zip&&city?(street+", "+zip+" "+city):null;

  var btn=document.getElementById("gvSubmitBtn");
  btn.disabled=true;btn.textContent="Zpracovávám...";
  fetch(SUPABASE_URL+"/functions/v1/process-payment",{
    method:"POST",
    headers:{"Content-Type":"application/json","apikey":SUPABASE_ANON_KEY},
    body:JSON.stringify({
      amount:total,voucher_amount:amount,type:"shop",source:"web",
      mode:"checkout",customer_email:email,customer_name:name,
      customer_phone:phone,is_print:isPrint,
      shipping_address:isPrint?addr:null
    })
  }).then(function(r){return r.json();})
  .then(function(data){
    if(data.checkout_url){window.location.href=data.checkout_url;}
    else{alert(data.error||"Nepodařilo se vytvořit platbu.");btn.disabled=false;btn.textContent="Pokračovat k platbě";}
  }).catch(function(err){
    console.error("[POUKAZ]",err);
    alert("Došlo k chybě. Zkuste to prosím znovu.");
    btn.disabled=false;btn.textContent="Pokračovat k platbě";
  });
});
update();
})();
</script>';

renderPage('Půjčovna motorek Vysočina - Koupit dárkový poukaz', $content . $js, '/koupit-darkovy-poukaz', [
    'description' => 'Objednejte dárkový poukaz na pronájem motorky od Motogo24. Platnost 3 roky, bez kauce, výbava v ceně.',
    'keywords' => 'koupit dárkový poukaz motorka, objednat voucher Motogo24, dárek pronájem motorky',
    'og_image' => 'https://motogo24.cz/gfx/darkovy-poukaz.jpg',
]);
