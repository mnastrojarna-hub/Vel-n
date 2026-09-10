"""Přehrávač hudby: `mpv` jako subprocess + JSON IPC přes unix socket (kontrakt §6).

Když binárka `mpv` chybí (FileNotFoundError) nebo se nepodaří připojit k IPC
socketu, přehrávač běží v „dummy" režimu: `alive=False`, metody nic neposílají,
nevyhazují a logují varování — controller tím nesmí spadnout.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import random
from typing import Any

log = logging.getLogger("motogo.mpv")

MUSIC_EXTENSIONS = (".mp3", ".ogg", ".flac", ".wav", ".m4a")
IPC_TIMEOUT_S = 2.0
SOCKET_WAIT_S = 5.0
RESTART_MIN_INTERVAL_S = 30.0   # ochrana proti restart smyčce zaseknutého mpv


class MpvError(Exception):
    """Chyba IPC komunikace s mpv (timeout, chybová odpověď, odpojený socket)."""


class MpvPlayer:
    """Řídí jeden proces mpv (idle, bez videa, playlist ve smyčce)."""

    def __init__(self, socket_path: str, music_dir: str, device: str | None = None) -> None:
        self.socket_path = socket_path
        self.music_dir = music_dir
        self.device = device
        self.volume: int = 0
        self.playlist_count: int = 0
        self._proc: asyncio.subprocess.Process | None = None
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._reader_task: asyncio.Task | None = None
        self._pending: dict[int, asyncio.Future] = {}
        self._req_id = 0
        self._write_lock = asyncio.Lock()
        self._dummy = False
        self._missing_binary = False   # mpv není nainstalováno → restart nemá smysl (jiné selhání ano)
        self._shuffle = True
        self._last_restart = 0.0

    # ─── stav ───────────────────────────────────────────────────────────────
    @property
    def alive(self) -> bool:
        """True, když proces mpv běží a IPC socket je připojený."""
        if self._dummy or self._proc is None or self._proc.returncode is not None:
            return False
        return self._writer is not None and not self._writer.is_closing()

    def _mpv_args(self) -> list[str]:
        args = ["mpv", "--idle=yes", "--no-video", "--no-terminal",
                f"--input-ipc-server={self.socket_path}", "--volume=0", "--loop-playlist=inf"]
        if self.device:
            args.append(f"--audio-device={self.device}")
        return args

    # ─── životní cyklus ─────────────────────────────────────────────────────
    async def start(self) -> None:
        """Spustí mpv a připojí se k IPC socketu; bez mpv přejde do dummy režimu."""
        if self.alive:
            return
        self._dummy = False
        sock_dir = os.path.dirname(self.socket_path)
        try:
            if sock_dir:
                os.makedirs(sock_dir, exist_ok=True)
            if os.path.exists(self.socket_path):
                os.remove(self.socket_path)
        except OSError as exc:
            log.warning("Příprava socketu %s selhala: %s", self.socket_path, exc)
        try:
            self._proc = await asyncio.create_subprocess_exec(
                *self._mpv_args(), stdin=asyncio.subprocess.DEVNULL,
                stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
            )
        except FileNotFoundError:
            self._dummy = self._missing_binary = True
            log.warning("mpv není nainstalováno — audio běží v dummy režimu (bez zvuku)")
            return
        except OSError as exc:
            self._dummy = True
            log.warning("Spuštění mpv selhalo (%s) — dummy režim", exc)
            return
        if not await self._connect_ipc():
            log.error("IPC socket mpv (%s) se nepodařilo připojit — dummy režim", self.socket_path)
            await self._kill_process()
            self._dummy = True
            return
        log.info("mpv spuštěno (pid %s, socket %s)", self._proc.pid, self.socket_path)

    async def _connect_ipc(self) -> bool:
        """Čeká na vznik socketu (max SOCKET_WAIT_S) a otevře spojení."""
        deadline = asyncio.get_running_loop().time() + SOCKET_WAIT_S
        while asyncio.get_running_loop().time() < deadline:
            if self._proc is not None and self._proc.returncode is not None:
                return False
            if os.path.exists(self.socket_path):
                try:
                    self._reader, self._writer = await asyncio.open_unix_connection(self.socket_path)
                    self._reader_task = asyncio.create_task(self._read_loop(), name="mpv-ipc-reader")
                    return True
                except OSError:
                    pass
            await asyncio.sleep(0.1)
        return False

    async def stop(self) -> None:
        """Ukončí IPC i proces mpv (SIGTERM, po 3 s SIGKILL)."""
        if self._reader_task is not None:
            self._reader_task.cancel()
            try:
                await self._reader_task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass
            self._reader_task = None
        if self._writer is not None:
            try:
                self._writer.close()
            except Exception:  # noqa: BLE001
                pass
            self._writer = None
            self._reader = None
        self._fail_pending("mpv ukončeno")
        await self._kill_process()
        try:
            if os.path.exists(self.socket_path):
                os.remove(self.socket_path)
        except OSError:
            pass

    async def _kill_process(self) -> None:
        proc, self._proc = self._proc, None
        if proc is None or proc.returncode is not None:
            return
        try:
            proc.terminate()
            await asyncio.wait_for(proc.wait(), timeout=3.0)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
        except ProcessLookupError:
            pass

    # ─── IPC ────────────────────────────────────────────────────────────────
    async def _read_loop(self) -> None:
        assert self._reader is not None
        try:
            while True:
                line = await self._reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line.decode("utf-8", "replace"))
                except ValueError:
                    continue
                rid = msg.get("request_id") if isinstance(msg, dict) else None
                fut = self._pending.pop(rid, None) if rid is not None else None
                if fut is not None and not fut.done():
                    fut.set_result(msg)
                elif isinstance(msg, dict) and msg.get("event"):
                    log.debug("mpv event: %s", msg.get("event"))
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001
            log.warning("IPC čtení mpv skončilo chybou: %s", exc)
        finally:
            self._fail_pending("IPC socket mpv uzavřen")
            if self._writer is not None:
                self._writer.close()
                self._writer = None

    def _fail_pending(self, reason: str) -> None:
        for fut in self._pending.values():
            if not fut.done():
                fut.set_exception(MpvError(reason))
        self._pending.clear()

    async def command(self, *args: Any) -> Any:
        """Pošle `{"command":[...]}` a vrátí `data` odpovědi. V dummy režimu vrací None.

        Vyhazuje `MpvError` při timeoutu (2 s), chybové odpovědi nebo odpojení.
        """
        if not self.alive or self._writer is None:
            log.debug("mpv není dostupné, příkaz %s ignorován", args[:1])
            return None
        self._req_id += 1
        rid = self._req_id
        fut: asyncio.Future = asyncio.get_running_loop().create_future()
        self._pending[rid] = fut
        payload = json.dumps({"command": list(args), "request_id": rid}) + "\n"
        try:
            async with self._write_lock:
                self._writer.write(payload.encode("utf-8"))
                await self._writer.drain()
            msg = await asyncio.wait_for(fut, timeout=IPC_TIMEOUT_S)
        except asyncio.TimeoutError as exc:
            self._pending.pop(rid, None)
            # Zaseknuté IPC (typicky odpojená/zamrzlá USB zvuková karta): přehrávač prohlásit za mrtvý,
            # aby další příkazy (fade 10 kroků, pause, play…) nečekaly každý 2 s a nezdržovaly pulz zámku.
            self._mark_dead(f"timeout příkazu {args[0]!r}")
            raise MpvError(f"timeout příkazu {args[0]!r}") from exc
        except (OSError, ConnectionError) as exc:
            self._pending.pop(rid, None)
            raise MpvError(f"IPC chyba: {exc}") from exc
        if msg.get("error") not in (None, "success"):
            raise MpvError(f"mpv odmítlo {args[0]!r}: {msg.get('error')}")
        return msg.get("data")

    def _mark_dead(self, reason: str) -> None:
        """Uzavře IPC (alive → False); proces se ukončí/restartuje až v `ensure_running`."""
        log.error("mpv neodpovídá (%s) — přehrávač označen jako mrtvý", reason)
        if self._writer is not None:
            try:
                self._writer.close()
            except Exception:  # noqa: BLE001
                pass
            self._writer = None
        self._fail_pending(reason)

    async def ensure_running(self, shuffle: bool | None = None) -> bool:
        """Když mpv neběží/neodpovídá (a není dummy = chybějící binárka), zkusí ho restartovat
        (nejvýš jednou za `RESTART_MIN_INTERVAL_S`) a znovu načíst playlist. Vrací `alive`."""
        if self.alive:
            return True
        if self._missing_binary:
            return False
        now = asyncio.get_running_loop().time()
        if now - self._last_restart < RESTART_MIN_INTERVAL_S:
            return False
        self._last_restart = now
        log.warning("Restartuji mpv")
        await self.stop()
        await self.start()
        if self.alive:
            await self.load_playlist(self._shuffle if shuffle is None else shuffle)
            await self.set_volume(0)
        return self.alive

    async def _safe(self, *args: Any) -> bool:
        """`command` bez výjimek — chybu zaloguje, vrátí False."""
        try:
            await self.command(*args)
            return self.alive
        except MpvError as exc:
            log.warning("mpv %s: %s", args[0], exc)
            return False

    # ─── ovládání ───────────────────────────────────────────────────────────
    def list_files(self) -> list[str]:
        """Hudební soubory v `music_dir` (abecedně)."""
        try:
            names = os.listdir(self.music_dir)
        except OSError as exc:
            log.warning("Adresář s hudbou %s nelze číst: %s", self.music_dir, exc)
            return []
        return sorted(os.path.join(self.music_dir, n) for n in names
                      if n.lower().endswith(MUSIC_EXTENSIONS)
                      and os.path.isfile(os.path.join(self.music_dir, n)))

    async def load_playlist(self, shuffle: bool = True) -> int:
        """Načte soubory z `music_dir` (první `replace`, další `append-play`); vrací počet."""
        self._shuffle = bool(shuffle)
        files = self.list_files()
        if shuffle:
            random.shuffle(files)
        if not files:
            log.warning("V %s nejsou žádné hudební soubory", self.music_dir)
            self.playlist_count = 0
            return 0
        if not self.alive:
            log.warning("mpv neběží — playlist (%d souborů) nenačten", len(files))
            self.playlist_count = 0
            return 0
        loaded = 0
        for i, path in enumerate(files):
            if await self._safe("loadfile", path, "replace" if i == 0 else "append-play"):
                loaded += 1
        await self._safe("set_property", "pause", True)
        self.playlist_count = loaded
        log.info("Playlist: %d souborů z %s", loaded, self.music_dir)
        return loaded

    async def play(self) -> None:
        await self._safe("set_property", "pause", False)

    async def pause(self) -> None:
        await self._safe("set_property", "pause", True)

    async def set_volume(self, vol: int) -> bool:
        """Nastaví hlasitost; False = mpv nedostupné/neodpovídá (volající nemá pokračovat v kroku)."""
        self.volume = max(0, min(100, int(vol)))
        return await self._safe("set_property", "volume", self.volume)

    async def fade(self, to: int, ms: int, steps: int = 10) -> bool:
        """Lineární přechod hlasitosti z aktuální na `to` během `ms` v `steps` krocích.

        Při první neúspěšné změně hlasitosti (mpv neodpovídá) končí hned — nikdy nečeká
        `steps × timeout`. Vrací True, když všechny kroky prošly.
        """
        target = max(0, min(100, int(to)))
        if steps <= 0 or ms <= 0 or target == self.volume or not self.alive:
            return await self.set_volume(target)
        start = self.volume
        delay = (ms / 1000.0) / steps
        for i in range(1, steps + 1):
            if not await self.set_volume(round(start + (target - start) * i / steps)):
                return False
            if i < steps:
                await asyncio.sleep(delay)
        return True
