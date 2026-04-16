// ===== SEARCH CALENDAR STATE =====
// MONTHS is defined in database.js
var sStep=1,sOd=null,sDo=null;

// Calendar state and unified navigation (shared with booking-detail-cal.js)
const calState={
  s:{y:TODAY_Y,m:TODAY_M,gridId:'s-cal',monthId:'cal-month-name',fn:'pickS',motoId:null},
  b:{y:TODAY_Y,m:TODAY_M,gridId:'b-cal',monthId:'b-month-name',fn:'pickB',motoId:null},
  e:{y:TODAY_Y,m:TODAY_M,gridId:'e-cal',monthId:'e-month-name',fn:'pickE',motoId:null},
  d:{y:TODAY_Y,m:TODAY_M,gridId:'d-cal',monthId:'d-cal-month',fn:'pickD',motoId:null}
};

function pickS(el,d,y,m){
  if(sStep===1){
    // Block past dates
    var today=AppTime.today();
    var clickDate=new Date(y,m,d);clickDate.setHours(0,0,0,0);
    if(clickDate<today){showT('⚠️',_t('res').date,_t('res').cannotSelectPast||'Nelze vybrat datum v minulosti');return;}
    document.querySelectorAll('#s-cal .cd').forEach(c=>{c.classList.remove('sel-od','sel-do','in-range');if(!c.disabled&&!c.classList.contains('empty'))c.classList.add('free');});
    el.classList.remove('free');el.classList.add('sel-od');
    sOd={d,y,m};
    document.getElementById('dbv-od').textContent=d+'. '+(m+1)+'. '+y;
    document.getElementById('dbv-od').classList.remove('ph');
    document.getElementById('db-od').classList.remove('focus');document.getElementById('db-do').classList.add('focus');
    document.getElementById('cal-step-el').textContent='2';document.getElementById('cal-label-el').textContent=_t('res').selectReturnDate||'Nyní vyberte datum vrácení';
    sStep=2;sDo=null;
  } else {
    var returnDate=new Date(y,m,d);returnDate.setHours(0,0,0,0);
    var startDate=new Date(sOd.y,sOd.m,sOd.d);startDate.setHours(0,0,0,0);
    if(returnDate<startDate){showT('⚠️',_t('res').returnDate,_t('res').returnMustBeSameOrLater||'musí být stejný nebo pozdější den');return;}
    el.classList.remove('free');el.classList.add('sel-do');
    sDo={d,y,m};
    if(sOd&&sOd.m===m&&sOd.y===y){
      document.querySelectorAll('#s-cal .cd.free').forEach(c=>{const cd=parseInt(c.textContent);if(cd>sOd.d&&cd<d){c.classList.remove('free');c.classList.add('in-range');}});
    }
    document.getElementById('dbv-do').textContent=d+'. '+(m+1)+'. '+y;
    document.getElementById('dbv-do').classList.remove('ph');
    document.getElementById('db-do').classList.remove('focus');
    var days2=Math.max(1,Math.round((returnDate-startDate)/86400000)+1);
    document.getElementById('cal-step-el').textContent='✓';
    document.getElementById('cal-label-el').textContent=(_t('res').dateConfirmed||'Termín vybrán')+' ('+days2+(days2===1?' '+_t('res').day1:' '+_t('res').days2)+')';
    sStep=1;applyFilters();
  }
}

function setSearchDateFromInput(type, val){
  if(!val) return;
  var parts = val.split('-');
  var y = parseInt(parts[0]);
  var m = parseInt(parts[1]) - 1;
  var d = parseInt(parts[2]);
  // Block past dates
  var today=AppTime.today();
  var picked=new Date(y,m,d);picked.setHours(0,0,0,0);
  if(picked<today){showT('⚠️',_t('res').date,_t('res').cannotSelectPast||'Nelze vybrat datum v minulosti');return;}

  if(type === 'od'){
    sOd = {d:d, y:y, m:m};
    document.getElementById('dbv-od').textContent = d+'. '+(m+1)+'. '+y;
    document.getElementById('dbv-od').classList.remove('ph');
    document.getElementById('db-od').classList.remove('focus');
    document.getElementById('db-do').classList.add('focus');
    sStep = 2; sDo = null;
    document.getElementById('cal-step-el').textContent = '2';
    document.getElementById('cal-label-el').textContent = _t('res').selectReturnDate||'Nyní vyberte datum vrácení';
    calState.s.y = y; calState.s.m = m;
    buildCal('s');
    if(typeof highlightSearchDates==='function')highlightSearchDates();
  } else {
    if(sOd && (y < sOd.y || (y === sOd.y && m < sOd.m) || (y === sOd.y && m === sOd.m && d < sOd.d))){
      showT('⚠️',_t('res').returnDate,_t('res').returnMustBeSameOrLater||'Musí být stejný nebo pozdější den');
      return;
    }
    sDo = {d:d, y:y, m:m};
    document.getElementById('dbv-do').textContent = d+'. '+(m+1)+'. '+y;
    document.getElementById('dbv-do').classList.remove('ph');
    document.getElementById('db-do').classList.remove('focus');
    var days = (sOd && sDo) ? Math.max(1, Math.round((new Date(sDo.y,sDo.m,sDo.d)-new Date(sOd.y,sOd.m,sOd.d))/86400000)+1) : 1;
    document.getElementById('cal-step-el').textContent = '✓';
    document.getElementById('cal-label-el').textContent = (_t('res').dateConfirmed||'Termín vybrán')+' ('+days+(days===1?' '+_t('res').day1:' '+_t('res').days2)+')';
    sStep = 1;
    if(sOd){calState.s.y=sOd.y;calState.s.m=sOd.m;}
    buildCal('s');
    if(typeof highlightSearchDates==='function')highlightSearchDates();
    applyFilters();
  }
}
