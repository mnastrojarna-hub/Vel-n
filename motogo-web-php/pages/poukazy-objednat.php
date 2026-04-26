<?php
// ===== MotoGo24 Web PHP — Koupit dárkový poukaz (objednávkový formulář) =====

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.vouchers'), 'href' => '/poukazy'], t('breadcrumb.buyVoucher')]);

$agreementHtml = t('voucher.agreement', ['href' => BASE_URL . '/obchodni-podminky']);

$form = '<div class="gift-voucher-order">' .
    '<h2>' . te('voucher.title') . '</h2>' .
    '<p>' . te('voucher.lead') . '</p>' .
    '<form id="giftVoucherForm" method="POST" action="">' .

    '<h3>' . te('voucher.contactSection') . '</h3>' .
    '<input type="text" name="senderName" id="gv-name" placeholder="' . te('voucher.fieldName') . '" required maxlength="255" autocomplete="name">' .
    '<div class="gr2">' .
        '<input type="email" name="senderEmail" id="gv-email" placeholder="' . te('voucher.fieldEmail') . '" required maxlength="255" autocomplete="email">' .
        '<input type="tel" name="senderPhone" id="gv-phone" placeholder="' . te('voucher.fieldPhone') . '" maxlength="20" autocomplete="tel">' .
    '</div>' .
    '<div class="gr2">' .
        '<input type="text" name="senderStreet" id="gv-street" placeholder="' . te('voucher.fieldStreet') . '" maxlength="255" autocomplete="street-address">' .
        '<input type="text" name="senderZipCode" id="gv-zip" placeholder="' . te('voucher.fieldZip') . '" maxlength="10" autocomplete="postal-code">' .
    '</div>' .
    '<div class="gr2">' .
        '<input type="text" name="senderCity" id="gv-city" placeholder="' . te('voucher.fieldCity') . '" maxlength="255" autocomplete="address-level2">' .
        '<input type="text" name="senderCountry" id="gv-country" placeholder="' . te('voucher.fieldCountry') . '" maxlength="2" value="CZ" autocomplete="country">' .
    '</div>' .
    '<div class="gr2">' .
        '<input type="text" name="senderCompany" id="gv-company" placeholder="' . te('voucher.fieldCompany') . '" maxlength="255" autocomplete="organization">' .
        '<input type="text" name="senderICO" id="gv-ico" placeholder="' . te('voucher.fieldIco') . '" maxlength="20">' .
    '</div>' .

    '<div class="gv-values">' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="300" checked> ' . moneyHtml(300) . '</label>' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="500"> ' . moneyHtml(500) . '</label>' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="1000"> ' . moneyHtml(1000) . '</label>' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="2000"> ' . moneyHtml(2000) . '</label>' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="5000"> ' . moneyHtml(5000) . '</label>' .
    '</div>' .
    '<div class="gv-custom-value">' .
        '<label>' . te('voucher.customAmount') . ' <input type="number" name="customValue" id="gv-custom" min="100" max="50000" step="1" placeholder="' . te('voucher.customPlaceholder') . '"></label>' .
    '</div>' .

    '<h3>' . te('voucher.extras') . '</h3>' .
    '<div class="gv-equipments">' .
        '<label class="gv-equipment-btn">' .
            '<input type="checkbox" name="equipmentId[]" id="gv-print" value="print" data-price="180">' .
            '<div><strong>' . te('voucher.printLabel') . '</strong><br><small>' . te('voucher.printNote') . '</small></div>' .
            '<span class="gv-eq-price">' . te('voucher.printPrice') . '</span>' .
        '</label>' .
    '</div>' .

    '<div class="gv-price-preview" id="gvPricePreview">' .
        te('voucher.totalPrice') . ' <strong id="gvTotalPrice">' . moneyHtml(300) . '</strong>' .
        ' <span class="gv-czk-note" id="gvCzkNote" style="font-size:.78rem;color:#6b7280;margin-left:.5rem"></span>' .
    '</div>' .

    '<div class="checkboxes">' .
        '<div class="agreement gr2">' .
            '<input type="checkbox" id="gvAgreement" name="gvAgreement">' .
            '<div><label for="gvAgreement">' . $agreementHtml . '</label></div>' .
        '</div>' .
    '</div>' .

    '<div class="dfcs"><div></div><div>' .
        '<button type="submit" id="gvSubmitBtn" class="btn btngreen">' . te('voucher.continueToPay') . '</button>' .
    '</div></div>' .
    '</form></div>';

$content = '<main id="content"><section aria-label="' . te('breadcrumb.buyVoucher') . '" class="container">' .
    $bc . '<div class="pcontent">' . $form . '</div></section></main>';

$lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
$localeMap = ['cs' => 'cs-CZ', 'en' => 'en-GB', 'de' => 'de-DE', 'es' => 'es-ES', 'fr' => 'fr-FR', 'nl' => 'nl-NL', 'pl' => 'pl-PL'];
$jsLocale = $localeMap[$lang] ?? 'cs-CZ';

