/* MotoGo24 kiosk — hlavní logika: WS klient, zadávání kódu, overlay stavů, dlaždice zón.
   Vanilla JS (offline, bez CDN). Texty a flow převzaté z Flutter kiosku (kiosk_screen.dart). */
'use strict';
window.MG = window.MG || {};

/* ── Texty (CZ) ─────────────────────────────────────────────────────────── */
MG.i18n = (function () {
  const SUPPORT = '+420 774 256 271';
  const RETRY = 'Zkuste to prosím znovu nebo kontaktujte podporu: ' + SUPPORT + '.';
  const STATES = { SECURED: 'Zamčeno', WAITING_FOR_OPEN: 'Otevřete dveře', DOOR_OPEN: 'Otevřeno',
    CLOSED_CONFIRMATION: 'Zavřeno', FAULT: 'Porucha' };
  const SIGNALS = { red: 'červená', green: 'zelená', green_pulse: 'zelená pulzuje', red_blink: 'červená bliká',
    both_blink: 'obě blikají', off: 'vypnuto' };
  const FAULTS = { io_offline: 'I/O modul nedostupný', forced_open: 'dveře otevřeny bez kódu',
    open_at_startup: 'dveře otevřené při startu', contact_fault: 'porucha dveřního kontaktu' };
  const ERR_TITLE = { invalid_code: 'Neplatný kód', network: 'Chyba spojení', locked: 'Zadávání dočasně zablokováno',
    zone_not_configured: 'Dveře nejsou nastaveny', io_offline: 'Kóje je mimo provoz', door_open: 'Dveře jsou otevřené',
    busy: 'Kóje je právě používána', lock_failed: 'Dveře se neozvaly', fault: 'Porucha kóje',
    unauthorized: 'Neplatný kód', branch_not_found: 'Neplatný kód', empty_code: 'Zadejte kód' };
  const ERR_SUB = { invalid_code: 'Kód nebyl rozpoznán nebo už není platný.',
    network: 'Chyba spojení. Zkontrolujte internet a zkuste znovu.',
    zone_not_configured: 'Kód je platný, ale dveře nejsou ve Velíně nastaveny. Kontaktujte podporu: ' + SUPPORT + '.',
    io_offline: 'Řídicí modul kóje je nedostupný. Kontaktujte podporu: ' + SUPPORT + '.',
    door_open: 'Dveře jsou už otevřené — zavřete je a zadejte kód znovu.',
    busy: 'Dveře jsou už otevřené — zavřete je a zadejte kód znovu.',
    lock_failed: RETRY, fault: 'Kóje hlásí poruchu. Kontaktujte podporu: ' + SUPPORT + '.',
    unauthorized: 'Kiosk není správně spárovaný s pobočkou.', branch_not_found: 'Kiosk není správně spárovaný s pobočkou.' };
  function lockedSubtitle(lockedUntil) {
    const min = lockedUntil ? Math.max(1, Math.ceil((Number(lockedUntil) - Date.now() / 1000) / 60)) : null;
    return 'Příliš mnoho neplatných pokusů.' + (min ? ' Zkuste to znovu za ' + min + ' min.' : ' Zkuste to později.')
      + '\nPodpora: ' + SUPPORT;
  }
  return {
    SUPPORT, RETRY,
    zoneState: (s) => STATES[s] || s || '—',
    signal: (s) => SIGNALS[(s || '').toLowerCase()] || s || '—',
    fault: (f) => FAULTS[f] || f || '',
    door: (c) => (c === true ? 'zavřeno' : c === false ? 'otevřeno' : 'neznámo'),
    zoneName: (z) => z.label || (z.kind === 'accessories' ? 'Oblečení' : 'Kóje ' + (z.box_number != null ? z.box_number : z.zone)),
    errorTitle: (e) => ERR_TITLE[e] || 'Neplatný kód',
    errorSubtitle: (e, lockedUntil) => (e === 'locked' ? lockedSubtitle(lockedUntil) : (ERR_SUB[e] || 'Zkuste to prosím znovu.')),
    successSubtitle: (kind, name) => (kind === 'accessories' ? name + '\n\nPo vyzvednutí oblečení zavřete dveře a zadejte kód k motorce.'
      : kind === 'motorcycle' ? name + '\n\nPříjemnou cestu! 🏍️' : name),
  };
})();

