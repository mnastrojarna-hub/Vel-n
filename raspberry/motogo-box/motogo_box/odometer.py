"""Stav tachometru při VRÁCENÍ motorky na samoobslužné pobočce (rozhodnutí majitele 2026-09-29, CONTRACT §30).

Kód motorky při vracení → displej chce stav tachometru (číselník; nápověda = poslední známý stav) a bez platné hodnoty
se kóje NEotevře. Při převzetí se km nikdy nezadávají — do protokolu je dá jednotka sama (`pickup_mileage`).
Vrácení vs. převzetí rozhoduje JEDNOTKA fázovým automatem rezervace (SQLite kv `odometer`): `out` = motorka u zákazníka,
`in` = v kóji, `at` = čas poslední změny fáze.
  * otevření kóje bez fáze / ve fázi `in` = převzetí → `out`; kód ve fázi `out` po ≥ `timings.odometer_grace_min` (60 min)
    = vrácení → výzva → platná hodnota → `in`. Opakovaný kód do grace od změny fáze = bez výzvy, fáze beze změny
    (zapomenutá věc). Vícedenní pronájem s parkováním v kóji: km při KAŽDÉM zaparkování, nikdy při vyjetí.
  * lokální stav má přednost; bez něj důkazy serveru z bloku `odo` (`last_open_at`/`last_open_phase` z ACCESS_GRANTED
    detailu, `delivered`/`delivered_at` = přistavení / SOS); bez důkazu → bez výzvy (fail-open jako dosud).
Hranice a důkazy → `odometer_rules.py` (shodně se SQL `_kiosk_odometer`). Platný stav se NEJDŘÍV trvale uloží
(`Storage.odometer_queue` + kv v jedné transakci), pak se kóje otevře; odesílání RPC → `odometer_queue.py`.
"""
from __future__ import annotations

import asyncio
import logging
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Callable

from . import controller_codes as cc
from . import odometer_queue as oq
from .models import Event, EventKind
from .odometer_rules import (OdoPlan, OdoPrompt, bounds, evidence, pos_int, rental_days, unit_label,  # noqa: F401
                             validate)

log = logging.getLogger("motogo.odometer")

KV = "odometer"
KEEP_S = 60 * 86400          # stav rezervace drží jednotka po dobu nejdelšího pronájmu (jako handover_locker)
RETRY_GRANT_S = 600          # stav uložen, kóje se neotevřela → opakovaný kód do 10 min otevře bez nové výzvy
RECENT_ACK_S = 300           # přijaté čtení drží km převzetí téže motorky, než sync (á 60 s) přinese nové `data.mileage`
DEFAULT_GRACE_MIN = 60


