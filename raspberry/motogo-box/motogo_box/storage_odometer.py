"""Trvalá fronta stavů tachometru při vrácení (`odometer.py`, CONTRACT §30) — mixin `Storage`.

Tabulka ``odometer_queue`` (jedno čtení = jeden řádek, klíč = `reading_id` uuid4 z jednotky = `p_reading_id` RPC
`kiosk_submit_odometer`, idempotentní). Stejně jako ``protocol_queue`` se NIKDY nemaže limitem pokusů ani přetečením —
stav tachometru, kvůli kterému se otevřela kóje, se nesmí ztratit (trvalé odmítnutí = ``failed``, znovu po „Znovu
synchronizovat“). Řádky ``pending`` = NEodeslaná čtení: zvedají spodní mez dalšího vrácení téže motorky a km do
protokolu dalšího převzetí (`odometer_queue_max_km`); po potvrzení serverem se mažou (pak platí jen server — korekce
nájezdu ve Velíně se tak vždy projeví). ``failed`` (server čtení trvale odmítl) meze NEovlivňuje — jinak by ho korekce
ve Velíně nikdy nepřebila a zákazník by u další výpůjčky zůstal zamčený.
"""
from __future__ import annotations

import json
import time
from typing import Any

ODOMETER_SCHEMA = """
CREATE TABLE IF NOT EXISTS odometer_queue (
    reading_id   TEXT PRIMARY KEY,
    booking_id   TEXT NOT NULL,
    moto_id      TEXT,
    km           INTEGER NOT NULL,
    payload_json TEXT NOT NULL,
    created_at   REAL NOT NULL,
    attempts     INTEGER NOT NULL DEFAULT 0,
    last_error   TEXT,
    status       TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX IF NOT EXISTS odometer_queue_moto ON odometer_queue (moto_id);
"""


class OdometerQueueMixin:
    """Metody fronty nad `self._db` / `self._lock` / `self._write_with_kv` třídy `Storage` (synchronní, thread-safe)."""

    _db: Any
    _lock: Any
    _write_with_kv: Any

    def odometer_queue_put(self, reading_id: str, booking_id: str, moto_id: str | None, km: int, payload: dict,
                           kv: tuple[str, Any] | None = None) -> None:
        """Uloží čtení (duplicitní `reading_id` se ignoruje) a volitelně v TÉŽE transakci kv (stav `OdometerManager`)."""
        self._write_with_kv(
            "INSERT INTO odometer_queue (reading_id, booking_id, moto_id, km, payload_json, created_at, attempts, "
            "last_error, status) VALUES (?, ?, ?, ?, ?, ?, 0, NULL, 'pending') ON CONFLICT(reading_id) DO NOTHING",
            (str(reading_id), str(booking_id), str(moto_id) if moto_id else None, int(km),
             json.dumps(payload, ensure_ascii=False, default=str), time.time()), kv)

    def odometer_queue_pending(self, limit: int = 20) -> list[dict]:
        """Čekající čtení (nejstarší první): ``{reading_id, booking_id, moto_id, km, payload, attempts, created_at}``."""
        with self._lock:
            rows = self._db.execute(
                "SELECT reading_id, booking_id, moto_id, km, payload_json, attempts, created_at FROM odometer_queue "
                "WHERE status = 'pending' ORDER BY created_at LIMIT ?", (int(limit),)).fetchall()
        out: list[dict] = []
        for r in rows:
            try:
                payload = json.loads(r["payload_json"])
            except (TypeError, ValueError):
                payload = {}
            out.append({"reading_id": str(r["reading_id"]), "booking_id": str(r["booking_id"]), "moto_id": r["moto_id"],
                        "km": int(r["km"]), "payload": payload if isinstance(payload, dict) else {},
                        "attempts": int(r["attempts"]), "created_at": float(r["created_at"])})
        return out

    def odometer_queue_done(self, reading_id: str) -> None:
        with self._lock:
            self._db.execute("DELETE FROM odometer_queue WHERE reading_id = ?", (str(reading_id),))

    def odometer_queue_fail(self, reading_id: str, error: str, permanent: bool) -> None:
        """Neúspěšný pokus: čítač + chyba; trvalé odmítnutí → ``failed`` (zůstává, neodeslané čtení platí dál)."""
        with self._lock:
            self._db.execute(
                "UPDATE odometer_queue SET attempts = attempts + 1, last_error = ?, status = ? WHERE reading_id = ?",
                (str(error or "")[:500], "failed" if permanent else "pending", str(reading_id)))

    def odometer_queue_retry_failed(self) -> int:
        """Trvale odmítnutá čtení znovu do fronty (Velín „Znovu synchronizovat“ po opravě)."""
        with self._lock:
            cur = self._db.execute("UPDATE odometer_queue SET status = 'pending' WHERE status = 'failed'")
            return int(cur.rowcount or 0)

    def odometer_queue_max_km(self, moto_id: str | None) -> int | None:
        """Nejvyšší čekající (``pending``) stav motorky; ``failed`` se nepočítá (server ho odmítl); None = žádný."""
        if not moto_id:
            return None
        with self._lock:
            row = self._db.execute("SELECT MAX(km) FROM odometer_queue WHERE moto_id = ? AND status = 'pending'",
                                   (str(moto_id),)).fetchone()
        return None if row is None or row[0] is None else int(row[0])

    def odometer_queue_status(self) -> dict:
        """``{pending: [booking_id…], failed: [booking_id…]}`` pro snapshot / Velín (jako protocol_queue_status)."""
        with self._lock:
            rows = self._db.execute("SELECT booking_id, status FROM odometer_queue ORDER BY created_at").fetchall()
        out: dict[str, list[str]] = {"pending": [], "failed": []}
        for r in rows:
            out["failed" if r["status"] == "failed" else "pending"].append(str(r["booking_id"]))
        return out
