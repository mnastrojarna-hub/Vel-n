<?php
// ===== MotoGo24 Web PHP — Stránka Poukazy =====
// Odpovídá pages-poukazy.js

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'Poukazy']);

$intro = '<section><h1>Kup dárkový poukaz – daruj zážitek na dvou kolech!</h1>' .
    '<div class="gr2"><div>' .
    '<p>Hledáš originální dárek pro partnera, kamaráda nebo tátu?</p><p>&nbsp;</p>' .
    '<p>Naše <strong>dárkové poukazy na pronájem motorky</strong> od Motogo24 – <strong>půjčovna motorek Vysočina</strong> – potěší začátečníky i zkušené jezdce.</p><p>&nbsp;</p>' .
    '<p>Vyber hodnotu poukazu nebo konkrétní motorku a daruj svobodu na dvou kolech.</p><p>&nbsp;</p>' .
    '<p><a class="btn btngreen" onclick="var e=document.getElementById(\'poukaz-order\');if(e)e.scrollIntoView({behavior:\'smooth\'})">OBJEDNAT DÁRKOVÝ POUKAZ</a></p>' .
    '</div><div>' .
    '<img alt="Dárkový poukaz" style="width:100%;max-width:500px;border-radius:10px" loading="lazy" src="gfx/darkovy-poukaz.jpg">' .
    '</div></div></section>';

$steps = '<section><div class="gr3">' .
    renderWbox('gfx/ico-step1.svg', '1. Vyber', 'Vybereš si hodnotu poukazu nebo konkrétní motorku.') .
    renderWbox('gfx/ico-step2.svg', '2. Zaplať', 'Zaplatíš online.') .
    renderWbox('gfx/ico-step3.svg', '3. Vyzvedni', 'Poukaz po zaplacení přistane do tvé e-mailové schránky.') .
    '</div>' .
    '<p>&nbsp;</p><p>Všechny vouchery mají <strong>platnost 3 roky</strong> od data vystavení. <strong>Obdarovaný si sám zvolí termín výpůjčky</strong>.</p>' .
    '<p>&nbsp;</p>' .
    '<div class="gr2"><div>' .
    '<h2>Proč zakoupit poukaz</h2><ul>' .
    '<li><strong>Flexibilní volba</strong> – hodnota poukazu nebo konkrétní motorka.</li>' .
    '<li><strong>Platnost 3 roky</strong> – obdarovaný si sám vybere termín.</li>' .
    '<li><strong>Bez kauce</strong> – férové podmínky.</li>' .
    '<li><strong>Výbava v ceně</strong> – helma, bunda, kalhoty a rukavice zdarma.</li>' .
    '<li><strong>Nonstop provoz</strong> – vyzvednutí i vrácení kdykoli.</li>' .
    '<li><strong>Online objednávka</strong> – poukaz ti po zaplacení přijde e-mailem.</li></ul>' .
    '</div><div>' .
    '<h2>Jak poukaz využít</h2><ul>' .
    '<li><strong>Cestovní motorky</strong> – víkendový roadtrip po Vysočině i celé ČR.</li>' .
    '<li><strong>Sportovní motorky</strong> – adrenalinová jízda v zatáčkách.</li>' .
    '<li><strong>Enduro</strong> – lehký terén a dobrodružství mimo hlavní cesty.</li>' .
    '<li><strong>Dětské motorky</strong> – první jízdy pro malé jezdce pod dohledem.</li></ul>' .
    '</div></div>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . '/katalog">ZOBRAZIT KATALOG MOTOREK</a></p>' .
    '</section>';

$orderForm = '<section id="poukaz-order"><h2>Objednat dárkový poukaz</h2>' .
    '<div class="pcontent">' .
    '<input type="text" id="poukaz-buyer-name" name="name" placeholder="* Jméno a příjmení">' .
    '<div class="gr2"><input type="text" id="poukaz-addr-street" name="address" placeholder="* Ulice, č.p.">' .
    '<input type="text" id="poukaz-addr-zip" name="postal-code" placeholder="* PSČ"></div>' .
    '<div class="gr2"><input type="text" id="poukaz-addr-city" name="city" placeholder="* Město">' .
    '<input type="text" id="poukaz-addr-country" name="country" placeholder="* Stát" value="Česká republika"></div>' .
    '<div class="gr2"><input type="email" id="poukaz-buyer-email" name="email" placeholder="* E-mail">' .
    '<input type="tel" id="poukaz-buyer-phone" name="tel" placeholder="* Telefon (+420XXXXXXXXX)"></div>' .
    '<div class="gr2" style="align-items:start;margin:1rem 0"><div class="checkboxes" style="margin:0">' .
    '<div><input type="checkbox" id="poukaz-print"><label for="poukaz-print">Fyzický poukaz <strong>(+180 Kč)</strong></label></div>' .
    '<div><input type="checkbox" id="poukaz-digital" checked><label for="poukaz-digital">Elektronický poukaz</label></div>' .
    '</div><div><label style="font-weight:700;color:#111">* Hodnota poukazu:</label>' .
    '<input type="number" id="poukaz-amount" placeholder="Částka v Kč" min="500" step="100"></div></div>' .
    '<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:1rem;margin-top:1rem">' .
    '<div id="poukaz-price" style="background:#74FB71;color:#0b0b0b;padding:.6rem 1.2rem;border-radius:25px;font-weight:800;border:2px solid #1a8c1a;min-width:150px">Cena:</div>' .
    '<button class="btn btngreen" onclick="submitVoucherOrder()">Pokračovat k platbě</button>' .
    '</div></div></section>';

