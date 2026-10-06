"""Hudba po zadání kódu VŽDY od začátku (zadání majitele 2026-10-06): `play_zone(..., restart=True)` z
`zone_access.start_music` (kód i pozdní otevření); oba enginy přetočí (`MpvPlayer.rewind`), ruční start ne."""
from __future__ import annotations

from motogo_box.audio import AudioController, AudioSelector
from motogo_box.mpv_player import MpvError, MpvPlayer
from motogo_box.models import HwRef, Zone, ZoneHw, ZoneState

from tests.test_audio import FakeIoBus, FakePlayer, _cfg
from tests.test_audio_multi import _rig
from tests.test_zone import rig_secured


class RwPlayer(FakePlayer):
    playlist_count = 1

    async def rewind(self) -> bool:
        self.log.append(("rewind",))
        return True


def _add_rewind(player) -> None:
    async def rewind() -> bool:
        player.log.append(("rewind",))
        return True
    player.rewind = rewind


def _selector(lib=None):
    zones = [Zone(hw=ZoneHw(zone=i, audio=HwRef("wav617b", i)), door_id=f"d{i}") for i in (1, 2)]
    player, cfg = RwPlayer(), _cfg()
    return AudioController(player, AudioSelector(FakeIoBus(), zones, cfg), cfg, lib, zones), player


async def test_zone_code_and_late_open_request_restart():
    r = await rig_secured()
    assert (await r.zc.grant_access(booking_id="b", kind="accessories", source="ui"))[0]
    assert r.audio.plays[-1][0] == 1 and r.audio.plays[-1][2] is True
    r.clock.advance(31)
    await r.zc.tick()                                        # OPEN_TIMEOUT → pozdní otevření (impulzní zámek)
    assert r.zc.state == ZoneState.SECURED and r.zc.latch_released
    await r.zc.on_input(False)
    assert r.zc.state == ZoneState.DOOR_OPEN and len(r.audio.plays) == 2 and r.audio.plays[-1][2] is True


async def test_selector_rewinds_paused_playlist_and_second_code():
    ctl, player = _selector()                                 # bez knihovny: legacy playlist načtený při startu
    await ctl.start()
    player.log.clear()
    assert await ctl.play_zone(1, restart=True)
    names = [e[0] for e in player.log]
    assert "rewind" in names and names.index("rewind") < names.index("play")
    player.log.clear()
    assert await ctl.play_zone(1, None, restart=True)         # 2. kód: už hraje → jen přetočit, bez fade/play
    assert player.log == [("rewind",)]
    player.log.clear()
    assert await ctl.play_zone(1)                             # ruční „Hudba ▶“: hraje dál
    assert player.log == []
    await ctl.stop()
    player.log.clear()
    assert await ctl.play_zone(1)                             # ruční start po pauze: bez přetáčení (jako dřív)
    assert ("rewind",) not in player.log
    await ctl.stop()


async def test_selector_fresh_playlist_needs_no_rewind():
    class Lib:
        def playlist_for(self, target: str) -> list[str]:
            return ["/m/a.mp3"] if target == "door:d1" else ["/m/c.mp3"]

        def status(self) -> dict:
            return {}

    ctl, player = _selector(Lib())
    await ctl.start()                                         # načten společný playlist (all)
    player.log.clear()
    assert await ctl.play_zone(1, restart=True)               # door:d1 → nový playlist začíná od 0
    assert ("rewind",) not in player.log and any(e[0] == "load_files" for e in player.log)
    await ctl.stop()


async def test_multi_rewinds_only_on_restart():
    eng, players, _ = _rig()
    for p in players.values():
        _add_rewind(p)
    await eng.start()
    out1 = players["out1"]
    out1.log.clear()
    assert await eng.play_zone(1, restart=True)               # playlist door:d1 načtený při startu, pauza uprostřed
    names = [e[0] for e in out1.log]
    assert "rewind" in names and names.index("rewind") < names.index("play") and "load_files" not in names
    out1.log.clear()
    assert await eng.play_zone(1, restart=True)               # už hraje → jen přetočit
    assert out1.log == [("rewind",)]
    out1.log.clear()
    assert await eng.play_zone(1) and out1.log == []          # bez restart beze změny
    await eng.sync_channels([1])
    await eng.wait_fade()
    assert ("rewind",) not in players["out9"].log             # venek (kanál) se nepřetáčí
    await eng.stop()
    await eng.reload_playlists()                              # změna knihovny → volný výstup načten znovu
    out1.log.clear()
    assert await eng.play_zone(1, restart=True)
    assert ("rewind",) in out1.log                            # načteno v reload_playlists (pauza) → přetočit
    await eng.stop()


class _IpcPlayer(MpvPlayer):
    """MpvPlayer s podvrženým IPC: zaznamená příkazy, `playlist-pos` vrací `pos` (výjimka = MpvError)."""

    def __init__(self, count: int, pos) -> None:
        super().__init__("/nonexistent/mpv.sock", "/nonexistent")
        self.playlist_count, self.pos, self.cmds = count, pos, []

    @property
    def alive(self) -> bool:
        return True

    async def command(self, *args):
        self.cmds.append(args)
        if args[:2] == ("get_property", "playlist-pos"):
            if isinstance(self.pos, Exception):
                raise self.pos
            return self.pos
        return None


async def test_mpv_rewind_uses_playlist_pos_or_seek():
    seek = ("seek", 0, "absolute")
    p = _IpcPlayer(0, 0)
    assert await p.rewind() is False and p.cmds == []
    p = _IpcPlayer(1, 0)
    assert await p.rewind() and p.cmds == [seek]               # jedna skladba → seek, bez dotazu na pozici
    p = _IpcPlayer(3, 2)
    assert await p.rewind() and p.cmds[-1] == ("set_property", "playlist-pos", 0)
    p = _IpcPlayer(3, -1)
    assert await p.rewind() and p.cmds[-1] == ("set_property", "playlist-pos", 0)
    p = _IpcPlayer(3, 0)
    assert await p.rewind() and p.cmds[-1] == seek
    p = _IpcPlayer(3, MpvError("x"))
    assert await p.rewind() and p.cmds[-1] == seek
