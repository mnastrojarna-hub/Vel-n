// ===== MotoGo24 Web — Stránka Rezervace =====
// Kompletní booking formulář napojený na Supabase

var MG = window.MG || {};
window.MG = MG;

MG.route('/rezervace', async function(app, params){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},'REZERVACE']);

  // Get pre-selected moto from URL
  var hash = window.location.hash || '';
  var motoParam = '';
  var motoMatch = hash.match(/[?&]moto=([^&]+)/);
  if(motoMatch) motoParam = decodeURIComponent(motoMatch[1]);

  app.innerHTML = '<main id="content"><section class="container">' + bc +
    '<div class="pcontent">' +
    '<h1>Rezervace motorky</h1>' +
    '<h3>Jak rezervace funguje?</h3><p>&nbsp;</p>' +
    '<p>Pokud si chcete <strong>půjčit motorku v konkrétním termínu</strong>, vyberte „libovolná dostupná motorka" a v kalendáři termín vyznačte.</p><p>&nbsp;</p>' +
    '<p>V případě, že si chcete <strong>vyzkoušet konkrétní motorku</strong>, vyberte ji ze seznamu a v kalendáři se vám zobrazí dostupné termíny.</p><p>&nbsp;</p>' +
    '<p><strong>Půjčujeme bez kauce. Základní výbavu pro řidiče poskytujeme zdarma.</strong></p><p>&nbsp;</p>' +

    '<div id="rez-moto-select"></div>' +
    '<div id="rez-calendar"></div>' +
    '<div id="rez-form" style="display:none">' +
    MG._rezFormHtml() +
    '</div>' +
    '</div></section></main>';

  // Load motos for select
  var motos = await MG._getMotos();
  var selectEl = document.getElementById('rez-moto-select');
  if(selectEl){
    var html = '<form class="form-product-select gr2"><div>Vyber motorku:</div>' +
      '<select id="rez-moto-dropdown">' +
      '<option value="">libovolná dostupná motorka v mém termínu</option>';
    motos.forEach(function(m){
      html += '<option value="' + m.id + '"' + (m.id === motoParam ? ' selected' : '') + '>' + m.model + '</option>';
    });
    html += '</select></form>';
    selectEl.innerHTML = html;

    document.getElementById('rez-moto-dropdown').addEventListener('change', function(){
      var motoId = this.value;
      MG._loadRezCalendar(motoId, motos);
    });
  }

  // Load calendar for selected or all
  MG._loadRezCalendar(motoParam, motos);
});

MG._loadRezCalendar = async function(motoId, motos){
  var calEl = document.getElementById('rez-calendar');
  if(!calEl) return;

  if(motoId){
    // Show calendar for specific moto
    calEl.innerHTML = MG.renderCalendar('rez-cal-' + motoId, motoId);

    // Show available bikes listing
    var formEl = document.getElementById('rez-form');
    if(formEl) formEl.style.display = 'block';

    var moto = motos.find(function(m){ return m.id === motoId; });
    if(moto){
      var prodName = document.getElementById('rez-product-name');
      if(prodName) prodName.textContent = 'Produkt: ' + moto.model;
    }
  } else {
    // Show combined calendar placeholder
    calEl.innerHTML = '<div id="rez-cal-all"></div>' +
      '<div class="calendar-icons gr3"><div><span class="cicon loosely">&nbsp;</span> Volné</div><div><span class="cicon occupied">&nbsp;</span> Obsazené</div><div><span class="cicon unconfirmed">&nbsp;</span> Nepotvrzené</div></div>';

    // Build combined calendar (no specific moto)
    var allCalEl = document.getElementById('rez-cal-all');
    if(allCalEl){
      var now = new Date();
      var state = {year: now.getFullYear(), month: now.getMonth(), bookedDays: {}};
      MG._calState['rez-cal-all'] = state;
      MG._renderCalMonth('rez-cal-all');
    }

    var formEl = document.getElementById('rez-form');
    if(formEl) formEl.style.display = 'block';
    var prodName = document.getElementById('rez-product-name');
    if(prodName) prodName.textContent = 'Produkt: Libovolná dostupná motorka';
  }
};

