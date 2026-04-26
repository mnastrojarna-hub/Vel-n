// ===== MotoGo24 Web PHP — Stránka Rezervace: init + form + events =====
// Adaptace pro PHP: žádný MG.route(), params z window.REZERVACE_PARAMS, čisté URL
var MG = window.MG || {};
window.MG = MG;

MG._rez = { startDate: null, endDate: null, motos: [], motoId: '', allBookings: {}, appliedCodes: [], discountAmt: 0,
  sizes: { rider:{}, passenger:{} } };

// ===== TOOLTIP HELPER =====
MG._tip = function(text){ return ' <span class="ctooltip">&#9432;<span class="ctooltiptext">'+text+'</span></span>'; };
MG._reqTip = function(){ return ' <span class="ctooltip" style="color:#c00;font-size:.75rem">*<span class="ctooltiptext">Toto pole je povinné</span></span>'; };

// ===== SIZE CHIP HELPERS =====
MG._SIZE_CHIPS_GEAR  = ['XS','S','M','L','XL','XXL'];
MG._SIZE_CHIPS_PANTS = ['XS','S','M','L','XL','XXL'];
MG._SIZE_CHIPS_BOOTS = ['36','37','38','39','40','41','42','43','44','45','46'];

MG._renderSizeChips = function(group, key, sizes, label, icon){
  var sel = (MG._rez.sizes[group]||{})[key] || '';
  var h = '<div class="size-row"><div class="size-row-head"><span class="size-ico">'+icon+'</span><span class="size-lbl">'+label+'</span>'+
    '<span class="size-pick" data-empty="'+(sel?'0':'1')+'">'+(sel?sel:'vyber')+'</span></div>'+
    '<div class="size-chips" data-group="'+group+'" data-key="'+key+'">';
  sizes.forEach(function(s){
    h += '<button type="button" class="size-chip'+(s===sel?' active':'')+'" data-size="'+s+'">'+s+'</button>';
  });
  h += '</div></div>';
  return h;
};

MG._gearPanelHtml = function(opts){
  // opts: { panelId, group ('rider'|'passenger'), kinds: ['helmet','jacket','gloves','pants','boots'] }
  var labels = {
    helmet: { l:'Helma',     ico:'&#129695;', sizes: MG._SIZE_CHIPS_GEAR },
    jacket: { l:'Bunda',     ico:'&#129509;', sizes: MG._SIZE_CHIPS_GEAR },
    gloves: { l:'Rukavice',  ico:'&#129306;', sizes: MG._SIZE_CHIPS_GEAR },
    pants:  { l:'Kalhoty',   ico:'&#128087;', sizes: MG._SIZE_CHIPS_PANTS },
    boots:  { l:'Boty',      ico:'&#129406;', sizes: MG._SIZE_CHIPS_BOOTS }
  };
  var rows = '';
  opts.kinds.forEach(function(k){
    var c = labels[k]; if(!c) return;
    rows += MG._renderSizeChips(opts.group, k, c.sizes, c.l, c.ico);
  });
  return '<div class="gear-size-panel" id="'+opts.panelId+'">'+rows+'</div>';
};

MG._initSizeChipEvents = function(scope){
  var root = scope || document;
  root.querySelectorAll('.size-chips').forEach(function(grp){
    if(grp.dataset.bound==='1') return; grp.dataset.bound='1';
    grp.addEventListener('click', function(ev){
      var btn = ev.target.closest('.size-chip'); if(!btn) return;
      var group = grp.dataset.group, key = grp.dataset.key, val = btn.dataset.size;
      MG._rez.sizes[group] = MG._rez.sizes[group] || {};
      var prev = MG._rez.sizes[group][key];
      if(prev === val){ delete MG._rez.sizes[group][key]; }
      else { MG._rez.sizes[group][key] = val; }
      grp.querySelectorAll('.size-chip').forEach(function(b){ b.classList.remove('active'); });
      if(MG._rez.sizes[group][key]){ btn.classList.add('active'); }
      var head = grp.previousElementSibling;
      if(head){
        var pick = head.querySelector('.size-pick');
        var current = MG._rez.sizes[group][key];
        if(pick){ pick.textContent = current ? current : 'vyber'; pick.dataset.empty = current ? '0' : '1'; }
      }
    });
  });
};

