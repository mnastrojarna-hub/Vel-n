"""Podpis předávacího protokolu z displeje a odesílání fronty — pomocný modul `handover.py`.

Pořadí při podpisu (§4, rozhodnutí majitele: podpis se NIKDY neztratí): (1) `Storage.protocol_queue_put`
+ stav manageru v JEDNÉ transakci, (2) pokus o okamžité odeslání edge funkci (45 s; úspěch i
`already_filled` = hotovo, síť/5xx = zůstává `pending`, 4xx = `failed` + událost), (3) teprve pak
otevření kóje (`then_open`). Identita podepisujícího = kód motorky téže rezervace (pole ve formuláři),
pokud overlay nepřišel z právě zadaného kódu (platný `then_open`).
"""
from __future__ import annotations

import logging
import re
from typing import TYPE_CHECKING, Any

from . import controller_codes as cc
from .models import Event, EventKind, now_iso
from .pins import mask, normalize_code

if TYPE_CHECKING:  # pragma: no cover
    from .handover import HandoverManager

log = logging.getLogger("motogo.handover")

SIGNATURE_PREFIX = "data:image/png;base64,"
SIGNATURE_RE = re.compile(r"data:image/png;base64,[A-Za-z0-9+/=]+")   # podmnožina SIG_RE edge (jen PNG, §0.3)
SIGNATURE_MAX_BYTES = 150 * 1024      # edge odmítá větší (413 signature_too_large) — odmítnout hned na displeji
QUEUE_BATCH = 20


def signature_bytes(signature: Any) -> int | None:
    """Dekódovaná velikost PNG v data-URL, bez odečtu paddingu — TÝŽ vzorec jako edge (`util.ts signatureBytes`:
    floor((len − idx(',') − 1) · 3/4)) a UI (`signature.js`), aby displej odmítl přesně to, co by server vrátil
    jako 413. None = chybí / není čistá PNG data-URL (edge → 400 `invalid_signature` = trvalé selhání, proto
    se takový podpis nesmí dostat ani do fronty)."""
    if not isinstance(signature, str) or not SIGNATURE_RE.fullmatch(signature):
        return None
    n = (len(signature) - len(SIGNATURE_PREFIX)) * 3 // 4
    return n if n > 0 else None


async def open_zone(hm: "HandoverManager", then_open: dict | None) -> tuple[dict | None, str | None]:
    """Otevře kóji dle `then_open`; vrací (`opened {zone, kind, message}`, None) nebo (None, důvod)."""
    ctrl = hm.ctrl
    zone = then_open.get("zone") if isinstance(then_open, dict) else None
    zc = ctrl.zones.get(zone) if zone is not None else None
    if zc is None:
        return None, "zone_not_configured"
    bid, kind, source = then_open.get("booking_id"), str(then_open.get("kind") or "motorcycle"), then_open.get("source")
    ok, reason = await zc.grant_access(booking_id=bid, kind=kind, source=str(source or "protocol"))
    name = zc.zone.display_name
    if ok:
        return {"zone": zc.number, "kind": zc.zone.kind, "message": cc.open_result_text(True, "ok", kind, name)}, None
    await ctrl.emit(Event(kind=EventKind.ACCESS_DENIED, success=False, level="warn", code_kind=kind,
                          zone=zc.number, door_id=zc.zone.door_id, booking_id=bid, box_number=zc.zone.box_number,
                          message=f"{name}: otevření po podpisu protokolu selhalo ({reason})",
                          detail={"source": source, "reason": reason}))
    return None, reason


async def _verify_code(hm: "HandoverManager", booking_id: str, code: str | None,
                       source: str) -> tuple[dict | None, dict]:
    """Kód motorky téže rezervace → (then_open, {}); jinak (None, {error: code_mismatch | locked, locked_until?}).
    Cizí/neplatný kód = pokus o hádání (PinGuard jako neplatný kód); vlastní kód šatny téže rezervace se netrestá.
    Během lockoutu se kód vůbec neověřuje a UI dostane stejnou informaci jako z `/api/pin` (ne „špatný kód“)."""
    ctrl = hm.ctrl
    locked = ctrl.pin_guard.locked_until()
    if locked:
        return None, {"error": "locked", "locked_until": locked}
    code = normalize_code(code or "")
    if not code:
        return None, {"error": "code_mismatch"}
    masked = mask(code)
    rr = await cc.resolve_code(ctrl, code)
    same = rr.ok and str(rr.booking_id or "") == booking_id
    if same and rr.kind == "motorcycle":
        ctrl.pin_guard.register_success(masked)
        zc = cc.zone_for_code(ctrl, rr.door_id, rr.box_number, rr.kind)
        return {"zone": zc.number if zc else None, "booking_id": booking_id, "kind": "motorcycle", "source": source}, {}
    if not same and ((rr.ok and not rr.is_service) or rr.error in cc.INVALID_CODE_ERRORS):
        until = ctrl.pin_guard.register_failure(masked)
        await ctrl.emit(Event(kind=EventKind.PIN_INVALID, success=False, level="warn", code_kind="invalid",
                              booking_id=booking_id, message=f"Kód motorky k protokolu nesedí {masked}",
                              detail={"source": source, "code_masked": masked, "error": "code_mismatch"}))
        if until:
            await ctrl.emit(Event(kind=EventKind.PIN_LOCKOUT, success=False, level="warn",
                                  message="Zadávání kódů dočasně zablokováno",
                                  detail={"source": source, "locked_until": until}))
            return None, {"error": "locked", "locked_until": until}
    return None, {"error": "code_mismatch"}