MG._rezFormHtml = function(){
  return '<p>&nbsp;</p>' +
    '<input type="text" id="rez-name" placeholder="* Jméno a příjmení" required>' +
    '<div class="gr2">' +
    '<input type="text" id="rez-street" placeholder="* Ulice, č.p." required>' +
    '<input type="text" id="rez-zip" placeholder="* PSČ" required></div>' +
    '<div class="gr2">' +
    '<input type="text" id="rez-city" placeholder="* Město" required>' +
    '<input type="text" id="rez-country" placeholder="* Stát" value="Česká republika" required></div>' +
    '<div class="gr2">' +
    '<input type="email" id="rez-email" placeholder="* E-mail" required>' +
    '<input type="tel" id="rez-phone" placeholder="* Telefon (+420XXXXXXXXX)" required pattern="^\\+\\d{12,15}$"></div>' +
    '<div class="gr2 voucher-code">' +
    '<input type="text" id="rez-voucher" placeholder="Slevový kód" maxlength="255">' +
    '<div><span class="btn btngreen-small" onclick="MG._addVoucherField()">DALŠÍ KÓD</span></div></div>' +
    '<div id="rez-extra-vouchers"></div>' +
    '<div class="dfc pickup"><div>Čas převzetí motorky</div>' +
    '<input type="time" id="rez-pickup-time"></div>' +

    '<div class="checkboxes">' +
    '<div><input type="checkbox" id="rez-delivery"><label for="rez-delivery">Přistavení motorky jinam než na adresu motopůjčovny</label></div>' +
    '<div id="rez-delivery-panel" style="display:none"><input type="text" id="rez-delivery-address" placeholder="Adresa přistavení"></div>' +

    '<div><input type="checkbox" id="rez-eq-passenger"><label for="rez-eq-passenger">Základní výbava spolujezdce - 690,- Kč</label></div>' +
    '<div><input type="checkbox" id="rez-eq-boots-rider"><label for="rez-eq-boots-rider">Zapůjčení bot pro řidiče - 290,- Kč</label></div>' +
    '<div><input type="checkbox" id="rez-eq-boots-passenger"><label for="rez-eq-boots-passenger">Zapůjčení bot pro spolujezdce - 290,- Kč</label></div>' +
    '</div>' +

    '<textarea id="rez-note" placeholder="Poznámka (velikosti výbavy apod.)"></textarea>' +
    '<div id="rez-product-name" class="form-product-name">Produkt: Libovolná dostupná motorka</div>' +

    '<div class="checkboxes">' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-vop" required><div>* Souhlasím s <a href="#/obchodni-podminky">obchodními podmínkami</a></div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-gdpr"><div>Souhlasím se <a href="#/gdpr">zpracováním osobních údajů</a></div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-marketing"><div>Souhlasím se zasíláním marketingových sdělení</div></div>' +
    '<div class="agreement gr2"><input type="checkbox" id="rez-agree-photo"><div>Souhlasím s využitím fotografií pro marketingové účely</div></div>' +
    '</div>' +

    '<div class="dfcs"><div><div id="rez-price-preview"></div></div>' +
    '<div><div class="text-right"><button class="btn btngreen" onclick="MG._submitReservation()">Pokračovat v rezervaci</button></div></div></div>';
};

MG._addVoucherField = function(){
  var container = document.getElementById('rez-extra-vouchers');
  if(!container) return;
  var div = document.createElement('div');
  div.className = 'gr2 voucher-code';
  div.innerHTML = '<input type="text" placeholder="Slevový kód" maxlength="255">';
  container.appendChild(div);
};

MG._submitReservation = function(){
  // Validate required fields
  var name = document.getElementById('rez-name');
  var email = document.getElementById('rez-email');
  var phone = document.getElementById('rez-phone');
  var agree = document.getElementById('rez-agree-vop');

  if(!name.value || !email.value || !phone.value){
    alert('Vyplňte prosím všechna povinná pole.');
    return;
  }
  if(!agree.checked){
    alert('Pro pokračování musíte souhlasit s obchodními podmínkami.');
    return;
  }

  // In production this would create a booking via Supabase
  alert('Děkujeme za rezervaci! Tato funkce bude brzy plně propojená s rezervačním systémem.\n\nPro rezervaci nás prosím kontaktujte na ' + MG.PHONE + ' nebo ' + MG.EMAIL_USER + '@' + MG.EMAIL_DOMAIN);
};

// Delivery checkbox toggle
document.addEventListener('change', function(e){
  if(e.target && e.target.id === 'rez-delivery'){
    var panel = document.getElementById('rez-delivery-panel');
    if(panel) panel.style.display = e.target.checked ? 'block' : 'none';
  }
});