// ===== STATIC FORM HTML =====
MG._rezFormHtml = function(){
  // Quick-time chips 06:00 .. 14:00 (po hodině), default vyznačeno 09:00
  var qt = ['06:00','07:00','08:00','09:00','10:00','11:00','12:00','13:00','14:00'];
  var quickChips = qt.map(function(t){
    var act = t === '09:00' ? ' active' : '';
    return '<button type="button" class="time-chip'+act+'" data-time="'+t+'">'+t+'</button>';
  }).join('');

  return '<div id="rez-form">' +
    // ===== STEP A — Kontaktní údaje =====
    '<section class="rez-section">' +
      '<div class="rez-section-head"><span class="rez-step-num">3</span><h2>Vaše kontaktní údaje</h2></div>' +
      '<input type="text" id="rez-name" name="name" placeholder="* Jméno a příjmení" required autocomplete="name">' +
      '<div class="gr2"><input type="text" id="rez-street" name="street-address" placeholder="* Ulice, č.p." required autocomplete="street-address">' +
      '<input type="text" id="rez-zip" name="postal-code" placeholder="* PSČ" required autocomplete="postal-code"></div>' +
      '<div class="gr2"><input type="text" id="rez-city" name="address-level2" placeholder="* Město" required autocomplete="address-level2">' +
      '<input type="text" id="rez-country" name="country-name" placeholder="* Stát" value="Česká republika" required autocomplete="country-name"></div>' +
      '<div class="gr2"><input type="email" id="rez-email" name="email" placeholder="* E-mail" required autocomplete="email">' +
      '<input type="tel" id="rez-phone" name="tel" placeholder="* Telefon (+420XXXXXXXXX)" required autocomplete="tel" pattern="^\\+\\d{12,15}$"></div>' +
      '<div class="rez-voucher-row"><input type="text" id="rez-voucher" placeholder="Slevový kód / dárkový poukaz" maxlength="255">' +
      '<button type="button" class="btn btngreen-small" onclick="MG._applyVoucher()">UPLATNIT</button></div>' +
      '<div id="rez-applied-codes"></div>' +
      '<div id="rez-voucher-msg" style="font-size:.85rem;margin:-.25rem 0 .25rem"></div>' +
    '</section>' +

    // ===== STEP B — Místo a čas =====
    '<section class="rez-section">' +
      '<div class="rez-section-head"><span class="rez-step-num">4</span><h2>Vyzvednutí a vrácení</h2></div>' +

      // Time card
      '<div class="rez-time-card">' +
        '<div class="rez-time-card-head"><span class="rez-time-ico">&#128340;</span>' +
        '<div><div class="rez-time-title">Čas převzetí nebo přistavení</div>' +
        '<div class="rez-time-sub">Vyberte z nabídky nebo zadejte vlastní čas</div></div>' +
        '<input type="time" id="rez-pickup-time" required value="09:00"></div>' +
        '<div class="rez-time-chips-label">Doporučené časy (06:00 — 14:00) <span style="color:#8aab99;font-weight:500;font-size:.75rem">· nebo vyberte vlastní čas vlevo</span></div>' +
        '<div class="rez-time-chips">'+quickChips+'</div>' +
      '</div>' +

      // Pickup option (delivery checkbox card)
      '<div class="rez-loc-grid">' +
        '<label class="rez-loc-card rez-loc-card-info">' +
          '<div class="rez-loc-ico">&#127968;</div>' +
          '<div class="rez-loc-body"><div class="rez-loc-title">Vyzvednutí v motopůjčovně</div>' +
          '<div class="rez-loc-sub">Zdarma · 24/7 přístup s kódem · základní nastavení</div></div>' +
        '</label>' +
        '<label class="rez-loc-card" data-loc="delivery">' +
          '<input type="checkbox" id="rez-delivery">' +
          '<div class="rez-loc-ico">&#128666;</div>' +
          '<div class="rez-loc-body"><div class="rez-loc-title">Přistavení motorky jinam' +
          MG._tip('Motorku vám dovezeme na domluvené místo. Cena: '+MG.formatPrice(1000)+' + '+MG.formatPrice(40)+'/km od pobočky Mezná 9, 393 01 Mezná. Trasu spočítáme automaticky po zadání adresy.') +
          '</div><div class="rez-loc-sub">'+MG.formatPrice(1000)+' + '+MG.formatPrice(40)+'/km od pobočky</div></div>' +
        '</label>' +
      '</div>' +

      // Delivery panel
      '<div id="rez-delivery-panel" class="rez-addr-panel" style="display:none">' +
        '<div class="rez-addr-row">' +
          '<input type="text" id="rez-delivery-address" placeholder="Zadejte adresu přistavení (ulice, město)">' +
          '<button type="button" class="rez-map-btn" onclick="MG._openWebMapPicker(\'delivery\')">&#128205; Mapa</button>' +
        '</div>' +
        '<div id="rez-delivery-route-info" class="rez-route-info" style="display:none"></div>' +
        '<div class="rez-addr-confirm" style="margin-top:.4rem"><label><input type="checkbox" id="rez-return-same-as-delivery" checked> Vrátit motorku na stejné adrese</label></div>' +
      '</div>' +

      // Return-other card
      '<div class="rez-loc-grid" style="grid-template-columns:1fr">' +
        '<label class="rez-loc-card" data-loc="return-other">' +
          '<input type="checkbox" id="rez-return-other">' +
          '<div class="rez-loc-ico">&#128205;</div>' +
          '<div class="rez-loc-body"><div class="rez-loc-title">Vrácení motorky jinde, než kde bylo vyzvednuto' +
          MG._tip('Motorku vám rádi vyzvedneme jinde. Cena: '+MG.formatPrice(1000)+' + '+MG.formatPrice(40)+'/km od pobočky Mezná 9, 393 01 Mezná. Trasu spočítáme automaticky po zadání adresy.') +
          '</div><div class="rez-loc-sub">'+MG.formatPrice(1000)+' + '+MG.formatPrice(40)+'/km od pobočky</div></div>' +
        '</label>' +
      '</div>' +

      // Return panel
      '<div id="rez-return-panel" class="rez-addr-panel" style="display:none">' +
        '<div class="rez-addr-row">' +
          '<input type="text" id="rez-return-address" placeholder="Zadejte adresu vrácení">' +
          '<button type="button" class="rez-map-btn" onclick="MG._openWebMapPicker(\'return\')">&#128205; Mapa</button>' +
        '</div>' +
        '<div id="rez-return-route-info" class="rez-route-info" style="display:none"></div>' +
        '<div class="rez-time-card rez-time-card-mini" style="margin-top:.6rem">' +
          '<div class="rez-time-card-head"><span class="rez-time-ico">&#128340;</span>' +
          '<div><div class="rez-time-title">Čas vrácení</div></div>' +
          '<input type="time" id="rez-return-time" value="19:00"></div>' +
        '</div>' +
      '</div>' +
    '</section>' +

    // ===== STEP C — Výbava =====
    '<section class="rez-section">' +
      '<div class="rez-section-head"><span class="rez-step-num">5</span><h2>Výbava a velikosti</h2></div>' +
      '<p class="rez-section-sub">Vyberte velikosti kliknutím na čtverečky níže. Pokud velikost nezvolíte, vyzkoušíme ji na místě.</p>' +

      '<div class="gear-grid">' +

        // Driver gear (free) — collapsed by default
        '<div class="gear-card gear-card-rider" id="gear-card-rider">' +
          '<label class="gear-head">' +
            '<input type="checkbox" id="rez-eq-rider-gear">' +
            '<span class="gear-ico">&#127949;</span>' +
            '<div class="gear-body"><div class="gear-title">Výbava řidiče</div>' +
            '<div class="gear-price gear-price-free">v ceně · zdarma</div>' +
            '<div class="gear-sub">Helma, bunda, rukavice, kalhoty</div></div>' +
          '</label>' +
          '<div class="gear-extra-toggle"><label><input type="checkbox" id="rez-own-gear"> Mám vlastní výbavu — nepůjčuji</label></div>' +
          '<div class="gear-size-panel-hint">&#9989; Zaškrtněte výše pro výběr velikostí (jinak se vyzkouší na místě)</div>' +
          MG._gearPanelHtml({panelId:'gear-panel-rider', group:'rider', kinds:['helmet','jacket','gloves','pants']}) +
        '</div>' +

        // Passenger basic kit
        '<div class="gear-card" id="gear-card-passenger">' +
          '<label class="gear-head">' +
            '<input type="checkbox" id="rez-eq-passenger">' +
            '<span class="gear-ico">&#128107;</span>' +
            '<div class="gear-body"><div class="gear-title">Výbava spolujezdce</div>' +
            '<div class="gear-price">+ '+MG.formatPrice(690)+'</div>' +
            '<div class="gear-sub">Helma, bunda, rukavice, kukla' +
            MG._tip('Základní výbava pro spolujezdce: helma, bunda, rukavice a kukla. Velikost si vyberete kliknutím níže nebo na místě.') +
            '</div></div>' +
          '</label>' +
          '<div class="gear-size-panel-hint">&#9989; Zaškrtněte výše a rozbalí se výběr velikostí spolujezdce</div>' +
          MG._gearPanelHtml({panelId:'gear-panel-passenger', group:'passenger', kinds:['helmet','jacket','gloves']}) +
        '</div>' +

        // Boots driver
        '<div class="gear-card" id="gear-card-boots-rider">' +
          '<label class="gear-head">' +
            '<input type="checkbox" id="rez-eq-boots-rider">' +
            '<span class="gear-ico">&#129406;</span>' +
            '<div class="gear-body"><div class="gear-title">Boty pro řidiče</div>' +
            '<div class="gear-price">+ '+MG.formatPrice(290)+'</div>' +
            '<div class="gear-sub">Motocyklové boty (nejsou v základní výbavě)</div></div>' +
          '</label>' +
          '<div class="gear-size-panel-hint">&#9989; Zaškrtněte výše a rozbalí se výběr velikosti bot</div>' +
          MG._gearPanelHtml({panelId:'gear-panel-boots-rider', group:'rider', kinds:['boots']}) +
        '</div>' +

        // Boots passenger
        '<div class="gear-card" id="gear-card-boots-passenger">' +
          '<label class="gear-head">' +
            '<input type="checkbox" id="rez-eq-boots-passenger">' +
            '<span class="gear-ico">&#129406;</span>' +
            '<div class="gear-body"><div class="gear-title">Boty pro spolujezdce</div>' +
            '<div class="gear-price">+ '+MG.formatPrice(290)+'</div>' +
            '<div class="gear-sub">Motocyklové boty pro spolujezdce</div></div>' +
          '</label>' +
          '<div class="gear-size-panel-hint">&#9989; Zaškrtněte výše a rozbalí se výběr velikosti bot</div>' +
          MG._gearPanelHtml({panelId:'gear-panel-boots-passenger', group:'passenger', kinds:['boots']}) +
        '</div>' +

      '</div>' +
    '</section>' +

    // ===== STEP D — Souhlasy =====
    '<section class="rez-section">' +
      '<div class="rez-section-head"><span class="rez-step-num">6</span><h2>Souhlasy</h2></div>' +
      '<div class="rez-agreements">' +
        '<label class="rez-agree"><input type="checkbox" id="rez-agree-vop" required checked><span>* Souhlasím s <a href="/obchodni-podminky">obchodními podmínkami</a></span></label>' +
        '<label class="rez-agree"><input type="checkbox" id="rez-agree-gdpr" checked><span>Souhlasím se <a href="/gdpr">zpracováním osobních údajů</a></span></label>' +
        '<label class="rez-agree"><input type="checkbox" id="rez-agree-marketing" checked><span>Souhlasím se zasíláním marketingových sdělení</span></label>' +
        '<label class="rez-agree"><input type="checkbox" id="rez-agree-photo" checked><span>Souhlasím s využitím fotografií pro marketingové účely</span></label>' +
      '</div>' +
    '</section>' +

    '<input type="hidden" id="rez-note" value="">' +
    '<div id="rez-price-preview"></div>' +
    '<div class="text-center" style="margin-top:1rem"><button type="button" class="btn btngreen rez-cta" onclick="MG._submitReservation()">Pokračovat v rezervaci &rarr;</button></div>' +
    '</div>';
};

