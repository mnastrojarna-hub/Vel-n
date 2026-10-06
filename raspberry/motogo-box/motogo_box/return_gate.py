"""Dokončení vrácení — OFFLINE hradlo jednotky (rozhodnutí majitele 2026-10-06, D1/D2, CONTRACT §32).

Vrácení motorky v POSLEDNÍ den pronájmu (Praha) nebo později je finální: server (`booking_kiosk_returns`,
`kiosk_process_returns`) rezervaci dokončí a kódy nechá doběhnout `GRACE` (15 min) — kód motorky 15 min po finálním
zavření kóje, kód šatny 15 min po zavření šatny při vrácení (vrátil-li výbavu PŘED motorkou — šatna zavřená ≤ 90 min
před kójí — 15 min po zavření kóje; šatnu po vrácení vůbec nezavřel → kód šatny platí dál). ONLINE to celé rozhoduje server
(zneplatněný kód = `reason:'revoked'`); tento modul jen zajistí totéž, když jednotka ověřuje kód z OFFLINE cache, která o
dokončení ještě neví (jinak by kód otevíral až do půlnoci po posledním dni).

Záznam (kv `return_gate` = `{"b": {booking_id: {"bay": ts, "locker": ts}}}`, unixové časy jednotky, záznamy starší 3 dní
pryč) plní `observe(storage, event)` z `BoxController.emit` — z TÝCHŽ událostí, které dostává server (§15, 1.2.8):
  * SESSION_COMPLETED kódu motorky s rezervací a `odometer_phase: in` (relace vrácení / kód po vrácení) → `bay` = čas události;
  * SESSION_COMPLETED kódu šatny s rezervací → `locker` = čas události;
  * ACCESS_GRANTED kódu motorky s `odometer_phase: out` (motorka znovu vyjela) → `bay` pryč (nové vrácení se zapíše znovu).
`blocks(ctrl, rr)` = OFFLINE `ok` zákaznického kódu s rezervací, `rr.return_final_from` (začátek posledního dne; chybí =
bez hradla) ≤ `bay` a kód doběhl (motorka: teď > bay + grace; šatna jen s `locker` ≥ bay − 90 min: teď > max(locker, bay) +
grace). Odmítnutí = `code_revoked` (známý kód, BEZ lockoutu) + ACCESS_DENIED `reason: returned`. Krátkodobý kód z Velína
(`temp`, bez rezervace) hradlo nemá — tím obsluha pustí zákazníka pro zapomenutou věc.
"""
from __future__ import annotations

import logging
import time
from datetime import datetime, timezone
from typing import Any

from .models import Event, EventKind
from .pins import parse_iso

log = logging.getLogger("motogo.return_gate")

KV = "return_gate"
KEEP_S = 3 * 86400            # záznam vrácení drží jednotka 3 dny (offline cache drží kódy do valid_until + 1 den)
VISIT_S = 90 * 60             # šatna zavřená nejvýš 90 min před kójí patří k témuž vrácení (server VISIT)
DEFAULT_GRACE_MIN = 15        # server GRACE — `timings.return_code_grace_min`
ERROR = "code_revoked"        # známá chyba (KNOWN_CODE_ERRORS) = hláška „kód už neplatí“, bez lockoutu
REASON = "returned"


def grace_s(ctrl: Any) -> float:
    t = getattr(getattr(ctrl, "hardware", None), "timings", None)
    try:
        return 60.0 * max(0, int(getattr(t, "return_code_grace_min", DEFAULT_GRACE_MIN)))
    except (TypeError, ValueError):
        return 60.0 * DEFAULT_GRACE_MIN


def _ts(value: Any) -> float | None:
    dt = parse_iso(value)
    return dt.timestamp() if dt is not None else None


def _load(storage: Any, now: float) -> dict:
    raw = storage.kv_get(KV) or {}
    rows = raw.get("b") if isinstance(raw, dict) and isinstance(raw.get("b"), dict) else {}
    out: dict[str, dict[str, float]] = {}
    for bid, rec in rows.items():
        if not isinstance(rec, dict):
            continue
        rec = {k: float(v) for k, v in rec.items() if k in ("bay", "locker") and isinstance(v, (int, float))}
        if rec and now - max(rec.values()) <= KEEP_S:
            out[str(bid)] = rec
    return {"b": out}


