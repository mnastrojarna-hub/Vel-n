"""Diagnostika hudby (kontrakt §24): zvukové karty, výstupy → zóny, skladby pro každou zónu s reproduktorem.

`collect(ctrl, ast)` doplní report `software.audio` (ast = `audio.status()`), `protocol_items(a)` z něj staví
řádky protokolu. Zóna bez reproduktoru (dnes kóje 1–7, hraje jen šatna) NENÍ chyba — jen informace.
"""
from __future__ import annotations

import logging
from typing import Any

from .audio import zone_target

log = logging.getLogger("motogo.diag")

HINT_CARD = ("Zkontrolujte USB→jack adaptér (zapojený, jiný port). Velín → Hardware → Audio: zařízení výstupu "
             "„Automaticky“ (jediná USB karta) nebo konkrétní USB port; pak „Test výstupu“.")
HINT_MPV = "Přehrávač mpv neběží — Velín → Restart služby; přetrvává-li, zkontrolujte USB zvukovku a log služby."
HINT_MUSIC = "Velín → Hudba pobočky: nahrajte skladby s cílem této zóny nebo „Všechny“ (bez skladeb zóna po kódu mlčí)."


def collect(ctrl: Any, ast: dict) -> dict:
    """Karty, výstupy zón a počty skladeb (z knihovny) pro zóny s reproduktorem."""
    zone_out = {str(k): v for k, v in (ast.get("zone_out") or {}).items()}
    lib = getattr(ctrl, "music", None)
    speakers, no_speaker = [], []
    for z in ctrl.hardware.zones:
        out = zone_out.get(str(z.number))
        if out is None:
            no_speaker.append(z.display_name)
            continue
        tracks = None
        if lib is not None:
            try:
                tracks = len(lib.playlist_for(zone_target(z)) or [])
            except Exception as exc:  # noqa: BLE001
                log.warning("Diagnostika: playlist zóny %s: %s", z.number, exc)
        speakers.append({"zone": z.number, "label": z.display_name, "out": out, "tracks": tracks})
    return {"cards": list(ast.get("cards") or []), "speakers": speakers, "no_speaker": no_speaker,
            "music_enabled": bool(getattr(ctrl.hardware.audio, "music_enabled", True))}


def _card_txt(c: dict) -> str:
    port = f", USB port {c['usb_path']}" if c.get("usb_path") else ""
    return f"karta {c.get('index')} {c.get('name') or c.get('id')}{port}"


def protocol_items(a: dict, item: Any) -> list[dict]:
    """Řádky sekce Program a služby: mapa audia, karty, přehrávače, hudba zón."""
    rows: list[dict] = []
    players = a.get("players") or {}
    speakers, no_sp = a.get("speakers"), a.get("no_speaker") or []
    if speakers is None:            # starší report (bez collect) — původní dva řádky
        rows.append(item("software.mpv", "Přehrávač mpv", "ok" if a.get("player_ok") else "fail", a.get("device") or "výchozí zařízení",
                         "" if a.get("player_ok") else "Přehrávač mpv neběží — hudba a tón nefungují.", HINT_MPV))
        return rows
    mapping = "; ".join(f"{s['out']} → {s['label']}" for s in speakers) or "žádná zóna"
    extra = f"; {len(no_sp)} zón bez reproduktoru" if no_sp else ""
    rows.append(item("software.audio_map", "Hudba — zapojení", "ok" if speakers else "skip",
                     f"{a.get('mode')}, {len(players)} výstup(ů): {mapping}{extra}",
                     "" if speakers else "Žádná zóna nemá reproduktor (Velín → Hardware → Audio)."))
    cards = a.get("cards") or []
    usb = [c for c in cards if c.get("usb_path")]
    bad = {o: p for o, p in players.items() if p.get("present") is False}
    msg = "; ".join(f"výstup {o} ({p.get('device_cfg')}): {p.get('problem')}" for o, p in bad.items())
    rows.append(item("software.cards", "Zvukové karty (ALSA)", "fail" if bad else "ok" if usb or not speakers else "warn",
                     ", ".join(_card_txt(c) for c in cards) or "žádná", msg or ("" if usb or not speakers else "Není připojena USB zvuková karta."),
                     HINT_CARD))
    for out, p in players.items():
        alive = bool(p.get("alive"))
        rows.append(item(f"software.mpv.{out}", f"Přehrávač {out}", "ok" if alive else "fail",
                         f"{p.get('device_cfg') or 'výchozí'} → {p.get('device') or 'výchozí'}" + (", mono" if p.get("mono") else ""),
                         "" if alive else f"Přehrávač výstupu {out} neběží — hudba ani tón v něm nehraje.", HINT_MPV))
    if not a.get("music_enabled", True):
        rows.append(item("software.music", "Hudba po kódu", "skip", "vypnuta", "Hudba po zadání kódu je na pobočce vypnutá."))
        return rows
    for s in speakers:
        t = s.get("tracks")
        rows.append(item(f"software.music.{s['zone']}", f"Hudba — {s['label']}", "skip" if t is None else "ok" if t else "warn",
                         "?" if t is None else f"{t} skladeb", "" if t else f"{s['label']}: žádná skladba — po kódu nic nehraje.", HINT_MUSIC))
    return rows


__all__ = ["collect", "protocol_items"]
