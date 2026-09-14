"""Venek (zóna bez dveří) — venkovní osvětlení + hudba venku (rozhodnutí uživatele 2026-09-11).

`OutdoorController` řídí venkovní světlo (relé Waveshare z `hw.outdoor.light`): svítí od první
relace (zadání kódu) do `light_after_close_s` po poslední; hudba venku = kanál `outdoor`
enginu `AudioMulti` (`sync_channels`, jen režim multi). Volá ho tick smyčka zón každých 250 ms
(`sync(active_zones)`) — nikdy nečeká déle než jeden `io.set` (Modbus timeout); po chybě relé
se další pokus odloží o `RETRY_S`. Bez `cfg.configured` je vše no-op. Žádné nové EventKind —
selhání relé jen `log.warning`. Konfigurace: `config_outdoor.OutdoorCfg`.
Venek nemá zámek `_busy` jako zóna — tick `sync` běží i během `test_sequence`; test proto po skončení
obnovuje stav podle AKTUÁLNÍ relace / ručního režimu, ne podle stavu před testem.
"""
from __future__ import annotations

import asyncio
import logging
import time
from typing import Any, Callable

from .config_outdoor import CHANNEL, LIGHT_AUTO, MUSIC_ALWAYS, MUSIC_OFF, MUSIC_SESSION, OutdoorCfg

log = logging.getLogger("motogo.outdoor")

RETRY_S = 5.0          # po chybě relé nejdřív za 5 s (tick je 250 ms — nezaplavit log ani sběrnici)
TEST_LIGHT_S = 1.0     # servisní test: světlo 1 s → obnovit


