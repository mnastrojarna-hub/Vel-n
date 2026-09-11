"""Integrační smoke test: celý `BoxController` proti in-process simulátoru hardwaru.

Bez sítě — Supabase míří na `http://127.0.0.1:1` (spojení odmítnuto ihned → offline
cache), mpv chybí (přehrávač v dummy režimu, reléový selektor se přesto přepíná).
Simulátor: 3× `SimRelayModule` (wav645, wav617a, wav617b) + 4× `SimShelly` na
dynamických portech; hardwarová mapa je vygenerovaná ze `config/sim-9zone.yaml`
(8 zón + venek: venkovní světlo wav617b R1 svítí po dobu relace + doběh).
"""
from __future__ import annotations

import asyncio
import copy
import os
import signal
import socket
import subprocess
import sys
import time
from typing import Any, Callable

import pytest
import yaml

from motogo_box import commands
from motogo_box.config import load_hardware_file, load_local
from motogo_box.controller import BoxController
from motogo_box.models import Signal, ZoneState
from motogo_box.pins import hmac_code
from motogo_box.storage import Storage
from motogo_box.supabase_api import SupabaseApi
from motogo_box.tools.simulator import SimRelayModule, SimShelly

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM_MAP = os.path.join(ROOT, "config", "sim-9zone.yaml")
DEVICE_ID = "11111111-2222-4333-8444-555555555555"
DEVICE_TOKEN = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
API_URL = "http://127.0.0.1:1"          # nic neposlouchá → ECONNREFUSED okamžitě
PIN_OK = "123456"
SERVICE_CODE = "servis1"

# Zóna 3 dle brno mapy: zámek wav645[2], kontakt wav617a in 2, světlo wav617a[2],
# audio wav617b[3], červená shelly1 light 4, zelená shelly2 light 0. Venek: světlo wav617b[0].
Z3_LOCK, Z3_CONTACT, Z3_LIGHT, Z3_AUDIO = 2, 2, 2, 3
Z3_RED, Z3_GREEN = ("shelly1", 4), ("shelly2", 0)
OUTDOOR_LIGHT = 0
ZONES = 8