$faqItems = [
    ['q' => 'Jaká je platnost dárkového poukazu?', 'a' => 'Všechny vouchery mají platnost <strong>3 roky</strong> od data vystavení. Termín výpůjčky si obdarovaný volí sám.'],
    ['q' => 'Jak poukaz doručíte?', 'a' => '<strong>Okamžitě e-mailem</strong> po úhradě. Na požádání umíme připravit i dárkový tisk.'],
    ['q' => 'Musí obdarovaný skládat kauci?', 'a' => 'Ne. <strong>Půjčujeme bez kauce</strong>. Podmínky jsou jasné a férové.'],
    ['q' => 'Lze změnit termín uplatnění?', 'a' => 'Ano, <strong>termín lze po domluvě změnit</strong> dle dostupnosti konkrétní motorky.'],
    ['q' => 'Na jaké motorky lze voucher uplatnit?', 'a' => 'Na <strong>cestovní, sportovní, enduro i dětské motorky</strong> v nabídce Motogo24.'],
];
$faqHtml = '';
foreach ($faqItems as $faq) { $faqHtml .= renderFaqItem($faq['q'], $faq['a']); }

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' . $intro . $steps . $orderForm .
    '<section><h2>Často kladené dotazy k dárkovým poukazům</h2>' .
    '<div class="tab-content"><div class="tab-pane active"><div class="gr2">' .
    $faqHtml . '</div></div></div></section>' .
    renderCta('Dárkový poukaz na pronájem motorky – Vysočina',
        'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop provozem</strong>, <strong>bez kauce</strong> a <strong>výbavou v ceně</strong>.',
        [['label' => 'OBJEDNAT POUKAZ', 'href' => '/poukazy', 'cls' => 'btndark pulse']]) .
    '</div></div></main>';

// JS pro interaktivní formulář poukazů
$voucherJs = '<script>
var SUPABASE_URL = ' . json_encode(SUPABASE_URL) . ';
var SUPABASE_ANON_KEY = ' . json_encode(SUPABASE_ANON_KEY) . ';

function formatPriceCZ(n){
  if(!n && n!==0) return "";
  return Number(n).toLocaleString("cs-CZ")+" Kč";
}
function updateVoucherPrice(){
  var a=document.getElementById("poukaz-amount");
  var pr=document.getElementById("poukaz-print");
  var el=document.getElementById("poukaz-price");
  if(!el)return;
  var val=a&&a.value?Number(a.value):0;
  var printFee=pr&&pr.checked?180:0;
  var total=val+printFee;
  el.textContent=total>0?"Cena: "+formatPriceCZ(total):"Cena:";
}
var amt=document.getElementById("poukaz-amount");
var prCb=document.getElementById("poukaz-print");
if(amt)amt.addEventListener("input",updateVoucherPrice);
if(prCb)prCb.addEventListener("change",updateVoucherPrice);

