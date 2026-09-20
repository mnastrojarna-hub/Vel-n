"""Testy health monitoru (kontrakt §17): parsery, politika LTE, cyklus s falešnými příkazy."""
from __future__ import annotations

import asyncio
import json

import httpx
import pytest

from motogo_box.config import HealthCfg
from motogo_box import health as health_mod
from motogo_box.health import HealthMonitor, LtePolicy, lte_error, run_cmd
from motogo_box.health_probe import (
    disk_free_pct, mem_free_pct, modem_gone, parse_meminfo, parse_mmcli_modem, parse_mmcli_signal,
    parse_nmcli_connection, parse_throttled, read_cpu_temp, usb_device_present,
)

MMCLI_MODEM = json.dumps({"modem": {
    "3gpp": {"operator-code": "23001", "operator-name": "T-Mobile CZ", "registration-state": "home"},
    "generic": {"state": "connected", "access-technologies": ["lte"],
                "signal-quality": {"recent": "yes", "value": "72"}},
}})
MMCLI_SIGNAL = json.dumps({"modem": {"signal": {
    "5g": {"rsrp": "--", "rsrq": "--", "snr": "--"},
    "lte": {"rsrp": "-98.00", "rsrq": "-10.00", "rssi": "-71.00", "snr": "12.40"},
    "refresh": {"rate": "30"},
}}})
MEMINFO = "MemTotal:        4045000 kB\nMemFree:          500000 kB\nMemAvailable:    2427000 kB\nBuffers: 1 kB\n"


# ─── parsery ─────────────────────────────────────────────────────────────────
def test_parse_mmcli_modem():
    m = parse_mmcli_modem(MMCLI_MODEM)
    assert m["state"] == "connected"
    assert m["signal_quality"] == 72
    assert m["operator"] == "T-Mobile CZ"
    assert m["access_tech"] == "lte"
    assert m["registration"] == "home"


def test_parse_mmcli_modem_garbage_and_missing():
    assert parse_mmcli_modem("error: couldn't find modem")["state"] == "unknown"
    m = parse_mmcli_modem(json.dumps({"modem": {"generic": {"state": "searching",
                                                              "signal-quality": {"value": "--"}},
                                                  "3gpp": {"operator-name": "--"}}}))
    assert m == {"state": "searching", "signal_quality": None, "operator": None,
                 "access_tech": None, "registration": None, "failed_reason": None,
                 "unlock_required": None, "unlock_retries": None}


def test_parse_mmcli_modem_failed_reason_and_lte_error():
    failed = json.dumps({"modem": {"generic": {"state": "failed", "state-failed-reason": "sim-missing"}}})
    m = parse_mmcli_modem(failed)
    assert m["state"] == "failed" and m["failed_reason"] == "sim-missing"
    assert lte_error(m) == "sim_missing"
    assert lte_error({"state": "locked"}) == "sim_locked"
    assert lte_error({"state": "failed", "failed_reason": "sim-error"}) == "sim_error"
    assert lte_error({"state": "failed", "failed_reason": "unknown"}) is None   # jiná porucha → USB reset má smysl
    assert lte_error({"state": "connected"}) is None
    assert parse_mmcli_modem(json.dumps({"modem": {"generic": {"state": "connected",
                                                                "state-failed-reason": "none"}}}))["failed_reason"] is None


def test_pin2_never_blocks_recovery():
    """PIN2/PUK2 chrání jen FDN — data nebrání. Brát je jako chybu = vypnutá obnova (živě 2026-09-20)."""
    connected_pin2 = parse_mmcli_modem(json.dumps({"modem": {"generic": {
        "state": "connected", "unlock-required": "sim-pin2", "unlock-retries": ["sim-pin2 (3)"]}}}))
    assert connected_pin2["unlock_required"] == "sim-pin2"      # zůstává jako informace
    assert lte_error(connected_pin2) is None                    # ale NENÍ to blokátor
    assert lte_error({"state": "searching", "unlock_required": "sim-puk2"}) is None
    # PIN1/PUK1 blokují dál
    assert lte_error({"state": "connected", "unlock_required": "sim-pin"}) == "sim_locked"
    assert lte_error({"state": "searching", "unlock_required": "sim-puk"}) == "sim_puk"


async def test_cycle_with_pin2_still_runs_recovery(tmp_path):
    """Modem s PIN2 a mrtvým internetem MUSÍ projít žebříčkem obnovy, ne stát na „obnova pozastavena"."""
    env = FakeEnv(internet_ok=False, modem_state="connected")
    d = json.loads(env.modem_json)
    d["modem"]["generic"]["unlock-required"] = "sim-pin2"
    env.modem_json = json.dumps(d)
    mon = _monitor(env, tmp_path, _cfg(reconnect_after=1))
    payload = await mon.cycle()
    assert payload["lte"]["unlock_required"] == "sim-pin2" and payload["lte"]["error"] is None
    assert payload["actions"] == ["reconnect"]