def record(storage: Any, booking_id: str | None) -> dict:
    """Záznam rezervace `{bay?, locker?}` (prázdný = nic) — pro testy a diagnostiku."""
    return dict(_load(storage, time.time())["b"].get(str(booking_id or "")) or {})


def observe(storage: Any, event: Event) -> None:
    """`BoxController.emit`: zapíše zavření kóje po vrácení / zavření šatny, vyjetí motorky záznam kóje maže."""
    bid = str(event.booking_id or "")
    if storage is None or not bid or not event.success \
            or event.kind not in (EventKind.SESSION_COMPLETED, EventKind.ACCESS_GRANTED):
        return
    d = event.detail or {}
    if d.get("temp") or d.get("emergency"):
        return
    phase = d.get("odometer_phase")
    if event.kind == EventKind.ACCESS_GRANTED:
        key = "drop" if event.code_kind == "motorcycle" and phase == "out" else None
    elif event.code_kind == "motorcycle":
        key = "bay" if phase == "in" else None
    else:
        key = "locker" if event.code_kind == "accessories" else None
    if key is None:
        return
    now = time.time()
    data = _load(storage, now)
    rec = data["b"].setdefault(bid, {})
    if key == "drop":
        if rec.pop("bay", None) is None:
            return
        log.info("return_gate: motorka rezervace %s znovu vyjela — záznam vrácení zrušen", bid)
        if not rec:
            data["b"].pop(bid, None)
    else:
        t = _ts(event.ts)
        rec[key] = t if t is not None else now
    storage.kv_set(KV, data)


def blocks(ctrl: Any, rr: Any, now: float | None = None) -> bool:
    """True = OFFLINE kód rezervace vrácené v poslední den už doběhl → odmítnout (`code_revoked`)."""
    bid = str(getattr(rr, "booking_id", None) or "")
    if not rr.ok or not rr.offline or rr.is_service or getattr(rr, "temp", False) or not bid:
        return False
    final = _ts(getattr(rr, "return_final_from", None))
    if final is None:
        return False
    now = time.time() if now is None else now
    try:
        rec = _load(ctrl.storage, now)["b"].get(bid) or {}
    except Exception:  # noqa: BLE001 — pomůcka offline režimu, ověření kódu nesmí shodit (fail-open)
        log.exception("return_gate: čtení záznamu vrácení selhalo")
        return False
    bay = rec.get("bay")
    if bay is None or bay < final:
        return False                      # bez vrácení / zaparkováno před posledním dnem = kódy platí dál
    if rr.kind == "motorcycle":
        return now > bay + grace_s(ctrl)
    if rr.kind == "accessories":
        lk = rec.get("locker")
        return lk is not None and lk >= bay - VISIT_S and now > max(lk, bay) + grace_s(ctrl)
    return False


async def refuse(ctrl: Any, rr: Any, source: str) -> None:
    """ACCESS_DENIED (info) do Velína — kód je známý, jen už doběhl (bez lockoutu; odpověď UI skládá `submit_code`)."""
    rec = record(ctrl.storage, rr.booking_id)
    closed = datetime.fromtimestamp(rec["bay"], timezone.utc).isoformat(timespec="seconds") if rec.get("bay") else None
    await ctrl.emit(Event(kind=EventKind.ACCESS_DENIED, success=False, level="info", code_kind=rr.kind or None,
                          door_id=rr.door_id, booking_id=rr.booking_id, box_number=rr.box_number,
                          message="Kód odmítnut — motorka vrácena v poslední den, kód už doběhl (offline)",
                          detail={"source": source, "reason": REASON, "error": ERROR, "closed_at": closed,
                                  "return_final_from": rr.return_final_from, "offline": True}))


__all__ = ["KV", "ERROR", "REASON", "VISIT_S", "grace_s", "observe", "blocks", "refuse", "record"]
