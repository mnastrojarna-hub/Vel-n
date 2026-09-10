"""Pomocné funkce `BoxController` pro kódy a události: zpracování kódu
(`submit_code`), texty pro UI (převzaté z tabletového kiosku
`kiosk_screen.dart`), mapování událostí na Supabase RPC (kontrakt §15) a výběr
zóny pro zákaznický kód.
"""
from __future__ import annotations

import secrets
import time
from datetime import datetime, timezone
from typing import TYPE_CHECKING

from .models import Event, EventKind, ResolveResult, ServiceDoor
from .pins import hmac_code, mask, normalize_code

if TYPE_CHECKING:  # pragma: no cover
    from .controller import BoxController
    from .zone import ZoneController

SUPPORT = "+420 774 256 271"

# Události zapisované přes kiosk_log_open (branch_door_events)
LOG_OPEN_KINDS = frozenset({
    EventKind.ACCESS_GRANTED, EventKind.ACCESS_DENIED, EventKind.DOOR_OPENED, EventKind.DOOR_CLOSED,
    EventKind.SESSION_COMPLETED, EventKind.OPEN_TIMEOUT, EventKind.FORCED_OPEN, EventKind.PIN_INVALID,
})
# Události zapisované přes kiosk_log_event (kiosk_logs) → zdroj
LOG_EVENT_SOURCES: dict[EventKind, str] = {
    EventKind.IO_OFFLINE: "modbus", EventKind.IO_ONLINE: "modbus",
    EventKind.SESSION_OVERTIME: "zone", EventKind.SESSION_OVERTIME_ALERT: "zone",
    EventKind.CONTACT_FAULT: "zone", EventKind.PIN_LOCKOUT: "pin", EventKind.STARTUP: "controller",
    EventKind.LTE_RESET: "lte", EventKind.REBOOT: "lte", EventKind.CONFIG_PROBLEM: "config",
    EventKind.RPC_ERROR: "rpc",
    EventKind.DIAGNOSTICS: "diagnostics",
}
# Události, které se zobrazí jako upozornění v UI
NOTICE_KINDS = frozenset({EventKind.FORCED_OPEN, EventKind.SESSION_OVERTIME, EventKind.SESSION_OVERTIME_ALERT})
# Jen tyto chyby ověření znamenají „zákazník zadal špatný kód" → počítají se do lockoutu (§10).
INVALID_CODE_ERRORS = frozenset({"invalid_code", "code_expired", "code_not_yet_valid"})
# Servisní hesla z offline cache platí nejvýš 3 dny bez synchronizace — odvolání hesla ve Velíně musí dojít.
SERVICE_CACHE_MAX_AGE_S = 72 * 3600


def error_text(error: str | None) -> str:
    """Podtitulek chyby ověření kódu (shodné s Flutter kioskem)."""
    if error in INVALID_CODE_ERRORS:
        return "Kód nebyl rozpoznán nebo už není platný."
    if error == "network":
        return "Chyba spojení. Zkontrolujte internet a zkuste znovu."
    if error in ("unauthorized", "branch_not_found", "missing_inputs") or (error or "").startswith("api_"):
        return "Kiosk není správně spárovaný s pobočkou."
    if error == "locked":
        return f"Příliš mnoho neplatných pokusů. Zkuste to později nebo kontaktujte podporu: {SUPPORT}."
    if error == "not_ready":
        return "Řídicí jednotka právě startuje. Zkuste to prosím za chvíli."
    if error == "service_cache_expired":
        return "Servisní heslo nelze ověřit bez spojení (offline cache je starší než 3 dny)."
    return "Zkuste to prosím znovu."


def hash_legacy_payload(payload: dict, device_id: str, device_token: str) -> dict:
    """Legacy `kiosk_sync_codes` (plaintext) → tvar `kiosk_sync_config` (jen HMAC hashe).

    PIN ani servisní heslo se NIKDY neukládají v čistém textu (SPEC §10): každý
    `{"code": c}` / řetězec se převede na `{"h": hmac}` a plaintext klíč se zahodí.
    """
    out = dict(payload)
    codes: list[dict] = []
    for row in payload.get("codes") or []:
        if not isinstance(row, dict):
            continue
        if row.get("h") is None and row.get("code"):
            row = {**{k: v for k, v in row.items() if k != "code"},
                   "h": hmac_code(device_id, device_token, str(row["code"]).strip())}
        codes.append(row)
    services: list[dict] = []
    for item in payload.get("service_codes") or []:
        if isinstance(item, dict):
            meta = {k: item[k] for k in ("action", "label") if item.get(k)}    # účel hesla (service|diagnostics)
            if item.get("h") is not None:
                services.append({"h": item["h"], **meta})
            elif item.get("code"):
                services.append({"h": hmac_code(device_id, device_token, str(item["code"]).strip()), **meta})
        elif str(item).strip():
            services.append({"h": hmac_code(device_id, device_token, str(item).strip())})
    out["codes"], out["service_codes"] = codes, services
    return out


