"""Testy režimu multi (`audio_multi.AudioMulti`): nezávislé kanály, playlisty cílů, venek, selhání."""
from __future__ import annotations

import asyncio
import os

from motogo_box.audio_build import audio_signature, build_audio
from motogo_box.audio_multi import AudioMulti
from motogo_box.config import AudioCfg, HardwareConfig, LocalConfig, TimingsCfg, load_hardware_file
from motogo_box.models import HwRef, Zone, ZoneHw

HW_FILE = os.path.join(os.path.dirname(__file__), "..", "config", "brno-9zone.yaml")


class FakePlayer:
    """Přehrávač jednoho výstupu: zaznamenává příkazy, `load_files` si pamatuje playlist."""

    def __init__(self, name: str, alive: bool = True, device: str | None = None) -> None:
        self.name, self.alive, self.device = name, alive, device
        self.volume = 0
        self.playlist_count = 0
        self.files: list[str] = []
        self.log: list[tuple] = []
        self.loads = 0

    async def start(self) -> None:
        self.log.append(("start",))

    async def stop(self) -> None:
        self.log.append(("stop",))

    async def load_playlist(self, shuffle: bool = True) -> int:
        self.log.append(("load_playlist", shuffle))
        return 0

    async def load_files(self, files: list[str], shuffle: bool = True) -> int:
        self.loads += 1
        self.files = list(files)
        self.playlist_count = len(files)
        self.log.append(("load_files", tuple(files)))
        return len(files)

    async def play(self) -> None:
        self.log.append(("play",))

    async def pause(self) -> None:
        self.log.append(("pause",))

    async def set_volume(self, vol: int) -> bool:
        self.volume = vol
        self.log.append(("volume", vol))
        return self.alive

    async def fade(self, to: int, ms: int, steps: int = 10) -> bool:
        self.log.append(("fade", to, ms))
        self.volume = to
        return self.alive


class FakeLibrary:
    def __init__(self, lists: dict[str, list[str]]) -> None:
        self.lists = lists

    def playlist_for(self, target: str) -> list[str]:
        return list(self.lists.get(target) or self.lists.get("all") or [])

    def status(self) -> dict:
        return {"tracks": sum(len(v) for v in self.lists.values()), "synced": 1, "pending": 0, "failed": 0,
                "last_sync_at": None, "targets": {k: len(v) for k, v in self.lists.items()}}


class FakeBus:
    def __init__(self) -> None:
        self.calls: list[tuple[HwRef, bool]] = []

    async def set(self, ref: HwRef, on: bool) -> bool:
        self.calls.append((ref, on))
        return True


class Clock:
    def __init__(self) -> None:
        self.t = 100.0

    def __call__(self) -> float:
        return self.t


def _cfg() -> AudioCfg:
    return AudioCfg(volume=70, fade_in_ms=5, fade_out_ms=5, shuffle=False, mode="multi")


def _rig(alive: dict[str, bool] | None = None, lists: dict[str, list[str]] | None = None, relays=None, bus=None):
    alive = alive or {}
    players = {o: FakePlayer(o, alive=alive.get(o, True), device=f"alsa/{o}") for o in ("out1", "out2", "out9")}
    lib = FakeLibrary(lists if lists is not None else {
        "door:d1": ["/m/tracks/a.mp3", "/m/tracks/b.mp3"], "all": ["/m/tracks/c.mp3"], "outdoor": ["/m/tracks/v.mp3"]})
    clock = Clock()
    eng = AudioMulti(players, {1: "out1", 2: "out2"}, {"outdoor": "out9"}, relays, _cfg(), lib, bus=bus,
                     zone_targets={1: "door:d1", 2: "door:d2"}, timings=TimingsCfg(music_after_close_s=10), clock=clock)
    return eng, players, clock


async def test_two_zones_play_simultaneously_with_own_playlists():
    eng, players, _ = _rig()
    await eng.start()
    assert players["out1"].files == ["/m/tracks/a.mp3", "/m/tracks/b.mp3"]   # start načte playlist cíle výstupu
    assert players["out2"].files == ["/m/tracks/c.mp3"]                      # door:d2 nemá vlastní → all
    assert await eng.play_zone(1) and await eng.play_zone(2)
    await eng.wait_fade()
    assert eng.playing_zones == [1, 2] and eng.playing_zone == 1
    assert eng.is_playing(1) and eng.is_playing(2) and not eng.is_playing(3)
    for out in ("out1", "out2"):
        assert players[out].log[-2:] == [("play",), ("fade", 70, 5)]
    assert players["out1"].loads == 1 and players["out2"].loads == 1        # playlist se nenačítá znovu
    # stop_zone jiné zóny nic neutne
    assert await eng.stop_zone(3) is False
    assert eng.playing_zones == [1, 2]
    assert await eng.stop_zone(2) is True
    assert eng.playing_zones == [1] and players["out2"].log[-2:] == [("fade", 0, 5), ("pause",)]
    assert ("pause",) not in players["out1"].log[-2:]
    await eng.stop()
    assert eng.playing_zones == [] and eng.status()["playing_zone"] is None


