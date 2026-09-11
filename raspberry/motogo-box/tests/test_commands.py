"""Testy vzdálených příkazů (`motogo_box.commands.execute`) s falešným controllerem."""
from __future__ import annotations

import asyncio

from motogo_box import commands
from motogo_box.config_outdoor import OutdoorCfg
from motogo_box.models import HwRef, Signal, Zone, ZoneHw


class FakeZone:
    def __init__(self, number: int, door_id: str | None, box_number: int) -> None:
        self.zone = Zone(hw=ZoneHw(zone=number, lock=HwRef("wav645", number - 1)), door_id=door_id, box_number=box_number)
        self.number = number
        self.grants: list[tuple[str, str]] = []
        self.light_on = False
        self.signal: Signal | None = None
        self.signals: list[Signal] = []
        self.grant_ok = True
        self.expected: Signal = Signal.RED     # signál odpovídající stavu zóny (refresh_signal)

    async def grant_access(self, *, booking_id, kind, source):
        self.grants.append((kind, source))
        return (True, "ok") if self.grant_ok else (False, "busy")

    async def set_light(self, on: bool) -> bool:
        self.light_on = on
        return True

    async def set_signal(self, signal: Signal) -> None:
        self.signal = signal
        self.signals.append(signal)

    def expected_signal(self) -> Signal:
        return self.expected

    async def refresh_signal(self) -> None:
        """Jako reálná zóna: obnoví signál podle (fake) stavu, ne podle snapshotu před blikáním."""
        await self.set_signal(self.expected)

    async def test_sequence(self) -> dict:
        return {"light": True, "signal": True, "audio": True}


class FakeAudio:
    mode = "selector"

    def __init__(self) -> None:
        self.playing_zone: int | None = None
        self.tones: list[tuple[int, int]] = []

    async def play_zone(self, zone: int) -> bool:
        self.playing_zone = zone
        return True

    async def stop(self, fade: bool = True) -> None:
        self.playing_zone = None

    async def test_tone(self, zone: int, seconds: int = 5) -> bool:
        self.tones.append((zone, seconds))
        return True


class FakeAudioMulti(FakeAudio):
    mode = "multi"

    def __init__(self) -> None:
        super().__init__()
        self.channels: list[str] = []

    async def play_channel(self, name: str) -> bool:
        self.channels.append(name)
        return True

    async def stop_channel(self, name: str, fade: bool = True) -> bool:
        was = name in self.channels
        self.channels = [c for c in self.channels if c != name]
        return was


class FakeOutdoor:
    """Falešný OutdoorController (kontrakt §26): cfg, set_light, test_sequence, status."""

    def __init__(self, zone: int = 9, configured: bool = True) -> None:
        self.cfg = OutdoorCfg(zone=zone, light=HwRef("wav617b", 0) if configured else None, present=True)
        self.light_on = False
        self.lights: list[bool] = []
        self.tests = 0
        self.result: dict = {"light": True, "audio": None}

    async def set_light(self, on: bool) -> bool:
        self.lights.append(on)
        self.light_on = on
        return True

    async def test_sequence(self) -> dict:
        self.tests += 1
        return dict(self.result)

    def status(self) -> dict:
        return {"zone": self.cfg.zone, "configured": self.cfg.configured, "light": self.light_on}


class FakeSignals:
    def __init__(self, zones) -> None:
        self._zones = zones

    def current(self, zone: int) -> Signal:
        return self._zones[zone].signal or Signal.RED


class FakeController:
    def __init__(self) -> None:
        self.zones = {1: FakeZone(1, "door-1", 1), 2: FakeZone(2, "door-2", 2)}
        self.audio = FakeAudio()
        self.outdoor = FakeOutdoor()
        self.signals = FakeSignals(self.zones)
        self.ui_notice = None
        self.all_off_calls = 0
        self.resyncs = 0

    def find_zone(self, *, door_id=None, zone=None, box_number=None):
        for zc in self.zones.values():
            if door_id is not None and zc.zone.door_id == door_id:
                return zc
        if zone is not None:
            return self.zones.get(int(zone))
        if box_number is not None:
            return next((z for z in self.zones.values() if z.zone.box_number == box_number), None)
        return None

    async def all_off(self) -> None:
        self.all_off_calls += 1

    async def resync(self) -> dict:
        self.resyncs += 1
        return {"changed": False, "problems": []}