class OutdoorController:
    """Venek (zóna bez dveří): světlo svítí od první relace do `light_after_close_s` po poslední;
    hudba = kanál `outdoor` AudioMulti. `manual`: True = drží rozsvíceno, False = zhasnuto do další
    relace, None = automaticky dle relací."""

    def __init__(self, cfg: OutdoorCfg, io: Any, timings: Any, audio: Any,
                 clock: Callable[[], float] = time.monotonic, music_allowed: bool = True) -> None:
        self.cfg, self.io, self.timings, self.audio, self.clock = cfg, io, timings, audio, clock
        # Hlavní vypínač hudby pobočky (`hardware.audio.music_enabled`) — vypnutý umlčí i venek.
        self.music_allowed: bool = music_allowed
        self.light_on: bool = False
        self.active: bool = False
        self.manual: bool | None = None
        self.off_at: float | None = None
        self._retry_at: float | None = None
        self._testing: bool = False          # běží test_sequence (druhý souběžný test → busy)
        self.music_manual: bool | None = None   # ruční hudba venku z Velína (None = řídí `music_mode`)
        self._music_retry_at: float | None = None

    # ─── konfigurace ─────────────────────────────────────────────────────────
    def update_cfg(self, cfg: OutdoorCfg, timings: Any = None, music_allowed: bool | None = None) -> None:
        """Změna bez přestavby HW (doběh, číslo zóny, audio výstup, hlavní vypínač hudby);
        relé světla mění podpis → přestavba."""
        self.cfg = cfg
        if timings is not None:
            self.timings = timings
        if music_allowed is not None:
            self.music_allowed = music_allowed

    def _delay(self) -> float:
        if self.cfg.light_after_close_s is not None:
            return float(self.cfg.light_after_close_s)
        return float(getattr(self.timings, "light_after_close_s", 30) or 0)

    # ─── relé ────────────────────────────────────────────────────────────────
    async def _set(self, on: bool, *, force: bool = False) -> bool:
        """Sepne/vypne relé světla; False = bez světla / odmítnuto (retry) / chyba. Úspěch → `light_on`."""
        ref = self.cfg.light
        if ref is None:
            return False
        now = self.clock()
        if not force and self._retry_at is not None and now < self._retry_at:
            return False
        try:
            ok = bool(await self.io.set(ref, on))
        except Exception as exc:  # noqa: BLE001 — chyba sběrnice nesmí shodit tick
            log.warning("Venek: světlo %s[%s] %s selhalo: %s", ref.dev, ref.idx, "on" if on else "off", exc)
            ok = False
        if ok:
            self.light_on, self._retry_at = on, None
            if not on:
                self.off_at = None
            log.info("Venek: světlo %s", "rozsvíceno" if on else "zhasnuto")
        else:
            self._retry_at = now + RETRY_S
            log.warning("Venek: relé světla %s[%s] se nepodařilo %s — další pokus za %.0f s",
                        ref.dev, ref.idx, "sepnout" if on else "vypnout", RETRY_S)
        return ok

    # ─── řízení z tick smyčky ────────────────────────────────────────────────
    async def sync(self, active_zones: list[int]) -> None:
        """Relace běží → světlo svítí (ruční režim se ruší); jinak doběh a zhasnout.
        Ruční režim: když `set_light` na relé selhalo, `sync` stav dorovná (backoff `RETRY_S` v `_set`).
        Režimy `light_mode`/`music_mode` (2026-09-14) relace neřeší vůbec — viz `_sync_light_mode`
        a `_sync_music_mode`; venek tak může svítit nonstop, zatímco v kójích se světlo řídí relací."""
        if not self.cfg.configured:
            return
        await self._sync_music_mode()
        if self.cfg.light_mode != LIGHT_AUTO:
            await self._sync_light_mode(active_zones)
            return
        if active_zones:
            self.active, self.manual, self.off_at = True, None, None
            if not self.light_on:
                await self._set(True)
            return
        self.active = False
        if self.manual is not None:
            if self.light_on != self.manual:
                await self._set(self.manual)     # ruční příkaz selhal (relé) → opakovat, bez doběhu
            return                               # True drží rozsvíceno, False zhasnuté
        if not self.light_on:
            return
        now = self.clock()
        if self.off_at is None:
            self.off_at = now + self._delay()
        elif now >= self.off_at:
            await self._set(False)

    async def _sync_light_mode(self, active_zones: list[int]) -> None:
        """Režim `always` (nonstop) / `off` (trvale zhasnuto): relace ani doběh se neřeší.
        Ruční příkaz z Velína/servisu má i tady přednost (technik smí venku zhasnout při údržbě) —
        drží, dokud ho někdo nezruší nebo jednotka nerestartuje. `_set` si sám hlídá backoff po chybě relé."""
        self.active = bool(active_zones)
        self.off_at = None
        want = self.manual if self.manual is not None else self.cfg.light_always
        if self.light_on != want:
            await self._set(want)

    async def _sync_music_mode(self) -> None:
        """Hudba venku mimo výchozí režim `session`. `always` = drží hrát i bez relace (kanál se pouští
        s `hold=True`, takže ho `AudioMulti.sync_channels` nezastaví); `off` = venku nikdy nehraje.
        Relace `manual` kanálu ruší (`sync_channels`), proto se režim vyhodnocuje při každém ticku.

        Ruční příkaz z Velína (`music_manual`, tlačítko Hudba ▶/⏹) má přednost před režimem — stejně
        jako u světla; jinak by v režimu `off` šla hudba zapnout jen na čtvrt sekundy. Drží do dalšího
        ručního příkazu nebo restartu jednotky.

        V režimu audio `selector` kanály bez dveří neexistují (`play_channel` vrací False) — bez
        backoffu by se pokus opakoval 4×/s a zaplavil log. Po neúspěchu se proto další pokus odloží
        o `RETRY_S`, stejně jako u relé světla."""
        mode = self.cfg.music_mode
        if not self.music_allowed:
            mode = MUSIC_OFF          # hlavní vypínač pobočky umlčí venek bez ohledu na jeho režim
        if mode == MUSIC_SESSION or not self.cfg.audio_out or self.music_manual is not None:
            return
        playing = CHANNEL in self._playing()
        if mode == MUSIC_ALWAYS and not playing:
            now = self.clock()
            if self._music_retry_at is not None and now < self._music_retry_at:
                return
            play = getattr(self.audio, "play_channel", None)
            ok = bool(await play(CHANNEL, hold=True)) if play is not None else False
            self._music_retry_at = None if ok else now + RETRY_S
        elif mode == MUSIC_OFF and playing:
            stop = getattr(self.audio, "stop_channel", None)
            if stop is not None:
                await stop(CHANNEL)

    def set_music_manual(self, on: bool | None) -> None:
        """Ruční zapnutí/vypnutí hudby venku z Velína nebo servisu (None = zpět na nastavený režim).
        Volá `commands._music_on` / `_music_off`; drží do dalšího příkazu nebo restartu jednotky."""
        self.music_manual = on
        self._music_retry_at = None

    async def set_light(self, on: bool) -> bool:
        """Ruční z Velína/servisu: True drží rozsvíceno, False zhasne do další relace.
        V režimu `always`/`off` drží ruční stav, dokud ho někdo nezruší (relace ho neruší)."""
        if not self.cfg.configured or self.cfg.light is None:
            return False
        self.manual, self.off_at = on, None
        return await self._set(on, force=True)

    async def on_module_reinit(self, name: str) -> None:
        """Modul po obnově (all_off): světlo mělo svítit → znovu sepnout."""
        ref = self.cfg.light
        if ref is not None and ref.dev == name and self.light_on:
            log.warning("Venek: modul %s obnoven — znovu rozsvěcím venkovní světlo", name)
            await self._set(True, force=True)

    async def all_off(self) -> None:
        """Bezpečné vypnutí (start, all_off příkaz): světlo off, ruční režim i doběh zrušen.
        V režimu `always` (nonstop) by ho další tick za 250 ms hned rozsvítil a tlačítko „Vše vypnout“
        by venku nic neudělalo — proto se tam uloží ruční vypnutí (`manual=False`), které drží do dalšího
        `light_on` z Velína/servisu nebo do restartu jednotky (po startu platí zase nastavený režim)."""
        self.manual = False if self.cfg.light_always else None
        self.music_manual, self._music_retry_at = None, None
        self.off_at, self.active = None, False
        if self.cfg.light is not None and self.light_on:
            await self._set(False, force=True)
        self.light_on = False

    # ─── servis ──────────────────────────────────────────────────────────────
    async def test_sequence(self) -> dict:
        """Servisní test: světlo 1 s → obnovit (jen s relé světla, jinak None); audio 3 s na výstupu venku
        (jen multi, když nehraje). `{"light": bool|None, "audio": bool|None, "error"?: "busy"|"not_configured"}`.
        Relace zahájená během testu (tick `sync` nemá zámek): světlo zůstane svítit a hudba venku se hned
        obnoví — test zákazníkovi nikdy nic nezhasne. Souběžný druhý test → `busy`."""
        if not self.cfg.configured:
            return {"light": False, "audio": None, "error": "not_configured"}
        if self.active or self._testing:
            return {"light": False, "audio": None, "error": "busy"}
        self._testing = True
        try:
            light = await self._test_light()
            audio = await self._test_audio()
        finally:
            self._testing = False
        return {"light": light, "audio": audio}

    async def _test_light(self) -> bool | None:
        """Světlo 1 s → obnovit; None = venek bez relé světla (jen audio výstup) — relé se nesahá."""
        if self.cfg.light is None:
            return None
        prev, light = self.light_on, False
        try:
            light = await self._set(True, force=True)
            await asyncio.sleep(TEST_LIGHT_S)
        finally:
            # relace během testu → svítit dál; ruční příkaz během testu → jeho stav; jinak původní (i po zrušení)
            want = self.active or (prev if self.manual is None else self.manual)
            light = await self._set(want, force=True) and light
        return light

    async def _test_audio(self) -> bool | None:
        """Tón 3 s na výstupu venku (jen multi, když kanál nehraje); None = netestováno."""
        test_channel = getattr(self.audio, "test_channel", None)
        if not self.cfg.audio_out or test_channel is None or getattr(self.audio, "mode", "") != "multi":
            return None
        if CHANNEL in self._playing():
            log.info("Venek: audio test přeskočen — kanál venku právě hraje")
            return None
        try:
            audio = bool(await test_channel(CHANNEL, 3))
        except Exception:  # noqa: BLE001
            log.exception("Venek: audio test selhal")
            audio = False
        play = getattr(self.audio, "play_channel", None)
        if play is not None and self.active and CHANNEL not in self._playing():
            # relace začala během tónu: `_test_key` kanál zastavil → hned zpět (jinak až další tick s fade);
            # bez ručního režimu (`hold=False`) — dál ho řídí `sync_channels` (doběh po poslední relaci)
            log.info("Venek: relace během audio testu — hudba venku pokračuje")
            await play(CHANNEL, hold=False)
        return audio

    def _playing(self) -> list[str]:
        return list(getattr(self.audio, "channels_playing", None) or [])

    def status(self) -> dict:
        """Stav do `snapshot()["outdoor"]` (Velín, displej, diagnostika)."""
        cfg = self.cfg
        off_in = None
        if self.off_at is not None and self.light_on:
            off_in = max(0, int(self.off_at - self.clock()))
        return {"zone": cfg.zone, "configured": cfg.configured, "light": self.light_on, "active": self.active,
                "manual": self.manual, "audio_out": cfg.audio_out,
                "music": CHANNEL in (getattr(self.audio, "channels_playing", None) or []),
                "light_ref": cfg.light_ref(), "off_in_s": off_in,
                "light_mode": cfg.light_mode, "music_mode": cfg.music_mode, "music_manual": self.music_manual}


__all__ = ["OutdoorController", "RETRY_S"]
