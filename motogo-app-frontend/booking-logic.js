// ===== BOOKING-LOGIC.JS – Home page filters, moto cards & carousel =====
// Detail page, reservation detail & calendar logic → booking-detail.js

// Booking extras/delivery/discount → js/cart-engine.js
// Variables kept here as they're referenced by booking calendar logic
var extraTotal=0,deliveryFee=0,discountAmt=0,bookingDays=2;
var bookingMoto=null; // currently selected moto for booking

// ===== MOTO CARDS =====
function mCard(m){
  // Check per-motorcycle availability: use selected date range if available, else today
  var free;
  if(typeof sOd!=='undefined'&&sOd&&typeof sDo!=='undefined'&&sDo){
    free=isMotoFreeForRange(m.id,new Date(sOd.y,sOd.m,sOd.d),new Date(sDo.y,sDo.m,sDo.d));
  } else {
    free=isMotoFreeToday(m.id);
  }
  const imgs=m.imgs||[m.img];
  const dots=imgs.map((_,i)=>`<div class="mc-dot ${i===0?'on':''}" onclick="event.stopPropagation();mcSlide('${m.id}',${i})"></div>`).join('');
  const imgTags=imgs.map((src,i)=>`<img src="${src}" class="${i===0?'active':''}" loading="lazy" alt="${m.name}">`).join('');
  var _sr=_t('search')||{};var _pl=_t('pricingL')||{};var _mt=_t('moto')||{};var _mtr=_mt[m.id]||{};
  const catLabels={cestovni:_sr.touring||'Cestovní',sportovni:_sr.sport||'Sportovní',naked:_sr.naked||'Naked',chopper:_sr.chopper||'Chopper',detske:'👶 '+(_sr.kids||'Dětské'),supermoto:_sr.supermoto||'Supermoto'};
  return `<div class="mc" id="mc-${m.id}">
    <div class="mc-carousel" onclick="openDetail('${m.id}')">
      ${imgTags}
      ${imgs.length>1?`<button class="mc-arr mc-arr-l" onclick="event.stopPropagation();mcPrev('${m.id}')">‹</button><button class="mc-arr mc-arr-r" onclick="event.stopPropagation();mcNext('${m.id}')">›</button>`:''}
      <div class="mc-ntag">${m.name}</div>
      <div class="atag ${free?'avl':'bsy'}">${free?(_pl.todayFree||'✓ Dnes volná'):(_pl.todayBusy||'✗ Dnes obsazená')}</div>
      <div class="mc-dots">${dots}</div>
    </div>
    <div class="mc-body" onclick="openDetail('${m.id}')">
      <div class="mc-badges">
        <span class="mc-badge mc-badge-rp">${_pl.rpLabel||'ŘP'} ${m.rp}</span>
        <span class="mc-badge mc-badge-cat">${catLabels[m.cat]||m.cat}</span>
        <span class="mc-badge mc-badge-vykon">${m.vykon} kW</span>
        <span class="mc-badge" style="background:#f3e8ff;color:#7e22ce;">📍 ${m._db&&m._db.branch_name?m._db.branch_name:'Mezná'}</span>
      </div>
      ${m.cat==='detske'?'<div style=\"background:#fef3c7;border:1px solid #fde68a;border-radius:8px;padding:7px 10px;font-size:11px;font-weight:600;color:#92400e;margin-bottom:8px;\">'+(_pl.kidsWarn||'⚠️ Pouze pro děti · uzavřený prostor · dohled zákonného zástupce · není povolen provoz na veřejných komunikacích')+'</div>':''}
      <ul class="mc-feats">${(_mtr.feats||m.feats).slice(0,2).map(f=>`<li>${f}</li>`).join('')}</ul>
      <div class="mc-row">
        <div><div class="mc-price-big">${_pl.fromLabel||'od'} ${m.price}</div><div class="mc-price-label">${_pl.perDayNote||'za den / cena bez DPH není plátcem'}</div></div>
        <button class="btn-det" onclick="event.stopPropagation();openDetail('${m.id}')">${_pl.detailBtn||'Detail →'}</button>
      </div>
    </div></div>`;
}