async def test_outdoor_starts_with_first_session_and_stops_after_delay():
    eng, players, clock = _rig()
    await eng.start()
    await eng.sync_channels([])
    assert eng.channels_playing == []
    await eng.sync_channels([3])
    assert eng.channels_playing == []                    # start běží na pozadí — tick na něj nečeká
    await eng.wait_fade()
    assert eng.channels_playing == ["outdoor"] and players["out9"].files == ["/m/tracks/v.mp3"]
    assert eng.playing_zones == []                       # venek není zóna
    await eng.sync_channels([])                          # poslední relace skončila → odložený stop
    clock.t += 9
    await eng.sync_channels([])
    assert eng.channels_playing == ["outdoor"]
    await eng.sync_channels([2])                         # nová relace ruší odložený stop
    clock.t += 20
    await eng.sync_channels([2])
    assert eng.channels_playing == ["outdoor"]
    await eng.sync_channels([])
    clock.t += 10
    await eng.sync_channels([])
    await eng.wait_fade()
    assert eng.channels_playing == [] and players["out9"].log[-2:] == [("fade", 0, 5), ("pause",)]
    st = eng.status()
    assert st["mode"] == "multi" and st["channels"] == [] and st["players"]["out9"]["alive"] is True
    assert st["playlist_count"] == 4 and st["library"]["tracks"] == 4 and "out1=alsa/out1" in st["device"]


async def test_all_fallback_and_empty_playlist():
    eng, players, _ = _rig(lists={"all": ["/m/x.mp3"]})
    await eng.start()
    assert players["out1"].files == ["/m/x.mp3"] and players["out9"].files == ["/m/x.mp3"]
    eng2, players2, _ = _rig(lists={})
    await eng2.start()
    assert players2["out1"].playlist_count == 0
    assert await eng2.play_zone(1) is True               # relé/stav se drží i bez skladeb (nic nehraje)
    assert await eng2.test_tone(1, 0) is False           # test tónu prázdný playlist odmítne


async def test_dead_player_does_not_affect_others():
    eng, players, _ = _rig(alive={"out1": False})
    await eng.start()
    assert eng.player_ok is False
    assert await eng.play_zone(1) is True and await eng.play_zone(2) is True
    await eng.wait_fade()
    assert eng.playing_zones == [1, 2] and players["out2"].volume == 70
    assert await eng.test_tone(1, 0) is False            # mrtvý mpv zóny 1
    assert eng.status()["players"]["out1"]["alive"] is False and eng.status()["players"]["out2"]["alive"] is True


async def test_test_tone_only_on_zone_output():
    eng, players, _ = _rig()
    await eng.start()
    for p in players.values():
        p.log.clear()
    assert await eng.test_tone(2, 0) is True
    assert ("play",) in players["out2"].log and players["out2"].log[-2:] == [("fade", 0, 5), ("pause",)]
    assert ("play",) not in players["out1"].log and ("play",) not in players["out9"].log
    assert eng.playing_zones == []


async def test_test_tone_does_not_stop_music_taken_over_by_session():
    eng, players, _ = _rig()
    await eng.start()
    task = asyncio.create_task(eng.test_tone(1, 1))
    await asyncio.sleep(0.05)
    assert eng.is_playing(1)
    await eng.stop_zone(1)
    assert await eng.play_zone(1)                        # relace převzala výstup během testu
    await task
    assert eng.is_playing(1)                             # test nesmí vypnout cizí hudbu


async def test_reload_while_playing_is_deferred():
    eng, players, _ = _rig()
    await eng.start()
    assert await eng.play_zone(1)
    eng.library.lists["door:d1"] = ["/m/tracks/n.mp3"]
    eng.library.lists["all"] = ["/m/tracks/c.mp3", "/m/tracks/d.mp3"]
    await eng.reload_playlists()
    assert players["out1"].files == ["/m/tracks/a.mp3", "/m/tracks/b.mp3"]   # hraje → neutnout
    assert players["out2"].files == ["/m/tracks/c.mp3", "/m/tracks/d.mp3"]   # volný výstup hned
    await eng.stop_zone(1)
    assert await eng.play_zone(1)
    assert players["out1"].files == ["/m/tracks/n.mp3"]                      # po zastavení nový playlist


