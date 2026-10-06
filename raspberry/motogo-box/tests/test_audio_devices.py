"""Hudba na jednoduchém zapojení (1 USB→jack adaptér pro šatnu) i na 9 výstupech: karty, auto/usb:, mono, tón,
zóna bez reproduktoru, test výstupu, přepojení karty, diagnostika (kontrakt §6, 2026-09-28)."""
from __future__ import annotations

import asyncio
import os
import wave

from motogo_box import audio_devices, audio_hotplug, commands, diag_audio, zone_access
from motogo_box.audio_build import NULL_DEVICE, audio_signature, build_audio
from motogo_box.audio_multi import AudioMulti
from motogo_box.config import AudioCfg, HardwareConfig, LocalConfig, load_hardware_file, merge_hardware, validate_hardware
from motogo_box.diag_protocol import item
from motogo_box.mpv_player import MpvPlayer
from tests.test_audio_multi import HW_FILE, FakePlayer, _cfg

def _card(root, idx: int, cid: str, name: str, port: str | None) -> str:
    os.makedirs(root / f"proc/asound/card{idx}/pcm0p", exist_ok=True)
    dev = root / (f"devices/usb1/{port}/{port}:1.0" if port else f"devices/platform/hdmi{idx}")
    os.makedirs(dev, exist_ok=True)
    os.makedirs(root / "sys/class/sound" / f"card{idx}", exist_ok=True)
    os.symlink(dev, root / "sys/class/sound" / f"card{idx}" / "device")
    return f" {idx} [{cid:<15}]: USB-Audio - {name}\n                      {name} at usb-xhci-hcd.0-1, full speed\n"


def _root(tmp_path, usb: list[tuple[int, str, str]]):
    text = _card(tmp_path, 0, "vc4hdmi0", "vc4-hdmi-0", None)
    for idx, cid, port in usb:
        text += _card(tmp_path, idx, cid, "USB Audio Device", port)
    (tmp_path / "proc/asound/cards").write_text(text)
    return str(tmp_path)


def test_list_and_resolve_auto_usb_card(tmp_path):
    cards = audio_devices.list_cards(_root(tmp_path, [(2, "Device", "1-1.2")]))
    assert [(c["index"], c["id"], c["usb_path"]) for c in cards] == [(0, "vc4hdmi0", None), (2, "Device", "1-1.2")]
    assert audio_devices.resolve("auto", cards) == ("alsa/plughw:2,0", None)
    assert audio_devices.resolve("usb:1-1.2", cards) == ("alsa/plughw:2,0", None)
    assert audio_devices.resolve("usb:1-1.3", cards)[0] is None
    assert audio_devices.resolve("alsa/plughw:CARD=Device", cards) == ("alsa/plughw:CARD=Device", None)
    assert audio_devices.resolve("alsa/plughw:CARD=Box9", cards)[0] is None
    assert audio_devices.resolve(None, cards) == (None, None)


def test_auto_is_ambiguous_with_two_cards_and_missing_without(tmp_path):
    cards = audio_devices.list_cards(_root(tmp_path, [(2, "Device", "1-1"), (3, "Device_1", "1-2")]))
    dev, problem = audio_devices.resolve("auto", cards)
    assert dev is None and "1-1" in problem and "1-2" in problem        # nikdy nehrát do náhodné zóny
    assert audio_devices.resolve("usb:1-2", cards)[0] == "alsa/plughw:3,0"
    assert audio_devices.resolve("auto", [])[1].startswith("žádná USB")


def test_tone_is_wav(tmp_path):
    path = audio_devices.ensure_tone((str(tmp_path),))
    with wave.open(path) as w:
        assert w.getnchannels() == 1 and w.getnframes() == 3 * 44100


def test_mono_and_device_in_mpv_args():
    args = MpvPlayer("/tmp/s", "/m", "alsa/plughw:2,0", mono=True)._mpv_args()
    assert "--audio-device=alsa/plughw:2,0" in args and "--audio-channels=mono" in args
    assert "--audio-channels=mono" not in MpvPlayer("/tmp/s", "/m")._mpv_args()


