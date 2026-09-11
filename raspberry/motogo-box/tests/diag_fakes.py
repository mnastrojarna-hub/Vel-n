"""Falešný controller, I/O, signalizace a zóny pro testy diagnostiky (`test_diagnostics.py`,
`test_diag_protocol.py`). Zámek se v diagnostice NIKDY nepulzuje — `FakeIo.pulse` to hlídá."""
from __future__ import annotations

import time

from motogo_box import controller_codes as cc
from motogo_box.config import HardwareConfig, LocalConfig, SecurityCfg
from motogo_box.diagnostics import NetworkDiagnostics
from motogo_box.models import HwRef, Signal, Zone, ZoneHw, ZoneState
from motogo_box.pins import LocalResolver, PinGuard
from motogo_box.storage import Storage
from motogo_box.zone import ACTIVE_STATES, ZoneController

DEVICE_ID, TOKEN = "6f1c2b8e-3a4d-4e5f-9a0b-1c2d3e4f5a6b", "0a1b2c3d-4e5f-6a7b-8c9d-0e1f2a3b4c5d"


# ─── falešný controller ──────────────────────────────────────────────────────
class FakeApi:
    def __init__(self, paired: bool = True) -> None:
        self.device_id, self.device_token = (DEVICE_ID, TOKEN) if paired else ("", "")
        self.reports: list[dict] = []
        self.resolve: dict | None = None

    @property
    def paired(self) -> bool:
        return bool(self.device_id)

    async def heartbeat(self) -> dict:
        return {"ok": True, "branch_name": "Test"}

    async def report_diagnostics(self, report: dict) -> None:
        self.reports.append(report)

    async def resolve_code(self, code: str):
        return self.resolve

    async def log_event(self, *a, **k) -> None:
        pass

    async def log_open(self, *a, **k) -> None:
        pass


class FakeModule:
    def __init__(self, coils: list[bool]) -> None:
        self.coils = coils

    async def read_coils(self) -> list[bool]:
        return list(self.coils)


class FakeIo:
    """Momentka vstupů/relé jako IoBus: `offline` moduly čtou None; zámek se jen čte (`get().read_coils`)."""

    def __init__(self) -> None:
        self.offline: set[str] = set()
        self.inputs: dict[str, list[bool]] = {"wav617a": [True] * 8, "wav617b": [True] * 8}
        self.coils: dict[str, list[bool]] = {"wav645": [False] * 16}
        self.pulses: list = []

    def is_online(self, name: str) -> bool:
        return name not in self.offline

    async def read_all_inputs(self) -> dict:
        return {n: (None if n in self.offline else list(v)) for n, v in self.inputs.items()}

    def input_value(self, snapshot: dict, ref: HwRef):
        values = snapshot.get(ref.dev)
        return None if values is None or not 0 <= ref.idx < len(values) else bool(values[ref.idx])

    def get(self, name: str) -> FakeModule:
        return FakeModule(self.coils.get(name, []))

    async def pulse(self, *a, **k):  # pragma: no cover — diagnostika NIKDY nesmí pulzovat
        self.pulses.append(a)
        raise AssertionError("diagnostika pulzovala zámek")


class FakeSignals:
    def __init__(self, shellies: dict | None = None) -> None:
        self.shellies = shellies or {}
        self.signal: dict[int, Signal] = {}

    def online(self, name: str) -> bool:
        return not self.shellies or bool(getattr(self.shellies.get(name), "online", False))

    def current(self, zone: int) -> Signal:
        return self.signal.get(zone, Signal.RED)


class FakePlayer:
    playlist_count, device = 3, None


class FakeAudio:
    playing_zone, player_ok, player = None, True, FakePlayer()


def zone_hw(n: int, shelly: str = "shelly1") -> ZoneHw:
    return ZoneHw(zone=n, lock=HwRef("wav645", n - 1), contact=HwRef("wav617a", n - 1), light=HwRef("wav617a", n - 1),
                  audio=HwRef("wav617b", n), red=HwRef(shelly, 0), green=HwRef(shelly, 1))


class FakeZone:
    """Falešný ZoneController: stav/porucha/kontakt + `test_sequence()` s nastavitelným výsledkem."""

    io_problems, io_ready = ZoneController.io_problems, ZoneController.io_ready

    def __init__(self, ctrl, n: int, *, state=ZoneState.SECURED, fault=None, door_closed=True, result=None, hw=None) -> None:
        self.zone = Zone(hw=hw or zone_hw(n), box_number=n, label=f"Kóje {n}")
        self.io, self.signals = ctrl.io, ctrl.signals
        self.state, self.fault, self.door_closed = state, fault, door_closed
        self.result = result or {"light": True, "signal": True, "audio": True}
        self.tests = 0

    @property
    def number(self) -> int:
        return self.zone.number

    async def test_sequence(self) -> dict:
        self.tests += 1
        if self.state in ACTIVE_STATES:
            return {"error": "busy", "light": False, "signal": False, "audio": False}
        return dict(self.result)


class FakeCtrl:
    def __init__(self, tmp_path, hw: dict, paired: bool = True) -> None:
        self.local = LocalConfig()
        self.local.supabase.url = "http://127.0.0.1:1"
        self.local.diagnostics.internet_urls = []
        self.local.diagnostics.code = "netdiag"     # výchozí je prázdný (vypnuto) — testy kód nastavují explicitně
        self.local.diagnostics.scan_subnets = ["127.0.0.1/30"]
        # scan hledá porty simulátoru (v hw mapě) místo 502/80
        self.local.diagnostics.scan_ports = sorted({int(d.get("port") or 502) for d in (hw.get("devices") or {}).values()}) or [502]
        self.storage = Storage(str(tmp_path / "d.db"))
        self.api = FakeApi(paired)
        self.version = "1.0.0+test"
        self.branch_name = "Test"
        self.ready = True
        self.hardware = HardwareConfig.from_dict(hw)
        self.config_problems: list[str] = []
        self._started_at = time.monotonic()
        self.io, self.signals, self.audio = FakeIo(), FakeSignals(), FakeAudio()
        self.events: list = []
        self.zones: dict = {}
        self.health: dict = {}
        self.power_status_url = None
        self.realtime = self.updater = None
        self.service_tokens: dict = {}
        self.pin_guard = PinGuard(self.storage, SecurityCfg())
        self.resolver = LocalResolver(DEVICE_ID, TOKEN)
        self.diagnostics = NetworkDiagnostics(self)

    def _device_id(self) -> str:
        return self.api.device_id

    async def emit(self, event) -> None:
        self.events.append(event)

    async def submit_code(self, code: str, source: str = "ui") -> dict:
        # stejná signatura jako `BoxController.submit_code` (BEZ `diagnostics_only`) — web endpoint
        # diagnostiky musí volat `controller_codes.submit_code` přímo, jinak by na jednotce padal
        return await cc.submit_code(self, code, source)

    def check_service_token(self, token) -> bool:
        return token == "svc-ok"

    def snapshot(self) -> dict:
        return {"ready": True, "zones": [], "diagnostics": self.diagnostics.status()}
