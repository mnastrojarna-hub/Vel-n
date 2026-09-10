"""Vzdálené příkazy z Velína (`kiosk_commands`) — kontrakt §13.

`execute(ctrl, command, params)` vrací `(success, result)`; nikdy nevyhazuje.
Příkaz `restart` ukončí proces uvnitř `execute`, proto ho `BoxController.handle_command`
potvrdí v Supabase PŘEDEM; `reboot` vrací skutečný výsledek `sudo` (selhání sudoers/timeout
se dostane do Velína). `update_software` / `update_system` se jen naplánují
(`ctrl.updater.start`, viz `updater.py`) — běží až když je box volný; dokud běží root skript
(apt/git), `restart`/`reboot` se odmítají (`update_blocks`) — restart unity by ho zabil uprostřed
dpkg. HW příkazy se odmítají, dokud jednotka není `ready` (start / přestavba HW — §12 krok 8).
"""
from __future__ import annotations

import asyncio
import logging
import os
import time
from typing import TYPE_CHECKING, Any, Awaitable, Callable

import httpx

from .models import Signal

if TYPE_CHECKING:  # pragma: no cover
    from .controller import BoxController

log = logging.getLogger("motogo.commands")

HTTP_TIMEOUT_S = 6.0
SUBPROCESS_TIMEOUT_S = 120.0

Handler = Callable[["BoxController", dict], Awaitable[tuple[bool, dict]]]


def _int(v: Any) -> int | None:
    try:
        return None if v is None or v == "" else int(v)
    except (TypeError, ValueError):
        return None


def _zone_of(ctrl: "BoxController", params: dict):
    """Najde zónu dle `door_id` → `zone` → `box_number`; None když nic nesedí."""
    door_id = params.get("door_id") or None
    zone_n = _int(params.get("zone"))
    box = _int(params.get("box_number"))
    z = ctrl.find_zone(door_id=str(door_id)) if door_id else None
    if z is None and zone_n is not None:
        z = ctrl.find_zone(zone=zone_n)
    if z is None and box is not None:
        z = ctrl.find_zone(box_number=box)
    return z


def _first_zone(ctrl: "BoxController"):
    return next(iter(sorted(ctrl.zones.values(), key=lambda zc: zc.number)), None)