def test_merge_null_device_keeps_local_usb_card():
    local = {"audio": {"device": "alsa/plughw:CARD=Device", "volume": 50}}
    out = merge_hardware(local, {"audio": {"device": None, "volume": 70, "mode": "multi"}})
    assert out["audio"] == {"device": "alsa/plughw:CARD=Device", "volume": 70, "mode": "multi"}


def _hw_locker_only() -> HardwareConfig:
    d = load_hardware_file(HW_FILE)
    d["audio"].update({"mode": "multi", "outputs": {"out8": {"device": "auto", "mono": True}}, "device": None})
    for z in d["zones"]:
        z.pop("audio", None)
    d["zones"][7]["audio"] = {"out": "out8"}
    return HardwareConfig.from_dict(d)


def test_build_locker_only_resolves_card_and_marks_missing():
    hw = _hw_locker_only()
    usb = [{"index": 2, "id": "Device", "name": "USB", "usb_path": "1-1", "playback": True}]
    eng = build_audio(hw, LocalConfig(), None, None, cards=usb)
    assert isinstance(eng, AudioMulti) and eng.zone_out == {8: "out8"}
    p = eng.players["out8"]
    assert p.device == "alsa/plughw:2,0" and p.mono is True and p.problem is None
    assert eng.has_output(8) and not eng.has_output(1)
    st = eng.status()
    assert st["players"]["out8"]["present"] is True and st["zone_out"] == {"8": "out8"} and st["cards"] == usb
    eng2 = build_audio(hw, LocalConfig(), None, None, cards=[])
    assert eng2.players["out8"].device == NULL_DEVICE and eng2.status()["players"]["out8"]["present"] is False
    assert audio_signature(hw.audio)[3] == {"out8": {"device": "auto", "mono": True}}
    assert not [p for p in validate_hardware(hw) if "Zóna" in p]      # kóje bez reproduktoru nejsou problém


def _eng():
    players = {"out8": FakePlayer("out8")}
    return AudioMulti(players, {8: "out8"}, {}, None, _cfg(), None, zone_targets={8: "zone:8"}), players


async def test_tone_on_output_and_customer_music_preempts_it():
    eng, players = _eng()
    await eng.start()
    assert await eng.test_output("out8", 0) is True
    assert any(e[0] == "load_files" and str(e[1][0]).endswith(".wav") for e in players["out8"].log)
    assert await eng.test_output("out3", 0) is False
    task = asyncio.create_task(eng.test_output("out8", 1))
    await asyncio.sleep(0.05)
    assert not eng.output_busy(8)                          # tón není zákaznická hudba
    assert await eng.play_zone(8)                          # kód šatny přebije tón
    await task
    assert eng.is_playing(8) and eng.output_busy(8) and not eng.channels["out8"].tone
    assert await eng.test_tone(8, 0) is False              # hrající hudbu test nepřeruší


class _Zc:
    def __init__(self, audio, enabled=True):
        self.audio, self.number, self.music_enabled = audio, 8, enabled


class _Aud:
    def __init__(self, speaker=True, delay=0.0):
        self.speaker, self.delay, self.calls = speaker, delay, 0

    def has_output(self, zone):
        return self.speaker

    async def play_zone(self, zone, track=None, restart=False):
        self.calls += 1
        await asyncio.sleep(self.delay)
        return True


async def test_start_music_only_zone_with_speaker(monkeypatch):
    d: dict = {}
    await zone_access.start_music(_Zc(_Aud(speaker=False)), d)
    assert d == {"music": False, "no_speaker": True}
    aud = _Aud()
    d = {}
    await zone_access.start_music(_Zc(aud), d)
    assert d == {"music": True} and aud.calls == 1
    d = {}
    await zone_access.start_music(_Zc(_Aud(), enabled=False), d)
    assert d == {"music": False, "music_disabled": True}
    monkeypatch.setattr(zone_access, "MUSIC_WAIT_S", 0.05)
    slow, d = _Aud(delay=0.3), {}
    t0 = asyncio.get_running_loop().time()
    await zone_access.start_music(_Zc(slow), d)
    assert asyncio.get_running_loop().time() - t0 < 0.2 and d["music_pending"]   # zámek na hudbu nečeká
    await asyncio.sleep(0.35)


