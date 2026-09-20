"""Servisní terminál na displeji pobočky (kontrakt §27).

Po zadání servisního kódu s účelem `diagnostics` nabídne displej vedle diagnostiky i terminál:

* **připravené příkazy** (`PRESETS`) — vždy dostupné, spouští se BEZ shellu (`exec` s pevným argv),
  takže z nich nejde nic „vyrobit“; pokrývají to, co se u skříně řeší nejčastěji (síť, LTE, služby, logy),
* **volné psaní** — po zadání **servisního hesla** (z Velína, `branch_service_codes`), nebo když ho pro
  pobočku odemkne Velín příkazem `shell_unlock` (výchozí 30 min, pak se samo zamkne). Běží jako `bash -c`
  pod uživatelem `motogo` — tedy BEZ rootu; jediné, co smí přes `sudo`, je pevný seznam v
  `systemd/motogo-sudoers`. Root shell z displeje udělat nejde.

**Proč servisní heslo stačí samo (rozhodnutí uživatele 2026-09-20):** terminál je potřeba hlavně tehdy,
když je pobočka OFFLINE — a tam žádný příkaz z Velína nedorazí (Pohořelice 2026-09-19). Servisní heslo
se ověří i offline (HMAC cache, nejvýš 3 dny bez synchronizace) a kdo ho zná, stejně už umí servisním
panelem otevřít každou kóji — shell bez rootu tedy jeho oprávnění nerozšiřuje. Cesta přes `shell_unlock`
zůstává pro případ, kdy má technik u sebe jen diagnostický kód (ten dveře neotevírá) a pobočka je online.

Každé spuštění (i odmítnuté) jde do `kiosk_logs` přes `EventKind.SHELL` — ve Velíně je tedy vidět,
kdo co na pobočce pouštěl. Výstup se ořezává (`OUTPUT_LIMIT`), aby nezahltil displej ani tabulku logů.
"""
from __future__ import annotations

import asyncio
import logging
import secrets
import time
from typing import TYPE_CHECKING, Any

from .models import Event, EventKind

if TYPE_CHECKING:  # pragma: no cover
    from .controller import BoxController

log = logging.getLogger("motogo.shell")

FREE_DEFAULT_MINUTES = 30
FREE_MIN_MINUTES = 5
FREE_MAX_MINUTES = 240
CMD_TIMEOUT_S = 25.0
OUTPUT_LIMIT = 8000          # znaků výstupu na displej i do logu
LOG_OUTPUT_LIMIT = 2000      # do kiosk_logs stačí začátek (detail má strop 64 KiB na RPC)
ARG_MAX = 64
TOKEN_MINUTES = 20           # platnost tokenu terminálu (zadání kódu na displeji)

# Připravené příkazy: `arg` = doplní se hodnota z displeje (jediný parametr, validuje `_arg_ok`).
# Vše je buď čtení stavu, nebo akce, kterou stejně umí Velín — nic, co by otevřelo kóji.
PRESETS: tuple[dict, ...] = (
    {"id": "net.addr", "group": "Síť", "label": "Adresy rozhraní", "argv": ("ip", "-br", "addr")},
    {"id": "net.route", "group": "Síť", "label": "Směrovací tabulka", "argv": ("ip", "route")},
    {"id": "net.dev", "group": "Síť", "label": "Stav zařízení (nmcli)", "argv": ("nmcli", "dev", "status")},
    {"id": "net.con", "group": "Síť", "label": "Profily (nmcli)",
     "argv": ("nmcli", "-f", "NAME,DEVICE,STATE", "con", "show")},
    {"id": "net.lan_up", "group": "Síť", "label": "Nahodit I/O síť (motogo-lan)",
     "argv": ("sudo", "-n", "nmcli", "-w", "20", "con", "up", "motogo-lan")},
    {"id": "net.ping", "group": "Síť", "label": "Ping na adresu", "arg": "IP adresa modulu",
     "argv": ("ping", "-c", "3", "-W", "2", "{arg}")},
    {"id": "net.arp", "group": "Síť", "label": "Sousedé na LAN (ARP)", "argv": ("ip", "neigh")},
    {"id": "lte.modem", "group": "LTE", "label": "Stav modemu", "argv": ("mmcli", "-m", "any")},
    {"id": "lte.list", "group": "LTE", "label": "Seznam modemů", "argv": ("mmcli", "-L")},
    {"id": "lte.up", "group": "LTE", "label": "Nahodit LTE (motogo-lte)",
     "argv": ("sudo", "-n", "nmcli", "-w", "30", "con", "up", "motogo-lte")},
    {"id": "lte.usbreset", "group": "LTE", "label": "USB reset modemu",
     "argv": ("sudo", "-n", "/usr/local/sbin/motogo-usbreset"), "danger": True},
    {"id": "sys.failed", "group": "Systém", "label": "Selhané jednotky", "argv": ("systemctl", "--failed")},
    {"id": "sys.services", "group": "Systém", "label": "Stav služeb MotoGo",
     "argv": ("systemctl", "--no-pager", "-n", "0", "status",
              "motogo-controller", "motogo-health", "motogo-ui")},
    {"id": "sys.disk", "group": "Systém", "label": "Místo na disku", "argv": ("df", "-h", "/")},
    {"id": "log.controller", "group": "Logy", "label": "Log řídicí jednotky",
     "argv": ("journalctl", "-u", "motogo-controller", "-n", "80", "--no-pager")},
    {"id": "log.health", "group": "Logy", "label": "Log health (LTE/síť)",
     "argv": ("journalctl", "-u", "motogo-health", "-n", "60", "--no-pager")},
    {"id": "log.update", "group": "Logy", "label": "Log aktualizace",
     "argv": ("tail", "-n", "60", "/var/log/motogo-update.log")},
    {"id": "svc.restart", "group": "Servis", "label": "Restart služeb MotoGo",
     "argv": ("sudo", "-n", "systemctl", "restart", "motogo-controller", "motogo-health"), "danger": True},
    {"id": "svc.reboot", "group": "Servis", "label": "Restart celého Raspberry",
     "argv": ("sudo", "-n", "systemctl", "reboot"), "danger": True},
)
_BY_ID = {p["id"]: p for p in PRESETS}


