"""Předávací protokol na displeji (SPEC §9/§10, kontrakt §22) — `HandoverManager`.

Kiosk vede zákazníka: kód šatny → po zavření šatny overlay protokolu; kód motorky bez podpisu →
kóje se NEotevře, overlay protokolu s `then_open` (po podpisu se otevře sama). Položky (`HandoverItem`)
žijí nejvýš 24 h, viditelná je vždy nejvýš jedna; `then_open` platí VÝHRADNĚ dokud je overlay viditelný
(dismiss, `handover_idle_s` bez dotyku i restart procesu ho ruší) — kóje se nikdy neotevře bez zákazníka
u displeje. Podpis se nikdy neztratí: `Storage.protocol_queue` (handover_submit.py). Persist v kv
`handover` jen nevyřízené položky bez then_open/podpisů; po startu je vše skryté.
Fail-open: `protocol is None` (stará DB / stará cache) i `absent` (rezervace v `protocols[]` sync chybí — sync
neumí rozlišit „podepsáno jinde“ od „kód odebrán / rezervace zrušena / cache mimo okno“) → hradlo se neuplatní;
absence se ale NIKDY nepamatuje jako podpis a z cesty sync/boot se kóje NIKDY neotevře (CONTRACT §28 pravidlo 1) —
otevírá jen `submit` z displeje a příkaz `protocol_signed` doručený během viditelného overlaye s `then_open`.
"""
from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any, Callable

from . import handover_submit as hs
from .models import ACCESSORIES_NAME, Event, EventKind, ResolveResult
from .pins import LocalResolver

if TYPE_CHECKING:  # pragma: no cover
    from .zone import ZoneController

log = logging.getLogger("motogo.handover")

KV_HANDOVER = "handover"
ITEM_MAX_AGE_S = 24 * 3600      # nevyřízený protokol se po dni zahodí (kód motorky ho vyvolá znovu)
SIGNED_KEEP_S = 24 * 3600       # potvrzené podpisy proti zastaralé offline cache (required=true)
DONE_TTL_S = 5.0                # toast „Protokol potvrzen. Teď zadejte kód motorky.“
DEFAULT_IDLE_S = 120
STAGE_PROTOCOL, STAGE_DONE = "protocol", "done"
GEAR_KEYS = ("helmet", "jacket", "pants", "boots", "gloves")
PERSISTED = ("booking_id", "kind_origin", "zone", "data", "is_child", "shown_at", "last_touch",
             "dismissed_at", "shown_logged", "created_at")


def _iso(ts: float | None) -> str | None:
    return None if ts is None else datetime.fromtimestamp(float(ts), timezone.utc).isoformat(timespec="seconds")


@dataclass
class HandoverItem:
    booking_id: str
    kind_origin: str = "accessories"     # accessories (po zavření šatny) | motorcycle (kód motorky bez podpisu)
    zone: int | None = None              # zóna, ke které se položka právě váže (šatna / kóje při then_open)
    data: dict = field(default_factory=dict)
    is_child: bool = False
    stage: str = STAGE_PROTOCOL          # protocol | done (toast)
    visible: bool = False
    then_open: dict | None = None        # {zone, booking_id, kind, source} — jen dokud je overlay vidět
    shown_at: float | None = None
    last_touch: float = 0.0
    dismissed_at: float | None = None
    shown_logged: bool = False           # PROTOCOL_SHOWN jen při prvním zobrazení
    created_at: float = 0.0
    in_flight: bool = False              # právě probíhá podpis z displeje (submit)

    def persisted(self) -> dict:
        d = asdict(self)
        return {k: d[k] for k in PERSISTED}

    @classmethod
    def from_dict(cls, d: Any) -> "HandoverItem | None":
        if not isinstance(d, dict) or not d.get("booking_id"):
            return None
        try:
            return cls(**{k: d[k] for k in PERSISTED if k in d}, visible=False, then_open=None)
        except (TypeError, ValueError):
            return None