async def test_enable_relays_and_all_off():
    bus = FakeBus()
    r1, r9 = HwRef("wav617b", 1), HwRef("wav645", 10)
    eng, players, _ = _rig(relays={1: r1, "outdoor": r9}, bus=bus)
    await eng.start()
    assert await eng.play_zone(1)
    await eng.sync_channels([1])
    await eng.sync_channels([1])                         # běžící přechod se nespouští dvakrát
    await eng.wait_fade()
    assert bus.calls == [(r1, True), (r9, True)]
    await eng.reselect_if_playing("wav645")
    assert bus.calls[-1] == (r9, True)
    await eng.all_off()
    assert (r1, False) in bus.calls and (r9, False) in bus.calls
    assert eng.playing_zones == [] and eng.channels_playing == []
    await eng.close()
    assert all(p.log[-1] == ("stop",) for p in players.values())


def test_build_audio_multi_and_signature():
    d = load_hardware_file(HW_FILE)
    # legacy alias `audio.channels.outdoor` (relé wav645 coil 10 = R11 rezerva) → doplní `outdoor.audio`
    d["audio"].update({"mode": "multi", "outputs": {f"out{i}": {"device": f"alsa/plughw:CARD=Box{i}"} for i in range(1, 10)},
                       "channels": {"outdoor": {"out": "out9", "trigger": "any", "dev": "wav645", "coil": 10}}})
    for i, z in enumerate(d["zones"][:7], start=1):
        z["audio"] = {"out": f"out{i}"}
    d["zones"][7]["audio"] = {"out": "out8", "dev": "wav645", "coil": 9}      # šatna: výstup + enable relé (R10)
    hw = HardwareConfig.from_dict(d)
    assert hw.zones[0].hw.audio_out == "out1" and hw.zones[0].hw.audio is None
    assert hw.zones[7].hw.audio == HwRef("wav645", 9) and hw.zones[7].hw.to_dict()["audio"] == {"dev": "wav645", "coil": 9, "out": "out8"}
    assert hw.outdoor.audio_out == "out9" and hw.outdoor.audio == HwRef("wav645", 10) and hw.outdoor.light == HwRef("wav617b", 0)
    eng = build_audio(hw, LocalConfig(), None, None)
    assert isinstance(eng, AudioMulti) and set(eng.players) == {f"out{i}" for i in range(1, 10)}
    assert eng.players["out3"].socket_path.endswith("mpv.sock.out3") and eng.players["out3"].name == "out3"
    assert eng.channel_out == {"outdoor": "out9"} and eng.relays["outdoor"] == HwRef("wav645", 10)
    assert eng.relays[8] == HwRef("wav645", 9) and eng.targets[1] == "zone:1"
    d["audio"].pop("channels")                                            # kanonický tvar dává stejný engine
    d["outdoor"]["audio"] = {"out": "out9", "dev": "wav645", "coil": 10}
    eng2 = build_audio(HardwareConfig.from_dict(d), LocalConfig(), None, None)
    assert eng2.channel_out == eng.channel_out and eng2.relays == eng.relays
    assert audio_signature(HardwareConfig.from_dict(d).audio) == audio_signature(hw.audio)
    sig = audio_signature(hw.audio)
    assert sig[0] == "multi" and sig != audio_signature(HardwareConfig.from_dict(load_hardware_file(HW_FILE)).audio)
    sel = build_audio(HardwareConfig.from_dict(load_hardware_file(HW_FILE)), LocalConfig(), None, None)
    assert sel.mode == "selector" and sel.targets[1] == "zone:1"
    assert Zone(hw=ZoneHw(zone=1), door_id="d1").door_id == "d1"


async def test_sync_channels_does_not_block_on_slow_player():
    """Zaseknuté IPC venkovního mpv nesmí zdržet tick smyčku zón (start běží na pozadí)."""
    eng, players, _ = _rig()
    await eng.start()
    slow = players["out9"]

    async def slow_play() -> None:
        await asyncio.sleep(0.3)
        slow.log.append(("play",))
    slow.play = slow_play
    loop = asyncio.get_running_loop()
    t0 = loop.time()
    await eng.sync_channels([1])
    assert loop.time() - t0 < 0.1
    await eng.wait_fade()
    assert eng.channels_playing == ["outdoor"] and ("play",) in slow.log
    await eng.all_off()                                  # zruší i rozběhnutý přechod
    assert eng.channels_playing == []


