"""MotoGo Box — řídicí program autonomní pobočky (Raspberry Pi 5)."""
from __future__ import annotations

import os
import subprocess

__version__ = "1.0.0"


def full_version() -> str:
    """Verze + krátký git hash (pokud běžíme z git checkoutu) — hlásí se do Velína."""
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    try:
        out = subprocess.run(["git", "-C", here, "rev-parse", "--short", "HEAD"],
                             capture_output=True, text=True, timeout=3)
        h = out.stdout.strip()
        return f"{__version__}+{h}" if out.returncode == 0 and h else __version__
    except Exception:
        return __version__
