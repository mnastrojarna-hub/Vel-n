"""Protokol diagnostiky pobočky (kontrakt §24): `build_protocol(report)` = seznam sekcí s položkami
`{id, label, status ok|warn|fail|skip, value, message, hint}` — JEDINÝ formát, který Velín i displej
vykreslují jako protokol; `build_summary(report, protocol)` = souhrn (zpětně kompatibilní klíče
ok/problems/hosts/internet/lte/devices_ok/devices_total + warnings/checks/zones_*/mode).
Texty česky, konkrétně (zařízení, kanál, IP) — technik z nich pozná, kde je problém a co s tím.
"""
from __future__ import annotations

from typing import Any

from .diag_hints import hint

RANK = {"skip": 0, "ok": 1, "warn": 2, "fail": 3}
STEP_TITLES = {"system": "Systém", "interfaces": "Síťová rozhraní", "lte": "LTE modem", "internet": "Internet a DNS",
               "supabase": "Spojení s Velínem", "devices": "Konfigurovaná zařízení", "software": "Software",
               "config": "Konfigurace", "zones": "Zóny a periferie", "power": "Napájení (FV)", "cameras": "Kamery",
               "lan": "Scan LAN", "arp": "Tabulka sousedů (ARP)", "summary": "Vyhodnocení"}
SKIP_CZ = {"session_active": "v kóji běží relace", "zone_test_disabled": "HW test zón je vypnutý (diagnostics.zone_test)",
           "io_offline": "I/O modul zóny je offline", "fault": "zóna je v poruše", "not_ready": "jednotka není připravena (start/přestavba)",
           "timeout": "došel časový limit diagnostiky"}
ROLE_CZ = {"light": "světlo", "signal": "signalizace", "audio": "audio", "contact": "dveřní kontakt", "lock": "zámek",
           "shelly": "Shelly signalizace", "fault": "porucha", "io": "I/O", "test": "HW test"}
def item(id_: str, label: str, status: str, value: Any = None, message: str = "", hint_: str | None = None) -> dict:
    d = {"id": id_, "label": label, "status": status if status in RANK else "warn", "value": value, "message": message}
    if d["status"] in ("warn", "fail"):
        d["hint"] = hint_ or ""
    return d


def section_status(items: list[dict]) -> str:
    """Nejhorší ze svých položek (fail > warn > ok); skip neovlivňuje; bez položek = skip."""
    ranks = [RANK.get(i.get("status"), 0) for i in items if i.get("status") != "skip"]
    return {3: "fail", 2: "warn", 1: "ok"}.get(max(ranks) if ranks else 0, "skip")


def section(key: str, title: str, items: list[dict]) -> dict:
    return {"key": key, "title": title, "status": section_status(items), "items": items}


def _missing(key: str, title: str, r: dict, step: str) -> dict | None:
    """Sekce pro krok, který neběžel (režim network) → None; běžel a selhal → 1 položka skip."""
    if step not in r:
        return None
    if r.get(step) is None:
        st = (r.get("steps") or {}).get(step) or {}
        return section(key, title, [item(f"{key}.step", title, "skip", None, f"Krok neproběhl ({st.get('error') or 'chyba'}).")])
    return section(key, title, [])


