"""Výpůjčka výbavy bez motorky na kiosku (1.3.0, rozhodnutí majitele 2026-10-22, CONTRACT §33) — pomocný modul `handover.py`.

Rezervace `booking_kind='gear'` má na pobočce jen kód šatny (kód brány je mimo kiosk): šatna je celé převzetí i vrácení.
* Převzetí: kód šatny → šatna (bez držení hudby a relace „do kódu motorky“, `controller_codes.submit_code`) → zavření →
  protokol jen s výbavou (velikosti + podpis, identita = kód šatny TÉŽE rezervace, `handover_submit._verify_code`) → kóje se
  neotvírá; zámek přejímky platí od zavření šatny do podpisu (displej / Velín) nebo do vypršení jako u motorky.
* Vrácení (varianta B): zavření šatny u PODEPSANÉ rezervace → dotaz „Vracíš všechnu výbavu?“ Ano / Ne, bez zámku přejímky.
  Ano → událost GEAR_RETURN_CONFIRMED (kiosk_log_open, kind accessories, `session_id` návštěvy šatny, `closed_ts` = zavření
  šatny, `offline`) → server rezervaci hned dokončí; offline `return_gate` kód šatny 15 min po zavření nevydá. Ne / bez odpovědi
  `ASK_S` → nic (výpůjčka běží dál). Výjimka: podepsáno jinde a server ví, že výbava ještě nebyla vyzvednuta
  (`protocol.gear_collected_at` null) → zavření šatny = převzetí → jen toast, bez dotazu.
Rozpoznání rezervace: `ResolveResult.gear_only` při grantu šatny (`visit`) nebo `protocol.gear_only` (RPC / sync cache).
"""
from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any

from . import gear_limits as gl
from . import return_gate
from .handover_lock import iso_ts
from .models import Event, EventKind, now_iso_ms

if TYPE_CHECKING:  # pragma: no cover
    from .handover import HandoverItem, HandoverManager

log = logging.getLogger("motogo.handover")

ASK_S = 120                 # dotaz na vrácení bez odpovědi zmizí (= Ne) — modální karta nesmí blokovat další zákazníky
VISIT_KEEP_S = 24 * 3600    # záznam návštěvy šatny (grant) — rozpoznání výbavy u zavření a text modální hlášky šatny
GEAR_KEYS = ("helmet", "jacket", "pants", "boots", "gloves")
LOCK_TEXT = ("Nejprve musí být dokončena předchozí přejímka — zákazník, který právě zavřel šatnu, podepisuje protokol. "
             "Pak přijdete na řadu.")


def protocol_gear(p: Any) -> bool:
    return isinstance(p, dict) and p.get("gear_only") is True


def catalog(p: Any) -> dict | None:
    """`protocol.sizes_catalog` = {helmet: [...], …} (velikosti z ceníku výpůjčky ∩ meze samoobsluhy) nebo None."""
    cat = p.get("sizes_catalog") if isinstance(p, dict) else None
    return {str(k): list(v) for k, v in cat.items() if isinstance(v, (list, tuple))} if isinstance(cat, dict) else None


def sizes_for(item: "HandoverItem", fallback: dict) -> dict:
    """Nabídka velikostí pro displej: výbava bez motorky z `sizes_catalog` (prohnaná `gear_limits` jako sync číselník),
    jinak (motorka / stará DB bez katalogu) `fallback` = `HandoverManager._sizes`."""
    cat = item.sizes_catalog if item.gear_only else None
    if not isinstance(cat, dict):
        return fallback
    return {k: gl.allowed_sizes(k, cat.get(k), False) for k in GEAR_KEYS}


