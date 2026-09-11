"""Kanály bez dveří (venek) — rozšíření audio enginů (kontrakt §6, rozhodnutí 2026-09-11).

`MultiChannelOps` je mixin `AudioMulti`: ruční `play_channel`/`stop_channel` (Velín, servis)
a `test_channel` (tón jen na výstupu kanálu — sdílí vnitřní `_test_key` s `test_tone` zóny).
Ručně spuštěný kanál (`ch.manual = True`) hraje, dokud nepřijde `stop_channel` (`manual = False`)
nebo relace (první relace `manual = None` → dál řídí `sync_channels`).

`SelectorChannelStubs` je mixin `AudioController` (selector): kanály bez dveří nemá — venek
v režimu selector nelze (`play_channel`/`stop_channel`/`test_channel` → False).
Oddělený modul kvůli délce `audio.py` / `audio_multi.py`.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any

log = logging.getLogger("motogo.audio")


class SelectorChannelStubs:
    """Selector: žádné kanály bez dveří (společné rozhraní s multi)."""

    @property
    def channels_playing(self) -> list[str]:
        return []

    async def sync_channels(self, active_zones: list[int]) -> None:
        """Selector kanály nemá — nic."""

    async def play_channel(self, name: str, *, hold: bool = True) -> bool:
        log.warning("Kanál %s: v režimu selector nelze (venek vyžaduje audio.mode multi)", name)
        return False

    async def stop_channel(self, name: str, fade: bool = True) -> bool:
        return False

    async def test_channel(self, name: str, seconds: int = 3) -> bool:
        return False


class MultiChannelOps:
    """Mixin `AudioMulti` — používá `_ch`, `_play`, `_stop`, `_files_for`, `_target_of`, `channel_out`."""

    channel_out: dict[str, str]

    async def play_channel(self, name: str, *, hold: bool = True) -> bool:
        """Ruční start kanálu (Velín/servis): hraje, dokud nepřijde `stop_channel` nebo relace.
        `hold=False` = bez ručního režimu (`manual = None`, dál řídí `sync_channels`) — obnova hudby
        venku po servisním testu, když mezitím začala relace (`OutdoorController._test_audio`)."""
        name = str(name)
        ch = self._ch(name) if name in self.channel_out else None
        if ch is None:
            log.warning("Kanál %s nemá audio výstup — hudba nelze spustit", name)
            return False
        ok = await self._play(name)
        if ok:
            ch.manual, ch.off_at = (True if hold else None), None
        return ok

    async def stop_channel(self, name: str, fade: bool = True) -> bool:
        """Ruční stop kanálu; `manual = False` = bez relace se sám znovu nespustí."""
        name = str(name)
        ch = self._ch(name) if name in self.channel_out else None
        if ch is None:
            return False
        stopped = await self._stop(name, fade)
        ch.manual = False
        return stopped

    async def test_channel(self, name: str, seconds: int = 3) -> bool:
        """Servisní test: `seconds` s JEN na výstupu kanálu (bez zásahu do ostatních kanálů)."""
        name = str(name)
        if name not in self.channel_out:
            log.warning("Audio test kanálu %s: kanál není nastaven", name)
            return False
        return await self._test_key(name, seconds)

    async def _test_key(self, key: Any, seconds: int) -> bool:
        """Společný test zóny (`test_tone`) i kanálu: přehraje a zastaví JEN svoji hudbu —
        pokud výstup mezitím převzala relace (`generation`), zákazníkovi hudba nezmizí."""
        ch = self._ch(key)
        files = self._files_for(self._target_of(key))
        count: Any = 0
        if ch is not None:
            count = len(files) if files is not None else getattr(ch.player, "playlist_count", None)
        if ch is None or not ch.player.alive or (count is not None and int(count or 0) <= 0):
            log.warning("Audio test %s: výstup chybí, mpv neběží nebo je playlist prázdný (%s)", key, count)
            return False
        ok = await self._play(key)
        if ok:
            gen = ch.generation
            try:
                await asyncio.sleep(max(0, int(seconds)))
            finally:
                if ch.playing == key and ch.generation == gen:
                    await self._stop(key, fade=True)
        return ok


__all__ = ["SelectorChannelStubs", "MultiChannelOps"]