$js = '<script>
var SUPABASE_URL=' . json_encode(SUPABASE_URL) . ';
var SUPABASE_ANON_KEY=' . json_encode(SUPABASE_ANON_KEY) . ';
var GV_I18N = {
  locale: ' . json_encode($jsLocale) . ',
  currency: ' . json_encode(t('currency.suffix'), JSON_UNESCAPED_UNICODE) . ',
  errMin: ' . json_encode(t('voucher.errMinAmount'), JSON_UNESCAPED_UNICODE) . ',
  errFill: ' . json_encode(t('voucher.errFillNameEmail'), JSON_UNESCAPED_UNICODE) . ',
  errAgr: ' . json_encode(t('voucher.errAgreement'), JSON_UNESCAPED_UNICODE) . ',
  errPay: ' . json_encode(t('voucher.errPaymentFailed'), JSON_UNESCAPED_UNICODE) . ',
  errGen: ' . json_encode(t('voucher.errGeneric'), JSON_UNESCAPED_UNICODE) . ',
  processing: ' . json_encode(t('voucher.processing'), JSON_UNESCAPED_UNICODE) . ',
  continue: ' . json_encode(t('voucher.continueToPay'), JSON_UNESCAPED_UNICODE) . ',
  czkChargeNote: ' . json_encode(t('currency.note.czkCharge'), JSON_UNESCAPED_UNICODE) . '
};
var GV_CURRENCY = ' . json_encode(function_exists('currencyJsConfig') ? currencyJsConfig() : ['current'=>'CZK','rates'=>[],'meta'=>[]], JSON_UNESCAPED_UNICODE) . ';
(function(){
var radios=document.querySelectorAll("input[name=value]");
var custom=document.getElementById("gv-custom");
var printCb=document.getElementById("gv-print");
var totalEl=document.getElementById("gvTotalPrice");
var czkNoteEl=document.getElementById("gvCzkNote");

// Konvertuje CZK částku na zobrazenou měnu (varianta A: backend vždy CZK)
function convert(czk){
  var cur=(GV_CURRENCY && GV_CURRENCY.current) || "CZK";
  if(cur==="CZK") return czk;
  var rate=GV_CURRENCY.rates && GV_CURRENCY.rates[cur];
  if(!rate) return czk;
  return czk/rate;
}
function fmt(czk){
  var cur=(GV_CURRENCY && GV_CURRENCY.current) || "CZK";
  var meta=(GV_CURRENCY.meta && GV_CURRENCY.meta[cur]) || {symbol:"Kč",decimals:0};
  var v=convert(czk);
  return Number(v).toLocaleString(GV_I18N.locale,{minimumFractionDigits:meta.decimals,maximumFractionDigits:meta.decimals})+" "+meta.symbol;
}
function fmtCzk(czk){return Number(czk).toLocaleString("cs-CZ")+" Kč";}
function getAmount(){
  if(custom&&custom.value&&Number(custom.value)>0)return Number(custom.value);
  var r=document.querySelector("input[name=value]:checked");
  return r?Number(r.value):0;
}
function update(){
  var a=getAmount();
  var eq=printCb&&printCb.checked?180:0;
  var totalCzk=a+eq;
  totalEl.textContent=fmt(totalCzk);
  // Když je vybrána jiná měna než CZK, zobraz info o reálné účtované CZK částce
  if(czkNoteEl){
    var cur=(GV_CURRENCY && GV_CURRENCY.current) || "CZK";
    if(cur!=="CZK"){
      czkNoteEl.textContent=GV_I18N.czkChargeNote.replace("{czk}",fmtCzk(totalCzk));
    } else { czkNoteEl.textContent=""; }
  }
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
  if(amount<100){alert(GV_I18N.errMin);return;}
  var name=document.getElementById("gv-name").value.trim();
  var email=document.getElementById("gv-email").value.trim();
  if(!name||!email){alert(GV_I18N.errFill);return;}
  var agr=document.getElementById("gvAgreement");
  if(!agr||!agr.checked){alert(GV_I18N.errAgr);return;}

  var isPrint=printCb&&printCb.checked;
  var printFee=isPrint?180:0;
  var total=amount+printFee;
  var phone=(document.getElementById("gv-phone").value||"").trim();
  var street=(document.getElementById("gv-street").value||"").trim();
  var zip=(document.getElementById("gv-zip").value||"").trim();
  var city=(document.getElementById("gv-city").value||"").trim();
  var addr=street&&zip&&city?(street+", "+zip+" "+city):null;

  var btn=document.getElementById("gvSubmitBtn");
  btn.disabled=true;btn.textContent=GV_I18N.processing;
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
    else{alert(data.error||GV_I18N.errPay);btn.disabled=false;btn.textContent=GV_I18N.continue;}
  }).catch(function(err){
    console.error("[POUKAZ]",err);
    alert(GV_I18N.errGen);
    btn.disabled=false;btn.textContent=GV_I18N.continue;
  });
});
update();
})();
</script>';

renderPage(t('voucher.pageTitle'), $content . $js, '/koupit-darkovy-poukaz', [
    'description' => t('voucher.description'),
    'keywords' => t('voucher.keywords'),
    'og_image' => 'https://motogo24.cz/gfx/darkovy-poukaz.jpg',
]);