// Carousel state
const mcState={};
function mcSlide(id,idx){
  const card=document.getElementById('mc-'+id);if(!card)return;
  const imgs=card.querySelectorAll('.mc-carousel img');
  const dots=card.querySelectorAll('.mc-dot');
  const n=imgs.length;
  mcState[id]=((idx%n)+n)%n;
  imgs.forEach((img,i)=>img.classList.toggle('active',i===mcState[id]));
  dots.forEach((d,i)=>d.classList.toggle('on',i===mcState[id]));
}
function mcNext(id){mcSlide(id,(mcState[id]||0)+1);}
function mcPrev(id){mcSlide(id,(mcState[id]||0)-1);}

// Home filter state
const HF={cat:'all',rp:'all',vykon:120,avail:false,sort:'default'};
function setHF(key,val,el){
  HF[key]=val;
  // deactivate siblings
  const prefix=key==='cat'?'hfc':'hfr';
  document.querySelectorAll('[id^="'+prefix+'-"]').forEach(c=>c.classList.remove('on'));
  if(el)el.classList.add('on');
  applyHomeFilters();
}
function setHFVykon(v){
  HF.vykon=parseInt(v);
  const lbl=document.getElementById('hf-vykon-lbl');
  if(lbl)lbl.textContent=v>=120?'vše':v+' kW';
  applyHomeFilters();
}
function resetHomeFilters(){
  HF.cat='all';HF.rp='all';HF.vykon=120;HF.avail=false;HF.sort='default';
  document.querySelectorAll('[id^="hfc-"],[id^="hfr-"]').forEach(c=>c.classList.remove('on'));
  const allC=document.getElementById('hfc-all');if(allC)allC.classList.add('on');
  const allR=document.getElementById('hfr-all');if(allR)allR.classList.add('on');
  const sl=document.getElementById('hf-vykon');if(sl)sl.value=120;
  const lbl=document.getElementById('hf-vykon-lbl');if(lbl)lbl.textContent='vše';
  const av=document.getElementById('hf-avail');if(av)av.checked=false;
  const so=document.getElementById('hf-sort');if(so)so.value='default';
  applyHomeFilters();
}
function applyHomeFilters(){
  const av=document.getElementById('hf-avail');
  if(av)HF.avail=av.checked;
  const so=document.getElementById('hf-sort');
  if(so)HF.sort=so.value;
  let list=[...MOTOS];
  if(HF.cat!=='all')list=list.filter(m=>m.cat===HF.cat);
  if(HF.rp==='A2')list=list.filter(m=>m.rp==='A2'||m.rp==='A1'||m.rp==='N');
  else if(HF.rp==='A')list=list.filter(m=>m.rp==='A');
  else if(HF.rp==='A1')list=list.filter(m=>m.rp==='A1'||m.rp==='N');
  else if(HF.rp==='N')list=list.filter(m=>m.rp==='N');
  if(HF.vykon<120)list=list.filter(m=>m.vykon<=HF.vykon);
  if(HF.avail)list=list.filter(function(m){return isMotoFreeToday(m.id);});
  const brHome=document.getElementById('f-branch-home')?.value||'';
  if(brHome)list=list.filter(m=>m.branch===brHome);
  if(HF.sort==='price-asc')list.sort((a,b)=>{const pa=a.price.replace(/[^0-9]/g,''),pb=b.price.replace(/[^0-9]/g,'');return parseInt(pa)-parseInt(pb);});
  if(HF.sort==='price-desc')list.sort((a,b)=>{const pa=a.price.replace(/[^0-9]/g,''),pb=b.price.replace(/[^0-9]/g,'');return parseInt(pb)-parseInt(pa);});
  if(HF.sort==='vykon-desc')list.sort((a,b)=>b.vykon-a.vykon);
  if(HF.sort==='name-asc')list.sort((a,b)=>a.name.localeCompare(b.name));
  const homeEl=document.getElementById('home-motos');
  if(homeEl)homeEl.innerHTML=list.length?list.map(m=>mCard(m)).join(''):'<div style="padding:30px 20px;text-align:center;color:var(--g400);font-size:13px;font-weight:600;">'+_t('res').noFilter+'</div>';
  const cnt=document.getElementById('hf-count-txt');
  if(cnt)cnt.textContent='Zobrazeno: '+list.length+' motorek';
}
function renderHome(cat){HF.cat=cat||'all';applyHomeFilters();}
function setCat(el,cat){
  document.querySelectorAll('.cat-scroll .chip').forEach(c=>c.classList.remove('active'));
  if(el)el.classList.add('active');
  renderHome(cat);
}

// Detail page, reservation detail & calendar → booking-detail.js
