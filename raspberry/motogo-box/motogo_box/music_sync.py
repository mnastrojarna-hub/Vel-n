"""Knihovna hudby pobočky a její synchronizace z bucketu `branch-music` (kontrakt §3).

- Index v ``Storage.kv['music_index']``: ``{tracks: {id: {target, path, ext, size, updated_at, file,
  sort_order, title}}, synced_at}``; ukládá se po KAŽDÉ stažené skladbě (přerušený sync o hotové
  soubory nepřijde). Soubory v ``<music_dir>/tracks/<id>.<ext>``; ručně nahrané soubory přímo
  v ``<music_dir>`` (legacy) = cíl ``all``.
- ``sync(tracks)`` stáhne nové/změněné skladby (jiné ``updated_at``/``size``) přes httpx streaming do
  ``.part`` → ``os.replace``, ověří velikost, smaže skladby mimo konfiguraci. Max 3 paralelně; timeout
  120 s = nečinnost spojení (httpx read) + strop přenosu dle velikosti (≥ 50 kB/s). Nikdy nevyhazuje —
  chyby se opakují s exponenciálním odstupem (2 min … 6 h; ruší ho změna path/size/updated_at nebo
  ``retry_failed()``). ``sync`` je serializované zámkem; ``start_sync`` = jediný task na pozadí.
- Cíle: ``door:<uuid>`` | ``zone:<n>`` | ``outdoor`` | ``all``; ``playlist_for`` padá na ``all`` (+ legacy).
"""
from __future__ import annotations

import asyncio
import logging
import os
import re
import time
from datetime import datetime, timezone
from typing import Any, Awaitable, Callable
from urllib.parse import quote

import httpx

from .mpv_player import MUSIC_EXTENSIONS

log = logging.getLogger("motogo.music")

KV_INDEX = "music_index"
TRACKS_SUBDIR = "tracks"
BUCKET = "branch-music"
MAX_PARALLEL = 3
FILE_TIMEOUT_S = 120.0          # nečinnost spojení (httpx read) + základ stropu přenosu
MIN_RATE_BPS = 50_000           # strop přenosu = FILE_TIMEOUT_S + size / MIN_RATE_BPS
BACKOFF_BASE_S = 120.0          # první opakování po 2 min, pak 4, 8 … až BACKOFF_MAX_S
BACKOFF_MAX_S = 6 * 3600.0
CHUNK = 64 * 1024
INVALID_REASON = "neplatný záznam v konfiguraci"
_ID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_EXT_RE = re.compile(r"^[a-z0-9]{1,8}$")


class MusicSyncError(Exception):
    """Chyba stažení jedné skladby (HTTP stav, velikost, I/O)."""


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _fingerprint(tr: dict) -> str:
    """Identita obsahu skladby — změna ruší odstup opakování (backoff)."""
    return f"{tr['path']}|{tr['size']}|{tr['updated_at']}"


def normalize_track(raw: Any) -> dict | None:
    """Ověří a znormalizuje položku z ``kiosk_sync_config.music.tracks``; None = neplatná."""
    if not isinstance(raw, dict):
        return None
    tid = str(raw.get("id") or "").strip().lower()
    ext = str(raw.get("ext") or "").strip().lower().lstrip(".")
    path = str(raw.get("path") or "").strip().lstrip("/")
    if not _ID_RE.match(tid) or not _EXT_RE.match(ext) or not path or "\n" in path:
        return None
    target = str(raw.get("target") or "all").strip() or "all"
    return {
        "id": tid, "target": target, "path": path, "ext": ext,
        "size": max(0, _int(raw.get("size"))), "sort_order": _int(raw.get("sort_order")),
        "updated_at": str(raw.get("updated_at") or ""), "title": str(raw.get("title") or ""),
    }


