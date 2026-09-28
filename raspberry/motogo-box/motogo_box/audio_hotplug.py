"""Přepojení / pozdní nalezení USB zvukové karty (kontrakt §6): á `status_report_s` (výchozí 30 s) se znovu přeloží
`device` výstupů (`auto` / `usb:<port>` → `alsa/plughw:N,0`, `audio_build.resolved_devices`); když se výsledek
liší od stavby enginu (adaptér přepojen do jiného portu, karta nalezena až po startu, index se změnil),
přestaví se JEN audio (nové mpv) — IO, zóny a relace běží dál. Hrající hudbu nepřeruší, pokud karty jen přibyly
(počká na ticho); zmizelá karta se přestaví hned (hudba do ní stejně nehraje).
"""
from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any

from . import audio_devices
from .audio_build import build_audio, resolved_devices

if TYPE_CHECKING:  # pragma: no cover
    from .controller import BoxController

log = logging.getLogger("motogo.audio")


async def recheck(ctrl: "BoxController", cards: list[dict] | None = None) -> bool:
    """Vrátí True, když se audio přestavělo."""
    audio = ctrl.audio
    if audio is None:
        return False
    cards = audio_devices.list_cards() if cards is None else cards
    new = resolved_devices(ctrl.hardware.audio, cards, fallback=bool(getattr(audio, "fallback", False)))
    old = getattr(audio, "resolved", None)
    audio.cards = cards
    if old is None or new == old:
        return False
    lost = any(old.get(k) and not new.get(k) for k in old)
    if not lost and (audio.playing_zones or audio.channels_playing):
        return False                        # nová karta počká, až dohraje hudba
    log.warning("Zvukové karty se změnily (%s → %s) — přestavuji audio", old, new)
    await rebuild_audio(ctrl, cards)
    return True


async def rebuild_audio(ctrl: "BoxController", cards: list[dict]) -> Any:
    """Nový engine se stejnou HW mapou; zóny a venek dostanou nový engine, starý se ukončí."""
    old = ctrl.audio
    try:
        await old.close()
    except Exception:  # noqa: BLE001
        log.exception("Ukončení starého audia selhalo")
    new = build_audio(ctrl.hardware, ctrl.local, ctrl.io, ctrl.music, cards)
    await new.start()
    await new.all_off()
    ctrl.audio = new
    if ctrl.outdoor is not None:
        ctrl.outdoor.audio = new
    for zc in ctrl.zones.values():
        zc.audio = new
    return new


__all__ = ["recheck", "rebuild_audio"]
