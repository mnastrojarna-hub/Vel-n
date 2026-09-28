"""Sestavení audio enginu podle HW mapy (kontrakt §6): `selector` (jeden mpv + relé) nebo
`multi` (mpv + výstup na každou místnost, `audio_multi.AudioMulti`).

`build_audio(hw, local, io, library)` vybere engine podle `hw.audio.mode` a přeloží `device` výstupů
(`auto` / `usb:<port>`, `audio_devices`); `audio_signature(cfg)` = část konfigurace vyžadující přestavbu
(nové mpv procesy), `resolved_devices(cfg)` = vyřešené karty (přepojení adaptéru → `audio_hotplug`); `make_music_library(...)` vytvoří knihovnu hudby
(import hlídaný — bez `music_sync` jede legacy playlist z adresáře).
"""
from __future__ import annotations

import logging
from typing import Any

from . import audio_devices
from .audio import AudioController, AudioSelector, zone_target
from .audio_multi import AudioMulti, Key
from .config import AudioCfg, HardwareConfig, LocalConfig
from .models import HwRef
from .mpv_player import MpvPlayer

log = logging.getLogger("motogo.audio")


NULL_DEVICE = "alsa/null"      # karta výstupu chybí → ticho (nikdy ne do HDMI / cizí zóny)


def _player(socket: str, music_dir: str, device: str | None, mono: bool, cards: list[dict], name: str) -> MpvPlayer:
    """mpv s vyřešeným zařízením (`auto` / `usb:<port>` → `alsa/plughw:N,0`); chybějící karta = `alsa/null`."""
    resolved, problem = audio_devices.resolve(device, cards)
    if problem:
        log.error("Audio výstup %s (%s): %s — výstup bude potichu", name, device, problem)
    player = MpvPlayer(socket, music_dir, NULL_DEVICE if problem else resolved, name=name, mono=mono)
    player.device_cfg, player.problem = device, problem      # pro status / diagnostiku / Velín
    return player


def resolved_devices(cfg: AudioCfg, cards: list[dict] | None = None) -> dict:
    """Vyřešená zařízení výstupů ({out: alsa…|None}) — změna (přepojení adaptéru) = přestavba audia."""
    cards = audio_devices.list_cards() if cards is None else cards
    if cfg.engine_mode != "multi":
        return {"mpv": audio_devices.resolve(cfg.device, cards)[0]}
    return {out: audio_devices.resolve(o["device"], cards)[0] for out, o in cfg.output_opts().items()}


def build_audio(hw: HardwareConfig, local: LocalConfig, io: Any, library: Any = None,
                cards: list[dict] | None = None):
    """Engine podle `hw.audio.mode`: `AudioMulti` (výstupy) nebo `AudioController` (selektor)."""
    cfg = hw.audio
    cards = audio_devices.list_cards() if cards is None else cards
    if cfg.engine_mode != "multi":
        player = _player(local.paths.mpv_socket, local.paths.music_dir, cfg.device, bool(cfg.mono), cards, "mpv")
        engine = AudioController(player, AudioSelector(io, hw.zones, cfg), cfg, library, hw.zones)
        engine.cards, engine.resolved = cards, resolved_devices(cfg, cards)
        return engine
    outputs = cfg.output_opts()
    players = {out: _player(f"{local.paths.mpv_socket}.{out}", local.paths.music_dir, o["device"], o["mono"], cards, out)
               for out, o in outputs.items()}
    zone_out = {z.number: z.hw.audio_out for z in hw.zones if z.hw.audio_out in outputs}
    relays: dict[Key, HwRef] = {z.number: z.hw.audio for z in hw.zones if z.hw.audio is not None and z.number in zone_out}
    channel_out: dict[str, str] = {}
    for name, ch in cfg.channel_map().items():
        if ch.get("out") in outputs:
            channel_out[name] = ch["out"]
            if ch.get("relay") is not None:
                relays[name] = ch["relay"]
    relays = _drop_reserved_relays(relays, hw.zones, getattr(getattr(hw, "outdoor", None), "light", None))
    engine = AudioMulti(players, zone_out, channel_out, relays, cfg, library, bus=io,
                        zone_targets={z.number: zone_target(z) for z in hw.zones}, timings=hw.timings)
    engine.cards, engine.resolved = cards, resolved_devices(cfg, cards)
    return engine


def _drop_reserved_relays(relays: dict[Key, HwRef], zones: list, outdoor_light: HwRef | None = None) -> dict[Key, HwRef]:
    """Druhá vrstva ochrany (první je validate_hardware, zrcadlí `AudioSelector`): relé „enable“
    nikdy nesmí být cívka zámku ani světla kterékoli zóny ani venkovního světla — hrálo by pod ním
    po celou hudbu (§12)."""
    reserved = {z.hw.lock for z in zones if z.hw.lock is not None} | {z.hw.light for z in zones if z.hw.light is not None}
    if outdoor_light is not None:
        reserved.add(outdoor_light)
    kept: dict[Key, HwRef] = {}
    for key, ref in relays.items():
        if ref in reserved:
            log.error("Audio relé %s: %s[%s] koliduje se zámkem/světlem — relé kanálu vypnuto",
                      f"zóny {key}" if isinstance(key, int) else f"kanálu {key}", ref.dev, ref.idx)
            continue
        kept[key] = ref
    return kept


def audio_signature(cfg: AudioCfg) -> list:
    """Část audio konfigurace, která vyžaduje přestavbu (nové mpv procesy): režim, výstupy, kanály."""
    return [cfg.engine_mode, cfg.device, bool(cfg.mono), cfg.output_opts(),
            {n: [c.get("out"), c.get("trigger"), str(c.get("relay"))] for n, c in cfg.channel_map().items()}]


def make_music_library(storage: Any, music_dir: str, supabase_url: str, on_changed: Any) -> Any:
    """`music_sync.MusicLibrary` (import hlídaný — bez modulu jede legacy playlist z `music_dir`)."""
    try:
        from .music_sync import MusicLibrary
    except Exception as exc:  # noqa: BLE001
        log.warning("Knihovna hudby není dostupná (%s) — hraje legacy playlist z adresáře", exc)
        return None
    try:
        return MusicLibrary(storage, music_dir, supabase_url, on_changed=on_changed)
    except Exception as exc:  # noqa: BLE001
        log.error("Knihovnu hudby nelze vytvořit: %s", exc)
        return None


__all__ = ["build_audio", "audio_signature", "resolved_devices", "make_music_library", "NULL_DEVICE"]
