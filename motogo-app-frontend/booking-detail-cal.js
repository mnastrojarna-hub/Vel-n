// ===== BOOKING-DETAIL-CAL.JS – Reservation detail, calendar builders & booking date helpers =====
// Split from booking-detail.js
// Contains: openResDetail, openDoneDetail, calendar building (buildCal, calNav, buildSCal,
//           buildBCal, buildECal, prev/nextMonth variants, renderDetailCal, highlightEditResDates),
//           Object.defineProperties for backward-compat getters,
//           booking date input helpers (toggleBookingDateInput, setBookingDateFromInput)
// Depends on: booking-detail.js (dIdx, dList, calState, sStep, sOd, sDo, dStep, dOd, dDo),
//             database.js (MOTOS, MONTHS, TODAY_Y, TODAY_M, UPC_START, UPC_END, ACT_START, ACT_END),
//             booking-logic.js (bookingMoto, bookingDays), js/router.js (goTo, genCal),
//             ui-controller.js (showT, isTodayFree, fmtDate, fmtDateShort, applyFilters),
//             js/cart-engine.js (updateBookingPrice, filterTimeChips),
//             booking-edit.js (switchEditTab, editIsActive, origResStart, origResEnd)

// ===== RESERVATION DETAIL =====
function openResDetail(type){
  const isNad=type.includes('nadchazejici');
  const isAkt=type.includes('aktivni');
  const isEdit=type.includes('upravit');

  if(isEdit){
    // Open edit screen
    editIsActive=isAkt;
    document.getElementById('edit-subtitle').textContent=isNad?'BMW R 1200 GS · #RES-'+UPC_START.y+'-0043':'Jawa RVM 500 · #RES-'+ACT_START.y+'-0031';
    // Show date range and duration in header
    var durEl=document.getElementById('edit-res-duration');
    var dateRangeEl=document.getElementById('edit-res-dates');
    if(durEl){
      var now=AppTime.today();
      if(isAkt){
        var endDate=new Date(ACT_END.y,ACT_END.m,ACT_END.d);
        var remaining=Math.max(0,Math.round((endDate-now)/86400000))+1;
        durEl.textContent=_t('res').activeRemaining+' '+remaining+(remaining===1?' '+_t('res').day1:remaining<5?' '+_t('res').days2:' '+_t('res').days5);
        if(dateRangeEl)dateRangeEl.textContent='Rezervováno '+fmtDateShort(ACT_START.d,ACT_START.m)+' – '+fmtDate(ACT_END.d,ACT_END.m,ACT_END.y);
      } else {
        var startDate=new Date(UPC_START.y,UPC_START.m,UPC_START.d);
        var daysTo=Math.max(0,Math.round((startDate-now)/86400000));
        var upcLen=Math.round((new Date(UPC_END.y,UPC_END.m,UPC_END.d)-startDate)/86400000)+1;
        durEl.textContent=_t('res').upcomingIn+' '+daysTo+(daysTo===1?' '+_t('res').day1:daysTo<5?' '+_t('res').days2:' '+_t('res').days5)+' · '+(_t('res').rentalDuration||'délka')+' '+upcLen+(upcLen===1?' '+_t('res').day1:upcLen<5?' '+_t('res').days2:' '+_t('res').days5);
        if(dateRangeEl)dateRangeEl.textContent='Rezervováno '+fmtDateShort(UPC_START.d,UPC_START.m)+' – '+fmtDate(UPC_END.d,UPC_END.m,UPC_END.y);
      }
    }
    buildECal();
    // Populate calendar reservation header
    var calResDates=document.getElementById('edit-cal-res-dates');
    var calResMoto=document.getElementById('edit-cal-res-moto');
    var calResInfo=document.getElementById('edit-res-info-cal');
    if(isAkt){
      if(calResDates)calResDates.textContent=fmtDateShort(ACT_START.d,ACT_START.m)+' – '+fmtDate(ACT_END.d,ACT_END.m,ACT_END.y);
      if(calResMoto)calResMoto.textContent='Jawa RVM 500 · #RES-'+ACT_START.y+'-0031';
      if(calResInfo){calResInfo.querySelector('div').textContent=_t('res').yourActiveRes;}
    } else {
      if(calResDates)calResDates.textContent=fmtDateShort(UPC_START.d,UPC_START.m)+' – '+fmtDate(UPC_END.d,UPC_END.m,UPC_END.y);
      if(calResMoto)calResMoto.textContent='BMW R 1200 GS · #RES-'+UPC_START.y+'-0043';
      if(calResInfo){calResInfo.querySelector('div').textContent=_t('res').yourUpcomingRes;}
    }
    // Show/hide shorten warning
    document.getElementById('edit-shorten-note').style.display='none';
    var priceSum=document.getElementById('edit-price-summary');
    if(priceSum)priceSum.style.display='none';
    var saveBtn=document.getElementById('edit-save-btn');
    if(saveBtn)saveBtn.textContent=_t('res').saveChanges;
    switchEditTab('prodlouzit');
    goTo('s-edit-res');
    return;
  }

  // Determine if reservation is within 7 days (for demo: upcoming = within 7 days)
  const daysAway=isNad?2:0;

  if(isNad){
    document.getElementById('rd-title').textContent='BMW R 1200 GS Adventure';
    document.getElementById('rd-subtitle').textContent='#RES-'+UPC_START.y+'-0043 · Nadcházející';
    document.getElementById('rd-moto-img').src='https://images.unsplash.com/photo-1558981359-219d6364c9c8?w=800&q=80';
    document.getElementById('rd-moto-name').textContent='BMW R 1200 GS Adventure';
    document.getElementById('rd-pickup').textContent=fmtDate(UPC_START.d,UPC_START.m,UPC_START.y)+' v 9:00';
    document.getElementById('rd-return').textContent=fmtDate(UPC_END.d,UPC_END.m,UPC_END.y)+' v 9:00';
    const upcDays=Math.round((new Date(UPC_END.y,UPC_END.m,UPC_END.d)-new Date(UPC_START.y,UPC_START.m,UPC_START.d))/(86400000))+1;
    document.getElementById('rd-duration').textContent=upcDays+(upcDays===1?' den':' dny');
    document.getElementById('rd-total').textContent=(2600*upcDays).toLocaleString('cs-CZ')+' Kč';

    const banner=document.getElementById('rd-banner');
    banner.style.display='block';
    // Within 7 days – can extend or cancel without refund
    banner.className='rd-info-banner rd-banner-warn';
    banner.innerHTML='⚠️ '+_t('res').cancelWarning48h;

    document.getElementById('rd-actions').innerHTML=`
      <button class="rd-btn rd-btn-g" onclick="openResDetail('nadchazejici-upravit')">✏️ Upravit / Prodloužit rezervaci</button>
      <button class="rd-btn rd-btn-r" onclick="openStornoDialog()">🗑️ Stornovat</button>
    `;
  } else {
    // Active
    document.getElementById('rd-title').textContent='Jawa RVM 500 Adventure';
    document.getElementById('rd-subtitle').textContent='#RES-'+ACT_START.y+'-0031 · Aktivní';
    document.getElementById('rd-moto-img').src='https://images.unsplash.com/photo-1609630875171-b1321377ee65?w=800&q=80';
    document.getElementById('rd-moto-name').textContent='Jawa RVM 500 Adventure';
    document.getElementById('rd-pickup').textContent=fmtDate(ACT_START.d,ACT_START.m,ACT_START.y)+' v 9:00';
    document.getElementById('rd-return').textContent=fmtDate(ACT_END.d,ACT_END.m,ACT_END.y)+' v 9:00';
    const actDays=Math.round((new Date(ACT_END.y,ACT_END.m,ACT_END.d)-new Date(ACT_START.y,ACT_START.m,ACT_START.d))/(86400000))+1;
    document.getElementById('rd-duration').textContent=actDays+(actDays===1?' den':' dny');
    document.getElementById('rd-total').textContent=(2200*actDays).toLocaleString('cs-CZ')+' Kč';

    const banner=document.getElementById('rd-banner');
    banner.style.display='block';
    banner.className='rd-info-banner rd-banner-info';
    banner.innerHTML='✅ '+_t('res').activeRentalBanner;

    document.getElementById('rd-actions').innerHTML=`
      <button class="rd-btn rd-btn-g" onclick="openResDetail('aktivni-upravit')">✏️ Upravit rezervaci</button>
      <button class="rd-btn" style="background:#fee2e2;color:#b91c1c;border:2px solid #fca5a5;font-family:var(--font);font-size:13px;font-weight:700;padding:13px 18px;border-radius:var(--rsm);cursor:pointer;width:100%;text-align:center;display:block;margin-top:8px;" onclick="goTo('s-sos')">🆘 Nahlásit poruchu</button>
      <div style="margin-top:8px;font-size:11px;color:#6b7280;font-weight:500;padding:8px;background:var(--g100);border-radius:var(--rsm);">ℹ️ Storno podmínky: více než 7 dní předem = plná refundace · 48 h–7 dní = 50 % vrácení · do 48 h = bez vrácení</div>
    `;
  }
  goTo('s-res-detail');
}

