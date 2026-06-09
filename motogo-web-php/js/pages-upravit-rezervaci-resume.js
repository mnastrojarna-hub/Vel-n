// ===== MotoGo24 — Upravit rezervaci: návrat z platební brány (Stripe „Zpět") =====
// Když zákazník na platební bráně klikne „Zpět na motogo24", Stripe cancel_url ho
// dřív poslal na holé /upravit-rezervaci → appka spadla zpět na SEZNAM rezervací a
// všechny rozpracované úpravy (datumy prodloužení, výbava, motorka, místo) zmizely.
//
// Nově cancel_url nese ?edit_booking=<id>&edit_tab=<tab> a před odchodem na bránu si
// uložíme „resume" snapshot rozpracovaného formuláře. Po návratu se vrátíme PŘÍMO na
// konkrétní záložku úpravy a formulář se předvyplní tím, co měl zákazník rozpracované
// (prodloužení = nové datumy, výbava = vybrané velikosti/doplňky).
(function () {
  var ER = (window.MG && MG._editRez) ? MG._editRez : null;
  if (!ER) return;

  var KEY = 'editRez_resume';
  var MAX_AGE = 60 * 60 * 1000; // 1 h — starší rozpracovaný stav už neobnovujeme

  // Uloží rozpracovaný stav formuláře těsně před odchodem na Stripe checkout.
  // tab = která záložka úpravy ('extend' | 'gear' | 'moto' | 'location'),
  // ui  = data potřebná k předvyplnění formuláře po návratu.
  ER._saveResume = function (tab, ui) {
    try {
      var b = ER.selectedBooking;
      if (!b) return;
      localStorage.setItem(KEY, JSON.stringify({ id: b.id, tab: tab, ui: ui || null, ts: Date.now() }));
    } catch (e) {}
  };

  ER._readResume = function (id) {
    try {
      var raw = localStorage.getItem(KEY);
      if (!raw) return null;
      var r = JSON.parse(raw);
      if (!r || (id && r.id !== id)) return null;
      if (r.ts && (Date.now() - r.ts) > MAX_AGE) { ER._clearResume(); return null; }
      return r;
    } catch (e) { return null; }
  };

  ER._clearResume = function () { try { localStorage.removeItem(KEY); } catch (e) {} };

  // Návrat z brány (volá _editRezInit při ?edit_booking=… v URL): najdi rezervaci,
  // otevři správnou záložku a předvyplň formulář rozpracovaným stavem.
  ER._resumeEdit = async function (id, tab) {
    try { await ER._loadBookings(); } catch (e) {}
    var r = (ER.bookings || []).find(function (b) { return b.id === id; });
    if (!r) { ER._goto('list'); return; }
    ER.selectedBooking = r;
    ER.selectedMoto = r.motorcycles || null;
    var res = ER._readResume(id);
    var t = tab || (res && res.tab) || 'detail';
    ER.tab = t;
    // _resumeUi / _resumeUiTab čtou jednorázově render funkce konkrétních záložek
    // (_renderTabExtend, _renderTabGear) a po předvyplnění je vynulují.
    if (res && res.tab === t && res.ui) {
      ER._resumeUi = res.ui;
      ER._resumeUiTab = t;
    }
    ER._clearResume();
    ER._goto('detail');
  };

  // --- Předvyplnění záložky „Místo vyzvednutí/vrácení" -----------------------
  // Záložku „Místo" nevyplňujeme úpravou render funkce (je provázaná s výpočtem
  // ceny), ale až PO vykreslení nastavíme hodnoty do formuláře a vyvoláme stejné
  // eventy, jaké spouští sám zákazník (change/input) → formulář se dopočítá sám.
  if (ER._renderTabLocation) {
    var _origLoc = ER._renderTabLocation;
    ER._renderTabLocation = function () {
      var ui = (ER._resumeUiTab === 'location' && ER._resumeUi) ? ER._resumeUi : null;
      ER._resumeUiTab = null; ER._resumeUi = null;
      var out = _origLoc.apply(this, arguments);
      if (ui) setTimeout(function () { ER._applyLocationResume(ui); }, 0);
      return out;
    };

    ER._applyLocationResume = function (ui) {
      var form = document.getElementById('edit-rez-loc-form');
      if (!form || !ui) return;
      function fire(el, type) { try { el.dispatchEvent(new Event(type, { bubbles: true })); } catch (e) {} }
      function setRadio(name, val) {
        var ctrl = form[name];
        if (!val || !ctrl) return;
        var radios = (typeof ctrl.length === 'number') ? Array.prototype.slice.call(ctrl) : [ctrl];
        radios.forEach(function (rd) { if (rd && rd.value === val) { rd.checked = true; fire(rd, 'change'); } });
      }
      function setVal(name, val, evt) {
        var f = form[name];
        if (!f || val == null || val === '') return;
        f.value = val;
        if (evt) fire(f, evt);
      }
      // Pořadí: nejdřív způsob (zobrazí panel s adresou) a souřadnice, pak adresa.
      setRadio('pickup', ui.p_new_pickup_method);
      setRadio('returnM', ui.p_new_return_method);
      setVal('pickupLat', ui.p_new_pickup_lat);
      setVal('pickupLng', ui.p_new_pickup_lng);
      setVal('returnLat', ui.p_new_return_lat);
      setVal('returnLng', ui.p_new_return_lng);
      setVal('pickupAddr', ui.p_new_pickup_address, 'input');
      setVal('returnAddr', ui.p_new_return_address, 'input');
      var tu = ui._time_update || {};
      setVal('pickupTime', tu.pickup_time, 'change');
      setVal('returnTime', tu.return_time, 'change');
    };
  }
})();