async def _run(*argv: str) -> tuple[bool, dict]:
    """Spustí proces (sudo …); chyby → (False, {error})."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *argv, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
        try:
            out, _ = await asyncio.wait_for(proc.communicate(), timeout=SUBPROCESS_TIMEOUT_S)
        except asyncio.TimeoutError:
            proc.kill()
            return False, {"error": "timeout", "argv": list(argv)}
        text = (out or b"").decode("utf-8", "replace")[-2000:]
        return proc.returncode == 0, {"returncode": proc.returncode, "output": text}
    except (OSError, ValueError) as exc:
        return False, {"error": str(exc), "argv": list(argv)}


# ─── jednotlivé příkazy ─────────────────────────────────────────────────────
async def _open_door(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    z = _zone_of(ctrl, params)
    if z is None:
        return False, {"error": "zone_not_found"}
    ok, reason = await z.grant_access(booking_id=None, kind="service", source="velin")
    return ok, {"zone": z.number, "reason": reason}


async def _music_on(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    selected = any(params.get(k) not in (None, "") for k in ("zone", "door_id", "box_number"))
    z = _zone_of(ctrl, params) if selected else _first_zone(ctrl)
    if z is None:
        # Zadaná, ale neexistující zóna NESMÍ spadnout na první kóji (cizí reproduktor).
        return False, {"error": "zone_not_found"}
    ok = bool(await ctrl.audio.play_zone(z.number))
    return ok, {"zone": z.number}


async def _music_off(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    await ctrl.audio.stop()
    return True, {}


def _light(on: bool) -> Handler:
    async def handler(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
        z = _zone_of(ctrl, params)
        if z is None:
            return False, {"error": "zone_not_found"}
        ok = await z.set_light(on)
        return ok, {"zone": z.number, "light": z.light_on}
    return handler


async def _set_signal(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    z = _zone_of(ctrl, params)
    if z is None:
        return False, {"error": "zone_not_found"}
    sig = Signal.parse(params.get("signal"))
    if sig is None:
        return False, {"error": "invalid_signal", "allowed": [s.value for s in Signal]}
    await z.set_signal(sig)
    return True, {"zone": z.number, "signal": sig.value}


async def _zone_test(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    z = _zone_of(ctrl, params)
    if z is None:
        return False, {"error": "zone_not_found"}
    res = await z.test_sequence()
    return all(bool(v) for v in res.values()), {"zone": z.number, **res}


async def _audio_test(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    z = _zone_of(ctrl, params)
    if z is None:
        return False, {"error": "zone_not_found"}
    seconds = _int(params.get("seconds")) or 5
    ok = bool(await ctrl.audio.test_tone(z.number, max(1, min(60, seconds))))
    return ok, {"zone": z.number, "seconds": seconds}


async def _all_off(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    await ctrl.all_off()
    return True, {}


async def _identify(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    label = str(params.get("label") or "Velín")
    ctrl.ui_notice = {"title": "Tady jsem 👋", "subtitle": f"Identifikace z Velína ({label})",
                      "kind": "info", "ts": time.time()}
    zones = list(ctrl.zones.values())
    for _ in range(3):
        for z in zones:
            await z.set_signal(Signal.GREEN)
        await asyncio.sleep(0.4)
        for z in zones:
            await z.set_signal(Signal.OFF)
        await asyncio.sleep(0.4)
    for z in zones:
        await z.refresh_signal()      # obnovit dle AKTUÁLNÍHO stavu zóny (mohl se během blikání změnit)
    return True, {"zones": len(zones)}


async def _reload(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    res = await ctrl.resync()
    return bool(res.get("ok", True)), res


async def _restart(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    log.warning("Vzdálený příkaz restart — ukončuji proces (systemd restartuje)")
    await asyncio.sleep(0.2)   # dát šanci odeslat complete_command / logy
    os._exit(0)


async def _reboot(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    """Potvrzení odchází PŘED rebootem (TERMINAL_COMMANDS) — systemd proces zabije dřív, než by
    se potvrzení přes LTE doručilo; selhání sudo se hlásí zvlášť přes kiosk_log_event."""
    if params.get("wait_idle"):
        # Velín „Restart OS“ (po novém jádru): až bude box volný — plánuje updater (§25), potvrzení je
        # `scheduled` (TERMINAL_COMMANDS), průběh v `snapshot()['update']`.
        return ctrl.updater.start("reboot", params)
    log.warning("Vzdálený příkaz reboot")
    ok, res = await _run("sudo", "systemctl", "reboot")
    if not ok:
        await ctrl.api.log_event("error", "controller", "Příkaz reboot selhal (sudo)", res)
    return ok, res


async def _update(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    """Aktualizace software — jen naplánuje (`{scheduled, ref, wait_idle_s}`), běží až v klidu (§25)."""
    return ctrl.updater.start("software", params)


async def _update_system(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    """Aktualizace OS (apt full-upgrade) — naplánuje; `auto_reboot` restartuje po jádru, až je box volný."""
    return ctrl.updater.start("system", params)


async def _diagnostics(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    """Diagnostika pobočky z Velína — běží na pozadí, report dorazí přes `kiosk_report_diagnostics`.

    `params {mode?: full|network (výchozí full), cameras?: [{name, kind, snapshot_url, stream_url}], reason?}`.
    """
    mode = "network" if str(params.get("mode") or "").strip().lower() == "network" else "full"
    cams = params.get("cameras")
    res = ctrl.diagnostics.start(source="velin", reason=str(params.get("reason") or "velin"), mode=mode,
                                 cameras=cams if isinstance(cams, list) else None)
    return bool(res.get("ok")), res


async def _http_get(ctrl: "BoxController", params: dict) -> tuple[bool, dict]:
    url = str(params.get("url") or "").strip()
    if not url.lower().startswith(("http://", "https://")):
        return False, {"error": "invalid_url"}
    try:
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT_S) as client:
            r = await client.get(url)
        return r.status_code < 400, {"status": r.status_code, "body": r.text[:500]}
    except httpx.HTTPError as exc:
        return False, {"error": str(exc)}


HANDLERS: dict[str, Handler] = {
    "open_door": _open_door,
    "music_on": _music_on,
    "music_off": _music_off,
    "light_on": _light(True),
    "light_off": _light(False),
    "set_signal": _set_signal,
    "zone_test": _zone_test,
    "audio_test": _audio_test,
    "all_off": _all_off,
    "identify": _identify,
    "reload": _reload,
    "sync_config": _reload,
    "restart": _restart,
    "reboot": _reboot,
    "update_software": _update,
    "update_system": _update_system,
    "http_get": _http_get,
    "camera_control": _http_get,
    "diagnostics": _diagnostics,
}

# Příkazy, které ukončí proces — controller je dokončí v Supabase PŘED spuštěním.
TERMINAL_COMMANDS = frozenset({"restart", "reboot"})
# Příkazy sahající na hardware — jen když je jednotka `ready` (po startu / mimo přestavbu).
HW_COMMANDS = frozenset({"open_door", "music_on", "music_off", "light_on", "light_off", "set_signal",
                         "zone_test", "audio_test", "all_off", "identify"})


def update_blocks(ctrl: "BoxController", command: str) -> dict | None:
    """`restart`/`reboot` během běhu root skriptu aktualizace → `{error: update_in_progress, …}`, jinak None."""
    updater = getattr(ctrl, "updater", None)
    if command not in TERMINAL_COMMANDS or not getattr(updater, "script_running", False):
        return None
    return {"error": "update_in_progress", "command": command, "state": updater.state, "kind": updater.kind}


async def execute(ctrl: "BoxController", command: str, params: dict) -> tuple[bool, dict]:
    """Provede příkaz z Velína; neznámý → `(False, {"error": "unknown_command"})`."""
    handler = HANDLERS.get(str(command or "").strip())
    if handler is None:
        return False, {"error": "unknown_command", "command": command}
    params = params if isinstance(params, dict) else {}
    if command in HW_COMMANDS and not getattr(ctrl, "ready", True):
        return False, {"error": "not_ready", "command": command}
    blocked = update_blocks(ctrl, command)
    if blocked is not None:
        log.warning("Příkaz %s odmítnut — běží aktualizace (%s)", command, blocked)
        return False, blocked
    try:
        ok, result = await handler(ctrl, params)
        log.info("Příkaz %s %s → %s %s", command, params, "OK" if ok else "FAIL", result)
        return bool(ok), dict(result or {})
    except Exception as exc:  # noqa: BLE001 — příkaz nesmí shodit smyčku
        log.exception("Příkaz %s selhal", command)
        return False, {"error": str(exc), "command": command}