class HandoverManager:
    """Stavový automat protokolů na displeji; HW (otevření kóje) volá jen `handover_submit.open_zone`."""

    def __init__(self, ctrl: Any, clock: Callable[[], float] = time.time) -> None:
        self.ctrl = ctrl
        self.clock = clock
        self.items: dict[str, HandoverItem] = {}
        self.signed: dict[str, float] = {}       # booking_id → čas potvrzení (server/appka/úspěšný upload)
        self.protocols: dict[str, dict] = {}     # `rr.protocol` z grantu šatny (pro okamžik zavření dveří)
        self.gear_sizes: dict = {}               # číselník velikostí ze sync (`gear_sizes`)
        self.queue_state: dict = {"pending": [], "failed": []}
        self.inflight: set[str] = set()
        self.wake = asyncio.Event()              # probudí protocol_loop (nový podpis / obnovené spojení)
        self._load()

    # ─── stav a persist ──────────────────────────────────────────────────────
    def _load(self) -> None:
        st = self.ctrl.storage
        try:
            raw = st.kv_get(KV_HANDOVER) or {}
            for d in raw.get("items") or []:
                item = HandoverItem.from_dict(d)
                if item is not None:
                    self.items[item.booking_id] = item
            self.signed = {str(k): float(v) for k, v in (raw.get("signed") or {}).items()}
            cache = st.load_code_cache() or {}
            self.gear_sizes = cache.get("gear_sizes") if isinstance(cache.get("gear_sizes"), dict) else {}
            self.refresh_queue()
        except Exception:  # noqa: BLE001 — poškozený stav nesmí zablokovat start
            log.exception("handover: načtení stavu selhalo")

    def state_dict(self) -> dict:
        items = [i.persisted() for i in self.items.values() if i.stage == STAGE_PROTOCOL and not i.in_flight]
        return {"items": items, "signed": dict(self.signed)}

    def _save(self) -> None:
        try:
            self.ctrl.storage.kv_set(KV_HANDOVER, self.state_dict())
        except Exception:  # noqa: BLE001
            log.exception("handover: uložení stavu selhalo")

    def refresh_queue(self) -> None:
        fn = getattr(self.ctrl.storage, "protocol_queue_status", None)
        if fn is not None:
            self.queue_state = fn()

    @property
    def idle_s(self) -> int:
        t = getattr(getattr(self.ctrl, "hardware", None), "timings", None)
        return int(getattr(t, "handover_idle_s", DEFAULT_IDLE_S) or DEFAULT_IDLE_S)

    def _zone(self, number: int | None) -> "ZoneController | None":
        return self.ctrl.zones.get(number) if number is not None else None

    def _cache_protocol(self, booking_id: str) -> dict | None:
        cache = getattr(self.ctrl.storage, "load_code_cache", lambda: None)()
        return LocalResolver.protocol_for(cache, booking_id)

    def signed_local(self, booking_id: str) -> bool:
        """Podepsáno u displeje (čeká ve frontě / trvale odmítnuto) nebo nedávno potvrzeno serverem."""
        return (booking_id in self.signed or booking_id in self.queue_state.get("pending", [])
                or booking_id in self.queue_state.get("failed", []))

    def then_open_valid(self, item: HandoverItem, now: float | None = None) -> bool:
        now = self.clock() if now is None else now
        return item.visible and item.stage == STAGE_PROTOCOL and item.then_open is not None \
            and now - item.last_touch < self.idle_s

    def active(self) -> HandoverItem | None:
        return next((i for i in self.items.values() if i.visible), None)

    def remember(self, rr: ResolveResult) -> None:
        """Kód šatny prošel: protokol rezervace z odpovědi RPC (čerstvější než cache) pro zavření dveří."""
        if rr.booking_id and isinstance(rr.protocol, dict):
            self.protocols[str(rr.booking_id)] = rr.protocol

    # ─── zobrazení ───────────────────────────────────────────────────────────
    async def _show(self, item: HandoverItem, then_open: dict | None) -> None:
        now = self.clock()
        for other in self.items.values():
            if other is not item:
                other.visible, other.then_open = False, None
        for bid in [b for b, i in self.items.items() if i.stage == STAGE_DONE]:
            self.items.pop(bid, None)
        item.visible, item.then_open, item.stage = True, then_open, STAGE_PROTOCOL
        item.shown_at, item.last_touch, item.dismissed_at = now, now, None
        self.items[item.booking_id] = item
        if not item.shown_logged:
            item.shown_logged = True
            zc = self._zone(item.zone)
            await self.ctrl.emit(Event(
                kind=EventKind.PROTOCOL_SHOWN, zone=item.zone, booking_id=item.booking_id,
                door_id=zc.zone.door_id if zc else None, box_number=zc.zone.box_number if zc else None,
                code_kind=item.kind_origin, message="Předávací protokol zobrazen na displeji",
                detail={"source": "kiosk", "then_open": then_open is not None}))
        self._save()

    def _show_done(self, booking_id: str, zone: int | None, data: dict) -> None:
        now = self.clock()
        for other in self.items.values():
            other.visible, other.then_open = False, None
        self.items[booking_id] = HandoverItem(booking_id=booking_id, kind_origin="accessories", zone=zone, data=data,
                                              stage=STAGE_DONE, visible=True, shown_at=now, last_touch=now,
                                              created_at=now)

    async def on_wardrobe_closed(self, zone: int, booking_id: str | None, protocol: dict | None = None) -> str | None:
        """DOOR_CLOSED šatny s rezervací: nepodepsáno → overlay protokolu; podepsáno → toast DONE; neznámo → nic."""
        bid = str(booking_id or "")
        if not bid:
            return None
        p = protocol if isinstance(protocol, dict) else (self.protocols.get(bid) or self._cache_protocol(bid))
        if bid in self.signed or (p is not None and not p.get("required")):
            if p is not None and p.get("absent"):
                log.info("handover: rezervace %s v cache bez protokolu (podepsáno jinde / mimo okno) — bez hradla", bid)
            self._show_done(bid, zone, dict(p.get("data") or {}) if p else {})
            self._save()
            return "done"
        if p is None:
            log.warning("handover: protocol_state_unknown (šatna zavřena, rezervace %s) — bez protokolu", bid)
            return None
        if self.signed_local(bid):
            return None
        item = self.items.get(bid) or HandoverItem(booking_id=bid, created_at=self.clock())
        item.kind_origin, item.zone = "accessories", zone
        item.data, item.is_child = dict(p.get("data") or {}), bool(p.get("is_child"))
        await self._show(item, None)
        return "protocol"

    async def require_before_open(self, rr: ResolveResult, zc: "ZoneController", source: str) -> bool:
        """Kód motorky: True = kóji NEotevírat, overlay protokolu s then_open (po podpisu se otevře sama)."""
        bid = str(rr.booking_id or "")
        p = rr.protocol
        if p is None or not bid:
            log.warning("handover: protocol_state_unknown (kód motorky, rezervace %s) — otevírám bez hradla", bid)
            return False
        done = self.items.get(bid)
        if done is not None and done.stage == STAGE_DONE:
            self.items.pop(bid, None)
        if not p.get("required") or self.signed_local(bid):
            if p.get("absent"):     # offline cache bez záznamu (podepsáno jinde / cache mimo okno) — fail-open, bez paměti
                log.warning("handover: protocol_absent (kód motorky, rezervace %s) — otevírám bez hradla", bid)
            return False
        item = self.items.get(bid)
        if item is None or item.stage != STAGE_PROTOCOL:
            item = HandoverItem(booking_id=bid, kind_origin="motorcycle", created_at=self.clock())
        item.zone, item.data, item.is_child = zc.number, dict(p.get("data") or {}), bool(p.get("is_child"))
        await self._show(item, {"zone": zc.number, "booking_id": bid, "kind": "motorcycle", "source": source})
        return True

    async def mark_signed_remote(self, booking_id: str, *, may_open: bool = False) -> dict | None:
        """Podpis potvrzený serverem (appka/Velín): položku odstranit a zapamatovat `signed`. `may_open=True`
        JEN pro příkaz `protocol_signed` (commands.py): overlay právě vidět s platným then_open → kóje se otevře
        (vrací `opened`); jinak viditelný → toast DONE. Sync (`reconcile`) volá s `may_open=False` — z cesty
        sync/boot se kóje nikdy neotevře (CONTRACT §28 pravidlo 1). Idempotentní."""
        bid = str(booking_id or "")
        self.signed[bid] = self.clock()
        self.protocols.pop(bid, None)
        return await self._drop(bid, may_open)

    async def forget(self, booking_id: str) -> None:
        """Rezervace po syncu v `protocols[]` CHYBÍ (podepsána jinde, zrušena, kód odebrán, cache mimo okno —
        důvod nelze rozlišit): položku jen odstranit (viditelná → toast DONE), NIKDY neotevírat ani nezapisovat
        `signed` (odebraný a znovu aktivovaný kód by jinak obešel hradlo)."""
        bid = str(booking_id or "")
        self.protocols.pop(bid, None)
        await self._drop(bid, False)

    async def _drop(self, bid: str, may_open: bool) -> dict | None:
        item = self.items.get(bid)
        if item is None or item.in_flight:      # submit z displeje právě běží — otevření řeší on (jedno otevření)
            self._save()
            return None
        del self.items[bid]
        opened = None
        if item.visible and item.stage == STAGE_PROTOCOL:
            if may_open and self.then_open_valid(item):
                to, item.then_open = item.then_open, None     # atomická konzumace
                opened, err = await hs.open_zone(self, to)
                if err:
                    log.warning("handover: otevření po vzdáleném podpisu selhalo (%s)", err)
            else:
                self._show_done(bid, item.zone, item.data)
        self._save()
        return opened

    async def submit(self, booking_id: str, form: Any, signature: Any, code: str | None, source: str = "ui") -> dict:
        """Podpis z displeje — viz `handover_submit.submit`."""
        return await hs.submit(self, booking_id, form, signature, code, source)

    def dismiss(self, booking_id: str) -> bool:
        item = self.items.get(str(booking_id or ""))
        if item is None:
            return False
        if item.stage == STAGE_DONE:
            self.items.pop(item.booking_id, None)
        else:
            item.visible, item.then_open, item.dismissed_at = False, None, self.clock()
        self._save()
        return True

    def touch(self, booking_id: str) -> bool:
        item = self.items.get(str(booking_id or ""))
        if item is None or not item.visible:
            return False
        item.last_touch = self.clock()
        return True

    def tick(self, now: float | None = None) -> None:
        """Volá tick_loop (250 ms): idle → skrýt (then_open pryč), toast po 5 s a položky po 24 h smazat."""
        now = self.clock() if now is None else now
        changed = False
        for bid, item in list(self.items.items()):
            if item.stage == STAGE_DONE:
                if now - (item.shown_at or now) >= DONE_TTL_S:
                    del self.items[bid]
                continue
            if item.visible and not item.in_flight and now - item.last_touch >= self.idle_s:
                item.visible, item.then_open, changed = False, None, True
            if now - item.created_at > ITEM_MAX_AGE_S and not item.in_flight:
                del self.items[bid]
                changed = True
        for bid in [b for b, ts in self.signed.items() if now - ts > SIGNED_KEEP_S]:
            del self.signed[bid]
            changed = True
        if changed:
            self._save()

    async def reconcile(self, protocols: Any, gear_sizes: Any = None) -> None:
        """Po každém syncu — NIKDY neotevírá kóji (CONTRACT §28): rezervace v `protocols[]` s `required=false`
        → potvrzený podpis (`mark_signed_remote`, bez otevření); v seznamu CHYBĚJÍCÍ → `forget` (důvod nelze
        rozlišit, bez `signed`); přítomná s `required=true` → obnovit data (velikosti) a zrušit případné lokální
        „podepsáno“ (server je zdroj pravdy, např. vrácený claim edge; podpis čekající ve frontě hradlo dál
        obchází přes `signed_local`). `protocols` None = stará DB bez seznamu → nic."""
        if isinstance(gear_sizes, dict):
            self.gear_sizes = gear_sizes
        if not isinstance(protocols, list):
            return
        by_id = {str(p.get("booking_id")): p for p in protocols if isinstance(p, dict) and p.get("booking_id")}
        for bid in list(self.protocols):
            self.protocols[bid] = by_id.get(bid) or {"booking_id": bid, "required": False, "absent": True}
        stale = [bid for bid, p in by_id.items() if p.get("required", True) and bid in self.signed]
        for bid in stale:
            del self.signed[bid]
        for bid, item in list(self.items.items()):
            if item.stage != STAGE_PROTOCOL or item.in_flight:
                continue
            p = by_id.get(bid)
            if p is None:
                await self.forget(bid)
            elif not p.get("required", True):
                await self.mark_signed_remote(bid, may_open=False)
            else:
                item.data, item.is_child = dict(p.get("data") or item.data), bool(p.get("is_child"))
        if stale:
            self._save()

    def busy(self, now: float | None = None) -> bool:
        """Zákazník právě podepisuje (overlay vidět, dotyk před méně než idle_s) → odložit přestavbu/aktualizaci."""
        now = self.clock() if now is None else now
        item = self.active()
        return bool(item and item.stage == STAGE_PROTOCOL and (item.in_flight or now - item.last_touch < self.idle_s))

    def retry_failed(self) -> int:
        fn = getattr(self.ctrl.storage, "protocol_queue_retry_failed", None)
        n = int(fn() or 0) if fn is not None else 0
        self.refresh_queue()
        self.wake.set()
        return n

    async def flush(self) -> int:
        return await hs.flush(self)

    # ─── snapshot (bez podpisů a formulářů — jde i do kiosk_report_status) ──
    def _sizes(self, is_child: bool) -> dict:
        gs = self.gear_sizes if isinstance(self.gear_sizes, dict) else {}
        group = gs.get("child" if is_child else "adult") or gs.get("adult") or gs
        return {k: list(group.get(k) or []) for k in GEAR_KEYS} if isinstance(group, dict) else {}

    def status(self) -> dict:
        item, now = self.active(), self.clock()
        active = None
        if item is not None:
            zc = self._zone(item.zone)
            label = zc.zone.display_name if zc else (ACCESSORIES_NAME if item.kind_origin == "accessories"
                                                     else f"Zóna {item.zone}")
            to_valid = self.then_open_valid(item, now)
            expires = (item.shown_at or now) + DONE_TTL_S if item.stage == STAGE_DONE else item.last_touch + self.idle_s
            active = {"booking_id": item.booking_id, "stage": item.stage, "zone": item.zone, "zone_label": label,
                      "kind": zc.zone.kind if zc else item.kind_origin, "then_open": to_valid,
                      "needs_code": not to_valid, "data": dict(item.data), "sizes": self._sizes(item.is_child),
                      "shown_at": _iso(item.shown_at), "expires_at": _iso(expires), "saving": item.in_flight}
        return {"active": active, "pending": list(self.queue_state.get("pending", [])),
                "failed": list(self.queue_state.get("failed", [])),
                "waiting": [b for b, i in self.items.items() if i.stage == STAGE_PROTOCOL and not i.in_flight]}
