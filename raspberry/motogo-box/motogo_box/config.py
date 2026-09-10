"""Konfigurace MotoGo Boxu.

Dvě vrstvy:
1. **Lokální** (`/etc/motogo/config.yaml`) — Supabase, identita zařízení, cesty, intervaly, health.
2. **Hardwarová** — výchozí mapa z YAML (`config/brno-9zone.yaml`), kterou přepisuje
   konfigurace z Velína (`branch_kiosk_config.hardware` + `branch_doors.hw`).

Lokální sekce `diagnostics` (kód pro diagnostiku sítě z displeje, porty a podsítě scanu)
patří do vrstvy 1 — je vázaná na konkrétní Raspberry, ne na pobočku.
"""
from __future__ import annotations

import copy
import logging
import os
from dataclasses import dataclass, field
from typing import Any

import yaml

from .models import Zone, ZoneHw

log = logging.getLogger("motogo.config")

DEFAULT_CONFIG_PATH = "/etc/motogo/config.yaml"
HW_TOP_KEYS = ("devices", "timings", "polling", "contacts", "security", "audio", "signal")


# ─── Lokální konfigurace ─────────────────────────────────────────────────────
@dataclass
class SupabaseCfg:
    url: str = "https://vnwnqteskbykeucanlhk.supabase.co"
    anon_key: str = ""


@dataclass
class DeviceCfgLocal:
    id: str = ""
    token: str = ""
    name: str = ""


@dataclass
class PathsCfg:
    data_dir: str = "/var/lib/motogo"
    music_dir: str = "/var/lib/motogo/music"
    hardware_file: str = "/etc/motogo/hardware.yaml"
    mpv_socket: str = "/run/motogo/mpv.sock"


@dataclass
class WebCfg:
    host: str = "127.0.0.1"
    port: int = 8080


@dataclass
class IntervalsCfg:
    heartbeat_s: int = 30
    sync_s: int = 60
    command_poll_s: int = 10
    status_report_s: int = 30
    outbox_flush_s: int = 60
    io_poll_ms: int = 100


@dataclass
class HealthCfg:
    check_interval_s: int = 30
    probe_url: str = "https://vnwnqteskbykeucanlhk.supabase.co/auth/v1/health"
    nm_connection: str = "motogo-lte"
    modem_vid_pid: str = "1e0e:9001"
    usb_reset_script: str = "/usr/local/sbin/motogo-usbreset"
    reconnect_after: int = 5
    usb_reset_after: int = 5
    reboot_after: int = 3
    min_uptime_before_reboot_s: int = 1800


@dataclass
class DiagnosticsCfg:
    """Diagnostika sítě (`diagnostics.py`): kód z displeje + parametry scanu LAN."""

    code: str = "netdiag"           # kód zadaný na displeji (install.sh se ptá); prázdný = jen Velín/servis
    scan_ports: list = field(default_factory=lambda: [502, 80, 443, 22, 8080, 8443, 1883])
    scan_timeout_ms: int = 600
    scan_concurrency: int = 96
    scan_subnets: list = field(default_factory=list)   # CIDR navíc k podsítím rozhraní, např. 192.168.50.0/24
    max_hosts: int = 1024            # strop hostů na jednu podsíť (větší než /22 se přeskočí)
    internet_urls: list = field(default_factory=lambda: [
        "https://vnwnqteskbykeucanlhk.supabase.co/auth/v1/health", "https://www.google.com/generate_204"])
    timeout_s: int = 120             # limit běhu v režimu `network` (jen síť)
    full_timeout_s: int = 240        # limit kompletního běhu (`full`: síť + software, zóny, napájení, kamery)
    zone_test: bool = True           # False = zóny se jen čtou, nic se nespíná (technik nechce blikat)
    camera_timeout_s: int = 6        # timeout HTTP sond kamer a měniče FV


@dataclass
class LocalConfig:
    supabase: SupabaseCfg = field(default_factory=SupabaseCfg)
    device: DeviceCfgLocal = field(default_factory=DeviceCfgLocal)
    paths: PathsCfg = field(default_factory=PathsCfg)
    web: WebCfg = field(default_factory=WebCfg)
    intervals: IntervalsCfg = field(default_factory=IntervalsCfg)
    health: HealthCfg = field(default_factory=HealthCfg)
    diagnostics: DiagnosticsCfg = field(default_factory=DiagnosticsCfg)
    log_level: str = "INFO"


