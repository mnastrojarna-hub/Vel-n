"""Testy knihovny hudby (`music_sync.py`) proti in-test fake Supabase Storage (aiohttp)."""
from __future__ import annotations

import asyncio
import os

import pytest
from aiohttp import web

from motogo_box import music_sync
from motogo_box.music_sync import KV_INDEX, MusicLibrary, normalize_track
from motogo_box.storage import Storage

BRANCH = "0f0f0f0f-1111-2222-3333-444444444444"
T1 = "11111111-aaaa-4bbb-8ccc-000000000001"
T2 = "22222222-aaaa-4bbb-8ccc-000000000002"
T3 = "33333333-aaaa-4bbb-8ccc-000000000003"
DOOR = "door:9d9d9d9d-1111-2222-3333-555555555555"


class FakeBucket:
    """``GET /storage/v1/object/public/branch-music/<path>``; chybějící → 404, ``fail`` → 500.

    ``gate`` (+ volitelně ``gate_path``) pozdrží odpověď do ``set()``; ``slow[path] = (chunky, prodleva)``
    streamuje tělo po částech s prodlevou (simulace pomalé / zaseklé linky).
    """

    def __init__(self) -> None:
        self.files: dict[str, bytes] = {}
        self.fail: set[str] = set()
        self.hits: list[str] = []
        self.gate: asyncio.Event | None = None
        self.gate_path: str | None = None
        self.slow: dict[str, tuple[int, float]] = {}
        self._runner: web.AppRunner | None = None
        self.port = 0

    async def _get(self, request: web.Request) -> web.StreamResponse:
        path = request.match_info["path"]
        self.hits.append(path)
        if self.gate is not None and (self.gate_path is None or self.gate_path == path):
            await self.gate.wait()
        if path in self.fail:
            return web.Response(status=500, text="boom")
        if path not in self.files:
            return web.json_response({"error": "not found"}, status=404)
        body = self.files[path]
        if path not in self.slow:
            return web.Response(body=body, content_type="audio/mpeg")
        parts, delay = self.slow[path]
        resp = web.StreamResponse(headers={"Content-Type": "audio/mpeg"})
        await resp.prepare(request)
        step = max(1, len(body) // parts)
        for i in range(0, len(body), step):
            await resp.write(body[i:i + step])
            await asyncio.sleep(delay)
        return resp

    async def start(self) -> None:
        app = web.Application()
        app.router.add_get("/storage/v1/object/public/branch-music/{path:.*}", self._get)
        self._runner = web.AppRunner(app)
        await self._runner.setup()
        site = web.TCPSite(self._runner, "127.0.0.1", 0)
        await site.start()
        self.port = site._server.sockets[0].getsockname()[1]  # noqa: SLF001

    async def stop(self) -> None:
        if self._runner is not None:
            await self._runner.cleanup()
            self._runner = None

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.port}"


@pytest.fixture
async def bucket():
    b = FakeBucket()
    b.files[f"{BRANCH}/{T1}.mp3"] = b"ID3" + b"\x01" * 3000
    b.files[f"{BRANCH}/{T2}.ogg"] = b"OggS" + b"\x02" * 70000   # více než jeden chunk
    await b.start()
    try:
        yield b
    finally:
        await b.stop()


@pytest.fixture
def storage(tmp_path):
    st = Storage(str(tmp_path / "music.db"))
    yield st
    st.close()


def track(tid: str, ext: str, size: int, target: str = "all", sort_order: int = 0,
          updated_at: str = "2026-09-10T10:00:00+00:00", title: str = "") -> dict:
    return {"id": tid, "target": target, "path": f"{BRANCH}/{tid}.{ext}", "ext": ext, "size": size,
            "sort_order": sort_order, "updated_at": updated_at, "title": title}


def base_tracks(bucket: FakeBucket) -> list[dict]:
    return [track(T1, "mp3", len(bucket.files[f"{BRANCH}/{T1}.mp3"]), DOOR, 2, title="b"),
            track(T2, "ogg", len(bucket.files[f"{BRANCH}/{T2}.ogg"]), "all", 1, title="a")]


class Changed:
    def __init__(self) -> None:
        self.calls = 0

    async def __call__(self) -> None:
        self.calls += 1