# ─── sekce ───────────────────────────────────────────────────────────────────
def _system(r: dict) -> dict:
    s = r.get("system") or {}
    m = s.get("metrics") or {}
    it: list[dict] = [item("system.version", "Verze programu", "ok", r.get("version")),
                      item("system.uptime", "Běh programu", "ok", f"{int(s.get('controller_uptime_s') or 0) // 60} min")]
    t, th = m.get("cpu_temp"), m.get("throttled")
    it.append(item("system.cpu_temp", "Teplota CPU", "fail" if (t or 0) > 85 else "warn" if (t or 0) > 75 else "ok" if t is not None else "skip",
                   f"{t} °C" if t is not None else None, "" if (t or 0) <= 75 else f"Vysoká teplota CPU {t} °C.", hint("cpu_temp")))
    it.append(item("system.throttled", "Napájení / throttling", "ok" if th in (None, "0x0") else "warn", th,
                   "" if th in (None, "0x0") else f"Raspberry hlásí throttling/podpětí ({th}).", hint("throttled")))
    d = m.get("disk_free_pct")
    it.append(item("system.disk", "Volné místo na disku", "skip" if d is None else "fail" if d < 10 else "warn" if d < 20 else "ok",
                   None if d is None else f"{d} %", "" if d is None or d >= 20 else f"Málo místa na disku ({d} % volných).", hint("disk")))
    mem = m.get("mem_free_pct")
    it.append(item("system.mem", "Volná paměť", "skip" if mem is None else "warn" if mem < 10 else "ok", None if mem is None else f"{mem} %",
                   "" if mem is None or mem >= 10 else f"Málo volné paměti ({mem} %).", hint("mem")))
    ntp = s.get("ntp_synced")
    it.append(item("system.ntp", "Synchronizace času (NTP)", "skip" if ntp is None else "ok" if ntp else "fail", ntp,
                   "" if ntp else "Čas není synchronizovaný (NTP) — platnost kódů se může vyhodnotit špatně.", hint("ntp")))
    it.append(item("system.ready", "Jednotka připravena", "ok" if s.get("ready") else "warn", s.get("ready"),
                   "" if s.get("ready") else "Jednotka není připravena (start / přestavba HW).", hint("not_ready")))
    cp = s.get("config_problems") or []
    it.append(item("system.config_problems", "Konfigurace HW", "fail" if cp else "ok", f"{len(cp)} problémů" if cp else "bez chyb",
                   "; ".join(cp[:5]), hint("config_problems")))
    return section("system", "Řídicí jednotka", it)


def _software(r: dict) -> dict | None:
    if (sec := _missing("software", "Program a služby", r, "software")) is None or sec["items"]:
        return sec
    s = r["software"]
    it: list[dict] = []
    for unit, st in (s.get("services") or {}).items():
        it.append(item(f"software.service.{unit}", f"Služba {unit}", "skip" if st is None else "ok" if st == "active" else "fail",
                       st or "nelze zjistit", "" if st in (None, "active") else f"Služba {unit} je ve stavu {st}.", hint("service", unit=unit)))
    fu = s.get("failed_units")
    it.append(item("software.failed_units", "Selhané systemd jednotky", "skip" if fu is None else "warn" if fu else "ok", fu,
                   f"{fu} selhaných jednotek systemd." if fu else "", hint("failed_units")))
    ha = s.get("health_age_s")
    young = int(s.get("uptime_s") or 0) < 120
    it.append(item("software.health", "Health služba (LTE/internet)", "ok" if ha is not None and ha <= 120 else "skip" if young else "fail",
                   None if ha is None else f"před {int(ha)} s", "" if (ha is not None and ha <= 120) or young else
                   "Health služba neposílá stav (poslední " + (f"před {int(ha)} s" if ha is not None else "nikdy") + ").", hint("health")))
    a = s.get("audio") or {}
    it.append(item("software.mpv", "Přehrávač mpv", "ok" if a.get("player_ok") else "fail", a.get("device") or "výchozí zařízení",
                   "" if a.get("player_ok") else "Přehrávač mpv neběží — hudba a tón nefungují.", hint("mpv")))
    mf, pc = a.get("music_files"), int(a.get("playlist_count") or 0)
    it.append(item("software.music", "Hudba (soubory / playlist)", "skip" if mf is None else "warn" if not mf or not pc else "ok",
                   f"{mf} souborů, {pc} v playlistu", "" if mf and pc else "Hudba chybí nebo playlist je prázdný.", hint("music")))
    ob = s.get("outbox_pending")
    it.append(item("software.outbox", "Fronta neodeslaných RPC", "skip" if ob is None else "warn" if ob else "ok", ob,
                   f"{ob} RPC čeká na odeslání do Velína." if ob else "", hint("outbox")))
    cc = s.get("code_cache") or {}
    age, paired = cc.get("age_s"), (s.get("api") or {}).get("paired")
    it.append(item("software.code_cache", "Cache kódů (offline ověření)", "ok" if age is not None and age <= 86400 else "skip" if not paired else "warn",
                   None if age is None else f"{cc.get('codes')} kódů, {cc.get('service_codes')} servisních, stáří {int(age) // 60} min",
                   "" if age is not None and age <= 86400 else "Cache kódů chybí nebo je starší než 24 h.", hint("code_cache")))
    lo = s.get("lockout_until")
    it.append(item("software.lockout", "PIN lockout", "warn" if lo else "ok", lo, f"PIN lockout aktivní do {lo}." if lo else "", hint("lockout")))
    re_ = s.get("recent_errors") or []
    it.append(item("software.errors", "Chyby za 24 h", "warn" if re_ else "ok", len(re_),
                   f"Poslední: {re_[0].get('kind')} — {re_[0].get('message')}" if re_ else "", hint("errors")))
    lu = s.get("last_update")
    lus = str((lu or {}).get("state") or "")
    it.append(item("software.update", "Poslední aktualizace", "skip" if not lu else "warn" if lus in ("failed", "error") else "ok",
                   f"{(lu or {}).get('kind') or ''} {lus} {(lu or {}).get('finished_at') or (lu or {}).get('ts') or ''}".strip() or None,
                   "Poslední aktualizace selhala." if lus in ("failed", "error") else "", hint("update")))
    it.append(item("software.reboot_required", "Restart OS potřebný", "warn" if s.get("reboot_required") else "ok", s.get("reboot_required"),
                   "OS vyžaduje restart po záplatách." if s.get("reboot_required") else "", hint("reboot_required")))
    return section("software", "Program a služby", it)


