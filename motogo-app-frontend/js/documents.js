// ===== DOCUMENTS.JS – Company constant, utilities, data fetching, VOP/GDPR/contract preview =====
// Split from original documents.js. See also: documents-booking.js, documents-pages.js

var COMPANY={name:'Bc. Petra Semorádová',ic:'21874263',sidlo:'Mezná 9, 393 01 Mezná',
  email:'info@motogo24.cz',tel:'+420 774 256 271',bank:'670100-2225851630/6210',
  note:'Nejsme plátci DPH dle §6 zákona č. 235/2004 Sb.'};

function _docDate(iso){
  var d=new Date(iso);
  return d.getDate()+'.'+(d.getMonth()+1)+'.'+d.getFullYear();
}

async function _getBookingDataAsync(bookingId){
  var b=null,m=null,p=null;
  if(_isSupabaseReady()){
    try {
      var result=await supabase.from('bookings').select('*, motorcycles(*), profiles(*)').eq('id',bookingId).single();
      if(result.data){
        b=result.data;
        m=result.data.motorcycles||null;
        p=result.data.profiles||null;
      }
    } catch(e){}
  }
  if(!b) return null;
  if(!p) p=await apiFetchProfile();
  var days=Math.max(1,Math.round((new Date(b.end_date)-new Date(b.start_date))/86400000)+1);
  return {b:b,m:m,p:p,days:days,
    motoName:m?(m.model||m.name):'Motorka',
    resNum:'#'+b.id.substr(-8).toUpperCase()};
}
function _getBookingData(bookingId){
  return null;
}

// ===== VOP (General Terms) – fetch from Velín template if available =====
async function showVOP(){
  var t=_t('doc');
  var tpl = typeof apiFetchDocTemplate === 'function' ? await apiFetchDocTemplate('vop') : null;
  var bodyHtml = '';
  if(tpl && tpl.content_html){
    bodyHtml = tpl.content_html;
  } else {
    bodyHtml = '<h3>'+t.vopTitle+'</h3><p><strong>'+COMPANY.name+'</strong>, '+t.seat+': '+COMPANY.sidlo+', IČ: '+COMPANY.ic+'</p>'+
      '<h4>1. '+t.vopSubject+'</h4><p>'+t.vopSubjectText+'</p>'+
      '<h4>2. '+t.vopRental+'</h4><p>'+t.vopRentalText+'</p>'+
      '<h4>3. '+t.vopObligations+'</h4><p>'+t.vopObligationsText+'</p>'+
      '<h4>4. '+t.vopDeposit+'</h4><p>'+t.vopDepositText+'</p>'+
      '<h4>5. '+t.vopInsurance+'</h4><p>'+t.vopInsuranceText+'</p>'+
      '<h4>6. '+t.vopCancel+'</h4><p>'+t.vopCancelText+'</p>'+
      '<h4>7. '+t.vopFinal+'</h4><p>'+t.vopFinalText+'</p>';
  }
  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
    '<h2>'+t.vopTitle+'</h2></div><div class="doc-view-body">'+bodyHtml+'</div></div>';
  _openDocOverlay(html);
}

// ===== CONTRACT PREVIEW (no booking data – just the template) =====
async function showContractPreview(){
  var t=_t('doc');
  var tpl = typeof apiFetchDocTemplate === 'function' ? await apiFetchDocTemplate('contract') : null;
  var bodyHtml = '';
  if(tpl && tpl.content_html){
    bodyHtml = tpl.content_html;
    // Replace placeholders with generic labels
    bodyHtml = bodyHtml.replace(/\{\{[^}]+\}\}/g, '___').replace(/\{[^}]+\}/g, '___');
  } else {
    bodyHtml = '<h3>'+t.contractTitle+'</h3>'+
      '<div class="doc-parties"><div class="doc-party"><strong>'+t.lessor+':</strong><br>'+
      COMPANY.name+'<br>'+COMPANY.sidlo+'<br>IČ: '+COMPANY.ic+'<br>'+COMPANY.email+'</div>'+
      '<div class="doc-party"><strong>'+t.lessee+':</strong><br>(doplní se při rezervaci)</div></div>'+
      '<h4>'+t.contractSubject+'</h4><p>Pronajímatel přenechává nájemci k užívání motorové vozidlo dle rezervace.</p>'+
      '<h4>'+t.contractPrice+'</h4><p>Cena dle platného ceníku.</p>'+
      '<h4>'+t.contractConditions+'</h4><p>'+t.contractConditionsText+'</p>';
  }
  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+t.back+'</div></div>'+
    '<h2>'+t.contractTitle+'</h2><p>Náhled vzorové smlouvy</p></div><div class="doc-view-body">'+bodyHtml+'</div></div>';
  _openDocOverlay(html);
}

// ===== GDPR – fetch from Velín template if available =====
async function showGDPR(){
  var t=_t('doc');
  var tpl = typeof apiFetchDocTemplate === 'function' ? await apiFetchDocTemplate('gdpr') : null;
  var bodyHtml = '';
  if(tpl && tpl.content_html){
    bodyHtml = tpl.content_html;
  } else {
    bodyHtml = '<h3>Zpracování osobních údajů (GDPR)</h3>'+
      '<p><strong>Správce:</strong> '+COMPANY.name+', '+COMPANY.sidlo+', IČ: '+COMPANY.ic+'</p>'+
      '<h4>1. Účel zpracování</h4><p>Osobní údaje jsou zpracovávány za účelem plnění smlouvy o pronájmu motorového vozidla, vystavení daňových dokladů a zajištění bezpečnosti provozu.</p>'+
      '<h4>2. Rozsah údajů</h4><p>Jméno, příjmení, datum narození, adresa, e-mail, telefon, číslo řidičského průkazu, platnost ŘP, kategorie ŘP.</p>'+
      '<h4>3. Právní základ</h4><p>Plnění smlouvy (čl. 6 odst. 1 písm. b) GDPR), plnění právní povinnosti (čl. 6 odst. 1 písm. c) GDPR), oprávněný zájem správce (čl. 6 odst. 1 písm. f) GDPR).</p>'+
      '<h4>4. Doba uchování</h4><p>Po dobu trvání smluvního vztahu a dále po dobu stanovenou právními předpisy (zejména daňové a účetní předpisy).</p>'+
      '<h4>5. Práva subjektu údajů</h4><p>Máte právo na přístup k údajům, opravu, výmaz, omezení zpracování, přenositelnost a právo vznést námitku. Kontakt: '+COMPANY.email+'</p>'+
      '<h4>6. Dozorový úřad</h4><p>Úřad pro ochranu osobních údajů, Pplk. Sochora 27, 170 00 Praha 7, www.uoou.cz</p>';
  }
  var html='<div class="doc-view"><div class="doc-view-hdr"><div class="back-row" onclick="closeDocView()">'+
    '<div class="bk-c">←</div><div class="bk-l">'+(t.back||'Zpět')+'</div></div>'+
    '<h2>Zpracování osobních údajů</h2></div><div class="doc-view-body">'+bodyHtml+'</div></div>';
  _openDocOverlay(html);
}