class GearState:
    """Stav výbavy bez motorky v `HandoverManager` (`hm.gear`): návštěvy šatny a právě položený dotaz na vrácení.
    Nic z toho se nepersistuje — restart dotaz zahodí (= Ne, výpůjčka běží dál; nikdy nic nedokončí)."""

    def __init__(self, hm: "HandoverManager") -> None:
        self.hm = hm
        self.visits: dict[str, dict] = {}     # booking_id → {returning, offline, at}
        self.ask: dict | None = None

    # ─── rozpoznání ─────────────────────────────────────────────────────────
    def is_gear(self, booking_id: Any, p: Any = None) -> bool:
        bid = str(booking_id or "")
        item = self.hm.items.get(bid)
        return bool(bid) and (bid in self.visits or protocol_gear(p) or protocol_gear(self.hm.protocols.get(bid))
                              or bool(item is not None and item.gear_only))

    def _signed(self, bid: str, p: Any) -> bool:
        hm = self.hm
        return bid in hm.signed or hm.signed_local(bid) or (isinstance(p, dict) and not p.get("required"))

    def _first_pickup(self, bid: str, p: Any) -> bool:
        """Podepsáno jinde a server hlásí výbavu ještě nevyzvednutou (online `_kiosk_protocol`) → zavření = převzetí."""
        hm = self.hm
        return isinstance(p, dict) and not p.get("absent") and "gear_collected_at" in p \
            and not p.get("gear_collected_at") and bid not in hm.signed and not hm.signed_local(bid)

    def visit(self, rr: Any) -> None:
        """Grant kódu šatny (`HandoverManager.remember`): zapamatovat rezervaci výbavy a zda jde (podle stavu při grantu)
        o vrácení — jen pro text modální hlášky šatny; o dotazu rozhoduje až zavření (`closed`)."""
        bid = str(getattr(rr, "booking_id", None) or "")
        if not bid or not getattr(rr, "gear_only", False):
            return
        p = rr.protocol
        self.visits[bid] = {"returning": self._signed(bid, p) and not self._first_pickup(bid, p),
                            "offline": bool(rr.offline), "at": self.hm.clock()}

    # ─── zavření / znovuotevření šatny ───────────────────────────────────────
    async def closed(self, zone: int, bid: str, p: Any) -> tuple[bool, str | None]:
        """DOOR_CLOSED šatny rezervace výbavy. (True, výsledek) = vyřízeno tady (vrácení / podepsáno jinde / neznámý
        stav); (False, None) = nepodepsaný protokol → běžná cesta `on_wardrobe_closed` (zámek + overlay)."""
        hm = self.hm
        if self._signed(bid, p):
            if self._first_pickup(bid, p):
                hm._show_done(bid, zone, dict(p.get("data") or {}), gear_only=True)   # noqa: SLF001
                hm._save()   # noqa: SLF001
                return True, "done"
            self._ask(zone, bid, p)
            return True, "return_ask"
        if p is None:
            log.warning("handover: protocol_state_unknown (šatna výbavy zavřena, rezervace %s) — bez protokolu", bid)
            return True, None
        return False, None

    def _ask(self, zone: int, bid: str, p: Any) -> None:
        zc = self.hm._zone(zone)   # noqa: SLF001
        ctx = getattr(zc, "session_ctx", None) or {}
        data = (p.get("data") if isinstance(p, dict) else None) or {}
        self.ask = {"booking_id": bid, "zone": zone, "door_id": zc.zone.door_id if zc else None,
                    "box_number": zc.zone.box_number if zc else None, "session_id": ctx.get("session_id"),
                    "closed_ts": now_iso_ms(), "shown_at": self.hm.clock(),
                    "offline": bool((self.visits.get(bid) or {}).get("offline")),
                    "data": {k: data.get(k) for k in ("customer_name", "start_date", "end_date") if data.get(k)}}
        log.info("handover: šatna výbavy zavřena (rezervace %s) — dotaz na vrácení na displeji", bid)

    def reopened(self, zone: int, booking_id: Any) -> bool:
        """Šatna znovu otevřena v téže relaci → dotaz schovat (při dalším zavření se položí znovu)."""
        a = self.ask
        if a is None or a["booking_id"] != str(booking_id or "") or a["zone"] != zone:
            return False
        self.ask = None
        return True

    async def answer(self, booking_id: Any, yes: bool) -> dict:
        """`POST /api/gear/return` — Ano → GEAR_RETURN_CONFIRMED (jednou; dotaz se tím spotřebuje), Ne → nic."""
        a, bid = self.ask, str(booking_id or "")
        if a is None or a["booking_id"] != bid:
            return {"ok": False, "confirmed": False, "error": "not_pending"}
        self.ask = None
        if not yes:
            log.info("handover: rezervace %s — výbavu zatím nevrací (Ne)", bid)
            return {"ok": True, "confirmed": False, "error": None}
        offline = bool(a["offline"]) or not bool(getattr(getattr(self.hm.ctrl, "api", None), "online", True))
        await self.hm.ctrl.emit(Event(
            kind=EventKind.GEAR_RETURN_CONFIRMED, zone=a["zone"], door_id=a["door_id"], booking_id=bid,
            box_number=a["box_number"], code_kind="accessories", message="Vrácení výbavy potvrzeno na displeji",
            detail={"source": "kiosk", "session_id": a["session_id"], "closed_ts": a["closed_ts"], "offline": offline}))
        log.info("handover: rezervace %s — vrácení výbavy potvrzeno na displeji", bid)
        return {"ok": True, "confirmed": True, "error": None}

    # ─── čas a snapshot ─────────────────────────────────────────────────────
    def asking(self, now: float) -> bool:
        return self.ask is not None and now - self.ask["shown_at"] < ASK_S

    def tick(self, now: float) -> None:
        if self.ask is not None and now - self.ask["shown_at"] >= ASK_S:
            log.info("handover: dotaz na vrácení výbavy (rezervace %s) bez odpovědi — výpůjčka běží dál",
                     self.ask["booking_id"])
            self.ask = None
        for bid in [b for b, v in self.visits.items() if now - v["at"] > VISIT_KEEP_S]:
            del self.visits[bid]

    def lock_status(self, lock: dict | None) -> dict | None:
        """Snapshot zámku přejímky + `gear_only` (UI: pruh „zákazník podepisuje protokol“ místo „zadá kód motorky“)."""
        return {**lock, "gear_only": True} if lock and self.is_gear(lock.get("booking_id")) else lock

    def status(self, now: float) -> dict | None:
        """`handover.gear` (§14): `return` = dotaz na vrácení (nebo null), `visits` = návštěvy šatny (pickup | return);
        None = žádná výpůjčka výbavy (klíč se do snapshotu nedává — rezervace s motorkou mají snapshot beze změny)."""
        a = self.ask if self.asking(now) else None
        if a is None and not self.visits:
            return None
        ret = None if a is None else {
            "booking_id": a["booking_id"], "zone": a["zone"], "data": dict(a["data"]),
            "expires_at": iso_ts(a["shown_at"] + ASK_S), "grace_min": int(return_gate.grace_s(self.hm.ctrl) // 60)}
        return {"return": ret, "visits": {b: ("return" if v["returning"] else "pickup") for b, v in self.visits.items()}}


def lock_message(handover: Any) -> str | None:
    """Česká hláška `handover_in_progress`, když zámek drží rezervace výbavy (žádný kód motorky nepřijde)."""
    lock, gear = getattr(handover, "lock", None), getattr(handover, "gear", None)
    return LOCK_TEXT if lock is not None and gear is not None and gear.is_gear(lock.booking_id) else None


async def http_return(server: Any, request: Any) -> Any:
    """`POST /api/gear/return {booking_id, answer: 'yes'|'no'}` → `{ok, confirmed, error}` (zákazník, bez tokenu)."""
    body = await server.read_body(request)
    bid, ans = body.get("booking_id"), body.get("answer")
    if not isinstance(bid, str) or not bid.strip():
        return server.error("missing_booking_id")
    if ans not in ("yes", "no"):
        return server.error("bad_answer")
    gear = getattr(getattr(server.ctrl, "handover", None), "gear", None)
    if gear is None:
        return server.json({"ok": False, "confirmed": False, "error": "not_pending"})
    return server.json(await gear.answer(bid.strip(), ans == "yes"))
