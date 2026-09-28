"""Zvukové karty jednotky (ALSA) a překlad `device` výstupu z Velína na zařízení mpv (kontrakt §6).

Hodnota `device` výstupu (`hardware.audio.outputs.<out>.device`, selector `audio.device`):
- `auto` — jediná USB zvuková karta (dnešní zapojení: 1 USB→jack adaptér pro šatnu),
- `usb:<port>` — USB karta na konkrétním fyzickém portu (`usb:1-1.2`; pro 9 stejných adaptérů — port je stálý,
  index karty ne), cestu portu ukazuje Velín ze `status.audio.cards`,
- cokoli jiného (`alsa/plughw:CARD=Device`, `default`…) — předá se mpv beze změny; `…CARD=X` se ověří v seznamu karet.
Výsledek pro mpv je `alsa/plughw:<index>,0` (plughw převzorkuje a mono rozkopíruje do L i R).
Bez terminálu a udev — jednotka to přeloží sama při stavbě audia a znovu každých 30 s (přepojení adaptéru).

`ensure_tone()` vygeneruje testovací tón (WAV, stdlib), aby šel reproduktor vyzkoušet i bez nahrané hudby.
"""
from __future__ import annotations

import logging
import math
import os
import re
import struct
import wave

log = logging.getLogger("motogo.audio")

AUTO = "auto"
USB_PREFIX = "usb:"
TONE_NAME = "motogo-test-tone.wav"
_TONE_DIRS = ("/run/motogo", "/tmp")


def _read(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def _usb_path(root: str, index: int) -> str | None:
    """Cesta USB portu karty (`1-1.2`) z `/sys/class/sound/cardN/device` (→ …/1-1.2/1-1.2:1.0)."""
    link = os.path.join(root, "sys/class/sound", f"card{index}", "device")
    try:
        real = os.path.realpath(link)
    except OSError:
        return None
    if "/usb" not in real:
        return None
    parts = [p for p in real.split("/") if re.fullmatch(r"\d+-[\d.]+", p)]
    return parts[-1] if parts else None


def list_cards(root: str = "/") -> list[dict]:
    """Zvukové karty z `/proc/asound/cards`: [{index, id, name, usb_path, playback}]."""
    text = _read(os.path.join(root, "proc/asound/cards"))
    cards: list[dict] = []
    for m in re.finditer(r"^\s*(\d+)\s+\[(\S+)\s*\]:\s*([^\n]*)\n\s*([^\n]*)", text, re.M):
        idx = int(m.group(1))
        pcm_dir = os.path.join(root, "proc/asound", f"card{idx}")
        try:
            playback = any(n.startswith("pcm") and n.endswith("p") for n in os.listdir(pcm_dir))
        except OSError:
            playback = True
        cards.append({"index": idx, "id": m.group(2), "name": m.group(3).split(" - ", 1)[-1].strip()[:80],
                      "usb_path": _usb_path(root, idx), "playback": playback})
    return cards


def _usb_cards(cards: list[dict]) -> list[dict]:
    return [c for c in cards if c.get("usb_path") and c.get("playback")]


def resolve(device: str | None, cards: list[dict]) -> tuple[str | None, str | None]:
    """(zařízení pro mpv, problém). Zařízení None + problém = karta chybí (mpv by hrálo do HDMI/jinam);
    (None, None) = výchozí výstup záměrně (device prázdné)."""
    dev = str(device or "").strip()
    if not dev:
        return None, None
    if dev.lower() == AUTO:
        usb = _usb_cards(cards)
        if len(usb) == 1:
            return f"alsa/plughw:{usb[0]['index']},0", None
        if not usb:
            return None, "žádná USB zvuková karta (adaptér nezapojen?)"
        ports = ", ".join(str(c["usb_path"]) for c in usb)
        return None, f"USB zvukových karet je {len(usb)} ({ports}) — u výstupu zvolte port"
    if dev.lower().startswith(USB_PREFIX):
        port = dev[len(USB_PREFIX):].strip()
        for c in _usb_cards(cards):
            if c["usb_path"] == port:
                return f"alsa/plughw:{c['index']},0", None
        return None, f"na USB portu {port} není zvuková karta"
    m = re.search(r"CARD=([^,\s]+)", dev)
    if m and cards and not any(c["id"] == m.group(1) for c in cards):
        return None, f"karta {m.group(1)} není připojena"
    return dev, None


def ensure_tone(dirs: tuple[str, ...] = _TONE_DIRS, seconds: float = 3.0, rate: int = 44100) -> str | None:
    """Testovací tón (střídavě 440/660 Hz po 0,5 s, −12 dBFS, mono WAV); vrací cestu nebo None."""
    for d in dirs:
        path = os.path.join(d, TONE_NAME)
        if os.path.isfile(path) and os.path.getsize(path) > 1000:
            return path
        try:
            os.makedirs(d, exist_ok=True)
            amp = int(32767 * 10 ** (-12 / 20))
            frames = bytearray()
            for i in range(int(seconds * rate)):
                t = i / rate
                freq = 440.0 if int(t * 2) % 2 == 0 else 660.0
                env = min(1.0, (t % 0.5) * 50, (0.5 - t % 0.5) * 50)   # bez lupnutí na hranách
                frames += struct.pack("<h", int(amp * env * math.sin(2 * math.pi * freq * t)))
            tmp = path + ".tmp"
            with wave.open(tmp, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(rate)
                w.writeframes(bytes(frames))
            os.replace(tmp, path)
            return path
        except OSError as exc:
            log.debug("Testovací tón do %s nelze zapsat: %s", d, exc)
    log.warning("Testovací tón nelze vytvořit")
    return None


__all__ = ["list_cards", "resolve", "ensure_tone", "AUTO", "USB_PREFIX"]