async def submit(hm: "HandoverManager", booking_id: str, form: Any, signature: Any, code: str | None,
                 source: str = "ui") -> dict:
    """`POST /api/protocol/submit` → `{ok, status: saved|queued|already_filled, opened|null, error}`
    (+ `locked_until` při `error: locked` — PIN lockout, stejně jako `/api/pin`)."""
    from .handover import KV_HANDOVER, STAGE_PROTOCOL   # lokálně: handover importuje tento modul
    base = {"ok": False, "status": None, "opened": None, "error": None}
    bid = str(booking_id or "")
    item = hm.items.get(bid)
    if item is None or item.stage != STAGE_PROTOCOL:
        return {**base, "error": "not_pending"}
    if item.in_flight or bid in hm.inflight:
        return {**base, "error": "in_progress"}
    size = signature_bytes(signature)
    if size is None:
        return {**base, "error": "missing_signature"}
    if size > SIGNATURE_MAX_BYTES:
        return {**base, "error": "signature_too_large"}
    then_open = item.then_open if hm.then_open_valid(item) else None
    if then_open is None:
        then_open, err = await _verify_code(hm, bid, code, source)
        if then_open is None:
            return {**base, **err}
    item.in_flight, item.then_open = True, None
    hm.inflight.add(bid)
    payload = {"booking_id": bid, "form": form if isinstance(form, dict) else {}, "signature": signature,
               "signed_at": now_iso()}
    stored = True
    try:
        hm.ctrl.storage.protocol_queue_put(bid, payload, kv=(KV_HANDOVER, hm.state_dict()))
    except Exception:  # noqa: BLE001 — disk: zkusit aspoň odeslat hned; bez uložení i odeslání podpis nevydat
        log.exception("handover: uložení podpisu do fronty selhalo")
        stored = False
    hm.refresh_queue()
    await hm.ctrl.emit(Event(kind=EventKind.PROTOCOL_SIGNED, zone=then_open.get("zone"), booking_id=bid,
                             code_kind="motorcycle", message="Předávací protokol podepsán na displeji",
                             detail={"source": source, "signature_bytes": size, "stored": stored}))
    try:
        result = await upload_one(hm, bid, payload)
    finally:
        hm.inflight.discard(bid)
        hm.items.pop(bid, None)
    if not stored and result in ("queued", "failed"):
        hm._save()  # noqa: SLF001
        return {**base, "error": "storage_failed"}
    hm.signed[bid] = hm.clock()
    opened, err = await open_zone(hm, then_open)
    hm._save()  # noqa: SLF001
    status = "already_filled" if result == "already_filled" else ("saved" if result == "saved" else "queued")
    return {"ok": True, "status": status, "opened": opened, "error": err}


async def upload_one(hm: "HandoverManager", booking_id: str, payload: dict) -> str:
    """Jeden pokus o odeslání: `saved` | `already_filled` | `queued` (síť/5xx) | `failed` (4xx trvale)."""
    st = hm.ctrl.storage
    res = await hm.ctrl.api.submit_protocol(payload)
    if res.get("ok"):
        st.protocol_queue_done(booking_id)
        hm.signed[booking_id] = hm.clock()
        hm.refresh_queue()
        return "already_filled" if res.get("already_filled") else "saved"
    permanent = bool(res.get("permanent"))
    st.protocol_queue_fail(booking_id, str(res.get("error") or ""), permanent)
    hm.refresh_queue()
    if not permanent:
        hm.wake.set()
        return "queued"
    await hm.ctrl.emit(Event(kind=EventKind.PROTOCOL_UPLOAD_FAILED, success=False, level="error",
                             booking_id=booking_id, code_kind="motorcycle",
                             message=f"Podpis protokolu z displeje odmítnut serverem ({res.get('error')})",
                             detail={"source": "protocol_queue", "error": res.get("error"), "booking_id": booking_id,
                                     "signature_bytes": signature_bytes(payload.get("signature"))}))
    return "failed"


async def flush(hm: "HandoverManager") -> int:
    """`protocol_loop`: odešle čekající podpisy (nejstarší první); při výpadku sítě končí hned."""
    sent = 0
    for row in hm.ctrl.storage.protocol_queue_pending(QUEUE_BATCH):
        bid = row["booking_id"]
        if bid in hm.inflight:
            continue
        hm.inflight.add(bid)
        try:
            result = await upload_one(hm, bid, row["payload"])
        finally:
            hm.inflight.discard(bid)
        if result == "queued":
            hm.wake.clear()      # síť/server dole — další pokus za PROTOCOL_FLUSH_S / po obnovení spojení
            break
        if result in ("saved", "already_filled"):
            sent += 1
    if sent:
        log.info("protocol_queue: odesláno %d podpisů", sent)
    return sent