async def test_open_door_by_door_id_zone_and_box():
    c = FakeController()
    ok, res = await commands.execute(c, "open_door", {"door_id": "door-2", "relay_url": "http://x", "light_url": "y"})
    assert ok and res["zone"] == 2 and c.zones[2].grants == [("service", "velin")]
    ok, res = await commands.execute(c, "open_door", {"zone": "1"})
    assert ok and res["zone"] == 1 and c.zones[1].grants == [("service", "velin")]
    ok, res = await commands.execute(c, "open_door", {"box_number": 2})
    assert ok and len(c.zones[2].grants) == 2
    c.zones[1].grant_ok = False
    ok, res = await commands.execute(c, "open_door", {"zone": 1})
    assert not ok and res["reason"] == "busy"
    ok, res = await commands.execute(c, "open_door", {"zone": 9})
    assert not ok and res["error"] == "zone_not_found"


async def test_light_on_off():
    c = FakeController()
    ok, res = await commands.execute(c, "light_on", {"zone": 2})
    assert ok and c.zones[2].light_on is True and res == {"zone": 2, "light": True}
    ok, res = await commands.execute(c, "light_off", {"door_id": "door-2"})
    assert ok and c.zones[2].light_on is False
    ok, res = await commands.execute(c, "light_on", {})
    assert not ok and res["error"] == "zone_not_found"


async def test_set_signal():
    c = FakeController()
    ok, res = await commands.execute(c, "set_signal", {"zone": 1, "signal": "green_pulse"})
    assert ok and c.zones[1].signal == Signal.GREEN_PULSE and res["signal"] == "green_pulse"
    ok, res = await commands.execute(c, "set_signal", {"zone": 1, "signal": "purple"})
    assert not ok and res["error"] == "invalid_signal"
    assert c.zones[1].signal == Signal.GREEN_PULSE


async def test_all_off_and_reload():
    c = FakeController()
    assert await commands.execute(c, "all_off", {}) == (True, {})
    assert c.all_off_calls == 1
    ok, res = await commands.execute(c, "sync_config", None)
    assert ok and res["changed"] is False and c.resyncs == 1


async def test_unknown_command():
    c = FakeController()
    ok, res = await commands.execute(c, "fly_away", {})
    assert not ok and res["error"] == "unknown_command"


async def test_music_and_audio_test():
    c = FakeController()
    ok, res = await commands.execute(c, "music_on", {})
    assert ok and res["zone"] == 1 and c.audio.playing_zone == 1
    ok, res = await commands.execute(c, "music_on", {"zone": 2})
    assert ok and c.audio.playing_zone == 2
    assert await commands.execute(c, "music_off", {}) == (True, {})
    assert c.audio.playing_zone is None
    ok, res = await commands.execute(c, "audio_test", {"zone": 1, "seconds": 2})
    assert ok and c.audio.tones == [(1, 2)]
    ok, res = await commands.execute(c, "zone_test", {"zone": 2})
    assert ok and res == {"zone": 2, "light": True, "signal": True, "audio": True}


async def test_identify_blinks_and_restores():
    c = FakeController()
    c.zones[1].signal = c.zones[1].expected = Signal.RED
    c.zones[2].signal = c.zones[2].expected = Signal.GREEN
    ok, res = await commands.execute(c, "identify", {"label": "Petra"})
    assert ok and res["zones"] == 2
    assert c.ui_notice["title"].startswith("Tady jsem") and "Petra" in c.ui_notice["subtitle"]
    # po blikání se obnoví signál podle SKUTEČNÉHO stavu zóny (refresh_signal), ne snapshotu
    assert c.zones[1].signal == Signal.RED and c.zones[2].signal == Signal.GREEN
    assert c.zones[1].signals.count(Signal.GREEN) == 3 and c.zones[1].signals.count(Signal.OFF) == 3


async def test_identify_restores_state_changed_during_blink():
    c = FakeController()
    c.zones[1].signal = Signal.GREEN            # před identify svítila zelená (relace)
    c.zones[1].expected = Signal.RED            # během blikání se zóna zabezpečila
    ok, _ = await commands.execute(c, "identify", {})
    assert ok and c.zones[1].signal == Signal.RED


async def test_music_on_with_unknown_zone_does_not_fall_back_to_first():
    c = FakeController()
    ok, res = await commands.execute(c, "music_on", {"zone": 12})
    assert ok is False and res["error"] == "zone_not_found" and c.audio.playing_zone is None
    ok, res = await commands.execute(c, "music_on", {})
    assert ok is True and c.audio.playing_zone == 1


async def test_hw_commands_refused_when_not_ready():
    c = FakeController()
    c.ready = False
    ok, res = await commands.execute(c, "open_door", {"zone": 1})
    assert ok is False and res["error"] == "not_ready" and c.zones[1].grants == []
    ok, _ = await commands.execute(c, "reload", {})    # síťové/konfigurační příkazy fungují dál
    assert ok is True


