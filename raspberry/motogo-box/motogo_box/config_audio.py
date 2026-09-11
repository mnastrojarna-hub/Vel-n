"""Validace audio části HW mapy (režim `selector` / `multi`) — doplněk `config.validate_hardware`.

Nesmí importovat `config` (cyklus) — pracuje s `HardwareConfig` duck-typed: `hw.audio`
(`AudioCfg`: `engine_mode`, `output_devices()`, `channel_map()`), `hw.zones`, `hw.devices`.

Blokující problémy (mapa se neuplatní): neznámý výstup, sdílený výstup, kanál bez výstupu,
relé kanálu na cívce, kterou už používá zóna (lock/light/audio…) nebo jiný kanál, nebo mimo rozsah
modulu (§12: relé „enable“ nesmí držet zámek pod napětím). `channel_limits` = `config.CHANNEL_LIMITS`
(předává volající — modul nesmí importovat `config`).
Nezávazná upozornění mají prefix „Upozornění:" — controller startuje, jen je zaloguje
(např. kanál venek v režimu selector, zóna bez výstupu v režimu multi).
"""
from __future__ import annotations

from typing import Any

AUDIO_MODES = ("selector", "multi")
WARN = "Upozornění:"


def zone_coils(hw: Any) -> dict[tuple[str, int], str]:
    """Cívky relé obsazené zónami: (dev, idx) → „zóna 1 (lock)“ (role lock/light/audio; contact je vstup)."""
    used: dict[tuple[str, int], str] = {}
    for z in hw.zones:
        for role in ("lock", "light", "audio"):
            ref = getattr(z.hw, role, None)
            if ref is not None:
                used.setdefault((ref.dev, ref.idx), f"zóna {z.number} ({role})")
    return used


def _validate_channel_relay(hw: Any, name: str, relay: Any, coils: dict[tuple[str, int], str],
                            channel_limits: dict | None) -> list[str]:
    """Relé „enable“ kanálu: Waveshare, index v rozsahu modulu, žádná kolize se zónou ani jiným kanálem."""
    dev = hw.devices.get(relay.dev)
    if dev is None:
        return [f"Kanál {name}: relé odkazuje na neznámé zařízení '{relay.dev}'."]
    if dev.type not in ("wav645", "wav617"):
        return [f"Kanál {name}: relé musí být Waveshare (je {dev.type})."]
    limit = (channel_limits or {}).get(dev.type, {}).get("coil")
    if relay.idx < 0 or (limit is not None and relay.idx >= limit):
        return [f"Kanál {name}: relé {relay.dev}[{relay.idx}] je mimo rozsah modulu {dev.type} (0–{(limit or 1) - 1})."]
    key = (relay.dev, relay.idx)
    if key in coils:
        return [f"Kanál {name}: relé {relay.dev}[{relay.idx}] už používá {coils[key]}."]
    coils[key] = f"kanál {name}"
    return []


def validate_audio(hw: Any, channel_limits: dict | None = None) -> list[str]:
    """Vrátí problémy audio konfigurace (prázdný = OK); viz docstring modulu."""
    cfg = hw.audio
    problems: list[str] = []
    raw_mode = str(getattr(cfg, "mode", "") or "").strip().lower()
    if raw_mode and raw_mode not in AUDIO_MODES:
        problems.append(f"{WARN} audio.mode '{raw_mode}' není selector ani multi — používám selector.")
    mode = cfg.engine_mode
    outputs = cfg.output_devices()
    channels = cfg.channel_map()
    if mode != "multi":
        if channels:
            names = ", ".join(sorted(channels))
            problems.append(f"{WARN} kanál {names} (venek) nelze v režimu selector — nastavte audio.mode: multi.")
        return problems
    if not outputs:
        problems.append("audio.mode multi: chybí audio.outputs (název → ALSA zařízení dle `aplay -L`).")
    for name, dev in outputs.items():
        if dev is None:
            problems.append(f"{WARN} audio.outputs.{name}: chybí device — mpv použije výchozí ALSA výstup.")
    used: dict[str, str] = {}          # výstup → kdo ho používá
    coils = zone_coils(hw)             # cívky relé obsazené zónami (+ postupně kanály)
    for z in hw.zones:
        out = z.hw.audio_out
        if not out:
            problems.append(f"{WARN} Zóna {z.number}: nemá audio výstup (audio.out) — v režimu multi v ní hudba nehraje.")
            continue
        if out not in outputs:
            problems.append(f"Zóna {z.number}: audio výstup '{out}' není v audio.outputs.")
            continue
        if out in used:
            problems.append(f"Zóna {z.number}: audio výstup '{out}' už používá {used[out]}.")
            continue
        used[out] = f"zóna {z.number}"
    for name, ch in channels.items():
        out = ch.get("out")
        if not out:
            problems.append(f"Kanál {name}: chybí výstup (audio.channels.{name}.out).")
        elif out not in outputs:
            problems.append(f"Kanál {name}: audio výstup '{out}' není v audio.outputs.")
        elif out in used:
            problems.append(f"Kanál {name}: audio výstup '{out}' už používá {used[out]}.")
        else:
            used[out] = f"kanál {name}"
        if ch.get("trigger") not in ("any",):
            problems.append(f"{WARN} Kanál {name}: trigger '{ch.get('trigger')}' není podporován (jen any).")
        relay = ch.get("relay")
        if relay is not None:
            problems.extend(_validate_channel_relay(hw, name, relay, coils, channel_limits))
    return problems
