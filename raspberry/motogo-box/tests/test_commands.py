"""Testy vzdálených příkazů (`motogo_box.commands.execute`) s falešným controllerem."""
from __future__ import annotations

from motogo_box import commands
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


class FakeSignals:
    def __init__(self, zones) -> None:
        self._zones = zones

    def current(self, zone: int) -> Signal:
        return self._zones[zone].signal or Signal.RED


class FakeController:
    def __init__(self) -> None:
        self.zones = {1: FakeZone(1, "door-1", 1), 2: FakeZone(2, "door-2", 2)}
        self.audio = FakeAudio()
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


async def test_http_get_rejects_invalid_url():
    c = FakeController()
    ok, res = await commands.execute(c, "http_get", {"url": "ftp://x"})
    assert not ok and res["error"] == "invalid_url"