// ===== INIT FORM EVENTS (called once) =====
MG._rezInitFormEvents = function(){
  // Delivery toggle
  var dc = document.getElementById('rez-delivery');
  if(dc) dc.addEventListener('change',function(){
    var p=document.getElementById('rez-delivery-panel');
    if(p) p.style.display=this.checked?'block':'none';
    var card = document.getElementById('gear-card-rider'); // delivery may want pre-fitted rider gear
    if(card){
      var cb = document.getElementById('rez-eq-rider-gear');
      if(this.checked && cb && !cb.checked){ cb.checked = true; card.classList.add('open'); }
    }
    MG._rezUpdatePrice();
  });
  // Return-other toggle
  var retO = document.getElementById('rez-return-other');
  if(retO) retO.addEventListener('change',function(){
    var p=document.getElementById('rez-return-panel');
    if(p) p.style.display=this.checked?'block':'none';
    var rSame = document.getElementById('rez-return-same-as-delivery');
    if(rSame && this.checked) rSame.checked=false;
    MG._rezUpdatePrice();
  });
  var rSame = document.getElementById('rez-return-same-as-delivery');
  if(rSame) rSame.addEventListener('change',function(){
    if(this.checked){
      var ro=document.getElementById('rez-return-other');
      if(ro){ ro.checked=false; var p=document.getElementById('rez-return-panel'); if(p) p.style.display='none'; }
      // Propagace distance: return = delivery
      if(typeof MG._rez.deliveryDistanceKm === 'number'){
        MG._rez.returnDistanceKm = MG._rez.deliveryDistanceKm;
      }
    }
    MG._rezUpdatePrice();
  });
  // Own gear toggle — když má vlastní, schovej rider size panel
  var og = document.getElementById('rez-own-gear');
  if(og) og.addEventListener('change',function(){
    var card = document.getElementById('gear-card-rider');
    if(!card) return;
    if(this.checked){
      // Vyčistit rider velikosti + UI
      MG._rez.sizes.rider = {};
      card.querySelectorAll('.size-chip.active').forEach(function(b){ b.classList.remove('active'); });
      card.querySelectorAll('.size-pick').forEach(function(p){ p.textContent='vyber'; p.dataset.empty='1'; });
      card.classList.add('disabled');
    } else {
      card.classList.remove('disabled');
    }
  });

  // Gear card heads — toggle open/close on checkbox change + sync ui
  ['rez-eq-rider-gear','rez-eq-passenger','rez-eq-boots-rider','rez-eq-boots-passenger'].forEach(function(id){
    var cb = document.getElementById(id);
    if(!cb) return;
    cb.addEventListener('change', function(){
      var card = cb.closest('.gear-card');
      if(card){
        if(cb.checked) card.classList.add('open');
        else {
          card.classList.remove('open');
          // Clear sizes on uncheck
          var panel = card.querySelector('.gear-size-panel');
          if(panel){
            var grps = panel.querySelectorAll('.size-chips');
            grps.forEach(function(g){
              var grp = g.dataset.group, key = g.dataset.key;
              if(MG._rez.sizes[grp]) delete MG._rez.sizes[grp][key];
              g.querySelectorAll('.size-chip.active').forEach(function(b){ b.classList.remove('active'); });
            });
            panel.querySelectorAll('.size-pick').forEach(function(p){ p.textContent='vyber'; p.dataset.empty='1'; });
          }
        }
      }
      MG._rezUpdatePrice();
    });
  });

  // Quick time chips
  var chipWrap = document.querySelector('.rez-time-chips');
  if(chipWrap){
    chipWrap.addEventListener('click', function(ev){
      var btn = ev.target.closest('.time-chip'); if(!btn) return;
      var t = btn.dataset.time;
      var inp = document.getElementById('rez-pickup-time');
      if(inp){ inp.value = t; inp.dispatchEvent(new Event('change',{bubbles:true})); }
      chipWrap.querySelectorAll('.time-chip.active').forEach(function(b){ b.classList.remove('active'); });
      btn.classList.add('active');
    });
  }
  var ptInp = document.getElementById('rez-pickup-time');
  if(ptInp){
    ptInp.addEventListener('change', function(){
      var v = ptInp.value;
      document.querySelectorAll('.time-chip').forEach(function(b){
        if(b.dataset.time === v) b.classList.add('active');
        else b.classList.remove('active');
      });
    });
  }

  // Size chips
  MG._initSizeChipEvents();
};

