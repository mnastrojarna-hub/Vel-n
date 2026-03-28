// ===== BOOKING-DETAIL.JS – Detail page & search calendar picking =====
// Split from booking-logic.js
// Calendar builders, reservation detail & booking date helpers → booking-detail-cal.js
// Depends on: database.js (MOTOS, MONTHS, TODAY_Y, TODAY_M, UPC_START, UPC_END, ACT_START, ACT_END),
//             booking-logic.js (bookingMoto, bookingDays), js/router.js (goTo, genCal),
//             ui-controller.js (showT, isTodayFree, fmtDate, fmtDateShort, applyFilters),
//             js/cart-engine.js (updateBookingPrice, filterTimeChips),
//             booking-edit.js (switchEditTab, editIsActive, origResStart, origResEnd)

// ===== DETAIL =====
var dIdx=0,dList=[...MOTOS];
function openDetail(id){
  // Pokud enrichMOTOS ještě nedoběhlo, počkej
  if(!window._enrichMOTOSDone && typeof enrichMOTOS === 'function'){
    enrichMOTOS().then(function(){
      dList=[...MOTOS];
      var i=dList.findIndex(function(m){return m.id===id||(m._db&&m._db.id===id);});
      dIdx=i>=0?i:0;
      goTo('s-detail');
      renderDetail();
    });
    return;
  }
  dList=[...MOTOS]; // Refresh seznam z aktuálního MOTOS (po enrichMOTOS)
  const i=dList.findIndex(m=>m.id===id||(m._db&&m._db.id===id));
  dIdx=i>=0?i:0;
  goTo('s-detail');   // navigate first (resets dOd/dDo)
  renderDetail();     // then render (sets dOd/dDo from sOd/sDo if available)
}
function prevMoto(){dIdx=(dIdx-1+dList.length)%dList.length;renderDetail();}
function nextMoto(){dIdx=(dIdx+1)%dList.length;renderDetail();}
var detImgIdx=0;
function detSlide(dir){
  const cont=document.getElementById('d-img-wrap');if(!cont)return;
  const imgs=cont.querySelectorAll('img');
  const dots=document.querySelectorAll('#d-dots .det-dot');
  const n=imgs.length;
  detImgIdx=((detImgIdx+dir)+n)%n;
  imgs.forEach((img,i)=>{img.style.opacity=i===detImgIdx?'1':'0';});
  dots.forEach((d,i)=>{d.classList.toggle('on',i===detImgIdx);});
}
function detSlideTo(i){
  const cont=document.getElementById('d-img-wrap');if(!cont)return;
  const imgs=cont.querySelectorAll('img');
  const dots=document.querySelectorAll('#d-dots .det-dot');
  detImgIdx=i;
  imgs.forEach((img,j)=>{img.style.opacity=j===i?'1':'0';});
  dots.forEach((d,j)=>{d.classList.toggle('on',j===i);});
}
var dStep=1,dOd=null,dDo=null;
function pickD(el,d,y,m){
  var motoId=dList[dIdx]?dList[dIdx].id:null;
  if(dStep===1){
    // Block past dates
    var today=AppTime.today();
    var clickDate=new Date(y,m,d);clickDate.setHours(0,0,0,0);
    if(clickDate<today){showT('⚠️',_t('res').date,_t('res').cannotSelectPast||'Nelze vybrat datum v minulosti');return;}
    document.querySelectorAll('#d-cal .cd').forEach(c=>{c.classList.remove('sel-od','sel-do','in-range');if(!c.disabled&&!c.classList.contains('empty')&&!c.classList.contains('unconfirmed'))c.classList.add('free');});
    el.classList.remove('free');el.classList.add('sel-od');
    dOd={d,y,m};dDo=null;dStep=2;
    showT('📅',_t('res').pickup+': '+d+'.'+(m+1)+'.'+y,_t('res').selectReturnDate||'Nyní vyberte datum vrácení');
  } else {
    var returnDate=new Date(y,m,d);returnDate.setHours(0,0,0,0);
    var startDate=new Date(dOd.y,dOd.m,dOd.d);startDate.setHours(0,0,0,0);
    if(returnDate<startDate){showT('⚠️',_t('res').returnDate,_t('res').returnMustBeSameOrLater||'Musí být stejné nebo pozdější');return;}
    // Validate entire range is free for this specific moto
    if(motoId&&typeof isMotoFreeForRange==='function'){
      if(!isMotoFreeForRange(motoId,startDate,returnDate)){
        showT('⚠️',_t('res').occupied||'Obsazeno',_t('res').motoNotFreeRange||'Motorka není v celém zvoleném období volná');return;
      }
    }
    el.classList.remove('free');el.classList.add('sel-do');
    dDo={d,y,m};
    if(dOd&&dOd.m===m&&dOd.y===y){
      document.querySelectorAll('#d-cal .cd').forEach(c=>{
        const cd=parseInt(c.textContent);
        if(c.classList.contains('free')&&cd>dOd.d&&cd<d){c.classList.remove('free');c.classList.add('in-range');}
      });
    }
    dStep=1;
    const days=Math.max(1,Math.round((returnDate-startDate)/86400000)+1);
    // Show total price under calendar
    var dm=dList[dIdx];
    if(dm&&dm.pricing){
      var dayMap=[dm.pricing.ne,dm.pricing.po,dm.pricing.ut,dm.pricing.st,dm.pricing.ct,dm.pricing.pa,dm.pricing.so];
      var tp=0;var dd=new Date(startDate);
      while(dd<=returnDate){tp+=dayMap[dd.getDay()]||dm.pricing.po||0;dd.setDate(dd.getDate()+1);}
      var prEl=document.getElementById('d-cal-price');
      var prVal=document.getElementById('d-cal-price-val');
      if(prEl){prEl.style.display='block';}
      if(prVal){prVal.textContent=tp.toLocaleString('cs-CZ')+' Kč';}
    }
    showT('📅',days+(days===1?' '+_t('res').day1:' '+_t('res').days5)+' '+(_t('res').rentalDuration||'výpůjčky'),_t('res').goToBooking||'Přejděte k rezervaci');
    // Enable CTA button when valid dates are selected
    var ctaBtn=document.getElementById('d-cta');
    if(ctaBtn){
      ctaBtn.textContent=(_t('res').bookMotoBtn||'Rezervovat motorku')+' →';
      ctaBtn.style.background='var(--green)';
      ctaBtn.disabled=false;
      ctaBtn.style.pointerEvents='auto';
    }
    // Collapse calendar to date summary to prevent accidental re-clicks
    var dDateSum=document.getElementById('d-date-summary');
    var dCalWr=document.getElementById('d-cal-wrap');
    if(dDateSum){
      document.getElementById('d-od-txt').textContent=dOd.d+'. '+(dOd.m+1)+'. '+dOd.y;
      document.getElementById('d-do-txt').textContent=dDo.d+'. '+(dDo.m+1)+'. '+dDo.y;
      dDateSum.style.display='block';
    }
    if(dCalWr)dCalWr.style.display='none';
  }
}