def test_build_audio_drops_relays_on_lock_or_light_coils(caplog):
    """Druhá vrstva ochrany (§12): relé enable na cívce zámku/světla zóny se nikdy nesepne."""
    d = load_hardware_file(HW_FILE)
    lock, light = d["zones"][0]["lock"], d["zones"][1]["light"]
    d["audio"].update({"mode": "multi", "outputs": {"out1": {"device": "alsa/a"}, "out2": {"device": "alsa/b"},
                                                    "out9": {"device": "alsa/v"}},
                       "channels": {"outdoor": {"out": "out9", "dev": lock["dev"], "coil": lock["coil"]}}})
    d["zones"] = [dict(d["zones"][0], audio={"out": "out1", "dev": light["dev"], "coil": light["coil"]}),
                  dict(d["zones"][1], audio={"out": "out2", "dev": "wav645", "coil": 15})]
    hw = HardwareConfig.from_dict(d)
    with caplog.at_level("ERROR", logger="motogo.audio"):
        eng = build_audio(hw, LocalConfig(), None, None)
    assert isinstance(eng, AudioMulti) and eng.relays == {2: HwRef("wav645", 15)}
    assert sum("koliduje se zámkem/světlem" in r.message for r in caplog.records) == 2
    d["audio"]["channels"] = {"outdoor": {"out": "out9", "dev": "wav617b", "coil": 0}}   # = venkovní světlo (outdoor.light)
    with caplog.at_level("ERROR", logger="motogo.audio"):
        eng = build_audio(HardwareConfig.from_dict(d), LocalConfig(), None, None)
    assert "outdoor" not in eng.relays and eng.channel_out == {"outdoor": "out9"}


async def test_manual_channel_play_stop_and_sessions():
    """Ruční start venku drží do stop_channel; relace ruční režim ruší; stop_channel bez relace = ticho."""
    eng, players, clock = _rig()
    await eng.start()
    assert await eng.play_channel("chodba") is False and await eng.stop_channel("chodba") is False
    assert await eng.play_channel("outdoor") is True
    ch = eng.channels["out9"]
    assert eng.channels_playing == ["outdoor"] and ch.manual is True and eng.status()["players"]["out9"]["manual"] is True
    await eng.sync_channels([])
    clock.t += 1000
    await eng.sync_channels([])                          # bez relací se ručně spuštěný kanál nezastaví
    await eng.wait_fade()
    assert eng.channels_playing == ["outdoor"] and ch.off_at is None
    await eng.sync_channels([2])                         # relace → automatický režim
    assert ch.manual is None and eng.channels_playing == ["outdoor"]
    assert await eng.stop_channel("outdoor") is True
    assert eng.channels_playing == [] and ch.manual is False
    await eng.sync_channels([])
    clock.t += 100
    await eng.sync_channels([])
    await eng.wait_fade()
    assert eng.channels_playing == []                    # ručně zastavený se bez relace sám nespustí
    await eng.sync_channels([1])                         # nová relace ho spustí
    await eng.wait_fade()
    assert eng.channels_playing == ["outdoor"] and ch.manual is None
    await eng.sync_channels([])
    clock.t += 10
    await eng.sync_channels([])
    await eng.wait_fade()
    assert eng.channels_playing == [] and ch.manual is None
    assert await eng.stop_channel("outdoor") is False    # nehraje → False, ale manual=False
    assert ch.manual is False
    await eng.play_channel("outdoor")
    await eng.all_off()
    assert ch.manual is None and eng.channels_playing == []


async def test_test_channel_only_on_channel_output():
    eng, players, _ = _rig()
    await eng.start()
    for p in players.values():
        p.log.clear()
    assert await eng.test_channel("outdoor", 0) is True
    assert ("play",) in players["out9"].log and players["out9"].log[-2:] == [("fade", 0, 5), ("pause",)]
    assert ("play",) not in players["out1"].log and ("play",) not in players["out2"].log
    assert eng.channels_playing == [] and eng.channels["out9"].manual is None
    assert await eng.test_channel("chodba", 0) is False
    eng2, _, _ = _rig(lists={"all": []})
    await eng2.start()
    assert await eng2.test_channel("outdoor", 0) is False   # prázdný playlist


async def test_selector_channel_stubs():
    from motogo_box.audio import AudioController, AudioSelector
    from motogo_box.config import AudioCfg as _AudioCfg
    player = FakePlayer("mpv")
    sel = AudioController(player, AudioSelector(FakeBus(), [], _AudioCfg()), _AudioCfg(), None, [])
    assert sel.channels_playing == [] and await sel.play_channel("outdoor") is False
    assert await sel.stop_channel("outdoor") is False and await sel.test_channel("outdoor", 1) is False
    await sel.sync_channels([1])