// ===== INIT PAGE (called from PHP inline script) =====
MG._rezInit = async function(){
  var P = window.REZERVACE_PARAMS || {};
  var mp = P.moto || '';
  var preStart = P.start || '';
  var preEnd = P.end || '';
  var preDelivery = P.delivery === '1';
  var resumeId = P.resume || '';

  // ===== RESUME FLOW =====
  if(resumeId){
    var rezApp = document.getElementById('rezervace-app');
    if(rezApp) rezApp.innerHTML = '<div id="rez-form"><div class="loading-overlay"><span class="spinner"></span> Načítám rezervaci...</div></div>';
    try {
      var resumeRes = await window.sb.rpc('get_web_booking_resume', { p_booking_id: resumeId });
      if(resumeRes.error || (resumeRes.data && resumeRes.data.error)){
        document.getElementById('rez-form').innerHTML =
          '<div style="text-align:center;padding:2rem 0"><div style="font-size:3rem;margin-bottom:1rem">&#9888;</div>' +
          '<h2>Rezervace nenalezena</h2><p>' + (resumeRes.data && resumeRes.data.error ? resumeRes.data.error : 'Rezervace již byla dokončena nebo zrušena.') + '</p>' +
          '<p style="margin-top:1rem"><a class="btn btngreen" href="/rezervace">Vytvořit novou rezervaci</a></p></div>';
        return;
      }
      var bd = resumeRes.data;
      MG._rez = {
        startDate: bd.start_date ? bd.start_date.split('T')[0] : null,
        endDate: bd.end_date ? bd.end_date.split('T')[0] : null,
        motos: [{ id: bd.moto_id, model: bd.moto_model }],
        motoId: bd.moto_id, allBookings: {}, appliedCodes: [], discountAmt: 0,
        bookingId: bd.booking_id, userId: bd.user_id, bookingAmount: bd.total_price,
        _isResume: true,
        _docsValidated: bd.has_id_number && bd.has_license_number,
        _docNumber: bd.has_id_number ? '(vyplněno)' : '',
        _licenseNumber: bd.has_license_number ? '(vyplněno)' : '',
        formData: {
          motoId: bd.moto_id, name: bd.customer_name || '', email: bd.customer_email || '',
          phone: bd.customer_phone || '', street: '', city: '', zip: '', country: 'Česká republika',
          extras: [], appliedCodes: [], discountAmt: 0, deliveryAddr: null, returnAddr: null
        }
      };
      if(MG._isMobile() && MG._rez._docsValidated) MG._rezShowMindeeStep();
      else MG._rezShowStep2();
    } catch(e){
      console.error('[REZ] resume error', e);
      document.getElementById('rez-form').innerHTML =
        '<div style="text-align:center;padding:2rem 0"><h2>Chyba při načítání rezervace</h2>' +
        '<p>Zkuste to prosím znovu nebo nás kontaktujte.</p>' +
        '<p style="margin-top:1rem"><a class="btn btngreen" href="/rezervace">Vytvořit novou rezervaci</a></p></div>';
    }
    return;
  }

  // ===== NORMAL FLOW =====
  var rezApp = document.getElementById('rezervace-app');
  if(rezApp){
    rezApp.innerHTML = '<div id="rez-intro"><h1>Rezervace motorky</h1>' +
      '<div style="background:#f0faf5;border:1px solid #d4e8e0;border-radius:10px;padding:.75rem 1rem;margin-bottom:1rem">' +
      '<p style="margin:0 0 .4rem;font-size:.9rem"><strong>Jak rezervace funguje?</strong></p>' +
      '<p style="margin:0 0 .3rem;font-size:.85rem;color:#555">Chcete <strong>konkrétní termín</strong>? Vyberte „libovolná dostupná motorka" a v kalendáři vyznačte datum — zobrazí se všechny volné motorky.</p>' +
      '<p style="margin:0 0 .3rem;font-size:.85rem;color:#555">Chcete <strong>konkrétní motorku</strong>? Vyberte ji ze seznamu — kalendář ukáže její dostupné termíny.</p>' +
      '<p style="margin:0;font-size:.85rem;color:#1a8c1a"><strong>Bez kauce · výbava pro řidiče zdarma · velikost si vyberete v motopůjčovně</strong></p>' +
      '</div></div>' +
      '<section class="rez-section rez-section-pre" id="rez-step-moto">' +
        '<div class="rez-section-head"><span class="rez-step-num">1</span><h2>Vyberte motorku</h2></div>' +
        '<div id="rez-moto-select"></div>' +
      '</section>' +
      '<section class="rez-section rez-section-pre" id="rez-step-cal">' +
        '<div class="rez-section-head"><span class="rez-step-num">2</span><h2>Vyberte termín</h2></div>' +
        '<div id="rez-calendar"></div>' +
        '<div id="rez-date-banner" style="display:none"></div>' +
        '<div id="rez-avail-select" style="display:none"></div>' +
      '</section>' +
      MG._rezFormHtml();
  }

  MG._rez = { startDate: preStart || null, endDate: preEnd || null, motos: [], motoId: mp, allBookings: {}, appliedCodes: [], discountAmt: 0 };

  // Restore from sessionStorage
  try {
    var saved = sessionStorage.getItem('mg_rez_form');
    if(saved){
      var sd = JSON.parse(saved);
      if(sd.formData) MG._rez.formData = sd.formData;
      if(sd.bookingId) MG._rez.bookingId = sd.bookingId;
      if(sd.userId) MG._rez.userId = sd.userId;
      if(sd.bookingAmount) MG._rez.bookingAmount = sd.bookingAmount;
      if(sd._docNumber) MG._rez._docNumber = sd._docNumber;
      if(sd._licenseNumber) MG._rez._licenseNumber = sd._licenseNumber;
      if(sd._docsValidated) MG._rez._docsValidated = sd._docsValidated;
      if(sd._passwordSet) MG._rez._passwordSet = sd._passwordSet;
      if(!preStart && sd.startDate) MG._rez.startDate = sd.startDate;
      if(!preEnd && sd.endDate) MG._rez.endDate = sd.endDate;
      if(!mp && sd.motoId) MG._rez.motoId = sd.motoId;
      if(sd.appliedCodes) MG._rez.appliedCodes = sd.appliedCodes;
      if(sd.discountAmt) MG._rez.discountAmt = sd.discountAmt;
      if(sd.sizes) MG._rez.sizes = sd.sizes;
    }
  } catch(e){}
  if(!MG._rez.sizes) MG._rez.sizes = { rider:{}, passenger:{} };

  var motos = await MG.fetchMotos();
  MG._rez.motos = motos;
  MG._motosCache = motos;

  var sel = document.getElementById('rez-moto-select');
  if(sel){
    var h = '<form class="rez-moto-pick"><label for="rez-moto-dropdown">Konkrétní model nebo libovolná motorka</label>' +
      '<div class="rez-moto-pick-wrap"><select id="rez-moto-dropdown">' +
      '<option value="">libovolná dostupná motorka v mém termínu</option>';
    motos.forEach(function(m){ h += '<option value="'+m.id+'"'+(m.id===mp?' selected':'')+'>'+m.model+'</option>'; });
    h += '</select></div></form>';
    sel.innerHTML = h;
    document.getElementById('rez-moto-dropdown').addEventListener('change', function(){
      MG._rez.motoId = this.value;
      MG._rezResetDates();
      MG._rezLoadCalendar();
    });
  }
  MG._rezInitFormEvents();

  if(MG._rez.motoId && !mp){
    var dd = document.getElementById('rez-moto-dropdown');
    if(dd) dd.value = MG._rez.motoId;
  }

  await MG._rezLoadCalendar();

  if(MG._rez.startDate && MG._rez.endDate){
    MG._rezUpdateBanner();
    MG._rezUpdatePrice();
  }

  // Pre-fill form from session
  if(MG._rez.formData){
    var _f = function(id, v){ var e = document.getElementById(id); if(e && v) e.value = v; };
    var d = MG._rez.formData;
    _f('rez-name', d.name); _f('rez-email', d.email); _f('rez-phone', d.phone);
    _f('rez-street', d.street); _f('rez-city', d.city); _f('rez-zip', d.zip);
    _f('rez-country', d.country); _f('rez-pickup-time', d.pickupTime);
  }
  // Trigger pickup-time chip highlight (i pro defaultni 09:00 bez session dat)
  var ptInp0 = document.getElementById('rez-pickup-time');
  if(ptInp0 && ptInp0.value){ ptInp0.dispatchEvent(new Event('change',{bubbles:true})); }

  // Restore size chip UI
  if(typeof MG._rezRestoreSizesUI === 'function') MG._rezRestoreSizesUI();

  if(preDelivery){
    var dc = document.getElementById('rez-delivery');
    if(dc){ dc.checked = true; dc.dispatchEvent(new Event('change')); }
  }
};
