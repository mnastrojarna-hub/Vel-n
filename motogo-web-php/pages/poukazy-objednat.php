<?php
// ===== MotoGo24 Web PHP — Koupit dárkový poukaz (objednávkový formulář) =====

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], ['label' => t('breadcrumb.vouchers'), 'href' => '/poukazy'], t('breadcrumb.buyVoucher')]);

// SEO: linkujeme primo na /dokumenty/obchodni-podminky aby crawler nemusel
// sledovat 301 redirect (Seobility hlasil 'Internal redirect' z /koupit-darkovy-poukaz).
$agreementHtml = t('voucher.agreement', ['href' => BASE_URL . '/dokumenty/obchodni-podminky']);

// Vzhled (2026-10-23, css/voucher.css): H1 = titulek formuláře (dřív se nad drobečkovou navigaci
// vkládal obecný „MotoGo24 — půjčovna motorek“), karta s číslovanými sekcemi, plovoucí popisky polí
// (placeholdery zůstávají), částky jako dlaždice, souhrn s cenou vpravo (desktop). Pole, name/id,
// hodnoty, data-price i inline JS beze změny — odesílaný payload je stejný.
// Nové popisky sekcí: CS zde, překlady lang/v2/<lang>/voucher.php (pages.voucher_form).
$gvL = ['value_title' => 'Hodnota poukazu', 'addr_title' => 'Adresa a fakturační údaje'];
$gvTr = t('pages.voucher_form');
if (is_array($gvTr)) $gvL = array_merge($gvL, array_filter($gvTr, 'is_string'));
// Pole s plovoucím popiskem: <label> obaluje input, text popisku = text placeholderu.
$gvField = function ($attrs, $key, $cls) {
    return '<label class="gv-f ' . $cls . '"><input ' . $attrs . '><span class="gv-fl">' . te($key) . '</span></label>';
};
// Číslo sekce stojí MIMO <h2> (text nadpisu = jen název, jako checkout.php rez-section-head).
$gvSecT = function ($n, $html) {
    return '<div class="gv-sec-h"><span class="gv-sec-n" aria-hidden="true">' . $n . '</span><h2 class="gv-sec-t">' . $html . '</h2></div>';
};

$form = '<div class="gift-voucher-order gv-order">' .
    '<div class="gv-order-head"><h1>' . te('voucher.title') . '</h1>' .
    '<p>' . te('voucher.lead') . '</p></div>' .
    '<form id="giftVoucherForm" method="POST" action="" class="gv-form">' .

    '<div class="gv-sec gv-sec--who">' . $gvSecT(1, te('voucher.contactSection')) .
    '<div class="gv-fields">' .
        $gvField('type="text" name="senderName" id="gv-name" placeholder="' . te('voucher.fieldName') . '" required maxlength="255" autocomplete="name"', 'voucher.fieldName', 'gv-f--full') .
        $gvField('type="email" name="senderEmail" id="gv-email" placeholder="' . te('voucher.fieldEmail') . '" required maxlength="255" autocomplete="email"', 'voucher.fieldEmail', 'gv-f--half') .
        $gvField('type="tel" name="senderPhone" id="gv-phone" placeholder="' . te('voucher.fieldPhone') . '" maxlength="20" autocomplete="tel"', 'voucher.fieldPhone', 'gv-f--half') .
    '</div>' .
    '<div class="gv-opt" role="group" aria-labelledby="gv-opt-t"><p class="gv-opt-t" id="gv-opt-t">' . htmlspecialchars($gvL['addr_title']) . '</p>' .
    '<div class="gv-fields">' .
        $gvField('type="text" name="senderStreet" id="gv-street" placeholder="' . te('voucher.fieldStreet') . '" maxlength="255" autocomplete="street-address"', 'voucher.fieldStreet', 'gv-f--full') .
        $gvField('type="text" name="senderZipCode" id="gv-zip" placeholder="' . te('voucher.fieldZip') . '" maxlength="10" autocomplete="postal-code"', 'voucher.fieldZip', 'gv-f--third') .
        $gvField('type="text" name="senderCity" id="gv-city" placeholder="' . te('voucher.fieldCity') . '" maxlength="255" autocomplete="address-level2"', 'voucher.fieldCity', 'gv-f--third') .
        $gvField('type="text" name="senderCountry" id="gv-country" placeholder="' . te('voucher.fieldCountry') . '" maxlength="2" value="CZ" autocomplete="country"', 'voucher.fieldCountry', 'gv-f--third') .
        $gvField('type="text" name="senderCompany" id="gv-company" placeholder="' . te('voucher.fieldCompany') . '" maxlength="255" autocomplete="organization"', 'voucher.fieldCompany', 'gv-f--co') .
        $gvField('type="text" name="senderICO" id="gv-ico" placeholder="' . te('voucher.fieldIco') . '" maxlength="20"', 'voucher.fieldIco', 'gv-f--half') .
        $gvField('type="text" name="senderDIC" id="gv-dic" placeholder="' . te('voucher.fieldDic') . '" maxlength="20"', 'voucher.fieldDic', 'gv-f--half') .
    '</div></div></div>' .

    '<div class="gv-sec gv-sec--val">' . $gvSecT(2, htmlspecialchars($gvL['value_title'])) .
    '<div class="gv-values">' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="1000" checked> ' . moneyHtml(1000) . '</label>' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="2000"> ' . moneyHtml(2000) . '</label>' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="3000"> ' . moneyHtml(3000) . '</label>' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="5000"> ' . moneyHtml(5000) . '</label>' .
        '<label class="gv-value-btn"><input type="radio" name="value" value="10000"> ' . moneyHtml(10000) . '</label>' .
        '<div class="gv-custom-value">' .
            '<label>' . te('voucher.customAmount') . ' <input type="number" name="customValue" id="gv-custom" min="100" max="50000" step="1" placeholder="' . te('voucher.customPlaceholder') . '"></label>' .
        '</div>' .
    '</div></div>' .

    '<div class="gv-sec gv-sec--extra">' . $gvSecT(3, te('voucher.extras')) .
    '<div class="gv-equipments">' .
        '<label class="gv-equipment-btn">' .
            '<input type="checkbox" name="equipmentId[]" id="gv-print" value="print" data-price="180">' .
            '<div><strong>' . te('voucher.printLabel') . '</strong><br><small>' . te('voucher.printNote') . '</small></div>' .
            '<span class="gv-eq-price">' . te('voucher.printPrice') . '</span>' .
        '</label>' .
    '</div></div>' .

    '<div class="gv-sec gv-sec--sum">' . $gvSecT(4, te('checkout.summary.title')) .
    '<div class="gv-price-preview" id="gvPricePreview">' .
        '<span class="gv-sum-l">' . te('voucher.totalPrice') . '</span> <strong id="gvTotalPrice">' . moneyHtml(1000) . '</strong>' .
        ' <span class="gv-czk-note" id="gvCzkNote"></span>' .
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
    '</div></form></div>';