async def test_policy_runs_on_success_even_with_blocking_sim_error(tmp_path):
    """I s blokující chybou SIM se při funkčním internetu musí srovnat počítadla (jinak last_online None)."""
    env = FakeEnv(internet_ok=True, modem_state="locked")
    mon = _monitor(env, tmp_path)
    mon.policy.internet_failures = 5
    payload = await mon.cycle()
    assert payload["lte"]["error"] == "sim_locked"
    assert mon.policy.internet_failures == 0 and mon.policy.last_online is not None


def test_cooldown_survives_clock_jump_backwards():
    """Posun hodin zpět (bez NTP, fake-hwclock po výpadku) nesmí zmrazit obnovu na hodiny."""
    clock = FakeClock(2_000_000.0)
    p = LtePolicy(_cfg(reconnect_after=1, usb_reset_after=1, action_cooldown_s=120), clock)
    assert p.step(False, 5000.0) == ["reconnect"]
    clock.t = 1_900_000.0                       # hodiny skočily o den zpět
    assert p.step(False, 5000.0) == ["modem_reset"]      # obnova běží dál, ne prázdno
    # stará značka z budoucnosti se navíc po načtení stavu ořízne
    q = LtePolicy(_cfg(), FakeClock(1_000.0))
    q.load({"last_action_at": 9_999_999.0, "last_online": 9_999_999.0,
            "history": [[9_999_999.0, "reconnect"]]})
    assert q.last_action_at == 1_000.0 and q.last_online == 1_000.0
    assert q.counts_24h()["reconnect"] == 0     # budoucí záznamy se nezapočítávají


def test_parse_mmcli_modem_sim_pin_beats_state():
    """Zamčená SIM se po restartu modemu umí tvářit jako `searching` — rozhodovat musí `unlock-required`."""
    locked = json.dumps({"modem": {"generic": {
        "state": "searching", "unlock-required": "sim-pin", "unlock-retries": ["sim-pin (3)"]}}})
    m = parse_mmcli_modem(locked)
    assert m["state"] == "searching" and m["unlock_required"] == "sim-pin" and m["unlock_retries"] == 3
    assert lte_error(m) == "sim_locked"      # politika obnovy se zastaví — USB reset ani reboot PIN nezadá

    puk = parse_mmcli_modem(json.dumps({"modem": {"generic": {
        "state": "locked", "unlock-required": "sim-puk", "unlock-retries": {"sim-puk": 10}}}}))
    assert lte_error(puk) == "sim_puk" and puk["unlock_retries"] == 10

    # SIM bez PINu: mmcli hlásí "--"/none → žádná chyba, obnova běží normálně
    free = parse_mmcli_modem(json.dumps({"modem": {"generic": {"state": "connected", "unlock-required": "--"}}}))
    assert free["unlock_required"] is None and free["unlock_retries"] is None and lte_error(free) is None
    assert lte_error({"state": "searching"}) is None


def test_parse_mmcli_signal():
    s = parse_mmcli_signal(MMCLI_SIGNAL)
    assert s["rssi"] == -71.0 and s["rsrp"] == -98.0 and s["rsrq"] == -10.0 and s["snr"] == 12.4
    assert s["refresh_rate"] == 30
    empty = parse_mmcli_signal(json.dumps({"modem": {"signal": {"lte": {"rssi": "--"}, "refresh": {"rate": "0"}}}}))
    assert empty["rssi"] is None and empty["refresh_rate"] == 0
    assert parse_mmcli_signal("nope")["rsrp"] is None


def test_parse_nmcli_connection():
    assert parse_nmcli_connection(0, "GENERAL.STATE:activated\nGENERAL.DEVICES:wwan0\n") == {
        "nm_state": "activated", "nm_device": "wwan0"}
    assert parse_nmcli_connection(0, "") == {"nm_state": "inactive", "nm_device": None}
    assert parse_nmcli_connection(10, "Error: unknown connection")["nm_state"] == "missing"


def test_parse_meminfo_and_throttled(tmp_path):
    assert parse_meminfo(MEMINFO) == 60.0
    assert parse_meminfo("MemTotal: 0 kB") is None
    assert parse_meminfo("") is None
    p = tmp_path / "meminfo"
    p.write_text(MEMINFO)
    assert mem_free_pct(str(p)) == 60.0
    assert mem_free_pct(str(tmp_path / "missing")) == 0.0
    assert parse_throttled("throttled=0x50000\n") == "0x50000"
    assert parse_throttled("") is None
    assert parse_throttled("VCHI initialization failed") is None


def test_sys_helpers(tmp_path):
    t = tmp_path / "temp"
    t.write_text("48250\n")
    assert read_cpu_temp(str(t)) == 48.2
    assert read_cpu_temp(str(tmp_path / "nope")) is None
    assert 0.0 <= disk_free_pct("/") <= 100.0
    assert disk_free_pct("/definitely/not/here") == 0.0


# ─── politika ────────────────────────────────────────────────────────────────
class FakeClock:
    def __init__(self, t: float = 1000.0) -> None:
        self.t = t

    def __call__(self) -> float:
        return self.t

    def advance(self, s: float) -> None:
        self.t += s


