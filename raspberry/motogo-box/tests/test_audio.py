"""Testy audio vrstvy: selektor (exkluzivita relé, pořadí kroků), controller, MpvPlayer dummy/fade."""
from __future__ import annotations

import asyncio
import os

import pytest

from motogo_box.audio import AudioController, AudioSelector, MpvPlayer
from motogo_box.config import AudioCfg
from motogo_box.models import HwRef, Zone, ZoneHw


class FakeIoBus:
    """In-memory cívky; `set` zaznamenává volání a hlídá max. počet současně sepnutých audio relé."""

    def __init__(self, fail_refs: set[HwRef] | None = None, fail_on_refs: set[HwRef] | None = None) -> None:
        self.coils: dict[HwRef, bool] = {}
        self.calls: list[tuple[HwRef, bool]] = []
        self.fail_refs = fail_refs or set()          # set selže vždy (relé neodpovídá)
        self.fail_on_refs = fail_on_refs or set()    # selže jen sepnutí (vypnutí projde)
        self.max_on = 0

    async def set(self, ref: HwRef, on: bool) -> bool:
        self.calls.append((ref, on))
        if ref in self.fail_refs or (on and ref in self.fail_on_refs):
            return False
        self.coils[ref] = on
        self.max_on = max(self.max_on, sum(1 for v in self.coils.values() if v))
        return True

    def on_refs(self) -> set[HwRef]:
        return {r for r, v in self.coils.items() if v}


class FakePlayer:
    """Zaznamenává příkazy controlleru; `fade` vrací hlasitost okamžitě."""

    def __init__(self, alive: bool = True) -> None:
        self.alive = alive
        self.volume = 0
        self.log: list[tuple] = []

    async def start(self) -> None:
        self.log.append(("start",))

    async def stop(self) -> None:
        self.log.append(("stop",))

    async def load_playlist(self, shuffle: bool = True) -> int:
        self.log.append(("load_playlist", shuffle))
        return 3

    async def play(self) -> None:
        self.log.append(("play",))

    async def pause(self) -> None:
        self.log.append(("pause",))

    async def set_volume(self, vol: int) -> None:
        self.volume = vol
        self.log.append(("volume", vol))

    async def fade(self, to: int, ms: int, steps: int = 10) -> None:
        self.log.append(("fade", to, ms))
        self.volume = to


def _zones(n: int = 3) -> list[Zone]:
    return [Zone(hw=ZoneHw(zone=i, audio=HwRef("wav617b", i)), box_number=i) for i in range(1, n + 1)]


def _cfg() -> AudioCfg:
    return AudioCfg(volume=70, fade_in_ms=20, fade_out_ms=10, selector_settle_ms=5, selector_on_ms=3)


# ─── AudioSelector ─────────────────────────────────────────────────────────
async def test_selector_step_order_and_exclusivity():
    bus = FakeIoBus()
    zones = _zones()
    sel = AudioSelector(bus, zones, _cfg())
    assert await sel.select(2) is True
    assert sel.active_zone == 2
    refs = [z.hw.audio for z in zones]
    # kroky: všechna relé OFF (ověřeno) → teprve potom JEDNO relé ON
    assert bus.calls[:3] == [(r, False) for r in refs]
    assert bus.calls[3] == (HwRef("wav617b", 2), True)
    assert len(bus.calls) == 4
    assert bus.on_refs() == {HwRef("wav617b", 2)}
    # přepnutí na jinou zónu: nejdřív všechna off, pak nová on — nikdy 2 současně
    await sel.select(3)
    assert bus.on_refs() == {HwRef("wav617b", 3)}
    assert bus.max_on == 1
    on_calls = [c for c in bus.calls if c[1]]
    assert on_calls == [(HwRef("wav617b", 2), True), (HwRef("wav617b", 3), True)]
    await sel.release()
    assert sel.active_zone is None and bus.on_refs() == set()


async def test_selector_settle_and_on_delays():
    bus = FakeIoBus()
    cfg = AudioCfg(selector_settle_ms=60, selector_on_ms=40)
    sel = AudioSelector(bus, _zones(1), cfg)
    loop = asyncio.get_running_loop()
    t0 = loop.time()
    assert await sel.select(1) is True
    assert loop.time() - t0 >= 0.09