async def test_handler_exception_is_reported_not_raised():
    c = FakeController()

    async def boom(*_):
        raise RuntimeError("kaboom")

    c.zones[1].set_light = boom
    ok, res = await commands.execute(c, "light_on", {"zone": 1})
    assert not ok and "kaboom" in res["error"]


# ─── zóna venku (outdoor, zone 9 — není dveře) ───────────────────────────────
async def test_outdoor_light_on_off_and_zone_test():
    c = FakeController()
    ok, res = await commands.execute(c, "light_on", {"zone": "9"})
    assert ok and res == {"zone": 9, "light": True, "outdoor": True} and c.outdoor.lights == [True]
    ok, res = await commands.execute(c, "light_off", {"zone": 9})
    assert ok and res["light"] is False and c.outdoor.lights == [True, False] and c.zones[1].light_on is False
    ok, res = await commands.execute(c, "zone_test", {"zone": 9})
    assert ok and res == {"zone": 9, "outdoor": True, "light": True, "audio": None} and c.outdoor.tests == 1
    c.outdoor.result = {"light": None, "audio": True}          # venek bez relé světla (jen audio výstup) → light None = OK
    ok, res = await commands.execute(c, "zone_test", {"zone": 9})
    assert ok and res["light"] is None and res["audio"] is True
    c.outdoor.result = {"light": True, "audio": False}
    ok, res = await commands.execute(c, "zone_test", {"zone": 9})
    assert not ok and res["audio"] is False
    c.outdoor.result = {"light": False, "audio": None, "error": "busy"}
    ok, res = await commands.execute(c, "zone_test", {"zone": 9})
    assert not ok and res["error"] == "busy"
    # venek není dveře: open_door / set_signal / audio_test → zone_not_found; nenastavený venek → zone_not_found
    for cmd, params in (("open_door", {"zone": 9}), ("set_signal", {"zone": 9, "signal": "green"}),
                        ("audio_test", {"zone": 9})):
        ok, res = await commands.execute(c, cmd, params)
        assert not ok and res["error"] == "zone_not_found", cmd
    assert c.zones[1].grants == [] and c.audio.tones == []
    c.outdoor = FakeOutdoor(configured=False)
    ok, res = await commands.execute(c, "light_on", {"zone": 9})
    assert not ok and res["error"] == "zone_not_found"
    del c.outdoor                                                # starší controller bez venku
    ok, res = await commands.execute(c, "light_on", {"zone": 9})
    assert not ok and res["error"] == "zone_not_found"


async def test_outdoor_music_requires_multi():
    c = FakeController()
    ok, res = await commands.execute(c, "music_on", {"zone": 9})
    assert not ok and res == {"error": "outdoor_requires_multi", "zone": 9} and c.audio.playing_zone is None
    ok, res = await commands.execute(c, "music_off", {"zone": 9})          # bez stop_channel → jen potvrzení
    assert ok and res == {"zone": 9, "channel": "outdoor"}
    c.audio = FakeAudioMulti()
    ok, res = await commands.execute(c, "music_on", {"zone": 9})
    assert ok and res == {"zone": 9, "channel": "outdoor"} and c.audio.channels == ["outdoor"]
    assert c.audio.playing_zone is None                                     # nikdy reproduktor kóje
    ok, res = await commands.execute(c, "music_off", {"zone": 9})
    assert ok and res == {"zone": 9, "channel": "outdoor"} and c.audio.channels == []
    ok, res = await commands.execute(c, "music_on", {"zone": 2})            # kóje dál přes play_zone
    assert ok and c.audio.playing_zone == 2 and c.audio.channels == []
    ok, res = await commands.execute(c, "music_on", {"door_id": "door-2", "zone": 9})   # door_id má přednost
    assert ok and res == {"zone": 2}


async def test_http_get_rejects_invalid_url():
    c = FakeController()
    ok, res = await commands.execute(c, "http_get", {"url": "ftp://x"})
    assert not ok and res["error"] == "invalid_url"


# ─── aktualizace (update_software / update_system → SoftwareUpdater) ─────────
class _Runner:
    def __init__(self) -> None:
        self.calls: list[list[str]] = []

    async def __call__(self, argv, timeout_s):
        self.calls.append(list(argv))
        return 0, "UPGRADED=1\nREBOOT_REQUIRED=0\n"