async def test_first_sync_downloads_then_unchanged(bucket, storage, tmp_path):
    changed = Changed()
    lib = MusicLibrary(storage, str(tmp_path / "music"), bucket.url, on_changed=changed)
    res = await lib.sync(base_tracks(bucket))
    assert res == {"added": 2, "removed": 0, "failed": 0, "unchanged": 0}
    f1, f2 = tmp_path / "music" / "tracks" / f"{T1}.mp3", tmp_path / "music" / "tracks" / f"{T2}.ogg"
    assert f1.read_bytes() == bucket.files[f"{BRANCH}/{T1}.mp3"] and f2.stat().st_size == 70004
    assert not list((tmp_path / "music" / "tracks").glob("*.part"))
    assert changed.calls == 1 and lib.sync_reason is None
    idx = storage.kv_get(KV_INDEX)
    assert set(idx["tracks"]) == {T1, T2} and idx["tracks"][T1]["file"] == str(f1) and idx["synced_at"]
    # druhý sync: nic se nestahuje, on_changed se nevolá
    hits = len(bucket.hits)
    res = await lib.sync(base_tracks(bucket))
    assert res == {"added": 0, "removed": 0, "failed": 0, "unchanged": 2}
    assert len(bucket.hits) == hits and changed.calls == 1
    st = lib.status()
    assert (st["tracks"], st["synced"], st["pending"], st["failed"]) == (2, 2, 0, 0)
    assert st["targets"] == {"all": 1, "legacy": 0, DOOR: 1} and st["last_sync_at"]


async def test_changed_size_redownloads_and_removed_deleted(bucket, storage, tmp_path):
    lib = MusicLibrary(storage, str(tmp_path / "music"), bucket.url)
    await lib.sync(base_tracks(bucket))
    bucket.files[f"{BRANCH}/{T1}.mp3"] = b"ID3" + b"\x07" * 5000
    tracks = base_tracks(bucket)
    hits = len(bucket.hits)
    res = await lib.sync(tracks)
    assert res == {"added": 1, "removed": 0, "failed": 0, "unchanged": 1}
    assert bucket.hits[hits:] == [f"{BRANCH}/{T1}.mp3"]
    assert (tmp_path / "music" / "tracks" / f"{T1}.mp3").stat().st_size == 5003
    # jiné updated_at (stejná velikost) → také znovu (kontrakt §3)
    tracks[1]["updated_at"] = "2026-09-11T00:00:00+00:00"
    res = await lib.sync(tracks)
    assert res["added"] == 1 and res["unchanged"] == 1
    # skladba odebraná z konfigurace → soubor smazán
    res = await lib.sync(tracks[:1])
    assert res == {"added": 0, "removed": 1, "failed": 0, "unchanged": 1}
    assert not (tmp_path / "music" / "tracks" / f"{T2}.ogg").exists()
    assert set(storage.kv_get(KV_INDEX)["tracks"]) == {T1}
    # index přežije nový objekt (načte se z kv)
    lib2 = MusicLibrary(storage, str(tmp_path / "music"), bucket.url)
    assert lib2.playlist_for(DOOR) == [str(tmp_path / "music" / "tracks" / f"{T1}.mp3")]


async def test_failed_download_backoff_and_retry(bucket, storage, tmp_path):
    changed = Changed()
    lib = MusicLibrary(storage, str(tmp_path / "music"), bucket.url, on_changed=changed)
    tracks = base_tracks(bucket) + [track(T3, "flac", 10)]              # T3 na serveru není → 404
    res = await lib.sync(tracks)
    assert res == {"added": 2, "removed": 0, "failed": 1, "unchanged": 0}
    st = lib.status()
    assert (st["tracks"], st["synced"], st["pending"], st["failed"]) == (3, 2, 1, 1)
    assert "1 skladeb" in (lib.sync_reason or "")
    assert not list((tmp_path / "music" / "tracks").glob("*.part"))
    # stejná konfigurace hned znovu → backoff: server se NEvolá, ale skladba se dál hlásí jako failed
    hits = len(bucket.hits)
    res = await lib.sync(tracks)
    assert res == {"added": 0, "removed": 0, "failed": 1, "unchanged": 2}
    assert len(bucket.hits) == hits and lib.status()["failed"] == 1 and "1 skladeb" in lib.sync_reason
    # ruční „Znovu synchronizovat“ ruší odstup; špatná velikost → selže a soubor se nezapíše, pokus 2
    bucket.files[f"{BRANCH}/{T3}.flac"] = b"fLaC" + b"\x03" * 20
    assert lib.retry_failed() == 1
    res = await lib.sync(tracks)
    assert res["failed"] == 1 and res["unchanged"] == 2 and bucket.hits[hits:] == [f"{BRANCH}/{T3}.flac"]
    assert not (tmp_path / "music" / "tracks" / f"{T3}.flac").exists()
    assert lib._failed[T3]["attempts"] == 2                              # noqa: SLF001
    # změna size v konfiguraci ruší backoff sama → příště se stáhne
    tracks[2]["size"] = 24
    res = await lib.sync(tracks)
    assert res == {"added": 1, "removed": 0, "failed": 0, "unchanged": 2}
    assert lib.status()["failed"] == 0 and lib.sync_reason is None and changed.calls == 2
    # chybná skladba odebraná z konfigurace zmizí i z failed
    bucket.fail.add(f"{BRANCH}/{T3}.flac")
    tracks[2]["updated_at"] = "2026-09-12T00:00:00+00:00"
    assert (await lib.sync(tracks))["failed"] == 1 and lib.status()["failed"] == 1
    assert (await lib.sync(tracks[:2]))["failed"] == 0 and lib.status()["failed"] == 0 and lib.sync_reason is None


