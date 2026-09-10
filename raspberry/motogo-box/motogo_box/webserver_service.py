"""Servisní endpointy webserveru (kontrakt §16, ``/api/service/*``).

Oddělené od ``webserver.py`` kvůli délce modulu; veřejné API (``WebServer``)
zůstává ve ``webserver.py``. Každý handler dostane instanci ``WebServer``
(``srv``) a ``aiohttp`` request. Všechny endpointy kromě párování nespárovaného
zařízení vyžadují platný ``service_token`` (``ctrl.check_service_token``);
neplatný → ``403 {"ok": false, "error": "forbidden"}``.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any

from aiohttp import web

log = logging.getLogger("motogo.web")

RESTART_DELAY_S = 0.5          # aby odešla odpověď před os._exit


def _to_int(value: Any) -> int | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _to_bool(value: Any) -> bool:
    if isinstance(value, str):
        return value.strip().lower() in ("1", "true", "on", "yes")
    return bool(value)


def service_denied(srv: Any, body: dict) -> web.Response | None:
    """403 pokud service_token neplatí, jinak None."""
    token = body.get("service_token")
    try:
        ok = bool(srv.ctrl.check_service_token(token if isinstance(token, str) else None))
    except Exception:  # noqa: BLE001
        log.exception("check_service_token selhal")
        ok = False
    return None if ok else srv.error("forbidden", 403)


async def service_open(srv: Any, request: web.Request) -> web.Response:
    body = await srv.read_body(request)
    if (denied := service_denied(srv, body)) is not None:
        return denied
    door_id = body.get("door_id")
    zone = _to_int(body.get("zone"))
    if not door_id and zone is None:
        return srv.error("missing_zone")
    result = await srv.ctrl.service_open(door_id if isinstance(door_id, str) else None, zone)
    return srv.json(result if isinstance(result, dict) else {"ok": bool(result)})


async def service_music(srv: Any, request: web.Request) -> web.Response:
    body = await srv.read_body(request)
    if (denied := service_denied(srv, body)) is not None:
        return denied
    on = _to_bool(body.get("on"))
    audio = getattr(srv.ctrl, "audio", None)
    if audio is None:
        return srv.error("audio_unavailable")
    if not on:
        await audio.stop()
        return srv.json({"ok": True, "on": False})
    zone = _to_int(body.get("zone"))
    if zone is None:
        zones = getattr(srv.ctrl, "zones", None) or {}
        zone = min(zones) if zones else None
    if zone is None:
        return srv.error("no_zone")
    ok = bool(await audio.play_zone(zone))
    return srv.json({"ok": ok, "on": ok, "zone": zone, "error": None if ok else "audio_failed"})


async def service_light(srv: Any, request: web.Request) -> web.Response:
    body = await srv.read_body(request)
    if (denied := service_denied(srv, body)) is not None:
        return denied
    zone = _to_int(body.get("zone"))
    if zone is None:
        return srv.error("missing_zone")
    zc = srv.ctrl.find_zone(zone=zone)
    if zc is None:
        return srv.error("zone_not_found", 404)
    on = _to_bool(body.get("on"))
    ok = bool(await zc.set_light(on))
    return srv.json({"ok": ok, "zone": zone, "on": on, "error": None if ok else "light_failed"})


async def service_all_off(srv: Any, request: web.Request) -> web.Response:
    body = await srv.read_body(request)
    if (denied := service_denied(srv, body)) is not None:
        return denied
    await srv.ctrl.all_off()
    return srv.json({"ok": True})


async def service_pair(srv: Any, request: web.Request) -> web.Response:
    """Spárování: bez service_token povoleno JEN když zařízení ještě není spárované."""
    body = await srv.read_body(request)
    paired = getattr(srv.api, "paired", None)            # ID i token (jen ID = nespárováno)
    if paired is None:
        paired = bool(getattr(srv.api, "device_id", "") and getattr(srv.api, "device_token", ""))
    if paired and (denied := service_denied(srv, body)) is not None:
        return denied
    device_id = str(body.get("device_id") or "").strip()
    device_token = str(body.get("device_token") or "").strip()
    if not device_id or not device_token:
        return srv.error("missing_inputs")
    error = await srv.api.validate_pairing(device_id, device_token)
    if error:
        return srv.json({"ok": False, "error": str(error)})
    srv.storage.kv_set("device_id", device_id)
    srv.storage.kv_set("device_token", device_token)
    srv.api.set_device(device_id, device_token)
    resync: Any
    try:
        resync = await srv.ctrl.resync()
    except Exception:  # noqa: BLE001
        log.exception("Resync po spárování selhal")
        resync = {"changed": False, "problems": ["resync_failed"]}
    log.info("Zařízení spárováno: %s", device_id)
    return srv.json({"ok": True, "device_id": device_id, "resync": resync})


# ─── diagnostika sítě ─────────────────────────────────────────────────────────
async def diagnostics_get(srv: Any, request: web.Request) -> web.Response:
    """Stav + poslední report (jen z localhostu — report obsahuje mapu LAN); `?report=0` = bez reportu."""
    from .webserver import is_local_request      # lazy: webserver importuje tento modul
    if not is_local_request(request):
        return srv.error("forbidden", 403)
    diag = getattr(srv.ctrl, "diagnostics", None)
    if diag is None:
        return srv.error("unavailable", 503)
    with_report = request.query.get("report") not in ("0", "false", "no")
    return srv.json({"ok": True, "status": diag.status(), "report": diag.last_report() if with_report else None})


async def diagnostics_run(srv: Any, request: web.Request) -> web.Response:
    """Spuštění: platný `service_token`, nebo `code` (lokální diagnostický kód / servisní heslo)."""
    body = await srv.read_body(request)
    diag = getattr(srv.ctrl, "diagnostics", None)
    if diag is None:
        return srv.error("unavailable", 503)
    token = body.get("service_token")
    if isinstance(token, str) and token and srv.ctrl.check_service_token(token):
        return srv.json(diag.start(source="service_panel", reason="service_panel"))
    code = body.get("code")
    if not isinstance(code, str) or not code.strip():
        return srv.error("forbidden", 403)
    res = await srv.ctrl.submit_code(code, "diag_ui")
    res = res if isinstance(res, dict) else {}
    if res.get("ok") and res.get("kind") == "diagnostics":
        return srv.json({"ok": True, **(res.get("diagnostics") or {})})
    if res.get("ok") and res.get("kind") == "service":       # servisní heslo smí i diagnostiku
        return srv.json(diag.start(source="service_code", reason="service_code"))
    return srv.json({"ok": False, "error": res.get("error") or "invalid_code",
                     "message": res.get("message") or "", "locked_until": res.get("locked_until")}, 403)


async def service_restart(srv: Any, request: web.Request) -> web.Response:
    body = await srv.read_body(request)
    if (denied := service_denied(srv, body)) is not None:
        return denied
    log.warning("Restart řídicí jednotky vyžádán ze servisního panelu")
    asyncio.get_running_loop().call_later(RESTART_DELAY_S, srv._exit, 0)
    return srv.json({"ok": True, "restarting": True})