class OdometerManager:
    """Fázový automat + hranice + trvalá fronta stavů tachometru (`ctrl.odometer`)."""

    def __init__(self, ctrl: Any, clock: Callable[[], float] = time.time) -> None:
        self.ctrl, self.clock = ctrl, clock
        self.wake = asyncio.Event()              # probudí odometer_loop (nové čtení / obnovené spojení / retry)
        self.inflight: set[str] = set()
        self.recent: dict[str, tuple[int, float]] = {}   # moto_id → (km, čas) čtení přijatých serverem (jen km převzetí)
        self.queue_state: dict = {"pending": [], "failed": []}
        self.refresh_queue()

    # ─── stav ────────────────────────────────────────────────────────────────
    @property
    def grace_s(self) -> float:
        t = getattr(getattr(self.ctrl, "hardware", None), "timings", None)
        try:
            return 60.0 * max(0, int(getattr(t, "odometer_grace_min", DEFAULT_GRACE_MIN)))
        except (TypeError, ValueError):
            return 60.0 * DEFAULT_GRACE_MIN

    def _load(self, now: float) -> dict:
        raw = self.ctrl.storage.kv_get(KV) or {}
        rows = raw.get("b") if isinstance(raw, dict) and isinstance(raw.get("b"), dict) else {}
        return {"b": {str(k): v for k, v in rows.items() if isinstance(v, dict) and v.get("phase") in ("out", "in")
                      and isinstance(v.get("at"), (int, float)) and now - float(v["at"]) <= KEEP_S}}

    def _local(self, booking_id: str, now: float | None = None) -> dict:
        return self._load(self.clock() if now is None else now)["b"].get(str(booking_id or "")) or {}

    def refresh_queue(self) -> None:
        fn = getattr(self.ctrl.storage, "odometer_queue_status", None)
        if fn is not None:
            self.queue_state = fn()

    def _unacked_km(self, moto_id: str | None) -> int | None:
        fn = getattr(self.ctrl.storage, "odometer_queue_max_km", None)
        try:
            return fn(moto_id) if fn is not None and moto_id else None
        except Exception:  # noqa: BLE001 — pomůcka hranice, otevření nesmí shodit
            log.exception("odometer: čtení fronty selhalo")
            return None

    # ─── rozhodnutí ──────────────────────────────────────────────────────────
    def plan(self, rr: Any, now: float | None = None) -> OdoPlan | None:
        """Kód motorky s rezervací → `OdoPlan`; jiný kód → None. Chyba = None (fail-open, kóje jako dosud)."""
        bid = str(getattr(rr, "booking_id", None) or "")
        if getattr(rr, "kind", "") != "motorcycle" or not bid:
            return None
        now = self.clock() if now is None else now
        try:
            return self._plan(bid, rr, now)
        except Exception:  # noqa: BLE001
            log.exception("odometer: rozhodnutí pro rezervaci %s selhalo — bez výzvy", bid)
            return None

    def _plan(self, bid: str, rr: Any, now: float) -> OdoPlan:
        odo = rr.odo if isinstance(getattr(rr, "odo", None), dict) else None
        proto = rr.protocol if isinstance(getattr(rr, "protocol", None), dict) else {}
        local = self._local(bid, now)
        phase, at = (local["phase"], float(local["at"])) if local else evidence(odo)
        unit_raw = (odo or {}).get("unit") or (proto.get("data") or {}).get("mileage_unit") or local.get("unit")
        p = OdoPlan(bid, phase, at, moto_id=str((odo or {}).get("moto_id") or proto.get("moto_id")
                                                or local.get("moto_id") or "") or None,
                    unit="mh" if unit_raw == "mh" else "km")
        un = local.get("unopened")
        if isinstance(un, dict) and un.get("rid") and now - float(un.get("ts") or 0) < RETRY_GRANT_S:
            p.phase_after, p.reading = "in", {"reading_id": un["rid"], "km": un.get("km"), "unit": p.unit}
            return p
        if phase is None or at is None:
            return p                              # bez důkazu o převzetí = převzetí (fail-open, km se nechtějí)
        if now - at < self.grace_s:
            p.phase_after = phase                 # opakovaný kód v grace: bez výzvy, fáze beze změny
            return p
        if phase == "in":
            return p                              # zaparkováno v kóji (vícedenní) → vyjíždí znovu, bez výzvy
        p.phase_after = "in"
        hint, lo, hi, days = bounds(odo, local, p.unit, self._unacked_km(p.moto_id), now)
        p.prompt = OdoPrompt(bid, p.unit, hint, lo, hi, days)
        return p

    async def gate(self, plan: OdoPlan, rr: Any, zc: Any, source: str, value: Any, base: dict) -> dict | None:
        """Hradlo vrácení v `submit_code` (hned po nalezení zóny): None = pustit dál (platný stav je už uložen
        v `plan.reading`), jinak odpověď `/api/pin` — `odometer_required` / `odometer_invalid` (bez lockoutu)."""
        pr = plan.prompt
        if pr is None:
            return None
        pr.zone = zc.number
        out = {**base, "kind": "motorcycle", "zone": zc.number, "booking_id": plan.booking_id, "odometer": pr.public()}
        if value is None or str(value).strip() == "":
            return {**out, "error": "odometer_required", "message": cc.error_text("odometer_required")}
        km, why = validate(pr, value)
        if km is None:
            await self.ctrl.emit(Event(
                kind=EventKind.ODOMETER_REJECTED, success=False, level="warn", code_kind="motorcycle", zone=zc.number,
                door_id=zc.zone.door_id, booking_id=plan.booking_id, box_number=zc.zone.box_number,
                message=f"{zc.zone.display_name}: stav tachometru odmítnut ({why}) — kóje zůstává zavřená",
                detail={"source": source, "reason": why, "value": str(value)[:12], "min": pr.min, "max": pr.max,
                        "days": pr.days, "unit": pr.unit, "offline": bool(rr.offline)}))
            return {**out, "error": "odometer_invalid", "reason": why, "message": cc.error_text("odometer_invalid")}
        plan.reading = await self.record(plan, km, source, bool(rr.offline))
        return None

    # ─── zápis ───────────────────────────────────────────────────────────────
    async def record(self, plan: OdoPlan, km: int, source: str, offline: bool) -> dict:
        """Platný stav: fronta + kv (`unopened`) v JEDNÉ transakci, událost, probuzení odesílání."""
        now, rid, pr = self.clock(), str(uuid.uuid4()), plan.prompt
        info = {"zone": pr.zone if pr else None, "min": pr.min if pr else None, "max": pr.max if pr else None,
                "days": pr.days if pr else None, "unit": plan.unit}
        payload = {"p_reading_id": rid, "p_booking_id": plan.booking_id, "p_km": int(km),
                   "p_recorded_at": datetime.fromtimestamp(now, timezone.utc).isoformat(timespec="seconds"),
                   "p_detail": {"source": source, "offline": offline, **info}}
        data = self._load(now)
        st = dict(data["b"].get(plan.booking_id) or {"phase": plan.phase or "out",
                                                      "at": plan.at if plan.at is not None else now})
        st.update(unit=plan.unit, last_km=int(km), last_at=now, unopened={"km": int(km), "rid": rid, "ts": now})
        if plan.moto_id:
            st["moto_id"] = plan.moto_id
        data["b"][plan.booking_id] = st
        stored = True
        try:
            self.ctrl.storage.odometer_queue_put(rid, plan.booking_id, plan.moto_id, int(km), payload, kv=(KV, data))
        except Exception:  # noqa: BLE001 — disk: kóji přesto otevřít (hodnota je platná), km zůstane aspoň v logu
            log.exception("odometer: uložení stavu tachometru selhalo")
            stored = False
        self.refresh_queue()
        await self.ctrl.emit(Event(
            kind=EventKind.ODOMETER_RECORDED, success=stored, level="info" if stored else "error",
            zone=info["zone"], booking_id=plan.booking_id, code_kind="motorcycle",
            message=f"Stav tachometru při vrácení: {km} {unit_label(plan.unit)}" + ("" if stored else " — NEULOŽEN"),
            detail={"source": source, "reading_id": rid, "km": int(km), "offline": offline, "stored": stored, **info}))
        self.wake.set()
        return {"reading_id": rid, "km": int(km), "unit": plan.unit}

    @staticmethod
    def grant_detail(plan: OdoPlan) -> dict:
        """Klíče do ACCESS_GRANTED (→ branch_door_events.detail; server z nich bere `last_open_phase`)."""
        d: dict = {"odometer_phase": plan.phase_after}
        if plan.reading:
            d.update(odometer_km=plan.reading.get("km"), odometer_reading_id=plan.reading.get("reading_id"))
        return d

    def commit_open(self, plan: OdoPlan, *, protocol: dict | None = None, now: float | None = None) -> None:
        """Kóje motorky otevřena: fáze → `phase_after` (čas jen při změně / prvním lokálním stavu), při převzetí
        start_km (km z protokolu) + start_at, `unopened` pryč."""
        now = self.clock() if now is None else now
        try:
            data = self._load(now)
            st = dict(data["b"].get(plan.booking_id) or {})
            changed = plan.phase != plan.phase_after or plan.at is None
            st.update(phase=plan.phase_after, at=now if changed else plan.at, unit=plan.unit)
            if plan.phase_after == "out" and plan.phase != "out":
                st.setdefault("start_at", now)
                km = self.pickup_mileage((protocol or {}).get("data"), plan.moto_id)   # = km v protokolu převzetí
                if km is not None:
                    st.setdefault("start_km", km)
            if plan.moto_id:
                st["moto_id"] = plan.moto_id
            st.pop("unopened", None)
            data["b"][plan.booking_id] = st
            self.ctrl.storage.kv_set(KV, data)
        except Exception:  # noqa: BLE001 — stav fáze je pomůcka, otevřené dveře nesmí shodit
            log.exception("odometer: uložení fáze rezervace %s selhalo", plan.booking_id)

    def on_pickup_opened(self, booking_id: str | None, data: dict | None = None, moto_id: str | None = None,
                         now: float | None = None) -> None:
        """Kóje otevřena po podpisu protokolu (handover_submit.open_zone) = převzetí → fáze `out`."""
        bid = str(booking_id or "")
        if not bid:
            return
        now = self.clock() if now is None else now
        local = self._local(bid, now)
        unit = "mh" if (data or {}).get("mileage_unit") == "mh" or local.get("unit") == "mh" else "km"
        plan = OdoPlan(bid, local.get("phase"), local.get("at"), phase_after="out",
                       moto_id=moto_id or local.get("moto_id"), unit=unit)
        self.commit_open(plan, protocol={"data": data or {}}, now=now)

    # ─── převzetí, šatna, snapshot ───────────────────────────────────────────
    def pickup_mileage(self, data: dict | None, moto_id: str | None) -> int | None:
        """Km do protokolu převzetí = max(data.mileage ze serveru, NEodeslaný stav vrácení téže motorky z fronty,
        stav přijatý serverem před < RECENT_ACK_S). Poslední člen kryje okno „čtení odešlo (řádek fronty zmizel), ale
        `data.mileage` na displeji / v cache je ještě z doby před zápisem“ (po obnově LTE jde sync PŘED odesláním fronty)
        — edge v režimu kiosk bere hodnotu jednotky, zastaralé nižší km by jinak vyhrálo."""
        rec = self.recent.get(str(moto_id or ""))
        fresh = rec[0] if rec is not None and 0 <= self.clock() - rec[1] < RECENT_ACK_S else None
        vals = [v for v in (pos_int((data or {}).get("mileage")), self._unacked_km(moto_id), fresh) if v is not None]
        return max(vals) if vals else None

    def note_accepted(self, moto_id: str | None, km: Any) -> None:
        """`odometer_queue.upload_one`: server čtení přijal (accepted) → km převzetí ho drží ještě RECENT_ACK_S (mez ne)."""
        k = pos_int(km)
        if not moto_id or k is None:
            return
        now, prev = self.clock(), self.recent.get(str(moto_id))
        self.recent = {m: v for m, v in self.recent.items() if 0 <= now - v[1] < RECENT_ACK_S}
        self.recent[str(moto_id)] = (max(k, prev[0]) if prev is not None and 0 <= now - prev[1] < RECENT_ACK_S else k, now)

    def returned(self, booking_id: str | None) -> bool:
        """Motorka rezervace je (podle jednotky) v kóji — zavření šatny pak není převzetí (bez zámku / toastu)."""
        try:
            return self._local(str(booking_id or "")).get("phase") == "in"
        except Exception:  # noqa: BLE001
            return False

    def status(self) -> dict:
        return {"pending": list(self.queue_state.get("pending", [])), "failed": list(self.queue_state.get("failed", []))}

    def retry_failed(self) -> int:
        fn = getattr(self.ctrl.storage, "odometer_queue_retry_failed", None)
        n = int(fn() or 0) if fn is not None else 0
        self.refresh_queue()
        self.wake.set()
        return n

    async def flush(self) -> int:
        return await oq.flush(self)