_BOOL_TRUE = ("1", "true", "yes", "on", "ano")
_BOOL_FALSE = ("0", "false", "no", "off", "ne", "")


def _coerce(cur: Any, v: Any) -> Any:
    """Převede `v` na typ výchozí hodnoty `cur` (None/dict/list = beze změny); neplatné → ValueError.

    bool bere i řetězce "true"/"false"/"1"/"0"/"ano"/"ne"; int odmítne desetinnou část.
    """
    if cur is None or isinstance(cur, (dict, list)):
        return v
    if isinstance(cur, bool):
        if isinstance(v, (bool, int, float)):
            return bool(v)
        sv = str(v).strip().lower()
        if sv in _BOOL_TRUE or sv in _BOOL_FALSE:
            return sv in _BOOL_TRUE
        raise ValueError(f"neplatná logická hodnota {v!r}")
    if isinstance(cur, int):
        f = float(v)
        if not f.is_integer():
            raise ValueError(f"očekáváno celé číslo, je {v!r}")
        return int(f)
    return type(cur)(v)


def _fill(dc_cls, d: Any):
    """Vytvoří dataclass z dictu; neznámé klíče ignoruje, chybějící nechá default.

    Neplatná hodnota (např. text v číselném poli z Velína) NIKDY neshodí start —
    zaloguje se a pole si ponechá výchozí hodnotu.
    """
    obj = dc_cls()
    if isinstance(d, dict):
        for k, v in d.items():
            if not hasattr(obj, k) or v is None:
                continue
            cur = getattr(obj, k)
            try:
                setattr(obj, k, _coerce(cur, v))
            except (TypeError, ValueError) as exc:
                log.warning("%s.%s: hodnota %r neplatná (%s) — ponechávám výchozí %r",
                            dc_cls.__name__, k, v, exc, cur)
    return obj


def load_local(path: str | None = None) -> LocalConfig:
    """Načte lokální konfiguraci; env `MOTOGO_CONFIG`, `MOTOGO_DEVICE_ID`, `MOTOGO_DEVICE_TOKEN` mají přednost."""
    path = path or os.environ.get("MOTOGO_CONFIG") or DEFAULT_CONFIG_PATH
    raw: dict = {}
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            raw = yaml.safe_load(f) or {}
    cfg = LocalConfig(
        supabase=_fill(SupabaseCfg, raw.get("supabase")),
        device=_fill(DeviceCfgLocal, raw.get("device")),
        paths=_fill(PathsCfg, raw.get("paths")),
        web=_fill(WebCfg, raw.get("web")),
        intervals=_fill(IntervalsCfg, raw.get("intervals")),
        health=_fill(HealthCfg, raw.get("health")),
        diagnostics=_fill(DiagnosticsCfg, raw.get("diagnostics")),
        log_level=str(raw.get("log_level") or "INFO"),
    )
    if os.environ.get("MOTOGO_DIAG_CODE"):
        cfg.diagnostics.code = os.environ["MOTOGO_DIAG_CODE"]
    if os.environ.get("MOTOGO_DEVICE_ID"):
        cfg.device.id = os.environ["MOTOGO_DEVICE_ID"]
    if os.environ.get("MOTOGO_DEVICE_TOKEN"):
        cfg.device.token = os.environ["MOTOGO_DEVICE_TOKEN"]
    return cfg


# ─── Hardwarová konfigurace ──────────────────────────────────────────────────
@dataclass
class DeviceCfg:
    name: str
    type: str                 # wav645 | wav617 | shelly_rgbww
    host: str
    port: int = 502
    unit_id: int = 1


@dataclass
class TimingsCfg:
    lock_pulse_ms: int = 800
    door_open_timeout_s: int = 30
    door_close_debounce_ms: int = 1000
    light_after_close_s: int = 30
    music_after_close_s: int = 10
    maximum_session_s: int = 600
    forced_open_debounce_ms: int = 500
    pin_entry_timeout_s: int = 20
    overtime_alert_minutes: list = field(default_factory=lambda: [10, 20, 30])


@dataclass
class PollingCfg:
    door_input_poll_ms: int = 100
    software_debounce_ms: int = 300
    modbus_timeout_ms: int = 500
    retry_delays_ms: list = field(default_factory=lambda: [100, 250, 500])
    device_offline_after_failures: int = 3