function openDoneDetail(id){
  const m=MOTOS.find(x=>x.id===id)||MOTOS[0];
  document.getElementById('done-img').src=m.img;
  document.getElementById('done-moto').textContent=m.name;
  document.getElementById('done-sub').textContent=id==='benelli'?'#RES-2025-0018':'#RES-2025-0009';
  goTo('s-done-detail');
}

// ===== CALENDAR =====
// Getters for backward compat with pick functions
Object.defineProperties(window,{
  sCurY:{get(){return calState.s.y},set(v){calState.s.y=v}},
  sCurM:{get(){return calState.s.m},set(v){calState.s.m=v}},
  bCurY:{get(){return calState.b.y},set(v){calState.b.y=v}},
  bCurM:{get(){return calState.b.m},set(v){calState.b.m=v}},
  eCurY:{get(){return calState.e.y},set(v){calState.e.y=v}},
  eCurM:{get(){return calState.e.m},set(v){calState.e.m=v}},
  dCurY:{get(){return calState.d.y},set(v){calState.d.y=v}},
  dCurM:{get(){return calState.d.m},set(v){calState.d.m=v}}
});

// genCal → js/router.js

// Calendar builders and navigation
function buildCal(k){const c=calState[k];var _mo=_t('months')||MONTHS;document.getElementById(c.monthId).textContent=(_mo[c.m]||MONTHS[c.m])+' '+c.y;document.getElementById(c.gridId).innerHTML=genCal(c.y,c.m,c.fn,c.motoId||null);}
function calNav(k,dir){const c=calState[k];c.m+=dir;if(c.m>11){c.m=0;c.y++;}if(c.m<0){c.m=11;c.y--;}buildCal(k);}

