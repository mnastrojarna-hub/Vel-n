"""Zkrácení skladby na konci (`music.tracks[].end_s`, 2026-10-06; `music_edl.py`): EDL vedle staženého souboru,
bez nového stahování, změna konce = znovunačtení playlistů. Integrační kontrola s reálným mpv (přeskočí se bez mpv)."""
from __future__ import annotations

import asyncio
import os
import shutil
import subprocess

import pytest

from motogo_box import music_edl
from motogo_box.music_sync import KV_INDEX, MusicLibrary, normalize_track
from motogo_box.mpv_player import MpvError, MpvPlayer

from tests.test_music_sync import BRANCH, DOOR, T1, T2, Changed, base_tracks, bucket, storage  # noqa: F401 — fixtures


@pytest.mark.parametrize("raw,want", [
    (242, 242.0), ("241.5", 241.5), (7200, 7200.0), (0.25, 0.25),
    (None, None), (0, None), (-4, None), (7200.5, None), ("x", None), (True, None), (float("nan"), None),
    (float("inf"), None), ([1], None),
])
def test_normalize_end_s(raw, want):
    assert music_edl.normalize_end_s(raw) == want
    tr = normalize_track({"id": T1, "ext": "mp3", "path": f"{BRANCH}/{T1}.mp3", "end_s": raw})
    assert tr is not None and tr["end_s"] == want


def test_edl_content_absolute_path_bytes_and_format(tmp_path):
    media = tmp_path / "tón, 1.mp3"
    path = str(media)
    assert music_edl.edl_content(path, 242) == f"# mpv EDL v0\n%{len(path.encode('utf-8'))}%{path},0,242\n"
    assert music_edl.edl_content(path, 241.5).endswith(",0,241.5\n")
    assert music_edl.edl_content(path, 7199.9994).endswith(",0,7199.999\n")
    assert music_edl.edl_path("/x/tracks", T1) == f"/x/tracks/{T1}.edl"


async def test_end_s_writes_edl_without_redownload_and_reloads(bucket, storage, tmp_path):  # noqa: F811
    changed = Changed()
    lib = MusicLibrary(storage, str(tmp_path / "music"), bucket.url, on_changed=changed)
    tracks = base_tracks(bucket)
    await lib.sync(tracks)
    media, edl = tmp_path / "music" / "tracks" / f"{T1}.mp3", tmp_path / "music" / "tracks" / f"{T1}.edl"
    assert changed.calls == 1 and not edl.exists() and lib.playlist_for(DOOR) == [str(media)]
    hits = len(bucket.hits)
    tracks[0]["end_s"] = 242                                       # Velín: konec 4:02
    assert await lib.sync(tracks) == {"added": 0, "removed": 0, "failed": 0, "unchanged": 2}
    assert len(bucket.hits) == hits and changed.calls == 2         # nic se nestahuje, přehrávače znovu načtou
    assert edl.read_text(encoding="utf-8") == f"# mpv EDL v0\n%{len(str(media).encode())}%{media},0,242\n"
    assert lib.playlist_for(DOOR) == [str(edl)] and lib.track_for(DOOR, 1) == str(edl)
    assert storage.kv_get(KV_INDEX)["tracks"][T1]["end_s"] == 242.0
    assert lib.targets() == {"all": 1, "legacy": 0, DOOR: 1}       # počty skladeb beze změny
    await lib.sync(tracks)
    assert changed.calls == 2                                      # stejný konec → nic
    tracks[0]["end_s"] = "241.5"
    await lib.sync(tracks)
    assert changed.calls == 3 and edl.read_text(encoding="utf-8").endswith(",0,241.5\n")
    lib2 = MusicLibrary(storage, str(tmp_path / "music"), bucket.url)
    assert lib2.playlist_for(DOOR) == [str(edl)]                   # index s end_s přežije restart
    tracks[0]["end_s"] = None
    await lib.sync(tracks)
    assert changed.calls == 4 and not edl.exists() and lib.playlist_for(DOOR) == [str(media)]
    assert len(bucket.hits) == hits
    tracks[1]["sort_order"] = 7                                    # pořadí (▲▼ ve Velíně) taky znovu načte playlisty
    await lib.sync(tracks)
    assert changed.calls == 5


async def test_first_download_with_end_s_and_cleanup(bucket, storage, tmp_path):  # noqa: F811
    lib = MusicLibrary(storage, str(tmp_path / "music"), bucket.url)
    tracks = base_tracks(bucket)
    tracks[0]["end_s"] = 242
    assert (await lib.sync(tracks))["added"] == 2
    tdir = tmp_path / "music" / "tracks"
    edl = tdir / f"{T1}.edl"
    assert edl.exists() and lib.playlist_for(DOOR) == [str(edl)]
    stale = tdir / "99999999-aaaa-4bbb-8ccc-000000000009.edl"
    stale.write_text("# mpv EDL v0\n")
    (tdir / f"{T2}.edl").write_text("# mpv EDL v0\n")             # skladba bez end_s nesmí mít EDL
    (tdir / f"{T1}.edl.part").write_text("x")
    await lib.sync(tracks)
    assert edl.exists() and not stale.exists() and not (tdir / f"{T2}.edl").exists()
    assert not (tdir / f"{T1}.edl.part").exists()
    assert lib.playlist_for("all") == [str(tdir / f"{T2}.ogg")]
    res = await lib.sync(tracks[1:])                               # skladba odebrána → soubor i EDL pryč
    assert res["removed"] == 1 and not edl.exists() and not (tdir / f"{T1}.mp3").exists()


