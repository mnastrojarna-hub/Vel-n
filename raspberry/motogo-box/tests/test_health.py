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
    disk_free_pct, mem_free_pct, parse_meminfo, parse_mmcli_modem, parse_mmcli_signal,
    parse_nmcli_connection, parse_throttled, read_cpu_temp,
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
                 "access_tech": None, "registration": None, "failed_reason": None}


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
    base = dict(check_interval_s=30, reconnect_after=5, usb_reset_after=5, reboot_after=3,
                min_uptime_before_reboot_s=1800)
    base.update(kw)
    return HealthCfg(**base)


def _drive(policy: LtePolicy, failures: int, uptime: float) -> list[str]:
    """Nechá politiku projít `failures` neúspěšnými kroky a vrátí všechny vydané akce."""
    out: list[str] = []
    for _ in range(failures):
        out += policy.step(False, uptime)
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


def test_policy_ladder_reconnect_usb_reset_reboot():
    p = LtePolicy(_cfg(), FakeClock())
    actions = _drive(p, 5 * 5, 5000.0)          # 5 reconnectů
    assert actions == ["reconnect"] * 5
    assert p.reconnects == 5 and p.reconnect_failures == 5 and p.usb_resets == 0
    assert _drive(p, 5, 5000.0) == ["usb_reset"]  # 6. dávka → USB reset
    assert p.usb_resets == 1 and p.reconnect_failures == 0 and p.usb_resets_pending == 1
    # další dva cykly (5 reconnectů + reset) → 3 resety
    for _ in range(2):
        a = _drive(p, 30, 5000.0)
        assert a.count("reconnect") == 5 and a.count("usb_reset") == 1
    assert p.usb_resets == 3 and p.usb_resets_pending == 3
    # hned další výpadek s dostatečným uptime → reboot; počítadla obnovy vynulovaná
    assert p.step(False, 5000.0) == ["reboot"]
    assert p.reboots == 1 and p.usb_resets_pending == 0 and p.reconnect_failures == 0
    assert p.last_action == "reboot"


def test_policy_no_reboot_before_min_uptime():
    p = LtePolicy(_cfg(), FakeClock())
    _drive(p, 30 * 3, 100.0)
    assert p.usb_resets_pending == 3
    # uptime 100 s < 1800 s → místo rebootu pokračuje žebříček (reconnecty)
    assert _drive(p, 5, 100.0) == ["reconnect"]
    assert p.reboots == 0
    # jakmile uptime dovolí, další výpadek → reboot
    assert p.step(False, 1800.0) == ["reboot"]


def test_policy_recovery_after_usb_reset_clears_pending():
    p = LtePolicy(_cfg(reconnect_after=1, usb_reset_after=1, reboot_after=2), FakeClock())
    assert p.step(False, 5000.0) == ["reconnect"]
    assert p.step(False, 5000.0) == ["usb_reset"]
    assert p.step(True, 5000.0) == []
    assert p.usb_resets_pending == 0 and p.usb_resets == 1   # lifetime počítadlo zůstává


def test_policy_persist_roundtrip():
    p = LtePolicy(_cfg(), FakeClock(50.0))
    _drive(p, 30, 5000.0)
    d = p.to_dict()
    q = LtePolicy(_cfg(), FakeClock(60.0))
    q.load(d)
    assert q.to_dict() == d
    q.load({"reconnects": "x", "usb_resets": -4, "last_online": "??"})
    assert q.reconnects == 5 and q.usb_resets == 0 and q.last_online is None   # vadné ignoruje, záporné ořeže
    q.load(None)


# ─── monitor s falešným prostředím ───────────────────────────────────────────
class FakeEnv:
    """Falešné `run_cmd` + HTTP transport: nic nesahá na síť ani sudo."""

    def __init__(self, internet_ok: bool = True, modem_ok: bool = True, *, tcp_ok: bool | None = None,
                 failing_hosts: set[str] | None = None, modem_state: str = "connected",
                 failed_reason: str | None = None) -> None:
        self.internet_ok, self.modem_ok = internet_ok, modem_ok
        self.tcp_ok = internet_ok if tcp_ok is None else tcp_ok
        self.failing_hosts = failing_hosts or set()   # HTTP cíle, které selžou i při internet_ok
        d = json.loads(MMCLI_MODEM)
        d["modem"]["generic"].update({"state": modem_state, "state-failed-reason": failed_reason or "none"})
        self.modem_json = json.dumps(d)
        self.cmds: list[tuple[str, ...]] = []
        self.posted: list[dict] = []
        self.tcp_probes = 0

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
                         http=env.client(), uptime=lambda: uptime, tcp_probe=env.tcp_probe)


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
                        tcp_probe=env.tcp_probe)
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
