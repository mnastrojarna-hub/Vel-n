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
    """Lokální mapa + remote `hardware` (pokud payload není legacy) + zóny z `doors`.

    Venek z LOKÁLNÍ šablony platí jen s lokálními zónami: když zóny přijdou z Velína (`doors[].hw`)
    a remote `hardware` sekci `outdoor` nenese (`{}` = Velín bez HW mapy, legacy payload), lokální
    `outdoor` se zahodí — jinak by šablonové světlo (wav617b R1) mohlo sdílet cívku se starou zónou 9
    z DB a zóna i venek by ji za běhu přepínaly (validace to hlásí, start ji ale neblokuje).
    """
    is_dict = isinstance(payload, dict)
    remote_hw = payload.get("hardware") if is_dict and not payload.get("legacy") else None
    remote_hw_d = remote_hw if isinstance(remote_hw, dict) else None
    doors = payload.get("doors") if is_dict else None
    doors = doors if isinstance(doors, list) else None
    remote_zones = bool(doors) and any(isinstance(d, dict) and d.get("hw") for d in doors)
    merged = merge_hardware(local_raw, remote_hw_d)
    if remote_zones and "outdoor" in merged and not isinstance((remote_hw_d or {}).get("outdoor"), dict):
        log.debug("Venek z lokální šablony se nepoužije — zóny jsou z Velína bez sekce outdoor")
        merged.pop("outdoor", None)
    hw = HardwareConfig.from_dict(merged, doors)
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
