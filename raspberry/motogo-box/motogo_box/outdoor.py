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

from .config_outdoor import CHANNEL, OutdoorCfg

log = logging.getLogger("motogo.outdoor")

RETRY_S = 5.0          # po chybě relé nejdřív za 5 s (tick je 250 ms — nezaplavit log ani sběrnici)
TEST_LIGHT_S = 1.0     # servisní test: světlo 1 s → obnovit


class OutdoorController:
    """Venek (zóna bez dveří): světlo svítí od první relace do `light_after_close_s` po poslední;
    hudba = kanál `outdoor` AudioMulti. `manual`: True = drží rozsvíceno, False = zhasnuto do další
    relace, None = automaticky dle relací."""

    def __init__(self, cfg: OutdoorCfg, io: Any, timings: Any, audio: Any,
                 clock: Callable[[], float] = time.monotonic) -> None:
        self.cfg, self.io, self.timings, self.audio, self.clock = cfg, io, timings, audio, clock
        self.light_on: bool = False
        self.active: bool = False
        self.manual: bool | None = None
        self.off_at: float | None = None
        self._retry_at: float | None = None
        self._testing: bool = False          # běží test_sequence (druhý souběžný test → busy)

    # ─── konfigurace ─────────────────────────────────────────────────────────
    def update_cfg(self, cfg: OutdoorCfg, timings: Any = None) -> None:
        """Změna bez přestavby HW (doběh, číslo zóny, audio výstup); relé světla mění podpis → přestavba."""
        self.cfg = cfg
        if timings is not None:
            self.timings = timings

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
        Ruční režim: když `set_light` na relé selhalo, `sync` stav dorovná (backoff `RETRY_S` v `_set`)."""
        if not self.cfg.configured:
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

    async def set_light(self, on: bool) -> bool:
        """Ruční z Velína/servisu: True drží rozsvíceno, False zhasne do další relace."""
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
        """Bezpečné vypnutí (start, all_off příkaz): světlo off, ruční režim i doběh zrušen."""
        self.manual, self.off_at, self.active = None, None, False
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
                "light_ref": cfg.light_ref(), "off_in_s": off_in}


__all__ = ["OutdoorController", "RETRY_S"]