def _network(r: dict) -> dict:
    ifc = r.get("interfaces") or {}
    it: list[dict] = []
    for i in ifc.get("interfaces") or []:
        name = str(i.get("name") or "?")
        if name == "lo":
            continue
        addrs = ", ".join(f"{a.get('addr')}/{a.get('prefix')}" for a in i.get("ipv4") or [] if a.get("addr"))
        bad = name.startswith(("eth", "wwan", "wlan", "ppp")) and not addrs
        it.append(item(f"network.iface.{name}", f"Rozhraní {name}", "warn" if bad else "ok", addrs or i.get("state"),
                       f"Rozhraní {name} nemá IPv4 adresu (stav {i.get('state')})." if bad else "", hint("iface_down", name=name)))
    routes = ifc.get("default_routes") or []
    dev = str(routes[0].get("dev") or "") if routes else ""
    it.append(item("network.gateway", "Výchozí brána", "fail" if not routes else "warn" if dev.startswith("eth") else "ok",
                   f"{routes[0].get('gateway') or routes[0].get('via') or '?'} přes {dev}" if routes else None,
                   "Chybí výchozí brána (žádná default route) — internet nemůže fungovat." if not routes else
                   f"Výchozí brána vede přes {dev} (LAN modulů) místo LTE." if dev.startswith("eth") else "",
                   hint("gateway_missing" if not routes else "gateway_eth")))
    dns = ifc.get("dns") or []
    it.append(item("network.dns", "DNS servery", "ok" if dns else "fail", ", ".join(map(str, dns)) or None,
                   "" if dns else "Není nastaven žádný DNS server (/etc/resolv.conf).", hint("dns_missing")))
    return section("network", "Síť", it)


def _lte(r: dict) -> dict:
    lte = r.get("lte")
    if not isinstance(lte, dict):
        return section("lte", "LTE modem", [item("lte.step", "LTE modem", "skip", None, "Krok neproběhl.")])
    st = lte.get("state")
    ok = st == "connected"
    val = ", ".join(str(x) for x in (lte.get("operator"), lte.get("signal_quality") and f"signál {lte.get('signal_quality')} %",
                                     lte.get("access_tech")) if x)
    msg = "" if ok else "ModemManager nevidí žádný modem (mmcli) — LTE nedostupné." if st == "unavailable" else \
        f"LTE modem není připojen (stav: {st}, NM: {lte.get('nm_state')})."
    return section("lte", "LTE", [item("lte.state", "Stav LTE modemu", "ok" if ok else "fail", val or st, msg, hint("lte"))])


