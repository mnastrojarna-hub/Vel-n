"""Venek (zóna bez dveří) v HW mapě — sekce `outdoor` (rozhodnutí uživatele 2026-09-11, kontrakt §2/§6).

Venek NENÍ řádek `branch_doors`: nemá zámek, kontakt, signalizaci ani dlaždici na displeji.
Je to top-level klíč `outdoor` v `branch_kiosk_config.hardware` (Velín) i v lokálním YAML:

    outdoor:
      zone: 9                             # popisné číslo (Velín, diagnostika, příkazy); nesmí kolidovat s dveřmi
      light: { dev: wav617b, coil: 0 }    # venkovní osvětlení = relé Waveshare
      audio: { out: out9 }                # jen multi: výstup venku (+ volitelně dev/coil = enable relé zesilovače)
      light_after_close_s: null           # doběh světla; null/chybí = timings.light_after_close_s

Legacy alias `audio.channels.outdoor {out, trigger: any, dev?, coil?}` zůstává podporovaný —
`apply_outdoor` ho doplní oběma směry, takže `build_audio`, `validate_audio`, `audio_signature`
i `AudioMulti.sync_channels` (hudba venku při jakémkoli kódu) fungují beze změny.

Nesmí importovat `config` (cyklus) — pracuje s `HardwareConfig` duck-typed (`hw.devices`,
`hw.zones`, `hw.outdoor`, `hw.raw`). Vzor: `config_audio.py`.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .models import HwRef

WARN = "Upozornění:"
CHANNEL = "outdoor"          # název kanálu bez dveří v `audio.channels` (legacy alias venku)


@dataclass
class OutdoorCfg:
    """Konfigurace venku; `present` = klíč `outdoor` v mapě existoval (i prázdný)."""

    zone: int | None = None
    light: HwRef | None = None          # relé Waveshare (venkovní osvětlení)
    audio: HwRef | None = None          # volitelné enable relé zesilovače (multi)
    audio_out: str | None = None        # výstup z audio.outputs (multi)
    light_after_close_s: int | None = None
    present: bool = False

    @property
    def configured(self) -> bool:
        return self.light is not None or bool(self.audio_out)

    @classmethod
    def from_dict(cls, d: Any) -> "OutdoorCfg":
        """Tolerantní jako `ZoneHw.from_dict`: None/ne-dict → `OutdoorCfg()`; vadné hodnoty se přeskočí."""
        if not isinstance(d, dict):
            return cls()
        audio = d.get("audio")
        out = audio.get("out") if isinstance(audio, dict) else None
        return cls(zone=_int(d.get("zone")), light=HwRef.from_dict(d.get("light"), "coil"),
                   audio=HwRef.from_dict(audio, "coil"),
                   audio_out=str(out).strip() or None if out not in (None, "") else None,
                   light_after_close_s=_int(d.get("light_after_close_s")), present=True)

    def to_dict(self) -> dict:
        """Kanonický tvar (bez None klíčů)."""
        out: dict[str, Any] = {}
        if self.zone is not None:
            out["zone"] = self.zone
        if self.light is not None:
            out["light"] = {"dev": self.light.dev, "coil": self.light.idx}
        audio: dict[str, Any] = {}
        if self.audio_out:
            audio["out"] = self.audio_out
        if self.audio is not None:
            audio.update({"dev": self.audio.dev, "coil": self.audio.idx})
        if audio:
            out["audio"] = audio
        if self.light_after_close_s is not None:
            out["light_after_close_s"] = self.light_after_close_s
        return out

    def light_ref(self) -> str | None:
        """Např. `wav617b[0]` (pro stav/diagnostiku); None bez světla."""
        return None if self.light is None else f"{self.light.dev}[{self.light.idx}]"


def _int(v: Any) -> int | None:
    try:
        return None if v is None or v == "" else int(v)
    except (TypeError, ValueError):
        return None


def legacy_channel(channels: Any) -> dict | None:
    """Položka `audio.channels.outdoor` (legacy alias), pokud existuje a je dict."""
    ch = channels.get(CHANNEL) if isinstance(channels, dict) else None
    return ch if isinstance(ch, dict) else None


def alias_conflict(outdoor: OutdoorCfg, legacy: dict | None) -> str | None:
    """Upozornění, když `outdoor.audio` i legacy `audio.channels.outdoor` existují a liší se."""
    if legacy is None or not outdoor.audio_out:
        return None
    legacy_cfg = OutdoorCfg.from_dict({"audio": legacy})
    if (legacy_cfg.audio_out, legacy_cfg.audio) == (outdoor.audio_out, outdoor.audio):
        return None
    return (f"{WARN} venek: audio.channels.outdoor ({legacy_cfg.audio_out}) se liší od outdoor.audio "
            f"({outdoor.audio_out}) — platí outdoor.audio.")


def apply_outdoor(audio_cfg: Any, outdoor: OutdoorCfg) -> list[str]:
    """Alias oběma směry mezi `outdoor.audio` a `audio.channels.outdoor` (mění `audio_cfg.channels`
    a `outdoor` na místě); vrací upozornění. `hw.raw` zůstává původní dict."""
    audio_cfg.channels = dict(audio_cfg.channels) if isinstance(audio_cfg.channels, dict) else {}   # kopie: vstupní dict se nemění
    legacy = legacy_channel(audio_cfg.channels)
    if not outdoor.audio_out:
        if legacy is not None:                       # legacy → kanonický (doplnit venek z kanálu)
            from_ch = OutdoorCfg.from_dict({"audio": legacy})
            outdoor.audio_out, outdoor.audio = from_ch.audio_out, from_ch.audio
        return []
    warning = alias_conflict(outdoor, legacy)
    ch: dict[str, Any] = {"out": outdoor.audio_out, "trigger": "any"}     # kanonický → kanál (build_audio, validace)
    if outdoor.audio is not None:
        ch.update({"dev": outdoor.audio.dev, "coil": outdoor.audio.idx})
    audio_cfg.channels[CHANNEL] = ch
    return [warning] if warning else []


def validate_outdoor(hw: Any, channel_limits: dict | None = None,
                     seen: dict[tuple[str, str, int], tuple[int, str]] | None = None) -> list[str]:
    """Problémy sekce `outdoor` (prázdný = OK). `seen` = kanály obsazené zónami z `validate_hardware`
    ({(dev, kind, idx): (zóna, role)}); bez něj se zóny projdou znovu. Blokující: neznámé zařízení,
    světlo mimo Waveshare, index mimo rozsah, kanál obsazený zónou, číslo zóny kolidující s dveřmi.
    Audio výstup v režimu selector hlídá `validate_audio` (kanál outdoor)."""
    o: OutdoorCfg = getattr(hw, "outdoor", None) or OutdoorCfg()
    problems: list[str] = []
    if seen is None:
        seen = {}
        for z in hw.zones:
            for role in ("lock", "light", "audio"):
                ref = getattr(z.hw, role, None)
                if ref is not None:
                    seen.setdefault((ref.dev, "coil", ref.idx), (z.number, role))
    if o.zone is not None and any(z.number == o.zone for z in hw.zones):
        problems.append(f"Venek: číslo zóny {o.zone} koliduje s dveřmi (zóna {o.zone}).")
    if o.light is not None:
        ref = o.light
        dev = hw.devices.get(ref.dev)
        if dev is None:
            problems.append(f"Venek: light odkazuje na neznámé zařízení '{ref.dev}'.")
        elif dev.type not in ("wav645", "wav617"):
            problems.append(f"Venek: light musí být relé Waveshare (je {dev.type}).")
        else:
            limit = (channel_limits or {}).get(dev.type, {}).get("coil")
            if ref.idx < 0 or (limit is not None and ref.idx >= limit):
                problems.append(f"Venek: light {ref.dev}[{ref.idx}] je mimo rozsah modulu {dev.type} (0–{(limit or 1) - 1}).")
            elif (ref.dev, "coil", ref.idx) in seen:
                zone, role = seen[(ref.dev, "coil", ref.idx)]
                problems.append(f"Venek: light {ref.dev}[{ref.idx}] už používá zóna {zone} ({role}).")
        if o.audio == ref:               # enable relé venku vs. zóny hlídá validate_audio (kanál outdoor)
            problems.append(f"Venek: light a audio sdílí {ref.dev}[{ref.idx}].")
    raw_audio = (getattr(hw, "raw", None) or {}).get("audio")
    warning = alias_conflict(o, legacy_channel(raw_audio.get("channels") if isinstance(raw_audio, dict) else None))
    if warning:
        problems.append(warning)
    if o.present and not o.configured:
        problems.append(f"{WARN} venek nemá světlo ani audio výstup.")
    return problems


__all__ = ["OutdoorCfg", "apply_outdoor", "validate_outdoor", "legacy_channel", "alias_conflict", "CHANNEL"]
