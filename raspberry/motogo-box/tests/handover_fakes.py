"""Falešný controller pro testy předávacího protokolu (`handover.py`, `handover_submit.py`)."""
from __future__ import annotations

import base64
from collections import deque
from types import SimpleNamespace

from motogo_box.config import SecurityCfg, TimingsCfg
from motogo_box.handover import HandoverManager
from motogo_box.models import ResolveResult
from motogo_box.pins import LocalResolver, PinGuard, hmac_code
from motogo_box.storage import Storage

DEVICE_ID = "11111111-2222-4333-8444-555555555555"
TOKEN = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
SIG = "data:image/png;base64," + base64.b64encode(b"\x89PNG" + b"\x00" * 200).decode()
GEAR_SIZES = {"adult": {"helmet": ["S", "M", "L"], "jacket": ["M"], "pants": [], "boots": ["43"], "gloves": ["L"]},
              "child": {"helmet": ["XS"], "jacket": [], "pants": [], "boots": [], "gloves": []}}


def protocol(booking_id: str = "b1", required: bool = True, **extra) -> dict:
    return {"booking_id": booking_id, "required": required, "filled_at": None if required else "2026-09-25T08:00:00Z",
            "needs_locker": True, "is_child": False, "prompted_at": None, "gear_collected_at": None,
            "data": {"customer_name": "Petra S.", "moto_model": "Honda CB500", "moto_spz": "1AB 2345",
                     "start_date": "2026-09-25", "end_date": "2026-09-27", "mileage": 1200,
                     "gear": [{"key": "helmet", "who": "rider", "field": "helmet_size", "size": "M"}]}, **extra}


def rr_moto(booking_id: str = "b1", proto: dict | None = None) -> ResolveResult:
    return ResolveResult(ok=True, kind="motorcycle", booking_id=booking_id, door_id="d3", box_number=3,
                         door_configured=True, protocol=proto)


class FakeClock:
    def __init__(self, t: float = 1_700_000_000.0) -> None:
        self.t = t

    def __call__(self) -> float:
        return self.t

    def advance(self, s: float) -> None:
        self.t += s


class FakeZone:
    def __init__(self, number: int, kind: str = "motorcycle") -> None:
        self.number, self.grants, self.result = number, [], (True, "ok")
        name = "Šatna" if kind == "accessories" else f"Kóje {number}"
        self.zone = SimpleNamespace(kind=kind, door_id=f"d{number}", display_name=name,
                                    box_number=None if kind == "accessories" else number)
        self.booking_id: str | None = None

    async def grant_access(self, *, booking_id, kind, source):
        self.grants.append((booking_id, kind, source))
        return self.result


class FakeApi:
    """`resolve_code`: dict dle `resolve[code]` (None = síť → offline cache); `submit_protocol`: fronta odpovědí."""

    def __init__(self) -> None:
        self.resolve: dict[str, dict | None] = {}
        self.results: deque[dict] = deque()
        self.submits: list[dict] = []
        self.online = True
        self.gate = None          # asyncio.Event → submit_protocol na něj počká (souběh s příkazem)

    async def resolve_code(self, code: str):
        return self.resolve.get(code, {"ok": False, "error": "invalid_code"})

    async def submit_protocol(self, payload: dict) -> dict:
        self.submits.append(payload)
        if self.gate is not None:
            await self.gate.wait()
        return self.results.popleft() if self.results else {"ok": True, "permanent": False, "error": None,
                                                              "already_filled": False}


class FakeCtrl:
    def __init__(self, tmp_path, clock: FakeClock | None = None) -> None:
        self.clock = clock or FakeClock()
        self.storage = Storage(str(tmp_path / "handover.db"))
        self.api = FakeApi()
        self.zones = {3: FakeZone(3), 8: FakeZone(8, "accessories")}
        self.hardware = SimpleNamespace(timings=TimingsCfg(), security=SecurityCfg())
        self.pin_guard = PinGuard(self.storage, SecurityCfg(), self.clock)
        self.resolver = LocalResolver(DEVICE_ID, TOKEN)
        self.events: list = []
        self.ready, self.diagnostics = True, None
        self.handover = HandoverManager(self, clock=self.clock)

    async def emit(self, event) -> None:
        self.events.append(event)

    def kinds(self) -> list[str]:
        return [e.kind.value for e in self.events]

    def find_zone(self, *, door_id=None, zone=None, box_number=None):
        for zc in self.zones.values():
            if door_id is not None and zc.zone.door_id == door_id:
                return zc
        if zone is not None:
            return self.zones.get(int(zone))
        return next((z for z in self.zones.values() if box_number is not None and z.zone.box_number == box_number), None)

    def cache(self, codes: list[dict], protocols: list | None) -> None:
        """Offline cache jako z `kiosk_sync_config` (kódy HMAC, protocols[] volitelně)."""
        payload = {"ok": True, "doors": [], "service_codes": [], "gear_sizes": GEAR_SIZES,
                   "codes": [{**c, "h": hmac_code(DEVICE_ID, TOKEN, c.pop("code"))} for c in codes]}
        if protocols is not None:
            payload["protocols"] = protocols
        self.storage.save_code_cache(payload)
        self.handover.gear_sizes = GEAR_SIZES

    def close(self) -> None:
        self.storage.close()
