"""Audio: mpv přehrávač + reléový selektor reproduktorů (kontrakt §6, spec §8).

Zesilovač je mono a SPK+ jde přes 9 samostatných NO relé — SOUČASNĚ smí být
sepnuté nejvýše jedno audio relé (paralelní reproduktory by snížily impedanci
a poškodily zesilovač). `AudioSelector` proto nikdy nesepne relé zóny, dokud
nejsou VŠECHNA audio relé ověřeně vypnutá. `AudioController` serializuje vše
přes `asyncio.Lock` a hraje vždy jen jedna zóna.

Veřejné API: `MpvPlayer` (implementace v `mpv_player.py`), `AudioSelector`,
`AudioController`. Režim `multi` (výstup + mpv na každou místnost) je v `audio_multi.py`;
oba enginy sdílejí stejné rozhraní (`is_playing`, `playing_zones`, `channels_playing`,
`sync_channels`, `play_channel`/`stop_channel`/`test_channel` — selector vrací False, viz
`audio_channels.py`, `reload_playlists`, `status`). Playlist cíle zóny dodává knihovna
hudby (`music_sync.MusicLibrary.playlist_for(target)`, cíl = `door:<uuid>` | `zone:<n>`);
bez knihovny hraje legacy playlist = všechny soubory v `music_dir`.
"""
from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING, Any

from .audio_channels import SelectorChannelStubs
from .config import AudioCfg
from .models import HwRef, Zone
from .mpv_player import MpvError, MpvPlayer

if TYPE_CHECKING:  # pragma: no cover — jen typ, modul píše jiná část programu
    from .io_devices import IoBus

__all__ = ["MpvPlayer", "MpvError", "AudioSelector", "AudioController", "zone_target", "library_status"]

log = logging.getLogger("motogo.audio")


def zone_target(zone: Zone) -> str:
    """Cíl hudby zóny: `door:<uuid>` (dveře z Velína) nebo `zone:<n>` (lokální mapa)."""
    return f"door:{zone.door_id}" if zone.door_id else f"zone:{zone.number}"


def library_status(library: Any) -> dict | None:
    """`library.status()` bez výjimek (knihovna je volitelná)."""
    if library is None:
        return None
    try:
        return dict(library.status() or {})
    except Exception as exc:  # noqa: BLE001
        log.warning("Stav knihovny hudby nelze zjistit: %s", exc)
        return None


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


class AudioController(SelectorChannelStubs):
    """Jediný vstupní bod pro hudbu — exkluzivita zón, fade in/out, bezpečné vypnutí."""

    mode = "selector"

    def __init__(self, player: MpvPlayer, selector: AudioSelector, cfg: AudioCfg,
                 library: Any = None, zones: list[Zone] | None = None) -> None:
        self.player = player
        self.selector = selector
        self.cfg = cfg
        self.library = library        # MusicLibrary (volitelná) — playlisty cílů
        self.targets: dict[int, str] = {z.number: zone_target(z) for z in (zones or [])}
        self.playing_zone: int | None = None
        self._loaded_target: str | None = None   # cíl právě načteného playlistu (None = legacy/dirty)
        self._lock = asyncio.Lock()
        self._fade_task: asyncio.Task | None = None
        self._generation = 0          # roste s každým play_zone — test_tone nesmí vypnout cizí hudbu

    @property
    def player_ok(self) -> bool:
        return bool(self.player.alive)

    # ─── společné rozhraní enginů ────────────────────────────────────────────
    def is_playing(self, zone: int) -> bool:
        return self.playing_zone == zone

    @property
    def playing_zones(self) -> list[int]:
        return [self.playing_zone] if self.playing_zone is not None else []

    def update_cfg(self, cfg: AudioCfg, timings: Any = None) -> None:
        self.cfg = self.selector.cfg = cfg

    async def reload_playlists(self) -> None:
        """Knihovna hudby se změnila: hrající zónu nerušit, playlist se vymění při dalším play_zone."""
        async with self._lock:
            self._loaded_target = None
            if self.playing_zone is None:
                await self._load_target(self.targets.get(1) if len(self.targets) == 1 else "all")

    def status(self) -> dict:
        return {"mode": self.mode, "playing_zone": self.playing_zone, "playing_zones": self.playing_zones,
                "channels": [], "player_ok": self.player_ok,
                "playlist_count": int(getattr(self.player, "playlist_count", 0) or 0),
                "device": getattr(self.player, "device", None),
                "players": {getattr(self.player, "name", "mpv"): {
                    "alive": self.player_ok, "playlist_count": int(getattr(self.player, "playlist_count", 0) or 0),
                    "device": getattr(self.player, "device", None)}},
                "library": library_status(self.library)}

    def _target_of(self, zone: int) -> str:
        return self.targets.get(zone) or f"zone:{zone}"

    def _files_for(self, target: str) -> list[str] | None:
        """Playlist cíle z knihovny; None = knihovna není (legacy scan adresáře)."""
        if self.library is None:
            return None
        try:
            return [str(f) for f in (self.library.playlist_for(target) or [])]
        except Exception as exc:  # noqa: BLE001
            log.warning("Playlist cíle %s nelze načíst: %s", target, exc)
            return []

    async def _load_target(self, target: str) -> None:
        """Načte do mpv playlist cíle (jen když se liší od právě načteného; bez knihovny legacy 1×)."""
        files = self._files_for(target)
        key = target if files is not None else "legacy"
        if key == self._loaded_target:
            return
        if files is None:
            await self.player.load_playlist(self.cfg.shuffle)
        else:
            await self.player.load_files(files, self.cfg.shuffle)
        self._loaded_target = key

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
            await self._load_target("all")
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
            # (1) ztlumit před přepínáním relé, playlist cíle zóny (door:<id> / zone:<n> → all)
            await self.player.set_volume(0)
            await self.player.pause()
            await self._load_target(self._target_of(zone))
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
        files = self._files_for(self._target_of(zone))
        if files is not None:
            count = len(files)
        if not self.player.alive or (count is not None and int(count or 0) <= 0):
            log.warning("Audio test zóny %s: přehrávač neběží nebo je playlist prázdný (%s souborů)", zone, count)
            return False
        ok = await self.play_zone(zone)
        if ok:
            gen = self._generation
            try:
                await asyncio.sleep(max(0, int(seconds)))
            finally:
                # i při zrušení (timeout diagnostiky) tón nesmí hrát dál — zastavit jen svoji hudbu
                if self.playing_zone == zone and self._generation == gen:
                    await self.stop(fade=True)
        return ok
