"""Sdílené datové typy MotoGo Boxu (stavy zón, signalizace, události).

Tento modul nemá žádné závislosti na I/O — používají ho všechny ostatní moduly.
"""
from __future__ import annotations

from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from enum import Enum
from typing import Any


def now_iso() -> str:
    """Aktuální čas jako ISO 8601 s časovou zónou (UTC)."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class ZoneState(str, Enum):
    """Stav jedné zóny (kóje) — viz specifikace §9."""

    SECURED = "SECURED"                          # zamčeno, červená
    WAITING_FOR_OPEN = "WAITING_FOR_OPEN"        # po pulzu zámku, čeká na otevření kontaktu
    DOOR_OPEN = "DOOR_OPEN"                      # dveře otevřené (relace běží)
    CLOSED_CONFIRMATION = "CLOSED_CONFIRMATION"  # zavřeno, doběh světla/hudby
    FAULT = "FAULT"                              # porucha (io_offline / forced_open / open_at_startup)


class Signal(str, Enum):
    """Vzor červené/zelené signalizace (specifikace §7)."""

    OFF = "off"
    RED = "red"
    GREEN = "green"
    GREEN_PULSE = "green_pulse"   # čekání na zavření / relace přesáhla limit
    RED_BLINK = "red_blink"       # porucha kontaktu / násilné otevření
    BOTH_BLINK = "both_blink"     # I/O modul nedostupný

    @classmethod
    def parse(cls, value: str | None) -> "Signal | None":
        if value is None:
            return None
        v = str(value).strip().lower()
        for s in cls:
            if s.value == v:
                return s
        return None


class EventKind(str, Enum):
    ACCESS_GRANTED = "ACCESS_GRANTED"
    ACCESS_DENIED = "ACCESS_DENIED"
    DOOR_OPENED = "DOOR_OPENED"
    DOOR_CLOSED = "DOOR_CLOSED"
    SESSION_COMPLETED = "SESSION_COMPLETED"
    OPEN_TIMEOUT = "OPEN_TIMEOUT"
    SESSION_OVERTIME = "SESSION_OVERTIME"
    SESSION_OVERTIME_ALERT = "SESSION_OVERTIME_ALERT"
    FORCED_OPEN = "FORCED_OPEN"
    CONTACT_FAULT = "CONTACT_FAULT"
    IO_OFFLINE = "IO_OFFLINE"
    IO_ONLINE = "IO_ONLINE"
    PIN_INVALID = "PIN_INVALID"
    PIN_LOCKOUT = "PIN_LOCKOUT"
    STARTUP = "STARTUP"
    CONFIG_PROBLEM = "CONFIG_PROBLEM"
    LTE_RESET = "LTE_RESET"
    REBOOT = "REBOOT"
    REMOTE_COMMAND = "REMOTE_COMMAND"
    RPC_ERROR = "RPC_ERROR"                      # ověření kódu selhalo na straně serveru/párování (ne neplatný PIN)
    DIAGNOSTICS = "DIAGNOSTICS"                  # dokončená diagnostika sítě (souhrn; celý report → kiosk_diagnostics)
    SHELL = "SHELL"                              # servisní terminál na displeji — spuštěný příkaz (§27)


@dataclass(frozen=True)
class HwRef:
    """Odkaz na jeden kanál hardwaru: zařízení + index (coil / input / light)."""

    dev: str
    idx: int

    @classmethod
    def from_dict(cls, d: Any, key: str) -> "HwRef | None":
        """`key` = 'coil' | 'input' | 'light' — akceptuje i obecné 'idx'."""
        if not isinstance(d, dict) or not d.get("dev"):
            return None
        raw = d.get(key, d.get("idx"))
        if raw is None:
            return None
        try:
            return cls(str(d["dev"]), int(raw))
        except (TypeError, ValueError):
            return None


# Časování, které smí být nastavené ZVLÁŠŤ pro jednu zónu (`branch_doors.hw.timings`) — 2026-09-14.
# Kóje 1–7 mají stejné nastavení (globální `timings`), ale šatna se používá jinak než garáž
# (zákazník se v ní převléká déle), takže si smí přepsat jen tyto doby. Ostatní časování (pulz zámku,
# debounce, PIN) zůstává společné pro celou pobočku — na jedné zóně nedává smysl a jen by se rozešlo.
ZONE_TIMING_KEYS = ("door_open_timeout_s", "light_after_close_s", "music_after_close_s", "maximum_session_s")


def _opt_bool(value: Any) -> bool | None:
    """Volitelný přepínač z JSON: None/prázdné = „dle pobočky“, jinak pravdivostní hodnota.
    Tolerantní jako zbytek `from_dict` — text „false“/„0“ z Velína se bere jako vypnuto."""
    if value is None or value == "":
        return None
    if isinstance(value, str):
        return value.strip().lower() not in ("false", "0", "ne", "off", "")
    return bool(value)


def zone_timings(value: Any) -> dict | None:
    """Override časování zóny z JSON: jen známé klíče s nezáporným celým číslem; jinak None.
    Tolerantní jako zbytek `from_dict` — nesmysl z Velína zónu nikdy neshodí, jen se ignoruje."""
    if not isinstance(value, dict):
        return None
    out: dict[str, int] = {}
    for key in ZONE_TIMING_KEYS:
        raw = value.get(key)
        if raw is None or raw == "":
            continue
        try:
            n = int(raw)
        except (TypeError, ValueError):
            continue
        if n >= 0:
            out[key] = n
    return out or None


@dataclass(frozen=True)
class ZoneHw:
    """Hardwarová mapa jedné zóny (= `branch_doors.hw` nebo položka `zones` v YAML)."""

    zone: int
    lock: HwRef | None = None      # WAV645 coil (zámek — jen HW pulz)
    contact: HwRef | None = None   # WAV617 input (dveřní NC kontakt)
    light: HwRef | None = None     # WAV617 coil (bílé světlo)
    audio: HwRef | None = None     # coil audio selektoru (selector) / volitelné „enable" relé zesilovače (multi)
    red: HwRef | None = None       # Shelly light id (červená)
    green: HwRef | None = None     # Shelly light id (zelená)
    closed_level: int | None = None  # override globálního contacts.closed_level
    audio_out: str | None = None   # režim multi: název výstupu z `audio.outputs` (`audio: {out: out1}`)
    timings: dict | None = None    # override globálního `timings` jen pro tuto zónu (ZONE_TIMING_KEYS)
    music_enabled: bool | None = None   # hudba v této zóně: None = dle pobočky (`audio.music_enabled`), True/False = přepis

    @classmethod
    def from_dict(cls, d: dict, default_zone: int | None = None) -> "ZoneHw | None":
        if not isinstance(d, dict):
            return None
        zone = d.get("zone", default_zone)
        if zone is None:
            return None
        try:
            zone = int(zone)
        except (TypeError, ValueError):
            return None
        cl = d.get("closed_level")
        audio = d.get("audio")
        out = audio.get("out") if isinstance(audio, dict) else None
        return cls(
            zone=zone,
            lock=HwRef.from_dict(d.get("lock"), "coil"),
            contact=HwRef.from_dict(d.get("contact"), "input"),
            light=HwRef.from_dict(d.get("light"), "coil"),
            audio=HwRef.from_dict(audio, "coil"),
            red=HwRef.from_dict(d.get("red"), "light"),
            green=HwRef.from_dict(d.get("green"), "light"),
            closed_level=int(cl) if cl is not None else None,
            audio_out=str(out).strip() or None if out not in (None, "") else None,
            timings=zone_timings(d.get("timings")),
            music_enabled=_opt_bool(d.get("music_enabled")),
        )

    def to_dict(self) -> dict:
        def ref(r: HwRef | None, key: str) -> dict | None:
            return None if r is None else {"dev": r.dev, key: r.idx}
        out: dict[str, Any] = {
            "zone": self.zone,
            "lock": ref(self.lock, "coil"),
            "contact": ref(self.contact, "input"),
            "light": ref(self.light, "coil"),
            "audio": ref(self.audio, "coil"),
            "red": ref(self.red, "light"),
            "green": ref(self.green, "light"),
        }
        if self.audio_out:
            out["audio"] = {**(out["audio"] or {}), "out": self.audio_out}
        if self.closed_level is not None:
            out["closed_level"] = self.closed_level
        if self.timings:
            out["timings"] = dict(self.timings)
        if self.music_enabled is not None:
            out["music_enabled"] = self.music_enabled
        return out


# Zóna s výbavou (`kind='accessories'`) se od 2026-09-14 jmenuje „Šatna" — ve Velíně, na displeji i v logu.
# Historicky „Oblečení" / „Skříň oblečení"; `door_kind` v DB se NEMĚNÍ (páruje se podle něj kód k výbavě).
ACCESSORIES_NAME = "Šatna"


@dataclass
class Zone:
    """Logická zóna = řádek `branch_doors` (nebo lokální fallback) + HW mapa."""

    hw: ZoneHw
    door_id: str | None = None
    box_number: int | None = None
    kind: str = "motorcycle"        # motorcycle | accessories
    label: str = ""

    @property
    def number(self) -> int:
        return self.hw.zone

    @property
    def display_name(self) -> str:
        """Název zóny pro Velín, displej a logy. Jednotné pojmenování (2026-09-14):
        kóje na motorku = „Kóje N", zóna s výbavou (`kind='accessories'`) = „Šatna", venek řeší
        `OutdoorController` mimo zóny. `kind` v DB zůstává `accessories` — mění se jen text.
        Vlastní popis dveří z Velína (`branch_doors.label`) má vždy přednost."""
        if self.label:
            return self.label
        if self.kind == "accessories":
            return ACCESSORIES_NAME
        if self.box_number is not None:
            return f"Kóje {self.box_number}"
        return f"Zóna {self.number}"


@dataclass
class ZoneStatus:
    zone: int
    door_id: str | None
    box_number: int | None
    kind: str
    label: str
    state: str
    door_closed: bool | None
    fault: str | None
    light: bool
    signal: str
    music: bool
    session_started_at: str | None
    booking_id: str | None
    last_event: str | None
    latch_released: bool = False   # IBFM po OPEN_TIMEOUT stále odjištěný (pozdní otevření = relace, ne forced_open)
    degraded: bool = False         # relace běží s částí I/O offline (nový přístup zamítnut)
    music_enabled: bool = True     # smí v této zóně po kódu hrát hudba (vypínač pobočky / přepis zóny)

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class ServiceDoor:
    """Dveře nabídnuté po servisním hesle (výběr v UI / Velíně)."""

    id: str | None
    kind: str
    box_number: int | None
    label: str
    zone: int | None
    configured: bool

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class ResolveResult:
    """Výsledek ověření kódu (online RPC `kiosk_resolve_code` nebo offline cache)."""

    ok: bool
    error: str | None = None
    kind: str = ""                  # motorcycle | accessories | service
    booking_id: str | None = None
    door_id: str | None = None
    box_number: int | None = None
    door_configured: bool = False
    doors: list[ServiceDoor] = field(default_factory=list)
    offline: bool = False           # ověřeno z lokální cache
    action: str = "service"         # u servisního hesla: service (panel) | diagnostics (jen diagnostika sítě)

    @property
    def is_service(self) -> bool:
        return self.kind == "service"

    @property
    def is_diagnostics(self) -> bool:
        return self.kind == "service" and self.action == "diagnostics"

    @classmethod
    def from_rpc(cls, m: dict) -> "ResolveResult":
        """Z odpovědi `kiosk_resolve_code` (viz migrace 20260628_selfservice_kiosk.sql)."""
        door = m.get("door") if isinstance(m.get("door"), dict) else None
        doors: list[ServiceDoor] = []
        for d in m.get("doors") or []:
            if isinstance(d, dict):
                doors.append(ServiceDoor(
                    id=d.get("id"), kind=d.get("door_kind") or "", box_number=d.get("box_number"),
                    label=d.get("label") or "", zone=None,
                    configured=bool(d.get("hw")) or bool(d.get("relay_url")),
                ))
        box = m.get("box_number")
        if box is None and door:
            box = door.get("box_number")
        return cls(
            ok=bool(m.get("ok")),
            error=m.get("error"),
            kind=m.get("kind") or "",
            booking_id=m.get("booking_id"),
            door_id=door.get("id") if door else None,
            box_number=box,
            door_configured=bool(m.get("door_configured")) or bool(door),
            doors=doors,
            action=str(m.get("action") or "service"),
        )


@dataclass
class Event:
    kind: EventKind
    zone: int | None = None
    door_id: str | None = None
    booking_id: str | None = None
    success: bool = True
    level: str = "info"             # info | warn | error
    message: str = ""
    detail: dict = field(default_factory=dict)
    ts: str = field(default_factory=now_iso)
    box_number: int | None = None
    code_kind: str | None = None    # motorcycle | accessories | service | invalid

    def to_dict(self) -> dict:
        d = asdict(self)
        d["kind"] = self.kind.value
        return d
