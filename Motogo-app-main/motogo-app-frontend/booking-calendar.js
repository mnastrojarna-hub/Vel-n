// ===== BOOKING-CALENDAR.JS – Calendar, date picking, filters, edit tabs =====

// Central reset for all booking-related global state.
// Called on navigation to s-home / s-search to ensure a clean start.
function resetBookingState(){
  // Reset detail calendar state
  dStep = 1; dOd = null; dDo = null;
  // Reset booking form state
  bStep = 1; bOd = null; bDo = null;
  bookingFromDetail = false;
  // Reset extras/delivery/discount
  extraTotal = 0; deliveryFee = 0; discountAmt = 0;
  pickupDelivFee = 0; returnDelivFee = 0;
  // Reset promo code state — so re-entering same code works
  if(typeof appliedCode !== 'undefined') appliedCode = null;
  if(typeof _appliedPromoId !== 'undefined') _appliedPromoId = null;
  if(typeof _appliedBookingCodes !== 'undefined') _appliedBookingCodes = [];
  if(typeof bookingDays !== 'undefined') bookingDays = 2;
  // Edit calendar
  if(typeof eStep !== 'undefined'){ eStep = 1; }
  if(typeof eOd !== 'undefined'){ eOd = null; }
  if(typeof eDo !== 'undefined'){ eDo = null; }
  // Cart FAB: respect user's X dismiss – do not reset cartFabDismissed
  // Payment
  if(typeof _currentBookingId !== 'undefined') _currentBookingId = null;
  // SOS
  if(typeof _sosCurrentBookingId !== 'undefined') _sosCurrentBookingId = null;
  if(typeof _sosCurrentMotoId !== 'undefined') _sosCurrentMotoId = null;
}

function showDetailCal(){
  document.getElementById('d-date-summary').style.display='none';
  document.getElementById('d-cal-wrap').style.display='block';
  var hadDates=(dOd&&dDo);
  dStep=1;
  if(hadDates){
    calState.d.y=dOd.y;calState.d.m=dOd.m;
    renderDetailCal();
    if(typeof highlightDetailDates==='function') highlightDetailDates();
  } else {
    dOd=null;dDo=null;
    var calPrice=document.getElementById('d-cal-price');
    if(calPrice)calPrice.style.display='none';
    renderDetailCal();
  }
}