def _internet(r: dict) -> dict:
    inet = r.get("internet")
    if not isinstance(inet, dict):
        return section("internet", "Internet", [item("internet.step", "Internet", "skip", None, "Krok neproběhl.")])
    it: list[dict] = []
    for d in inet.get("dns") or []:
        ok = bool(d.get("addresses"))
        it.append(item(f"internet.dns.{d.get('host')}", f"DNS {d.get('host')}", "ok" if ok else "fail", ", ".join(d.get("addresses") or []) or None,
                       "" if ok else f"DNS nepřeloží {d.get('host')} ({d.get('error') or 'bez odpovědi'}).", hint("internet")))
    tcp = inet.get("tcp") or {}
    it.append(item("internet.tcp", f"TCP {tcp.get('host')}:{tcp.get('port')}", "ok" if tcp.get("open") else "fail",
                   f"{tcp.get('ms')} ms" if tcp.get("open") else tcp.get("error"),
                   "" if tcp.get("open") else f"TCP spojení na {tcp.get('host')}:{tcp.get('port')} selhalo.", hint("internet")))
    for p in inet.get("http") or []:
        ok = p.get("status") is not None and p["status"] < 500
        it.append(item(f"internet.http.{p.get('url')}", f"HTTP {p.get('url')}", "ok" if ok else "fail",
                       f"{p.get('status')} / {p.get('ms')} ms" if ok else p.get("error") or p.get("status"),
                       "" if ok else f"HTTP sonda {p.get('url')} selhala ({p.get('error') or p.get('status')}).", hint("internet")))
    it.append(item("internet.ok", "Internet celkem", "ok" if inet.get("ok") else "fail", inet.get("ok"),
                   "" if inet.get("ok") else "Internet nedostupný (sondy selhaly).", hint("internet")))
    return section("internet", "Internet", it)


def _velin(r: dict) -> dict:
    sb = r.get("supabase") or {}
    paired = bool(sb.get("paired", r.get("paired")))
    it = [item("velin.paired", "Párování s Velínem", "ok" if paired else "fail", sb.get("device_id") or r.get("device_id"),
               "" if paired else "Zařízení není spárované s Velínem (report se odešle po spárování).", hint("not_paired"))]
    if paired:
        ok = sb.get("ok")
        it.append(item("velin.heartbeat", "Heartbeat (kiosk_heartbeat)", "ok" if ok else "skip" if ok is None else "fail",
                       f"{sb.get('ms')} ms, pobočka {sb.get('branch_name')}" if ok else sb.get("error"),
                       "" if ok or ok is None else "Velín (Supabase) neodpovídá na heartbeat.", hint("heartbeat")))
    rt = ((r.get("software") or {}).get("realtime") or {}).get("connected") if isinstance(r.get("software"), dict) else None
    if rt is not None:
        it.append(item("velin.realtime", "Realtime kanál", "ok" if rt else "warn", rt, "" if rt else "Realtime kanál není spojen.", hint("realtime")))
    return section("velin", "Spojení s Velínem", it)