def menu() -> list[dict]:
    """Seznam pro displej — bez `argv` (co se spustí, rozhoduje jednotka, ne prohlížeč)."""
    return [{k: v for k, v in p.items() if k != "argv"} for p in PRESETS]


# ─── token terminálu ─────────────────────────────────────────────────────────
# Záměrně NENÍ `service_token`: ten otevírá kóje, a diagnostický kód na displeji dveře otevřít nesmí.
# Terminálový token platí jen pro `/api/service/shell` a nic jiného s ním udělat nejde.
def issue_token(ctrl: "BoxController") -> str | None:
    """Nový token terminálu; `None`, když ho není kam uložit (vydání tokenu nesmí shodit ověření kódu)."""
    tokens = getattr(ctrl, "shell_tokens", None)
    if not isinstance(tokens, dict):
        try:
            tokens = ctrl.shell_tokens = {}
        except Exception:  # noqa: BLE001 — controller bez tohoto atributu (starší/omezená instance)
            return None
    token = secrets.token_urlsafe(24)
    tokens[token] = time.time() + TOKEN_MINUTES * 60
    return token


def check_token(ctrl: "BoxController", token: Any) -> bool:
    now = time.time()
    tokens = getattr(ctrl, "shell_tokens", None)
    if not isinstance(tokens, dict):
        return False
    for t, exp in list(tokens.items()):
        if exp <= now:
            tokens.pop(t, None)
    return bool(token) and isinstance(token, str) and token in tokens


# ─── odemčení volného psaní ──────────────────────────────────────────────────
def unlock(ctrl: "BoxController", minutes: Any = None) -> dict:
    """Odemkne volné psaní na `minutes` (0 = hned zamknout). Vrací stav pro Velín i displej."""
    try:
        mins = FREE_DEFAULT_MINUTES if minutes in (None, "") else int(minutes)
    except (TypeError, ValueError):
        mins = FREE_DEFAULT_MINUTES
    if mins <= 0:
        ctrl.shell_until = 0.0
    else:
        ctrl.shell_until = time.time() + max(FREE_MIN_MINUTES, min(FREE_MAX_MINUTES, mins)) * 60
    log.warning("Servisní terminál: volné psaní %s", "ZAMČENO" if mins <= 0 else f"odemčeno na {mins} min")
    return state(ctrl)


def free_seconds(ctrl: "BoxController") -> int:
    """Kolik sekund volného psaní zbývá (0 = zamčeno)."""
    return max(0, int(float(getattr(ctrl, "shell_until", 0.0) or 0.0) - time.time()))


def state(ctrl: "BoxController") -> dict:
    """`{free, free_s}` — do snapshotu (Velín) i do odpovědi displeji.

    `free` = odemčeno z Velína. Servisní heslo si volné psaní nese samo (viz `run(service=True)`),
    ve stavu se proto neprojeví — Velín tím hlásí jen to, co sám povolil.
    """
    left = free_seconds(ctrl)
    return {"free": left > 0, "free_s": left}


