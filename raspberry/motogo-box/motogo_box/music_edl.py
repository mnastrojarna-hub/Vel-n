"""Zkrácení skladby hudby pobočky na konci (2026-10-06, zadání majitele „skladbu zkrať na 4:02“; kontrakt §3).

Velín ukládá `branch_music_tracks.end_s` (s, NULL = celá skladba), `kiosk_sync_config` ho posílá v `music.tracks[].end_s`.
Stažený soubor zůstává beze změny (žádné nové stahování — `end_s` NENÍ součástí otisku obsahu); jednotka vedle něj
vytvoří EDL `<tracks_dir>/<id>.edl` a mpv přehraje jen 0 … end_s jako samostatnou skladbu (dokola, `seek 0` i
`playlist-pos` fungují jako u běžného souboru). EDL `# mpv EDL v0` umí i mpv 0.35 (Debian bookworm na RPi).
"""
from __future__ import annotations

import logging
import math
import os
from typing import Any

log = logging.getLogger("motogo.music")

EDL_EXT = ".edl"
END_S_MAX = 7200.0     # stejně jako CHECK branch_music_tracks_end_s_check (0 < end_s <= 7200)
EDL_HEADER = "# mpv EDL v0\n"


def normalize_end_s(value: Any) -> float | None:
    """`music.tracks[].end_s` → float v (0, 7200] s; cokoli jiného (NULL, text, 0, záporné, NaN, bool) → None."""
    if value is None or isinstance(value, bool):
        return None
    try:
        f = float(value)
    except (TypeError, ValueError):
        return None
    return f if math.isfinite(f) and 0 < f <= END_S_MAX else None


def edl_path(tracks_dir: str, tid: str) -> str:
    return os.path.join(tracks_dir, f"{tid}{EDL_EXT}")


def _seconds(x: float) -> str:
    """242.0 → "242", 241.5 → "241.5" (ms přesnost, bez exponentu)."""
    return f"{float(x):.3f}".rstrip("0").rstrip(".")


def edl_content(media: str, end_s: float) -> str:
    """EDL s jediným úsekem 0 … end_s; cesta absolutní, délka v bajtech UTF-8 (`%n%` — čárky/mezery v názvu nevadí)."""
    path = os.path.abspath(media)
    return f"{EDL_HEADER}%{len(path.encode('utf-8'))}%{path},0,{_seconds(end_s)}\n"


def _remove(path: str) -> bool:
    try:
        if os.path.isfile(path):
            os.remove(path)
            return True
    except OSError as exc:
        log.warning("Smazání %s selhalo: %s", path, exc)
    return False


def write_edl(path: str, content: str) -> bool:
    """Zapíše EDL atomicky (`.part` → `os.replace`); stejný obsah nepřepisuje. Chyba zápisu → starý EDL smazat (přehrávač
    pak vezme celou skladbu, nikdy zastaralý konec). Vrací True, když se na disku něco změnilo (zapsáno / smazáno)."""
    try:
        with open(path, encoding="utf-8") as fh:
            if fh.read() == content:
                return False
    except OSError:
        pass
    part = path + ".part"
    try:
        with open(part, "w", encoding="utf-8") as fh:
            fh.write(content)
        os.replace(part, path)
        return True
    except OSError as exc:
        log.warning("EDL %s nelze zapsat (%s) — skladba se přehraje celá", path, exc)
        _remove(part)
        return _remove(path)


def sync_edls(index: dict[str, dict], tracks_dir: str) -> bool:
    """Srovná EDL se záznamy indexu: `end_s` → (pře)psat EDL, bez `end_s` → smazat. Vrací True při jakékoli změně
    na disku (přehrávače pak musí znovu načíst playlisty — `MusicLibrary.on_changed`)."""
    changed = False
    for tid, e in index.items():
        path, end_s, media = edl_path(tracks_dir, tid), normalize_end_s(e.get("end_s")), e.get("file")
        if media and os.path.abspath(str(media)) == os.path.abspath(path):
            continue                       # soubor s příponou .edl = sama skladba — nikdy nepřepsat ani nesmazat
        if end_s is not None and media:
            changed = write_edl(path, edl_content(str(media), end_s)) or changed
        else:
            changed = _remove(path) or changed
    return changed


def keep_paths(index: dict[str, dict], tracks_dir: str) -> set[str]:
    """EDL, které úklid `tracks/` nesmí smazat (skladby indexu s platným `end_s`)."""
    return {edl_path(tracks_dir, tid) for tid, e in index.items() if normalize_end_s(e.get("end_s")) is not None}


def play_path(tracks_dir: str, tid: str, entry: dict) -> str:
    """Soubor pro mpv: EDL zkrácené skladby (existuje-li), jinak stažený soubor."""
    if normalize_end_s(entry.get("end_s")) is not None:
        edl = edl_path(tracks_dir, tid)
        if os.path.isfile(edl):
            return edl
    return str(entry["file"])


__all__ = ["normalize_end_s", "edl_path", "edl_content", "write_edl", "sync_edls", "keep_paths", "play_path",
           "EDL_EXT", "END_S_MAX"]
