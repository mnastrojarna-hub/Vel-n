"""Protokol diagnostiky pobočky (kontrakt §24): `build_protocol(report)` = seznam sekcí s položkami
`{id, label, status ok|warn|fail|skip, value, message, hint}` — JEDINÝ formát, který Velín i displej
vykreslují jako protokol; `build_summary(report, protocol)` = souhrn (zpětně kompatibilní klíče
ok/problems/hosts/internet/lte/devices_ok/devices_total + warnings/checks/zones_*/mode).
Texty česky, konkrétně (zařízení, kanál, IP) — technik z nich pozná, kde je problém a co s tím.
Venek (zóna bez dveří): položky a `summary.outdoor` staví `diag_outdoor.py` (lokální import — cyklus).
"""
from __future__ import annotations

from typing import Any

from .diag_hints import hint

RANK = {"skip": 0, "ok": 1, "warn": 2, "fail": 3}
STEP_TITLES = {"system": "Systém", "interfaces": "Síťová rozhraní", "lte": "LTE modem", "internet": "Internet a DNS",
               "supabase": "Spojení s Velínem", "devices": "Konfigurovaná zařízení", "provision": "Automatické zřízení modulů",
               "software": "Software",
               "config": "Konfigurace", "zones": "Zóny a periferie", "power": "Napájení (FV)", "cameras": "Kamery",
               "netlog": "Historie sítě a logy", "lan": "Scan LAN", "arp": "Tabulka sousedů (ARP)", "summary": "Vyhodnocení"}
SKIP_CZ = {"session_active": "v kóji běží relace", "zone_test_disabled": "HW test zón je vypnutý (diagnostics.zone_test)",
           "io_offline": "I/O modul zóny je offline", "fault": "zóna je v poruše", "not_ready": "jednotka není připravena (start/přestavba)",
           "timeout": "došel časový limit diagnostiky"}
ROLE_CZ = {"light": "světlo", "signal": "signalizace", "audio": "audio", "contact": "dveřní kontakt", "lock": "zámek",
           "shelly": "Shelly signalizace", "fault": "porucha", "io": "I/O", "test": "HW test"}


def _outdoor():
    from . import diag_outdoor      # lokální import — diag_outdoor používá item/RANK/SKIP_CZ odtud
    return diag_outdoor


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
    # Internet jde VÝHRADNĚ přes LTE (wwan0/usb0). Výchozí trasa přes eth0 = chyba: kabelem internet není, trasa
    # přebije LTE a pošle provoz do prázdna (zrušená „záložní brána kabelem", 2026-09-26) — health ji sám maže.
    foreign = [str(r.get("dev")) for r in routes if r.get("dev") and str(r.get("dev")).startswith(("eth", "en"))]
    wifi = [r for r in routes if str(r.get("dev", "")).startswith("wl")]
    lte_route = any(str(r.get("dev", "")).startswith(("wwan", "usb", "ppp")) for r in routes)
    it.append(item("network.gateway", "Výchozí brána",
                   "fail" if not routes or foreign else "warn" if wifi and not lte_route else "ok",
                   f"{routes[0].get('gateway') or routes[0].get('via') or '?'} přes {dev}" if routes else None,
                   "Chybí výchozí brána (žádná default route) — LTE nemá trasu, internet nemůže fungovat." if not routes else
                   f"Výchozí trasa přes {', '.join(foreign)} blokuje LTE — kabelem internet není." if foreign else
                   "Internet jde přes Wi-Fi (wlan0), LTE trasa chybí — na pobočce Wi-Fi není, tohle je stav při testu mimo pobočku."
                   if wifi and not lte_route else "",
                   hint("gateway_missing") if not routes else hint("gateway_eth") if foreign
                   else hint("gateway_wifi") if wifi and not lte_route else None))
    dns = ifc.get("dns") or []
    it.append(item("network.dns", "DNS servery", "ok" if dns else "fail", ", ".join(map(str, dns)) or None,
                   "" if dns else "Není nastaven žádný DNS server (/etc/resolv.conf).", hint("dns_missing")))
    return section("network", "Síť", it)