async def test_selector_refuses_when_off_not_verified():
    bad = HwRef("wav617b", 1)
    bus = FakeIoBus(fail_refs={bad})
    sel = AudioSelector(bus, _zones(3), _cfg())
    assert await sel.select(3) is False
    assert sel.active_zone is None
    # relé zóny 3 nesmělo být nikdy sepnuto, dokud nebyla všechna ověřeně vypnutá
    assert all(not on for _, on in bus.calls)
    assert bus.on_refs() == set()


async def test_selector_on_failure_turns_everything_off():
    target = HwRef("wav617b", 2)
    bus = FakeIoBus(fail_on_refs={target})
    sel = AudioSelector(bus, _zones(3), _cfg())
    assert await sel.select(2) is False
    assert sel.active_zone is None
    # po neúspěšném sepnutí následuje další kolo vypnutí všech relé
    idx = bus.calls.index((target, True))
    assert [c for c in bus.calls[idx + 1:]] == [(HwRef("wav617b", i), False) for i in (1, 2, 3)]


async def test_selector_zone_without_audio_ref():
    bus = FakeIoBus()
    sel = AudioSelector(bus, [Zone(hw=ZoneHw(zone=5))], _cfg())
    assert await sel.select(5) is False
    assert bus.calls == []


# ─── AudioController ───────────────────────────────────────────────────────
async def test_controller_play_zone_sequence_and_switch():
    bus = FakeIoBus()
    player = FakePlayer()
    cfg = _cfg()
    ctl = AudioController(player, AudioSelector(bus, _zones(), cfg), cfg)
    await ctl.start()
    assert player.log == [("start",), ("load_playlist", True), ("volume", 0), ("pause",)]
    player.log.clear()
    bus.calls.clear()

    assert await ctl.play_zone(1) is True
    assert ctl.playing_zone == 1
    await ctl.wait_fade()                          # fade-in běží na pozadí (pulz zámku nečeká)
    # ztlumit + pauza PŘED přepínáním relé, play + fade-in AŽ PO výběru
    assert player.log == [("volume", 0), ("pause",), ("play",), ("fade", 70, 20)]
    assert bus.on_refs() == {HwRef("wav617b", 1)}

    player.log.clear()
    assert await ctl.play_zone(1) is True          # stejná zóna → nic
    assert player.log == []

    bus.calls.clear()
    assert await ctl.play_zone(2) is True
    assert ctl.playing_zone == 2
    await ctl.wait_fade()
    # nejdřív fade-out + pauza (stop jiné zóny), release, pak nová sekvence
    assert player.log[:2] == [("fade", 0, 10), ("pause",)]
    assert player.log[-2:] == [("play",), ("fade", 70, 20)]
    assert bus.on_refs() == {HwRef("wav617b", 2)}
    assert bus.max_on == 1
    first_on = next(i for i, c in enumerate(bus.calls) if c[1])
    assert all(not on for _, on in bus.calls[:first_on])   # vše off před sepnutím

    player.log.clear()
    await ctl.stop()
    assert player.log == [("fade", 0, 10), ("pause",)]
    assert ctl.playing_zone is None and bus.on_refs() == set()


async def test_controller_play_zone_fails_when_selector_fails():
    bus = FakeIoBus(fail_on_refs={HwRef("wav617b", 2)})
    player = FakePlayer()
    cfg = _cfg()
    ctl = AudioController(player, AudioSelector(bus, _zones(), cfg), cfg)
    assert await ctl.play_zone(2) is False
    assert ctl.playing_zone is None
    assert ("play",) not in player.log
    assert bus.on_refs() == set()


async def test_controller_all_off_and_test_tone():
    bus = FakeIoBus()
    player = FakePlayer()
    cfg = _cfg()
    ctl = AudioController(player, AudioSelector(bus, _zones(), cfg), cfg)
    assert await ctl.play_zone(3) is True
    player.log.clear()
    await ctl.all_off()
    assert player.log == [("pause",), ("volume", 0)]
    assert ctl.playing_zone is None and bus.on_refs() == set()

    player.log.clear()
    assert await ctl.test_tone(1, seconds=0) is True
    assert ("play",) in player.log and player.log[-2:] == [("fade", 0, 10), ("pause",)]
    assert ctl.playing_zone is None and bus.on_refs() == set()
    await ctl.close()
    assert player.log[-1] == ("stop",)