// Preserve original function names (called from HTML onclick)
function buildSCal(){buildCal('s');}
function buildBCal(){buildCal('b');}
function buildECal(){
  buildCal('e');
  // Highlight calendar with original reservation + new/shortened days
  var resStart = origResStart || {d:0,m:0,y:0};
  var resEnd = origResEnd || {d:0,m:0,y:0};
  var cs = calState.e;
  var origS = new Date(resStart.y, resStart.m, resStart.d);
  var origE = new Date(resEnd.y, resEnd.m, resEnd.d);
  var newS = (typeof eOd !== 'undefined' && eOd) ? new Date(eOd.y, eOd.m, eOd.d) : origS;
  var newE = (typeof eDo !== 'undefined' && eDo) ? new Date(eDo.y, eDo.m, eDo.d) : origE;

  document.querySelectorAll('#e-cal .cd').forEach(function(c){
    var cd = parseInt(c.textContent);
    if(isNaN(cd) || c.classList.contains('empty')) return;
    var cellDate = new Date(cs.y, cs.m, cd);

    var inOrig = (cellDate >= origS && cellDate <= origE);
    var inNew = (cellDate >= newS && cellDate <= newE);

    if(inOrig && inNew){
      // Stávající den (zůstává)
      c.style.background = 'var(--green)'; c.style.color = '#fff'; c.style.fontWeight = '800';
    } else if(!inOrig && inNew){
      // Nově přidaný den
      c.style.background = 'var(--green)'; c.style.color = '#fff'; c.style.fontWeight = '800';
    } else if(inOrig && !inNew){
      // Zkrácený den
      c.style.background = 'var(--red)'; c.style.color = '#fff'; c.style.fontWeight = '800';
    }
  });
}
function prevMonthB(){calNav('b',-1);}
function nextMonthB(){calNav('b',1);}
function prevMonthE(){calNav('e',-1);highlightEditResDates();}
function nextMonthE(){calNav('e',1);highlightEditResDates();}
function highlightEditResDates(){
  // Reuse buildECal highlighting which now handles orig vs new days
  var resStart = origResStart || {d:0,m:0,y:0};
  var resEnd = origResEnd || {d:0,m:0,y:0};
  var cs = calState.e;
  var origS = new Date(resStart.y, resStart.m, resStart.d);
  var origE = new Date(resEnd.y, resEnd.m, resEnd.d);
  var newS = (typeof eOd !== 'undefined' && eOd) ? new Date(eOd.y, eOd.m, eOd.d) : origS;
  var newE = (typeof eDo !== 'undefined' && eDo) ? new Date(eDo.y, eDo.m, eDo.d) : origE;

  document.querySelectorAll('#e-cal .cd').forEach(function(c){
    var cd = parseInt(c.textContent);
    if(isNaN(cd) || c.classList.contains('empty')) return;
    var cellDate = new Date(cs.y, cs.m, cd);
    var inOrig = (cellDate >= origS && cellDate <= origE);
    var inNew = (cellDate >= newS && cellDate <= newE);
    if(inOrig && inNew){
      c.style.background = 'var(--green)'; c.style.color = '#fff'; c.style.fontWeight = '800';
    } else if(!inOrig && inNew){
      c.style.background = 'var(--green)'; c.style.color = '#fff'; c.style.fontWeight = '800';
    } else if(inOrig && !inNew){
      c.style.background = 'var(--red)'; c.style.color = '#fff'; c.style.fontWeight = '800';
    }
  });
}
function prevMonth(){calNav('s',-1);highlightSearchDates();}
function nextMonth(){calNav('s',1);highlightSearchDates();}
function highlightSearchDates(){
  if(typeof sOd==='undefined'&&typeof sDo==='undefined')return;
  var cs=calState.s;
  document.querySelectorAll('#s-cal .cd').forEach(function(c){
    var cd=parseInt(c.textContent);
    if(isNaN(cd)||c.classList.contains('empty'))return;
    if(sOd&&sOd.m===cs.m&&sOd.y===cs.y&&cd===sOd.d){c.classList.remove('free');c.classList.add('sel-od');}
    if(sDo&&sDo.m===cs.m&&sDo.y===cs.y&&cd===sDo.d){c.classList.remove('free');c.classList.add('sel-do');}
    if(sOd&&sDo&&sOd.m===cs.m&&sDo.m===cs.m&&sOd.y===cs.y&&sDo.y===cs.y&&cd>sOd.d&&cd<sDo.d){
      c.classList.remove('free');c.classList.add('in-range');
    }
  });
}
function prevMonthD(){calNav('d',-1);if(typeof highlightDetailDates==='function')highlightDetailDates();}
function nextMonthD(){calNav('d',1);if(typeof highlightDetailDates==='function')highlightDetailDates();}
function renderDetailCal(){buildCal('d');}
function highlightDetailDates(){
  if(!dOd||!dDo)return;
  var cs=calState.d;
  var startDate=new Date(dOd.y,dOd.m,dOd.d);
  var endDate=new Date(dDo.y,dDo.m,dDo.d);
  document.querySelectorAll('#d-cal .cd').forEach(function(c){
    var cd=parseInt(c.textContent);
    if(isNaN(cd)||c.classList.contains('empty')||c.disabled)return;
    var cellDate=new Date(cs.y,cs.m,cd);
    if(cellDate.getTime()===startDate.getTime()){c.classList.remove('free');c.classList.add('sel-od');}
    else if(cellDate.getTime()===endDate.getTime()){c.classList.remove('free');c.classList.add('sel-do');}
    else if(cellDate>startDate&&cellDate<endDate){c.classList.remove('free');c.classList.add('in-range');}
  });
}
// Calendar init is called from app.js initApp()

