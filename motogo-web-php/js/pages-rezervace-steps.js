// ===== MotoGo24 Web — Rezervace: krok 1 submit + krok 2 (doklady+faktura) + QR =====
var MG = window.MG || {};
window.MG = MG;

// ===== MOBILE DETECTION =====
MG._isMobile = function(){ return /Mobi|Android|iPhone|iPad/i.test(navigator.userAgent); };

// ===== QR CODE IMAGE URL (via goqr.me API) =====
MG._qrCodeUrl = function(data){
  return 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data='+encodeURIComponent(data);
};

// ===== VALIDATION HELPERS =====
MG._isNameValid = function(v){
  if(!v||v.trim().length<2) return false;
  if(!/^[\p{Letter}\s'\-]+$/u.test(v.trim())) return false;
  if(/(.)\1{2,}/i.test(v.trim())) return false;
  return true;
};
MG._isPhoneValid = function(v){
  if(!v) return false;
  var digits=v.replace(/[\s\-()]/g,'');
  return /^\+\d{8,14}$/.test(digits);
};
MG._isLicenseExpiryValid = function(dateStr){
  if(!dateStr) return false;
  var d=new Date(dateStr);
  var min=new Date();min.setHours(0,0,0,0);min.setDate(min.getDate()+14);
  return d>=min;
};

// ===== STEP 1 SUBMIT: validate form → save customer → show step 2 =====
MG._submitReservation = async function(){
  var btn=document.querySelector('#rez-form .btn.btngreen');
  var name=document.getElementById('rez-name'),email=document.getElementById('rez-email'),
    phone=document.getElementById('rez-phone'),street=document.getElementById('rez-street'),
    city=document.getElementById('rez-city'),zip=document.getElementById('rez-zip'),
    country=document.getElementById('rez-country'),agree=document.getElementById('rez-agree-vop');

  var T = (MG.t || function(k){ return k; });
  // Enhanced validation
  if(!name||!MG._isNameValid(name.value)){
    alert(T('rez.alert.name'));return;}
  if(!street||!street.value||street.value.trim().length<3){
    alert(T('rez.alert.street'));return;}
  if(!city||!city.value||city.value.trim().length<2){
    alert(T('rez.alert.city'));return;}
  if(!zip||!zip.value){
    alert(T('rez.alert.zip'));return;}
  if(!email||!email.value||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.value.trim())){
    alert(T('rez.alert.email'));return;}
  if(!phone||!MG._isPhoneValid(phone.value)){
    alert(T('rez.alert.phone'));return;}
  if(!agree||!agree.checked){alert(T('rez.alert.terms'));return;}
  var r=MG._rez;
  if(!r.startDate||!r.endDate){alert(T('rez.alert.dates'));return;}
  var mId=r.motoId||r.selectedMotoId;
  if(!mId){alert(T('rez.alert.moto'));return;}
  var ptEl=document.getElementById('rez-pickup-time');
  if(!ptEl||!ptEl.value){alert(T('rez.alert.pickupTime'));return;}
  if(!MG._rezValidatePickupTime()){
    var isDel=document.getElementById('rez-delivery')&&document.getElementById('rez-delivery').checked;
    alert(isDel?T('rez.alert.minTimeDelivery'):T('rez.alert.minTime'));return;}
  var extras=[];
  if(document.getElementById('rez-eq-passenger')&&document.getElementById('rez-eq-passenger').checked) extras.push({name:T('rez.gear.item.passengerExtras'),unit_price:MG._accessoryPrice('passenger_gear')});
  if(document.getElementById('rez-eq-boots-rider')&&document.getElementById('rez-eq-boots-rider').checked) extras.push({name:T('rez.gear.item.bootsRider'),unit_price:MG._accessoryPrice('boots_rider')});
  if(document.getElementById('rez-eq-boots-passenger')&&document.getElementById('rez-eq-boots-passenger').checked) extras.push({name:T('rez.gear.item.bootsPassenger'),unit_price:MG._accessoryPrice('boots_passenger')});
  var deliveryAddr=null,returnAddr=null;
  if(document.getElementById('rez-delivery')&&document.getElementById('rez-delivery').checked)
    deliveryAddr=(document.getElementById('rez-delivery-address')||{}).value||null;
  var retO=document.getElementById('rez-return-other'),retS=document.getElementById('rez-return-same-as-delivery');
  if(retO&&retO.checked) returnAddr=(document.getElementById('rez-return-address')||{}).value||null;
  else if(retS&&retS.checked&&deliveryAddr) returnAddr=deliveryAddr;
  // Když motorku nevracíme do půjčovny, čas vrácení je povinný
  if(returnAddr){
    var rtElValidate=document.getElementById('rez-return-time');
    if(!rtElValidate||!rtElValidate.value){
      alert(T('rez.alert.returnTime'));return;}
  }
  // Fee = 1000 Kč + 40 Kč/km (km = vzdalenost od pobocky Mezna 9, spoctena pres Mapy.cz)
  if(deliveryAddr){
    var dKm = MG._rez.deliveryDistanceKm;
    var dFee = MG._calcDeliveryFee(dKm);
    var dLbl = (typeof dKm==='number') ? ' ('+MG.formatPrice(1000)+' + '+MG.formatPrice(40)+' × '+dKm.toFixed(1).replace('.',',')+' km)' : '';
    extras.push({name:T('rez.gear.item.delivery')+dLbl,unit_price:dFee});
  }
  if(returnAddr){
    var rKm = (retS&&retS.checked) ? MG._rez.deliveryDistanceKm : MG._rez.returnDistanceKm;
    var rFee = MG._calcDeliveryFee(rKm);
    var rLbl = (typeof rKm==='number') ? ' ('+MG.formatPrice(1000)+' + '+MG.formatPrice(40)+' × '+rKm.toFixed(1).replace('.',',')+' km)' : '';
    extras.push({name:T('rez.gear.item.return')+rLbl,unit_price:rFee});
  }

  // Collect sizes from new chip UI
  var rs = (MG._rez.sizes && MG._rez.sizes.rider) || {};
  var ps = (MG._rez.sizes && MG._rez.sizes.passenger) || {};
  // If "own gear" toggled — clear rider sizes (force rental skipped)
  var ownGearEl = document.getElementById('rez-own-gear');
  if(ownGearEl && ownGearEl.checked){ rs = {}; }

  MG._rez.formData={motoId:mId,name:name.value,email:email.value,phone:phone.value,
    street:street.value,city:city.value,zip:zip.value,country:(country&&country.value)||T('rez.contact.countryDefault'),
    note:'',pickupTime:ptEl.value,
    deliveryAddr:deliveryAddr,returnAddr:returnAddr,extras:extras,
    appliedCodes:(MG._rez.appliedCodes&&MG._rez.appliedCodes.length)?MG._rez.appliedCodes:[],
    discountAmt:MG._rez.discountAmt||0,
    riderSizes: rs, passengerSizes: ps};

  // Save customer to DB immediately (even if they don't finish payment)
  try {
    // Prepare discount params
    var codes = MG._rez.formData.appliedCodes || [];
    var discAmt = MG._rez.formData.discountAmt || 0;
    var promoCode = null, voucherId = null;
    for(var ci=0;ci<codes.length;ci++){
      if(codes[ci].type==='promo') promoCode = codes[ci].code;
      if(codes[ci].type==='voucher') voucherId = codes[ci].id;
    }
    var rpcParams = {
      p_moto_id: mId, p_start_date: r.startDate, p_end_date: r.endDate,
      p_name: name.value, p_email: email.value, p_phone: phone.value,
      p_street: street.value||'', p_city: city.value||'', p_zip: zip.value||'',
      p_country: (country&&country.value)||'CZ',
      p_note: '',
      p_pickup_time: ptEl.value ? ptEl.value+':00' : null,
      p_delivery_address: deliveryAddr, p_return_address: returnAddr,
      p_extras: extras,
      p_discount_amount: discAmt||0,
      p_discount_code: codes.length?codes.map(function(c){return c.code;}).join(', '):null,
      p_promo_code: promoCode,
      p_voucher_id: voucherId,
      p_license_group: (document.getElementById('rez-license-group')||{}).value||null,
      // Driver gear sizes (RPC supports since 2026-04-11)
      p_helmet_size: rs.helmet||null,
      p_jacket_size: rs.jacket||null,
      p_pants_size:  rs.pants||null,
      p_boots_size:  rs.boots||null,
      p_gloves_size: rs.gloves||null,
      // Pokud uživatel kliknul "Zpět" v kroku 2 a vrací se s úpravami,
      // RPC namísto vytvoření nového pending bookingu UPDATE-uje původní
      p_existing_booking_id: MG._rez.bookingId || null
    };
    // Passenger gear sizes — pošli jen pokud je RPC rozšířený (po aplikaci SQL migrace)
    var hasPassengerSizes = !!(ps.helmet||ps.jacket||ps.gloves||ps.boots);
    if(hasPassengerSizes){
      rpcParams.p_passenger_helmet_size = ps.helmet||null;
      rpcParams.p_passenger_jacket_size = ps.jacket||null;
      rpcParams.p_passenger_gloves_size = ps.gloves||null;
      rpcParams.p_passenger_boots_size  = ps.boots||null;
    }
    // Cas vraceni — uloz jen pokud se vraci mimo provozovnu
    // (return-other = vlastni adresa vraceni, nebo delivery + same-as-delivery = vraci na adrese pristaveni)
    var isReturnOffsite = (retO && retO.checked) ||
      (document.getElementById('rez-delivery') && document.getElementById('rez-delivery').checked &&
       retS && retS.checked);
    if(isReturnOffsite){
      var rtEl = document.getElementById('rez-return-time');
      if(rtEl && rtEl.value) rpcParams.p_return_time = rtEl.value;
    }
    console.log('[REZ] create_web_booking params:', rpcParams);
    var regRes = await window.sb.rpc('create_web_booking', rpcParams);
    if(regRes.error){
      console.error('[REZ] create_web_booking error:', regRes.error);
      var emsg = regRes.error.message || '';
      if(emsg.indexOf('Booking overlap') !== -1) alert(T('rez.alert.bookingOverlap'));
      else if(emsg.indexOf('overlapping booking') !== -1) alert(T('rez.alert.bookingOverlapOwn'));
      else alert(T('rez.alert.error', {msg: emsg}));
      if(btn){btn.disabled=false;btn.textContent=T('rez.cta.continuePay');}
      return;
    }
    var regData = regRes.data;
    if(regData && regData.error){
      alert(regData.error);
      if(btn){btn.disabled=false;btn.textContent=T('rez.cta.continuePay');}
      return;
    }
    if(regData){
      MG._rez.bookingId = regData.booking_id;
      MG._rez.userId = regData.user_id;
      MG._rez.bookingAmount = regData.amount;
      // i18n: ulož jazyk zákazníka do bookings.language (pro maily/SMS/push)
      try {
        await window.sb.rpc('set_booking_language', {
          p_booking_id: regData.booking_id,
          p_language: (document.documentElement.lang || 'cs').slice(0, 2)
        });
      } catch (e) { console.warn('[REZ] set_booking_language failed:', e); }
      // Uložit stav formuláře do sessionStorage (přežije navigaci zpět)
      try { sessionStorage.setItem('mg_rez_form', JSON.stringify({
        formData: MG._rez.formData, bookingId: MG._rez.bookingId,
        userId: MG._rez.userId, bookingAmount: MG._rez.bookingAmount,
        startDate: MG._rez.startDate, endDate: MG._rez.endDate,
        motoId: MG._rez.motoId, appliedCodes: MG._rez.appliedCodes,
        discountAmt: MG._rez.discountAmt,
        sizes: MG._rez.sizes,
        _docNumber: MG._rez._docNumber, _licenseNumber: MG._rez._licenseNumber,
        _docsValidated: MG._rez._docsValidated,
        _passwordSet: MG._rez._passwordSet||false
      })); } catch(e2){}
    }
  } catch(e){ alert(T('rez.alert.saveError', {msg: e.message})); return; }

  // Abandoned-mail planning is now server-side: pg_cron `send_abandoned_booking_emails`
  // posílá mail 20 min po vytvoření pending bookingu (krok 1→2) nebo 10 min po
  // vytvoření Stripe session (kliknutí "Pokračovat k platbě"). Frontend nepotřebuje timer.

  MG._rezShowStep2();
};

// ===== MOTO GALLERY (compact hero with prev/next + dots) =====
MG._rezGalleryImages = function(moto){
  if(!moto) return [];
  var arr = [];
  if(moto.image_url) arr.push(moto.image_url);
  if(moto.images && moto.images.length){
    moto.images.forEach(function(p){ if(p && arr.indexOf(p)===-1) arr.push(p); });
  }
  return arr.map(function(p){ return MG.imgUrl(p); }).filter(Boolean);
};

MG._rezGalleryHtml = function(moto){
  var imgs = MG._rezGalleryImages(moto);
  var name = moto ? (moto.model||'') : '';
  if(!imgs.length){
    return '<div class="rez-moto-hero rez-moto-hero-empty">'+
      '<div class="rez-moto-hero-placeholder">&#127949;</div>'+
      '<div class="rez-moto-hero-caption"><div class="rez-moto-hero-name">'+name+'</div></div>'+
    '</div>';
  }
  var slides = imgs.map(function(src,i){
    return '<img class="rez-moto-hero-img'+(i===0?' active':'')+'" data-idx="'+i+'" src="'+src+'" alt="'+name+'" loading="lazy">';
  }).join('');
  var dots = imgs.length>1 ? imgs.map(function(_,i){
    return '<button type="button" class="rez-moto-hero-dot'+(i===0?' active':'')+'" data-idx="'+i+'" aria-label="Foto '+(i+1)+'"></button>';
  }).join('') : '';
  var nav = imgs.length>1 ? (
    '<button type="button" class="rez-moto-hero-nav rez-moto-hero-prev" aria-label="Předchozí">&#10094;</button>'+
    '<button type="button" class="rez-moto-hero-nav rez-moto-hero-next" aria-label="Další">&#10095;</button>'
  ) : '';
  return '<div class="rez-moto-hero" data-count="'+imgs.length+'">'+
    '<div class="rez-moto-hero-stage">'+slides+'</div>'+
    nav+
    '<div class="rez-moto-hero-caption"><div class="rez-moto-hero-name">'+name+'</div>'+
      (dots?'<div class="rez-moto-hero-dots">'+dots+'</div>':'')+
    '</div>'+
  '</div>';
};

MG._rezInitGallery = function(){
  var hero = document.querySelector('.rez-moto-hero'); if(!hero) return;
  var imgs = hero.querySelectorAll('.rez-moto-hero-img');
  var dots = hero.querySelectorAll('.rez-moto-hero-dot');
  var n = imgs.length; if(n<=1) return;
  var idx = 0;
  function show(i){
    idx = (i+n)%n;
    imgs.forEach(function(im,k){ im.classList.toggle('active', k===idx); });
    dots.forEach(function(dt,k){ dt.classList.toggle('active', k===idx); });
  }
  hero.querySelector('.rez-moto-hero-prev').addEventListener('click', function(){ show(idx-1); });
  hero.querySelector('.rez-moto-hero-next').addEventListener('click', function(){ show(idx+1); });
  dots.forEach(function(dt){ dt.addEventListener('click', function(){ show(parseInt(dt.dataset.idx,10)||0); }); });
  // Touch swipe
  var sx = null;
  hero.addEventListener('touchstart', function(e){ sx = e.touches[0].clientX; }, {passive:true});
  hero.addEventListener('touchend', function(e){
    if(sx==null) return;
    var dx = (e.changedTouches[0].clientX - sx);
    if(Math.abs(dx)>40) show(idx + (dx<0?1:-1));
    sx = null;
  });
};

// ===== UPSELL: e-shop produkty v kroku 2 =====
MG._rezProductsCache = null;
MG._rezLoadProducts = async function(){
  if(MG._rezProductsCache) return MG._rezProductsCache;
  try {
    var prods = await MG.fetchProducts();
    // Limit na max 8 nejviditelnějších produktů; obsahuje sizes/stock
    MG._rezProductsCache = (prods||[]).slice(0, 8);
  } catch(e){ MG._rezProductsCache = []; }
  return MG._rezProductsCache;
};

MG._rezShopItems = MG._rezShopItems || []; // [{product_id, name, unit_price, qty, size, image, stock}]

MG._rezCartKey = function(productId, size){ return productId + '|' + (size||''); };

MG._rezShopTotal = function(){
  var t = 0;
  (MG._rezShopItems||[]).forEach(function(it){ t += (it.unit_price||0) * (it.qty||1); });
  return t;
};

MG._rezProductsHtml = function(){
  var prods = MG._rezProductsCache || [];
  if(!prods.length){
    return '<p class="rez-section-sub" style="margin:0">Aktuálně nejsou k dispozici žádné doplňky.</p>';
  }
  var cards = prods.map(function(p){
    var img = MG.imgUrl((p.images && p.images[0]) || p.image_url || '');
    var price = MG.formatPrice(p.price||0);
    var sizes = Array.isArray(p.sizes) ? p.sizes : [];
    // Souhrn co už má v košíku z tohoto produktu (přes všechny velikosti)
    var inCartQty = (MG._rezShopItems||[]).filter(function(it){ return it.product_id===p.id; })
      .reduce(function(a,it){ return a+(it.qty||1); }, 0);
    var stock = (typeof p.stock_quantity==='number' && p.stock_quantity>=0) ? p.stock_quantity : 99;
    var sizeChips = sizes.length ?
      ('<div class="rez-prod-sizes">'+sizes.map(function(s){
        return '<button type="button" class="rez-prod-size" data-size="'+s+'">'+s+'</button>';
      }).join('')+'</div>') : '';
    var qtyStep =
      '<div class="rez-prod-qty">'+
        '<span class="rez-prod-qty-label">Počet</span>'+
        '<div class="rez-prod-qty-step">'+
          '<button type="button" class="rez-prod-qty-btn rez-prod-qty-minus" aria-label="Méně">&minus;</button>'+
          '<span class="rez-prod-qty-val">1</span>'+
          '<button type="button" class="rez-prod-qty-btn rez-prod-qty-plus" aria-label="Více">+</button>'+
        '</div>'+
      '</div>';
    var inCartBadge = inCartQty>0 ? ('<div class="rez-prod-incart">&#10003; v košíku: '+inCartQty+' ks</div>') : '';
    return '<div class="rez-prod-card" data-id="'+p.id+'" data-price="'+(p.price||0)+'" data-name="'+(p.name||'').replace(/"/g,'&quot;')+'" data-image="'+img+'" data-has-sizes="'+(sizes.length?'1':'0')+'" data-stock="'+stock+'">'+
      '<div class="rez-prod-thumb">'+(img?('<img src="'+img+'" alt="'+(p.name||'')+'" loading="lazy">'):'<span class="rez-prod-thumb-ph">&#128717;</span>')+'</div>'+
      '<div class="rez-prod-body">'+
        '<div class="rez-prod-name">'+(p.name||'')+'</div>'+
        '<div class="rez-prod-price">'+price+'</div>'+
        sizeChips+
        qtyStep+
        inCartBadge+
        '<button type="button" class="rez-prod-add">+ Přidat</button>'+
      '</div>'+
    '</div>';
  }).join('');
  return '<div class="rez-prod-grid">'+cards+'</div>';
};

MG._rezResetProductCard = function(card){
  card.querySelectorAll('.rez-prod-size').forEach(function(x){ x.classList.remove('active'); });
  var qv = card.querySelector('.rez-prod-qty-val'); if(qv) qv.textContent = '1';
  // Update disabled stav − tlačítka
  var minus = card.querySelector('.rez-prod-qty-minus'); if(minus) minus.disabled = true;
};

MG._rezInitProducts = function(){
  var grid = document.querySelector('.rez-prod-grid'); if(!grid) return;
  grid.querySelectorAll('.rez-prod-card').forEach(function(card){
    var sizeBtns = card.querySelectorAll('.rez-prod-size');
    var addBtn = card.querySelector('.rez-prod-add');
    var minus = card.querySelector('.rez-prod-qty-minus');
    var plus = card.querySelector('.rez-prod-qty-plus');
    var qv = card.querySelector('.rez-prod-qty-val');
    var stock = parseInt(card.dataset.stock,10) || 99;

    // Initial disabled state of − button
    if(minus) minus.disabled = true;

    sizeBtns.forEach(function(b){
      b.addEventListener('click', function(){
        sizeBtns.forEach(function(x){ x.classList.remove('active'); });
        b.classList.add('active');
      });
    });

    if(minus){
      minus.addEventListener('click', function(){
        var n = parseInt(qv.textContent,10) || 1;
        if(n>1){ n--; qv.textContent = String(n); }
        minus.disabled = (n<=1);
        plus.disabled = false;
      });
    }
    if(plus){
      plus.addEventListener('click', function(){
        var n = parseInt(qv.textContent,10) || 1;
        if(n<stock){ n++; qv.textContent = String(n); }
        plus.disabled = (n>=stock);
        minus.disabled = (n<=1);
      });
    }

    if(addBtn){
      addBtn.addEventListener('click', function(){
        var pid = card.dataset.id;
        var hasSizes = card.dataset.hasSizes==='1';
        var qty = Math.max(1, parseInt(qv.textContent,10) || 1);
        var size = null;
        if(hasSizes){
          var sel = card.querySelector('.rez-prod-size.active');
          if(!sel){ alert(MG.t('rez.alert.selectSize')); return; }
          size = sel.dataset.size;
        }
        // Sloučit s existujícím řádkem (stejný product_id + size) — kupujeme víc kusů
        var key = MG._rezCartKey(pid, size);
        var existing = MG._rezShopItems.find(function(it){ return MG._rezCartKey(it.product_id, it.size)===key; });
        if(existing){
          existing.qty = Math.min(stock, (existing.qty||1) + qty);
        } else {
          MG._rezShopItems.push({
            product_id: pid,
            name: card.dataset.name,
            unit_price: parseFloat(card.dataset.price)||0,
            qty: qty, size: size,
            image: card.dataset.image,
            stock: stock
          });
        }
        // Vizuální feedback + reset karty pro přidání další velikosti / kusu
        addBtn.classList.add('flash');
        setTimeout(function(){ addBtn.classList.remove('flash'); }, 600);
        MG._rezResetProductCard(card);
        MG._rezRefreshShopUi(true); // skip rebuild produkty (uživatel právě klikl, ať mu karty neskáčou)
      });
    }
  });
};

MG._rezRefreshShopUi = function(skipProductsRebuild){
  // Rebuild product cards (incart badge update) + invoice rows
  if(!skipProductsRebuild){
    var sec = document.getElementById('rez-shop-products');
    if(sec){ sec.innerHTML = MG._rezProductsHtml(); MG._rezInitProducts(); }
  } else {
    // Jen aktualizovat „v košíku: X ks" badge u produktů, beze rebuildu
    var grid = document.querySelector('.rez-prod-grid');
    if(grid){
      grid.querySelectorAll('.rez-prod-card').forEach(function(card){
        var pid = card.dataset.id;
        var inCartQty = (MG._rezShopItems||[]).filter(function(it){ return it.product_id===pid; })
          .reduce(function(a,it){ return a+(it.qty||1); }, 0);
        var body = card.querySelector('.rez-prod-body');
        var badge = card.querySelector('.rez-prod-incart');
        if(inCartQty>0){
          if(!badge){
            badge = document.createElement('div');
            badge.className = 'rez-prod-incart';
            // Vlož před tlačítko Přidat
            var addBtn2 = card.querySelector('.rez-prod-add');
            body.insertBefore(badge, addBtn2);
          }
          badge.innerHTML = '&#10003; v košíku: '+inCartQty+' ks';
        } else if(badge){ badge.remove(); }
      });
    }
  }
  MG._rezRefreshInvoice();
};

// ===== Akce v invoice řádcích doprodeje =====
MG._rezShopItemAdjust = function(key, delta){
  var idx = MG._rezShopItems.findIndex(function(it){ return MG._rezCartKey(it.product_id, it.size)===key; });
  if(idx<0) return;
  var it = MG._rezShopItems[idx];
  var stock = it.stock || 99;
  var n = (it.qty||1) + delta;
  if(n<=0){ MG._rezShopItems.splice(idx,1); }
  else { it.qty = Math.min(stock, Math.max(1, n)); }
  MG._rezRefreshShopUi();
};
MG._rezShopItemRemove = function(key){
  MG._rezShopItems = MG._rezShopItems.filter(function(it){ return MG._rezCartKey(it.product_id, it.size)!==key; });
  MG._rezRefreshShopUi();
};

MG._rezRefreshInvoice = function(){
  var box = document.getElementById('rez-invoice-box');
  if(!box) return;
  var d=MG._rez.formData,r=MG._rez;
  var moto=r.motos.find(function(m){return m.id===d.motoId;});
  var motoName=moto?moto.model:'—';
  var base=0,extT=0,disc=0,bookingTotal=0,rows='';
  if(MG._rez._isResume){
    bookingTotal=MG._rez.bookingAmount||0;
    rows='<tr><td><span class="rez-inv-ico">&#127949;</span>Rezervace: '+motoName+'</td>'+
      '<td>'+MG.formatPrice(bookingTotal)+'</td></tr>';
  } else {
    var bd=(moto&&r.startDate&&r.endDate)?MG.calcPriceBreakdown(moto,r.startDate,r.endDate):{total:0,days:[],uniform:true};
    base=bd.total;
    d.extras.forEach(function(e){extT+=e.unit_price;});
    disc=d.discountAmt||0;
    bookingTotal=Math.max(0,base+extT-disc);
    if(bd.uniform || bd.days.length<=1){
      rows='<tr><td><span class="rez-inv-ico">&#127949;</span>Pronájem: '+motoName+
        (bd.days.length>1?' <span class="rez-inv-sub">('+bd.days.length+' dní × '+MG.formatPrice(bd.days[0].price)+')</span>':'')+'</td>'+
        '<td>'+MG.formatPrice(base)+'</td></tr>';
    } else {
      rows='<tr><td><span class="rez-inv-ico">&#127949;</span>Pronájem: '+motoName+'</td>'+
        '<td>'+MG.formatPrice(base)+'</td></tr>';
      bd.days.forEach(function(day){
        rows+='<tr class="rez-invoice-row-day"><td><span class="rez-inv-ico">&middot;</span><span class="rez-inv-day-lbl">'+day.dowLabel+' '+MG.formatDate(day.iso)+'</span></td>'+
          '<td>'+MG.formatPrice(day.price)+'</td></tr>';
      });
    }
    d.extras.forEach(function(e){rows+='<tr><td><span class="rez-inv-ico">&#10010;</span>'+e.name+'</td>'+
      '<td>'+MG.formatPrice(e.unit_price)+'</td></tr>';});
    if(disc>0){var cl=(d.appliedCodes||[]).map(function(c){return c.code;}).join('+');
      rows+='<tr class="rez-invoice-row-discount"><td><span class="rez-inv-ico">&#127873;</span>Sleva ('+cl+')</td>'+
      '<td>−'+MG.formatPrice(disc)+'</td></tr>';}
  }
  // Shop items s ovládáním (− 1 + × )
  var shop = MG._rezShopItems||[];
  shop.forEach(function(it){
    var sLbl = it.size ? ' ('+it.size+')' : '';
    var key = MG._rezCartKey(it.product_id, it.size);
    var stock = it.stock || 99;
    var qty = it.qty||1;
    var minusDis = qty<=1 ? '' : '';
    var plusDis = qty>=stock ? ' disabled' : '';
    rows += '<tr class="rez-invoice-row-shop"><td>'+
      '<div class="rez-inv-shop-cell">'+
        '<span class="rez-inv-ico">&#128717;</span>'+
        '<span class="rez-inv-shop-name">'+it.name+sLbl+'</span>'+
        '<span class="rez-inv-qty">'+
          '<button type="button" class="rez-inv-qty-btn" onclick="MG._rezShopItemAdjust(\''+key+'\',-1)" aria-label="Méně">&minus;</button>'+
          '<span class="rez-inv-qty-val">'+qty+'</span>'+
          '<button type="button" class="rez-inv-qty-btn" onclick="MG._rezShopItemAdjust(\''+key+'\',1)" aria-label="Více"'+plusDis+'>+</button>'+
        '</span>'+
        '<button type="button" class="rez-inv-remove" onclick="MG._rezShopItemRemove(\''+key+'\')" aria-label="Odstranit">&times;</button>'+
      '</div>'+
      '</td>'+
      '<td>'+MG.formatPrice((it.unit_price||0)*qty)+'</td></tr>';
  });
  var shopTotal = MG._rezShopTotal();
  var grandTotal = bookingTotal + shopTotal;

  box.innerHTML =
    '<table class="rez-invoice-table">'+
      '<tr><th>Položka</th><th>Cena</th></tr>'+rows+
    '</table>'+
    '<div class="rez-invoice-total"><strong>Celkem k úhradě</strong><strong>'+MG.formatPrice(grandTotal)+'</strong></div>';

  // Update sticky pay amount
  var amtEl = document.querySelector('.rez-step2-amount');
  if(amtEl) amtEl.textContent = MG.formatPrice(grandTotal);
  MG._rez._grandTotal = grandTotal;
};

// ===== STEP 2: Doklady + QR kód + Náhled faktury =====
MG._rezShowStep2 = function(){
  var form=document.getElementById('rez-form');if(!form)return;
  // Hide calendar, banner, moto select — only show on step 1
  ['rez-intro','rez-step-moto','rez-step-cal','rez-calendar','rez-date-banner','rez-avail-select','rez-moto-select'].forEach(function(id){
    var el=document.getElementById(id);if(el)el.style.display='none';
  });
  var d=MG._rez.formData,r=MG._rez;
  var moto=r.motos.find(function(m){return m.id===d.motoId;});
  // Pokud v resume flow moto nemá fotky, doplň ji asynchronně
  if(moto && !moto.image_url && !(moto.images && moto.images.length)){
    try {
      window.sb.from('motorcycles').select('id, model, image_url, images').eq('id', moto.id).maybeSingle().then(function(rs){
        if(rs && rs.data){
          moto.image_url = rs.data.image_url; moto.images = rs.data.images;
          var heroSec = document.getElementById('rez-moto-hero-wrap');
          if(heroSec){ heroSec.innerHTML = MG._rezGalleryHtml(moto); MG._rezInitGallery(); }
        }
      });
    } catch(e){}
  }
  var motoName=moto?moto.model:'—';
  // Initial booking total for sticky pay button (přepočte se po přidání produktů)
  var bookingTotal=0;
  if(MG._rez._isResume){
    bookingTotal=MG._rez.bookingAmount||0;
  } else {
    var _b=(moto&&r.startDate&&r.endDate)?MG.calcPrice(moto,r.startDate,r.endDate):0;
    var _e=0; d.extras.forEach(function(e){_e+=e.unit_price;});
    bookingTotal=Math.max(0,_b+_e-(d.discountAmt||0));
  }
  var total = bookingTotal + MG._rezShopTotal();

  var isMob=MG._isMobile();
  // QR cílí na stejnou doménu, ze které zákazník přišel (.cz/.com/.de/...).
  // window.location.origin obsahuje protokol+host+port → např. "https://motogo24.cz".
  var resumeLink=MG._rez.bookingId?(window.location.origin+'/rezervace?resume='+MG._rez.bookingId):'';

  // Mobile: button goes to Mindee step; Desktop: button goes to Stripe payment
  var payBtnLabel=isMob?'Ověřit doklady a zaplatit':'Pokračovat k platbě';
  var payBtnAction=isMob?'MG._rezShowMindeeStep()':'MG._rezSubmitPayment()';

  // QR code section (desktop only) — allows customer to continue on mobile
  var qrSectionMarkup = '';
  if(!isMob && resumeLink){
    qrSectionMarkup =
      '<div class="rez-qr-card">'+
      '<img src="'+MG._qrCodeUrl(resumeLink)+'" alt="QR kód">'+
      '<div class="rez-qr-body">'+
      '<h3>Dokončete na mobilu</h3>'+
      '<div class="rez-qr-bullets">'+
      '<div>&#10003; Apple Pay / Google Pay</div>'+
      '<div>&#10003; Sken dokladů fotoaparátem</div>'+
      '<div>&#10003; Autonomní pobočka</div></div>'+
      '<p class="rez-qr-note">QR platný 4 hodiny</p></div></div>';
  }

  form.innerHTML=
    // Hero — fotka rezervované motorky (kompaktní galerie)
    '<div id="rez-moto-hero-wrap">'+MG._rezGalleryHtml(moto)+'</div>'+

    // Section 1 — Verifikace dokladů + ŘP
    '<section class="rez-section">'+
      '<div class="rez-section-head"><span class="rez-step-num">1</span><h2>Ověření totožnosti a řidičského oprávnění</h2></div>'+
      '<p class="rez-section-sub">Pro přípravu nájemní smlouvy vyplňte údaje z dokladu totožnosti a řidičského průkazu.</p>'+

      '<h3 class="rez-subhead"><span class="rez-subhead-ico">&#128196;</span>Doklad totožnosti</h3>'+
      '<div class="rez-doc-grid">'+
        '<label class="rez-doc-card"><input type="radio" id="rez-doc-op" name="rez-doc-type" value="op" checked>'+
        '<span class="rez-doc-ico">&#128100;</span><span class="rez-doc-label">Občanský průkaz</span></label>'+
        '<label class="rez-doc-card"><input type="radio" id="rez-doc-pas" name="rez-doc-type" value="pas">'+
        '<span class="rez-doc-ico">&#128370;</span><span class="rez-doc-label">Cestovní pas</span></label>'+
      '</div>'+
      '<label class="rez-field-label" for="rez-doc-number">* Číslo dokladu</label>'+
      '<input type="text" id="rez-doc-number" class="rez-input" placeholder="Zadejte číslo dokladu totožnosti" required autocomplete="off"'+(MG._rez._docNumber?' value="'+MG._rez._docNumber+'"':'')+'>'+

      '<h3 class="rez-subhead"><span class="rez-subhead-ico">&#128663;</span>Řidičský průkaz</h3>'+
      '<div id="rez-license-num-wrap">'+
        '<label class="rez-field-label" for="rez-license-number">* Číslo řidičského průkazu</label>'+
        '<input type="text" id="rez-license-number" class="rez-input" placeholder="Zadejte číslo ŘP" autocomplete="off"'+(MG._rez._licenseNumber?' value="'+MG._rez._licenseNumber+'"':'')+'>'+
      '</div>'+
      '<div style="margin-top:.85rem">'+
        '<label class="rez-field-label">* Skupina ŘP</label>'+
        '<div id="rez-license-group-chips" style="display:flex;gap:.5rem;flex-wrap:wrap">'+
          '<button type="button" class="lic-chip" data-val="A2">A2</button>'+
          '<button type="button" class="lic-chip" data-val="A">A</button>'+
          '<button type="button" class="lic-chip" data-val="N">Bez ŘP</button>'+
        '</div>'+
        '<input type="hidden" id="rez-license-group" value="">'+
      '</div>'+
      '<div id="rez-license-expiry-wrap" style="margin-top:.85rem">'+
        '<label class="rez-field-label">* Platnost ŘP do</label>'+
        '<div class="rez-date-row">'+
          '<select id="rez-lic-day" class="lic-date-sel" aria-label="Den"></select>'+
          '<select id="rez-lic-month" class="lic-date-sel" aria-label="Měsíc"></select>'+
          '<select id="rez-lic-year" class="lic-date-sel" aria-label="Rok"></select>'+
        '</div>'+
        '<input type="hidden" id="rez-license-expiry" value="">'+
      '</div>'+
      '<div id="rez-license-confirm-wrap" style="margin:.95rem 0 .25rem">'+
        '<label class="rez-agree"><input type="checkbox" id="rez-license-confirm"'+(MG._rez._docsValidated?' checked':'')+'>'+
        '<span>* Potvrzuji, že jsem držitelem platného řidičského oprávnění a splňuji zákonné podmínky k řízení rezervovaného motocyklu.</span></label>'+
      '</div>'+
    '</section>'+

    // Section 2 — volitelné nahrání dokladů (desktop only — mobil dostane plnou Mindee step po Pokračovat)
    (!isMob?
    '<section class="rez-section">'+
      '<div class="rez-section-head"><span class="rez-step-num">2</span><h2>Nahrání dokladů</h2></div>'+
      '<p class="rez-section-sub">Volitelné — zrychlí odbavení. Fotografie automaticky rozpoznáme a údaje doplníme do formuláře.</p>'+
      '<div class="rez-doc-upload-grid">'+
        '<div class="rez-doc-upload-card">'+
          '<div class="rez-doc-upload-card-head">&#128196; Doklad totožnosti</div>'+
          '<div id="webdoc-id-status"></div>'+
          '<div class="rez-doc-upload-actions">'+
            '<button class="btn btngreen-small" onclick="MG._rezCaptureDoc(\'id\')" style="font-size:.8rem">&#128247; Vyfotit (skener)</button>'+
            '<button class="btn btngreen-small" onclick="MG._rezUploadDoc(\'id\')" style="font-size:.8rem">&#128194; Nahrát soubor</button>'+
          '</div>'+
        '</div>'+
        '<div class="rez-doc-upload-card">'+
          '<div class="rez-doc-upload-card-head">&#128663; Řidičský průkaz</div>'+
          '<div id="webdoc-dl-status"></div>'+
          '<div class="rez-doc-upload-actions">'+
            '<button class="btn btngreen-small" onclick="MG._rezCaptureDoc(\'dl\')" style="font-size:.8rem">&#128247; Vyfotit (skener)</button>'+
            '<button class="btn btngreen-small" onclick="MG._rezUploadDoc(\'dl\')" style="font-size:.8rem">&#128194; Nahrát soubor</button>'+
          '</div>'+
        '</div>'+
      '</div>'+
    '</section>':'')+

    // Section 3 — Heslo pro správu rezervace
    '<section class="rez-section">'+
      '<div class="rez-section-head"><span class="rez-step-num">'+(isMob?'2':'3')+'</span><h2>Heslo pro správu rezervace</h2></div>'+
      '<div class="rez-pwd-section">'+
        '<div class="rez-pwd-head">'+
          '<span class="rez-pwd-ico">&#128274;</span>'+
          '<div><div class="rez-pwd-title">Vytvořte si přístupové heslo</div>'+
          '<p class="rez-pwd-sub">Pro úpravu rezervace a přihlášení do aplikace MotoGo24. Min. 8 znaků.</p></div>'+
        '</div>'+
        '<div class="rez-pwd-grid">'+
          '<input type="password" id="rez-password" class="rez-input" name="new-password" placeholder="* Heslo (min. 8 znaků)" required autocomplete="new-password" minlength="8">'+
          '<input type="password" id="rez-password-confirm" class="rez-input" name="new-password" placeholder="* Potvrzení hesla" required autocomplete="new-password" minlength="8">'+
        '</div>'+
      '</div>'+
      qrSectionMarkup+
    '</section>'+

    // Section 4 — Doprodej (e-shop produkty) — jen pokud nejsme v resume režimu
    (MG._rez._isResume?'':
      '<section class="rez-section">'+
        '<div class="rez-section-head"><span class="rez-step-num">'+(isMob?'3':'4')+'</span><h2>Doplňky na cestu</h2></div>'+
        '<p class="rez-section-sub">Přidejte si k pronájmu výbavu nebo doplňky. <strong>Vyzvednete s motorkou</strong>, doprava 0 Kč. Faktura za doplňky přijde samostatně.</p>'+
        '<div id="rez-shop-products"><div class="rez-prod-loading"><span class="spinner"></span> Načítám doplňky…</div></div>'+
      '</section>')+

    // Section 5 — Náhled zálohové faktury
    '<section class="rez-section">'+
      '<div class="rez-section-head"><span class="rez-step-num">'+(MG._rez._isResume?(isMob?'3':'4'):(isMob?'4':'5'))+'</span><h2>Náhled zálohové faktury</h2></div>'+
      '<div class="rez-invoice-card" id="rez-invoice-box"></div>'+
      '<div class="rez-invoice-meta">'+
        '<div class="rez-meta-row"><span class="rez-meta-ico">&#128100;</span>'+
          '<div class="rez-meta-body"><div class="rez-meta-label">Odběratel</div>'+
          '<div class="rez-meta-value">'+d.name+' &middot; '+d.email+(d.phone?' &middot; '+d.phone:'')+
          ((d.street||d.city||d.zip)?'<br><span class="rez-meta-dim">'+(d.street?d.street+', ':'')+(d.zip?d.zip+' ':'')+(d.city||'')+'</span>':'')+
          '</div></div></div>'+
        '<div class="rez-meta-row"><span class="rez-meta-ico">&#127949;</span>'+
          '<div class="rez-meta-body"><div class="rez-meta-label">Motorka &amp; termín</div>'+
          '<div class="rez-meta-value">'+motoName+' &middot; '+MG.formatDate(r.startDate)+' – '+MG.formatDate(r.endDate)+'</div></div></div>'+
        (d.deliveryAddr?'<div class="rez-meta-row"><span class="rez-meta-ico">&#128666;</span>'+
          '<div class="rez-meta-body"><div class="rez-meta-label">Přistavení</div>'+
          '<div class="rez-meta-value">'+d.deliveryAddr+'</div></div></div>':'')+
        (d.returnAddr?'<div class="rez-meta-row"><span class="rez-meta-ico">&#128205;</span>'+
          '<div class="rez-meta-body"><div class="rez-meta-label">Vrácení</div>'+
          '<div class="rez-meta-value">'+d.returnAddr+'</div></div></div>':'')+
      '</div>'+
    '</section>'+

    // Akční lišta
    '<div class="rez-step2-actions">'+
      (MG._rez._isResume?'<a class="btn btndark" href="/rezervace">&#8592; Nová rezervace</a>':
      '<button class="btn btndark" onclick="MG._rezBackToStep1()">&#8592; Zpět</button>')+
      '<div class="rez-step2-pay">'+
        '<div class="rez-step2-amount">'+MG.formatPrice(total)+'</div>'+
        '<button class="btn btngreen" onclick="'+payBtnAction+'">'+payBtnLabel+'</button>'+
      '</div>'+
    '</div>';
  MG._rezInitLicenseUI();
  MG._rezInitGallery();
  MG._rezRefreshInvoice();
  // Lazy-load products and render upsell section
  if(!MG._rez._isResume){
    MG._rezLoadProducts().then(function(){ MG._rezRefreshShopUi(); });
  }
  window.scrollTo({top:form.offsetTop-80,behavior:'smooth'});
};

// ===== LICENSE UI: chips for group + custom date picker =====
MG._rezInitLicenseUI = function(){
  // Inject styles once
  if(!document.getElementById('mg-lic-styles')){
    var st=document.createElement('style'); st.id='mg-lic-styles';
    st.textContent =
      '.lic-chip{padding:.6rem 1.1rem;border:1.5px solid #d4e8e0;background:#fff;border-radius:999px;font-size:.95rem;font-weight:700;cursor:pointer;color:#1a2e22;transition:all .15s;min-width:72px;font-family:Montserrat,sans-serif}'+
      '.lic-chip:hover{border-color:#74FB71;background:#f0faf5;transform:translateY(-1px)}'+
      '.lic-chip.active{background:#1a8c1a;border-color:#1a8c1a;color:#fff;box-shadow:0 3px 10px rgba(26,140,26,.35);transform:translateY(-1px)}';
    document.head.appendChild(st);
  }

  // ---- Group chips ----
  var hidden = document.getElementById('rez-license-group');
  var expiryWrap = document.getElementById('rez-license-expiry-wrap');
  var chips = document.querySelectorAll('#rez-license-group-chips .lic-chip');
  var pre = (MG._rez && MG._rez.formData && MG._rez.formData._licGroup) || '';
  var numWrap = document.getElementById('rez-license-num-wrap');
  var confirmWrap = document.getElementById('rez-license-confirm-wrap');
  function applyGroup(val){
    hidden.value = val;
    chips.forEach(function(c){ c.classList.toggle('active', c.dataset.val === val); });
    var hide = (val === 'N');
    if(expiryWrap) expiryWrap.style.display = hide ? 'none' : '';
    if(numWrap) numWrap.style.display = hide ? 'none' : '';
    if(confirmWrap) confirmWrap.style.display = hide ? 'none' : '';
  }
  chips.forEach(function(c){
    c.addEventListener('click', function(){ applyGroup(c.dataset.val); });
  });
  if(pre) applyGroup(pre);

  // ---- Date selects ----
  var dSel=document.getElementById('rez-lic-day');
  var mSel=document.getElementById('rez-lic-month');
  var ySel=document.getElementById('rez-lic-year');
  var hiddenExp=document.getElementById('rez-license-expiry');
  if(!dSel||!mSel||!ySel) return;

  var now=new Date(); var thisYear=now.getFullYear();
  var monthNames=['leden','únor','březen','duben','květen','červen','červenec','srpen','září','říjen','listopad','prosinec'];

  function opt(val,label,sel){ var o=document.createElement('option'); o.value=val; o.textContent=label; if(sel) o.selected=true; return o; }

  // Day select
  dSel.appendChild(opt('','Den',true));
  for(var i=1;i<=31;i++) dSel.appendChild(opt(i, i<10?('0'+i):(''+i)));
  // Month select
  mSel.appendChild(opt('','Měsíc',true));
  for(var m=1;m<=12;m++){ var lbl=(m<10?('0'+m):(''+m))+' — '+monthNames[m-1]; mSel.appendChild(opt(m, lbl)); }
  // Year select (this year .. this year + 20)
  ySel.appendChild(opt('','Rok',true));
  for(var y=thisYear; y<=thisYear+20; y++) ySel.appendChild(opt(y, y));

  function syncExpiry(){
    var d=dSel.value, m=mSel.value, y=ySel.value;
    if(!d||!m||!y){ hiddenExp.value=''; return; }
    var iso = y+'-'+(m<10?('0'+m):(''+m))+'-'+(d<10?('0'+d):(''+d));
    var test=new Date(iso);
    if(isNaN(test.getTime())){ hiddenExp.value=''; return; }
    if(test.getFullYear()!=y || (test.getMonth()+1)!=parseInt(m,10) || test.getDate()!=parseInt(d,10)){
      hiddenExp.value=''; return;
    }
    hiddenExp.value = iso;
  }
  [dSel,mSel,ySel].forEach(function(s){ s.addEventListener('change', syncExpiry); });

  // Restore previous value if any
  var prev = (MG._rez && MG._rez.formData && MG._rez.formData._licExpiry) || '';
  if(prev && /^\d{4}-\d{2}-\d{2}$/.test(prev)){
    var pp=prev.split('-');
    ySel.value=parseInt(pp[0],10); mSel.value=parseInt(pp[1],10); dSel.value=parseInt(pp[2],10);
    syncExpiry();
  }
};

// ===== BACK TO STEP 1 =====
MG._rezBackToStep1 = function(){
  var form=document.getElementById('rez-form');if(!form)return;
  // Zruš případnou již vytvořenou shop objednávku (zákazník mění rezervaci)
  MG._rez._shopOrderId = null;
  // Show calendar elements again
  ['rez-intro','rez-step-moto','rez-step-cal','rez-calendar','rez-date-banner','rez-moto-select'].forEach(function(id){
    var el=document.getElementById(id);if(el)el.style.display='';
  });
  form.outerHTML=MG._rezFormHtml();MG._rezInitFormEvents();
  var d=MG._rez.formData;if(!d)return;
  var f=function(id,v){var e=document.getElementById(id);if(e&&v)e.value=v;};
  f('rez-name',d.name);f('rez-email',d.email);f('rez-phone',d.phone);
  f('rez-street',d.street);f('rez-city',d.city);f('rez-zip',d.zip);
  f('rez-country',d.country);f('rez-pickup-time',d.pickupTime);
  // Trigger pickup-time chip highlight (zachova default 09:00 i puvodni vyber)
  var ptInpB = document.getElementById('rez-pickup-time');
  if(ptInpB && ptInpB.value){ ptInpB.dispatchEvent(new Event('change',{bubbles:true})); }

  // Restore sizes UI
  MG._rezRestoreSizesUI();
  MG._rezUpdatePrice();
};

// ===== RESTORE SIZES UI from MG._rez.sizes =====
MG._rezRestoreSizesUI = function(){
  var s = MG._rez.sizes || {rider:{}, passenger:{}};
  // Tick parent gear card if any size selected
  var groups = {
    'rez-eq-rider-gear': ['rider', ['helmet','jacket','gloves','pants']],
    'rez-eq-passenger':  ['passenger', ['helmet','jacket','gloves']],
    'rez-eq-boots-rider': ['rider', ['boots']],
    'rez-eq-boots-passenger': ['passenger', ['boots']]
  };
  Object.keys(groups).forEach(function(cbId){
    var grp = groups[cbId][0], keys = groups[cbId][1];
    var hasAny = keys.some(function(k){ return (s[grp]||{})[k]; });
    var cb = document.getElementById(cbId);
    if(cb && hasAny){ cb.checked = true; var card = cb.closest('.gear-card'); if(card) card.classList.add('open'); }
  });
  // Mark active chips
  document.querySelectorAll('.size-chips').forEach(function(g){
    var grp = g.dataset.group, key = g.dataset.key;
    var sel = (s[grp]||{})[key];
    if(!sel) return;
    g.querySelectorAll('.size-chip').forEach(function(b){
      if(b.dataset.size === sel) b.classList.add('active');
    });
    var head = g.previousElementSibling;
    if(head){ var pick = head.querySelector('.size-pick'); if(pick){ pick.textContent = sel; pick.dataset.empty='0'; } }
  });
};

// Mindee scan + Stripe payment → pages-rezervace-scan.js