async def test_timeout_is_inactivity_not_wall_clock(bucket, storage, tmp_path, monkeypatch):
    monkeypatch.setattr(music_sync, "FILE_TIMEOUT_S", 0.3)
    monkeypatch.setattr(music_sync, "MIN_RATE_BPS", 70004 / 2.0)         # strop = 0.3 + 2 s pro T2
    monkeypatch.setattr(music_sync, "BACKOFF_BASE_S", 0.0)
    lib = MusicLibrary(storage, str(tmp_path / "music"), bucket.url)
    tracks = base_tracks(bucket)[1:]
    bucket.slow[f"{BRANCH}/{T2}.ogg"] = (6, 0.12)                        # ~0.7 s > 0.3 s, ale data tečou
    res = await lib.sync(tracks)
    assert res == {"added": 1, "removed": 0, "failed": 0, "unchanged": 0}
    assert (tmp_path / "music" / "tracks" / f"{T2}.ogg").stat().st_size == 70004
    # zaseklá linka (prodleva > timeout nečinnosti) → timeout, .part uklizen
    bucket.slow[f"{BRANCH}/{T2}.ogg"] = (2, 0.6)
    tracks[0]["updated_at"] = "2026-09-11T00:00:00+00:00"
    res = await lib.sync(tracks)
    assert res["failed"] == 1 and lib._failed[T2]["reason"] == "timeout stahování"  # noqa: SLF001
    assert not list((tmp_path / "music" / "tracks").glob("*.part"))


async def test_interrupted_sync_keeps_progress(bucket, storage, tmp_path):
    lib = MusicLibrary(storage, str(tmp_path / "music"), bucket.url)
    bucket.gate, bucket.gate_path = asyncio.Event(), f"{BRANCH}/{T2}.ogg"   # T1 projde, T2 visí
    task = lib.start_sync(base_tracks(bucket))
    for _ in range(50):
        await asyncio.sleep(0.02)
        if (tmp_path / "music" / "tracks" / f"{T1}.mp3").exists():
            break
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert set(storage.kv_get(KV_INDEX)["tracks"]) == {T1}               # index uložen po každé skladbě
    assert not list((tmp_path / "music" / "tracks").glob("*.part"))
    bucket.gate.set()
    hits = len(bucket.hits)
    res = await lib.sync(base_tracks(bucket))
    assert res == {"added": 1, "removed": 0, "failed": 0, "unchanged": 1}
    assert bucket.hits[hits:] == [f"{BRANCH}/{T2}.ogg"]
    # hotový soubor na disku bez záznamu v indexu (pád před uložením) → adoptuje se bez stahování
    storage.kv_set(KV_INDEX, {"tracks": {}})
    lib2 = MusicLibrary(storage, str(tmp_path / "music"), bucket.url)
    hits = len(bucket.hits)
    res = await lib2.sync(base_tracks(bucket))
    assert res == {"added": 2, "removed": 0, "failed": 0, "unchanged": 0} and len(bucket.hits) == hits


async def test_concurrent_sync_calls_are_serialized(bucket, storage, tmp_path):
    lib = MusicLibrary(storage, str(tmp_path / "music"), bucket.url)
    bucket.gate = asyncio.Event()
    a = asyncio.ensure_future(lib.sync(base_tracks(bucket)))
    b = asyncio.ensure_future(lib.sync(base_tracks(bucket)))
    await asyncio.sleep(0.05)
    bucket.gate.set()
    ra, rb = await asyncio.gather(a, b)
    assert ra == {"added": 2, "removed": 0, "failed": 0, "unchanged": 0}
    assert rb == {"added": 0, "removed": 0, "failed": 0, "unchanged": 2}
    assert lib.status()["failed"] == 0 and lib.sync_reason is None and len(bucket.hits) == 2