def _modules(r: dict) -> dict:
    it: list[dict] = []
    by_ip: dict[str, list[str]] = {}
    for d in r.get("devices") or []:
        name, typ, host, port = d.get("name"), d.get("type"), d.get("host"), d.get("port")
        by_ip.setdefault(f"{host}:{port}", []).append(str(name))
        g = (d.get("identified") or {}).get("guess") if typ != "shelly_rgbww" else None
        hk = "shelly_unreachable" if typ == "shelly_rgbww" else "modbus_unreachable"
        if not d.get("reachable"):
            st, msg = "fail", f"Zařízení {name} ({typ}) na {host}:{port} neodpovídá ({d.get('error') or 'timeout'})."
        elif typ == "shelly_rgbww" and not d.get("identified"):
            st, msg = "fail", f"{name} na {host} neodpovídá jako Shelly (RPC Shelly.GetDeviceInfo)."
        elif typ in ("wav645", "wav617") and g is None:
            st, msg, hk = "warn", f"{name} na {host} má otevřený port {port}, ale nemluví Modbus (jiné zařízení?).", "device_mismatch"
        elif typ in ("wav645", "wav617") and g not in (typ, "modbus"):
            st, msg, hk = "fail", f"{name} je nastaveno jako {typ}, ale na {host} odpovídá {g}.", "device_mismatch"
        elif d.get("online") is False:
            st, msg, hk = "warn", f"{name} odpovídá na síti, ale program ho má offline / v obnově.", "module_offline_in_program"
        else:
            st, msg = "ok", ""
        val = f"ping {d.get('ping_ms')} ms, TCP {d.get('ms')} ms" if d.get("reachable") else d.get("error")
        it.append(item(f"modules.{name}", f"{name} ({typ}, {host})", st, val, msg, hint(hk, name=name, host=host, type=typ)))
    for ip, names in by_ip.items():
        if len(names) > 1:
            it.append(item(f"modules.ip.{ip}", f"Adresa {ip}", "fail", ", ".join(names), f"Více zařízení sdílí adresu {ip}: {', '.join(names)}.", hint("ip_conflict")))
    return section("modules", "Moduly Waveshare / Shelly", it)


def _config(r: dict) -> dict | None:
    if (sec := _missing("config", "Konfigurace pobočky", r, "config")) is None or sec["items"]:
        return sec
    c = r["config"]
    zt = int(c.get("zones_total") or 0)
    it = [item("config.zones", "Zóny / dveře s HW mapou", "ok" if zt else "fail", f"{zt} zón ({c.get('source')})",
               "" if zt else "Žádné zóny (nespárováno / bez HW mapy).", hint("no_zones"))]
    for z in c.get("zones") or []:
        for role in z.get("missing") or []:
            it.append(item(f"config.zone.{z.get('zone')}.{role}", f"{z.get('label')} — role {role}", "fail" if role in ("lock", "contact") else "warn",
                           None, f"Zóna {z.get('zone')}: chybí role {role} v HW mapě.", hint("missing_role", role=role, zone=z.get("zone"))))
    for lbl in c.get("doors_without_hw") or []:
        it.append(item(f"config.door.{lbl}", f"Dveře {lbl}", "warn", None, f"Dveře {lbl} ve Velíně nemají HW mapu.", hint("door_without_hw", label=lbl)))
    for i, dup in enumerate(c.get("duplicates") or []):
        it.append(item(f"config.duplicate.{i}", "Duplicitní kanál", "fail", None, dup, hint("duplicate")))
    t = c.get("timings") or {}
    it.append(item("config.timings", "Časování", "ok", f"pulz {t.get('lock_pulse_ms')} ms, otevření {t.get('door_open_timeout_s')} s, "
                   f"relace {t.get('maximum_session_s')} s, světlo {t.get('light_after_close_s')} s, hudba {t.get('music_after_close_s')} s"))
    for i, tp in enumerate(c.get("timings_problems") or []):
        it.append(item(f"config.timing.{i}", "Časování mimo rozsah", "warn", None, tp, hint("timings")))
    return section("config", "Konfigurace pobočky", it)