@dataclass
class SecurityCfg:
    maximum_failed_attempts: int = 5
    attempt_window_minutes: int = 5
    lockout_minutes: int = 15
    pin_length: int = 6
    mask_pin_on_screen: bool = True
    service_token_minutes: int = 10


@dataclass
class AudioCfg:
    volume: int = 70
    fade_in_ms: int = 1500
    fade_out_ms: int = 500
    selector_settle_ms: int = 200
    selector_on_ms: int = 100
    device: str | None = None     # mpv --audio-device (None = výchozí)
    shuffle: bool = True


@dataclass
class SignalCfg:
    brightness: int = 100
    blink_ms: int = 500
    pulse_ms: int = 1500
    transition_s: float = 0.2


@dataclass
class HardwareConfig:
    devices: dict[str, DeviceCfg]
    timings: TimingsCfg
    polling: PollingCfg
    contacts_closed_level: int
    security: SecurityCfg
    audio: AudioCfg
    signal: SignalCfg
    zones: list[Zone]
    source: str = "local"          # local | remote
    raw: dict = field(default_factory=dict)

    @classmethod
    def from_dict(cls, d: dict, doors: list[dict] | None = None) -> "HardwareConfig":
        d = d or {}
        devices: dict[str, DeviceCfg] = {}
        for name, dv in (d.get("devices") or {}).items():
            if not isinstance(dv, dict):
                continue
            devices[str(name)] = DeviceCfg(
                name=str(name), type=str(dv.get("type") or ""), host=str(dv.get("host") or ""),
                port=int(dv.get("port") or 502), unit_id=int(dv.get("unit_id") or 1),
            )
        zones = zones_from_doors(doors) if doors else []
        if not zones:
            zones = zones_from_local(d.get("zones") or [])
        zones.sort(key=lambda z: z.number)
        contacts = d.get("contacts") or {}
        return cls(
            devices=devices,
            timings=_fill(TimingsCfg, d.get("timings")),
            polling=_fill(PollingCfg, d.get("polling")),
            contacts_closed_level=int(contacts.get("closed_level", 1)),
            security=_fill(SecurityCfg, d.get("security")),
            audio=_fill(AudioCfg, d.get("audio")),
            signal=_fill(SignalCfg, d.get("signal")),
            zones=zones,
            raw=copy.deepcopy(d),
        )

    def zone_by_number(self, n: int) -> Zone | None:
        return next((z for z in self.zones if z.number == n), None)

    def zone_by_door(self, door_id: str) -> Zone | None:
        return next((z for z in self.zones if z.door_id and z.door_id == door_id), None)

    def zone_by_box(self, box_number: int) -> Zone | None:
        z = next((z for z in self.zones if z.box_number == box_number), None)
        return z or self.zone_by_number(box_number)

    def modbus_devices(self) -> dict[str, DeviceCfg]:
        return {n: d for n, d in self.devices.items() if d.type in ("wav645", "wav617")}

    def shelly_devices(self) -> dict[str, DeviceCfg]:
        return {n: d for n, d in self.devices.items() if d.type == "shelly_rgbww"}


def zones_from_local(items: list) -> list[Zone]:
    """Zóny z lokálního YAML (bez door_id; box_number = číslo zóny)."""
    out: list[Zone] = []
    for i, item in enumerate(items, start=1):
        hw = ZoneHw.from_dict(item, default_zone=i)
        if hw:
            out.append(Zone(hw=hw, door_id=None, box_number=hw.zone,
                            kind=str(item.get("kind") or "motorcycle"),
                            label=str(item.get("label") or "")))
    return out


def zones_from_doors(doors: list[dict]) -> list[Zone]:
    """Zóny z řádků `branch_doors` (bere jen dveře s neprázdným `hw`)."""
    out: list[Zone] = []
    for d in doors or []:
        hw_raw = d.get("hw") if isinstance(d, dict) else None
        if not isinstance(hw_raw, dict) or not hw_raw:
            continue
        hw = ZoneHw.from_dict(hw_raw, default_zone=d.get("box_number"))
        if not hw:
            continue
        out.append(Zone(hw=hw, door_id=d.get("id"), box_number=d.get("box_number"),
                        kind=str(d.get("door_kind") or "motorcycle"), label=str(d.get("label") or "")))
    return out