def config_part(payload: dict) -> dict:
    """Část sync payloadu bez kódů (do kv `remote_config`) — kódy patří jen do code cache."""
    return {k: v for k, v in payload.items() if k not in ("codes", "service_codes")}


def door_name(kind: str, zc: "ZoneController | None", box_number: int | None) -> str:
    if zc is not None:
        return zc.zone.display_name
    if kind == "accessories":
        return "Oblečení"
    return f"Garáž #{box_number}" if box_number is not None else "Dveře"


def not_configured_text(name: str) -> str:
    return (f"Kód je platný ({name}), ale relé pro tyto dveře není ve Velíně nastaveno. "
            f"Kontaktujte podporu: {SUPPORT}.")


def open_result_text(ok: bool, reason: str, kind: str, name: str) -> str:
    """Text overlay po pokusu o otevření (úspěch dle druhu kódu, jinak důvod)."""
    if ok:
        if kind == "accessories":
            return f"Otevřeno — {name}. Po vyzvednutí oblečení zavřete dveře a zadejte kód k motorce."
        if kind == "motorcycle":
            return f"Otevřeno — {name}. Příjemnou cestu! 🏍️"
        return f"Otevřeno — {name}."
    if reason in ("busy", "door_open"):
        return f"{name}: dveře jsou už otevřené — zavřete je a zadejte kód znovu."
    if reason == "fault":
        return f"{name} hlásí poruchu. Kontaktujte podporu: {SUPPORT}."
    return f"Dveře se neozvaly. Zkuste to prosím znovu nebo kontaktujte podporu: {SUPPORT}."


def service_doors(ctrl: "BoxController") -> list[dict]:
    """Nabídka dveří po servisním hesle — jedna položka na zónu (configured = má zámek)."""
    out: list[dict] = []
    for zc in sorted(ctrl.zones.values(), key=lambda z: z.number):
        out.append(ServiceDoor(
            id=zc.zone.door_id, kind=zc.zone.kind, box_number=zc.zone.box_number,
            label=zc.zone.display_name, zone=zc.number, configured=zc.zone.hw.lock is not None,
        ).to_dict())
    return out


def zone_for_code(ctrl: "BoxController", door_id: str | None, box_number: int | None,
                  kind: str = "motorcycle") -> "ZoneController | None":
    """Zóna pro zákaznický kód: nejdřív podle door_id, pak (JEN u motorky) podle box_number.

    Kód k oblečení nikdy nesmí spadnout na kóji motorky podle čísla boxu z rezervace.
    """
    zc = ctrl.find_zone(door_id=door_id) if door_id else None
    if zc is None and box_number is not None and kind != "accessories":
        zc = ctrl.find_zone(box_number=box_number)
    return zc


def open_detail(event: Event) -> dict:
    """`detail` pro kiosk_log_open/log_event: {event, zone, box_number, source} + extra."""
    d = {"event": event.kind.value, "zone": event.zone, "box_number": event.box_number,
         "source": event.detail.get("source")}
    d.update({k: v for k, v in event.detail.items() if v is not None})
    return d


def log_open_kind(event: Event) -> str:
    if event.kind == EventKind.PIN_INVALID:
        return "invalid"
    return event.code_kind or "unknown"


def start_diagnostics(ctrl: "BoxController", base: dict, source: str, reason: str) -> dict:
    """Kód pro diagnostiku sítě: spustí běh (nebo vrátí ten probíhající) a UI otevře přehled.

    `source` = odkud přišel kód (ui/diag_ui), `reason` = jaký kód (local_code/service_code) —
    do reportu jde jako source=local_code|service_code (Velín SOURCE_CZ), reason=ui|diag_ui.
    """
    # režim: full (výchozí), nebo hint `pending_mode` z `/api/diagnostics/run` (jen síť)
    res = ctrl.diagnostics.start(source=reason, reason=source,
                                 mode=getattr(ctrl.diagnostics, "pending_mode", None) or "full")
    running = bool(res.get("started")) or res.get("error") == "already_running"
    return {**base, "ok": running, "kind": "diagnostics", "error": None if running else res.get("error"),
            "message": "Diagnostika pobočky spuštěna" if res.get("started") else "Diagnostika pobočky už běží",
            "diagnostics": res}


def _cache_age_s(ctrl: "BoxController") -> float | None:
    saved = getattr(ctrl.storage, "code_cache_saved_at", lambda: None)()
    return None if saved is None else max(0.0, time.time() - float(saved))


