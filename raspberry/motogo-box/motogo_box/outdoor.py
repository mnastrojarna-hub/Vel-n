"""Venek (zóna bez dveří) — venkovní osvětlení + hudba venku (rozhodnutí uživatele 2026-09-11).

`OutdoorController` řídí venkovní světlo (relé Waveshare z `hw.outdoor.light`): svítí od první
relace (zadání kódu) do `light_after_close_s` po poslední; hudba venku = kanál `outdoor`
enginu `AudioMulti` (`sync_channels`, jen režim multi). Volá ho tick smyčka zón každých 250 ms
(`sync(active_zones)`) — nikdy nečeká déle než jeden `io.set` (Modbus timeout); po chybě relé
se další pokus odloží o `RETRY_S`. Bez `cfg.configured` je vše no-op. Žádné nové EventKind —
selhání relé jen `log.warning`. Konfigurace: `config_outdoor.OutdoorCfg`.
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
        """Relace běží → světlo svítí (ruční režim se ruší); jinak doběh a zhasnout."""
        if not self.cfg.configured:
            return
        if active_zones:
            self.active, self.manual, self.off_at = True, None, None
            if not self.light_on:
                await self._set(True)
            return
        self.active = False
        if self.manual is not None or not self.light_on:
            return                       # True drží rozsvíceno, False už je zhasnuté; bez světla nic
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
        """Servisní test: světlo 1 s → obnovit; audio 3 s na výstupu venku (jen multi, když nehraje).
        `{"light": bool, "audio": bool|None, "error"?: "busy"|"not_configured"}`."""
        if not self.cfg.configured:
            return {"light": False, "audio": None, "error": "not_configured"}
        if self.active:
            return {"light": False, "audio": None, "error": "busy"}
        prev, light = self.light_on, False
        if self.cfg.light is not None:
            try:
                light = await self._set(True, force=True)
                await asyncio.sleep(TEST_LIGHT_S)
            finally:
                light = await self._set(prev, force=True) and light      # i při zrušení vrátit původní stav
        audio: bool | None = None
        test_channel = getattr(self.audio, "test_channel", None)
        if self.cfg.audio_out and test_channel is not None and getattr(self.audio, "mode", "") == "multi":
            if CHANNEL in (getattr(self.audio, "channels_playing", None) or []):
                log.info("Venek: audio test přeskočen — kanál venku právě hraje")
            else:
                try:
                    audio = bool(await test_channel(CHANNEL, 3))
                except Exception:  # noqa: BLE001
                    log.exception("Venek: audio test selhal")
                    audio = False
        return {"light": light, "audio": audio}

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