// CMS-editable outro pod formulářem (Velín → CMS → Texty webu → Koupit poukaz)
$sb = new SupabaseClient();
$pvDefaults = [
    'outro' => [
        'title' => 'Co o dárkovém poukazu od MotoGo24 vědět',
        'body1' => 'Dárkový poukaz na pronájem motorky je <strong>originální dárek</strong>, který udělá radost partnerovi, kamarádovi nebo rodičům. Platnost má <strong>3 roky od data vystavení</strong>, obdarovaný si sám zvolí termín výpůjčky a typ motorky podle hodnoty poukazu — od cestovních strojů přes naked motorky a supermoto až po dětské elektromotorky.',
        'body2' => 'Po zaplacení vám poukaz <strong>okamžitě dorazí na e-mail</strong> ve formě PDF, které stačí vytisknout nebo přeposlat obdarovanému. Pokud chcete tištěnou variantu na luxusním papíře, můžete ji připlatit při objednávce a my vám ji připravíme k vyzvednutí nebo pošleme poštou. Půjčujeme bez kauce, výbava pro řidiče (helma, bunda, kalhoty, rukavice) je v ceně nájmu a otevřeno máme nonstop — obdarovaný si tedy snadno najde termín, který mu sedne.',
    ],
];
$PVC = $sb->siteContent('koupit_darkovy_poukaz', $pvDefaults);
$pvOutroT = $PVC['outro']['title'] ?? $pvDefaults['outro']['title'];
$pvOutroB1 = $PVC['outro']['body1'] ?? $pvDefaults['outro']['body1'];
$pvOutroB2 = $PVC['outro']['body2'] ?? $pvDefaults['outro']['body2'];
$pvOutroHtml = '<section class="voucher-outro">'
    . '<h2 data-cms-key="web.koupit_darkovy_poukaz.outro.title">' . sanitizeHtml($pvOutroT) . '</h2>'
    . '<p data-cms-key="web.koupit_darkovy_poukaz.outro.body1">' . sanitizeHtml($pvOutroB1) . '</p>'
    . '<p data-cms-key="web.koupit_darkovy_poukaz.outro.body2">' . sanitizeHtml($pvOutroB2) . '</p>'
    . '</section>';

$content = '<main id="content" class="voucher-page gv-page"><section aria-label="' . te('breadcrumb.buyVoucher') . '" class="container">' .
    $bc . '<div class="pcontent gv-order-wrap">' . $form . $pvOutroHtml . '</div></section></main>';

$lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';
$localeMap = ['cs' => 'cs-CZ', 'en' => 'en-GB', 'de' => 'de-DE', 'es' => 'es-ES', 'fr' => 'fr-FR', 'nl' => 'nl-NL', 'pl' => 'pl-PL', 'uk' => 'uk-UA'];
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
  var addr=street&&zip&&city?(street+", "+zip+" "+city):(street||null);
  var company=(document.getElementById("gv-company").value||"").trim();
  var ico=(document.getElementById("gv-ico").value||"").trim();
  var dic=(document.getElementById("gv-dic").value||"").trim();

  var btn=document.getElementById("gvSubmitBtn");
  btn.disabled=true;btn.textContent=GV_I18N.processing;
  fetch(SUPABASE_URL+"/functions/v1/process-payment",{
    method:"POST",
    headers:{"Content-Type":"application/json","apikey":SUPABASE_ANON_KEY,"Authorization":"Bearer "+SUPABASE_ANON_KEY},
    body:JSON.stringify({
      amount:total,voucher_amount:amount,type:"shop",source:"web",
      mode:"checkout",customer_email:email,customer_name:name,
      customer_phone:phone,is_print:isPrint,
      shipping_address:isPrint?addr:null,
      billing_address:addr,
      customer_company:company||null,
      customer_ico:ico||null,
      customer_dic:dic||null,
      origin: window.location.origin,
      locale: (document.documentElement.lang||"cs").slice(0,2)
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
    'og_image' => 'https://www.motogo24.cz/gfx/darkovy-poukaz.jpg',
    'styles' => ['/css/voucher.css', '/css/voucher-form.css'],
]);