async def test_legacy_and_playlist_fallback(bucket, storage, tmp_path):
    music = tmp_path / "music"
    music.mkdir()
    (music / "rucni.mp3").write_bytes(b"x" * 10)
    (music / "poznamka.txt").write_text("ne")
    lib = MusicLibrary(storage, str(music), bucket.url)
    assert lib.playlist_for(DOOR) == [str(music / "rucni.mp3")]        # jen legacy před syncem
    await lib.sync(base_tracks(bucket))
    own, common = str(music / "tracks" / f"{T1}.mp3"), str(music / "tracks" / f"{T2}.ogg")
    assert lib.playlist_for(DOOR) == [own]                              # vlastní → bez all/legacy
    assert lib.playlist_for("zone:5") == [common, str(music / "rucni.mp3")]
    assert lib.playlist_for("outdoor") == [common, str(music / "rucni.mp3")]
    assert lib.playlist_for("all") == [common, str(music / "rucni.mp3")]
    assert lib.targets() == {"all": 1, "legacy": 1, DOOR: 1}
    # pořadí dle sort_order, pak title
    tracks = base_tracks(bucket)
    tracks[0]["target"], tracks[0]["sort_order"], tracks[0]["title"] = "all", 1, "a"
    tracks[1]["sort_order"], tracks[1]["title"] = 1, "b"
    await lib.sync(tracks)
    assert lib.playlist_for("all") == [own, common, str(music / "rucni.mp3")]
    tracks[0]["sort_order"] = 9
    await lib.sync(tracks)
    assert lib.playlist_for(DOOR)[:2] == [common, own]
    # smazaný soubor na disku se v playlistu neobjeví
    os.remove(own)
    assert lib.playlist_for("all") == [common, str(music / "rucni.mp3")]
    assert lib.status()["pending"] == 1


async def test_start_sync_dedup_and_background(bucket, storage, tmp_path):
    changed = Changed()
    lib = MusicLibrary(storage, str(tmp_path / "music"), bucket.url, on_changed=changed)
    bucket.gate = asyncio.Event()
    task = lib.start_sync(base_tracks(bucket))
    assert task is not None and lib.start_sync(base_tracks(bucket)) is None
    await asyncio.sleep(0.05)
    assert lib.status()["syncing"] is True and lib.sync_reason == "stahování běží"
    bucket.gate.set()
    assert await task == {"added": 2, "removed": 0, "failed": 0, "unchanged": 0}
    assert changed.calls == 1
    again = lib.start_sync(base_tracks(bucket))
    assert again is not None and (await again)["unchanged"] == 2 and changed.calls == 1


async def test_sanitizes_ids_ext_and_url(bucket, storage, tmp_path):
    assert normalize_track({"id": T1.upper(), "ext": ".MP3", "path": f"/{BRANCH}/x.mp3", "size": "12"}) == {
        "id": T1, "target": "all", "path": f"{BRANCH}/x.mp3", "ext": "mp3", "size": 12,
        "sort_order": 0, "updated_at": "", "title": ""}
    assert normalize_track({"id": "../etc", "ext": "mp3", "path": "a"}) is None
    assert normalize_track({"id": T1, "ext": "m/p3", "path": "a"}) is None
    assert normalize_track({"id": T1, "ext": "mp3", "path": ""}) is None
    assert normalize_track("nope") is None
    lib = MusicLibrary(storage, str(tmp_path / "music"), bucket.url)
    res = await lib.sync([{"id": "bad", "ext": "mp3", "path": "x"}, None] + base_tracks(bucket))
    assert res == {"added": 2, "removed": 0, "failed": 2, "unchanged": 0}
    assert sorted(os.listdir(tmp_path / "music" / "tracks")) == [f"{T1}.mp3", f"{T2}.ogg"]
    # neplatné záznamy se hlásí ve status()/sync_reason (Velín nesmí svítit zeleně), po opravě zmizí
    st = lib.status()
    assert (st["tracks"], st["synced"], st["pending"], st["failed"]) == (4, 2, 2, 2)
    assert set(lib._failed) == {"bad", "invalid:1"} and "2 skladeb" in lib.sync_reason  # noqa: SLF001
    res = await lib.sync(base_tracks(bucket))
    assert res["failed"] == 0 and lib.status()["failed"] == 0 and lib.sync_reason is None
    # ne-http URL Supabase → nic se nestahuje, jen failed
    lib2 = MusicLibrary(Storage(str(tmp_path / "b.db")), str(tmp_path / "m2"), "ftp://nic")
    res = await lib2.sync(base_tracks(bucket))
    assert res["failed"] == 2 and res["added"] == 0 and lib2.status()["pending"] == 2
    # poškozený index v kv nespadne
    storage.kv_set(KV_INDEX, {"tracks": "rozbité"})
    assert MusicLibrary(storage, str(tmp_path / "music"), bucket.url).status()["tracks"] == 0
