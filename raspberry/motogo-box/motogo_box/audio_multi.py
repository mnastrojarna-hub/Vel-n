"""Audio režim `multi`: každá místnost má vlastní výstup (ALSA) a vlastní mpv (kontrakt §6).

Program hraje současně v libovolném počtu kanálů, každý svůj playlist z knihovny hudby
(`MusicLibrary.playlist_for(target)`): zóna → `door:<uuid>` / `zone:<n>`, kanál bez dveří
(`outdoor`) → název kanálu; bez vlastních skladeb hraje cíl `all`. Kanál `outdoor`
(trigger `any`) řídí `sync_channels(active_zones)`: hraje, dokud běží aspoň jedna relace,
stop se odloží o `timings.music_after_close_s` po poslední. Selhání jednoho mpv neovlivní
ostatní (per-výstup zámek, `ensure_running` per přehrávač). Volitelné relé „enable“
zesilovače (`audio: {out, dev, coil}`) se sepne při startu hudby a vypne při zastavení.

Sestavení enginu podle `hw.audio.mode` (`build_audio`), podpis konfigurace a knihovna hudby
jsou v `audio_build.py`.
"""
from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import Any, Callable

from .audio import library_status
from .config import AudioCfg
from .models import HwRef

log = logging.getLogger("motogo.audio")

Key = int | str      # int = zóna, str = kanál bez dveří (např. "outdoor")


@dataclass
class _Channel:
    """Stav jednoho výstupu (mpv + kdo v něm hraje + načtený playlist)."""

    out: str
    player: Any
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    playing: Key | None = None
    target: str | None = None      # cíl právě načteného playlistu
    dirty: bool = True             # playlist je třeba (znovu) načíst
    generation: int = 0
    fade_task: asyncio.Task | None = None
    sync_task: asyncio.Task | None = None   # kanál bez dveří: start/stop na pozadí (neblokuje tick zón)
    off_at: float | None = None    # kanál bez dveří: čas odloženého stopu