def _cfg(**kw) -> HealthCfg:
    # `action_cooldown_s=0`: žebříček se testuje bez čekání, cooldown má vlastní testy níž.
    base = dict(check_interval_s=30, reconnect_after=5, usb_reset_after=5, reboot_after=3,
                min_uptime_before_reboot_s=1800, action_cooldown_s=0)
    base.update(kw)
    return HealthCfg(**base)


def _drive(policy: LtePolicy, failures: int, uptime: float, *, gone: bool = False) -> list[str]:
    """Nechá politiku projít `failures` neúspěšnými kroky a vrátí všechny vydané akce."""
    out: list[str] = []
    for _ in range(failures):
        out += policy.step(False, uptime, modem_gone=gone)
    return out


def test_policy_online_resets_everything():
    clock = FakeClock()
    p = LtePolicy(_cfg(), clock)
    assert _drive(p, 4, 100.0) == []
    assert p.internet_failures == 4
    assert p.step(True, 100.0) == []
    assert p.internet_failures == 0 and p.last_online == clock.t
    # po obnovení začíná počítání znovu — 5. výpadek až po dalších pěti krocích
    assert _drive(p, 4, 100.0) == []
    assert _drive(p, 1, 100.0) == ["reconnect"]


def test_policy_ladder_reconnect_modem_reset_usb_reset_reboot():
    p = LtePolicy(_cfg(), FakeClock())
    actions = _drive(p, 5 * 5, 5000.0)          # 5 reconnectů
    assert actions == ["reconnect"] * 5
    assert p.reconnects == 5 and p.reconnect_failures == 5 and p.usb_resets == 0
    # 6. dávka → nejdřív levnější reset modemu (modem v MM je), teprve pak USB reset
    assert _drive(p, 5, 5000.0) == ["modem_reset"]
    assert p.modem_resets == 1 and p.usb_resets == 0 and p.modem_reset_done is True
    # když ani reset modemu nepomohl, jde USB reset hned další dávkou — ne po dalších pěti reconnectech
    assert _drive(p, 5, 5000.0) == ["usb_reset"]
    assert p.usb_resets == 1 and p.reconnect_failures == 0 and p.usb_resets_pending == 1
    # mmcli reset se v jednom výpadku zkouší jen jednou → další dvě dávky končí USB resetem
    for _ in range(2):
        a = _drive(p, 30, 5000.0)
        assert a.count("reconnect") == 5 and a.count("usb_reset") == 1 and "modem_reset" not in a
    assert p.usb_resets == 3 and p.usb_resets_pending == 3
    # hned další výpadek s dostatečným uptime → reboot; počítadla obnovy vynulovaná
    assert p.step(False, 5000.0) == ["reboot"]
    assert p.reboots == 1 and p.usb_resets_pending == 0 and p.reconnect_failures == 0
    assert p.last_action == "reboot"
    assert p.counts_24h() == {"reconnect": 15, "modem_reset": 1, "usb_reset": 3, "reboot": 1}


def test_policy_no_reboot_before_min_uptime():
    p = LtePolicy(_cfg(), FakeClock())
    for _ in range(500):              # uptime 100 s < 1800 s → reboot se nesmí spustit ani po 3 resetech
        if p.usb_resets_pending >= 3:
            break
        p.step(False, 100.0)
    assert p.usb_resets_pending == 3 and p.reboots == 0
    # žebříček pokračuje dál (další dávka → reconnect), pořád bez rebootu
    assert _drive(p, 5, 100.0) == ["reconnect"]
    assert p.reboots == 0
    # jakmile uptime dovolí, další výpadek → reboot
    assert p.step(False, 1800.0) == ["reboot"]


def test_policy_recovery_after_usb_reset_clears_pending():
    p = LtePolicy(_cfg(reconnect_after=1, usb_reset_after=1, reboot_after=2), FakeClock())
    assert p.step(False, 5000.0) == ["reconnect"]
    assert p.step(False, 5000.0) == ["modem_reset"]
    assert p.step(False, 5000.0) == ["usb_reset"]
    assert p.step(True, 5000.0) == []
    assert p.usb_resets_pending == 0 and p.usb_resets == 1   # lifetime počítadlo zůstává
    assert p.modem_reset_done is False                       # po návratu internetu se mmcli reset smí znovu


def test_policy_persist_roundtrip():
    p = LtePolicy(_cfg(), FakeClock(50.0))
    _drive(p, 30, 5000.0)
    d = p.to_dict()
    q = LtePolicy(_cfg(), FakeClock(60.0))
    q.load(d)
    assert q.to_dict() == d
    q.load({"reconnects": "x", "usb_resets": -4, "last_online": "??", "history": "nesmysl"})
    assert q.reconnects == 5 and q.usb_resets == 0 and q.last_online is None   # vadné ignoruje, záporné ořeže
    assert q.history == []
    q.load(None)