def _lte(r: dict) -> dict:
    lte = r.get("lte")
    if not isinstance(lte, dict):
        return section("lte", "LTE modem", [item("lte.step", "LTE modem", "skip", None, "Krok neproběhl.")])
    st = lte.get("state")
    inet_ok = bool((r.get("internet") or {}).get("ok")) if isinstance(r.get("internet"), dict) else False
    mode, usb_mode, ipv4, iface = lte.get("mode"), lte.get("usb_mode"), lte.get("ipv4"), lte.get("iface")
    it: list[dict] = []
    if mode == "rndis":
        # RNDIS (2026-09-26): ModemManager neběží schválně — zdraví = rozhraní usb0 má adresu (+ modem s PID 9011 na USB)
        ok = bool(ipv4)
        it.append(item("lte.state", "Stav LTE modemu (RNDIS)", "ok" if ok else "fail",
                       f"{iface} {ipv4}" if ok else f"{iface} bez adresy",
                       "" if ok else "Modem je v režimu RNDIS, ale síťová karta modemu nemá IPv4 — datové spojení nenavázáno.",
                       None if ok else hint("rndis_no_ip")))
    else:
        ok = st == "connected"
        val = ", ".join(str(x) for x in (lte.get("operator"), lte.get("signal_quality") and f"signál {lte.get('signal_quality')} %",
                                         lte.get("access_tech")) if x)
        if ok:
            msg, status, h = "", "ok", None
        elif st == "unavailable" and usb_mode is not None:
            # modem NA USB JE, ale ModemManager ho nevidí = mrtvý QMI kanál (kernel -71) — vždy chyba, i když internet jde Wi-Fi
            msg, status, h = ("Modem je na USB (PID 9001), ale ModemManager ho nevidí — QMI kanál je mrtvý (známá závada "
                              "SIM7600, kernel -71); health dělá USB reset."), "fail", hint("modem_gone")
        elif st == "unavailable":
            msg = "Žádný LTE modem (ModemManager ani USB)" + (" — internet jde jinou cestou (Wi-Fi při testu)." if inet_ok else ".")
            status, h = ("warn" if inet_ok else "fail"), hint("lte")
        else:
            msg, status, h = f"LTE modem není připojen (stav: {st}, NM: {lte.get('nm_state')}).", "fail", hint("lte")
        it.append(item("lte.state", "Stav LTE modemu", status, val or st, msg, h))
    if usb_mode is not None or mode is not None:
        unknown = isinstance(usb_mode, str) and usb_mode.startswith("other:")
        pid = usb_mode.split(":", 1)[1] if unknown else None
        others = ", ".join(f"{d.get('vid')}:{d.get('pid')} {d.get('product') or ''}".strip() for d in (lte.get("usb_other") or [])[:5])
        usb_txt = {"qmi": "PID 9001 (QMI)", "rndis": "PID 9011 (RNDIS)"}.get(usb_mode) or (
            f"SIMCom 1e0e:{pid} (neznámý režim)" if unknown else "NENÍ na USB" + (f" · na USB je: {others}" if others else " · na USB není nic dalšího"))
        mismatch = usb_mode in ("qmi", "rndis") and mode is not None and usb_mode != mode
        status = "fail" if usb_mode is None else "warn" if (mismatch or unknown) else "ok"
        it.append(item("lte.usb", "Modem na USB", status, usb_txt,
                       "Žádné SIMCom zařízení na USB — kabel (musí přenášet data, ne jen napájení), napájení modemu nebo USB port."
                       if usb_mode is None else
                       f"Modem je na USB pod PID {pid}, což není QMI (9001) ani RNDIS (9011) — jiná USB kompozice; přepínací skript "
                       "ji nezná a datové spojení nenaběhne." if unknown else
                       f"Modem se na USB hlásí jako {usb_mode}, konfigurace jednotky má {mode} — přepnutí ještě neproběhlo "
                       "nebo skončilo v půlce." if mismatch else "",
                       hint("modem_usb_missing") if usb_mode is None else hint("lte_pid_unknown") if unknown
                       else hint("lte_mode_mismatch") if mismatch else None))
        it.append(item("lte.mode", "Režim modemu", "ok", f"{mode or '?'}" + (f" · ModemManager {'běží' if lte.get('mm_active') else 'neběží'}"
                                                                          if lte.get("mm_active") is not None else ""), ""))
    # Zamčená SIM (PIN/PUK) — vlastní řádek, protože z „state: searching" ji nikdo nepozná a modem
    # se o PIN hlásí až po restartu (Pohořelice 2026-09-19: LTE po rebootu nenaskočilo kvůli PINu).
    err, unlock = lte.get("error"), lte.get("unlock_required")
    if unlock in ("sim-pin2", "sim-puk2") and err not in ("sim_locked", "sim_puk"):
        # PIN2 chrání jen FDN/servisní funkce SIM — připojení neblokuje (health_probe: informace, ne blokátor)
        it.append(item("lte.sim_lock", "Zámek SIM karty", "ok", unlock, "Jen PIN2 (servisní funkce SIM) — datové připojení neblokuje."))
        unlock = None
    if err in ("sim_locked", "sim_puk") or unlock:
        retries = lte.get("unlock_retries")
        puk = err == "sim_puk"
        it.append(item("lte.sim_lock", "Zámek SIM karty", "fail",
                       f"{unlock or err}" + (f", zbývá {retries} pokusů" if retries is not None else ""),
                       "SIM karta je zablokovaná a čeká na PUK — PIN už ji neodemkne."
                       if puk else "SIM karta vyžaduje PIN — modem si o něj řekne po každém restartu, takže LTE "
                                   "po rebootu samo nenaskočí.", hint("sim_puk" if puk else "sim_pin")))
    return section("lte", "LTE", it)