class MusicLibrary:
    """Lokální knihovna hudby: index v kv + soubory na disku + synchronizace z Supabase Storage."""

    def __init__(self, storage, music_dir: str, supabase_url: str, *,
                 on_changed: Callable[[], Awaitable[None]] | None = None) -> None:
        self.storage = storage
        self.music_dir = music_dir
        self.tracks_dir = os.path.join(music_dir, TRACKS_SUBDIR)
        self.supabase_url = str(supabase_url or "").rstrip("/")
        self.on_changed = on_changed
        self.sync_reason: str | None = None     # proč knihovna není kompletní (None = vše staženo)
        self._task: asyncio.Task | None = None
        self._lock = asyncio.Lock()                   # sync() se nikdy nesmí překrývat
        self._wanted: dict[str, dict] | None = None   # platné skladby z poslední konfigurace
        self._invalid = 0                             # neplatné záznamy v poslední konfiguraci
        # id → {reason, attempts, next_at (monotonic), key (fingerprint)}
        self._failed: dict[str, dict] = {}
        self._index = self._load_index()

    # ─── index ──────────────────────────────────────────────────────────────
    def _load_index(self) -> dict:
        raw = self.storage.kv_get(KV_INDEX) if self.storage is not None else None
        tracks = raw.get("tracks") if isinstance(raw, dict) else None
        clean = {str(k): v for k, v in (tracks or {}).items() if isinstance(v, dict) and v.get("file")} \
            if isinstance(tracks, dict) else {}
        return {"tracks": clean, "synced_at": raw.get("synced_at") if isinstance(raw, dict) else None}

    def _save_index(self) -> None:
        if self.storage is None:
            return
        try:
            self.storage.kv_set(KV_INDEX, self._index)
        except Exception as exc:  # noqa: BLE001
            log.warning("Uložení music_index selhalo: %s", exc)

    def _register(self, tr: dict, file: str) -> None:
        """Zapíše skladbu do indexu (po stažení / adopci hotového souboru) a index hned uloží."""
        old = self._index["tracks"].get(tr["id"], {}).get("file")
        if old and old != file:
            self._remove(old)
        self._index["tracks"][tr["id"]] = {
            "target": tr["target"], "path": tr["path"], "ext": tr["ext"], "size": tr["size"],
            "updated_at": tr["updated_at"], "file": file, "sort_order": tr["sort_order"], "title": tr["title"],
        }
        self._failed.pop(tr["id"], None)
        self._save_index()

    def _file_for(self, tr: dict) -> str:
        return os.path.join(self.tracks_dir, f"{tr['id']}.{tr['ext']}")

    def _url_for(self, tr: dict) -> str | None:
        if not self.supabase_url.lower().startswith(("http://", "https://")):
            return None
        return f"{self.supabase_url}/storage/v1/object/public/{BUCKET}/{quote(tr['path'], safe='/')}"

    @staticmethod
    def _needs_download(entry: dict | None, tr: dict, file: str) -> bool:
        if entry is None or entry.get("file") != file:
            return True
        if str(entry.get("updated_at") or "") != tr["updated_at"] or _int(entry.get("size")) != tr["size"]:
            return True
        if not os.path.isfile(file):
            return True
        return tr["size"] > 0 and os.path.getsize(file) != tr["size"]

    @staticmethod
    def _complete_on_disk(tr: dict, file: str) -> bool:
        """Hotový soubor bez záznamu v indexu (sync přerušený po ``os.replace``) — netahat znovu."""
        try:
            return tr["size"] > 0 and os.path.isfile(file) and os.path.getsize(file) == tr["size"]
        except OSError:
            return False

    @staticmethod
    def _remove(path: str | None) -> None:
        try:
            if path and os.path.isfile(path):
                os.remove(path)
        except OSError as exc:
            log.warning("Smazání %s selhalo: %s", path, exc)

    # ─── chyby a odstup opakování ──────────────────────────────────────────
    def _mark_failed(self, key: str, reason: str, fingerprint: str) -> int:
        """Zaznamená chybu; vrací pořadí pokusu (1 = první → WARNING, další jen DEBUG)."""
        prev = self._failed.get(key)
        attempts = prev["attempts"] + 1 if prev and prev.get("key") == fingerprint else 1
        delay = min(BACKOFF_MAX_S, BACKOFF_BASE_S * 2 ** (attempts - 1))
        self._failed[key] = {"reason": reason, "attempts": attempts, "next_at": time.monotonic() + delay,
                             "key": fingerprint}
        return attempts

    def _in_backoff(self, tid: str, fingerprint: str) -> bool:
        f = self._failed.get(tid)
        return f is not None and f.get("key") == fingerprint and time.monotonic() < f["next_at"]

    def retry_failed(self) -> int:
        """Zruší odstup opakování u všech chybných skladeb (ruční „Znovu synchronizovat“); vrací počet."""
        for f in self._failed.values():
            f["next_at"] = 0.0
        return len(self._failed)

    # ─── synchronizace ─────────────────────────────────────────────────────
    def start_sync(self, tracks: list[dict]) -> asyncio.Task | None:
        """Spustí ``sync`` na pozadí; když už jeden běží, vrátí None a nic nedělá."""
        if self._task is not None and not self._task.done():
            log.info("Synchronizace hudby už běží — požadavek ignorován")
            return None
        self._task = asyncio.get_running_loop().create_task(self.sync(tracks), name="music-sync")
        return self._task

    async def sync(self, tracks: list[dict]) -> dict:
        """Srovná lokální knihovnu s konfigurací; vrací ``{added, removed, failed, unchanged}``. Nevyhazuje."""
        result = {"added": 0, "removed": 0, "failed": 0, "unchanged": 0}
        async with self._lock:
            try:
                await self._sync(tracks if isinstance(tracks, list) else [], result)
            except Exception as exc:  # noqa: BLE001
                log.error("Synchronizace hudby selhala: %s", exc)
                self.sync_reason = f"chyba synchronizace: {exc}"
        return result

    def _parse(self, tracks: list, result: dict) -> dict[str, dict]:
        """Znormalizuje konfiguraci; neplatné záznamy eviduje v ``_failed`` (stabilní klíč), staré chyby pročistí."""
        wanted: dict[str, dict] = {}
        invalid: list[str] = []
        for n, raw in enumerate(tracks):
            tr = normalize_track(raw)
            if tr is not None:
                wanted[tr["id"]] = tr
                continue
            key = (str(raw.get("id") or "").strip() if isinstance(raw, dict) else "") or f"invalid:{n}"
            invalid.append(key)
            if key not in self._failed:
                log.warning("Neplatná skladba v konfiguraci (%s) ignorována: %.120r", key, raw)
        for key in [k for k in self._failed if k not in wanted and k not in invalid]:
            del self._failed[key]                       # skladba z konfigurace zmizela / už je platná
        for key in invalid:
            self._mark_failed(key, INVALID_REASON, "invalid")
        result["failed"] += len(invalid)
        self._invalid = len(invalid)
        return wanted

    async def _sync(self, tracks: list, result: dict) -> None:
        wanted = self._wanted = self._parse(tracks, result)
        self.sync_reason = "stahování běží"
        try:
            os.makedirs(self.tracks_dir, exist_ok=True)
        except OSError as exc:
            log.warning("Adresář %s nelze vytvořit: %s", self.tracks_dir, exc)
        index: dict[str, dict] = self._index["tracks"]
        for tid in [t for t in index if t not in wanted]:        # skladby odebrané z konfigurace
            self._remove(index.pop(tid).get("file"))
            result["removed"] += 1
        todo: list[dict] = []
        for tid, tr in wanted.items():
            file = self._file_for(tr)
            if not self._needs_download(index.get(tid), tr, file):
                index[tid].update(target=tr["target"], sort_order=tr["sort_order"], title=tr["title"], path=tr["path"])
                self._failed.pop(tid, None)
                result["unchanged"] += 1
            elif index.get(tid) is None and self._complete_on_disk(tr, file):
                self._register(tr, file)                          # hotový soubor z přerušeného syncu
                result["added"] += 1
            elif self._in_backoff(tid, _fingerprint(tr)):
                result["failed"] += 1                             # čeká na další pokus
            else:
                todo.append(tr)
        if todo:
            sem = asyncio.Semaphore(MAX_PARALLEL)
            timeout = httpx.Timeout(FILE_TIMEOUT_S, connect=15.0)
            async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
                await asyncio.gather(*(self._download(client, sem, tr, result) for tr in todo))
        self._cleanup_orphans(index)
        self._index["synced_at"] = _now_iso()
        self._save_index()
        self.sync_reason = (f"{len(self._failed)} skladeb se nepodařilo stáhnout" if self._failed else None)
        log.info("Hudba synchronizována: +%d −%d ✗%d =%d", result["added"], result["removed"],
                 result["failed"], result["unchanged"])
        if (result["added"] or result["removed"]) and self.on_changed is not None:
            try:
                await self.on_changed()
            except Exception as exc:  # noqa: BLE001
                log.warning("on_changed po synchronizaci hudby selhalo: %s", exc)

    async def _download(self, client: httpx.AsyncClient, sem: asyncio.Semaphore, tr: dict, result: dict) -> None:
        file = self._file_for(tr)
        tid = tr["id"]
        async with sem:
            try:
                cap = FILE_TIMEOUT_S + tr["size"] / MIN_RATE_BPS     # strop celého přenosu dle velikosti
                await asyncio.wait_for(self._fetch(client, tr, file), cap)
            except asyncio.CancelledError:
                self._remove(file + ".part")
                raise
            except Exception as exc:  # noqa: BLE001
                timeout = isinstance(exc, (asyncio.TimeoutError, httpx.TimeoutException))
                reason = "timeout stahování" if timeout else str(exc) or type(exc).__name__
                self._remove(file + ".part")
                attempts = self._mark_failed(tid, reason, _fingerprint(tr))
                result["failed"] += 1
                log.log(logging.WARNING if attempts == 1 else logging.DEBUG,
                        "Skladba %s (%s) se nestáhla (pokus %d, další za %.0f s): %s", tid, tr["path"],
                        attempts, self._failed[tid]["next_at"] - time.monotonic(), reason)
                return
        self._register(tr, file)
        result["added"] += 1

    async def _fetch(self, client: httpx.AsyncClient, tr: dict, file: str) -> None:
        url = self._url_for(tr)
        if url is None:
            raise MusicSyncError("URL Supabase není http(s)")
        part = file + ".part"
        async with client.stream("GET", url) as resp:
            if resp.status_code != 200:
                raise MusicSyncError(f"HTTP {resp.status_code}")
            with open(part, "wb") as fh:
                async for chunk in resp.aiter_bytes(CHUNK):
                    fh.write(chunk)
        got = os.path.getsize(part)
        if tr["size"] > 0 and got != tr["size"]:
            raise MusicSyncError(f"velikost {got} ≠ {tr['size']} B")
        os.replace(part, file)
        log.debug("Staženo %s → %s (%d B)", tr["path"], file, got)

    def _cleanup_orphans(self, index: dict[str, dict]) -> None:
        """Smaže z ``tracks/`` soubory bez záznamu v indexu (zbytky po pádu, .part)."""
        keep = {e.get("file") for e in index.values()}
        try:
            names = os.listdir(self.tracks_dir)
        except OSError:
            return
        for n in names:
            p = os.path.join(self.tracks_dir, n)
            if p not in keep and os.path.isfile(p):
                self._remove(p)

    # ─── čtení ─────────────────────────────────────────────────────────────
    def legacy_files(self) -> list[str]:
        """Ručně nahrané soubory přímo v ``music_dir`` (abecedně) — cíl ``all``."""
        try:
            names = os.listdir(self.music_dir)
        except OSError:
            return []
        return sorted(os.path.join(self.music_dir, n) for n in names
                      if n.lower().endswith(MUSIC_EXTENSIONS) and os.path.isfile(os.path.join(self.music_dir, n)))

    def _tracks_of(self, target: str) -> list[str]:
        entries = [e for e in self._index["tracks"].values()
                   if e.get("target") == target and e.get("file") and os.path.isfile(e["file"])]
        entries.sort(key=lambda e: (_int(e.get("sort_order")), str(e.get("title") or ""), str(e.get("file"))))
        return [e["file"] for e in entries]

    def playlist_for(self, target: str) -> list[str]:
        """Absolutní cesty skladeb cíle; bez vlastních → ``all`` + legacy; když nic, []."""
        target = str(target or "all")
        if target != "all":
            own = self._tracks_of(target)
            if own:
                return own
        return self._tracks_of("all") + self.legacy_files()

    def targets(self) -> dict[str, int]:
        """Počty stažených skladeb po cílech (vždy s klíči ``all`` a ``legacy``)."""
        counts: dict[str, int] = {"all": 0, "legacy": len(self.legacy_files())}
        for e in self._index["tracks"].values():
            if e.get("file") and os.path.isfile(e["file"]):
                t = str(e.get("target") or "all")
                counts[t] = counts.get(t, 0) + 1
        return counts

    def status(self) -> dict:
        """Stav knihovny pro ``snapshot()['audio']['library']`` (neplatné záznamy počítá mezi tracks i failed)."""
        index = self._index["tracks"]
        wanted = self._wanted if self._wanted is not None else index
        synced = sum(1 for tid in wanted if tid in index and os.path.isfile(str(index[tid].get("file") or "")))
        total = len(wanted) + self._invalid
        return {
            "tracks": total, "synced": synced, "pending": max(0, total - synced),
            "failed": len(self._failed), "last_sync_at": self._index.get("synced_at"),
            "targets": self.targets(), "syncing": self._task is not None and not self._task.done(),
            "reason": self.sync_reason,
        }
