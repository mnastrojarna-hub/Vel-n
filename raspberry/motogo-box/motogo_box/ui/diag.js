/* MotoGo24 kiosk — diagnostika sítě: overlay s progresem a reportem (GET /api/diagnostics),
   spuštění kódem (POST /api/diagnostics/run {code}) nebo servisním tokenem. Vanilla JS, offline. */
'use strict';
window.MG = window.MG || {};

MG.Diag = (function () {
  const $ = (id) => document.getElementById(id);
  let deps = null;            // { post, getState }
  let visible = false, askCode = false, token = null, code = '', busy = false, kb = null;
  let shownId = null;         // id reportu, který je vykreslený
  let lastStatus = null;

  const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = String(text); return e; };
  const fmt = (v) => (v == null || v === '' ? '—' : String(v));
  const yesno = (v) => (v === true ? 'ANO' : v === false ? 'NE' : '—');

  function table(head, rows) {
    const t = el('table', 'diag-table');
    const tr = el('tr');
    head.forEach((h) => tr.appendChild(el('th', '', h)));
    t.appendChild(tr);
    rows.forEach((r) => { const row = el('tr'); r.forEach((c) => { const td = el('td'); if (c instanceof Node) td.appendChild(c); else td.textContent = fmt(c); row.appendChild(td); }); t.appendChild(row); });
    return t;
  }
  function section(title, node, cls) {
    const s = el('div', 'diag-section' + (cls ? ' ' + cls : ''));
    s.appendChild(el('div', 'diag-h', title));
    if (node) s.appendChild(node);
    return s;
  }
  function badge(ok, text) { return el('span', 'diag-badge ' + (ok === true ? 'ok' : ok === false ? 'bad' : 'na'), text); }
  function kv(pairs) {
    const g = el('div', 'diag-kv');
    pairs.forEach(([k, v]) => { g.appendChild(el('span', 'k', k)); const s = el('span', 'v'); if (v instanceof Node) s.appendChild(v); else s.textContent = fmt(v); g.appendChild(s); });
    return g;
  }

  function renderReport(r) {
    const box = $('diag-report');
    box.textContent = '';
    if (!r) { box.appendChild(el('div', 'diag-empty', 'Zatím neproběhla žádná diagnostika.')); return; }
    const sm = r.summary || {};
    const head = el('div', 'diag-summary ' + (sm.ok ? 'ok' : 'bad'));
    head.appendChild(el('div', 'diag-summary-title', sm.ok ? '✔ Síť je v pořádku' : '⚠ Nalezeno problémů: ' + (sm.problems || []).length));
    head.appendChild(el('div', 'diag-summary-sub', 'Běh ' + fmt(r.id) + ' · ' + new Date(r.ts).toLocaleString('cs-CZ') + ' · ' + fmt(r.duration_s) + ' s · spuštěno: ' + fmt(r.source)
      + ' · zařízení v LAN: ' + fmt(sm.hosts) + ' · moduly dostupné: ' + fmt(sm.devices_ok) + '/' + fmt(sm.devices_total)));
    if ((sm.problems || []).length) { const ul = el('ul', 'diag-problems'); sm.problems.forEach((p) => ul.appendChild(el('li', '', p))); head.appendChild(ul); }
    box.appendChild(head);

    const sys = r.system || {}, m = sys.metrics || {};
    box.appendChild(section('Systém', kv([['Hostname', sys.hostname], ['Verze programu', r.version], ['Zařízení', r.device_id], ['Pobočka', r.branch_name],
      ['Kernel', sys.kernel], ['Čas', sys.time], ['NTP sync', yesno(sys.ntp_synced)], ['CPU', m.cpu_temp != null ? m.cpu_temp + ' °C' : '—'],
      ['Throttled', m.throttled], ['Disk volný', m.disk_free_pct != null ? m.disk_free_pct + ' %' : '—'], ['RAM volná', m.mem_free_pct != null ? m.mem_free_pct + ' %' : '—'],
      ['Uptime systému', m.uptime_s != null ? Math.round(m.uptime_s / 60) + ' min' : '—'], ['Konfigurace', sys.config_source], ['Ready', yesno(sys.ready)]])));

    const ifc = r.interfaces || {};
    const ifRows = (ifc.interfaces || []).map((i) => [i.name, i.state, i.mac, (i.ipv4 || []).map((a) => a.addr + '/' + a.prefix).join(', ') || '—', (i.ipv6 || []).map((a) => a.addr).join(', ') || '—']);
    const rtRows = (ifc.default_routes || []).map((x) => [x.gateway, x.dev, x.metric]);
    const netBox = el('div');
    netBox.appendChild(table(['Rozhraní', 'Stav', 'MAC', 'IPv4', 'IPv6'], ifRows));
    netBox.appendChild(el('div', 'diag-sub', 'Výchozí brány'));
    netBox.appendChild(rtRows.length ? table(['Brána', 'Rozhraní', 'Metrika'], rtRows) : el('div', 'diag-empty', 'Žádná default route!'));
    netBox.appendChild(el('div', 'diag-sub', 'DNS servery: ' + ((ifc.dns || []).join(', ') || 'žádné')));
    box.appendChild(section('Síťová rozhraní', netBox));

    const lte = r.lte || {};
    box.appendChild(section('LTE modem', kv([['Stav modemu', lte.state], ['Operátor', lte.operator], ['Technologie', lte.access_tech], ['Registrace', lte.registration],
      ['Kvalita', lte.signal_quality != null ? lte.signal_quality + ' %' : '—'], ['RSSI', lte.rssi != null ? lte.rssi + ' dBm' : '—'], ['RSRP', lte.rsrp != null ? lte.rsrp + ' dBm' : '—'],
      ['RSRQ', lte.rsrq != null ? lte.rsrq + ' dB' : '—'], ['SNR', lte.snr != null ? lte.snr + ' dB' : '—'], ['NM profil', fmt(lte.nm_connection) + ' · ' + fmt(lte.nm_state) + (lte.nm_device ? ' (' + lte.nm_device + ')' : '')], ['Chyba', lte.error]])));

    const inet = r.internet || {};
    const inetBox = el('div');
    inetBox.appendChild(table(['Test', 'Výsledek', 'Čas'],
      [['TCP ' + fmt((inet.tcp || {}).host) + ':' + fmt((inet.tcp || {}).port), badge((inet.tcp || {}).open, (inet.tcp || {}).open ? 'otevřeno' : 'selhalo ' + fmt((inet.tcp || {}).error)), fmt((inet.tcp || {}).ms) + ' ms']]
        .concat((inet.dns || []).map((d) => ['DNS ' + d.host, badge(!!(d.addresses || []).length, (d.addresses || []).join(', ') || fmt(d.error)), fmt(d.ms) + ' ms']))
        .concat((inet.http || []).map((h) => ['HTTP ' + h.url, badge(h.status != null && h.status < 500, h.status != null ? 'HTTP ' + h.status : fmt(h.error)), fmt(h.ms) + ' ms']))));
    box.appendChild(section('Internet a DNS', inetBox));

    const sb = r.supabase || {};
    box.appendChild(section('Spojení s Velínem (Supabase)', kv([['URL', sb.url], ['Spárováno', yesno(sb.paired)], ['Heartbeat', sb.ok == null ? '— (nespárováno)' : badge(sb.ok, sb.ok ? 'OK ' + fmt(sb.ms) + ' ms' : fmt(sb.error))],
      ['Pobočka', sb.branch_name], ['Čekající odeslání (outbox)', sb.outbox_pending]])));

    const devRows = (r.devices || []).map((d) => {
      const id = d.identified || {};
      const idTxt = d.type === 'shelly_rgbww' ? (id.model ? fmt(id.model) + ' ' + fmt(id.id) + ' fw ' + fmt(id.fw) : '—') : (id.guess ? id.guess + ' (' + id.coils + ' relé, ' + id.inputs + ' DI)' : '—');
      return [d.name, d.type, d.host + ':' + d.port, badge(d.reachable, d.reachable ? 'dostupné ' + fmt(d.ms) + ' ms' : 'NEDOSTUPNÉ ' + fmt(d.error)), d.ping_ms != null ? d.ping_ms + ' ms' : '—', idTxt, badge(d.online, d.online ? 'online' : 'offline')];
    });
    box.appendChild(section('Konfigurovaná zařízení (Velín / hardware.yaml)', devRows.length ? table(['Název', 'Typ', 'Adresa', 'TCP', 'Ping', 'Identifikace', 'V programu'], devRows) : el('div', 'diag-empty', 'Žádná zařízení v konfiguraci.')));

    const lan = r.lan || {};
    const lanRows = (lan.hosts || []).map((h) => {
      let ident = '—';
      if (h.shelly) ident = 'Shelly ' + fmt(h.shelly.model) + ' ' + fmt(h.shelly.id);
      else if (h.modbus) ident = 'Modbus ' + fmt(h.modbus.guess) + ' (' + h.modbus.coils + ' relé, ' + h.modbus.inputs + ' DI)';
      else if (h.http) ident = 'HTTP ' + fmt(h.http.status) + ' ' + fmt(h.http.server || h.http.title);
      return [h.ip, h.mac, Object.keys(h.ports || {}).join(', '), ident, h.configured_as || '—'];
    });
    const lanBox = el('div');
    lanBox.appendChild(el('div', 'diag-sub', 'Podsítě: ' + ((lan.subnets || []).join(', ') || '—') + ' · porty: ' + ((lan.ports || []).join(', ')) + ' · prověřeno adres: ' + fmt(lan.scanned_hosts)
      + ((lan.skipped_subnets || []).length ? ' · přeskočeno: ' + lan.skipped_subnets.join(', ') : '')));
    lanBox.appendChild(lanRows.length ? table(['IP', 'MAC', 'Otevřené porty', 'Identifikace', 'V konfiguraci jako'], lanRows) : el('div', 'diag-empty', 'V LAN nebylo nalezeno žádné zařízení s otevřeným portem.'));
    box.appendChild(section('Zařízení nalezená v LAN', lanBox));

    const arpRows = (r.arp || []).map((a) => [a.ip, a.mac, a.dev, a.state]);
    box.appendChild(section('Tabulka sousedů (ARP) — ' + arpRows.length, arpRows.length ? table(['IP', 'MAC', 'Rozhraní', 'Stav'], arpRows) : null));
    const stepRows = Object.entries(r.steps || {}).map(([k, v]) => [k, badge(v.ok, v.ok ? 'OK' : fmt(v.error)), fmt(v.ms) + ' ms']);
    box.appendChild(section('Kroky diagnostiky', table(['Krok', 'Výsledek', 'Trvání'], stepRows)));
    box.scrollTop = 0;
  }

  function renderProgress(st) {
    const p = $('diag-progress');
    if (!st || !st.running) { p.hidden = true; return; }
    p.hidden = false;
    if (!p.firstChild) { p.appendChild(el('div', 'spinner small')); p.appendChild(el('div', 'diag-progress-text')); }
    const done = st.done || [];
    p.lastChild.textContent = 'Probíhá diagnostika… ' + (st.step_title || '') + ' (' + done.length + '/' + (st.steps || []).length + ', ' + fmt(st.elapsed_s) + ' s)';
  }

  async function fetchReport() {
    try {
      const r = await fetch('/api/diagnostics', { cache: 'no-store' });
      if (!r.ok) return;
      const d = await r.json();
      shownId = d.report ? d.report.id : null;
      renderReport(d.report);
    } catch (e) { /* server nedostupný — banner v app.js */ }
  }

  /** Volá app.js při každém snapshotu: progres + po dokončení běhu stáhne nový report. */
  function onState(st) {
    if (!visible || !st) return;
    const d = st.diagnostics || null;
    lastStatus = d;
    renderProgress(d);
    const lastId = d && d.last ? d.last.id : null;
    if (d && !d.running && lastId && lastId !== shownId) fetchReport();
    $('diag-state').textContent = d && d.running ? '● běží' : '';
    $('diag-rerun').hidden = !!(d && d.running) || askCode;
  }

  function msg(text, kind) { const m = $('diag-msg'); m.textContent = text || ''; m.className = 'service-msg' + (kind ? ' ' + kind : ''); }
  function setError(text) { const e = $('diag-error'); e.hidden = !text; e.textContent = text || ''; }
  function paintCode() { $('diag-code').textContent = code ? '●'.repeat(code.length) : ''; }
  function showAuth(on) { askCode = on; $('diag-auth').hidden = !on; $('diag-report').hidden = on; $('diag-rerun').hidden = on; if (on) { code = ''; paintCode(); setError(''); } }

  async function run(body) {
    if (busy) return;
    busy = true;
    msg('Spouštím diagnostiku…');
    const res = await deps.post('/api/diagnostics/run', body);
    busy = false;
    if (res && (res.ok || res.error === 'already_running')) {
      showAuth(false);
      msg(res.error === 'already_running' ? 'Diagnostika už běží.' : 'Diagnostika spuštěna — trvá cca 10–60 s.', 'ok');
      onState(deps.getState());
      return true;
    }
    const err = res ? (res.message || MG.i18n.errorSubtitle(res.error, res.locked_until) || res.error) : 'Chyba spojení.';
    if (askCode) setError(res && res.status === 403 && !res.message ? 'Neplatný kód.' : err); else msg(err, 'err');
    return false;
  }

  function submitCode() { const c = code.trim(); if (!c) { setError('Zadejte kód.'); return; } run({ code: c }); }
  function onChar(ch) { if (busy || code.length >= 32) return; code += ch; paintCode(); }
  function onBackspace() { if (busy) return; code = code.slice(0, -1); paintCode(); }
  function onClear() { if (busy) return; code = ''; paintCode(); }

  /** opts: { token? (servisní), askCode? (bez oprávnění → zadat kód), started? (běh už spuštěn přes /api/pin) } */
  function open(opts) {
    opts = opts || {};
    token = opts.token || null;
    visible = true;
    $('diag').hidden = false;
    msg('');
    shownId = null;
    showAuth(!!opts.askCode && !token && !opts.started);
    if (!askCode) fetchReport();
    if (token) run({ service_token: token });
    onState(deps.getState());
  }
  function close() { visible = false; $('diag').hidden = true; }

  function init(d) {
    deps = d;
    kb = MG.Keyboard.build($('diag-keys'), { mode: 'text', onChar, onBackspace, onEnter: submitCode, onClear, enterLabel: 'SPUSTIT' });
    $('diag-close').addEventListener('click', close);
    $('diag-close2').addEventListener('click', close);
    $('diag-rerun').addEventListener('click', () => run(token ? { service_token: token } : { code: code.trim() || '' }).then((ok) => { if (!ok && !token) showAuth(true); }));
  }

  return { init, open, close, onState, isVisible: () => visible, wantsKeys: () => visible && askCode,
    keys: { onChar, onBackspace, onEnter: submitCode, onClear, onEscape: close } };
})();