function renderDetail(){
  const m=dList[dIdx];
  // Reset price display from previous detail visit
  var calPriceReset=document.getElementById('d-cal-price');
  if(calPriceReset) calPriceReset.style.display='none';
  var calPriceValReset=document.getElementById('d-cal-price-val');
  if(calPriceValReset) calPriceValReset.textContent='0 Kč';
  const wrap=document.getElementById('d-img-wrap');
  if(wrap){
    const imgs2=(m.imgs||[m.img||'']).filter(Boolean);
    // Keep the gradient overlay and nav buttons, replace images
    const grad=wrap.querySelector('.det-grad');
    const navBtns=wrap.querySelector('.det-nav-btns');
    const oldImgs=wrap.querySelectorAll('img');
    oldImgs.forEach(i=>i.remove());
    const frag=document.createDocumentFragment();
    imgs2.forEach((src,i)=>{
      const img=document.createElement('img');
      img.src=src;img.alt=m.name;
      img.style.cssText='position:absolute;inset:0;width:100%;height:100%;object-fit:cover;transition:opacity .3s;opacity:'+(i===0?'1':'0')+';';
      frag.appendChild(img);
    });
    if(grad)wrap.insertBefore(frag,grad);
    else wrap.appendChild(frag);
  }
  const nameEl=document.getElementById('d-name');if(nameEl)nameEl.textContent=m.name;
  const locEl=document.getElementById('d-loc');if(locEl)locEl.textContent=m.loc;
  const brEl=document.getElementById('d-branch');
  if(brEl){var _bl=_t('pricingL')||{};var _bp=_bl.branch||'Pobočka';brEl.textContent=_bp+': '+m.loc;}
  // Check per-motorcycle availability: use selected dates if available, otherwise today
  var motoFree;
  if(sOd && sDo){
    motoFree=isMotoFreeForRange(m.id,new Date(sOd.y,sOd.m,sOd.d),new Date(sDo.y,sDo.m,sDo.d));
  } else {
    motoFree=isMotoFreeToday(m.id);
  }
  const avl=document.getElementById('d-avl');
  if(avl){avl.textContent=motoFree?('✓ '+(_t('res').availableNow||'Dostupná – rezervuj hned')):('✗ '+(_t('res').occupiedNow||'Momentálně obsazená'));avl.style.background=motoFree?'var(--gp)':'var(--g100)';avl.style.color=motoFree?'var(--gd)':'var(--g600)';}
  var _mt=_t('moto')||{};var _tr=_mt[m.id]||{};
  const descEl=document.getElementById('d-desc');if(descEl)descEl.textContent=_tr.desc||m.desc||'';
  const specsEl=document.getElementById('d-specs');
  var _sl=_t('specL')||{};var _sv=_t('specV')||{};
  if(specsEl)specsEl.innerHTML=m.specs.map(s=>{var lbl=_sl[s.l]||s.l;var val=s.v;for(var _k in _sv){val=val.split(_k).join(_sv[_k]);}return`<div class="spec-b"><div class="spec-l">${lbl}</div><div class="spec-v">${val}</div></div>`;}).join('');
  const featsEl=document.getElementById('d-feats');
  if(featsEl)featsEl.innerHTML=(_tr.feats||m.feats).map(f=>`<li>${f}</li>`).join('');
  const p=m.pricing||{po:2600,ut:2600,st:2600,ct:2600,pa:2900,so:2900,ne:2900};
  const pEl=document.getElementById('d-pricing');
  var _da=_t('dayAbbr')||{po:'Po',ut:'Út',st:'St',ct:'Čt',pa:'Pá',so:'So',ne:'Ne'};var _pl=_t('pricingL')||{};
  if(pEl)pEl.innerHTML=`<div style="font-size:11px;font-weight:800;text-transform:uppercase;color:var(--g400);letter-spacing:.5px;margin-bottom:10px;">${_pl.pricingTitle||'💰 Ceník dle dne v týdnu'}</div><div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;text-align:center;">${[['po',p.po],['ut',p.ut],['st',p.st],['ct',p.ct],['pa',p.pa],['so',p.so],['ne',p.ne]].map(([k,v])=>{var d=_da[k]||k;var isWe=k==='so'||k==='ne';return`<div style="background:${isWe?'rgba(239,68,68,.08)':'var(--g100)'};border-radius:8px;padding:7px 2px;"><div style="font-size:9px;font-weight:700;color:var(--g400);text-transform:uppercase;">${d}</div><div style="font-size:12px;font-weight:900;color:var(--black);margin-top:3px;">${v?v.toLocaleString('cs-CZ'):'—'}</div><div style="font-size:8px;color:var(--g400);">${_pl.perDay||'Kč/den'}</div></div>`;}).join('')}</div><div style="font-size:10px;color:var(--g400);margin-top:8px;">${_pl.pricingNote||'Ceny bez DPH. Víkend Pá–Ne. 1 den = 24 h.'}</div>`;
  // If coming from search with dates, show date summary instead of calendar
  const dCalWrap=document.getElementById('d-cal-wrap');
  const dDateSummary=document.getElementById('d-date-summary');
  calState.d.motoId=m.id;
  if(sOd && sDo){
    dOd={...sOd};dDo={...sDo};dStep=1;
    if(dDateSummary){
      document.getElementById('d-od-txt').textContent=sOd.d+'. '+(sOd.m+1)+'. '+sOd.y;
      document.getElementById('d-do-txt').textContent=sDo.d+'. '+(sDo.m+1)+'. '+sDo.y;
      dDateSummary.style.display='block';
    }
    if(dCalWrap)dCalWrap.style.display='none';
    // Show total price for search dates
    if(m.pricing){
      var dayMap=[m.pricing.ne,m.pricing.po,m.pricing.ut,m.pricing.st,m.pricing.ct,m.pricing.pa,m.pricing.so];
      var tp=0;var sd=new Date(sOd.y,sOd.m,sOd.d);var ed=new Date(sDo.y,sDo.m,sDo.d);
      var dd=new Date(sd);while(dd<=ed){tp+=dayMap[dd.getDay()]||m.pricing.po||0;dd.setDate(dd.getDate()+1);}
      var prEl=document.getElementById('d-cal-price');var prVal=document.getElementById('d-cal-price-val');
      if(prEl){prEl.style.display='block';}
      if(prVal){prVal.textContent=tp.toLocaleString('cs-CZ')+' Kč';}
    }
  } else if(dOd && dDo){
    // Dates from previous detail calendar selection – show summary
    if(dDateSummary){
      document.getElementById('d-od-txt').textContent=dOd.d+'. '+(dOd.m+1)+'. '+dOd.y;
      document.getElementById('d-do-txt').textContent=dDo.d+'. '+(dDo.m+1)+'. '+dDo.y;
      dDateSummary.style.display='block';
    }
    if(dCalWrap)dCalWrap.style.display='none';
    // Show total price for detail dates
    if(m.pricing){
      var dayMap2=[m.pricing.ne,m.pricing.po,m.pricing.ut,m.pricing.st,m.pricing.ct,m.pricing.pa,m.pricing.so];
      var tp2=0;var sd2=new Date(dOd.y,dOd.m,dOd.d);var ed2=new Date(dDo.y,dDo.m,dDo.d);
      var dd2=new Date(sd2);while(dd2<=ed2){tp2+=dayMap2[dd2.getDay()]||m.pricing.po||0;dd2.setDate(dd2.getDate()+1);}
      var prEl2=document.getElementById('d-cal-price');var prVal2=document.getElementById('d-cal-price-val');
      if(prEl2){prEl2.style.display='block';}
      if(prVal2){prVal2.textContent=tp2.toLocaleString('cs-CZ')+' Kč';}
    }
  } else {
    if(dDateSummary)dDateSummary.style.display='none';
    if(dCalWrap)dCalWrap.style.display='block';
    renderDetailCal();
  }
  const manEl=document.getElementById('d-manual-name');if(manEl)manEl.textContent=m.manual||'Návod k obsluze';
  const manBtn=document.getElementById('d-manual-btn');if(manBtn)manBtn.onclick=()=>downloadManual(m);
  const manViewBtn=document.getElementById('d-manual-view-btn');if(manViewBtn)manViewBtn.onclick=()=>viewManual(m);
  const manSearchBtn=document.getElementById('d-manual-search-btn');if(manSearchBtn)manSearchBtn.onclick=()=>{_manualSearchOrigHtml='';searchManual(m);};
  const pbarEl=document.getElementById('d-pbar');
  if(pbarEl)pbarEl.innerHTML=`<div><div class="pb-l">Cena od</div><div class="pb-p">${m.price}<span style="font-size:12px;font-weight:500;color:var(--g400)">/den</span></div></div><div style="text-align:right"><div class="pb-l">Záloha</div><div style="font-size:14px;font-weight:800;color:var(--green)">Neúčtujeme ✓</div></div>`;
  const imgs2=(m.imgs||[m.img||'']).filter(Boolean);
  const dotsEl=document.getElementById('d-dots');
  if(dotsEl)dotsEl.innerHTML=imgs2.map((_,i)=>`<div class="det-dot ${i===0?'on':''}" onclick="detSlideTo(${i})" style="cursor:pointer;"></div>`).join('');
  detImgIdx=0;
  const cta=document.getElementById('d-cta');
  if(cta){
    var motoDisabled = (m.avail === false);
    // Remove old event listeners by cloning
    var newCta=cta.cloneNode(true);
    cta.parentNode.replaceChild(newCta,cta);
    if(motoDisabled){
      newCta.textContent=_t('res').outOfService||'Motorka mimo provoz';
      newCta.style.background='var(--g400)';
      newCta.disabled=true;
      newCta.style.pointerEvents='none';
    } else {
      var hasDates = (dOd && dDo);
      newCta.textContent= hasDates ? ((_t('res').bookMotoBtn||'Rezervovat motorku')+' \u2192') : (motoFree ? ((_t('res').bookMotoBtn||'Rezervovat motorku')+' \u2192') : ((_t('res').selectDateAndBook||'Vybrat term\u00edn a rezervovat')+' \u2192'));
      newCta.style.background='var(--green)';
      newCta.disabled=false;
      newCta.style.pointerEvents='auto';
      newCta.removeAttribute('disabled');
      // Use addEventListener (more robust than onclick)
      newCta.addEventListener('click',function _ctaHandler(ev){
        ev.stopPropagation();
        try{
          var currentM=dList[dIdx];
          if(!currentM){showT('\u2717',_t('common').error,_t('res').resNotFound||'Motorka nenalezena');return;}
          var localDOd=dOd?{d:dOd.d,y:dOd.y,m:dOd.m}:null;
          var localDDo=dDo?{d:dDo.d,y:dDo.y,m:dDo.m}:null;
          var setupFn=function(){
            bookingMoto=currentM;
            calState.b.motoId=currentM.id;
            var bi=document.getElementById('b-img');if(bi)bi.src=(currentM.imgs&&currentM.imgs.length)?currentM.imgs[0]:(currentM.img||'');
            var bn2=document.getElementById('b-name');if(bn2)bn2.textContent=currentM.name;
            var bbn=document.getElementById('b-branch-info');if(bbn)bbn.textContent='\ud83d\udccd Pobo\u010dka: '+currentM.loc;
            // Update branch info in pickup/return steps (5 & 6)
            var _brAddr=currentM._db&&currentM._db.branch_address?currentM._db.branch_address:'Mezná 9';
            var _brCity=currentM._db&&currentM._db.branch_city?currentM._db.branch_city:'393 01 Mezná';
            var _brFull=_brAddr+', '+_brCity;
            var bkBr=document.getElementById('t-bkBranch');if(bkBr)bkBr.innerHTML='🏪 Pobočka: <strong>'+_brFull+'</strong>';
            var bkPS=document.getElementById('t-bkPickupStoreNote');if(bkPS)bkPS.textContent=_brFull+' – ve vámi zvolenou dobu';
            var bkDN=document.getElementById('t-bkDeliveryNote');if(bkDN)bkDN.textContent='1 000 Kč + 40 Kč/km od provozovny ('+_brFull+')';
            var bkRS=document.getElementById('t-bkReturnStoreNote');if(bkRS)bkRS.textContent=_brFull+' – nejpozději do 24:00 posledního dne';
            if(localDOd && localDDo){
              bOd={d:localDOd.d,y:localDOd.y,m:localDOd.m};bDo={d:localDDo.d,y:localDDo.y,m:localDDo.m};bStep=1;
              bookingFromDetail=true;
              var odEl=document.getElementById('b-od-txt');if(odEl)odEl.textContent=localDOd.d+'. '+(localDOd.m+1)+'. '+localDOd.y;
              var doEl=document.getElementById('b-do-txt');if(doEl)doEl.textContent=localDDo.d+'. '+(localDDo.m+1)+'. '+localDDo.y;
              var bds=document.getElementById('b-date-summary');if(bds)bds.style.display='block';
              var bcw=document.getElementById('b-cal-wrap');if(bcw)bcw.style.display='none';
              updateBookingPrice();
              if(typeof filterTimeChips==='function')filterTimeChips();
            } else {
              bookingFromDetail=false;
              var bds2=document.getElementById('b-date-summary');if(bds2)bds2.style.display='none';
              var bcw2=document.getElementById('b-cal-wrap');if(bcw2){bcw2.style.display='block';buildBCal();}
            }
          };
          if(typeof startBookingWithScan==='function') startBookingWithScan(setupFn);
          else { setupFn(); goTo('s-booking'); }
        }catch(e){console.error('CTA click error:',e);showT('\u2717',_t('common').error,_t('res').failedToBook||'Nepoda\u0159ilo se p\u0159ej\u00edt k rezervaci');}
      });
    }
  }
}