def _internet(r: dict) -> dict:
    inet = r.get("internet")
    if not isinstance(inet, dict):
        return section("internet", "Internet", [item("internet.step", "Internet", "skip", None, "Krok neproběhl.")])
    it: list[dict] = []
    for d in inet.get("dns") or []:
        ok = bool(d.get("addresses"))
        it.append(item(f"internet.dns.{d.get('host')}", f"DNS {d.get('host')}", "ok" if ok else "fail", ", ".join(d.get("addresses") or []) or None,
                       "" if ok else f"DNS nepřeloží {d.get('host')} ({d.get('error') or 'bez odpovědi'}).", hint("dns_fail")))
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
        val = (f"ping {d.get('ping_ms')} ms, TCP {d.get('ms')} ms" + (" (RTU přes TCP 4196 — tovární režim)" if d.get("protocol") == "rtu" else "")
               if d.get("reachable") else d.get("error"))
        it.append(item(f"modules.{name}", f"{name} ({typ}, {host})", st, val, msg, hint(hk, name=name, host=host, type=typ)))
    for ip, names in by_ip.items():
        if len(names) > 1:
            it.append(item(f"modules.ip.{ip}", f"Adresa {ip}", "fail", ", ".join(names), f"Více zařízení sdílí adresu {ip}: {', '.join(names)}.", hint("ip_conflict")))
    return section("modules", "Moduly Waveshare / Shelly", it)


def _provision(r: dict) -> dict:
    p = r.get("provision")
    if not isinstance(p, dict):
        return section("provision", "Automatické zřízení modulů (IP Waveshare)",
                       [item("provision.step", "Vyhledávání modulů", "skip", None, "Krok neproběhl.")])
    iface, addrs, missing = p.get("iface") or "eth0", p.get("lan_addrs") or [], p.get("missing") or []
    devs = p.get("devices") or {}
    it: list[dict] = []
    if not addrs:
        it.append(item("provision.addr", f"Adresy jednotky ({iface})", "fail", None,
                       f"Rozhraní {iface} nemá žádnou IPv4 adresu — moduly jsou nedosažitelné.", hint("provision_no_lan", iface=iface)))
    elif not p.get("factory_addr"):
        it.append(item("provision.addr", f"Adresy jednotky ({iface})", "warn" if not missing else "fail", ", ".join(addrs),
                       "Chybí pomocná adresa 192.168.1.253/24 — moduly s tovární IP se nenajdou.", hint("provision_addr", iface=iface)))
    else:
        it.append(item("provision.addr", f"Adresy jednotky ({iface})", "ok", ", ".join(addrs)))
    found = p.get("found")
    if found is None:
        err = p.get("error") or "?"
        it.append(item("provision.found", "Vyhledávání modulů (ZLAN, UDP 1092)", "skip" if err in ("no_provisioner", "no_lan_address") else "warn",
                       None, f"Vyhledávání neproběhlo ({err}).", None if err in ("no_provisioner", "no_lan_address") else hint("step")))
        found = []
    else:
        hosts = {str(d.get("host")): n for n, d in devs.items()}
        st = "fail" if missing and not found else "ok"
        it.append(item("provision.found", "Vyhledávání modulů (ZLAN, UDP 1092)", st, f"{len(found)} modulů",
                       "Žádný modul Waveshare neodpověděl." if st == "fail" else "", hint("provision_none") if st == "fail" else None))
        for f in found:
            ip, mac = str(f.get("ip")), str(f.get("mac"))
            val = f"{ip} ({f.get('protocol')}, port {f.get('port')})"
            name = hosts.get(ip)
            if name:
                it.append(item(f"provision.mod.{mac}", f"Modul {mac}", "ok", val, f"= {name} z HW mapy" + ("" if devs[name].get("online") else " (program ho zatím má offline)")))
            elif missing:
                it.append(item(f"provision.mod.{mac}", f"Modul {mac}", "warn", val,
                               f"Modul na {ip} není v HW mapě — bude přiřazen chybějícímu zařízení ({', '.join(missing)}).", hint("provision_pending", mac=mac, ip=ip)))
            else:
                it.append(item(f"provision.mod.{mac}", f"Modul {mac}", "warn", val, f"Modul na {ip} není v HW mapě.", hint("provision_extra", mac=mac, ip=ip)))
        free = [f for f in found if str(f.get("ip")) not in hosts]
        if missing and found and not free:
            for n in missing:
                d = devs.get(n) or {}
                it.append(item(f"provision.missing.{n}", f"Chybí {n}", "fail", d.get("host"),
                               f"{n} ({d.get('host')}) neodpovídá a žádný volný modul k přiřazení nebyl nalezen.",
                               hint("provision_missing", name=n, host=d.get("host"))))
    rem = p.get("remembered") or {}
    if rem:
        it.append(item("provision.remembered", "Dřívější přiřazení (MAC → zařízení)", "ok", ", ".join(f"{m} → {n}" for m, n in sorted(rem.items()))))
    return section("provision", "Automatické zřízení modulů (IP Waveshare)", it)


