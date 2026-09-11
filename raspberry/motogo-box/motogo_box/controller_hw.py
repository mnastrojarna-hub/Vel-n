"""Pomocné funkce `BoxController` pro hardwarovou konfiguraci: načtení lokální
mapy, sloučení s konfigurací z Velína, podpis pro detekci změn a vyhodnocení
dveřního kontaktu (`closed_level`).
"""
from __future__ import annotations

import json
import logging
import os
from typing import TYPE_CHECKING

from .config import HardwareConfig, LocalConfig, load_hardware_file, merge_hardware

if TYPE_CHECKING:  # pragma: no cover
    from .io_devices import IoBus
    from .zone import ZoneController

log = logging.getLogger("motogo.controller")

BUNDLED_HW_FILE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "brno-9zone.yaml")


def load_local_hw(local: LocalConfig) -> dict:
    """Lokální HW mapa (`paths.hardware_file`); když chybí, výchozí mapa z balíku."""
    path = local.paths.hardware_file
    for candidate in (path, BUNDLED_HW_FILE):
        try:
            if candidate and os.path.exists(candidate):
                if candidate != path:
                    log.warning("HW mapa %s chybí — používám výchozí %s", path, candidate)
                return load_hardware_file(candidate)
        except Exception as exc:  # noqa: BLE001
            log.error("Načtení HW mapy %s selhalo: %s", candidate, exc)
    return {}


def build_hardware(local_raw: dict, payload: dict | None) -> HardwareConfig:
    """Lokální mapa + remote `hardware` (pokud payload není legacy) + zóny z `doors`."""
    is_dict = isinstance(payload, dict)
    remote_hw = payload.get("hardware") if is_dict and not payload.get("legacy") else None
    doors = payload.get("doors") if is_dict else None
    doors = doors if isinstance(doors, list) else None
    hw = HardwareConfig.from_dict(merge_hardware(local_raw, remote_hw if isinstance(remote_hw, dict) else None), doors)
    remote_zones = bool(doors) and any(isinstance(d, dict) and d.get("hw") for d in doors)
    hw.source = "remote" if (remote_hw or remote_zones) else "local"
    return hw


def hw_signature(hw: HardwareConfig) -> str:
    """Podpis částí konfigurace, které se nedají změnit za běhu → nutná přestavba HW vrstvy.

    Zařízení, zóny, polling (timeouty/retry Modbus klientů), polarita kontaktů
    (`closed_level` — změna za běhu by invertovala stav dveří uprostřed relací),
    zvukové zařízení mpv (`--audio-device` se nastavuje při startu přehrávače) a relé
    venkovního světla (`outdoor.light` — staré relé musí přestavba bezpečně vypnout).
    """
    zones = [[z.hw.to_dict(), z.door_id] for z in hw.zones]
    outdoor_light = getattr(getattr(hw, "outdoor", None), "light", None)
    return json.dumps([hw.raw.get("devices"), zones, hw.raw.get("polling"), hw.contacts_closed_level,
                       hw.audio.device, str(outdoor_light)], sort_keys=True, default=str)


def door_value(io: "IoBus", hw: HardwareConfig, zc: "ZoneController", snapshot: dict) -> bool | None:
    """True = zavřeno dle `closed_level` (override zóny nebo globální); None = modul offline / bez kontaktu."""
    ref = zc.zone.hw.contact
    if ref is None:
        return None
    raw = io.input_value(snapshot, ref)
    if raw is None:
        return None
    level = zc.zone.hw.closed_level if zc.zone.hw.closed_level is not None else hw.contacts_closed_level
    return raw == bool(level)