def _with_updater(tmp_path):
    from motogo_box.updater import SoftwareUpdater

    c = FakeController()
    runner = _Runner()
    c.updater = SoftwareUpdater(c, runner=runner, data_dir=str(tmp_path))
    c.updater.script_exists = lambda _p: True     # testovací stroj nemá /usr/local/sbin/motogo-sysupdate
    return c, runner


async def test_update_software_is_scheduled_not_awaited(tmp_path):
    c, runner = _with_updater(tmp_path)
    ok, res = await commands.execute(c, "update_software", {"ref": "8ceff42", "rollout_id": "r", "wait_idle_s": 60})
    assert ok and res == {"scheduled": True, "ref": "8ceff42", "wait_idle_s": 60}
    assert runner.calls == []                 # odpověď odchází HNED, běh je na pozadí
    assert "update_software" not in commands.TERMINAL_COMMANDS and "update_software" not in commands.HW_COMMANDS
    await c.updater.wait()
    assert runner.calls == [["sudo", "/usr/local/sbin/motogo-update"]] and c.updater.state == "done"
    ok, res = await commands.execute(c, "update_software", {"ref": "v1.2"})
    assert not ok and res["error"] == "invalid_ref"


async def test_update_system_scheduled_and_in_progress(tmp_path):
    c, runner = _with_updater(tmp_path)
    c.ready = False                           # není HW příkaz — funguje i mimo ready
    ok, res = await commands.execute(c, "update_system", {"auto_reboot": True})
    assert ok and res == {"scheduled": True, "wait_idle_s": 1800, "auto_reboot": True}
    ok, res = await commands.execute(c, "update_software", {})
    assert not ok and res["error"] == "update_in_progress"
    assert "update_system" not in commands.TERMINAL_COMMANDS
    await c.updater.wait()
    assert runner.calls == [["sudo", "/usr/local/sbin/motogo-sysupdate"]]
    assert c.updater.state == "done" and c.updater.reboot_required is False


async def test_restart_and_reboot_refused_while_update_script_runs(tmp_path):
    c, runner = _with_updater(tmp_path)
    started = asyncio.Event()

    async def slow_runner(argv, timeout_s):
        started.set()
        await asyncio.sleep(3600)                 # apt běží…
        return 0, ""

    c.updater.runner = slow_runner
    assert commands.update_blocks(c, "restart") is None
    assert (await commands.execute(c, "update_system", {}))[0]
    await asyncio.wait_for(started.wait(), 1)
    assert c.updater.script_running
    for cmd in ("restart", "reboot"):
        assert commands.update_blocks(c, cmd) == {"error": "update_in_progress", "command": cmd,
                                                  "state": "running", "kind": "system"}
        ok, res = await commands.execute(c, cmd, {})
        assert not ok and res["error"] == "update_in_progress"
    assert commands.update_blocks(c, "identify") is None
    await c.updater.cancel()
    assert commands.update_blocks(c, "restart") is None
    assert commands.update_blocks(FakeController(), "reboot") is None   # bez updateru → nic neblokuje


async def test_reboot_with_wait_idle_is_scheduled_via_updater(tmp_path):
    c, runner = _with_updater(tmp_path)
    c.active = [1]
    ok, res = await commands.execute(c, "reboot", {"wait_idle": True, "wait_idle_s": 60})
    assert ok and res == {"scheduled": True, "wait_idle_s": 60}
    assert runner.calls == [] and c.updater.state == "waiting" and c.updater.kind == "reboot"
    c.active = []
    await c.updater.wait()
    assert runner.calls == [["sudo", "systemctl", "reboot"]] and c.updater.state == "rebooting"


class _UnkillableProc:
    """Nezabitelný sudo (root) potomek: `kill()` hází PermissionError, `communicate()` nikdy neskončí."""

    returncode = None

    def __init__(self) -> None:
        self.kill_calls = 0

    async def communicate(self):
        await asyncio.sleep(3600)

    def kill(self) -> None:
        self.kill_calls += 1
        raise PermissionError(1, "Operation not permitted")


async def test_run_timeout_survives_unkillable_sudo_child(monkeypatch):
    """A10: timeout na sudo potomkovi → 'timeout' (ne EPERM z proc.kill), volání se nevyhodí."""
    proc = _UnkillableProc()

    async def fake_exec(*argv, **kw):
        return proc

    monkeypatch.setattr(commands.asyncio, "create_subprocess_exec", fake_exec)
    monkeypatch.setattr(commands, "SUBPROCESS_TIMEOUT_S", 0.05)
    ok, detail = await commands._run("sudo", "systemctl", "reboot")
    assert ok is False and detail == {"error": "timeout", "argv": ["sudo", "systemctl", "reboot"]}
    assert proc.kill_calls == 1