def _config(r: dict) -> dict | None:
    if (sec := _missing("config", "Konfigurace pobočky", r, "config")) is None or sec["items"]:
        return sec
    c = r["config"]
    zt = int(c.get("zones_total") or 0)
    it = [item("config.zones", "Zóny / dveře s HW mapou", "ok" if zt else "fail", f"{zt} zón ({c.get('source')})",
               "" if zt else "Žádné zóny (nespárováno / bez HW mapy).", hint("no_zones"))]
    # Nepovinné role, které pobočka vůbec nepoužívá (bez Shelly v mapě / audio relé nikde), nejsou varování — jen informace
    zones = c.get("zones") or []
    devtypes = {str((d or {}).get("type")) for d in (c.get("devices") or {}).values()}
    unused = {r for r in ("red", "green") if "shelly_rgbww" not in devtypes}
    if zones and all("audio" in (z.get("missing") or []) for z in zones):
        unused.add("audio")
    for z in zones:
        for role in z.get("missing") or []:
            if role in unused:
                it.append(item(f"config.zone.{z.get('zone')}.{role}", f"{z.get('label')} — role {role}", "skip", None,
                               f"Zóna {z.get('zone')}: role {role} nepoužita (pobočka ji nemá zapojenou)."))
                continue
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
    if (venek := _outdoor().config_item(c)) is not None:
        it.append(venek)
    return section("config", "Konfigurace pobočky", it)


def _zones(r: dict) -> dict | None:
    if (sec := _missing("zones", "Zóny a periferie", r, "zones")) is None or sec["items"]:
        return sec
    zs = r["zones"]
    it: list[dict] = [] if zs else [item("zones.none", "Zóny", "warn", 0, "Žádné zóny (nespárováno / bez HW mapy).", hint("no_zones"))]
    for z in zs:
        n, label, f = z.get("zone"), z.get("label") or f"Zóna {z.get('zone')}", z.get("findings") or []
        worst = max((RANK.get(x.get("status"), 0) for x in f), default=0)
        st = {3: "fail", 2: "warn"}.get(worst) or ("skip" if z.get("skipped_reason") else "ok")
        door = {True: "zavřeno", False: "otevřeno"}.get(z.get("door_closed"), "?")
        tests = " ".join(f"{k} {'✔' if v else '✘' if v is False else '–'}" for k, v in (("světlo", z.get("light")), ("zelená", z.get("signal")), ("tón", z.get("audio"))))
        val = f"{z.get('state')}, dveře {door}" + (f" (vstup {z.get('contact_ref')} = {z.get('contact_input')}, zavřeno = {z.get('closed_level')})" if z.get("contact_input") is not None else "") + (f", test: {tests}" if z.get("tested") else "")
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
    it += _outdoor().items(r)             # skupina „Venek (zóna N)“ za zónami; bez venku nic
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


def _fmt_dur(s) -> str:
    s = int(s or 0)
    return f"{s // 3600} h {s % 3600 // 60} min" if s >= 3600 else f"{s // 60} min {s % 60} s" if s >= 60 else f"{s} s"