def _zones(r: dict) -> dict | None:
    if (sec := _missing("zones", "Zóny a periferie", r, "zones")) is None or sec["items"]:
        return sec
    zs = r["zones"]
    if not zs:
        return section("zones", "Zóny a periferie", [item("zones.none", "Zóny", "warn", 0, "Žádné zóny (nespárováno / bez HW mapy).", hint("no_zones"))])
    it: list[dict] = []
    for z in zs:
        n, label, f = z.get("zone"), z.get("label") or f"Zóna {z.get('zone')}", z.get("findings") or []
        worst = max((RANK.get(x.get("status"), 0) for x in f), default=0)
        st = {3: "fail", 2: "warn"}.get(worst) or ("skip" if z.get("skipped_reason") else "ok")
        door = {True: "zavřeno", False: "otevřeno"}.get(z.get("door_closed"), "?")
        tests = " ".join(f"{k} {'✔' if v else '✘' if v is False else '–'}" for k, v in (("světlo", z.get("light")), ("zelená", z.get("signal")), ("tón", z.get("audio"))))
        val = f"{z.get('state')}, dveře {door}" + (f", test: {tests}" if z.get("tested") else "")
        msg = f"{len(f)} nálezů: " + ", ".join(dict.fromkeys(ROLE_CZ.get(x.get("key"), str(x.get("key"))) for x in f)) if f else \
            f"Test přeskočen: {SKIP_CZ.get(z.get('skipped_reason'), z.get('skipped_reason'))}." if z.get("skipped_reason") else "Vše v pořádku."
        # rada souhrnné položky = rada prvního nálezu (včetně {dev}/{ch} u světla — jinak by zůstaly složené závorky)
        it.append({**item(f"zone.{n}", label, st, val, msg,
                          hint(f"zone.{f[0].get('key')}", dev=f[0].get("dev") or "?", ch=f[0].get("ch") or "?") if f else None), "group": True})
        used: dict[str, int] = {}
        for x in f:
            key = str(x.get("key") or "problem")
            used[key] = used.get(key, 0) + 1
            it.append(item(f"zone.{n}.{key}" + (f".{used[key]}" if used[key] > 1 else ""), f"{label} — {ROLE_CZ.get(key, key)}", x.get("status") or "warn",
                           None, str(x.get("message") or ""), hint(f"zone.{key}", dev=x.get("dev") or "?", ch=x.get("ch") or "?")))
    return section("zones", "Zóny a periferie", it)


def _power(r: dict) -> dict | None:
    if (sec := _missing("power", "Napájení (FV)", r, "power")) is None or sec["items"]:
        return sec
    p = r["power"]
    if not p.get("configured"):
        return section("power", "Napájení (FV)", [item("power.url", "Měnič / monitor FV", "skip", None, "Nenastaveno (power_status_url pobočky).")])
    v = p.get("values") or {}
    it = [item("power.url", "Měnič / monitor FV", "ok" if p.get("ok") else "fail", f"HTTP {p.get('status')} / {p.get('ms')} ms" if p.get("ok") else p.get("error"),
               "" if p.get("ok") else f"Stav napájení nelze stáhnout z {p.get('url')} ({p.get('error')}).", hint("power"))]
    if p.get("ok"):
        soc = v.get("battery_soc")
        try:
            soc_f = float(soc) if soc is not None else None
        except (TypeError, ValueError):
            soc_f = None
        it.append(item("power.soc", "Baterie (SOC)", "skip" if soc_f is None else "warn" if soc_f < 20 else "ok", None if soc_f is None else f"{soc_f} %",
                       "Nízké nabití baterie." if soc_f is not None and soc_f < 20 else "", hint("power_soc")))
        it.append(item("power.values", "Hodnoty", "ok", ", ".join(f"{k} {val}" for k, val in v.items() if val is not None) or "žádné známé klíče"))
    return section("power", "Napájení (FV)", it)


def _cameras(r: dict) -> dict | None:
    if (sec := _missing("cameras", "Kamery", r, "cameras")) is None or sec["items"]:
        return sec
    cams = r["cameras"]
    if not cams:
        return section("cameras", "Kamery", [item("cameras.none", "Kamery", "skip", 0, "Velín nepředal žádné kamery.")])
    it = [item(f"camera.{c.get('name')}.{c.get('url_kind')}", f"Kamera {c.get('name')} — {c.get('url_kind')}", "ok" if c.get("ok") else "fail",
               f"HTTP {c.get('status')} / {c.get('ms')} ms" if c.get("ok") else c.get("error"),
               "" if c.get("ok") else f"Kamera {c.get('name')} ({c.get('url_kind')}) neodpovídá: {c.get('error')}.",
               hint("camera", name=c.get("name"), url_kind=c.get("url_kind"))) for c in cams]
    return section("cameras", "Kamery", it)