async def submit_code(ctrl: "BoxController", code: str, source: str, *, diagnostics_only: bool = False) -> dict:
    """Ověří kód (online RPC → offline cache), servisní heslo vydá token, zákaznický otevře zónu.

    Diagnostický kód (lokální `diagnostics.code` nebo servisní heslo s účelem `diagnostics`)
    spustí diagnostiku sítě — funguje i před spárováním a při `not ready` (odlaďování instalace),
    ale ne během PIN lockoutu (hádání kódů). `diagnostics_only=True` (okno diagnostiky): smí jen
    spustit diagnostiku (lokální kód / kterékoli servisní heslo) — nikdy neotevře dveře ani nevydá
    servisní token; zákaznický kód se tam chová přesně jako neplatný (žádné orákulum).
    """
    code = normalize_code(code or "")
    base = {"ok": False, "kind": "invalid", "error": None, "message": "", "zone": None,
            "locked_until": None, "doors": [], "service_token": None}
    if not code:
        return {**base, "error": "empty", "message": "Zadejte přístupový kód."}
    locked = ctrl.pin_guard.locked_until()
    if locked:
        return {**base, "error": "locked", "message": error_text("locked"), "locked_until": locked}
    diag = getattr(ctrl, "diagnostics", None)
    if diag is not None and diag.matches_local_code(code):
        return start_diagnostics(ctrl, base, source, "local_code")
    if not ctrl.ready:              # §12 krok 8: PIN až po dokončení startu / přestavby HW
        return {**base, "error": "not_ready", "message": error_text("not_ready")}
    masked = mask(code)
    raw = await ctrl.api.resolve_code(code)
    if isinstance(raw, dict):
        rr = ResolveResult.from_rpc(raw)
    else:
        cache = ctrl.storage.load_code_cache()
        rr = ctrl.resolver.resolve(code, cache, datetime.now(timezone.utc)) if cache else None
        if rr is None:
            rr = ResolveResult(ok=False, error="invalid_code" if cache else "network", offline=True)
        elif rr.is_service and (_cache_age_s(ctrl) or 0) > SERVICE_CACHE_MAX_AGE_S:
            rr = ResolveResult(ok=False, error="service_cache_expired", offline=True)
    if diagnostics_only and rr.ok and not rr.is_service:
        rr = ResolveResult(ok=False, error="invalid_code", offline=rr.offline)   # zákaznický kód zde neotevírá
    if not rr.ok:
        err = rr.error or "invalid_code"
        if err in INVALID_CODE_ERRORS:      # jen skutečně neplatný kód se počítá do lockoutu
            until = ctrl.pin_guard.register_failure(masked)
            await ctrl.emit(Event(kind=EventKind.PIN_INVALID, success=False, level="warn", code_kind="invalid",
                                  message=f"Neplatný kód {masked}",
                                  detail={"source": source, "code_masked": masked, "error": err,
                                          "offline": rr.offline}))
            if until:
                await ctrl.emit(Event(kind=EventKind.PIN_LOCKOUT, success=False, level="warn",
                                      message="Zadávání kódů dočasně zablokováno",
                                      detail={"source": source, "locked_until": until}))
                return {**base, "error": "locked", "message": error_text("locked"), "locked_until": until}
            return {**base, "error": "invalid_code", "message": error_text(err)}
        if err != "network":                # systémová chyba (párování, API) — hlásit, ne trestat
            await ctrl.emit(Event(kind=EventKind.RPC_ERROR, success=False, level="error",
                                  message=f"Ověření kódu selhalo: {err}",
                                  detail={"source": source, "error": err, "code_masked": masked}))
        return {**base, "error": err, "message": error_text(err)}
    ctrl.pin_guard.register_success(masked)
    if diag is not None and (rr.is_diagnostics or (diagnostics_only and rr.is_service)):
        return start_diagnostics(ctrl, base, source, "service_code")
    if rr.is_service:
        token = secrets.token_urlsafe(24)
        ctrl.service_tokens[token] = time.time() + ctrl.hardware.security.service_token_minutes * 60
        return {**base, "ok": True, "kind": "service", "message": "Servisní režim",
                "doors": service_doors(ctrl), "service_token": token}
    zc = zone_for_code(ctrl, rr.door_id, rr.box_number, rr.kind)
    name = door_name(rr.kind, zc, rr.box_number)
    if zc is None:
        await ctrl.emit(Event(kind=EventKind.ACCESS_DENIED, success=False, level="warn", code_kind=rr.kind,
                              door_id=rr.door_id, booking_id=rr.booking_id, box_number=rr.box_number,
                              message=f"Kód platný, ale zóna není nastavena ({name})",
                              detail={"source": source, "reason": "door_not_configured"}))
        return {**base, "kind": rr.kind, "error": "zone_not_configured", "message": not_configured_text(name)}
    ok, reason = await zc.grant_access(booking_id=rr.booking_id, kind=rr.kind, source=source)
    if not ok:
        await ctrl.emit(Event(kind=EventKind.ACCESS_DENIED, success=False, level="warn", code_kind=rr.kind,
                              zone=zc.number, door_id=zc.zone.door_id, booking_id=rr.booking_id,
                              box_number=zc.zone.box_number, message=f"{name}: otevření selhalo ({reason})",
                              detail={"source": source, "reason": reason, "offline": rr.offline}))
    return {**base, "ok": ok, "kind": rr.kind, "error": None if ok else reason, "zone": zc.number,
            "message": open_result_text(ok, reason, rr.kind, name)}