def _netlog(r: dict) -> dict:
    n = r.get("netlog")
    if not isinstance(n, dict):
        return section("netlog", "Historie sítě (24 h / 7 dní)", [item("netlog.step", "Historie sítě", "skip", None, "Krok neproběhl.")])
    it: list[dict] = []
    od, ow = n.get("outages_24h") or [], n.get("outages_7d") or []
    dd, dw = int(n.get("downtime_24h_s") or 0), int(n.get("downtime_7d_s") or 0)
    if not n.get("samples_24h"):
        it.append(item("netlog.samples", "Vzorky stavu sítě", "warn", 0, "Za 24 h žádné vzorky — health služba neposílá stav (nebo jednotka právě startuje).", hint("health")))
    else:
        it.append(item("netlog.samples", "Vzorky stavu sítě", "ok", f"{n.get('samples_24h')} za 24 h, {n.get('samples_7d')} za 7 dní"))
    st = "fail" if dd >= 1800 or len(od) >= 5 else "warn" if od else "ok"
    it.append(item("netlog.outages", "Výpadky internetu za 24 h", st, f"{len(od)}× celkem {_fmt_dur(dd)}",
                   "" if not od else f"Nejdelší {_fmt_dur(max(o['duration_s'] for o in od))}; při výpadku LTE „{od[-1].get('lte')}“, modem {'pryč z USB' if od[-1].get('modem_gone') else 'vidět'}, kabel {od[-1].get('lan') or 'OK'}, brána přes {od[-1].get('gw_dev') or 'nic'}."
                   + (" Výpadek TRVÁ." if od[-1].get("open") else ""), hint("net_outages") if od else None))
    it.append(item("netlog.outages_7d", "Výpadky internetu za 7 dní", "warn" if len(ow) >= 10 or dw >= 4 * 3600 else "ok", f"{len(ow)}× celkem {_fmt_dur(dw)}",
                   "" if len(ow) < 10 and dw < 4 * 3600 else "Opakované výpadky — modem (SIM7600 padá z USB) / anténa / SIM; viz logy níže.", hint("net_outages") if len(ow) >= 10 or dw >= 4 * 3600 else None))
    mg = int(n.get("modem_gone_24h") or 0)
    if mg:
        it.append(item("netlog.modem_gone", "Modem pryč z USB (vzorky za 24 h)", "warn" if mg < 60 else "fail", mg,
                       f"Modem nebyl vidět v ModemManageru v {mg} vzorcích (~{_fmt_dur(mg * 30)}) — známá závada SIM7600 (USB -71).", hint("modem_gone")))
    resets = sum(1 for e in n.get("events") or [] if e.get("kind") in ("LTE_RESET", "REBOOT"))
    it.append(item("netlog.recovery", "Obnovy LTE / restarty za 7 dní", "ok" if resets < 10 else "warn", resets,
                   "" if resets < 10 else "Health opakovaně resetuje modem — SIM7600 padá z USB (kernel -71); obnova funguje, ale při růstu četnosti řešit kabel/port/modem.", hint("net_outages") if resets >= 10 else None))
    gw = n.get("gw_now") or {}
    it.append(item("netlog.gw", "Internet právě jde přes", "ok" if gw.get("dev") else "warn", f"{gw.get('dev') or 'nic'} · DNS {gw.get('dns') or '—'}",
                   "" if gw.get("dev") else "Bez výchozí trasy — internet nejde.", None if gw.get("dev") else hint("gateway_missing")))
    return section("netlog", "Historie sítě (24 h / 7 dní)", it)


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
    for fn in (_system, _software, _network, _lte, _internet, _velin, _modules, _provision, _netlog, _config, _zones, _power, _cameras, _lan, _steps):
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
            "zones_total": zones_total, "zones_tested": sum(1 for z in zs if z.get("tested")), "outdoor": _outdoor().summary(r),
            "zones_ok": sum(1 for z in zs if not any(f.get("status") == "fail" for f in z.get("findings") or [])),
            "hosts": len(lan.get("hosts") or []), "internet": bool(inet.get("ok")),
            # RNDIS: mmcli nic neví — stav podle adresy rozhraní modemu (usb0)
            "lte": ("connected" if lte.get("ipv4") else "no_address") if lte.get("mode") == "rndis" else lte.get("state"),
            "devices_ok": sum(1 for d in r.get("devices") or [] if d.get("reachable")), "devices_total": len(r.get("devices") or []),
            "sections": {s.get("key"): s.get("status") for s in protocol}}
