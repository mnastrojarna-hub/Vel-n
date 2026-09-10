"""Audio: mpv přehrávač + reléový selektor reproduktorů (kontrakt §6, spec §8).

Zesilovač je mono a SPK+ jde přes 9 samostatných NO relé — SOUČASNĚ smí být
sepnuté nejvýše jedno audio relé (paralelní reproduktory by snížily impedanci
a poškodily zesilovač). `AudioSelector` proto nikdy nesepne relé zóny, dokud
nejsou VŠECHNA audio relé ověřeně vypnutá. `AudioController` serializuje vše
přes `asyncio.Lock` a hraje vždy jen jedna zóna.

Veřejné API: `MpvPlayer` (implementace v `mpv_player.py`), `AudioSelector`,
`AudioController`.
"""
from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING

from .config import AudioCfg
from .models import HwRef, Zone
from .mpv_player import MpvError, MpvPlayer

if TYPE_CHECKING:  # pragma: no cover — jen typ, modul píše jiná část programu
    from .io_devices import IoBus

__all__ = ["MpvPlayer", "MpvError", "AudioSelector", "AudioController"]

log = logging.getLogger("motogo.audio")


class AudioSelector:
    """Reléový výběr reproduktoru zóny (§8 sekvence přepnutí)."""

    def __init__(self, bus: "IoBus", zones: list[Zone], cfg: AudioCfg) -> None:
        self.bus = bus
        self.cfg = cfg
        self.active_zone: int | None = None
        # Druhá vrstva ochrany (první je validate_hardware): audio relé nikdy nesmí být cívka
        # zámku ani světla kterékoli zóny — selektor by ji držel trvale sepnutou (§12).
        reserved = {z.hw.lock for z in zones if z.hw.lock is not None} | {z.hw.light for z in zones if z.hw.light is not None}
        self._refs: dict[int, HwRef] = {}
        for z in zones:
            ref = z.hw.audio
            if ref is None:
                continue
            if ref in reserved:
                log.error("Zóna %s: audio relé %s[%s] koliduje se zámkem/světlem — reproduktor zóny vypnut",
                          z.number, ref.dev, ref.idx)
                continue
            self._refs[z.number] = ref

    def ref_for(self, zone: int) -> HwRef | None:
        return self._refs.get(zone)

    async def _all_off(self) -> bool:
        """Vypne (ověřeně) všechna audio relé; True jen když všechna potvrdila vypnutí.

        Relé jednoho modulu se vypínají postupně (klient má jeden request v letu),
        moduly navzájem paralelně — nedostupný modul tak nezdržuje ostatní.
        """
        groups: dict[str, list[tuple[int, HwRef]]] = {}
        for zone, ref in self._refs.items():
            groups.setdefault(ref.dev, []).append((zone, ref))
        results = await asyncio.gather(*(self._off_group(refs) for refs in groups.values()))
        return all(results)

    async def _off_group(self, refs: list[tuple[int, HwRef]]) -> bool:
        ok = True
        for zone, ref in refs:
            if not await self.bus.set(ref, False):
                log.error("Audio relé zóny %s (%s[%s]) se nepodařilo ověřeně vypnout",
                          zone, ref.dev, ref.idx)
                ok = False
        return ok

    async def select(self, zone: int) -> bool:
        """§8: (1) volající ztlumil → (2) vše off ověřeně → (3) settle → (4) relé zóny on
        ověřeně → (5) čekání on_ms. Při jakémkoli neúspěchu vše vypne a vrátí False."""
        ref = self._refs.get(zone)
        if ref is None:
            log.warning("Zóna %s nemá audio relé — reproduktor nelze vybrat", zone)
            self.active_zone = None
            return False
        # (2) všechna relé off; při neúspěchu jeden opakovaný pokus, jinak konec.
        if not await self._all_off() and not await self._all_off():
            self.active_zone = None
            return False
        # (3) klid po odpadnutí kontaktů
        await asyncio.sleep(self.cfg.selector_settle_ms / 1000.0)
        # (4) sepnout POUZE relé požadované zóny (ověřeně)
        if not await self.bus.set(ref, True):
            log.error("Audio relé zóny %s (%s[%s]) se nepodařilo sepnout — vypínám vše",
                      zone, ref.dev, ref.idx)
            await self._all_off()
            self.active_zone = None
            return False
        # (5) ustálení kontaktu před spuštěním zvuku
        await asyncio.sleep(self.cfg.selector_on_ms / 1000.0)
        self.active_zone = zone
        log.info("Audio selektor: zóna %s", zone)
        return True

    async def release(self) -> None:
        """Vypne všechna audio relé, žádná zóna není aktivní."""
        await self._all_off()
        self.active_zone = None