class _Ctrl:
    def __init__(self, eng, hw=None):
        self.audio, self.hardware, self.zones, self.outdoor, self.music = eng, hw, {}, None, None
        self.local, self.io = LocalConfig(), None


async def test_audio_test_command_by_output():
    eng, _ = _eng()
    await eng.start()
    ok, res = await commands._audio_test(_Ctrl(eng), {"out": "out8", "seconds": 1})
    assert ok and res["out"] == "out8"
    ok, res = await commands._audio_test(_Ctrl(eng), {"out": "outX"})
    assert not ok and res["error"] == "output_not_found"


async def test_hotplug_rebuilds_when_card_appears(monkeypatch):
    hw = _hw_locker_only()
    eng = build_audio(hw, LocalConfig(), None, None, cards=[])
    ctrl = _Ctrl(eng, hw)
    built = []

    async def fake_rebuild(c, cards):
        built.append(cards)
    monkeypatch.setattr(audio_hotplug, "rebuild_audio", fake_rebuild)
    assert await audio_hotplug.recheck(ctrl, cards=[]) is False
    usb = [{"index": 2, "id": "Device", "name": "USB", "usb_path": "1-1", "playback": True}]
    assert await audio_hotplug.recheck(ctrl, cards=usb) is True and built == [usb]


def test_diag_rows_locker_only():
    a = {"mode": "multi", "cards": [], "no_speaker": ["Kóje 1"], "music_enabled": True,
         "speakers": [{"zone": 8, "label": "Šatna", "out": "out8", "tracks": 0}],
         "players": {"out8": {"alive": True, "device_cfg": "auto", "device": NULL_DEVICE, "present": False,
                              "problem": "žádná USB zvuková karta (adaptér nezapojen?)", "mono": True}}}
    rows = {r["id"]: r for r in diag_audio.protocol_items(a, item)}
    assert "out8 → Šatna" in rows["software.audio_map"]["value"] and "1 zón bez reproduktoru" in rows["software.audio_map"]["value"]
    assert rows["software.cards"]["status"] == "fail" and "adaptér" in rows["software.cards"]["message"]
    assert rows["software.music.8"]["status"] == "warn"
    a["speakers"][0]["tracks"] = 5
    a["players"]["out8"].update(present=True, problem=None)
    a["cards"] = [{"index": 2, "id": "Device", "name": "USB", "usb_path": "1-1"}]
    rows = {r["id"]: r for r in diag_audio.protocol_items(a, item)}
    assert rows["software.cards"]["status"] == "ok" and "USB port 1-1" in rows["software.cards"]["value"]


def test_selector_default_cfg_has_mono_flag():
    assert AudioCfg().mono is False and AudioCfg(outputs={"o": {"device": "auto", "mono": True}}).output_opts() == \
        {"o": {"device": "auto", "mono": True}}


def test_selector_without_relays_plays_locker_through_usb():
    """Velké Němčice 28. 9.: Velín má starý režim selector, žádné audio relé → šatna hraje přes jedinou USB kartu."""
    d = load_hardware_file(HW_FILE)
    for z in d["zones"]:
        z.pop("audio", None)
    d["zones"][7]["kind"] = "accessories"
    d["audio"].update({"mode": "selector", "device": None})
    hw = HardwareConfig.from_dict(d)
    usb = [{"index": 2, "id": "Device", "name": "USB", "usb_path": "1-1", "playback": True}]
    eng = build_audio(hw, LocalConfig(), None, None, cards=usb)
    assert isinstance(eng, AudioMulti) and eng.fallback and eng.zone_out == {8: "jack"}
    assert eng.players["jack"].device == "alsa/plughw:2,0" and eng.players["jack"].mono
    assert eng.has_output(8) and not eng.has_output(1) and eng.status()["fallback"] is True
    assert eng.resolved == {"jack": "alsa/plughw:2,0"}
    sel = build_audio(HardwareConfig.from_dict(load_hardware_file(HW_FILE)), LocalConfig(), None, None, cards=usb)
    assert sel.mode == "selector"                          # s relé selektoru beze změny


