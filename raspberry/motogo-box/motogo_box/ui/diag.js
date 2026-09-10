/* MotoGo24 kiosk — diagnostika pobočky: overlay s progresem, protokolem a detailním reportem (GET /api/diagnostics),
   spuštění kódem (POST /api/diagnostics/run {code}) nebo servisním tokenem. Vanilla JS, offline.
   Report = tvar dle CONTRACT.md §24: každý klíč může chybět (starší reporty bez `protocol` se vykreslí jen jako síťový detail). */
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
  const STATUS = { ok: ['ok', 'OK'], warn: ['warn', 'VAROVÁNÍ'], fail: ['bad', 'CHYBA'], skip: ['na', 'PŘESKOČENO'] };
  const stKey = (s) => (STATUS[s] ? s : 'skip');
  function sbadge(status) { const s = STATUS[stKey(status)]; return el('span', 'diag-badge ' + s[0], STATUS[status] ? s[1] : fmt(status)); }
  const arr = (v) => (Array.isArray(v) ? v : []);
  const obj = (v) => (v && typeof v === 'object' ? v : {});
  /** České množné číslo: plural(3, ['problém', 'problémy', 'problémů']) → „3 problémy“ */
  function plural(n, f) { n = Number(n) || 0; return n + ' ' + (n === 1 ? f[0] : n >= 2 && n <= 4 ? f[1] : f[2]); }
  function secs(v) {
    if (v == null) return '—';
    if (v < 90) return Math.round(v) + ' s';
    if (v < 3600) return Math.round(v / 60) + ' min';
    let h = Math.floor(v / 3600), m = Math.round((v % 3600) / 60);
    if (m === 60) { h += 1; m = 0; }   // 1 h 59 min 30 s → „2 h 0 min“, ne „1 h 60 min“
    return h + ' h ' + m + ' min';
  }
  const openClosed = (v) => (v === true ? 'zavřeno' : v === false ? 'otevřeno' : '—');
  const tri = (label, v) => badge(v, label + (v === true ? ' ✔' : v === false ? ' ✘' : ' —'));
  const COLOR = { red: 'červená', green: 'zelená', off: 'vypnuto' };

  /** PROTOKOL — sekce `protocol` z reportu (CONTRACT §24): badge stavu sekce + tabulka Kontrola | Stav | Zjištění | Co s tím. */
  function renderProtocol(proto) {
    const wrap = el('div', 'diag-proto');
    if (!proto.length) wrap.appendChild(el('div', 'diag-empty', 'Protokol je prázdný.'));
    proto.forEach((sec) => {
      sec = obj(sec);
      const items = arr(sec.items).map(obj);
      const cnt = { ok: 0, warn: 0, fail: 0, skip: 0 };
      items.forEach((it) => { cnt[stKey(it.status)]++; });
      const s = el('div', 'diag-proto-sec ' + stKey(sec.status));
      const h = el('div', 'diag-proto-head');
      h.appendChild(sbadge(sec.status));
      h.appendChild(el('span', 'diag-proto-title', fmt(sec.title || sec.key)));
      h.appendChild(el('span', 'diag-proto-cnt', [['ok', 'OK'], ['fail', null], ['warn', 'varování'], ['skip', 'přeskočeno']]
        .filter(([k]) => cnt[k]).map(([k, t]) => (t ? cnt[k] + ' ' + t : plural(cnt[k], ['chyba', 'chyby', 'chyb']))).join(' · ') || 'bez kontrol'));
      s.appendChild(h);
      if (items.length) {
        const t = el('table', 'diag-table diag-proto-table');
        const th = el('tr'); ['Kontrola', 'Stav', 'Zjištění', 'Co s tím'].forEach((x) => th.appendChild(el('th', '', x))); t.appendChild(th);
        items.forEach((it) => {
          const st = stKey(it.status), ok = st === 'ok';
          const row = el('tr', 'diag-item ' + st);
          row.appendChild(el('td', '', fmt(it.label || it.id)));
          const tdS = el('td'); tdS.appendChild(sbadge(it.status)); row.appendChild(tdS);
          const isBool = typeof it.value === 'boolean';   // bool hodnoty česky; u warn/fail už je ve zprávě → nepřidávat „(false)“
          const val = isBool ? (it.value ? 'ano' : 'ne') : (it.value != null && it.value !== '' ? String(it.value) : '');
          row.appendChild(el('td', '', ok ? (val || fmt(it.message)) : fmt(it.message) + (val && !isBool && val !== it.message ? ' (' + val + ')' : '')));
          row.appendChild(el('td', 'hint', (st === 'fail' || st === 'warn') && it.hint ? '→ ' + it.hint : ''));
          t.appendChild(row);
        });
        s.appendChild(t);
      }
      wrap.appendChild(s);
    });
    return wrap;
  }
  function kv(pairs) {
    const g = el('div', 'diag-kv');
    pairs.forEach(([k, v]) => { g.appendChild(el('span', 'k', k)); const s = el('span', 'v'); if (v instanceof Node) s.appendChild(v); else s.textContent = fmt(v); g.appendChild(s); });
    return g;
  }

  function renderReport(r) {
    const box = $('diag-report');
    box.textContent = '';
    if (!r) { box.appendChild(el('div', 'diag-empty', 'Zatím neproběhla žádná diagnostika.')); return; }
    const sm = obj(r.summary), checks = obj(sm.checks), proto = Array.isArray(r.protocol) ? r.protocol : null;
    const mode = r.mode || sm.mode || (proto ? 'full' : 'network');
    const nProb = checks.fail != null ? checks.fail : arr(sm.problems).length;
    const nWarn = checks.warn != null ? checks.warn : Array.isArray(sm.warnings) ? sm.warnings.length : null;
    const what = mode === 'network' ? 'Síť' : 'Pobočka';
    const head = el('div', 'diag-summary ' + (sm.ok ? (nWarn ? 'warn' : 'ok') : 'bad'));
    head.appendChild(el('div', 'diag-summary-title', sm.ok ? '✔ ' + what + ' je v pořádku' + (nWarn ? ' (' + plural(nWarn, ['varování', 'varování', 'varování']) + ')' : '')
      : '⚠ ' + plural(nProb, ['problém', 'problémy', 'problémů']) + (nWarn != null ? ', ' + plural(nWarn, ['varování', 'varování', 'varování']) : '')));
    const run = ['Běh ' + fmt(r.id), r.ts ? new Date(r.ts).toLocaleString('cs-CZ') : '—', fmt(r.duration_s) + ' s', 'spuštěno: ' + fmt(r.source),
      'režim: ' + (mode === 'network' ? 'jen síť' : 'kompletní')];
    if (mode !== 'network' && sm.zones_total != null) run.push('zóny OK ' + fmt(sm.zones_ok) + '/' + fmt(sm.zones_total) + (sm.zones_tested != null ? ' (testováno ' + sm.zones_tested + ')' : ''));
    run.push('moduly dostupné: ' + fmt(sm.devices_ok) + '/' + fmt(sm.devices_total), 'zařízení v LAN: ' + fmt(sm.hosts));
    if (checks.total != null) run.push('kontrol: ' + checks.total);
    head.appendChild(el('div', 'diag-summary-sub', run.join(' · ')));
    if (arr(sm.problems).length) { const ul = el('ul', 'diag-problems'); sm.problems.forEach((p) => ul.appendChild(el('li', '', p))); head.appendChild(ul); }
    box.appendChild(head);
    if (proto) box.appendChild(section('Protokol', renderProtocol(proto), 'diag-proto-wrap'));

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
    if (Array.isArray(r.zones)) {
      const zRows = r.zones.map(obj).map((z) => {
        const lock = obj(z.lock), sh = obj(z.shelly), red = sh.red ? obj(sh.red) : null, green = sh.green ? obj(sh.green) : null;
        const tests = el('div', 'diag-tests');
        if (z.tested) [['Světlo', z.light], ['Signál', z.signal], ['Audio', z.audio]].forEach(([l, v]) => tests.appendChild(tri(l, v)));
        else tests.appendChild(badge(null, 'přeskočeno' + (z.skipped_reason ? ': ' + z.skipped_reason : '')));
        const lockTxt = !lock.configured ? '—' : lock.module_online === false ? badge(false, 'modul offline')
          : lock.coil_off === false ? badge(false, 'relé SEPNUTÉ!') : lock.coil_off === true ? badge(true, 'v klidu') : badge(null, 'nezjištěno');
        const shTxt = !red && !green ? '—' : badge(sh.matches, 'R ' + (red ? (red.on ? 'zap' : 'vyp') : '—') + ' · G ' + (green ? (green.on ? 'zap' : 'vyp') : '—')
          + ' · má být ' + (COLOR[sh.expected] || fmt(sh.expected)) + (sh.matches === false ? ' — NESOUHLASÍ' : ''));
        const contact = el('div', 'diag-tests'); contact.appendChild(el('span', '', openClosed(z.contact_raw)));
        if (z.contact_consistent === false) contact.appendChild(badge(false, 'nesouhlasí s programem'));
        const probs = arr(z.io_problems).concat(arr(z.problems));
        return [fmt(z.zone) + ' · ' + fmt(z.label) + (z.kind ? ' (' + z.kind + ')' : ''), fmt(z.state) + (z.fault ? ' · FAULT' : '') + (z.session_active ? ' · aktivní relace' : ''),
          openClosed(z.door_closed), contact, tests, lockTxt, shTxt, probs.length ? probs.join('; ') : '—'];
      });
      const zt = zRows.length ? table(['Zóna', 'Stav', 'Dveře (program)', 'Kontakt (modul)', 'Test světlo / signál / audio', 'Zámek', 'Shelly signalizace', 'Problémy'], zRows) : null;
      if (zt) zt.classList.add('diag-zones');
      box.appendChild(section('Zóny a periferie', zt || el('div', 'diag-empty', 'Žádné zóny (nespárováno / bez HW mapy).')));
    }
    if (r.power && typeof r.power === 'object') {
      const p = r.power, v = obj(p.values);
      box.appendChild(section('Napájení (FV)', !p.configured ? el('div', 'diag-empty', 'Stavová URL napájení není nastavena (Velín → pobočka → power_status_url).')
        : kv([['URL', p.url], ['Stav', badge(p.ok, p.ok ? 'OK ' + fmt(p.ms) + ' ms' : fmt(p.error || (p.status != null ? 'HTTP ' + p.status : 'chyba')))], ['HTTP', p.status],
          ['Baterie', v.battery_soc != null ? v.battery_soc + ' %' : '—'], ['Napětí baterie', v.battery_voltage != null ? v.battery_voltage + ' V' : '—'],
          ['Výkon baterie', v.battery_power_w != null ? v.battery_power_w + ' W' : '—'], ['Výkon FV', v.pv_power_w != null ? v.pv_power_w + ' W' : '—'],
          ['Zátěž', v.load_power_w != null ? v.load_power_w + ' W' : '—'], ['Síť přítomna', yesno(v.grid_present)], ['Klíče odpovědi', arr(p.raw_keys).join(', ')]])));
    }
    if (Array.isArray(r.cameras)) {
      const cRows = r.cameras.map(obj).map((c) => [c.name, c.kind, c.url_kind, c.url, badge(c.ok, c.ok ? 'OK' + (c.status != null ? ' HTTP ' + c.status : '') : fmt(c.error || (c.status != null ? 'HTTP ' + c.status : 'chyba'))), fmt(c.ms) + ' ms', c.content_type]);
      box.appendChild(section('Kamery', cRows.length ? table(['Kamera', 'Typ', 'Druh', 'URL', 'Výsledek', 'Čas', 'Content-Type'], cRows) : el('div', 'diag-empty', 'Velín nepředal žádné kamery.')));
    }
    if (r.software && typeof r.software === 'object') {
      const sw = r.software, sv = obj(sw.services), au = obj(sw.audio), api = obj(sw.api), cc = obj(sw.code_cache), lu = sw.last_update ? obj(sw.last_update) : null;
      const svc = el('div', 'diag-tests');
      Object.keys(sv).forEach((k) => svc.appendChild(badge(sv[k] == null ? null : sv[k] === 'active', k + ': ' + fmt(sv[k]))));
      if (!Object.keys(sv).length) svc.textContent = '—';
      const swBox = el('div');
      swBox.appendChild(kv([['Verze', sw.version], ['Uptime programu', secs(sw.uptime_s)], ['Ready', yesno(sw.ready)], ['Konfigurace', sw.config_source], ['Služby', svc],
        ['Selhané jednotky', sw.failed_units], ['Health (stáří)', sw.health_age_s != null ? secs(sw.health_age_s) + (sw.health_age_s > 120 ? ' — služba neběží?' : '') : '—'],
        ['Přehrávač', badge(au.player_ok, au.player_ok ? 'mpv OK' : au.player_ok === false ? 'mpv NEBĚŽÍ' : '—')], ['Playlist / hudba', fmt(au.playlist_count) + ' / ' + fmt(au.music_files) + ' souborů'],
        ['Audio zařízení', au.device], ['Realtime', yesno(obj(sw.realtime).connected)], ['API online / spárováno', yesno(api.online) + ' / ' + yesno(api.paired)],
        ['Outbox / události', fmt(sw.outbox_pending) + ' / ' + fmt(sw.events_total)], ['Cache kódů', cc.saved_at ? fmt(cc.codes) + ' kódů, ' + fmt(cc.service_codes) + ' servisních, stáří ' + secs(cc.age_s) : '—'],
        ['Zámek PIN do', sw.lockout_until ? new Date(sw.lockout_until).toLocaleString('cs-CZ') : '—'], ['Restart vyžadován', yesno(sw.reboot_required)],
        ['Poslední aktualizace', lu ? fmt(lu.kind) + ' ' + fmt(lu.state) + (lu.finished_at || lu.started_at ? ' (' + fmt(lu.finished_at || lu.started_at) + ')' : '') + (lu.error ? ' — ' + lu.error : '') : '—']]));
      if (arr(sw.config_problems).length) { swBox.appendChild(el('div', 'diag-sub', 'Problémy konfigurace')); const ul = el('ul', 'diag-problems'); sw.config_problems.forEach((p) => ul.appendChild(el('li', '', p))); swBox.appendChild(ul); }
      if (arr(sw.recent_errors).length) { swBox.appendChild(el('div', 'diag-sub', 'Poslední chyby (24 h)'));
        swBox.appendChild(table(['Čas', 'Typ', 'Zpráva'], sw.recent_errors.map(obj).map((e) => [e.ts ? new Date(e.ts).toLocaleString('cs-CZ') : '—', e.kind, e.message]))); }
      box.appendChild(section('Software', swBox));
    }
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
    const res = await deps.post('/api/diagnostics/run', Object.assign({ mode: 'full' }, body || {}));
    busy = false;
    if (res && (res.ok || res.error === 'already_running')) {
      showAuth(false);
      msg(res.error === 'already_running' ? 'Diagnostika už běží.' : 'Diagnostika spuštěna — trvá 1–4 min.', 'ok');
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

  window.__diagRender = renderReport;   // jen pro statický náhled/screenshot (harness), appka to nepoužívá
  return { init, open, close, onState, isVisible: () => visible, wantsKeys: () => visible && askCode,
    keys: { onChar, onBackspace, onEnter: submitCode, onClear, onEscape: close } };
})();
