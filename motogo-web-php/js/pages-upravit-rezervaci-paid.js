/* ===== MotoGo24 — Upravit rezervaci: výsledek zaplacené změny po návratu ze Stripe =====
 * Odpověď majitele 2026-10-16 (otázka 3): když zaplacenou výměnu (úpravu) nejde zapsat, protože
 * motorku mezitím obsadila jiná rezervace, má nová rezervace přednost — zákazník uvidí „Motorka je
 * mezitím obsazená", že původní rezervace platí beze změny, že se doplatek vrací automaticky,
 * a co dál (vybrat jinou motorku / ponechat současnou). Bez kontaktů (D5).
 * Výsledek říká SERVER: process-payment {action:'complete_extension', session_id} — session_id
 * dosadí Stripe do success_url (swap.js a gear.js ho posílají, k ostatním webovým úpravám ho
 * přidá process-payment). Server změnu zapíše (idempotentně, stejně jako webhook), nebo řekne,
 * proč ne; vratku i upozornění obsluhy (debug_log + e-mail) už vyřídil sám.
 * Klientský zápis (swap.js / gear.js / jádro) zůstává jen jako záloha: změna se nevešla do
 * metadat (state client_apply) nebo server akci ještě nezná (starší nasazení). Když ani záloha
 * výsledek nezná, ukáže se „platba proběhla, změnu dokončujeme" — nikdy chyba s kontaktem.
 * Načítá se ZA swap.js a gear.js → obaluje jejich _applyPendingAfterPayment. Nejvíc venku je
 * guard.js (načtený až po resume.js): klientský dopis času vyzvednutí a late slevy dělá jen tehdy,
 * když výsledek NEŘEKL server — ER._paidOutcome (selhání / obsazeno / nezaplaceno / dokončujeme)
 * a ER._paidByServer (zapsal server) proto nastavujeme při každém volání znovu.
 */