class AudioMulti:
    """Nezávislé kanály: `players` {out: MpvPlayer}, `zone_out` {zóna: out}, `channel_out` {kanál: out},
    `relays` {zóna|kanál: HwRef} (volitelné enable relé, spíná přes `bus.set`)."""

    mode = "multi"

    def __init__(self, players: dict[str, Any], zone_out: dict[int, str], channel_out: dict[str, str],
                 relays: dict[Key, HwRef] | None, cfg: AudioCfg, library: Any = None, *,
                 bus: Any = None, zone_targets: dict[int, str] | None = None, timings: Any = None,
                 clock: Callable[[], float] = time.monotonic) -> None:
        self.cfg, self.library, self.bus, self.timings, self.clock = cfg, library, bus, timings, clock
        self.zone_out = {int(z): o for z, o in zone_out.items() if o in players}
        self.channel_out = {str(c): o for c, o in channel_out.items() if o in players}
        self.relays: dict[Key, HwRef] = dict(relays or {})
        self.targets: dict[int, str] = dict(zone_targets or {})
        self.channels: dict[str, _Channel] = {out: _Channel(out, p) for out, p in players.items()}
        self.players = players
        self.player = None            # kompatibilita (selector má jeden přehrávač)

    # ─── stav ───────────────────────────────────────────────────────────────
    @property
    def player_ok(self) -> bool:
        return bool(self.players) and all(bool(p.alive) for p in self.players.values())

    @property
    def playing_zone(self) -> int | None:
        zones = self.playing_zones
        return zones[0] if zones else None

    @property
    def playing_zones(self) -> list[int]:
        return sorted(ch.playing for ch in self.channels.values() if isinstance(ch.playing, int))

    @property
    def channels_playing(self) -> list[str]:
        return sorted(ch.playing for ch in self.channels.values() if isinstance(ch.playing, str))

    def is_playing(self, zone: int) -> bool:
        ch = self._ch(zone)
        return ch is not None and ch.playing == zone

    def update_cfg(self, cfg: AudioCfg, timings: Any = None) -> None:
        self.cfg = cfg
        if timings is not None:
            self.timings = timings

    def status(self) -> dict:
        players = {out: {"alive": bool(ch.player.alive), "playlist_count": int(getattr(ch.player, "playlist_count", 0) or 0),
                         "device": getattr(ch.player, "device", None), "playing": ch.playing, "target": ch.target}
                   for out, ch in self.channels.items()}
        devices = [f"{o}={p['device']}" for o, p in players.items() if p["device"]]
        return {"mode": self.mode, "playing_zone": self.playing_zone, "playing_zones": self.playing_zones,
                "channels": self.channels_playing, "player_ok": self.player_ok,
                "playlist_count": sum(p["playlist_count"] for p in players.values()),
                "device": ", ".join(devices) or None, "players": players, "library": library_status(self.library)}

    # ─── pomocné ────────────────────────────────────────────────────────────
    def _ch(self, key: Key) -> _Channel | None:
        out = self.zone_out.get(key) if isinstance(key, int) else self.channel_out.get(key)
        return self.channels.get(out) if out else None

    def _target_of(self, key: Key) -> str:
        if isinstance(key, int):
            return self.targets.get(key) or f"zone:{key}"
        return str(key)

    def _files_for(self, target: str) -> list[str] | None:
        if self.library is None:
            return None
        try:
            return [str(f) for f in (self.library.playlist_for(target) or [])]
        except Exception as exc:  # noqa: BLE001
            log.warning("Playlist cíle %s nelze načíst: %s", target, exc)
            return []

    async def _load(self, ch: _Channel, target: str) -> None:
        """Načte playlist cíle do mpv výstupu (jen když se změnil cíl nebo je playlist dirty)."""
        if ch.target == target and not ch.dirty:
            return
        files = self._files_for(target)
        try:
            if files is None:
                await ch.player.load_playlist(self.cfg.shuffle)
            else:
                await ch.player.load_files(files, self.cfg.shuffle)
        except Exception as exc:  # noqa: BLE001
            log.warning("%s: načtení playlistu %s selhalo: %s", ch.out, target, exc)
        ch.target, ch.dirty = target, False

    async def _relay(self, key: Key, on: bool) -> None:
        ref = self.relays.get(key)
        if ref is None or self.bus is None:
            return
        try:
            if not await self.bus.set(ref, on):
                log.warning("Audio relé %s (%s[%s]) se nepodařilo %s", key, ref.dev, ref.idx, "sepnout" if on else "vypnout")
        except Exception as exc:  # noqa: BLE001
            log.warning("Audio relé %s: %s", key, exc)

    def _start_fade(self, ch: _Channel, to: int, ms: int) -> None:
        ch.fade_task = asyncio.create_task(ch.player.fade(to, ms), name=f"motogo.audio.fade.{ch.out}")

    async def _cancel_fade(self, ch: _Channel) -> None:
        task, ch.fade_task = ch.fade_task, None
        if task is not None and not task.done():
            task.cancel()
            try:
                await task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass

    async def wait_fade(self) -> None:
        """Počká na doběh přechodů kanálů bez dveří (`sync_channels`) a fade-in/out (testy, servis)."""
        for ch in list(self.channels.values()):
            for task in (ch.sync_task, ch.fade_task):
                if task is not None and not task.done():
                    try:
                        await task
                    except (asyncio.CancelledError, Exception):  # noqa: BLE001
                        pass

    async def _cancel_sync(self, ch: _Channel) -> None:
        task, ch.sync_task = ch.sync_task, None
        if task is not None and not task.done():
            task.cancel()
            try:
                await task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass

    # ─── životní cyklus ─────────────────────────────────────────────────────
    async def start(self) -> None:
        """Spustí všechny přehrávače (nezávisle), načte playlisty cílů, hlasitost 0, pauza."""
        first: dict[str, Key] = {}
        for key, out in list(self.zone_out.items()) + list(self.channel_out.items()):
            first.setdefault(out, key)
        for out, ch in self.channels.items():
            try:
                await ch.player.start()
                await self._load(ch, self._target_of(first.get(out, "all")))
                await ch.player.set_volume(0)
                await ch.player.pause()
            except Exception as exc:  # noqa: BLE001 — jeden výstup nesmí shodit ostatní
                log.error("Start audia %s selhal: %s", out, exc)
            if not ch.player.alive:
                log.warning("Přehrávač %s neběží — kanál bude bez zvuku", out)

    async def close(self) -> None:
        await self.all_off()
        for out, ch in self.channels.items():
            try:
                await ch.player.stop()
            except Exception as exc:  # noqa: BLE001
                log.warning("Ukončení přehrávače %s selhalo: %s", out, exc)

    # ─── přehrávání ─────────────────────────────────────────────────────────
    async def _play(self, key: Key) -> bool:
        ch = self._ch(key)
        if ch is None:
            log.warning("%s nemá audio výstup — hudba nelze spustit", f"Zóna {key}" if isinstance(key, int) else f"Kanál {key}")
            return False
        async with ch.lock:
            if ch.playing == key:
                return True
            if ch.playing is not None:
                await self._stop_locked(ch, fade=True)
            await self._cancel_fade(ch)
            try:
                ensure = getattr(ch.player, "ensure_running", None)
                if ensure is not None and not ch.player.alive:
                    await ensure(self.cfg.shuffle)
                await ch.player.set_volume(0)
                await ch.player.pause()
                await self._load(ch, self._target_of(key))
                await self._relay(key, True)
                await ch.player.play()
                self._start_fade(ch, self.cfg.volume, self.cfg.fade_in_ms)
            except Exception as exc:  # noqa: BLE001 — mrtvý mpv jednoho výstupu
                log.error("Hudba %s (%s) se nespustila: %s", key, ch.out, exc)
            ch.playing, ch.off_at = key, None
            ch.generation += 1
            log.info("Hudba: %s → výstup %s (cíl %s, %s souborů)", key, ch.out, ch.target,
                     getattr(ch.player, "playlist_count", "?"))
            return True

    async def _stop_locked(self, ch: _Channel, fade: bool) -> None:
        key = ch.playing
        await self._cancel_fade(ch)
        try:
            if fade and ch.player.volume > 0:
                await ch.player.fade(0, self.cfg.fade_out_ms)
            else:
                await ch.player.set_volume(0)
            await ch.player.pause()
        except Exception as exc:  # noqa: BLE001
            log.warning("Zastavení hudby %s (%s): %s", key, ch.out, exc)
        if key is not None:
            await self._relay(key, False)
        ch.playing, ch.off_at = None, None
        if key is not None:
            log.info("Hudba: %s zastavena (výstup %s)", key, ch.out)

    async def _stop(self, key: Key, fade: bool) -> bool:
        ch = self._ch(key)
        if ch is None:
            return False
        async with ch.lock:
            if ch.playing != key:
                return False
            await self._stop_locked(ch, fade)
            return True

    async def play_zone(self, zone: int) -> bool:
        return await self._play(int(zone))

    async def stop_zone(self, zone: int, fade: bool = True) -> bool:
        return await self._stop(int(zone), fade)

    async def stop(self, fade: bool = True) -> None:
        """Zastaví hudbu ve všech zónách i kanálech."""
        for ch in list(self.channels.values()):
            async with ch.lock:
                if ch.playing is not None:
                    await self._stop_locked(ch, fade)

    async def all_off(self) -> None:
        """Okamžité bezpečné vypnutí bez fade (start programu, all_off příkaz)."""
        for ch in list(self.channels.values()):
            await self._cancel_sync(ch)
            async with ch.lock:
                await self._cancel_fade(ch)
                try:
                    await ch.player.pause()
                    await ch.player.set_volume(0)
                except Exception as exc:  # noqa: BLE001
                    log.warning("all_off přehrávače %s: %s", ch.out, exc)
                if ch.playing is not None:
                    await self._relay(ch.playing, False)
                ch.playing, ch.off_at = None, None

    async def sync_channels(self, active_zones: list[int]) -> None:
        """Kanály bez dveří (trigger any): hrají, dokud běží aspoň jedna relace; stop po
        `music_after_close_s` od poslední (volá tick smyčka zón každých 250 ms).

        Start/stop (IPC, případný restart mpv, fade) běží jako úloha na pozadí — tick smyčka
        (timeouty dveří, overtime) na ni nikdy nečeká; dokud úloha běží, další tick nic nespouští."""
        delay = float(getattr(self.timings, "music_after_close_s", 10) or 0)
        for name in list(self.channel_out):
            ch = self._ch(name)
            if ch is None:
                continue
            busy = ch.sync_task is not None and not ch.sync_task.done()
            if active_zones:
                ch.off_at = None
                if ch.playing != name and not busy:
                    ch.sync_task = asyncio.create_task(self._play(name), name=f"motogo.audio.sync.{ch.out}")
            elif ch.playing == name:
                now = self.clock()
                if ch.off_at is None:
                    ch.off_at = now + delay
                elif now >= ch.off_at and not busy:
                    ch.sync_task = asyncio.create_task(self._stop(name, fade=True), name=f"motogo.audio.sync.{ch.out}")

    async def reload_playlists(self) -> None:
        """Knihovna se změnila: volné výstupy načíst hned, hrající až po zastavení (dirty)."""
        for ch in list(self.channels.values()):
            ch.dirty = True
            if ch.playing is None and ch.target is not None and not ch.lock.locked():
                async with ch.lock:
                    if ch.playing is None:
                        await self._load(ch, ch.target)

    async def reselect_if_playing(self, module: str) -> None:
        """Po obnově modulu (all_off) znovu sepne enable relé hrajících kanálů, která na něm leží."""
        for ch in list(self.channels.values()):
            key, ref = ch.playing, self.relays.get(ch.playing) if ch.playing is not None else None
            if ref is not None and ref.dev == module:
                log.warning("Audio: modul %s obnoven — znovu spínám relé %s", module, key)
                await self._relay(key, True)

    async def test_tone(self, zone: int, seconds: int = 5) -> bool:
        """Servisní test: přehraje `seconds` s JEN na výstupu zóny a zastaví (jen svoji hudbu)."""
        ch = self._ch(int(zone))
        files = self._files_for(self._target_of(int(zone)))
        count: Any = 0
        if ch is not None:
            count = len(files) if files is not None else getattr(ch.player, "playlist_count", None)
        if ch is None or not ch.player.alive or (count is not None and int(count or 0) <= 0):
            log.warning("Audio test zóny %s: výstup chybí, mpv neběží nebo je playlist prázdný (%s)", zone, count)
            return False
        ok = await self.play_zone(zone)
        if ok:
            gen = ch.generation
            try:
                await asyncio.sleep(max(0, int(seconds)))
            finally:
                if ch.playing == zone and ch.generation == gen:
                    await self.stop_zone(zone, fade=True)
        return ok


__all__ = ["AudioMulti", "Key"]
