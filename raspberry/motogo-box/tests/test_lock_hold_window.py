"""Okno drženého zámku (`lock_hold_min_s`, 2026-10-06) — regresní testy z review: 2. kód v okně, dozvuk po vypnutí
zámku, šatna a kód motorky ve fázi `lock_wait`, hudba/venek jako dřív po SECURED, čas sepnutí před zápisem cívky."""
from __future__ import annotations

from dataclasses import replace
from types import SimpleNamespace

from motogo_box.controller import BoxController
from motogo_box.models import EventKind, ZoneState

from tests.test_lock_hold import _open_close, grant, lock_on, rig_hold
from tests.test_zone import Rig


def pull_during_music(r: Rig) -> None:
    """Zákazník zatáhne za dveře uprostřed pomalých kroků grantu (hudba) — jednorázově."""
    orig = r.audio.play_zone

    async def play_and_pull(zone: int, *a, **kw) -> bool:
        r.audio.play_zone = orig                                  # type: ignore[method-assign]
        await r.zc.on_input(False)
        r.clock.advance(0.6)
        return await orig(zone, *a, **kw)

    r.audio.play_zone = play_and_pull                             # type: ignore[method-assign]


def wardrobe(r: Rig) -> None:
    r.zone = r.zc.zone = replace(r.zone, kind="accessories", hw=replace(r.zone.hw, light_until_moto_code=True))


async def test_second_code_door_pulled_during_grant_is_not_forced():
    r = await rig_hold(light_after_close_s=10)
    await _open_close(r)
    r.clock.advance(10)
    await r.zc.tick()                                             # 31 s: lock_wait, zámek 1. kódu drží
    pull_during_music(r)
    assert (await r.zc.grant_access(booking_id="b-2", kind="motorcycle", source="ui")) == (True, "ok")
    assert r.zc.state == ZoneState.DOOR_OPEN and r.zc.booking_id == "b-2" and r.zc.fault is None
    assert lock_on(r) is True and r.zc.lock_held_since == 1031.6   # nové minimum od zápisu cívky
    assert r.kinds()[-2:] == [EventKind.ACCESS_GRANTED, EventKind.DOOR_OPENED]
    r.clock.advance(5)
    await r.zc.tick()
    assert r.zc.state == ZoneState.DOOR_OPEN and EventKind.FORCED_OPEN not in r.kinds()


async def test_second_code_hold_failed_with_door_pulled_continues_session():
    r = await rig_hold(light_after_close_s=10)
    await _open_close(r)
    pull_during_music(r)
    r.io.pulse_ok = False                                         # nové držení modul nepotvrdí
    assert (await r.zc.grant_access(booking_id="b-2", kind="motorcycle", source="ui")) == (False, "lock_failed")
    assert r.zc.state == ZoneState.DOOR_OPEN and r.zc.booking_id == "b-2" and r.zc.fault is None
    assert not r.zc.lock_held and EventKind.FORCED_OPEN not in r.kinds() and r.light() is True


async def test_door_seen_in_release_grace_is_same_session():
    r = await rig_hold(light_after_close_s=10)
    await _open_close(r)
    r.clock.advance(39)
    await r.zc.tick()                                             # 60 s: zámek vypnut, dozvuk
    assert lock_on(r) is False and r.zc.state == ZoneState.CLOSED_CONFIRMATION
    r.clock.advance(0.4)
    await r.zc.on_input(False)                                    # zatažené v posledních 0,4 s držení
    assert r.zc.state == ZoneState.DOOR_OPEN and r.zc.booking_id == "b-1" and EventKind.FORCED_OPEN not in r.kinds()


async def test_lock_wait_stops_music_and_light_like_secured():
    r = await rig_hold(light_after_close_s=0, music_after_close_s=10)   # výchozí Velín
    await _open_close(r)                                          # 21 s: zavřeno
    assert r.zc.state == ZoneState.CLOSED_CONFIRMATION and r.zc.lock_wait and lock_on(r) is True
    assert r.audio.playing_zone is None and r.light() is False    # jako dřív SECURED hned po zavření
    ctrl = SimpleNamespace(zones={1: r.zc})                       # venek nepočítá, aktualizace/přestavba počkají
    assert BoxController._sessions_active(ctrl) == [1] and BoxController._sessions_active(ctrl, lock_wait=False) == []
    r.clock.advance(39)
    await r.zc.tick()
    r.clock.advance(1)
    await r.zc.tick()                                             # 61 s: SECURED
    assert r.zc.state == ZoneState.SECURED and not r.zc.lock_wait and r.audio.stops == 1


async def test_moto_code_in_lock_wait_turns_wardrobe_light_off():
    r = await rig_hold(light_after_close_s=0)
    wardrobe(r)
    await _open_close(r)                                          # 21 s: lock_wait, světlo šatny drží
    assert r.zc.lock_wait and r.light() is True
    r.clock.advance(21)                                           # 42 s: kód motorky, zámek šatny drží do 60 s
    assert await r.zc.light_off_after_moto_code() is True and r.light() is False
    r.clock.advance(18)
    await r.zc.tick()
    r.clock.advance(1)
    await r.zc.tick()                                             # 61 s
    assert r.zc.state == ZoneState.SECURED and r.light() is False and r.zc.light_hold_since is None


async def test_moto_code_during_close_window_darkens_at_its_end_even_after_reopen():
    r = await rig_hold(light_after_close_s=30)
    wardrobe(r)
    await _open_close(r)
    r.clock.advance(9)                                            # 30 s: doběh po zavření ještě běží
    assert await r.zc.light_off_after_moto_code() is False and r.light() is True
    r.clock.advance(21)
    await r.zc.tick()                                             # 51 s: konec doběhu → zhasnout
    assert r.zc.lock_wait and r.light() is False
    await r.zc.on_input(False)                                    # znovu otevřeno: rozsvítit
    assert r.zc.state == ZoneState.DOOR_OPEN and r.light() is True and not r.zc.lock_wait
    await r.zc.on_input(True)
    r.clock.advance(1)
    await r.zc.tick()
    for step in (30, 1):
        r.clock.advance(step)
        await r.zc.tick()
    assert r.zc.state == ZoneState.SECURED and r.light() is False and r.zc.light_hold_since is None


async def test_lock_held_since_taken_before_slow_hold_write():
    r = await rig_hold()
    orig = r.io.hold

    async def slow_hold(ref, ms: int) -> bool:
        ok = await orig(ref, ms)
        r.clock.advance(2.8)                                      # ověření read_coils + retry (nestabilní modul)
        return ok

    r.io.hold = slow_hold                                         # type: ignore[method-assign]
    await grant(r)
    assert r.zc.lock_held_since == 1000.0                         # SW minimum nikdy nepřesáhne HW časovač (61 s)