(function () {
  var MG = window.MG;
  var ER = (MG && MG._editRez) ? MG._editRez : null;
  if (!ER) return;

  var TAKEN = { new_moto_unavailable: 1, moto_unavailable: 1 };
  var SWAP_KEY = 'editRez_swap_pending_';
  var POLL = 20;          // max. pokusů (~40 s), dokud server hlásí pending / retry
  var POLL_MS = 2000;

  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  function t(k, p) { return MG.t(k, p); }
  function price(n) { return n == null || !isFinite(Number(n)) ? '' : (MG.formatPrice ? MG.formatPrice(Number(n)) : Math.round(n) + ' Kč'); }

  /** Id Checkout Session z návratové adresy (doslovný zástupný text Stripe se ignoruje). */
  function sessionIdFromUrl() {
    try {
      var s = new URL(window.location.href).searchParams.get('session_id') || '';
      return /^cs_[A-Za-z0-9_]+$/.test(s) ? s : null;
    } catch (e) { return null; }
  }

  /** Dotaz na server: {state, reason, refund, amount…} | null (akci nezná / nečitelná odpověď). */
  async function askServer(sessionId) {
    var sd = await window.sb.auth.getSession();
    var tok = sd && sd.data && sd.data.session && sd.data.session.access_token;
    if (!tok) return null;
    var res = await fetch(window.MOTOGO_CONFIG.SUPABASE_URL + '/functions/v1/process-payment', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + tok, apikey: window.MOTOGO_CONFIG.SUPABASE_ANON_KEY },
      body: JSON.stringify({ action: 'complete_extension', session_id: sessionId })
    });
    var j = await res.json().catch(function () { return null; });
    if (j && typeof j.state === 'string') return j;
    return res.status === 503 ? { state: 'retry' } : null;
  }

  function swapPending(id) {
    try { var raw = localStorage.getItem(SWAP_KEY + id); return raw ? (JSON.parse(raw) || {}) : null; } catch (e) { return null; }
  }
  function clearPending(id) {
    try { localStorage.removeItem(SWAP_KEY + id); } catch (e) { /* noop */ }
    try { localStorage.removeItem('editRez_pending_' + id); } catch (e) { /* noop */ }
  }

  ER._paidOutcome = null;
  ER._paidByServer = false;
  var inner = ER._applyPendingAfterPayment;
  ER._applyPendingAfterPayment = async function (id) {
    ER._paidOutcome = null;
    ER._paidByServer = false;
    var sid = sessionIdFromUrl();
    var sw = swapPending(id);
    if (sid) {
      var r = null;
      for (var i = 0; i < POLL; i++) {
        try { r = await askServer(sid); } catch (e) { r = null; }
        if (!r || (r.state !== 'pending' && r.state !== 'retry')) break;
        await sleep(POLL_MS);
      }
      // Výměna bez dorovnání, kterou server ani po ~40 s nezapsal (retry — např. před nasazením
      // SQL 20261016p3 ji smí zapsat jen webhook): záloha = klientský zápis jako dřív (RPC je
      // idempotentní; obsazenou motorku vyhodnotí a doplatek vrátí webhook).
      var swapFallback = r && r.state === 'retry' && sw && sw.base && !sw.r;
      if (r && r.state !== 'client_apply' && !swapFallback) {
        if (r.state === 'applied' || r.state === 'already_applied') {
          // Čas vyzvednutí i late slevu zapsal server (extension-apply) — guard.js je nepřepisuje.
          ER._paidByServer = true;
          // „K vyzvednutí" po výměně = pobočka NOVÉ motorky (stejně jako swap.js).
          if (sw && sw.base && sw.base.p_new_moto_id) ER._lastSwapMoto = sw.base.p_new_moto_id;
          clearPending(id);
          return true;
        }
        clearPending(id); // změnu zapisuje / vyhodnotil server — klient ji už nezapisuje
        if (r.state === 'failed') {
          ER._paidOutcome = { kind: TAKEN[r.reason] ? 'taken' : 'failed', staff: r.refund === 'staff', amount: r.amount, swap: !!sw, id: id };
        } else if (r.state === 'not_paid') {
          ER._paidOutcome = { kind: 'notPaid', id: id };
        } else {
          ER._paidOutcome = { kind: 'finishing', id: id }; // pending / retry i po ~40 s
        }
        return true;
      }
    }
    var ok = false;
    try { ok = inner ? await inner.apply(this, arguments) : false; } catch (e) { ok = false; }
    if (!ok) {
      // Výsledek neznámý (klientský zápis neprošel) — změnu dopíše / vyhodnotí server sám
      // (webhook): žádná chyba s kontaktem, jen „platba proběhla, dokončujeme".
      ER._paidOutcome = { kind: 'finishing', id: id };
      return true;
    }
    return ok;
  };

  function button(label, cls, onClick) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = cls;
    b.textContent = label;
    b.addEventListener('click', onClick);
    return b;
  }

  function renderOutcome(o) {
    var c = document.getElementById('edit-rez-content');
    if (!c) return;
    var old = document.getElementById('edit-rez-paid-outcome');
    if (old && old.parentNode) old.parentNode.removeChild(old);
    var sec = document.createElement('section');
    sec.className = 'edit-rez-card';
    sec.id = 'edit-rez-paid-outcome';
    sec.setAttribute('role', 'status');
    var amount = price(o.amount);
    var title = '', body = '';
    if (o.kind === 'taken') {
      title = t('editRez.paid.takenTitle');
      body = t(o.staff ? 'editRez.paid.takenBodyStaff' : 'editRez.paid.takenBody', { amount: amount });
    } else if (o.kind === 'failed') {
      title = t('editRez.paid.failedTitle');
      body = t(o.staff ? 'editRez.paid.failedBodyStaff' : 'editRez.paid.failedBody', { amount: amount });
    } else if (o.kind === 'notPaid') {
      body = t('editRez.paid.notPaid');
    } else {
      body = t('editRez.postStripe.finishing');
    }
    if (title) {
      var h = document.createElement('h3');
      h.textContent = title;
      sec.appendChild(h);
    }
    var p = document.createElement('p');
    p.textContent = body;
    sec.appendChild(p);
    var row = document.createElement('div');
    row.style.cssText = 'display:flex;flex-wrap:wrap;gap:8px;margin-top:8px';
    function close() { if (sec.parentNode) sec.parentNode.removeChild(sec); }
    if (o.kind === 'taken' && o.swap && o.id) {
      row.appendChild(button(t('editRez.paid.pickOther'), 'btn btngreen-small', async function () {
        close();
        if (ER._resumeEdit) await ER._resumeEdit(o.id, 'swap');
        // jádro záložku „Výměna" nezná — otevře ji tlačítko vložené swap.js
        setTimeout(function () {
          var b = document.querySelector('#edit-rez-app .edit-rez-tab[data-tab="swap"]');
          if (b) b.click();
          else if (ER._renderTabSwap) { ER.tab = 'swap'; ER._renderTabSwap(); }
        }, 80);
      }));
      row.appendChild(button(t('editRez.paid.keepCurrent'), 'btn btndark', close));
    } else if (o.kind !== 'finishing') {
      row.appendChild(button(t('editRez.paid.close'), 'btn btndark', close));
    }
    if (row.childNodes.length) sec.appendChild(row);
    c.insertBefore(sec, c.firstChild);
    try { sec.scrollIntoView({ behavior: 'smooth', block: 'start' }); } catch (e) { /* noop */ }
  }

  var innerPickup = ER._paidPickup;
  ER._paidPickup = function () {
    var o = ER._paidOutcome;
    ER._paidOutcome = null;
    if (!o) return innerPickup ? innerPickup.apply(this, arguments) : undefined;
    renderOutcome(o);
  };

  // ── D1 na webu (odpověď majitele 2026-10-16, otázka 2): věta o minimální platbě kartou
  // u doplatků v jádru (prodloužení, místo, změna motorky) — jádro volá ER._cardNote(částka).
  ER._cardNote = function (due, compact) {
    var s = MG.cardNoteEdit ? MG.cardNoteEdit(due, compact) : '';
    if (!s) return '';
    var span = document.createElement('span');
    span.className = 'erez-card-note';
    span.textContent = s;
    return span.outerHTML;
  };

  // Test hook (node): výběr výsledku bez DOM.
  ER._paidTest = { sessionIdFromUrl: sessionIdFromUrl, renderOutcome: renderOutcome };
})();