// Booking calendar – range selection (same as search cal)
var bStep=1,bOd=null,bDo=null;
var bookingFromDetail=false;
function showBookingCal(){
  document.getElementById('b-date-summary').style.display='none';
  document.getElementById('b-cal-wrap').style.display='block';
  bookingFromDetail=false;
  bOd=null;bDo=null;bStep=1;
  // Keep dOd/dDo intact – proceedToPayment uses them as fallback
  buildBCal();
}
function pickB(el,d,y,m){
  var h=_t('hc');
  var motoId=bookingMoto?bookingMoto.id:null;
  if(bStep===1){
    // Block past dates
    var today=AppTime.today();
    var clickDate=new Date(y,m,d);clickDate.setHours(0,0,0,0);
    if(clickDate<today){showT('⚠️',_t('res').date,_t('res').cannotSelectPast||h.cannotSelectPast);return;}
    document.querySelectorAll('#b-cal .cd').forEach(c=>{c.classList.remove('sel-od','sel-do','in-range');if(!c.disabled&&!c.classList.contains('empty')&&!c.classList.contains('unconfirmed'))c.classList.add('free');});
    el.classList.remove('free');el.classList.add('sel-od');
    bOd={d,y,m};bDo=null;bStep=2;
    document.getElementById('b-od-txt').textContent=d+'. '+(m+1)+'. '+y;
    document.getElementById('b-do-txt').textContent=_t('res').selectReturnDate||h.selectReturnDate;
    filterTimeChips();
    updateBookingPrice();
  } else {
    var returnDate=new Date(y,m,d);returnDate.setHours(0,0,0,0);
    var startDate=new Date(bOd.y,bOd.m,bOd.d);startDate.setHours(0,0,0,0);
    if(returnDate<startDate){showT('⚠️',_t('res').returnDate,_t('res').returnMustBeSameOrLater||h.returnMustBeLater);return;}
    // Validate entire range is free for this specific moto
    if(motoId&&typeof isMotoFreeForRange==='function'){
      if(!isMotoFreeForRange(motoId,startDate,returnDate)){
        showT('⚠️',_t('res').occupied||'Obsazeno',_t('res').motoNotFreeRange||h.motoNotFree);return;
      }
    }
    el.classList.remove('free');el.classList.add('sel-do');
    bDo={d,y,m};
    if(bOd&&bOd.m===m&&bOd.y===y){
      document.querySelectorAll('#b-cal .cd').forEach(c=>{
        const cd=parseInt(c.textContent);
        if(c.classList.contains('free')&&cd>bOd.d&&cd<d){c.classList.remove('free');c.classList.add('in-range');}
      });
    }
    document.getElementById('b-do-txt').textContent=d+'. '+(m+1)+'. '+y;
    bStep=1;updateBookingPrice();
    showT('📅',_t('res').dateConfirmed||'Termín vybrán',bOd.d+'.–'+d+'. '+(m+1)+'. '+y);
  }
}
// updateBookingPrice → js/cart-engine.js
var eStep=1,eOd=null,eDo=null;
var editMode='prodlouzit'; // 'prodlouzit' or 'zkratit'
var editShortenDir=null; // 'start' or 'end' — user-chosen direction for shortening
// Original reservation: dynamic based on current date
var origResStart={d:ACT_START.d,m:ACT_START.m,y:ACT_START.y};
var origResEnd={d:ACT_END.d,m:ACT_END.m,y:ACT_END.y};
function getEditResRange(){
  // Always use origResStart/origResEnd which are set from actual booking data
  return {start:origResStart,end:origResEnd};
}
function pickE(el,d,y,m){
  var h=_t('hc');
  var range=getEditResRange();
  var resEnd=range.end;
  var resStart=range.start;
  var origEndDate=new Date(resEnd.y,resEnd.m,resEnd.d);
  var origStartDate=new Date(resStart.y,resStart.m,resStart.d);
  var clickedDate=new Date(y,m,d);
  var now=AppTime.today();

  // ===== SHORTEN MODE =====
  if(editMode==='zkratit'){
    var inRes=(clickedDate>=origStartDate&&clickedDate<=origEndDate);
    if(!inRes){showT('⚠️',_t('edit').tabShorten,h.calSelectInside);return;}
    document.querySelectorAll('#e-cal .cd').forEach(function(c){c.classList.remove('sel-od','sel-do','in-range');c.style.textDecoration='';if(!c.disabled&&!c.classList.contains('empty')&&!c.classList.contains('unconfirmed'))c.classList.add('free');});
    if(editIsActive){
      // Active: only shorten end, min 1 day from today
      if(clickedDate>=origEndDate){showT('⚠️',_t('edit').tabShorten,h.calDateMustBeBefore.replace('{d}',resEnd.d+'.'+(resEnd.m+1)+'.'));return;}
      if(clickedDate<now){showT('⚠️',_t('edit').tabShorten,h.calNotInPast);return;}
      eOd={d:now.getDate(),y:now.getFullYear(),m:now.getMonth()};
      eDo={d:d,y:y,m:m};
    } else {
      // Upcoming: shorten from start or end
      var totalDays=Math.round((origEndDate-origStartDate)/86400000)+1;
      var daysFromStart=Math.round((clickedDate-origStartDate)/86400000);
      if(totalDays<=1){showT('⚠️',_t('edit').tabShorten,h.calMinLength);return;}

      // Determine direction: use user-chosen direction if set, otherwise auto-detect
      var dir=editShortenDir;
      if(!dir) dir=(daysFromStart<totalDays/2)?'start':'end';

      if(dir==='start'){
        // Shorten from start → new start (move start later)
        if(clickedDate<=origStartDate){
          // Click on first day or before = keep full reservation
          eOd={d:resStart.d,y:resStart.y,m:resStart.m};
          eDo={d:resEnd.d,y:resEnd.y,m:resEnd.m};
        } else {
          eOd={d:d,y:y,m:m};
          eDo={d:resEnd.d,y:resEnd.y,m:resEnd.m};
        }
      } else {
        // Shorten from end → new end (move end earlier)
        if(clickedDate>=origEndDate){
          // Click on last day or after = keep full reservation
          eOd={d:resStart.d,y:resStart.y,m:resStart.m};
          eDo={d:resEnd.d,y:resEnd.y,m:resEnd.m};
        } else {
          eOd={d:resStart.d,y:resStart.y,m:resStart.m};
          eDo={d:d,y:y,m:m};
        }
      }
    }
    el.classList.remove('free');el.classList.add('sel-do');
    el.style.background='#ef4444';el.style.color='#fff';
    document.querySelectorAll('#e-cal .cd').forEach(function(c){
      var cd=parseInt(c.textContent);if(isNaN(cd))return;
      var cellDate=new Date(calState.e.y,calState.e.m,cd);
      var inOrig=(cellDate>=origStartDate&&cellDate<=origEndDate);
      var newS=new Date(eOd.y,eOd.m,eOd.d);var newE=new Date(eDo.y,eDo.m,eDo.d);
      var inNew=(cellDate>=newS&&cellDate<=newE);
      if(inOrig&&!inNew){c.style.background='var(--red)';c.style.color='#fff';c.style.textDecoration='line-through';}
      else if(inOrig&&inNew){c.style.background='var(--green)';c.style.color='#fff';c.style.fontWeight='800';}
    });
    var newDays=Math.max(1,Math.round((new Date(eDo.y,eDo.m,eDo.d)-new Date(eOd.y,eOd.m,eOd.d))/86400000)+1);
    showT('✓',h.calShortened,h.calNewLength.replace('{n}',newDays+(newDays===1?' '+h.day1:newDays<5?' '+h.days24:' '+h.days5)));
    updateEditPriceSummary();
    return;
  }

  // ===== EXTEND MODE =====
  // Upcoming: extend start earlier
  if(!editIsActive&&clickedDate<origStartDate){
    if(clickedDate<now){showT('⚠️',_t('edit').tabExtend,h.calCannotPast);return;}
    var chk=new Date(clickedDate);var ok=true;
    while(chk<origStartDate){if(!isDateFree(chk.getDate(),chk.getMonth())){ok=false;break;}chk.setDate(chk.getDate()+1);}
    if(!ok){showT('⚠️',_t('edit').tabExtend,h.calDaysOccupied);return;}
    document.querySelectorAll('#e-cal .cd').forEach(function(c){c.classList.remove('sel-od','sel-do','in-range');});
    eOd={d:d,y:y,m:m};eDo={d:resEnd.d,y:resEnd.y,m:resEnd.m};
    el.classList.remove('free');el.classList.add('sel-od');
    var extra=Math.round((origStartDate-clickedDate)/86400000);
    showT('✓','+ '+extra+(extra===1?' '+h.day1:extra<5?' '+h.days24:' '+h.days5),h.calNewStart.replace('{d}',d+'.'+(m+1)+'.'+y));
    updateEditPriceSummary();highlightEditResDates();return;
  }
  // Block clicks inside reservation
  if(clickedDate>=origStartDate&&clickedDate<=origEndDate){
    showT('⚠️',_t('edit').tabExtend,editIsActive?h.calSelectAfter.replace('{d}',resEnd.d+'.'+(resEnd.m+1)+'.'):h.calSelectOutside);return;
  }
  // Extend end (active + upcoming)
  var chk2=new Date(origEndDate);chk2.setDate(chk2.getDate()+1);var ok2=true;
  while(chk2<=clickedDate){if(!isDateFree(chk2.getDate(),chk2.getMonth())){ok2=false;break;}chk2.setDate(chk2.getDate()+1);}
  if(!ok2){showT('⚠️',_t('edit').tabExtend,h.calDaysOccupied);return;}
  document.querySelectorAll('#e-cal .cd').forEach(function(c){
    c.classList.remove('sel-do','in-range');var cd2=parseInt(c.textContent);
    if(!isNaN(cd2)&&!c.disabled&&!c.classList.contains('empty')&&!c.classList.contains('occupied')&&!c.classList.contains('unconfirmed')){
      if(new Date(y,m,cd2)>origEndDate)c.classList.add('free');
    }
  });
  eOd={d:resStart.d,y:resStart.y,m:resStart.m};eDo={d:d,y:y,m:m};
  el.classList.remove('free');el.classList.add('sel-do');
  document.querySelectorAll('#e-cal .cd').forEach(function(c){
    var cd=parseInt(c.textContent);if(isNaN(cd))return;
    if(new Date(y,m,cd)>origEndDate&&new Date(y,m,cd)<clickedDate){c.classList.remove('free');c.classList.add('in-range');}
  });
  var extra2=Math.round((clickedDate-origEndDate)/86400000);
  showT('✓','+ '+extra2+(extra2===1?' '+h.day1:extra2<5?' '+h.days24:' '+h.days5),h.calNewEnd.replace('{d}',d+'.'+(m+1)+'.'+y));
  updateEditPriceSummary();highlightEditResDates();
}

