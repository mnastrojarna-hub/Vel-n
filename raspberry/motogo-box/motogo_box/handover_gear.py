"""Výpůjčka výbavy bez motorky na kiosku (1.3.0, rozhodnutí majitele 2026-10-22, CONTRACT §33) — pomocný modul `handover.py`.

Rezervace `booking_kind='gear'` má na pobočce jen kód šatny (kód brány je mimo kiosk): šatna je celé převzetí i vrácení.
* Převzetí: kód šatny → šatna (bez držení hudby a relace „do kódu motorky“, `controller_codes.submit_code`) → zavření →
  protokol jen s výbavou (velikosti + podpis, identita = kód šatny TÉŽE rezervace, `handover_submit._verify_code`) → kóje se
  neotvírá; zámek přejímky platí od zavření šatny do podpisu (displej / Velín) nebo do vypršení jako u motorky.
* Vrácení (varianta B): zavření šatny u PODEPSANÉ rezervace → dotaz „Vracíš všechnu výbavu?“ Ano / Ne, bez zámku přejímky.
  Ano → událost GEAR_RETURN_CONFIRMED (kiosk_log_open, kind accessories, `session_id` návštěvy šatny, `closed_ts` = zavření
  šatny, `offline`) → server rezervaci hned dokončí; offline `return_gate` kód šatny 15 min po zavření nevydá. Ne / bez odpovědi
  `ASK_S` → nic (výpůjčka běží dál). Vrácení = výbava vyzvednutá PŘED touto návštěvou (rozhoduje grant, `visit`): šatna té
  výpůjčky už byla na TÉTO jednotce zavřena (`picked`, persist kv `handover_gear`), podpis z displeje čeká ve frontě, nebo server
  hlásí `protocol.gear_collected_at` — a zavření při převzetí na jednotce je starší než `PICKUP_GRACE_S` (kdo se hned po
  převzetí vrátí pro zapomenutý kus, dotaz nedostane). Jinak (podepsáno ve Velíně / appce před převzetím — příkaz `protocol_signed`
  píše `hm.signed` —, offline `absent`) je zavření převzetí → jen toast, bez dotazu (nikdy nic nedokončí omylem).
Rozpoznání rezervace: `ResolveResult.gear_only` při grantu šatny (`visit`) nebo `protocol.gear_only` (RPC / sync cache).
"""
from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any

from . import gear_limits as gl
from . import return_gate
from .handover_lock import iso_ts
from .models import Event, EventKind, now_iso_ms
from .pins import parse_iso

if TYPE_CHECKING:  # pragma: no cover
    from .handover import HandoverItem, HandoverManager

log = logging.getLogger("motogo.handover")

ASK_S = 60                  # dotaz na vrácení bez odpovědi zmizí (= Ne) — modální karta nesmí blokovat další zákazníky
VISIT_KEEP_S = 24 * 3600    # záznam návštěvy šatny (grant) — rozpoznání výbavy u zavření a text modální hlášky šatny
KV = "handover_gear"        # persist: {"picked": {booking_id: {"at": zavření při převzetí | 0, "until": do kdy držet}}} (unix)
PICKED_KEEP_S = 40 * 86400  # záznam „šatna zavřena“ drží aspoň 40 dní, déle do konce výpůjčky + 2 dny
PICKUP_GRACE_S = 30 * 60    # nová návštěva do 30 min od 1. zavření šatny = ještě převzetí (zapomenutý kus), ne vrácení
GEAR_KEYS = ("helmet", "jacket", "pants", "boots", "gloves")
LOCK_TEXT = ("Nejprve musí být dokončena předchozí přejímka — zákazník, který právě zavřel šatnu, podepisuje protokol. "
             "Pak přijdete na řadu.")
