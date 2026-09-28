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

from .audio_devices import ensure_tone

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

    async def test_output(self, out: str, seconds: int = 3) -> bool:
        """Test výstupu (Velín „Test výstupu“): selector má jediný výstup `mpv` → tón v první zóně s relé."""
        zones = sorted(self.selector._refs)
        if str(out) != "mpv" or not zones:
            return False
        return await self.test_tone(zones[0], seconds)

    async def test_tone(self, zone: int, seconds: int = 5) -> bool:
        """Servisní test reproduktoru zóny GENEROVANÝM TÓNEM (funguje i bez nahrané hudby).
        Zákaznickou hudbu nepřeruší (vrátí False); `play_zone` tón naopak přebije a test ji pak nevypne."""
        tone = ensure_tone()
        async with self._lock:
            if self.playing_zone is not None and not self._tone:
                log.info("Audio test zóny %s: reproduktor používá zóna %s", zone, self.playing_zone)
                return False
            ensure = getattr(self.player, "ensure_running", None)
            if ensure is not None and not self.player.alive:
                await ensure(self.cfg.shuffle)
            if tone is None or not self.player.alive:
                log.warning("Audio test zóny %s: přehrávač neběží", zone)
                return False
            await self._cancel_fade()
            await self.player.set_volume(0)
            await self.player.pause()
            await self.player.load_files([tone], False)
            self._loaded_target = None                 # po testu se playlist zóny načte znovu
            if not await self.selector.select(zone):
                self.playing_zone = None
                return False
            await self.player.play()
            await self.player.set_volume(self.cfg.volume)
            self.playing_zone, self._tone = zone, True
            self._generation += 1
            gen = self._generation
        try:
            await asyncio.sleep(max(0, int(seconds)))
        finally:
            # i při zrušení (timeout diagnostiky) tón nesmí hrát dál — zastavit jen svůj tón
            async with self._lock:
                if self._tone and self._generation == gen:
                    await self._stop_locked(fade=False)
        return True


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

    def has_output(self, zone: int) -> bool:
        """Má zóna reproduktor (výstup `hw.audio.out`)? Bez něj se po kódu hudba nespouští (není to chyba)."""
        return int(zone) in self.zone_out

    def output_busy(self, zone: int) -> bool:
        """Výstup zóny právě hraje zákaznickou hudbu (tón testu se nepočítá)."""
        ch = self._ch(int(zone))
        return ch is not None and ch.playing is not None and not ch.tone

    async def test_output(self, out: str, seconds: int = 3) -> bool:
        """Test výstupu (Velín „Test výstupu“) tónem — i výstup, který zatím nemá žádnou zónu."""
        ch = self.channels.get(str(out))
        if ch is None:
            log.warning("Test výstupu %s: výstup není v audio.outputs", out)
            return False
        pairs = list(self.zone_out.items()) + list(self.channel_out.items())
        key = next((k for k, o in pairs if o == ch.out), None)
        return await self._tone(ch, key, seconds)

    async def _test_key(self, key: Any, seconds: int) -> bool:
        """Test zóny (`test_tone`) i kanálu (`test_channel`) tónem jen na jejich výstupu."""
        ch = self._ch(key)
        if ch is None:
            log.warning("Audio test %s: výstup chybí", key)
            return False
        return await self._tone(ch, key, seconds)

    async def _tone(self, ch: Any, key: Any, seconds: int) -> bool:
        """Generovaný tón `seconds` s (funguje i bez nahrané hudby). Zákaznickou hudbu nepřeruší (False);
        `_play` tón naopak přebije (`ch.tone`) a test pak cizí hudbu nevypne (`generation`)."""
        tone = ensure_tone()
        async with ch.lock:
            if ch.playing is not None and not ch.tone:
                log.info("Audio test %s: výstup %s právě hraje %s", key, ch.out, ch.playing)
                return False
            await self._cancel_fade(ch)
            ensure = getattr(ch.player, "ensure_running", None)
            if ensure is not None and not ch.player.alive:
                await ensure(self.cfg.shuffle)
            if tone is None or not ch.player.alive:
                log.warning("Audio test %s: přehrávač výstupu %s neběží", key, ch.out)
                return False
            await ch.player.set_volume(0)
            await ch.player.pause()
            await ch.player.load_files([tone], False)
            ch.dirty = True                           # po testu se playlist cíle načte znovu
            if key is not None:
                await self._relay(key, True)
            await ch.player.play()
            await ch.player.set_volume(self.cfg.volume)
            ch.playing, ch.tone, ch.off_at = key, True, None
            ch.generation += 1
            gen = ch.generation
        try:
            await asyncio.sleep(max(0, int(seconds)))
        finally:
            async with ch.lock:
                if ch.tone and ch.generation == gen:
                    await self._stop_locked(ch, fade=False)
        return True


__all__ = ["SelectorChannelStubs", "MultiChannelOps"]