var _voucherData=null;
function submitVoucherOrder(){
  var amount=document.getElementById("poukaz-amount");
  var bName=document.getElementById("poukaz-buyer-name");
  var bEmail=document.getElementById("poukaz-buyer-email");
  var bPhone=document.getElementById("poukaz-buyer-phone");
  var aSt=document.getElementById("poukaz-addr-street");
  var aZip=document.getElementById("poukaz-addr-zip");
  var aCity=document.getElementById("poukaz-addr-city");
  if(!amount||!amount.value||Number(amount.value)<500){alert("Zadejte prosím hodnotu poukazu (min. 500 Kč).");return;}
  if(!bName||!bName.value||!bEmail||!bEmail.value||!bPhone||!bPhone.value){alert("Vyplňte prosím všechna povinná pole.");return;}
  if(!aSt||!aSt.value||!aZip||!aZip.value||!aCity||!aCity.value){alert("Vyplňte prosím adresu.");return;}
  var isPrint=document.getElementById("poukaz-print")&&document.getElementById("poukaz-print").checked;
  var printFee=isPrint?180:0;
  _voucherData={amount:Number(amount.value),printFee:printFee,total:Number(amount.value)+printFee,name:bName.value,email:bEmail.value,phone:bPhone.value,isPrint:isPrint,addr:{street:aSt.value,zip:aZip.value,city:aCity.value}};
  showVoucherSummary();
}
function showVoucherSummary(){
  var el=document.getElementById("poukaz-order");if(!el)return;
  var d=_voucherData;
  var typeLabel=d.isPrint?"Tištěný poukaz (doručení poštou)":"Elektronický poukaz (doručení e-mailem)";
  var rows=\'<tr><td style="padding:6px 0;border-bottom:1px solid #eee">Dárkový poukaz (hodnota)</td><td style="padding:6px 0;border-bottom:1px solid #eee;text-align:right">\'+formatPriceCZ(d.amount)+"</td></tr>";
  if(d.printFee)rows+=\'<tr><td style="padding:6px 0;border-bottom:1px solid #eee">Fyzický poukaz (tisk + poštovné)</td><td style="padding:6px 0;border-bottom:1px solid #eee;text-align:right">\'+formatPriceCZ(d.printFee)+"</td></tr>";
  rows+=\'<tr><td style="padding:6px 0;border-bottom:1px solid #eee">Typ</td><td style="padding:6px 0;border-bottom:1px solid #eee;text-align:right">\'+typeLabel+"</td></tr>";
  el.innerHTML=\'<h2>Shrnutí objednávky</h2><div style="background:#f9f9f9;border:1px solid #e0e0e0;border-radius:10px;padding:1.25rem;margin-bottom:1.5rem"><table style="width:100%;border-collapse:collapse;font-size:.9rem;color:#333">\'+rows+\'</table><div style="display:flex;justify-content:space-between;align-items:center;margin-top:12px;padding-top:12px;border-top:2px solid #1a8c1a"><strong style="font-size:1.1rem">Celkem k úhradě</strong><strong style="font-size:1.1rem;color:#1a8c1a">\'+formatPriceCZ(d.total)+\'</strong></div></div><div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:10px;padding:1rem;margin-bottom:1.5rem;font-size:.88rem;color:#374151"><strong>Kupující:</strong> \'+d.name+"<br>"+d.addr.street+", "+d.addr.zip+" "+d.addr.city+"<br>"+d.email+" | "+d.phone+\'</div><div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:1rem"><button class="btn btndark" onclick="window.location.href=\\\''+BASE_URL+'/poukazy\\\'">← Zpět</button><div style="display:flex;align-items:center;gap:1rem"><div style="background:#74FB71;color:#0b0b0b;padding:.6rem 1.2rem;border-radius:25px;font-weight:800">\'+formatPriceCZ(d.total)+\'</div><button class="btn btngreen" onclick="voucherPay()">Pokračovat k platbě</button></div></div>\';
  window.scrollTo({top:el.offsetTop-80,behavior:"smooth"});
}
async function voucherPay(){
  var d=_voucherData;
  var btn=document.querySelector("#poukaz-order .btn.btngreen");
  if(btn){btn.disabled=true;btn.textContent="Zpracovávám...";}
  try{
    var r=await fetch(SUPABASE_URL+"/functions/v1/process-payment",{
      method:"POST",headers:{"Content-Type":"application/json","apikey":SUPABASE_ANON_KEY},
      body:JSON.stringify({amount:d.total,voucher_amount:d.amount,type:"shop",source:"web",mode:"checkout",customer_email:d.email,customer_name:d.name,customer_phone:d.phone,is_print:d.isPrint,shipping_address:d.isPrint?(d.addr.street+", "+d.addr.zip+" "+d.addr.city):null})
    });
    var data=await r.json();
    if(data.checkout_url){window.location.href=data.checkout_url;}
    else{alert(data.error||"Nepodařilo se vytvořit platbu.");if(btn){btn.disabled=false;btn.textContent="Pokračovat k platbě";}}
  }catch(e){console.error("[POUKAZ] Error:",e);alert("Došlo k chybě. Zkuste to prosím znovu.");if(btn){btn.disabled=false;btn.textContent="Pokračovat k platbě";}}
}
</script>';

renderPage('Dárkové poukazy – Motogo24', $content . $voucherJs, '/poukazy');
