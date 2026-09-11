"""`play_channel(hold=False)` (kontrakt §6 doplněk): obnova hudby venku po servisním testu během relace —
kanál se spustí BEZ ručního režimu, dál ho řídí `sync_channels` (doběh po poslední relaci)."""
from __future__ import annotations

from tests.test_audio_multi import _rig


async def test_play_channel_without_hold_follows_sessions():
    eng, players, clock = _rig()
    await eng.start()
    assert await eng.play_channel("outdoor", hold=False) is True
    ch = eng.channels["out9"]
    assert eng.channels_playing == ["outdoor"] and ch.manual is None and ch.off_at is None
    await eng.sync_channels([])                          # bez relace → doběh jako u automaticky spuštěného kanálu
    clock.t += 10
    await eng.sync_channels([])
    await eng.wait_fade()
    assert eng.channels_playing == [] and ch.manual is None
    assert await eng.play_channel("outdoor") is True and ch.manual is True      # výchozí = ruční režim (drží)
    assert await eng.play_channel("chodba", hold=False) is False