LOCK_EVENT_TEXT = "Kód odmítnut — probíhá přejímka jiné rezervace (zákazník podepisuje protokol výbavy)"


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
    """Stav výbavy bez motorky v `HandoverManager` (`hm.gear`): návštěvy šatny, právě položený dotaz na vrácení (oboje
    v paměti — restart dotaz zahodí = Ne, nikdy nic nedokončí) a persistované `picked` (šatna výpůjčky už zavřena)."""

    def __init__(self, hm: "HandoverManager") -> None:
        self.hm = hm
        self.visits: dict[str, dict] = {}     # booking_id → {returning, offline, at, end}
        self.ask: dict | None = None
        self.picked: dict[str, dict] = {}     # booking_id → {at, until}: šatna výpůjčky už byla na jednotce zavřena (persist)
        try:
            rows = (hm.ctrl.storage.kv_get(KV) or {}).get("picked") or {}
            self.picked = {str(b): {"at": float(r.get("at") or 0), "until": float(r.get("until") or 0)}
                           for b, r in rows.items() if isinstance(r, dict) and float(r.get("until") or 0) > hm.clock()}
        except Exception:  # noqa: BLE001 — poškozený stav nesmí zablokovat start (bez záznamu = převzetí, nic nedokončí)
            log.exception("handover: načtení záznamů výbavy selhalo")

    # ─── rozpoznání ─────────────────────────────────────────────────────────
    def is_gear(self, booking_id: Any, p: Any = None) -> bool:
        bid = str(booking_id or "")
        item = self.hm.items.get(bid)
        return bool(bid) and (bid in self.visits or protocol_gear(p) or protocol_gear(self.hm.protocols.get(bid))
                              or bool(item is not None and item.gear_only))

    def _signed(self, bid: str, p: Any) -> bool:
        hm = self.hm
        return bid in hm.signed or hm.signed_local(bid) or (isinstance(p, dict) and not p.get("required"))

    def _returning(self, bid: str, p: Any) -> bool:
        """Vrácení = podepsáno ∧ výbava vyzvednutá už dřív: zavření šatny na jednotce (`picked`; 1. zavření mladší než
        `PICKUP_GRACE_S` = ještě převzetí), podpis z displeje ve frontě, nebo server (`gear_collected_at` — důkaz je jen
        nenulová hodnota; null ze zastaralé cache / před doručením události nic nevyvrací). `hm.signed` jako důkaz záměrně NE
        — plní ho i podpis ve Velíně před převzetím (příkaz `protocol_signed`)."""
        q, rec = self.hm.queue_state, self.picked.get(bid)
        if not self._signed(bid, p) or (rec is not None and self.hm.clock() - rec["at"] < PICKUP_GRACE_S):
            return False
        return rec is not None or bid in q.get("pending", []) or bid in q.get("failed", []) \
            or bool(isinstance(p, dict) and p.get("gear_collected_at"))

    def _mark_closed(self, bid: str, p: Any, pickup: bool) -> None:
        """Zavření šatny výpůjčky = důkaz převzetí pro další návštěvy (i offline, i po restartu); `at` = čas zavření při
        převzetí (0 = první zavření na jednotce už bylo vrácení → `PICKUP_GRACE_S` neplatí)."""
        now, data = self.hm.clock(), (p.get("data") if isinstance(p, dict) else None) or {}
        end = parse_iso(data.get("end_date") or (self.visits.get(bid) or {}).get("end"))
        until = max(now + PICKED_KEEP_S, end.timestamp() + 2 * 86400 if end is not None else 0.0)
        rec = self.picked.get(bid)
        if rec is None or rec["until"] < until:
            self.picked[bid] = {"at": rec["at"] if rec else (now if pickup else 0.0), "until": until}
            self._save()

    def _save(self) -> None:
        try:
            self.hm.ctrl.storage.kv_set(KV, {"picked": dict(self.picked)})
        except Exception:  # noqa: BLE001
            log.exception("handover: uložení záznamů výbavy selhalo")

    def visit(self, rr: Any) -> None:
        """Grant kódu šatny (`HandoverManager.remember`): rezervace výbavy a zda jde o VRÁCENÍ — podle stavu PŘED touto
        návštěvou (znovuzavření v téže relaci / opakovaný kód při převzetí tak dotaz nevyvolá); text hlášky šatny + `closed`."""
        bid = str(getattr(rr, "booking_id", None) or "")
        if not bid or not getattr(rr, "gear_only", False):
            return
        p = rr.protocol
        self.visits[bid] = {"returning": self._returning(bid, p), "offline": bool(rr.offline),
                            "at": self.hm.clock(), "end": ((p or {}).get("data") or {}).get("end_date")}

    # ─── zavření / znovuotevření šatny ───────────────────────────────────────
    async def closed(self, zone: int, bid: str, p: Any) -> tuple[bool, str | None]:
        """DOOR_CLOSED šatny rezervace výbavy. (True, výsledek) = vyřízeno tady (vrácení / podepsáno jinde / neznámý
        stav); (False, None) = nepodepsaný protokol → běžná cesta `on_wardrobe_closed` (zámek + overlay)."""
        hm, v = self.hm, self.visits.get(bid)
        signed = self._signed(bid, p)
        returning = signed and (v["returning"] if v is not None else self._returning(bid, p))
        self._mark_closed(bid, p, pickup=not returning)
        if signed:
            if not returning:        # převzetí výbavy podepsané jinde (Velín / appka) — jen toast
                hm._show_done(bid, zone, dict((p or {}).get("data") or {}), gear_only=True)   # noqa: SLF001
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
        old = [b for b, r in self.picked.items() if r["until"] < now]
        for bid in old:
            del self.picked[bid]
        if old:
            self._save()

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
    """Česká hláška `handover_in_progress`, když zámek drží rezervace výbavy (žádný kód motorky nepřijde); text události
    ACCESS_DENIED do Velína pak `LOCK_EVENT_TEXT`."""
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