class AudioController:
    """Jediný vstupní bod pro hudbu — exkluzivita zón, fade in/out, bezpečné vypnutí."""

    def __init__(self, player: MpvPlayer, selector: AudioSelector, cfg: AudioCfg) -> None:
        self.player = player
        self.selector = selector
        self.cfg = cfg
        self.playing_zone: int | None = None
        self._lock = asyncio.Lock()
        self._fade_task: asyncio.Task | None = None
        self._generation = 0          # roste s každým play_zone — test_tone nesmí vypnout cizí hudbu

    @property
    def player_ok(self) -> bool:
        return bool(self.player.alive)

    def _start_fade(self, to: int, ms: int) -> None:
        """Fade na pozadí — přístupová sekvence nečeká na náběh hlasitosti (pulz zámku dřív)."""
        self._fade_task = asyncio.create_task(self.player.fade(to, ms), name="motogo.audio.fade")

    async def wait_fade(self) -> None:
        """Počká na doběh fade-in (servisní test, testy)."""
        task = self._fade_task
        if task is not None and not task.done():
            try:
                await task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass

    async def _cancel_fade(self) -> None:
        task, self._fade_task = self._fade_task, None
        if task is not None and not task.done():
            task.cancel()
            try:
                await task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass

    async def start(self) -> None:
        """Spustí přehrávač, načte playlist, hlasitost 0 a pauza (nic nehraje)."""
        try:
            await self.player.start()
            await self.player.load_playlist(self.cfg.shuffle)
            await self.player.set_volume(0)
            await self.player.pause()
        except Exception as exc:  # noqa: BLE001 — audio nesmí shodit controller
            log.error("Start audia selhal: %s", exc)
        if not self.player.alive:
            log.warning("Přehrávač neběží — hudba bude bez zvuku, selektor funguje dál")

    async def close(self) -> None:
        await self.all_off()
        try:
            await self.player.stop()
        except Exception as exc:  # noqa: BLE001
            log.warning("Ukončení přehrávače selhalo: %s", exc)

    async def play_zone(self, zone: int) -> bool:
        """Přehrává hudbu v zóně (jiná hrající zóna se nejprve korektně zastaví)."""
        async with self._lock:
            if self.playing_zone == zone and self.selector.active_zone == zone:
                return True
            if self.playing_zone is not None:
                await self._stop_locked(fade=True)
            await self._cancel_fade()
            ensure = getattr(self.player, "ensure_running", None)
            if ensure is not None and not self.player.alive:
                await ensure(self.cfg.shuffle)          # zaseknutý/padlý mpv → pokus o restart (rate-limit)
            # (1) ztlumit před přepínáním relé
            await self.player.set_volume(0)
            await self.player.pause()
            if not await self.selector.select(zone):
                self.playing_zone = None
                return False
            # (6) spustit hudbu, (7) plynule zesílit — fade běží na pozadí
            await self.player.play()
            self._start_fade(self.cfg.volume, self.cfg.fade_in_ms)
            self.playing_zone = zone
            self._generation += 1
            log.info("Hudba: zóna %s (hlasitost %s)", zone, self.cfg.volume)
            return True

    async def stop(self, fade: bool = True) -> None:
        """Zastaví hudbu: fade-out → pauza → settle → uvolnění selektoru."""
        async with self._lock:
            await self._stop_locked(fade)

    async def stop_zone(self, zone: int, fade: bool = True) -> bool:
        """Zastaví hudbu JEN pokud (pod zámkem) stále hraje v `zone` — čekající stop jedné zóny
        nesmí vypnout hudbu zóně, která reproduktor mezitím převzala (§13.7). Vrací, zda zastavila."""
        async with self._lock:
            if self.playing_zone != zone:
                return False
            await self._stop_locked(fade)
            return True

    async def reselect_if_playing(self, module: str) -> None:
        """Po obnově modulu (reinit = all_off) znovu sepne audio relé hrající zóny, pokud leží na něm."""
        async with self._lock:
            zone = self.playing_zone
            ref = self.selector.ref_for(zone) if zone is not None else None
            if ref is None or ref.dev != module:
                return
            log.warning("Audio: modul %s byl obnoven (all_off) — znovu vybírám reproduktor zóny %s", module, zone)
            await self._cancel_fade()
            await self.player.set_volume(0)
            await self.player.pause()
            if not await self.selector.select(zone):
                self.playing_zone = None
                return
            await self.player.play()
            self._start_fade(self.cfg.volume, self.cfg.fade_in_ms)

    async def _stop_locked(self, fade: bool) -> None:
        zone = self.playing_zone
        await self._cancel_fade()
        if fade and self.player.volume > 0:
            await self.player.fade(0, self.cfg.fade_out_ms)
        else:
            await self.player.set_volume(0)
        await self.player.pause()
        await asyncio.sleep(self.cfg.selector_settle_ms / 1000.0)
        await self.selector.release()
        self.playing_zone = None
        if zone is not None:
            log.info("Hudba: zóna %s zastavena", zone)

    async def all_off(self) -> None:
        """Okamžité bezpečné vypnutí bez fade (start programu, all_off příkaz)."""
        async with self._lock:
            await self._cancel_fade()
            try:
                await self.player.pause()
                await self.player.set_volume(0)
            except MpvError as exc:
                log.warning("all_off přehrávače: %s", exc)
            await self.selector.release()
            self.playing_zone = None

    async def test_tone(self, zone: int, seconds: int = 5) -> bool:
        """Servisní test reproduktoru zóny: přehrát `seconds` sekund a zastavit.

        Zastaví jen svoji hudbu — pokud mezitím reproduktor převzala jiná relace
        (`play_zone`), zákazníkovi hudba nezmizí.
        """
        count = getattr(self.player, "playlist_count", None)
        if not self.player.alive or (count is not None and int(count or 0) <= 0):
            log.warning("Audio test zóny %s: přehrávač neběží nebo je playlist prázdný (%s souborů)", zone, count)
            return False
        ok = await self.play_zone(zone)
        if ok:
            gen = self._generation
            await asyncio.sleep(max(0, int(seconds)))
            if self.playing_zone == zone and self._generation == gen:
                await self.stop(fade=True)
        return ok