function toggleBookingDateInput(type){
  var inp=document.getElementById('b-'+type+'-date-input');
  var txt=document.getElementById('b-'+type+'-txt');
  if(!inp)return;
  if(inp.style.display==='none'){
    inp.style.display='block';
    if(txt)txt.style.display='none';
    inp.focus();
  } else {
    inp.style.display='none';
    if(txt)txt.style.display='block';
  }
}
function setBookingDateFromInput(type,val){
  if(!val)return;
  var parts=val.split('-');
  var y=parseInt(parts[0]),m=parseInt(parts[1])-1,d=parseInt(parts[2]);
  // Block past dates
  var today=AppTime.today();
  var picked=new Date(y,m,d);picked.setHours(0,0,0,0);
  if(picked<today){showT('⚠️',_t('res').date,_t('res').cannotSelectPast||'Nelze vybrat datum v minulosti');return;}
  if(type==='od'){
    bOd={d:d,m:m,y:y};
    var txt=document.getElementById('b-od-txt');
    if(txt){txt.textContent=d+'. '+(m+1)+'. '+y;txt.style.display='block';}
    var inp=document.getElementById('b-od-date-input');
    if(inp)inp.style.display='none';
  } else {
    if(bOd){
      var startDate=new Date(bOd.y,bOd.m,bOd.d);startDate.setHours(0,0,0,0);
      if(picked<startDate){showT('⚠️',_t('res').returnDate,_t('res').returnMustBeSameOrLater||'Musí být stejné nebo pozdější');return;}
      // Validate range free for this moto
      var motoId=bookingMoto?bookingMoto.id:null;
      if(motoId&&typeof isMotoFreeForRange==='function'){
        if(!isMotoFreeForRange(motoId,startDate,picked)){
          showT('⚠️',_t('res').occupied||'Obsazeno',_t('res').motoNotFreeRange||'Motorka není v celém zvoleném období volná');return;
        }
      }
    }
    bDo={d:d,m:m,y:y};
    var txt2=document.getElementById('b-do-txt');
    if(txt2){txt2.textContent=d+'. '+(m+1)+'. '+y;txt2.style.display='block';}
    var inp2=document.getElementById('b-do-date-input');
    if(inp2)inp2.style.display='none';
  }
  if(bOd&&bDo){
    bStep=1;bookingFromDetail=true;
    updateBookingPrice();filterTimeChips();
    showT('📅',_t('res').dateConfirmed||'Termín aktualizován',bOd.d+'.'+(bOd.m+1)+'.–'+bDo.d+'.'+(bDo.m+1)+'.');
  }
}
