"""Odesílání stavů tachometru z trvalé fronty `Storage.odometer_queue` — pomocný modul `odometer.py` (CONTRACT §30).

RPC `kiosk_submit_odometer` přes kiosk RPC klienta (`SupabaseApi.submit_odometer`, auth device_id+token), mimo outbox
(outbox čtení po 50 pokusech zahazuje a 404 „RPC chybí“ bere jako trvalé — čtení musí přežít i nasazení jednotky dřív
než SQL). Kóje je v okamžiku odeslání UŽ otevřená — server čtení nikdy neodmítne kvůli hodnotě: `ok:true` se
`status: accepted | disputed` = hotovo (disputed = mimo serverový rozsah → jen evidence, varování do Velína).
Dočasné (zkusit znovu bez limitu): síť, 5xx, `unauthorized`, 401/403/408/429, 404/PGRST202 (RPC ještě není nasazená).
Trvalé (řádek zůstává `failed`, znovu po „Znovu synchronizovat“): `missing_inputs`, `invalid_km`, `not_found`,
`forbidden`, `conflict` a ostatní 4xx.
"""
from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from .models import Event, EventKind

if TYPE_CHECKING:  # pragma: no cover
    from .odometer import OdometerManager

log = logging.getLogger("motogo.odometer")

QUEUE_BATCH = 20


async def upload_one(om: "OdometerManager", row: dict) -> str:
    """Jeden pokus o odeslání řádku fronty: `saved` | `queued` (dočasná chyba) | `failed` (trvalé odmítnutí)."""
    ctrl, st = om.ctrl, om.ctrl.storage
    rid, bid, payload = row["reading_id"], row["booking_id"], row.get("payload") or {}
    res = await ctrl.api.submit_odometer(payload)
    if res.get("ok"):
        st.odometer_queue_done(rid)
        om.refresh_queue()
        if res.get("status") == "accepted":
            om.note_accepted(row.get("moto_id"), row.get("km"))   # km převzetí do dalšího syncu (odometer.RECENT_ACK_S)
        if res.get("status") == "disputed" and not res.get("duplicate"):
            await ctrl.emit(Event(kind=EventKind.ODOMETER_DISPUTED, success=False, level="warn", booking_id=bid,
                                  code_kind="motorcycle",
                                  message=f"Stav tachometru {row.get('km')} je podle serveru mimo věrohodný rozsah "
                                          f"({res.get('reason')}) — uložen jako sporný, bez zápisu do rezervace",
                                  detail={"source": "odometer_queue", "reading_id": rid, "booking_id": bid,
                                          "km": row.get("km"), "reason": res.get("reason")}))
        return "saved"
    permanent = bool(res.get("permanent"))
    st.odometer_queue_fail(rid, str(res.get("error") or ""), permanent)
    om.refresh_queue()
    if not permanent:
        om.wake.set()
        return "queued"
    await ctrl.emit(Event(kind=EventKind.ODOMETER_UPLOAD_FAILED, success=False, level="error", booking_id=bid,
                          code_kind="motorcycle",
                          message=f"Stav tachometru z kiosku odmítnut serverem ({res.get('error')})",
                          detail={"source": "odometer_queue", "error": res.get("error"), "reading_id": rid,
                                  "booking_id": bid, "km": row.get("km")}))
    return "failed"


async def flush(om: "OdometerManager") -> int:
    """`odometer_loop`: odešle čekající čtení (nejstarší první); při výpadku sítě / serveru končí hned."""
    sent = 0
    for row in om.ctrl.storage.odometer_queue_pending(QUEUE_BATCH):
        rid = row["reading_id"]
        if rid in om.inflight:
            continue
        om.inflight.add(rid)
        try:
            result = await upload_one(om, row)
        finally:
            om.inflight.discard(rid)
        if result == "queued":
            om.wake.clear()      # síť/server dole — další pokus za ODOMETER_FLUSH_S / po obnovení spojení
            break
        if result == "saved":
            sent += 1
    if sent:
        log.info("odometer_queue: odesláno %d stavů tachometru", sent)
    return sent
