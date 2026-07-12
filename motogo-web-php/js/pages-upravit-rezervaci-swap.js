// ===== MotoGo24 — Upravit rezervaci: záložka "Výměna motorky" =====
// Přidává MG._editRez._renderTabSwap + _submitSwap a vlastní tlačítko záložky do tab baru.
// Výměna = od zvoleného DATA (a času) zákazník přejede na jinou motorku. Na pozadí to
// vytvoří DRUHOU navazující rezervaci na novou motorku (nová smlouva + kompletní mail),
// původní se zkrátí a odebrané dny se refundují po zaplacení druhé.
// Backend: RPC split_booking_moto_swap(p_booking_id, p_new_moto_id, p_swap_date, p_swap_time).
// Dostupnost nové motorky od data výměny do konce: MG.fetchMotoBookings(id) (RPC get_moto_booked_dates).
//
// POZOR: hlavní soubor js/pages-upravit-rezervaci.js je MINIFIKOVANÝ a NEUPRAVUJE se.
// Tab bar i dispatch tabů se staví v jádru (_renderDetail) — proto tuto záložku přidáváme
// bezpečně zvenčí: MutationObserverem hlídáme překreslení tab baru (#edit-rez-app .edit-rez-tabs)
// a doplňujeme do něj vlastní tlačítko "Výměna motorky", jehož klik vyrenderuje _renderTabSwap.
// Díky tomu není potřeba žádný zásah do minifikovaného jádra.
(function () {
  var ER = (window.MG && MG._editRez) ? MG._editRez : null;
  if (!ER) return;

  var TAB = 'swap';

  function esc(x) { return String(x == null ? '' : x).replace(/"/g, '&quot;'); }

  // ---- Obsah záložky ----
  ER._renderTabSwap = async function () {
    var b = ER.selectedBooking;
    var content = document.getElementById('edit-rez-tab-content');
    if (!b || !content) return;

    var origStart = ER._normIso(b.start_date);
    var origEnd = ER._normIso(b.end_date);
    var defTime = (b.pickup_time || '').toString().slice(0, 5) || '09:00';

    content.innerHTML =
      '<h3>' + MG.t('editRez.swap.title') + '</h3>' +
      '<p class="muted">' + MG.t('editRez.swap.help', { start: MG.formatDate(origStart), end: MG.formatDate(origEnd) }) + '</p>' +
      '<div class="erez-swap-controls" style="display:flex;flex-wrap:wrap;gap:16px;margin:12px 0">' +
        '<label style="display:flex;flex-direction:column;gap:4px;font-weight:600">' +
          '<span>' + MG.t('editRez.swap.pickDate') + '</span>' +
          '<input type="date" id="erez-swap-date" min="' + esc(origStart) + '" max="' + esc(origEnd) + '" value="' + esc(origStart) + '" style="padding:8px;border:1px solid #ccc;border-radius:8px">' +
        '</label>' +
        '<label style="display:flex;flex-direction:column;gap:4px;font-weight:600">' +
          '<span>' + MG.t('editRez.swap.pickTime') + '</span>' +
          '<input type="time" id="erez-swap-time" value="' + esc(defTime) + '" style="padding:8px;border:1px solid #ccc;border-radius:8px">' +
        '</label>' +
      '</div>' +
      '<p class="muted" style="font-size:.9em">' + MG.t('editRez.swap.priceNote') + '</p>' +
      '<h4 style="margin-top:16px">' + MG.t('editRez.swap.pickMoto') + '</h4>' +
      '<div id="erez-swap-motos" class="erez-moto-grid">' +
        '<div class="edit-rez-loading"><span class="spinner"></span> ' + MG.t('editRez.moto.loading') + '</div>' +
      '</div>';

    var dateInput = document.getElementById('erez-swap-date');
    dateInput.addEventListener('change', function () { renderMotos(); });

    async function renderMotos() {
      var grid = document.getElementById('erez-swap-motos');
      if (!grid) return;
      var swapDate = dateInput.value || origStart;
      if (swapDate < origStart) swapDate = origStart;
      if (swapDate > origEnd) swapDate = origEnd;
      grid.innerHTML = '<div class="edit-rez-loading"><span class="spinner"></span> ' + MG.t('editRez.moto.loading') + '</div>';

      try {
        var res = await Promise.all([
          window.sb.from('motorcycles')
            .select('id,model,brand,image_url,images,license_required,engine_cc,power_kw,year')
            .in('status', ['active', 'maintenance']).order('model'),
          window.sb.from('profiles').select('license_group').eq('id', ER.user.id).maybeSingle()
        ]);
        var motos = ((res[0] && res[0].data) || []).filter(function (m) { return m.id !== b.moto_id; });
        var lic = (res[1] && res[1].data && res[1].data.license_group) || [];

        if (!motos.length) { grid.innerHTML = '<p class="muted">' + MG.t('editRez.swap.noOptions') + '</p>'; return; }

        var withOcc = await Promise.all(motos.map(function (m) {
          return MG.fetchMotoBookings(m.id).then(function (occ) {
            return {
              moto: m,
              occupied: (occ || []).map(function (o) {
                return { start_date: ER._normIso(o.start_date), end_date: ER._normIso(o.end_date), status: o.status };
              })
            };
          });
        }));

        grid.innerHTML = withOcc.map(function (x) {
          var m = x.moto;
          var allowed = ER._licenseAllows(lic, m.license_required);
          // Dostupnost nové motorky POUZE od data výměny do konce rezervace.
          var free = !ER._rangeOverlapsOccupied(swapDate, origEnd, x.occupied);
          var disabled = !allowed || !free;

          var img = (m.images && m.images.length ? m.images[0] : m.image_url) || '';
          var src = (typeof MG.imgUrl === 'function') ? MG.imgUrl(img) : img;
          var hero = src
            ? '<img class="erez-moto-hero-img" src="' + esc(src) + '" alt="" loading="lazy">'
            : '<div class="erez-moto-hero-placeholder">🏍️</div>';

          var brand = (m.brand || '').trim(), model = (m.model || '').trim();
          var name = brand && 0 !== model.toLowerCase().indexOf(brand.toLowerCase()) ? brand + ' ' + model : (model || brand);

          var pill = m.license_required && 'N' !== m.license_required
            ? '<span class="erez-moto-pill">' + MG.t('editRez.moto.licPill', { lic: m.license_required }) + '</span>'
            : '<span class="erez-moto-pill alt">' + MG.t('editRez.moto.noLicPill') + '</span>';

          var specs = [];
          if (m.engine_cc) specs.push(m.engine_cc + ' cm³');
          if (m.power_kw) specs.push(m.power_kw + ' kW');
          if (m.year) specs.push(m.year);
          var specsHtml = specs.length ? '<div class="erez-moto-specs">' + specs.join(' · ') + '</div>' : '';

          var reasons = [];
          if (!allowed) reasons.push(MG.t('editRez.moto.reasonLicense'));
          if (!free) reasons.push(MG.t('editRez.moto.reasonOccupied'));
          var reasonsHtml = reasons.length ? '<div class="erez-moto-reasons">' + reasons.join(' · ') + '</div>' : '';

          var cta = disabled
            ? '<button type="button" class="erez-moto-cta disabled" disabled>' + MG.t('editRez.moto.unavailable') + '</button>'
            : '<button type="button" class="erez-moto-cta" data-id="' + esc(m.id) + '" data-name="' + esc(name) + '">' + MG.t('editRez.swap.confirm') + '</button>';

          return '<article class="erez-moto-card' + (disabled ? ' is-disabled' : '') + '">' +
            '<div class="erez-moto-hero">' + hero + pill + '</div>' +
            '<div class="erez-moto-meta"><h4>' + name + '</h4>' + specsHtml + reasonsHtml + cta + '</div>' +
            '</article>';
        }).join('');

        grid.querySelectorAll('.erez-moto-cta:not(.disabled)').forEach(function (btn) {
          btn.addEventListener('click', function () {
            var id = btn.getAttribute('data-id');
            var nm = btn.getAttribute('data-name');
            var timeVal = (document.getElementById('erez-swap-time') || {}).value || defTime;
            ER._confirmDialog(
              MG.t('editRez.moto.confirmTitle', { name: nm }),
              function () { ER._submitSwap(id, swapDate, timeVal); },
              { yesLabel: MG.t('editRez.moto.confirmYes'), noLabel: MG.t('editRez.moto.confirmNo') }
            );
          });
        });
      } catch (e) {
        console.error('[editRez] renderTabSwap err', e);
        grid.innerHTML = '<div class="edit-rez-error">' + MG.t('editRez.err.generic') + '</div>';
      }
    }

    renderMotos();
  };

  // ---- Odeslání výměny ----
  ER._submitSwap = async function (newMotoId, swapDate, swapTime) {
    if (ER.busy) return;
    var b = ER.selectedBooking;
    ER._setBusy(true);
    try {
      // Split: vytvoří DRUHOU (nezaplacenou) rezervaci na novou motorku od data výměny.
      // Původní se zkrátí + refunduje AŽ po zaplacení té druhé (backend trigger).
      var payload = { p_booking_id: b.id, p_new_moto_id: newMotoId, p_swap_date: swapDate };
      if (swapTime) payload.p_swap_time = swapTime;
      var res = await window.sb.rpc('split_booking_moto_swap', payload);

      if (res.error || !res.data || res.data.success === false) {
        var code = (res.data && res.data.error) || (res.error && (res.error.message || res.error.code)) || '';
        console.error('[editRez] swap failed', { sent: payload, code: code, error: res.error, data: res.data });
        var map = {
          not_found: 'editRez.err.notFound',
          forbidden: 'editRez.err.generic',
          wrong_status: 'editRez.err.wrongStatus',
          not_paid: 'editRez.err.notPaid',
          invalid_new_moto: 'editRez.swap.err.unavailable',
          new_moto_unavailable: 'editRez.swap.err.unavailable',
          swap_date_out_of_range: 'editRez.swap.err.dateRange',
          already_split: 'editRez.swap.err.dateRange'
        };
        var key = map[code];
        ER._showError(key ? MG.t(key) : (code || MG.t('editRez.err.generic')));
        return;
      }

      // Druhou rezervaci je potřeba zaplatit → přesměruj na platební krok (resume).
      var nb = res.data.new_booking_id;
      if (res.data.payment_required && nb) {
        window.location.href = '/rezervace?resume=' + encodeURIComponent(nb);
        return;
      }

      var msg = MG.t('editRez.swap.success', { date: MG.formatDate(swapDate) });
      var content = document.getElementById('edit-rez-tab-content');
      if (content) {
        content.innerHTML = '<div class="edit-rez-success-box"><h3>✓</h3><p>' + msg + '</p>' +
          '<button type="button" class="btn btngreen-small" id="edit-rez-swap-back">' + MG.t('editRez.list.title') + '</button></div>';
        var back = document.getElementById('edit-rez-swap-back');
        if (back) back.addEventListener('click', async function () {
          ER.selectedBooking = null;
          await ER._loadBookings();
          ER._goto('list');
        });
      }
    } catch (e) {
      console.error('[editRez] swap exception', e);
      ER._showError(MG.t('editRez.err.generic'));
    } finally {
      ER._setBusy(false);
    }
  };

  // ---- Vložení záložky do tab baru (bez zásahu do minifikovaného jádra) ----
  // Výměna má smysl u nadcházející, zaplacené rezervace (reserved + paid) — stejná podmínka
  // jako záložka "Výměna/Změna motorky" v jádru; backend vrací wrong_status / not_paid jinak.
  function shouldShow() {
    var b = ER.selectedBooking;
    // Výměna dává smysl u nadcházející i PROBÍHAJÍCÍ rezervace (switch uprostřed), zaplacené.
    return !!b && (b.status === 'reserved' || b.status === 'active') &&
      (b.payment_status === 'paid' || b.payment_status === 'partial_refund' || b.payment_status === 'refund_pending');
  }

  function injectTab() {
    if (!shouldShow()) return;
    var nav = document.querySelector('#edit-rez-app .edit-rez-tabs');
    if (!nav) return;
    if (nav.querySelector('.edit-rez-tab[data-tab="' + TAB + '"]')) return; // už tam je

    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'edit-rez-tab' + (ER.tab === TAB ? ' active' : '');
    btn.setAttribute('data-tab', TAB);
    btn.textContent = MG.t('editRez.swap.tab');

    // Umístění „uprostřed" — hned za záložku výměny motorky (moto), jinak na konec.
    var motoBtn = nav.querySelector('.edit-rez-tab[data-tab="moto"]');
    if (motoBtn) nav.insertBefore(btn, motoBtn.nextSibling);
    else nav.appendChild(btn);

    btn.addEventListener('click', function () {
      ER.tab = TAB;
      nav.querySelectorAll('.edit-rez-tab').forEach(function (t) { t.classList.remove('active'); });
      btn.classList.add('active');
      ER._renderTabSwap();
    });
  }

  function startObserver() {
    var app = document.getElementById('edit-rez-app');
    if (!app) { setTimeout(startObserver, 200); return; }
    var obs = new MutationObserver(function () { injectTab(); });
    obs.observe(app, { childList: true, subtree: true });
    injectTab();
  }

  startObserver();
})();