// ===== SHORTEN DIRECTION TOGGLE =====
function setShortenDir(dir){
  editShortenDir=dir;
  _updateShortenDirUI();
  // Reset current selection and re-render calendar
  eOd=null;eDo=null;
  if(typeof buildECal==='function')buildECal();
  if(typeof updateEditPriceSummary==='function')updateEditPriceSummary();
}
function _updateShortenDirUI(){
  var wrap=document.getElementById('edit-shorten-dir-wrap');
  if(!wrap)return;
  if(editMode!=='zkratit'||editIsActive){wrap.style.display='none';return;}
  wrap.style.display='flex';
  var btnS=document.getElementById('edit-dir-start');
  var btnE=document.getElementById('edit-dir-end');
  if(btnS){
    btnS.style.background=editShortenDir==='start'?'var(--green)':'var(--g100)';
    btnS.style.color=editShortenDir==='start'?'#fff':'var(--g600)';
    btnS.style.borderColor=editShortenDir==='start'?'var(--green)':'var(--g200)';
  }
  if(btnE){
    btnE.style.background=editShortenDir==='end'?'var(--green)':'var(--g100)';
    btnE.style.color=editShortenDir==='end'?'#fff':'var(--g600)';
    btnE.style.borderColor=editShortenDir==='end'?'var(--green)':'var(--g200)';
  }
  var hint=document.getElementById('edit-cal-instruction');
  if(hint){
    var h=_t('hc');
    if(editShortenDir==='start')hint.textContent=h.calClickNewStart;
    else if(editShortenDir==='end')hint.textContent=h.calClickNewEnd;
    else hint.textContent=h.calChooseDir;
  }
}