async def test_controller_works_with_dead_player():
    bus = FakeIoBus()
    cfg = _cfg()
    ctl = AudioController(FakePlayer(alive=False), AudioSelector(bus, _zones(), cfg), cfg)
    await ctl.start()
    assert ctl.player_ok is False
    assert await ctl.play_zone(1) is True      # selektor funguje i bez zvuku
    await ctl.stop()
    assert bus.on_refs() == set()


# ─── MpvPlayer ─────────────────────────────────────────────────────────────
async def test_mpv_dummy_mode_when_binary_missing(tmp_path, monkeypatch):
    music = tmp_path / "music"
    music.mkdir()
    (music / "a.mp3").write_bytes(b"x")
    (music / "b.txt").write_bytes(b"x")
    monkeypatch.setenv("PATH", str(tmp_path / "nobin"))   # mpv nedostupné
    player = MpvPlayer(str(tmp_path / "mpv.sock"), str(music))
    args = player._mpv_args()  # noqa: SLF001
    assert args[:2] == ["mpv", "--idle=yes"] and "--loop-playlist=inf" in args
    assert f"--input-ipc-server={tmp_path / 'mpv.sock'}" in args
    assert "--audio-device=alsa/x" in MpvPlayer("s", "m", "alsa/x")._mpv_args()  # noqa: SLF001
    await player.start()
    assert player.alive is False
    assert player.list_files() == [str(music / "a.mp3")]
    assert await player.load_playlist() == 0
    assert await player.command("get_property", "volume") is None
    await player.play()
    await player.set_volume(50)
    await player.fade(80, 10)
    assert player.volume == 80
    await player.pause()
    await player.stop()


async def test_mpv_ipc_against_fake_socket(tmp_path):
    """Fake mpv IPC server na unix socketu: ověří request_id, odpovědi a lineární fade."""
    sock = str(tmp_path / "mpv.sock")
    received: list[dict] = []

    async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        import json
        while line := await reader.readline():
            msg = json.loads(line)
            received.append(msg)
            cmd = msg["command"]
            if cmd[0] == "get_property":
                reply = {"data": 42, "error": "success", "request_id": msg["request_id"]}
            elif cmd[0] == "bad":
                reply = {"error": "invalid parameter", "request_id": msg["request_id"]}
            elif cmd[0] == "hang":
                continue
            else:
                reply = {"error": "success", "request_id": msg["request_id"]}
            writer.write((json.dumps(reply) + "\n").encode())
            await writer.drain()

    server = await asyncio.start_unix_server(handle, path=sock)
    player = MpvPlayer(sock, str(tmp_path))
    # simulace „proces běží": bez spouštění mpv jen připojíme IPC
    class _Proc:
        returncode = None
        pid = 1
    player._proc = _Proc()  # noqa: SLF001
    assert await player._connect_ipc()  # noqa: SLF001
    assert player.alive is True
    try:
        assert await player.command("get_property", "volume") == 42
        assert received[-1]["request_id"] == 1
        from motogo_box.audio import MpvError
        with pytest.raises(MpvError):
            await player.command("bad")
        await player.set_volume(0)
        await player.fade(100, 40, steps=4)
        vols = [m["command"][2] for m in received if m["command"][:2] == ["set_property", "volume"]]
        assert vols == [0, 25, 50, 75, 100]
        assert player.volume == 100
        await player.play()
        assert received[-1]["command"] == ["set_property", "pause", False]
        import motogo_box.mpv_player as mp
        mp.IPC_TIMEOUT_S = 0.1
        with pytest.raises(MpvError):
            await player.command("hang")
    finally:
        mp.IPC_TIMEOUT_S = 2.0
        player._proc = None  # noqa: SLF001
        await player.stop()
        server.close()
        await server.wait_closed()
    assert not os.path.exists(sock)