class _Kv:
    def __init__(self):
        self.d = {}

    def kv_get(self, k, default=None):
        return self.d.get(k, default)

    def kv_set(self, k, v):
        self.d[k] = v


def test_music_phase_welcome_then_return():
    from motogo_box.music_phase import track_for_grant
    kv = _Kv()
    assert track_for_grant(kv, "b1", "accessories", 3 * 3600, now=1000) == 1          # šatna poprvé
    assert track_for_grant(kv, "b1", "motorcycle", 3 * 3600, now=1000 + 600) == 1      # kóje hned potom
    assert track_for_grant(kv, "b1", "accessories", 3 * 3600, now=1000 + 3600) == 1    # za hodinu zapomenutá věc
    assert track_for_grant(kv, "b1", "motorcycle", 3 * 3600, now=1000 + 3 * 3600) == 2  # návrat
    assert track_for_grant(kv, "b2", "motorcycle", 3 * 3600, now=1000 + 3 * 3600) == 1  # jiná rezervace
    assert track_for_grant(kv, None, "motorcycle", 60) is None and track_for_grant(kv, "b1", "service", 60) is None
    assert track_for_grant(None, "b1", "motorcycle", 60) is None
    kv.d["booking_first_open"]["old"] = 0
    track_for_grant(kv, "b3", "motorcycle", 60, now=61 * 86400)                        # prořez starých záznamů
    assert "old" not in kv.d["booking_first_open"]


class _Lib:
    def __init__(self, own, shared):
        self.own, self.shared = own, shared

    def playlist_for(self, target):
        return self.own or self.shared

    def track_for(self, target, n):
        for lst in (self.own, self.shared):
            if len(lst) >= n:
                return lst[n - 1]
        return (self.own or self.shared or [None])[0]


async def test_play_zone_track_loads_single_song_without_shuffle():
    players = {"out8": FakePlayer("out8")}
    eng = AudioMulti(players, {8: "out8"}, {}, None, _cfg(), _Lib(["/m/uvitaci.mp3", "/m/navrat.mp3"], []),
                     zone_targets={8: "door:s"})
    await eng.start()
    assert await eng.play_zone(8, 1) and players["out8"].files == ["/m/uvitaci.mp3"]
    loads = players["out8"].loads
    assert await eng.play_zone(8, 1) and players["out8"].loads == loads           # stejná fáze nenačítá znovu
    assert await eng.play_zone(8, 2) and players["out8"].files == ["/m/navrat.mp3"]  # návrat přepne skladbu
    assert eng.status()["players"]["out8"]["track"] == 2
    await eng.stop_zone(8)
    assert await eng.play_zone(8) and players["out8"].files == ["/m/uvitaci.mp3", "/m/navrat.mp3"]   # ruční = playlist


def test_library_track_for_falls_back_to_shared(tmp_path):
    from motogo_box.music_sync import MusicLibrary
    lib = MusicLibrary.__new__(MusicLibrary)
    files = {"door:s": [str(tmp_path / "s1.mp3")], "all": [str(tmp_path / "a1.mp3"), str(tmp_path / "a2.mp3")]}
    lib._tracks_of = lambda t: list(files.get(t, []))
    lib.legacy_files = lambda: []
    assert lib.track_for("door:s", 1).endswith("s1.mp3") and lib.track_for("door:s", 2).endswith("a2.mp3")
    files["all"] = []
    assert lib.track_for("door:s", 2).endswith("s1.mp3")                            # jediná skladba hraje i při návratu
    files["door:s"] = []
    assert lib.track_for("door:s", 1) is None


async def test_start_music_passes_track():
    got = []

    class A(_Aud):
        async def play_zone(self, zone, track=None, restart=False):
            got.append(track)
            return True
    zc = _Zc(A())
    zc.music_track = 2
    d: dict = {}
    await zone_access.start_music(zc, d)
    assert got == [2] and d["music_track"] == 2
