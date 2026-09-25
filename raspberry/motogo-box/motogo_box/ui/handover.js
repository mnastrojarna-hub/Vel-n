/* MotoGo24 kiosk — předávací protokol na displeji (overlay #handover, kontrakt §4/§5 návrhu 2026-09-25).
   Zdroj pravdy = snapshot `st.handover.active` (jednotka: HandoverManager) — UI ho jen zobrazuje a posílá
   /api/protocol/submit | dismiss | touch. Odpočet výhradně z `active.expires_at`. Výsledek, který snapshot nenese
   (kóje otevřená po vzdáleném podpisu s then_open, timeout vlastního submitu), se odvozuje ze stavu zón (S.wait).
   Vanilla JS, bez závislostí; závisí na MG.i18n (+ i18n-handover.js), MG.Keyboard (mode 'pin') a MG.Signature. */
'use strict';
window.MG = window.MG || {};

MG.Handover = (function () {
  const $ = (id) => document.getElementById(id);
  const TOUCH_MS = 5000, SUBMIT_TIMEOUT_MS = 60000, CODE_LEN = 6, DONE_GUARD_MS = 15000, WAIT_MS = 4000;
  const GEAR_ICON = { helmet: '🪖', jacket: '🧥', pants: '👖', boots: '🥾', gloves: '🧤' };
  const LOCALE = { cs: 'cs-CZ', en: 'en-GB', de: 'de-DE', es: 'es-ES', fr: 'fr-FR', nl: 'nl-NL', pl: 'pl-PL', uk: 'uk-UA' };
  let deps = null;    // { post, showStatus, getState }
  const S = { item: null, key: '', code: '', picks: [], saving: false, lastTouch: 0, msg: null, sig: null, kb: null,
    timer: null, doneKey: '', ownDone: { id: '', at: 0 }, wait: null };
  // S.msg = {key} (i18n) | {locked: locked_until} ; S.wait = {id, thenOpen, at} — položka zmizela, výsledek řekne stav zón

  function setText(el, text) { if (el && el.textContent !== text) el.textContent = text; }
  const itemKey = (a) => a.booking_id + '|' + (a.shown_at || '');
  const cz = () => MG.i18n.lang === MG.i18n.DEFAULT;

  /** Datum z ISO (date i timestamp) v jazyce displeje; nerozpoznané → původní text. */
  function fmtDate(v) {
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v || ''));
    if (!m) return v ? String(v) : '';
    try { return new Intl.DateTimeFormat(LOCALE[MG.i18n.lang] || 'cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' }).format(new Date(+m[1], +m[2] - 1, +m[3])); }
    catch (e) { return m[3] + '. ' + m[2] + '. ' + m[1]; }
  }

  /* ── Dotyk → prodloužení relace (throttle) ────────────────────────────── */
  function touch() {
    const now = Date.now();
    if (!S.item || now - S.lastTouch < TOUCH_MS) return;
    S.lastTouch = now;
    deps.post('/api/protocol/touch', { booking_id: S.item.booking_id }, 5000);
  }

  /* ── Vykreslení ───────────────────────────────────────────────────────── */
  function renderMeta(a) {
    const d = a.data || {};
    setText($('ho-customer'), d.customer_name || '—');
    setText($('ho-moto'), [d.moto_model, d.moto_spz].filter(Boolean).join(' · ') || '—');
    const from = fmtDate(d.start_date), to = fmtDate(d.end_date);
    setText($('ho-period'), from && to && from !== to ? from + ' – ' + to : (from || to || '—'));
  }

  function chip(label, on, onTap) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'ho-chip' + (on ? ' on' : '');
    b.textContent = label;
    b.addEventListener('click', (e) => { e.preventDefault(); onTap(); });
    return b;
  }

  /** Řádky výbavy: skupina Řidič / Spolujezdec, ikona + název (i18n g.*), chipy velikostí z číselníku (+ aktuální). */
  function renderGear(a) {
    const box = $('ho-gear-list');
    box.textContent = '';
    const gear = Array.isArray(a.data && a.data.gear) ? a.data.gear : [];
    if (!gear.length) {
      const p = document.createElement('div'); p.className = 'ho-nogear'; p.textContent = MG.i18n.t('ho.noGear'); box.appendChild(p);
      return;
    }
    ['rider', 'passenger'].forEach((who) => {
      const rows = gear.map((g, i) => [g, i]).filter(([g]) => (g.who || 'rider') === who);
      if (!rows.length) return;
      const h = document.createElement('div'); h.className = 'ho-group'; h.textContent = MG.i18n.t('ho.' + who); box.appendChild(h);
      rows.forEach(([g, i]) => {
        const row = document.createElement('div');
        row.className = 'ho-row';
        row.innerHTML = '<span class="ho-row-ico"></span><span class="ho-row-name"></span><div class="ho-chips"></div>';
        row.querySelector('.ho-row-ico').textContent = GEAR_ICON[g.key] || '🎽';
        row.querySelector('.ho-row-name').textContent = MG.i18n.g('g', g.key) || g.key || '';
        const sizes = (a.sizes && Array.isArray(a.sizes[g.key]) ? a.sizes[g.key] : []).map(String);
        const cur = S.picks[i];
        if (cur && sizes.indexOf(cur) === -1) sizes.unshift(cur);
        const chips = row.querySelector('.ho-chips');
        if (!sizes.length) { const s = document.createElement('span'); s.className = 'ho-size-na'; s.textContent = '—'; chips.appendChild(s); }
        sizes.forEach((sz) => chips.appendChild(chip(sz, sz === cur, () => { S.picks[i] = sz; touch(); renderGear(a); })));
        box.appendChild(row);
      });
    });
  }

  function paintCode() {
    const box = $('ho-code-box');
    if (!S.code) { box.textContent = '— — — — — —'; box.classList.add('empty'); }
    else { box.textContent = S.code.split('').join(' '); box.classList.remove('empty'); }
  }
  /** Hláška v patičce: i18n klíč, nebo `{locked}` = PIN lockout jednotky (stejný text jako na hlavní obrazovce, minuty živě). */
  function paintMsg() {
    const m = S.msg, el = $('ho-msg');
    const text = !m ? '' : m.locked !== undefined
      ? MG.i18n.errorTitle('locked') + '\n' + MG.i18n.errorSubtitle('locked', m.locked) : MG.i18n.t(m.key);
    setText(el, text);
    el.hidden = !text;
  }
  function setMsg(m) { S.msg = !m ? null : typeof m === 'string' ? { key: m } : m; paintMsg(); }
  /** Spinner „Ukládám…“: vlastní požadavek NEBO jednotka stále ukládá (`active.saving` — po timeoutu UI / jiná cesta). */
  function paintSaving() {
    const on = S.saving || !!(S.item && S.item.saving);
    $('ho-saving').hidden = !on;
    $('handover').classList.toggle('saving', on);
  }
  function updateButtons() {
    const a = S.item;
    const busy = S.saving || !!(a && a.saving);
    const noSig = !S.sig || S.sig.isEmpty();
    const noCode = !!(a && a.needs_code) && S.code.length !== CODE_LEN;
    $('ho-confirm').disabled = !a || busy || noSig || noCode;
    $('ho-back').disabled = busy;
    $('ho-sig-hint').hidden = !noSig;
    if (S.kb) S.kb.setEnabled(!busy);
  }
  function tickTimer() {
    const a = S.item;
    if (!a) return;
    const left = Math.ceil((Date.parse(a.expires_at || '') - Date.now()) / 1000);
    setText($('ho-timer'), isFinite(left) && left >= 0 ? MG.i18n.t('ho.autoClose', { s: left }) : '');
    if (S.msg && S.msg.locked !== undefined) paintMsg();   // „zkuste za {m} min“ ubíhá
    if (isFinite(left) && left < -3) hide();   // jednotka overlay skryje sama (WS); pojistka při výpadku WS
  }
  function setSaving(on) { S.saving = on; paintSaving(); updateButtons(); }

  /* ── Otevření / skrytí ────────────────────────────────────────────────── */
  function open(a) {
    S.item = a; S.key = itemKey(a); S.code = ''; S.saving = false; S.lastTouch = Date.now();
    if (S.wait && S.wait.id === a.booking_id) S.wait = null;   // protokol téže rezervace znovu (podpis se neuložil) — čekaný výsledek je pasé
    S.picks = (Array.isArray(a.data && a.data.gear) ? a.data.gear : []).map((g) => (g.size != null && g.size !== '' ? String(g.size) : ''));
    setMsg(null);
    $('handover').hidden = false;
    $('handover').classList.toggle('no-code', !a.needs_code);
    $('ho-code-sec').hidden = !a.needs_code;
    renderMeta(a);
    renderGear(a);
    paintCode();
    if (!S.sig) S.sig = MG.Signature.create($('ho-sig'), { onStroke: () => { touch(); updateButtons(); } });
    S.sig.clear();
    S.sig.resize();
    if (!S.kb) S.kb = MG.Keyboard.build($('ho-keys'), { mode: 'pin', onChar: onCodeChar, onBackspace: onCodeBackspace, onEnter: confirm, onClear: onCodeClear });
    paintSaving();
    clearInterval(S.timer);
    S.timer = setInterval(tickTimer, 1000);
    tickTimer();
    updateButtons();
  }
  /** Stejná položka, nový snapshot: then_open mohl vypršet (needs_code), ukládání z jiné cesty, prodloužený odpočet. */
  function sync(a) {
    const codeChanged = !!S.item.needs_code !== !!a.needs_code;
    S.item = a;
    if (codeChanged) { $('handover').classList.toggle('no-code', !a.needs_code); $('ho-code-sec').hidden = !a.needs_code; S.sig.resize(); }
    paintSaving();
    // po timeoutu vlastního submitu: položka je dál vidět a jednotka neukládá → požadavek k ní vůbec nedorazil
    if (S.wait && S.wait.id === a.booking_id && !S.saving && !a.saving) { S.wait = null; setMsg('ho.failed'); }
    tickTimer();
    updateButtons();
  }
  function hide() {
    if (!S.item) return;
    S.item = null; S.key = ''; S.code = ''; S.saving = false;
    clearInterval(S.timer); S.timer = null;
    $('handover').hidden = true;
    $('handover').classList.remove('saving');
    setMsg(null);
  }

  /** Toast DONE (stage 'done'): jednou na položku; po vlastním podpisu ho nahrazuje výsledek submitu. */
  function showDone(a) {
    const k = itemKey(a);
    if (k === S.doneKey) return;
    S.doneKey = k;
    if (a.booking_id === S.ownDone.id && Date.now() - S.ownDone.at < DONE_GUARD_MS) return;
    deps.showStatus('success', MG.i18n.t('ho.doneTitle'), MG.i18n.t('ho.done'), true);
  }

  /* ── Výsledek, který snapshot nenese (§1: vzdálený podpis s then_open = plnohodnotné otevření) ── */
  const openedZone = (st, id) => ((st && st.zones) || []).find((z) => z.booking_id === id && z.kind !== 'accessories'
    && (z.state === 'WAITING_FOR_OPEN' || z.state === 'DOOR_OPEN'));
  function announceOpened(z) {
    deps.showStatus('success', MG.i18n.t('opened'),
      MG.i18n.t('ho.doneMoto') + '\n' + MG.i18n.successSubtitle('motorcycle', MG.i18n.zoneName(z)), true);
  }
  /** Čekání na stav zón: kóje rezervace otevřená → „Otevřeno — Kóje N“; po WAIT_MS bez otevření → DONE
      (then_open: „kóji se nepodařilo otevřít — zadejte kód znovu“; jinak „teď zadejte kód motorky“). */
  function armWait(id, thenOpen) {
    S.wait = { id, thenOpen, at: Date.now() };
    setTimeout(() => resolveWait(deps.getState()), WAIT_MS + 300);
    resolveWait(deps.getState());
  }
  function resolveWait(st) {
    const w = S.wait;
    if (!w) return;
    const z = openedZone(st, w.id);
    if (!z && Date.now() - w.at < WAIT_MS) return;
    S.wait = null;
    if (z) { announceOpened(z); return; }
    deps.showStatus('success', MG.i18n.t('ho.doneTitle'), MG.i18n.t(w.thenOpen ? 'ho.doneNoOpen' : 'ho.done'), true);
  }
  /** Položka zmizela bez naší odpovědi: vlastní submit řeší confirm(); vypršelý odpočet = zákazník odešel (nic);
      jinak vzdálený podpis (appka/Velín) během overlaye s platným then_open → jednotka kóji otevřela → potvrdit ze zón. */
  function onGone(prev, ownSaving) {
    if (ownSaving || S.wait || prev.stage !== 'protocol' || !prev.then_open) return;
    if (!(Date.parse(prev.expires_at || '') - Date.now() > 1500)) return;
    armWait(prev.booking_id, true);
  }

  /** Volá app.js render() s každým snapshotem. */
  function onState(st) {
    const a = st && st.handover && st.handover.active;
    if (!a) { const prev = S.item, own = S.saving; hide(); if (prev) onGone(prev, own); }
    else if (a.stage === 'done') { hide(); showDone(a); }
    else if (itemKey(a) !== S.key) open(a);
    else sync(a);
    resolveWait(st);
  }

  /* ── Kód motorky (identita podepisujícího) ────────────────────────────── */
  function onCodeChar(ch) {
    if (S.saving || !S.item || !S.item.needs_code || !/^[0-9]$/.test(ch) || S.code.length >= CODE_LEN) return;
    S.code += ch; paintCode(); touch(); updateButtons();
  }
  function onCodeBackspace() { if (S.saving || !S.code) return; S.code = S.code.slice(0, -1); paintCode(); touch(); updateButtons(); }
  function onCodeClear() { if (S.saving) return; S.code = ''; paintCode(); touch(); updateButtons(); }

  /* ── Potvrdit a podepsat ──────────────────────────────────────────────── */
  async function confirm() {
    const a = S.item;
    if (!a || $('ho-confirm').disabled) return;
    touch();
    const signature = S.sig.toPng();
    if (!signature) { setMsg('ho.sigTooLarge'); return; }
    const gear = Array.isArray(a.data && a.data.gear) ? a.data.gear : [];
    const form = {
      mileage: a.data && a.data.mileage != null ? String(a.data.mileage) : '',
      accessories: gear.map((g, i) => ({ key: g.key, who: g.who || 'rider', field: g.field, size: S.picks[i] || '', checked: true })),
    };
    const body = { booking_id: a.booking_id, form, signature };
    if (a.needs_code) body.code = S.code;
    setMsg(null);
    setSaving(true);
    const res = await deps.post('/api/protocol/submit', body, SUBMIT_TIMEOUT_MS);
    const same = !!(S.item && S.item.booking_id === a.booking_id);
    if (same) setSaving(false);
    if (!res.ok) {
      const e = res.error;
      if (e === 'not_pending') { hide(); return; }   // položka mezitím zmizela (podpis v appce) — displej řídí snapshot
      if (e === 'network' && !res.status) {
        // timeout / spojení: jednotka může dál ukládat a otevírat (resolve + edge až ~52 s) → výsledek řekne snapshot
        if (same && !S.item.saving) { setMsg('ho.failed'); return; }   // jednotka neukládá → požadavek nedorazil
        armWait(a.booking_id, !a.needs_code);
        return;
      }
      if (e === 'storage_failed') {   // podpis se neuložil ani neodeslal; jednotka položku zrušila → pokyn do #status (overlay zmizí)
        hide(); deps.showStatus('error', MG.i18n.errorTitle('protocol_failed'), MG.i18n.t('ho.retryCode'), true); return;
      }
      if (!same) return;
      if (e === 'locked') { S.code = ''; paintCode(); setMsg({ locked: res.locked_until || null }); updateButtons(); return; }
      if (e === 'body_too_large' || res.status === 413) { setMsg('ho.sigTooLarge'); return; }
      setMsg(e === 'code_mismatch' ? 'ho.codeMismatch' : e === 'signature_too_large' ? 'ho.sigTooLarge'
        : e === 'in_progress' ? 'ho.inProgress' : 'ho.failed');
      if (e === 'code_mismatch') { S.code = ''; paintCode(); updateButtons(); }
      return;
    }
    S.ownDone = { id: a.booking_id, at: Date.now() };
    hide();
    const st = deps.getState() || {};
    if (res.opened) {
      const z = (st.zones || []).find((x) => x.zone === res.opened.zone);
      const name = z ? MG.i18n.zoneName(z) : MG.i18n.t('box', { n: res.opened.zone });
      deps.showStatus('success', MG.i18n.t('opened'),
        MG.i18n.t('ho.doneMoto') + '\n' + ((cz() && res.opened.message) || MG.i18n.successSubtitle('motorcycle', name)), true);
      return;
    }
    const noOpen = ['busy', 'door_open', 'lock_failed', 'zone_not_configured', 'io_offline', 'fault'].indexOf(res.error) !== -1;
    deps.showStatus('success', MG.i18n.t('ho.doneTitle'), MG.i18n.t(noOpen ? 'ho.doneNoOpen' : 'ho.done'), true);
  }

  async function dismiss() {
    const a = S.item;
    if (!a || S.saving || a.saving) return;
    hide();
    deps.post('/api/protocol/dismiss', { booking_id: a.booking_id }, 5000);
  }

  /** Změna jazyka: statické popisky řeší MG.i18n.applyStatic (data-i18n), tady dynamické části;
      delší/kratší texty mění výšku rámečku podpisu → přepočet bitmapy canvasu. */
  function rerender() {
    const a = S.item;
    if (!a) return;
    renderMeta(a); renderGear(a); paintMsg(); tickTimer();
    if (S.sig) S.sig.resize();
  }

  function init(d) {
    deps = d;
    $('ho-confirm').addEventListener('click', (e) => { e.preventDefault(); confirm(); });
    $('ho-back').addEventListener('click', (e) => { e.preventDefault(); dismiss(); });
    $('ho-sig-clear').addEventListener('click', (e) => { e.preventDefault(); if (S.sig && !S.saving) S.sig.clear(); touch(); });
    $('handover').addEventListener('pointerdown', touch, { passive: true, capture: true });
  }

  /** Fyzická klávesnice, dokud je overlay vidět (app.js): číslice → kód motorky, Enter → potvrdit, Esc → zpět. */
  const keys = { onChar: onCodeChar, onBackspace: onCodeBackspace, onEnter: confirm, onClear: onCodeClear, onEscape: dismiss };

  return { init, onState, rerender, keys, isVisible: () => !!S.item, dismiss };
})();