// ===== EDIT DATE FROM INPUT =====
function setEditDateFromInput(type,val){
  var h=_t('hc');
  if(!val)return;
  var parts=val.split('-');
  var y=parseInt(parts[0]),m=parseInt(parts[1])-1,d=parseInt(parts[2]);
  var range=getEditResRange();
  if(type==='od'){
    eOd={d:d,m:m,y:y};
    var odInp=document.getElementById('e-od-date-input');
    if(odInp)odInp.style.borderColor='var(--green)';
  } else {
    // For extend: validate new end is after reservation end
    if(editMode==='prodlouzit'){
      var newEnd=new Date(y,m,d);
      var resEndDate=new Date(range.end.y,range.end.m,range.end.d);
      if(newEnd<=resEndDate){
        showT('⚠️',_t('edit').tabExtend,h.calDateMustBeAfter.replace('{d}',range.end.d+'.'+(range.end.m+1)+'.'));return;
      }
      eOd={d:range.start.d,m:range.start.m,y:range.start.y};
    }
    eDo={d:d,m:m,y:y};
    var doInp=document.getElementById('e-do-date-input');
    if(doInp)doInp.style.borderColor='var(--green)';
  }
  if(eOd&&eDo){
    var days=calcRentalDays(new Date(eOd.y,eOd.m,eOd.d),new Date(eDo.y,eDo.m,eDo.d));
    showT('📅',h.calDateEntered,days+(days===1?' '+h.day1:' '+h.days5));
    updateEditPriceSummary();
  }
}

// ===== FILTERS =====
function toggleFchip(el){el.classList.toggle('on');applyFilters();}
function applyFilters(){
  const cat=document.getElementById('f-cat')?.value||'';
  const rp=document.getElementById('f-rp')?.value||'';
  const vykonFilter=document.getElementById('f-vykon')?.value||'';
  const availChk=document.getElementById('f-avail-chk');
  const avail=availChk&&availChk.checked?'free':'all';
  const branch=document.getElementById('f-branch')?.value||'';
  const activeVyuziti=[...document.querySelectorAll('#fchips-wrap .fchip.on')].map(c=>c.dataset.vyuziti).filter(Boolean);
  let list=MOTOS.filter(m=>{
    if(cat&&m.cat!==cat)return false;
    if(rp&&m.rp&&m.rp!==rp&&!(rp==='A2'&&(m.rp==='A2'||m.rp==='A1'||m.rp==='N')))return false;
    if(vykonFilter==='35'&&m.vykon>35)return false;
    if(vykonFilter==='60'&&m.vykon>60)return false;
    if(vykonFilter==='61'&&m.vykon<61)return false;
    if(avail==='free'&&!isMotoFreeToday(m.id))return false;
    if(branch&&m.branch!==branch)return false;
    if(activeVyuziti.length>0&&m.vyuziti){
      if(!activeVyuziti.some(v=>m.vyuziti.includes(v)))return false;
    }
    return true;
  });
  // Filter by selected date range availability (per-motorcycle)
  if(sOd&&sDo)list=list.filter(function(m){return isMotoFreeForRange(m.id,new Date(sOd.y,sOd.m,sOd.d),new Date(sDo.y,sDo.m,sDo.d));});
  const drop=document.getElementById('avail-drop');
  drop.style.display='block';
  const termText=sOd&&sDo?` · ${sOd.d}.${sOd.m+1}.–${sDo.d}.${sDo.m+1}.`:'';
  const branchText=branch?' · '+({mezna:'Mezná'}[branch]||branch):'';
  var h=_t('hc');
  document.getElementById('avail-count-txt').textContent=list.length+' '+h.availMotos+termText+branchText;
  document.getElementById('drop-body').innerHTML=`<div class="mg-grid" style="padding:0;">${list.map(m=>mCard(m)).join('')}</div>`;
  document.getElementById('drop-arr').classList.add('open');
  document.getElementById('drop-body').classList.add('open');
}
var dropOpen=true;
function toggleDrop(){
  dropOpen=!dropOpen;
  document.getElementById('drop-arr').classList.toggle('open',dropOpen);
  document.getElementById('drop-body').classList.toggle('open',dropOpen);
}

