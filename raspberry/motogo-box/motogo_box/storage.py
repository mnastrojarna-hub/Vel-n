"""Lokální SQLite úložiště MotoGo Boxu (kontrakt §7).

Jedna databáze `<data_dir>/motogo.db` (WAL) s tabulkami:

- ``kv``            — obecné klíč/hodnota (JSON): device_id/token, remote_config, lockout…
- ``code_cache``    — poslední payload `kiosk_sync_config` / `kiosk_sync_codes` (offline ověřování)
- ``outbox``        — fronta neodeslaných RPC (log_open, log_event, complete_command)
- ``pin_attempts``  — historie pokusů o PIN (lockout dle §10)
- ``events``        — lokální audit událostí, ring buffer (max ``EVENTS_MAX``)

Modul je synchronní (``sqlite3``); volání jsou krátká a chráněná zámkem, takže je
lze bezpečně volat i z různých vláken (``check_same_thread=False``).
"""
from __future__ import annotations

import json
import logging
import sqlite3
import threading
import time
from typing import Any

from .models import Event

log = logging.getLogger("motogo.storage")

EVENTS_MAX = 5000            # ring buffer událostí
OUTBOX_MAX_ATTEMPTS = 50     # po více pokusech se položka zahodí
OUTBOX_MAX = 3000            # strop fronty: nad ním se zahazují nejstarší log_event (audit dveří zůstává)
PIN_ATTEMPTS_KEEP_S = 7 * 24 * 3600   # starší pokusy se průběžně mažou
KV_LOCKOUT_UNTIL = "pin_lockout_until"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS kv (
    key        TEXT PRIMARY KEY,
    value_json TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS code_cache (
    id           INTEGER PRIMARY KEY CHECK (id = 1),
    payload_json TEXT NOT NULL,
    saved_at     REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS outbox (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    kind         TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    attempts     INTEGER NOT NULL DEFAULT 0,
    created_at   REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS pin_attempts (
    id     INTEGER PRIMARY KEY AUTOINCREMENT,
    ts     REAL NOT NULL,
    ok     INTEGER NOT NULL,
    masked TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS pin_attempts_ts ON pin_attempts (ts);
CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ts          TEXT NOT NULL,
    kind        TEXT NOT NULL,
    zone        INTEGER,
    door_id     TEXT,
    booking_id  TEXT,
    success     INTEGER NOT NULL DEFAULT 1,
    level       TEXT NOT NULL DEFAULT 'info',
    message     TEXT NOT NULL DEFAULT '',
    detail_json TEXT NOT NULL DEFAULT '{}'
);
"""


def _dumps(value: Any) -> str:
    """JSON serializace tolerantní k datům, která json neumí (datetime, dataclass…)."""
    return json.dumps(value, ensure_ascii=False, default=str)


def _loads(text: str | None, default: Any = None) -> Any:
    if text is None:
        return default
    try:
        return json.loads(text)
    except (TypeError, ValueError):
        log.warning("Poškozený JSON v databázi: %.80r", text)
        return default


class Storage:
    """SQLite úložiště; všechny metody jsou synchronní a thread-safe."""

    def __init__(self, path: str) -> None:
        self.path = path
        self._lock = threading.RLock()
        self._db = sqlite3.connect(path, check_same_thread=False, isolation_level=None, timeout=10)
        self._db.row_factory = sqlite3.Row
        try:
            self._db.execute("PRAGMA journal_mode=WAL")
            self._db.execute("PRAGMA synchronous=NORMAL")
        except sqlite3.DatabaseError as exc:   # např. read-only FS — DB stále funguje bez WAL
            log.warning("PRAGMA selhalo (%s), pokračuji bez WAL", exc)
        self._db.executescript(_SCHEMA)
        log.debug("Storage otevřeno: %s", path)

    # ─── kv ──────────────────────────────────────────────────────────────────
    def kv_get(self, key: str, default: Any = None) -> Any:
        with self._lock:
            row = self._db.execute("SELECT value_json FROM kv WHERE key = ?", (key,)).fetchone()
        return default if row is None else _loads(row["value_json"], default)

    def kv_set(self, key: str, value: Any) -> None:
        with self._lock:
            self._db.execute(
                "INSERT INTO kv (key, value_json) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json",
                (key, _dumps(value)),
            )

    def kv_delete(self, key: str) -> None:
        with self._lock:
            self._db.execute("DELETE FROM kv WHERE key = ?", (key,))

    # ─── cache kódů ──────────────────────────────────────────────────────────
    def save_code_cache(self, payload: dict) -> None:
        with self._lock:
            self._db.execute(
                "INSERT INTO code_cache (id, payload_json, saved_at) VALUES (1, ?, ?) "
                "ON CONFLICT(id) DO UPDATE SET payload_json = excluded.payload_json, "
                "saved_at = excluded.saved_at",
                (_dumps(payload), time.time()),
            )

    def load_code_cache(self) -> dict | None:
        with self._lock:
            row = self._db.execute("SELECT payload_json FROM code_cache WHERE id = 1").fetchone()
        if row is None:
            return None
        data = _loads(row["payload_json"])
        return data if isinstance(data, dict) else None

    def code_cache_saved_at(self) -> float | None:
        """Unix čas posledního uložení cache (None = cache není)."""
        with self._lock:
            row = self._db.execute("SELECT saved_at FROM code_cache WHERE id = 1").fetchone()
        return None if row is None else float(row["saved_at"])

    # ─── outbox ──────────────────────────────────────────────────────────────
    def outbox_add(self, kind: str, payload: dict) -> int:
        with self._lock:
            cur = self._db.execute(
                "INSERT INTO outbox (kind, payload_json, attempts, created_at) VALUES (?, ?, 0, ?)",
                (kind, _dumps(payload), time.time()),
            )
            oid = int(cur.lastrowid or 0)
            n = int(self._db.execute("SELECT COUNT(*) FROM outbox").fetchone()[0])
            if n > OUTBOX_MAX:
                # nejdřív nejstarší log_event (diagnostika), audit otevření a potvrzení příkazů až nakonec
                self._db.execute(
                    "DELETE FROM outbox WHERE id IN (SELECT id FROM outbox ORDER BY "
                    "CASE kind WHEN 'log_event' THEN 0 ELSE 1 END, id LIMIT ?)", (n - OUTBOX_MAX,))
                log.warning("Outbox přetekl (%d) — nejstarší položky zahozeny", n)
        log.debug("Outbox +%s (#%d)", kind, oid)
        return oid

    def outbox_pending(self, limit: int = 50) -> list[tuple[int, str, dict]]:
        with self._lock:
            rows = self._db.execute(
                "SELECT id, kind, payload_json FROM outbox ORDER BY id LIMIT ?", (int(limit),)
            ).fetchall()
        out: list[tuple[int, str, dict]] = []
        for r in rows:
            payload = _loads(r["payload_json"], {})
            out.append((int(r["id"]), str(r["kind"]), payload if isinstance(payload, dict) else {}))
        return out

    def outbox_count(self) -> int:
        with self._lock:
            return int(self._db.execute("SELECT COUNT(*) FROM outbox").fetchone()[0])

    def outbox_done(self, oid: int) -> None:
        with self._lock:
            self._db.execute("DELETE FROM outbox WHERE id = ?", (int(oid),))

    def outbox_fail(self, oid: int) -> None:
        """Zvýší počet pokusů; po překročení ``OUTBOX_MAX_ATTEMPTS`` položku zahodí."""
        with self._lock:
            self._db.execute("UPDATE outbox SET attempts = attempts + 1 WHERE id = ?", (int(oid),))
            row = self._db.execute("SELECT attempts FROM outbox WHERE id = ?", (int(oid),)).fetchone()
            if row is not None and int(row["attempts"]) > OUTBOX_MAX_ATTEMPTS:
                self._db.execute("DELETE FROM outbox WHERE id = ?", (int(oid),))
                log.warning("Outbox #%d zahozen po %d pokusech", oid, row["attempts"])

    # ─── PIN pokusy / lockout ───────────────────────────────────────────────
    def pin_attempt(self, ok: bool, masked: str, ts: float | None = None) -> None:
        now = time.time() if ts is None else float(ts)
        with self._lock:
            self._db.execute(
                "INSERT INTO pin_attempts (ts, ok, masked) VALUES (?, ?, ?)",
                (now, 1 if ok else 0, masked or ""),
            )
            self._db.execute("DELETE FROM pin_attempts WHERE ts < ?", (now - PIN_ATTEMPTS_KEEP_S,))

    def pin_failures_since(self, since_ts: float) -> int:
        with self._lock:
            row = self._db.execute(
                "SELECT COUNT(*) FROM pin_attempts WHERE ok = 0 AND ts >= ?", (float(since_ts),)
            ).fetchone()
        return int(row[0])

    def lockout_until(self) -> float | None:
        value = self.kv_get(KV_LOCKOUT_UNTIL)
        try:
            return None if value is None else float(value)
        except (TypeError, ValueError):
            return None

    def set_lockout_until(self, ts: float | None) -> None:
        if ts is None:
            self.kv_delete(KV_LOCKOUT_UNTIL)
        else:
            self.kv_set(KV_LOCKOUT_UNTIL, float(ts))

    # ─── události (ring buffer) ─────────────────────────────────────────────
    def event_add(self, event: Event) -> None:
        with self._lock:
            self._db.execute(
                "INSERT INTO events (ts, kind, zone, door_id, booking_id, success, level, message, detail_json) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    event.ts, event.kind.value, event.zone, event.door_id, event.booking_id,
                    1 if event.success else 0, event.level or "info", event.message or "",
                    _dumps(event.detail or {}),
                ),
            )
            self._db.execute(
                "DELETE FROM events WHERE id <= (SELECT MAX(id) FROM events) - ?", (EVENTS_MAX,)
            )

    def events_recent(self, limit: int = 100) -> list[dict]:
        """Nejnovější události (nejnovější první) jako slovníky pro UI/API."""
        with self._lock:
            rows = self._db.execute(
                "SELECT id, ts, kind, zone, door_id, booking_id, success, level, message, detail_json "
                "FROM events ORDER BY id DESC LIMIT ?", (int(limit),)
            ).fetchall()
        return [
            {
                "id": int(r["id"]), "ts": r["ts"], "kind": r["kind"], "zone": r["zone"],
                "door_id": r["door_id"], "booking_id": r["booking_id"], "success": bool(r["success"]),
                "level": r["level"], "message": r["message"], "detail": _loads(r["detail_json"], {}),
            }
            for r in rows
        ]

    def events_count(self) -> int:
        with self._lock:
            return int(self._db.execute("SELECT COUNT(*) FROM events").fetchone()[0])

    # ─── životní cyklus ─────────────────────────────────────────────────────
    def close(self) -> None:
        with self._lock:
            try:
                self._db.close()
            except sqlite3.Error as exc:
                log.warning("Zavření DB selhalo: %s", exc)
