"""Testy příkazů z Velína pro zónu venku (kontrakt §B/§13) — doplněk `test_commands.py` (soubor je plný):
`zone_test` u venku bez relé světla, chybové kódy `light_on/off` (`outdoor_no_light`, `light_failed`)."""
from __future__ import annotations

from motogo_box import commands
from motogo_box.config_outdoor import OutdoorCfg
from tests.test_commands import FakeController, FakeOutdoor


class FailingOutdoor(FakeOutdoor):
    """Relé světla selhává (`set_light` → False, stav se nemění)."""

    async def set_light(self, on: bool) -> bool:
        self.lights.append(on)
        return False


def _audio_only() -> FakeOutdoor:
    o = FakeOutdoor(configured=False)
    o.cfg = OutdoorCfg(zone=9, audio_out="out9", present=True)      # venek jen s hudbou — bez relé světla
    return o


async def test_zone_test_without_light_relay_uses_audio_only():
    c = FakeController()
    c.outdoor = _audio_only()
    c.outdoor.result = {"light": None, "audio": True}
    ok, res = await commands.execute(c, "zone_test", {"zone": 9})
    assert ok and res == {"zone": 9, "outdoor": True, "light": None, "audio": True} and c.outdoor.tests == 1
    c.outdoor.result = {"light": None, "audio": False}
    assert (await commands.execute(c, "zone_test", {"zone": 9}))[0] is False
    c.outdoor.result = {"light": None, "audio": None}        # selector: nic se netestuje — jako diagnostika OK
    assert (await commands.execute(c, "zone_test", {"zone": 9}))[0] is True


async def test_light_on_off_error_codes():
    c = FakeController()
    c.outdoor = _audio_only()
    ok, res = await commands.execute(c, "light_on", {"zone": 9})
    assert not ok and res == {"zone": 9, "light": False, "outdoor": True, "error": "outdoor_no_light"}
    assert c.outdoor.lights == []                             # relé se nesahá
    c.outdoor = FailingOutdoor()
    ok, res = await commands.execute(c, "light_off", {"zone": 9})
    assert not ok and res == {"zone": 9, "light": False, "outdoor": True, "error": "light_failed"}
    assert c.outdoor.lights == [False]
    ok, res = await commands.execute(c, "light_on", {"zone": 1})   # zóna dveří beze změny
    assert ok and res == {"zone": 1, "light": True}