# ─── pomocné ─────────────────────────────────────────────────────────────────
async def wait_until(pred: Callable[[], bool], timeout: float, what: str = "podmínka") -> None:
    """Aktivně čeká (po 20 ms), dokud `pred()` neplatí; jinak selže po `timeout` s."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if pred():
            return
        await asyncio.sleep(0.02)
    raise AssertionError(f"{what} nenastala do {timeout} s")


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def write_hw_map(path: str, ports: dict[str, int], timings: dict[str, Any]) -> dict:
    """Sim mapa s reálnými porty simulátoru a zkrácenými časy; vrací výsledný dict."""
    raw = load_hardware_file(SIM_MAP)
    for name, port in ports.items():
        raw["devices"][name]["port"] = port
        raw["devices"][name]["host"] = "127.0.0.1"
    raw["timings"].update(timings)
    with open(path, "w", encoding="utf-8") as f:
        yaml.safe_dump(raw, f, allow_unicode=True)
    return raw


def write_local_config(path: str, data_dir: str, hw_file: str, web_port: int) -> None:
    cfg = {
        "supabase": {"url": API_URL, "anon_key": "anon-test"},
        "device": {"id": DEVICE_ID, "token": DEVICE_TOKEN, "name": "sim"},
        "paths": {"data_dir": data_dir, "music_dir": os.path.join(data_dir, "music"),
                  "hardware_file": hw_file, "mpv_socket": os.path.join(data_dir, "mpv.sock")},
        "web": {"host": "127.0.0.1", "port": web_port},
        "intervals": {"heartbeat_s": 30, "sync_s": 60, "command_poll_s": 10,
                      "status_report_s": 30, "outbox_flush_s": 60},
        "log_level": "INFO",
    }
    with open(path, "w", encoding="utf-8") as f:
        yaml.safe_dump(cfg, f)


def sync_payload(hw_raw: dict) -> dict:
    """Payload ve tvaru `kiosk_sync_config`: 8 dveří s `hw` = zóny mapy, `hardware.outdoor` = venek, hashované kódy."""
    doors = []
    for item in hw_raw["zones"]:
        n = int(item["zone"])
        doors.append({"id": f"door-{n}", "door_kind": "motorcycle", "box_number": n,
                      "label": f"Kóje {n}", "hw": copy.deepcopy(item), "relay_url": None, "light_url": None})
    return {
        "ok": True, "synced_at": "2026-09-09T10:00:00+00:00", "branch_name": "Brno (sim)",
        "hardware": {"outdoor": copy.deepcopy(hw_raw["outdoor"])},
        "timings": {"door_open_seconds": 30, "light_seconds": 30, "music_seconds": 10},
        "music_on_url": None, "music_off_url": None, "power_status_url": None, "power_poll_seconds": 60,
        "doors": doors,
        "service_codes": [{"h": hmac_code(DEVICE_ID, DEVICE_TOKEN, SERVICE_CODE)}],
        "codes": [{"h": hmac_code(DEVICE_ID, DEVICE_TOKEN, PIN_OK), "kind": "motorcycle", "booking_id": "b1",
                   "valid_from": None, "valid_until": None, "door_id": "door-3", "box_number": 3}],
    }


class Sim:
    """In-process simulátor: 3 Modbus moduly + 4 Shelly na dynamických portech."""

    def __init__(self) -> None:
        self.modules = {
            "wav645": SimRelayModule("wav645", port=0, name="wav645"),
            "wav617a": SimRelayModule("wav617", port=0, name="wav617a"),
            "wav617b": SimRelayModule("wav617", port=0, name="wav617b"),
        }
        self.shellies = {f"shelly{i}": SimShelly(port=0, name=f"shelly{i}") for i in range(1, 5)}

    async def start(self) -> None:
        for srv in [*self.modules.values(), *self.shellies.values()]:
            await srv.start()

    async def stop(self) -> None:
        for srv in [*self.modules.values(), *self.shellies.values()]:
            await srv.stop()

    @property
    def ports(self) -> dict[str, int]:
        return {**{n: m.port for n, m in self.modules.items()}, **{n: s.port for n, s in self.shellies.items()}}

    def all_coils(self) -> dict[str, list[bool]]:
        return {n: list(m.coils) for n, m in self.modules.items()}

    def coils_all_off(self) -> bool:
        return not any(any(m.coils) for m in self.modules.values())

    def light(self, dev: str, lid: int) -> bool:
        return bool(self.shellies[dev].lights[lid]["on"])

    def audio_coils(self, hw_raw: dict) -> list[bool]:
        return [self.modules[z["audio"]["dev"]].coils[int(z["audio"]["coil"])] for z in hw_raw["zones"]]


@pytest.fixture
async def sim():
    s = Sim()
    await s.start()
    try:
        yield s
    finally:
        await s.stop()


async def drain_log_tasks() -> None:
    """Počká na fire-and-forget úlohy `emit` (odeslání do Supabase → outbox)."""
    tasks = [t for t in asyncio.all_tasks() if t.get_name().startswith("motogo.log.") and not t.done()]
    if tasks:
        await asyncio.wait_for(asyncio.gather(*tasks, return_exceptions=True), 10)


# ─── end-to-end ──────────────────────────────────────────────────────────────
async def test_box_controller_end_to_end(sim: Sim, tmp_path) -> None:
    data_dir = tmp_path / "data"
    (data_dir / "music").mkdir(parents=True)
    hw_file = str(tmp_path / "hardware.yaml")
    hw_raw = write_hw_map(hw_file, sim.ports, {"music_after_close_s": 1, "light_after_close_s": 2,
                                                "door_close_debounce_ms": 500})
    cfg_file = str(tmp_path / "config.yaml")
    write_local_config(cfg_file, str(data_dir), hw_file, free_port())
    local = load_local(cfg_file)
    assert local.supabase.url == API_URL and local.paths.hardware_file == hw_file

    storage = Storage(str(data_dir / "motogo.db"))
    payload = sync_payload(hw_raw)
    storage.kv_set("remote_config", payload)
    storage.save_code_cache(payload)
    api = SupabaseApi(local.supabase.url, local.supabase.anon_key, DEVICE_ID, DEVICE_TOKEN, storage, "test")
    ctrl = BoxController(local, storage, api, "test")

    # „Špinavý" HW před startem: sepnutá relé a rozsvícená světla musí start vypnout (§12).
    sim.modules["wav645"].coils[5] = True
    sim.modules["wav617a"].coils[1] = True
    sim.shellies["shelly3"].lights[2]["on"] = True
    # Všechny kontakty zavřené (closed_level 1 → vstup True = zavřeno) — výchozí stav simulátoru.
    assert all(all(m.inputs) for m in sim.modules.values() if m.inputs)

    try:
        await asyncio.wait_for(ctrl.start(), 30)
        assert ctrl.ready and ctrl.hardware.source == "remote" and len(ctrl.zones) == ZONES
        assert ctrl.branch_name == "Brno (sim)"
        assert ctrl.config_problems == []
        assert ctrl.hardware.outdoor.zone == 9 and ctrl.outdoor.cfg.configured and not ctrl.outdoor.light_on

        # Start: all_off proběhl (špinavá relé jsou vypnutá), Shelly nejdřív vše zhasla, pak RED.
        assert sim.coils_all_off(), sim.all_coils()
        for name, sh in sim.shellies.items():
            first_on = next((i for i, c in enumerate(sh.calls) if c["params"].get("on")), None)
            offs = [c["params"]["id"] for c in sh.calls[:first_on] if c["method"] == "Light.Set"
                    and c["params"].get("on") is False]
            assert set(offs) >= {0, 1, 2, 3, 4}, f"{name}: all_off nepředcházel rozsvícení ({sh.calls[:8]})"
        for z in hw_raw["zones"]:
            n = int(z["zone"])
            zc = ctrl.zones[n]
            assert zc.state == ZoneState.SECURED and zc.fault is None and zc.door_closed is True
            assert ctrl.signals.current(n) == Signal.RED
            assert sim.light(z["red"]["dev"], int(z["red"]["light"])) is True
            assert sim.light(z["green"]["dev"], int(z["green"]["light"])) is False
            assert zc.zone.door_id == f"door-{n}"
        snap = ctrl.snapshot()
        assert all(snap["modules"].values()) and set(snap["modules"]) == set(sim.ports)
        assert snap["audio"]["player_ok"] is False        # mpv není → dummy režim
        assert snap["outdoor"]["configured"] is True and snap["outdoor"]["zone"] == 9 and snap["outdoor"]["light"] is False
        assert snap["outdoor"]["light_ref"] == "wav617b[0]" and snap["outdoor"]["music"] is False

        # ── platný kód: API padne → offline cache → zóna 3 ──
        lock = sim.modules["wav645"]
        task = asyncio.create_task(ctrl.submit_code(PIN_OK))
        await wait_until(lambda: lock.coils[Z3_LOCK], 5, "flash-on zámku zóny 3")
        t_on = time.monotonic()
        await wait_until(lambda: not lock.coils[Z3_LOCK], 2.5, "automatické vypnutí zámku")
        assert 0.5 <= time.monotonic() - t_on <= 1.5
        res = await asyncio.wait_for(task, 10)
        assert res["ok"] is True and res["kind"] == "motorcycle" and res["zone"] == 3, res
        assert res["error"] is None and "Otevřeno" in res["message"]
        z3 = ctrl.zones[3]
        assert z3.state == ZoneState.WAITING_FOR_OPEN and z3.booking_id == "b1"
        assert sim.modules["wav617a"].coils[Z3_LIGHT] is True and z3.light_on
        assert sim.light(*Z3_GREEN) is True and sim.light(*Z3_RED) is False
        assert ctrl.signals.current(3) == Signal.GREEN
        assert ctrl.audio.playing_zone == 3
        audio = sim.audio_coils(hw_raw)
        assert audio[2] is True and sum(audio) == 1, audio        # jen wav617b coil 3
        assert not lock.coils[Z3_LOCK]
        await wait_until(lambda: sim.modules["wav617b"].coils[OUTDOOR_LIGHT], 2, "venkovní světlo po zadání kódu")
        assert ctrl.outdoor.light_on and ctrl.snapshot()["outdoor"]["active"] is True

        # ── otevření dveří → DOOR_OPEN, zavření → CLOSED_CONFIRMATION → SECURED ──
        sim.modules["wav617a"].set_input(Z3_CONTACT, False)
        await wait_until(lambda: z3.state == ZoneState.DOOR_OPEN, 3, "DOOR_OPEN")
        assert z3.door_closed is False and sim.light(*Z3_GREEN) is True
        assert sim.modules["wav617b"].coils[Z3_AUDIO] is True
        sim.modules["wav617a"].set_input(Z3_CONTACT, True)
        await wait_until(lambda: z3.state == ZoneState.CLOSED_CONFIRMATION, 4, "CLOSED_CONFIRMATION")
        assert ctrl.signals.current(3) == Signal.RED
        # stav se přepne před doručením Light.Set do Shelly → na světla počkat
        await wait_until(lambda: sim.light(*Z3_RED) and not sim.light(*Z3_GREEN), 2, "červená po zavření")
        assert sim.modules["wav617a"].coils[Z3_LIGHT] is True          # světlo ještě svítí (doběh)
        await wait_until(lambda: ctrl.audio.playing_zone is None, 3, "vypnutí hudby po 1 s")
        await wait_until(lambda: z3.state == ZoneState.SECURED, 4, "SECURED po doběhu světla")
        assert sim.modules["wav617a"].coils[Z3_LIGHT] is False and not z3.light_on
        assert sim.modules["wav617b"].coils[Z3_AUDIO] is False and sum(sim.audio_coils(hw_raw)) == 0
        # venek: světlo svítí ještě light_after_close_s (2 s) po poslední relaci, pak zhasne
        assert sim.modules["wav617b"].coils[OUTDOOR_LIGHT] is True and ctrl.snapshot()["outdoor"]["active"] is False
        await wait_until(lambda: not sim.modules["wav617b"].coils[OUTDOOR_LIGHT], 4, "venkovní světlo zhaslo po doběhu")
        assert not ctrl.outdoor.light_on
        assert sim.coils_all_off(), sim.all_coils()
        assert z3.booking_id is None and z3.last_event == "SESSION_COMPLETED"
        kinds = [e["kind"] for e in storage.events_recent(50)]
        for kind in ("ACCESS_GRANTED", "DOOR_OPENED", "DOOR_CLOSED", "SESSION_COMPLETED", "STARTUP"):
            assert kind in kinds, kinds

        # ── servisní heslo ──
        res = await asyncio.wait_for(ctrl.submit_code(SERVICE_CODE), 10)
        assert res["ok"] is True and res["kind"] == "service" and res["service_token"]
        assert len(res["doors"]) == ZONES and all(d["configured"] for d in res["doors"])
        assert ctrl.check_service_token(res["service_token"]) and not ctrl.check_service_token("x")

        # ── neplatný kód a lockout po 5 pokusech ──
        res = await asyncio.wait_for(ctrl.submit_code("000000"), 10)
        assert res["ok"] is False and res["error"] == "invalid_code" and res["kind"] == "invalid"
        for i in range(1, 4):
            res = await asyncio.wait_for(ctrl.submit_code(f"00000{i}"), 10)
            assert res["ok"] is False and res["error"] == "invalid_code"
        res = await asyncio.wait_for(ctrl.submit_code("000009"), 10)     # 5. selhání → lockout
        assert res["error"] == "locked" and res["locked_until"] and res["locked_until"] > time.time()
        res = await asyncio.wait_for(ctrl.submit_code(PIN_OK), 10)       # i platný kód je odmítnut
        assert res["ok"] is False and res["error"] == "locked"
        assert ctrl.zones[3].state == ZoneState.SECURED

        # ── vzdálený příkaz přes handle_command (complete_command → outbox, síť není) ──
        await asyncio.wait_for(ctrl.handle_command({"id": "cmd-1", "command": "light_on", "params": {"zone": 1}}), 10)
        assert sim.modules["wav617a"].coils[0] is True
        await asyncio.wait_for(ctrl.handle_command({"id": "cmd-2", "command": "light_on", "params": {"zone": 9}}), 10)
        assert sim.modules["wav617b"].coils[OUTDOOR_LIGHT] is True and ctrl.outdoor.manual is True   # venek ručně
        ok, result = await commands.execute(ctrl, "music_on", {"zone": 9})
        assert ok is False and result["error"] == "outdoor_requires_multi"       # selector: venek nehraje
        await drain_log_tasks()
        assert any(kind == "complete_command" for _, kind, _ in storage.outbox_pending(200))

        # ── all_off: vše vypnout, zóny zpět do klidu ──
        ok, result = await asyncio.wait_for(commands.execute(ctrl, "all_off", {}), 15)
        assert ok is True and result == {}
        assert sim.coils_all_off(), sim.all_coils()
        assert ctrl.audio.playing_zone is None and ctrl.audio.selector.active_zone is None
        assert not ctrl.outdoor.light_on and ctrl.outdoor.manual is None
        assert all(zc.state == ZoneState.SECURED for zc in ctrl.zones.values())
        assert sim.light(*Z3_RED) is True and sim.light(*Z3_GREEN) is False
        ok, result = await commands.execute(ctrl, "neexistuje", {})
        assert ok is False and result["error"] == "unknown_command"

        snap = ctrl.snapshot()
        assert len(snap["zones"]) == ZONES and snap["zones"][2]["state"] == "SECURED"
        assert snap["zones"][2]["door_id"] == "door-3" and snap["zones"][2]["signal"] == "red"
        assert snap["ready"] is True and snap["internet"] is False and snap["config_source"] == "remote"
        assert set(snap["modules"]) == set(sim.ports)
    finally:
        await asyncio.wait_for(ctrl.stop(), 20)
        await drain_log_tasks()
        await api.close()
        storage.close()

    assert ctrl.ready is False
    assert sim.coils_all_off(), sim.all_coils()
    assert sim.modules["wav617b"].coils[Z3_AUDIO] is False
    assert sim.light(*Z3_RED) is True                       # zavřené zóny zůstávají červené
    leftover = [t.get_name() for t in asyncio.all_tasks() if t.get_name().startswith("motogo.")]
    assert not leftover, leftover


# ─── proces `python -m motogo_box controller` (bez sítě, bez simulátoru) ─────
def test_controller_process_starts_and_stops_on_sigterm(tmp_path) -> None:
    data_dir = tmp_path / "data"
    (data_dir / "music").mkdir(parents=True)
    port = free_port()
    cfg_file = str(tmp_path / "config.yaml")
    write_local_config(cfg_file, str(data_dir), SIM_MAP, port)
    env = {**os.environ, "MOTOGO_CONFIG": cfg_file, "PYTHONUNBUFFERED": "1"}
    env.pop("NOTIFY_SOCKET", None)
    env.pop("WATCHDOG_USEC", None)
    proc = subprocess.Popen([sys.executable, "-m", "motogo_box", "controller"], cwd=ROOT, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        deadline = time.monotonic() + 20
        body = None
        while time.monotonic() < deadline and proc.poll() is None:
            try:
                out = subprocess.run(["curl", "-s", "-m", "2", f"http://127.0.0.1:{port}/api/state"],
                                     capture_output=True, text=True, timeout=5)
                if out.returncode == 0 and out.stdout.strip().startswith("{"):
                    body = out.stdout
                    break
            except (subprocess.TimeoutExpired, OSError):
                pass
            time.sleep(0.25)
        assert proc.poll() is None, f"proces skončil předčasně: {proc.stdout.read() if proc.stdout else ''}"
        assert body is not None, "GET /api/state neodpověděl do 20 s"
        assert '"zones"' in body and '"modules"' in body
        proc.send_signal(signal.SIGTERM)
        t0 = time.monotonic()
        output = proc.communicate(timeout=10)[0]
        assert time.monotonic() - t0 <= 5, f"ukončení trvalo příliš dlouho:\n{output[-2000:]}"
        assert proc.returncode == 0, output[-2000:]
        assert "Traceback" not in output, output[-3000:]
        assert "Ukončuji" in output
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.communicate(timeout=5)