def test_sync_edls_never_touches_media_with_edl_extension(tmp_path):
    media = tmp_path / f"{T1}.edl"                                   # (teoreticky) skladba nahraná s příponou .edl
    media.write_text("data")
    for end_s in (None, 242):
        assert music_edl.sync_edls({T1: {"file": str(media), "end_s": end_s}}, str(tmp_path)) is False
        assert media.read_text() == "data"


async def test_edl_write_failure_falls_back_to_whole_track(bucket, storage, tmp_path, monkeypatch):  # noqa: F811
    changed = Changed()
    lib = MusicLibrary(storage, str(tmp_path / "music"), bucket.url, on_changed=changed)
    tracks = base_tracks(bucket)
    tracks[0]["end_s"] = 242
    await lib.sync(tracks)
    edl = tmp_path / "music" / "tracks" / f"{T1}.edl"
    assert edl.exists()
    real = os.replace

    def failing(src, dst):
        if str(dst).endswith(".edl"):
            raise OSError("disk plný")
        return real(src, dst)

    monkeypatch.setattr(music_edl.os, "replace", failing)
    tracks[0]["end_s"] = 230
    await lib.sync(tracks)
    assert not edl.exists() and not (tmp_path / "music" / "tracks" / f"{T1}.edl.part").exists()
    assert lib.playlist_for(DOOR) == [str(tmp_path / "music" / "tracks" / f"{T1}.mp3")]   # nikdy starý konec
    assert changed.calls == 2
    await lib.sync(tracks)                                         # chyba trvá → už nic nemění, žádné znovunačítání
    assert changed.calls == 2


# ─── integrace s reálným mpv (RPi: mpv 0.35 bookworm; jen IPC dostupné v 0.35) ──────────────────────────
MPV, FFMPEG = shutil.which("mpv"), shutil.which("ffmpeg")


class _NullMpv(MpvPlayer):
    def _mpv_args(self) -> list[str]:
        return [*super()._mpv_args(), "--ao=null", "--no-config"]


async def _prop(p: MpvPlayer, name: str, ok=lambda v: v is not None, timeout: float = 5.0):
    """Počká, až vlastnost mpv existuje a splní `ok` (soubor se načítá asynchronně)."""
    deadline = asyncio.get_running_loop().time() + timeout
    while True:
        try:
            v = await p.command("get_property", name)
            if ok(v):
                return v
        except MpvError:
            pass
        if asyncio.get_running_loop().time() > deadline:
            raise AssertionError(f"mpv {name} se nedočkal")
        await asyncio.sleep(0.05)


@pytest.mark.skipif(not (MPV and FFMPEG), reason="mpv/ffmpeg není nainstalováno")
async def test_mpv_plays_edl_cut_seek_rewind_and_loop(tmp_path):
    media = tmp_path / "tón, 1.mp3"
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                    "sine=frequency=440:duration=10", str(media)], check=True, timeout=60)
    cut, short = tmp_path / "cut.edl", tmp_path / "short.edl"
    cut.write_text(music_edl.edl_content(str(media), 4), encoding="utf-8")
    short.write_text(music_edl.edl_content(str(media), 1), encoding="utf-8")
    p = _NullMpv(str(tmp_path / "mpv.sock"), str(tmp_path), name="test")
    await p.start()
    try:
        assert p.alive
        assert await p.load_files([str(cut)], shuffle=False) == 1
        assert abs(await _prop(p, "duration") - 4.0) < 0.05           # 10 s soubor → skladba 4 s
        await p.play()
        await asyncio.sleep(1.2)
        assert await p.command("get_property", "time-pos") > 0.5
        assert await p.rewind()                                         # 1 skladba → seek 0 absolute
        assert await p.command("get_property", "time-pos") < 0.5
        assert await p.load_files([str(cut), str(short)], shuffle=False) == 2
        await _prop(p, "duration")
        await p.command("set_property", "playlist-pos", 1)
        assert abs(await _prop(p, "duration", lambda v: v is not None and v < 2) - 1.0) < 0.05
        assert await p.rewind()                                         # jiná než první → playlist-pos 0
        assert abs(await _prop(p, "duration", lambda v: v is not None and v > 2) - 4.0) < 0.05
        assert await p.command("get_property", "playlist-pos") == 0
        assert await p.load_files([str(short)], shuffle=False) == 1
        await _prop(p, "duration")
        await p.play()
        await asyncio.sleep(1.6)                                        # konec EDL → dokola od začátku
        assert await p.command("get_property", "idle-active") is False
        assert await p.command("get_property", "time-pos") < 1.0
    finally:
        await p.stop()