def _lan(r: dict) -> dict:
    lan = r.get("lan") or {}
    hosts = lan.get("hosts") or []
    it = [item("lan.hosts", "Zařízení v LAN", "ok", f"{len(hosts)} zařízení ({', '.join(lan.get('subnets') or []) or 'bez podsítě'})")]
    for h in hosts:
        if not h.get("configured_as") and (h.get("modbus") or h.get("shelly")):
            it.append(item(f"lan.unknown.{h.get('ip')}", f"Neznámé zařízení {h.get('ip')}", "warn", h.get("mac"),
                           f"{h.get('ip')} je {'Shelly' if h.get('shelly') else 'Modbus'} mimo HW mapu.", hint("lan_unknown")))
    for x in lan.get("skipped") or []:
        if x.get("reason") != "wan":
            it.append(item(f"lan.subnet.{x.get('subnet')}", f"Podsíť {x.get('subnet')}", "warn", None, "Přeskočená podsíť (příliš velká / neplatná).", hint("lan_subnet")))
    return section("lan", "Ostatní zařízení v LAN", it)


def _steps(r: dict) -> dict:
    it = [item(f"step.{n}", STEP_TITLES.get(n, n), "ok" if st.get("ok") else "warn", f"{st.get('ms')} ms",
               "" if st.get("ok") else f"Krok „{STEP_TITLES.get(n, n)}“ selhal: {st.get('error')}" + (" (částečný výsledek)" if st.get("partial") else ""), hint("step"))
          for n, st in (r.get("steps") or {}).items()]
    return section("steps", "Průběh diagnostiky", it)


def build_protocol(report: dict) -> list[dict]:
    r = report or {}
    out = []
    for fn in (_system, _software, _network, _lte, _internet, _velin, _modules, _config, _zones, _power, _cameras, _lan, _steps):
        try:
            sec = fn(r)
        except Exception as exc:  # noqa: BLE001 — vadná data jednoho kroku nesmí shodit protokol
            sec = section(fn.__name__.strip("_"), fn.__name__.strip("_"), [item(f"{fn.__name__.strip('_')}.error", "Sekce", "warn", None,
                                                                                f"Vyhodnocení selhalo: {type(exc).__name__}: {str(exc)[:120]}", hint("step"))])
        if sec is not None:
            out.append(sec)
    return out


def build_summary(report: dict, protocol: list[dict]) -> dict:
    r = report or {}
    items = [(s, i) for s in protocol for i in s.get("items") or [] if not i.get("group")]   # souhrn zóny = skupina, ne kontrola
    checks = {k: sum(1 for _, i in items if i.get("status") == k) for k in ("ok", "warn", "fail", "skip")}
    checks["total"] = len(items)
    problems = [f"{i.get('label')}: {i.get('message') or 'problém'}" for _, i in items if i.get("status") == "fail"]
    warnings = [f"{i.get('label')}: {i.get('message') or 'varování'}" for _, i in items if i.get("status") == "warn"]
    zs = r.get("zones") if isinstance(r.get("zones"), list) else []
    lan, inet, lte, cfg = (r.get(k) or {} for k in ("lan", "internet", "lte", "config"))
    zones_total = len(zs)
    if ((r.get("steps") or {}).get("zones") or {}).get("error") == "timeout":      # krok nedoběhl → celkem zón z konfigurace
        zones_total = max(zones_total, int(cfg.get("zones_total") or 0))
    return {"ok": not problems, "problems": problems, "warnings": warnings, "checks": checks, "mode": r.get("mode") or "network",
            "zones_total": zones_total, "zones_tested": sum(1 for z in zs if z.get("tested")),
            "zones_ok": sum(1 for z in zs if not any(f.get("status") == "fail" for f in z.get("findings") or [])),
            "hosts": len(lan.get("hosts") or []), "internet": bool(inet.get("ok")), "lte": lte.get("state"),
            "devices_ok": sum(1 for d in r.get("devices") or [] if d.get("reachable")), "devices_total": len(r.get("devices") or []),
            "sections": {s.get("key"): s.get("status") for s in protocol}}