def test_policy_modem_gone_skips_reconnects():
    """Modem zmizel z ModemManageru (ale na USB je): `nmcli con up` vrací „No suitable device found",
    takže se reconnecty přeskočí a po 2 sondách (~1 min) jde rovnou USB reset."""
    p = LtePolicy(_cfg(), FakeClock())
    assert p.step(False, 5000.0, modem_gone=True) == []          # 1. sonda
    assert p.step(False, 5000.0, modem_gone=True) == ["usb_reset"]
    assert p.reconnects == 0 and p.usb_resets == 1 and p.usb_resets_pending == 1
    # po třech resetech (a dostatečném uptime) přijde reboot i v tomhle režimu
    assert _drive(p, 2, 5000.0, gone=True) == ["usb_reset"]
    assert _drive(p, 2, 5000.0, gone=True) == ["usb_reset"]
    assert p.step(False, 5000.0, modem_gone=True) == ["reboot"]
    assert p.counts_24h() == {"reconnect": 0, "modem_reset": 0, "usb_reset": 3, "reboot": 1}


def test_policy_modem_gone_but_usb_empty_uses_normal_ladder():
    """Modem není ani na USB → `modem_gone=False` (reset nemá co resetovat) → běžný žebříček."""
    p = LtePolicy(_cfg(reconnect_after=1), FakeClock())
    assert p.step(False, 5000.0, modem_gone=False) == ["reconnect"]


def test_policy_cooldown_blocks_actions_until_it_passes():
    """Po akci se jen sonduje — USB reset s restartem ModemManageru trvá ~90 s."""
    clock = FakeClock()
    p = LtePolicy(_cfg(reconnect_after=1, usb_reset_after=1, action_cooldown_s=120), clock)
    assert p.step(False, 5000.0) == ["reconnect"]
    clock.advance(30)
    assert p.step(False, 5000.0) == []            # cooldown běží
    clock.advance(30)
    assert p.step(False, 5000.0) == []
    clock.advance(61)                              # 121 s od akce
    assert p.step(False, 5000.0) == ["modem_reset"]


def test_counts_24h_forgets_older_entries():
    clock = FakeClock(1_000_000.0)
    p = LtePolicy(_cfg(reconnect_after=1), clock)
    p.step(False, 5000.0)
    assert p.counts_24h()["reconnect"] == 1
    clock.advance(86400 + 60)
    assert p.counts_24h() == {"reconnect": 0, "modem_reset": 0, "usb_reset": 0, "reboot": 0}
    assert p.reconnects == 1                       # celkové počítadlo zůstává


# ─── detekce modemu na USB ───────────────────────────────────────────────────
def test_usb_device_present(tmp_path):
    base = tmp_path / "usb"
    (base / "1-1").mkdir(parents=True)
    (base / "1-1" / "idVendor").write_text("1e0e\n")
    (base / "1-1" / "idProduct").write_text("9001\n")
    (base / "usb1").mkdir()                        # zařízení bez id souborů se přeskočí
    assert usb_device_present("1e0e:9001", str(base)) is True
    assert usb_device_present("1E0E:9001", str(base)) is True      # velikost písmen nerozhoduje
    assert usb_device_present("dead:beef", str(base)) is False
    assert usb_device_present("nesmysl", str(base)) is None
    assert usb_device_present("1e0e:9001", str(tmp_path / "nic")) is None


def test_modem_gone_rules():
    assert modem_gone({"state": "no_modem"}, True) is True
    assert modem_gone({"state": "unavailable"}, None) is True      # o USB nevíme → radši resetovat
    assert modem_gone({"state": "no_modem"}, False) is False       # na sběrnici není → reset nemá co dělat
    assert modem_gone({"state": "connected"}, True) is False
    assert modem_gone({"state": "searching"}, True) is False       # modem MM má, jen se nepřipojil


