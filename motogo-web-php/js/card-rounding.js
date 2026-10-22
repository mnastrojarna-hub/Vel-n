/* ===== MotoGo24 — minimální platba kartou na webu (D1/D2) =====
 * Odpověď majitele 2026-10-16 („ano i web"): stejné pravidlo jako appka a server
 * (process-payment/card-minimum.ts): částka do 1 Kč se neúčtuje, 1–15 Kč se platí kartou
 * 15 Kč a dorovnání je na dokladu samostatný řádek. Stripe stránka dorovnání ukazuje sama;
 * tady ho zákazník vidí UŽ na našich stránkách (rezervace, pokladna e-shopu, úprava rezervace).
 * Zobrazuje se, jen když server dorovnání opravdu umí (SQL 20261016p1 nasazené — sloupec
 * bookings.card_rounding; detekce jedním dotazem, do té doby se nic nemění).
 * Samostatný soubor — minifikované moduly (pages-rezervace-*.js, checkout.js, jádro úprav)
 * se nemění; háčky níže čtou jen jejich stav (MG._rez._grandTotal) a DOM.
 */
(function () {
  var MG = window.MG = window.MG || {};
  var MIN = 15;
  function r2(n) { return Math.round((Number(n) || 0) * 100) / 100; }
  function t(k, p) {
    if (typeof MG.t === 'function') return MG.t(k, p);
    var s = (window.MG_I18N || {})[k] || k;
    if (p) Object.keys(p).forEach(function (x) { s = s.split('{' + x + '}').join(String(p[x])); });
    return s;
  }
  /** Částka dorovnání / platby kartou VŽDY přesně v Kč (Stripe účtuje v CZK; zobrazovací měna webu
   *  by zaokrouhlila 7,50 → 8 a z 14,60 udělala dorovnání „0 Kč"): celé Kč bez desetin, jinak „7,50 Kč". */
  function fp(n) {
    var v = Math.round((Number(n) || 0) * 100) / 100;
    var whole = Math.abs(v - Math.round(v)) < 0.005;
    var parts = (whole ? String(Math.round(v)) : v.toFixed(2)).split('.');
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
    return parts.join(',') + ' Kč';
  }
  /** Původní částka u tlačítka „Zaplatit" (v zobrazovací měně jako jádro rezervace). */
  function fpDisplay(n) {
    if (typeof MG.formatPrice === 'function') { var s = MG.formatPrice(n); if (s) return s; }
    return fp(n);
  }
  function esc(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }

  MG.CARD_MIN = MIN;
  /** Pravidlo serveru: ≤ 0 nic, ≤ 1 odpustit, 1–15 zaplatit 15 (dorovnání +x), ≥ 15 beze změny. */
  MG.cardCharge = function (due) {
    var d = r2(due);
    if (!(d > 0)) return { kind: 'free', due: d, charge: 0, rounding: 0 };
    if (d <= 1) return { kind: 'waive', due: d, charge: 0, rounding: r2(-d) };
    if (d < MIN) return { kind: 'round', due: d, charge: MIN, rounding: r2(MIN - d) };
    return { kind: 'ok', due: d, charge: d, rounding: 0 };
  };

  // ── Je dorovnání na serveru nasazené? (sloupec card_rounding; RLS řádky skryje, chybu ne) ──
  var livePromise = null, liveVal = false;
  MG.cardRoundingLive = function () {
    if (livePromise) return livePromise;
    livePromise = new Promise(function (resolve) {
      var tries = 0;
      (function go() {
        if (!window.sb || typeof window.sb.from !== 'function') {
          if (tries++ < 50) { setTimeout(go, 200); return; }
          resolve(false); return;
        }
        try {
          window.sb.from('bookings').select('card_rounding').limit(1).then(function (r) {
            liveVal = !!(r && !r.error); resolve(liveVal); refreshAll();
          }, function () { resolve(false); });
        } catch (e) { resolve(false); }
      })();
    });
    return livePromise;
  };
  MG.cardRoundingIsLive = function () { return liveVal; };

  /** Úprava rezervace: věta k doplatku (prázdná, když se nic nemění / dorovnání není nasazené). */
  MG.cardNoteEdit = function (due, compact) {
    if (!liveVal) return '';
    var c = MG.cardCharge(due);
    if (c.kind === 'round') {
      return compact ? t('editRez.card.roundShort', { charge: fp(c.charge) })
        : t('editRez.card.round', { amount: fp(c.due), charge: fp(c.charge), rounding: fp(c.rounding) });
    }
    if (c.kind === 'waive') return compact ? t('editRez.card.waiveShort') : t('editRez.card.waive', { amount: fp(c.due) });
    return '';
  };

  /** Rezervace / e-shop: řádky pod celkovou částkou (HTML) nebo ''. kind: 'rez' | 'shop'. */
  MG.cardNoteLines = function (due, kind) {
    if (!liveVal) return '';
    var c = MG.cardCharge(due);
    if (c.kind === 'round') {
      return '<div class="mg-card-round-line">' + esc(t('pay.card.round', { rounding: fp(c.rounding) })) + '</div>'
        + '<div class="mg-card-round-note">' + esc(t('pay.card.roundNote', { charge: fp(c.charge) })) + '</div>';
    }
    if (c.kind === 'waive') return '<div class="mg-card-round-note">' + esc(t(kind === 'shop' ? 'shop.card.waive' : 'rez.card.waive')) + '</div>';
    return '';
  };

  try {
    var st = document.createElement('style');
    st.textContent = '.mg-card-round{margin:.35rem 0 0;font-size:.9rem;line-height:1.35;color:#3a4a40}'
      + '.mg-card-round-line{font-weight:600}.mg-card-round-note{opacity:.85}'
      + '.erez-card-note{display:block;margin-top:.35rem;font-size:.88rem;font-weight:500;color:#3a4a40}'
      // krok platby rezervace: věta patří pod částku a tlačítko „Zaplatit" na každé šířce (na mobilu
      // řadí main.css volbu platby 1 / částku 2 / zpět 3 — bez order by věta skočila nad volbu platby)
      + '.rez-step2-actions>.mg-card-round{order:2;flex:0 0 auto;width:100%;text-align:center}'
      + '@media(min-width:769px){.rez-step2-actions>.mg-card-round{text-align:right}}';
    (document.head || document.documentElement).appendChild(st);
  } catch (e) { /* noop */ }

  function place(anchor, id, html) {
    if (!anchor || !anchor.parentNode) return;
    var el = document.getElementById(id);
    if (!html) { if (el) el.parentNode.removeChild(el); return; }
    if (!el) {
      el = document.createElement('div'); el.id = id; el.className = 'mg-card-round';
      el.setAttribute('role', 'note');
      anchor.parentNode.insertBefore(el, anchor.nextSibling);
    }
    if (el.innerHTML !== html) el.innerHTML = html;
  }

  // ── Háček 1: rezervace (krok s platbou) — částka MG._rez._grandTotal (rezervace + doprodej) ──
  function refreshRez() {
    var amt = document.querySelector('.rez-step2-pay .rez-step2-amount');
    if (!amt) return;
    var rez = MG._rez || {};
    var due = rez._grandTotal != null ? Number(rez._grandTotal)
      : (rez.bookingAmount != null ? Number(rez.bookingAmount) + (typeof MG._rezShopTotal === 'function' ? Number(MG._rezShopTotal()) || 0 : 0) : NaN);
    var m = document.querySelector('input[name="rez-pay-method"]:checked');
    var online = !m || m.value === 'online'; // QR platba převodem minimum karty nemá
    var html = online && isFinite(due) ? MG.cardNoteLines(due, 'rez') : '';
    place(amt.parentNode, 'mg-card-round-rez', html);
    payAmount(amt, html ? chargeText(due) : null, isFinite(due) ? fpDisplay(due) : null);
  }

  /** Co se opravdu zaplatí kartou: dorovnání → 15 Kč, odpuštění (do 1 Kč) → 0 Kč, jinak nic neměnit. */
  function chargeText(due) {
    var k = MG.cardCharge(due).kind;
    return k === 'round' ? fp(MIN) : (k === 'waive' ? fp(0) : null);
  }

  /** Částka u tlačítka „Zaplatit": s dorovnáním 15 Kč (stejně jako na stránce Stripe), odpuštěná
   *  částka do 1 Kč 0 Kč; jinak se vrátí původní částka (jen když ji změnil tenhle soubor). */
  function payAmount(el, roundText, normalText) {
    if (!el) return;
    if (roundText) {
      el.setAttribute('data-mg-card', '1');
      if (el.textContent !== roundText) el.textContent = roundText;
    } else if (el.getAttribute('data-mg-card')) {
      el.removeAttribute('data-mg-card');
      if (normalText != null && el.textContent !== normalText) el.textContent = normalText;
    }
  }

  // ── Háček 2: pokladna e-shopu — celkem z [data-checkout-total] (checkout.js: „1 234 Kč") ──
  function refreshShop() {
    var tot = document.querySelector('[data-checkout-total]');
    if (!tot) return;
    var due = Number(String(tot.textContent || '').replace(/[^\d]/g, ''));
    var dl = tot.closest ? tot.closest('dl') : null;
    var html = due > 0 ? MG.cardNoteLines(due, 'shop') : '';
    place(dl || tot, 'mg-card-round-shop', html);
    payAmount(document.querySelector('[data-checkout-pay]'), html ? chargeText(due) : null, tot.textContent);
  }

  var pending = false;
  function refreshAll() {
    if (pending) return;
    pending = true;
    setTimeout(function () { pending = false; try { refreshRez(); refreshShop(); } catch (e) { /* noop */ } }, 60);
  }

  function start() {
    MG.cardRoundingLive();
    // DOM háčky jen na stránce rezervace (#rez-form) a v pokladně e-shopu ([data-checkout-form]).
    if (!document.getElementById('rezervace-app') && !document.getElementById('rez-form') && !document.querySelector('[data-checkout-form]')) return;
    try {
      var obs = new MutationObserver(function (list) {
        for (var i = 0; i < list.length; i++) {
          var n = list[i].target;
          if (n && n.id && /^mg-card-round/.test(n.id)) continue;
          if (n && n.parentNode && n.parentNode.id && /^mg-card-round/.test(n.parentNode.id)) continue;
          refreshAll(); return;
        }
      });
      obs.observe(document.body, { childList: true, subtree: true, characterData: true });
    } catch (e) { /* noop */ }
    document.addEventListener('change', function (e) {
      if (e.target && e.target.name === 'rez-pay-method') refreshAll();
    });
    refreshAll();
  }

  // Úprava rezervace (háčky v pages-upravit-rezervaci*.js) potřebuje jen detekci.
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