# ─── spouštění ───────────────────────────────────────────────────────────────
def _arg_ok(arg: str) -> bool:
    """Parametr připraveného příkazu: jen běžné znaky adres/jmen — nikdy mezera nebo shell metaznak."""
    return 0 < len(arg) <= ARG_MAX and all(ch.isalnum() or ch in ".:-_" for ch in arg)


async def _exec(argv: tuple[str, ...] | list[str], shell_text: str | None = None) -> tuple[int, str]:
    """Spustí příkaz (argv, nebo `bash -c shell_text`) s limitem; vrací `(rc, výstup)`."""
    try:
        if shell_text is not None:
            proc = await asyncio.create_subprocess_exec(
                "bash", "-c", shell_text, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
        else:
            proc = await asyncio.create_subprocess_exec(
                *argv, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
    except (OSError, ValueError) as exc:
        return 127, f"{(argv or ['?'])[0]}: {exc}"
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=CMD_TIMEOUT_S)
    except asyncio.TimeoutError:
        try:
            proc.kill()
        except (ProcessLookupError, PermissionError):
            pass   # potomek pod sudo (root) — kill nesmí shodit endpoint
        return 124, f"Příkaz nedoběhl do {int(CMD_TIMEOUT_S)} s a byl ukončen."
    return int(proc.returncode or 0), out.decode("utf-8", "replace")


async def run(ctrl: "BoxController", *, preset_id: str | None = None,
              command: str | None = None, arg: str | None = None, service: bool = False) -> dict:
    """Spustí připravený příkaz (`preset_id`) nebo volný text (`command`).

    `service=True` = volající se prokázal SERVISNÍM HESLEM (ne jen diagnostickým kódem) → volné psaní
    smí i bez odemčení z Velína; jinak je potřeba `shell_unlock` (offline pobočka ho nedostane).

    Vrací `{ok, rc, output, truncated, label, free_s}`; chyba → `{ok:false, error}`
    (`unknown_preset` | `invalid_arg` | `locked` | `empty`).
    """
    if preset_id:
        preset = _BY_ID.get(str(preset_id).strip())
        if preset is None:
            return {"ok": False, "error": "unknown_preset"}
        argv = list(preset["argv"])
        if preset.get("arg"):
            value = str(arg or "").strip()
            if not _arg_ok(value):
                return {"ok": False, "error": "invalid_arg"}
            argv = [value if a == "{arg}" else a for a in argv]
        label, shown, shell_text = preset["label"], " ".join(argv), None
    else:
        text = str(command or "").strip()
        if not text:
            return {"ok": False, "error": "empty"}
        if not service and free_seconds(ctrl) <= 0:
            # Diagnostický kód sám na volné psaní nestačí — potřebuje odemčení z Velína.
            # Servisní heslo (`service=True`) ho má rovnou, aby šel terminál použít i offline.
            return {"ok": False, "error": "locked"}
        argv, label, shown, shell_text = [], "volný příkaz", text, text

    started = time.monotonic()
    rc, output = await _exec(argv, shell_text)
    took_ms = int((time.monotonic() - started) * 1000)
    truncated = len(output) > OUTPUT_LIMIT
    output = output[:OUTPUT_LIMIT] + ("\n… (výstup zkrácen)" if truncated else "")
    await _audit(ctrl, shown, preset_id, rc, output, took_ms,
                 "service_code" if service else "diag_code")
    return {"ok": rc == 0, "rc": rc, "output": output, "truncated": truncated,
            "label": label, "command": shown, "took_ms": took_ms, "free_s": free_seconds(ctrl)}


async def _audit(ctrl: "BoxController", shown: str, preset_id: str | None,
                 rc: int, output: str, took_ms: int, auth: str = "diag_code") -> None:
    """Zápis do `kiosk_logs` — co se na pobočce pustilo a jak to dopadlo (fire-and-forget přes outbox)."""
    try:
        await ctrl.emit(Event(
            kind=EventKind.SHELL, level="warn" if rc else "info", success=rc == 0,
            message=f"Servisní terminál: {shown}",
            detail={"preset": preset_id, "free_text": preset_id is None, "rc": rc, "auth": auth,
                    "took_ms": took_ms, "output": output[:LOG_OUTPUT_LIMIT]}))
    except Exception:  # noqa: BLE001 — audit nesmí shodit odpověď displeji
        log.exception("Audit servisního terminálu selhal")