def load_hardware_file(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def merge_hardware(local: dict, remote: dict | None) -> dict:
    """Remote (Velín) přepisuje lokální po top-level klíčích; `zones` remote nikdy nenese."""
    out = copy.deepcopy(local or {})
    if not isinstance(remote, dict):
        return out
    for key in HW_TOP_KEYS:
        if key in remote and remote[key] is not None:
            if isinstance(remote[key], dict) and isinstance(out.get(key), dict):
                merged = copy.deepcopy(out[key])
                merged.update(copy.deepcopy(remote[key]))
                out[key] = merged
            else:
                out[key] = copy.deepcopy(remote[key])
    return out


# Počet kanálů modulů (index je 0-based): WAV645 16 relé, WAV617 8 relé + 8 vstupů, Shelly 5 světel.
CHANNEL_LIMITS = {"wav645": {"coil": 16, "input": 0}, "wav617": {"coil": 8, "input": 8}, "shelly_rgbww": {"light": 5}}
LOCK_PULSE_RANGE_MS = (100, 5000)


def validate_hardware(hw: HardwareConfig) -> list[str]:
    """Vrátí seznam problémů konfigurace (prázdný = OK).

    §12: zámek VÝHRADNĚ na WAV645 (HW flash-on — nezůstane pod napětím ani při pádu procesu);
    žádný kanál nesdílí dvě role ani uvnitř jedné zóny (lock==audio by držel zámek pod
    proudem po dobu hudby, light==audio by obcházel exkluzivitu audio selektoru).
    """
    problems: list[str] = []
    if not hw.zones:
        problems.append("Žádné zóny (branch_doors.hw ani lokální zones).")
    seen: dict[tuple[str, str, int], tuple[int, str]] = {}
    for z in hw.zones:
        refs = {"lock": z.hw.lock, "contact": z.hw.contact, "light": z.hw.light,
                "audio": z.hw.audio, "red": z.hw.red, "green": z.hw.green}
        for role, ref in refs.items():
            if ref is None:
                if role in ("lock", "contact"):
                    problems.append(f"Zóna {z.number}: chybí {role}.")
                continue
            dev = hw.devices.get(ref.dev)
            if dev is None:
                problems.append(f"Zóna {z.number}: {role} odkazuje na neznámé zařízení '{ref.dev}'.")
                continue
            if role in ("red", "green") and dev.type != "shelly_rgbww":
                problems.append(f"Zóna {z.number}: {role} musí být na Shelly (je {dev.type}).")
            if role == "lock" and dev.type != "wav645":
                problems.append(f"Zóna {z.number}: lock musí být relé WAV645 s HW flash-on (je {dev.type}).")
            if role in ("light", "audio") and dev.type not in ("wav645", "wav617"):
                problems.append(f"Zóna {z.number}: {role} musí být relé Waveshare (je {dev.type}).")
            if role == "contact" and dev.type != "wav617":
                problems.append(f"Zóna {z.number}: contact musí být vstup WAV617 (je {dev.type}).")
            if ref.idx < 0:
                problems.append(f"Zóna {z.number}: {role} má záporný index {ref.idx}.")
            kind = "input" if role == "contact" else ("light" if role in ("red", "green") else "coil")
            limit = CHANNEL_LIMITS.get(dev.type, {}).get(kind)
            if limit is not None and ref.idx >= limit:
                problems.append(f"Zóna {z.number}: {role} {ref.dev}[{ref.idx}] je mimo rozsah modulu {dev.type} (0–{limit - 1}).")
            key = (ref.dev, kind, ref.idx)
            if key in seen:
                other_zone, other_role = seen[key]
                if other_zone == z.number:
                    problems.append(f"Zóna {z.number}: {role} a {other_role} sdílí {ref.dev}[{ref.idx}].")
                else:
                    problems.append(f"Zóna {z.number}: {role} {ref.dev}[{ref.idx}] už používá "
                                    f"zóna {other_zone} ({other_role}).")
                continue
            seen[key] = (z.number, role)
    nums = [z.number for z in hw.zones]
    if len(nums) != len(set(nums)):
        problems.append("Duplicitní čísla zón.")
    lo, hi = LOCK_PULSE_RANGE_MS
    if not lo <= int(hw.timings.lock_pulse_ms) <= hi:
        problems.append(f"timings.lock_pulse_ms {hw.timings.lock_pulse_ms} je mimo rozsah {lo}–{hi} ms "
                        f"(WAV645 flash-on v krocích 100 ms).")
    return problems