# ─── monitor s falešným prostředím ───────────────────────────────────────────
class FakeEnv:
    """Falešné `run_cmd` + HTTP transport: nic nesahá na síť ani sudo."""

    def __init__(self, internet_ok: bool = True, modem_ok: bool = True, *, tcp_ok: bool | None = None,
                 failing_hosts: set[str] | None = None, modem_state: str = "connected",
                 failed_reason: str | None = None, lan: list[dict] | None = None) -> None:
        self.internet_ok, self.modem_ok = internet_ok, modem_ok
        # výchozí stav I/O sítě: eth0 s adresou (zdravá pobočka) — testy si ho přepíšou
        self.ifaces = [{"name": "eth0", "state": "up", "ipv4": [{"addr": "192.168.50.10", "prefix": 24}]}] \
            if lan is None else lan
        self.tcp_ok = internet_ok if tcp_ok is None else tcp_ok
        self.failing_hosts = failing_hosts or set()   # HTTP cíle, které selžou i při internet_ok
        d = json.loads(MMCLI_MODEM)
        d["modem"]["generic"].update({"state": modem_state, "state-failed-reason": failed_reason or "none"})
        self.modem_json = json.dumps(d)
        self.cmds: list[tuple[str, ...]] = []
        self.posted: list[dict] = []
        self.tcp_probes = 0

    async def interfaces(self) -> list[dict]:
        return self.ifaces

    async def tcp_probe(self, host: str, port: int, timeout: float = 8.0) -> bool:
        self.tcp_probes += 1
        return self.tcp_ok

    async def run_cmd(self, *args: str, timeout: float = 20) -> tuple[int, str]:
        self.cmds.append(args)
        if args[0] == "mmcli" and not self.modem_ok:
            return 1, "error: couldn't find modem"
        if args[0] == "mmcli" and "-J" in args and "--signal-get" in args:
            return 0, MMCLI_SIGNAL
        if args[0] == "mmcli" and "-J" in args:
            return 0, self.modem_json
        if args[0] == "nmcli":
            return 0, "GENERAL.STATE:activated\nGENERAL.DEVICES:wwan0\n"
        return 0, ""

    def handler(self, request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/health":
            self.posted.append(json.loads(request.content))
            return httpx.Response(200, json={"ok": True})
        if not self.internet_ok or request.url.host in self.failing_hosts:
            raise httpx.ConnectError("no route", request=request)
        return httpx.Response(200, json={"status": "ok"})

    def client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(transport=httpx.MockTransport(self.handler))


def _monitor(env: FakeEnv, tmp_path, cfg: HealthCfg | None = None, uptime: float = 5000.0) -> HealthMonitor:
    return HealthMonitor(cfg or _cfg(), "http://127.0.0.1:8080", run_cmd=env.run_cmd,
                         clock=FakeClock(), state_path=str(tmp_path / "health.json"),
                         http=env.client(), uptime=lambda: uptime, tcp_probe=env.tcp_probe,
                         interfaces=env.interfaces)


async def test_cycle_online_posts_payload(tmp_path):
    env = FakeEnv()
    mon = _monitor(env, tmp_path)
    payload = await mon.cycle()
    assert payload["internet"] is True and payload["actions"] == []
    lte = payload["lte"]
    assert lte["state"] == "connected" and lte["operator"] == "T-Mobile CZ"
    assert lte["rssi"] == -71.0 and lte["rsrp"] == -98.0 and lte["nm_state"] == "activated"
    assert lte["reconnects"] == 0 and lte["usb_resets"] == 0
    assert set(payload["sys"]) >= {"cpu_temp", "throttled", "disk_free_pct", "mem_free_pct", "load1", "uptime_s"}
    assert env.posted and env.posted[-1]["internet"] is True
    assert not any(c[0] == "sudo" for c in env.cmds)
    assert json.loads((tmp_path / "health.json").read_text())["reconnects"] == 0


async def test_cycle_no_modem(tmp_path):
    env = FakeEnv(modem_ok=False)
    payload = await _monitor(env, tmp_path).cycle()
    assert payload["lte"]["state"] == "no_modem" and payload["lte"]["rssi"] is None


async def test_cycle_failures_run_actions_without_real_sudo(tmp_path):
    env = FakeEnv(internet_ok=False)
    cfg = _cfg(reconnect_after=1, usb_reset_after=1, reboot_after=1, min_uptime_before_reboot_s=10)
    mon = _monitor(env, tmp_path, cfg)
    p1 = await mon.cycle()
    assert p1["actions"] == ["reconnect"]
    assert ("sudo", "-n", "nmcli", "con", "down", "motogo-lte") in env.cmds
    assert ("sudo", "-n", "nmcli", "-w", "30", "con", "up", "motogo-lte") in env.cmds
    pm = await mon.cycle()
    assert pm["actions"] == ["modem_reset"]
    assert ("sudo", "-n", "mmcli", "-m", "any", "--reset") in env.cmds
    p2 = await mon.cycle()
    assert p2["actions"] == ["usb_reset"]
    # sudoers povoluje skript jen BEZ argumentů (VID:PID čte z /etc/motogo/modem_vidpid)
    assert ("sudo", "-n", cfg.usb_reset_script) in env.cmds
    assert not any(c[:3] == ("sudo", "-n", cfg.usb_reset_script) and len(c) > 3 for c in env.cmds)
    env.cmds.clear()
    p3 = await mon.cycle()
    assert p3["actions"] == ["reboot"]
    assert env.cmds[-1] == ("sudo", "-n", "systemctl", "reboot")
    # controller dostal payload s akcí reboot ještě PŘED rebootem, a to jen jednou
    reboot_posts = [p for p in env.posted if "reboot" in p["actions"]]
    assert len(reboot_posts) == 1
    # počítadla přežila (soubor) — nový monitor je načte
    mon2 = _monitor(env, tmp_path, cfg)
    assert mon2.policy.usb_resets == 1 and mon2.policy.reboots == 1 and mon2.policy.usb_resets_pending == 0


async def test_cycle_survives_controller_down(tmp_path):
    env = FakeEnv()

    def down(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/health":
            raise httpx.ConnectError("controller down", request=request)
        return httpx.Response(200)

    mon = HealthMonitor(_cfg(), "http://127.0.0.1:8080", run_cmd=env.run_cmd, clock=FakeClock(),
                        state_path=str(tmp_path / "h.json"),
                        http=httpx.AsyncClient(transport=httpx.MockTransport(down)), uptime=lambda: 1.0,
                        tcp_probe=env.tcp_probe, interfaces=env.interfaces)
    payload = await mon.cycle()
    assert payload["internet"] is True and mon.last_payload is payload


SUPABASE_HOST = "vnwnqteskbykeucanlhk.supabase.co"


async def test_probe_internet_down_only_when_all_targets_fail(tmp_path):
    # Supabase nedostupná, google + TCP OK → internet funguje
    env = FakeEnv(failing_hosts={SUPABASE_HOST}, tcp_ok=True)
    mon = _monitor(env, tmp_path)
    assert await mon.probe_internet() is True
    assert mon.last_probe == {"probe_url": False, "google_204": True, "tcp_1.1.1.1": True}
    # jen TCP 1.1.1.1 OK (výpadek DNS operátora) → stále internet OK
    env = FakeEnv(internet_ok=False, tcp_ok=True)
    mon = _monitor(env, tmp_path)
    assert await mon.probe_internet() is True and env.tcp_probes == 1
    # všechny tři cíle dole → DOWN
    env = FakeEnv(internet_ok=False)
    mon = _monitor(env, tmp_path)
    assert await mon.probe_internet() is False
    assert mon.last_probe == {"probe_url": False, "google_204": False, "tcp_1.1.1.1": False}


async def test_cycle_backend_outage_does_not_escalate(tmp_path):
    env = FakeEnv(failing_hosts={SUPABASE_HOST})
    cfg = _cfg(reconnect_after=1, usb_reset_after=1, reboot_after=1, min_uptime_before_reboot_s=10)
    mon = _monitor(env, tmp_path, cfg)
    for _ in range(6):
        payload = await mon.cycle()
        assert payload["internet"] is True and payload["actions"] == []
    assert not any(c[0] == "sudo" for c in env.cmds)
    assert mon.policy.reconnects == 0 and mon.policy.usb_resets == 0 and mon.policy.reboots == 0


@pytest.mark.parametrize("state,reason,error", [("locked", None, "sim_locked"),
                                                ("failed", "sim-missing", "sim_missing")])
async def test_cycle_sim_problem_reports_error_without_escalation(tmp_path, state, reason, error):
    env = FakeEnv(internet_ok=False, modem_state=state, failed_reason=reason)
    cfg = _cfg(reconnect_after=1, usb_reset_after=1, reboot_after=1, min_uptime_before_reboot_s=10)
    mon = _monitor(env, tmp_path, cfg)
    for _ in range(4):
        payload = await mon.cycle()
        assert payload["internet"] is False and payload["actions"] == []
        assert payload["lte"]["state"] == state and payload["lte"]["error"] == error
    assert not any(c[0] == "sudo" for c in env.cmds)          # žádný nmcli/usbreset/reboot
    assert mon.policy.internet_failures == 0 and mon.policy.reconnects == 0 and mon.policy.reboots == 0
    assert env.posted and env.posted[-1]["lte"]["error"] == error   # controller/Velín chybu vidí


async def test_cycle_failed_modem_other_reason_still_escalates(tmp_path):
    env = FakeEnv(internet_ok=False, modem_state="failed", failed_reason="unknown")
    payload = await _monitor(env, tmp_path, _cfg(reconnect_after=1)).cycle()
    assert payload["lte"]["error"] is None and payload["actions"] == ["reconnect"]


async def test_run_loop_stops(tmp_path):
    env = FakeEnv()
    mon = _monitor(env, tmp_path, _cfg(check_interval_s=5))
    task = asyncio.create_task(mon.run())
    for _ in range(50):
        await asyncio.sleep(0.01)
        if env.posted:
            break
    mon.stop()
    await asyncio.wait_for(task, timeout=3)
    assert env.posted


async def test_run_cmd_never_raises():
    rc, out = await run_cmd("/definitely/missing/binary")
    assert rc == 127 and "missing" in out
    rc, out = await run_cmd("sh", "-c", "echo hi; exit 3")
    assert rc == 3 and out.strip() == "hi"
    rc, out = await run_cmd("sleep", "5", timeout=0.2)
    assert rc == 124 and "timeout" in out


class _RootChild:
    """Potomek pod sudo: kill() je zakázaný (root) / proces už není, wait() by čekal donekonečna."""
    returncode = None

    def __init__(self, kill_exc: type[BaseException]) -> None:
        self.kill_exc = kill_exc

    async def communicate(self):
        await asyncio.sleep(10)

    def kill(self) -> None:
        raise self.kill_exc()

    async def wait(self):
        await asyncio.sleep(10)


@pytest.mark.parametrize("exc", [PermissionError, ProcessLookupError])
async def test_run_cmd_timeout_survives_unkillable_sudo_child(monkeypatch, exc):
    async def fake_exec(*args, **kwargs):
        return _RootChild(exc)

    monkeypatch.setattr(asyncio, "create_subprocess_exec", fake_exec)
    monkeypatch.setattr(health_mod, "KILL_WAIT_S", 0.05)
    rc, out = await run_cmd("sudo", "-n", "/usr/local/sbin/motogo-usbreset", timeout=0.05)
    assert rc == 124 and "timeout" in out and "motogo-usbreset" in out


def test_state_file_unreadable_is_tolerated(tmp_path):
    bad = tmp_path / "health.json"
    bad.write_text("{not json")
    env = FakeEnv()
    mon = _monitor(env, tmp_path)
    assert mon.policy.reconnects == 0


@pytest.mark.parametrize("text,expected", [("throttled=0x0", "0x0"), ("throttled=0xF000F", "0xF000F")])
def test_throttled_variants(text, expected):
    assert parse_throttled(text) == expected


# ─── OS pole v `sys` (reboot_required, os, kernel, last_unattended_at) ───────
def test_sys_metrics_os_fields(tmp_path, monkeypatch):
    from motogo_box import health_probe as hp

    osr = tmp_path / "os-release"
    osr.write_text('NAME="Debian GNU/Linux"\nPRETTY_NAME="Debian GNU/Linux 12 (bookworm)"\nID=debian\n')
    stamp = tmp_path / "upgrade-stamp"
    stamp.write_text("")
    monkeypatch.setattr(hp, "OS_RELEASE_PATH", str(osr))
    monkeypatch.setattr(hp, "UNATTENDED_STAMP_PATH", str(stamp))
    monkeypatch.setattr(hp, "REBOOT_REQUIRED_PATH", str(tmp_path / "reboot-required"))
    m = hp.sys_metrics()
    assert m["reboot_required"] is False and m["os"] == "Debian GNU/Linux 12 (bookworm)"
    assert isinstance(m["kernel"], str) and m["kernel"]
    assert m["last_unattended_at"] and m["last_unattended_at"].endswith("+00:00")
    (tmp_path / "reboot-required").write_text("*** System restart required ***\n")
    assert hp.sys_metrics()["reboot_required"] is True
    # chybějící soubory → None/False, nikdy výjimka
    monkeypatch.setattr(hp, "OS_RELEASE_PATH", str(tmp_path / "nope"))
    monkeypatch.setattr(hp, "UNATTENDED_STAMP_PATH", str(tmp_path / "nope2"))
    m = hp.sys_metrics()
    assert m["os"] is None and m["last_unattended_at"] is None
    assert hp.read_os_name(str(tmp_path / "nope")) is None
    (tmp_path / "junk").write_text("garbage\nPRETTY_NAME=\n")
    assert hp.read_os_name(str(tmp_path / "junk")) is None
    assert hp.file_mtime_iso(str(tmp_path / "missing")) is None


# ─── I/O síť (eth0) — hlídka a obnova profilu motogo-lan ─────────────────────
def _lan_monitor(env: FakeEnv, tmp_path, clock: FakeClock | None = None, **cfg_kw) -> HealthMonitor:
    return HealthMonitor(_cfg(**cfg_kw), "http://127.0.0.1:8080", run_cmd=env.run_cmd,
                         clock=clock or FakeClock(), state_path=str(tmp_path / "health.json"),
                         http=env.client(), uptime=lambda: 5000.0, tcp_probe=env.tcp_probe,
                         interfaces=env.interfaces)


def _lan_cmds(env: FakeEnv) -> list[tuple[str, ...]]:
    return [c for c in env.cmds if "motogo-lan" in c]


async def test_lan_ok_nothing_happens(tmp_path):
    env = FakeEnv()
    lan = await _lan_monitor(env, tmp_path).lan_state()
    assert lan == {"interface": "eth0", "state": "up", "ipv4": "192.168.50.10",
                   "ok": True, "problem": None, "action": None}
    assert _lan_cmds(env) == []


async def test_lan_no_link_is_reported_but_never_touched(tmp_path):
    """Mrtvý kabel/switch (stav down): software to neopraví → žádné nmcli, jen hlášení."""
    env = FakeEnv(lan=[{"name": "eth0", "state": "down", "ipv4": []}])
    mon = _lan_monitor(env, tmp_path)
    lan = await mon.lan_state()
    assert lan["problem"] == "no_link" and lan["ok"] is False and lan["ipv4"] is None
    assert lan["action"] is None and _lan_cmds(env) == []


async def test_lan_no_address_triggers_nmcli_up_once_per_window(tmp_path):
    """Link je, adresa ne (profil nenaskočil) → `nmcli con up`, ale nejvýš jednou za lan_recover_s."""
    clock = FakeClock()
    env = FakeEnv(lan=[{"name": "eth0", "state": "up", "ipv4": []}])
    mon = _lan_monitor(env, tmp_path, clock=clock, lan_recover_s=300)
    first = await mon.lan_state()
    assert first["problem"] == "no_address" and first["action"] == "lan_up"
    assert _lan_cmds(env) == [("sudo", "-n", "nmcli", "-w", "20", "con", "up", "motogo-lan")]
    clock.advance(299)
    assert (await mon.lan_state())["action"] is None     # okno ještě běží
    assert len(_lan_cmds(env)) == 1
    clock.advance(2)
    assert (await mon.lan_state())["action"] == "lan_up"
    assert len(_lan_cmds(env)) == 2


async def test_lan_recover_disabled_and_failed_nmcli(tmp_path):
    env = FakeEnv(lan=[{"name": "eth0", "state": "up", "ipv4": []}])
    off = await _lan_monitor(env, tmp_path, lan_recover_s=0).lan_state()
    assert off["problem"] == "no_address" and off["action"] is None and _lan_cmds(env) == []

    class Failing(FakeEnv):
        async def run_cmd(self, *args: str, timeout: float = 20) -> tuple[int, str]:
            self.cmds.append(args)
            if "motogo-lan" in args:
                return 4, "Error: Connection activation failed: device not ready"
            return await FakeEnv.run_cmd(self, *args, timeout=timeout)

    bad = Failing(lan=[{"name": "eth0", "state": "up", "ipv4": []}])
    assert (await _lan_monitor(bad, tmp_path).lan_state())["action"] == "lan_up_failed"


async def test_lan_missing_interface_and_unreadable_list(tmp_path):
    env = FakeEnv(lan=[{"name": "wlan0", "state": "up", "ipv4": []}])
    assert (await _lan_monitor(env, tmp_path).lan_state())["problem"] == "missing"

    class Broken(FakeEnv):
        async def interfaces(self) -> list[dict]:
            raise OSError("ip: not found")

    unknown = await _lan_monitor(Broken(), tmp_path).lan_state()
    assert unknown["ok"] is None and unknown["problem"] is None   # nezjištěno ≠ porucha (žádný falešný poplach)


async def test_cycle_payload_carries_lan(tmp_path):
    env = FakeEnv(lan=[{"name": "eth0", "state": "down", "ipv4": []}])
    payload = await _lan_monitor(env, tmp_path).cycle()
    assert payload["lan"]["problem"] == "no_link"
    assert env.posted[-1]["lan"]["ok"] is False     # dorazí do controlleru → status → Velín


# ─── režim RNDIS (modem jako síťová karta, bez ModemManageru) ────────────────
def _rndis_monitor(env: FakeEnv, tmp_path, **kw) -> HealthMonitor:
    cfg = _cfg(lte_mode="rndis", **kw)
    return HealthMonitor(cfg, "http://127.0.0.1:8080", run_cmd=env.run_cmd, clock=FakeClock(),
                         state_path=str(tmp_path / "health.json"), http=env.client(),
                         uptime=lambda: 5000.0, tcp_probe=env.tcp_probe, interfaces=env.interfaces)


async def test_rndis_healthy_interface_is_not_modem_gone(tmp_path, monkeypatch):
    """usb0 má adresu → zdravé. BEZ přepínače by `modem_gone` bylo trvale True (mmcli modem nemá)
    a jednotka by se resetovala pořád dokola."""
    env = FakeEnv(lan=[{"name": "eth0", "state": "up", "ipv4": [{"addr": "192.168.50.10", "prefix": 24}]},
                       {"name": "usb0", "state": "up", "ipv4": [{"addr": "10.1.2.3", "prefix": 24}]}])
    monkeypatch.setattr(health_mod, "usb_device_present", lambda *a, **k: True)
    mon = _rndis_monitor(env, tmp_path)
    lte = await mon.lte_info()
    assert lte["mode"] == "rndis" and lte["iface"] == "usb0" and lte["ipv4"] == "10.1.2.3"
    assert lte["modem_gone"] is False and lte["state"] == "connected"
    assert not any(c and c[0] == "mmcli" for c in env.cmds)      # ModemManager se vůbec nevolá


async def test_rndis_dead_interface_escalates_to_usb_reset(tmp_path, monkeypatch):
    env = FakeEnv(internet_ok=False, lan=[{"name": "usb0", "state": "down", "ipv4": []}])
    monkeypatch.setattr(health_mod, "usb_device_present", lambda *a, **k: True)
    mon = _rndis_monitor(env, tmp_path, action_cooldown_s=0)
    assert (await mon.cycle())["lte"]["modem_gone"] is True
    p2 = await mon.cycle()
    assert p2["actions"] == ["usb_reset"]                        # rovnou reset, žádné mmcli --reset
    assert mon.policy.modem_resets == 0
    assert ("sudo", "-n", mon.cfg.usb_reset_script) in env.cmds


# ─── návrat spojení: okamžitý resync kódů ────────────────────────────────────
async def test_resync_on_reconnect():
    """Po výpadku se kódy dotáhnou hned, ne až dalším sync_loopem (jinak by u boxu mohl platit starý kód)."""
    from motogo_box.controller_loops import resync_on_reconnect

    class Ctrl:
        def __init__(self, online):
            self.api = type("A", (), {"online": online})()
            self.resyncs = 0

        async def resync(self):
            self.resyncs += 1

    back = Ctrl(online=True)
    assert await resync_on_reconnect(back, was_online=False) is True and back.resyncs == 1
    steady = Ctrl(online=True)
    assert await resync_on_reconnect(steady, was_online=True) is True and steady.resyncs == 0
    down = Ctrl(online=False)
    assert await resync_on_reconnect(down, was_online=True) is False and down.resyncs == 0