/* ── Aplikace ───────────────────────────────────────────────────────────── */
(function () {
  const $ = (id) => document.getElementById(id);
  const MAX_LEN = 24, AUTO_HIDE_MS = 6000, WS_RECONNECT_MS = 2000, POLL_MS = 5000, STALE_MS = 4500;
  const S = { state: null, ws: null, wsOk: false, lastStateAt: 0, entry: '', busy: false, mode: 'num',
    pinTimer: null, pinDeadline: 0, hideTimer: null, noticeTs: null, kb: null };
  const tiles = new Map();   // zone → { el, json }

  /* ── HTTP ─────────────────────────────────────────────────────────── */
  async function post(path, body, timeoutMs) {
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), timeoutMs || 20000);
    try {
      const r = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body || {}), signal: ctl.signal, cache: 'no-store' });
      let data = null;
      try { data = await r.json(); } catch (e) { data = null; }
      if (!data || typeof data !== 'object') data = { ok: false, error: r.ok ? 'bad_response' : 'network' };
      data.status = r.status;
      return data;
    } catch (e) {
      return { ok: false, error: 'network', status: 0 };
    } finally { clearTimeout(t); }
  }

  /* ── Stav ze serveru (WS + fallback) ──────────────────────────────── */
  function applyState(st) {
    if (!st || typeof st !== 'object') return;
    S.state = st;
    S.lastStateAt = Date.now();
    render();
  }

  function connectWs() {
    if (S.ws) return;
    let ws;
    try { ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws'); }
    catch (e) { setTimeout(connectWs, WS_RECONNECT_MS); return; }
    S.ws = ws;
    ws.onopen = () => { S.wsOk = true; updateBanner(); };
    ws.onmessage = (ev) => {
      try {
        const m = JSON.parse(ev.data);
        if (m && m.type === 'state') applyState(m.state);
      } catch (e) { /* ignorovat nevalidní zprávu */ }
    };
    ws.onerror = () => { try { ws.close(); } catch (e) { /* noop */ } };
    ws.onclose = () => { S.ws = null; S.wsOk = false; updateBanner(); setTimeout(connectWs, WS_RECONNECT_MS); };
  }

  async function pollFallback() {
    if (S.wsOk) return;
    try {
      const r = await fetch('/api/state', { cache: 'no-store' });
      if (r.ok) applyState(await r.json());
    } catch (e) { /* server nedostupný — banner */ }
    updateBanner();
  }

  function updateBanner() {
    const down = !S.wsOk && Date.now() - S.lastStateAt > STALE_MS;
    $('banner').hidden = !down;
  }

  /* ── Vykreslení (jen změněné části) ───────────────────────────────── */
  function setText(el, text) { if (el.textContent !== text) el.textContent = text; }

  function render() {
    const st = S.state || {};
    setText($('branch-name'), st.branch_name || 'Samoobslužná pobočka');
    const dot = $('online-dot');
    const cls = st.internet === true ? 'dot dot-on' : 'dot dot-off';
    if (dot.className !== cls) dot.className = cls;
    renderTiles(st.zones || []);
    renderAlert(st);
    if (st.paired === false && !MG.Setup.isVisible()) MG.Setup.show({ cancelable: false });
    MG.Panel.render(st);
    if (st.notice && st.notice.ts && st.notice.ts !== S.noticeTs) {
      S.noticeTs = st.notice.ts;
      if (!S.busy) showStatus(st.notice.kind === 'error' ? 'error' : 'success', st.notice.title || 'Tady jsem 👋', st.notice.subtitle || '', true);
    }
  }

  function tileEl(z) {
    const el = document.createElement('div');
    el.className = 'tile';
    el.innerHTML = '<div class="tile-top"><span class="tile-num"></span><span class="tile-sig"></span></div>' +
      '<div class="tile-name"></div><div class="tile-bottom"><span class="tile-state"></span><span class="tile-door"></span></div>';
    return el;
  }

  function isOvertime(z) {
    return z.overtime === true || (z.state === 'DOOR_OPEN' && (z.signal || '').toLowerCase() === 'green_pulse')
      || (z.last_event || '').indexOf('SESSION_OVERTIME') === 0;
  }

  function renderTiles(zones) {
    const box = $('zones');
    const seen = new Set();
    zones.forEach((z) => {
      seen.add(z.zone);
      const j = JSON.stringify(z);
      let t = tiles.get(z.zone);
      if (!t) { t = { el: tileEl(z), json: '' }; tiles.set(z.zone, t); box.appendChild(t.el); }
      if (t.json === j) return;
      t.json = j;
      const sig = (z.signal || 'off').toLowerCase();
      t.el.className = 'tile sig-' + sig + (z.fault || z.state === 'FAULT' ? ' fault' : '') + (isOvertime(z) ? ' overtime' : '');
      setText(t.el.querySelector('.tile-num'), String(z.box_number != null ? z.box_number : z.zone));
      setText(t.el.querySelector('.tile-name'), MG.i18n.zoneName(z));
      setText(t.el.querySelector('.tile-state'), z.fault ? MG.i18n.fault(z.fault) : MG.i18n.zoneState(z.state));
      setText(t.el.querySelector('.tile-door'), z.door_closed === true ? '🔒' : z.door_closed === false ? '🚪' : '❔');
    });
    tiles.forEach((t, zone) => { if (!seen.has(zone)) { t.el.remove(); tiles.delete(zone); } });
  }

  function renderAlert(st) {
    const el = $('zone-alert');
    let text = '', kind = '';
    if (st.ready === false && st.last_error) { text = 'Řídicí jednotka: ' + st.last_error; kind = 'error'; }
    (st.zones || []).forEach((z) => {
      if (text) return;
      const name = MG.i18n.zoneName(z);
      if (isOvertime(z)) { text = '⚠ ' + name + ': dveře jsou otevřené příliš dlouho — zavřete je prosím.'; kind = 'warn'; }
      else if (z.fault || z.state === 'FAULT') { text = '⚠ ' + name + ': ' + (MG.i18n.fault(z.fault) || 'porucha') + ' — kontaktujte podporu ' + MG.i18n.SUPPORT; kind = 'error'; }
    });
    setText(el, text);
    const cls = 'zone-alert' + (kind ? ' ' + kind : '');
    if (el.className !== cls) el.className = cls;
  }

  /* ── Zadávání kódu ────────────────────────────────────────────────── */
  function masked() {
    const sec = (S.state && S.state.security) || {};
    return sec.mask_pin_on_screen !== false;
  }
  function pinTimeoutMs() {
    const t = S.state && S.state.timings && Number(S.state.timings.pin_entry_timeout_s);
    return (t > 0 ? t : 20) * 1000;
  }
  function paintEntry() {
    const box = $('code-box');
    if (!S.entry) { box.textContent = '— — — — — —'; box.classList.add('empty'); }
    else { box.textContent = masked() ? '●'.repeat(S.entry.length) : S.entry.toUpperCase(); box.classList.remove('empty'); }
  }
  function armPinTimeout() {
    clearTimeout(S.pinTimer);
    if (!S.entry) { $('code-timer').hidden = true; return; }
    S.pinDeadline = Date.now() + pinTimeoutMs();
    S.pinTimer = setTimeout(() => { S.entry = ''; paintEntry(); $('code-timer').hidden = true; }, pinTimeoutMs());
  }
  function tickTimer() {
    const el = $('code-timer');
    if (!S.entry || S.busy) { el.hidden = true; return; }
    const left = Math.max(0, Math.ceil((S.pinDeadline - Date.now()) / 1000));
    el.hidden = false;
    setText(el, left + ' s');
  }
  function onChar(ch) { if (S.busy || S.entry.length >= MAX_LEN) return; S.entry += ch; paintEntry(); armPinTimeout(); }
  function onBackspace() { if (S.busy || !S.entry) return; S.entry = S.entry.slice(0, -1); paintEntry(); armPinTimeout(); }
  function onClear() { if (S.busy) return; S.entry = ''; paintEntry(); armPinTimeout(); }
  function toggleMode() { S.mode = S.mode === 'num' ? 'qwerty' : 'num'; buildKeys(); }
  function buildKeys() {
    S.kb = MG.Keyboard.build($('keys'), { mode: S.mode, onChar, onBackspace, onEnter: submit, onClear, onToggle: toggleMode });
    S.kb.setEnabled(!S.busy);
  }

  async function submit() {
    const code = S.entry.trim();
    if (!code || S.busy) return;
    S.busy = true;
    S.kb.setEnabled(false);
    clearTimeout(S.pinTimer);
    showStatus('working', 'Ověřuji kód…', '', false);
    const res = await post('/api/pin', { code });
    S.entry = '';
    paintEntry();
    S.busy = false;
    S.kb.setEnabled(true);
    if (!res.ok) {
      showStatus('error', MG.i18n.errorTitle(res.error), res.message || MG.i18n.errorSubtitle(res.error, res.locked_until), true);
      return;
    }
    if (res.kind === 'service') { hideStatus(); MG.Panel.show(res.service_token); return; }
    const z = res.zone != null ? (S.state && (S.state.zones || []).find((x) => x.zone === res.zone)) : null;
    const name = z ? MG.i18n.zoneName(z) : (res.kind === 'accessories' ? 'Oblečení' : 'Dveře');
    showStatus('success', 'Otevřeno', res.message || MG.i18n.successSubtitle(res.kind, name), true);
  }

  /* ── Overlay stavů ────────────────────────────────────────────────── */
  function showStatus(kind, title, subtitle, dismissable) {
    clearTimeout(S.hideTimer);
    const working = kind === 'working';
    $('status-spinner').hidden = !working;
    const icon = $('status-icon');
    icon.hidden = working;
    icon.className = 'status-icon ' + kind;
    icon.textContent = kind === 'success' ? '🔓' : kind === 'error' ? '!' : '';
    $('status-title').textContent = title || '';
    $('status-sub').textContent = subtitle || '';
    $('status-dismiss').hidden = !dismissable;
    $('status').hidden = false;
    if (dismissable) S.hideTimer = setTimeout(hideStatus, AUTO_HIDE_MS);
  }
  function hideStatus() { clearTimeout(S.hideTimer); $('status').hidden = true; }

  /* ── Škálování na okno (1920×1080 fixní plátno) ───────────────────── */
  function fit() {
    const s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
    $('app').style.transform = s !== 1 ? 'scale(' + s + ')' : '';
    document.body.style.width = (1920 * s) + 'px';
    document.body.style.height = (1080 * s) + 'px';
  }

  /* ── Init ─────────────────────────────────────────────────────────── */
  function init() {
    MG.Panel.init({ post, showStatus, getState: () => S.state });
    MG.Setup.init({ post, onPaired: () => { showStatus('success', 'Spárováno', 'Zařízení je připojeno k pobočce.', true); pollFallback(); } });
    buildKeys();
    paintEntry();
    $('status').addEventListener('click', () => { if (!$('status-dismiss').hidden) hideStatus(); });
    MG.Keyboard.bindPhysical({
      isActive: () => !MG.Panel.isOpen() || MG.Setup.isVisible(),
      onChar: (c) => (MG.Setup.isVisible() ? MG.Setup.keys.onChar(c) : (/[0-9a-z]/.test(c) && onChar(c))),
      onBackspace: () => (MG.Setup.isVisible() ? MG.Setup.keys.onBackspace() : onBackspace()),
      onEnter: () => (MG.Setup.isVisible() ? MG.Setup.keys.onEnter() : submit()),
      onClear: () => (MG.Setup.isVisible() ? MG.Setup.keys.onClear() : onClear()),
      onEscape: () => { if (MG.Setup.isVisible()) MG.Setup.keys.onEscape(); else if (!$('status').hidden && !S.busy) hideStatus(); else onClear(); },
    });
    document.addEventListener('contextmenu', (e) => e.preventDefault());
    window.addEventListener('resize', fit);
    fit();
    connectWs();
    pollFallback();
    setInterval(pollFallback, POLL_MS);
    setInterval(() => { updateBanner(); tickTimer(); }, 1000);
  }

  MG.app = { post, showStatus, hideStatus, getState: () => S.state };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