// ===== RESERVATION FILTER & EDIT =====
var editIsActive=false;
function switchEditTab(tab){
  // origResStart/origResEnd jsou nastaveny v openEditResByBookingId
  ['prodlouzit','zkratit'].forEach(function(t){
    var btn=document.getElementById('etab-'+t);
    if(btn){btn.style.background=t===tab?'var(--green)':'transparent';btn.style.color=t===tab?'#fff':'var(--gd)';}
  });
  var note=document.getElementById('edit-shorten-note');
  if(note)note.style.display=tab==='zkratit'?'block':'none';
  var legZkr=document.getElementById('edit-leg-zkraceno');
  if(legZkr)legZkr.style.display=tab==='zkratit'?'flex':'none';
  // Return location: show on both tabs
  var retCard=document.getElementById('edit-return-location-card');
  if(retCard) retCard.style.display='block';
  // Pickup location: show for upcoming
  var pickupLocCard=document.getElementById('edit-pickup-location-card');
  var calCard=document.getElementById('edit-cal-card');
  if(!editIsActive){
    if(pickupLocCard)pickupLocCard.style.display='block';
  } else {
    if(pickupLocCard)pickupLocCard.style.display='none';
  }
  // Calendar: always show
  if(calCard)calCard.style.display='block';
  if(typeof editMode!=='undefined')editMode=tab==='zkratit'?'zkratit':'prodlouzit';
  editShortenDir=null;
  // Extras: show for upcoming
  var extrasCard=document.getElementById('edit-extras-card');
  if(extrasCard) extrasCard.style.display=editIsActive?'none':'block';
  // Branch card: only for upcoming (active = customer already has the moto)
  var branchCard=document.getElementById('edit-branch-card');
  if(branchCard) branchCard.style.display=editIsActive?'none':'block';
  // Moto change card: only for upcoming (active = customer already has the moto)
  var motoCard=document.getElementById('edit-moto-change-card');
  if(motoCard) motoCard.style.display=editIsActive?'none':'block';
  // Populate moto change list
  if(typeof populateEditMotoList==='function') populateEditMotoList();
  // Reset selection
  eStep=1;eOd=null;eDo=null;editShortenDir=null;
  _updateShortenDirUI();
  var priceSum=document.getElementById('edit-price-summary');
  if(priceSum)priceSum.style.display='none';
  buildECal();
  // Update calendar instruction text
  var calInstruction=document.getElementById('edit-cal-instruction');
  if(calInstruction){
    var h=_t('hc');
    if(tab==='prodlouzit'){
      var range=getEditResRange();
      if(editIsActive){
        calInstruction.textContent=h.calClickAfter.replace('{d}',range.end.d+'.'+(range.end.m+1)+'.');
      } else {
        calInstruction.textContent=h.calClickBeforeOrAfter.replace('{d1}',range.start.d+'.'+(range.start.m+1)+'.').replace('{d2}',range.end.d+'.'+(range.end.m+1)+'.');
      }
    } else if(tab==='zkratit'){
      if(editIsActive){
        calInstruction.textContent=h.calClickNewReturn.replace('{d}',getEditResRange().end.d+'.'+(getEditResRange().end.m+1)+'.');
      } else {
        calInstruction.textContent=h.calChooseDir;
      }
    }
  }
}
