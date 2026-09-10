"""Čisté sondy pro health monitor (kontrakt §17) — parsování výstupů a systémové metriky.

Nic tady nespouští procesy s vedlejšími účinky: parsery dostávají text a vrací
dict/číslo, čtení metrik jen čte `/sys`, `/proc` a `shutil.disk_usage`; `tcp_probe`
jen otevře a zavře TCP spojení. Vše je bezpečné volat mimo Raspberry (vrací `None`/False).
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import shutil
import subprocess
from typing import Any

log = logging.getLogger("motogo.health")

THERMAL_PATH = "/sys/class/thermal/thermal_zone0/temp"
MEMINFO_PATH = "/proc/meminfo"
UPTIME_PATH = "/proc/uptime"


# ─── Pomocné konverze ────────────────────────────────────────────────────────
def to_num(value: Any) -> float | None:
    """`"-71.00"` → -71.0; `"--"`, prázdno, None → None (mmcli píše čísla jako řetězce)."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    s = str(value).strip()
    if not s or s == "--":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _dig(d: Any, *keys: str) -> Any:
    """Bezpečné zanoření do dictu; chybějící klíč → None."""
    cur = d
    for k in keys:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(k)
    return cur


def _load_json(text: str) -> dict | None:
    try:
        data = json.loads(text)
    except (TypeError, ValueError):
        return None
    return data if isinstance(data, dict) else None


# ─── ModemManager (mmcli -J) ─────────────────────────────────────────────────
def parse_mmcli_modem(text: str) -> dict:
    """Z `mmcli -m any -J` vytáhne stav, kvalitu signálu, operátora a technologii.

    Vrací `{"state": str, "signal_quality": int|None, "operator": str|None,
    "access_tech": str|None, "registration": str|None, "failed_reason": str|None}`;
    nečitelný vstup → state `unknown`. `failed_reason` = mmcli `state-failed-reason`
    (`sim-missing`, `sim-error`, …) — health podle něj pozná, že obnova LTE nemá smysl.
    """
    out: dict[str, Any] = {"state": "unknown", "signal_quality": None, "operator": None,
                           "access_tech": None, "registration": None, "failed_reason": None}
    data = _load_json(text)
    if data is None:
        return out
    generic = _dig(data, "modem", "generic") or {}
    gpp = _dig(data, "modem", "3gpp") or {}
    state = generic.get("state")
    if isinstance(state, str) and state.strip():
        out["state"] = state.strip().lower()
    q = to_num(_dig(generic, "signal-quality", "value"))
    out["signal_quality"] = int(q) if q is not None else None
    op = gpp.get("operator-name")
    out["operator"] = op.strip() if isinstance(op, str) and op.strip() and op != "--" else None
    techs = generic.get("access-technologies")
    if isinstance(techs, list) and techs:
        out["access_tech"] = ",".join(str(t) for t in techs)
    reg = gpp.get("registration-state")
    out["registration"] = reg if isinstance(reg, str) and reg not in ("", "--") else None
    reason = generic.get("state-failed-reason")
    if isinstance(reason, str) and reason.strip().lower() not in ("", "--", "none"):
        out["failed_reason"] = reason.strip().lower()
    return out


def parse_mmcli_signal(text: str) -> dict:
    """Z `mmcli -m any --signal-get -J` vytáhne LTE `rssi/rsrp/rsrq/snr` (dBm/dB) a refresh rate.

    Chybějící hodnoty (`"--"`) → None. `refresh_rate` 0 znamená, že je potřeba `--signal-setup`.
    """
    out: dict[str, Any] = {"rssi": None, "rsrp": None, "rsrq": None, "snr": None, "refresh_rate": 0}
    data = _load_json(text)
    if data is None:
        return out
    sig = _dig(data, "modem", "signal") or {}
    lte = sig.get("lte") if isinstance(sig.get("lte"), dict) else {}
    # 5G SA/NSA hlásí metriky ve větvi "5g"; LTE má přednost, 5g je záloha.
    nr = sig.get("5g") if isinstance(sig.get("5g"), dict) else {}
    for key in ("rssi", "rsrp", "rsrq", "snr"):
        val = to_num(lte.get(key))
        if val is None:
            val = to_num(nr.get(key))
        out[key] = val
    rate = to_num(_dig(sig, "refresh", "rate"))
    out["refresh_rate"] = int(rate) if rate is not None else 0
    return out


SIM_FAILED_REASONS = {"sim-missing": "sim_missing", "sim-error": "sim_error"}


def lte_error(modem: dict) -> str | None:
    """`sim_locked` (PIN), `sim_missing`/`sim_error` — stavy, kdy reconnect/USB reset/reboot nepomůže."""
    state = modem.get("state")
    if state == "locked":
        return "sim_locked"
    if state == "failed":
        return SIM_FAILED_REASONS.get(str(modem.get("failed_reason") or ""))
    return None


# ─── NetworkManager (nmcli -t) ───────────────────────────────────────────────
def parse_nmcli_connection(rc: int, text: str) -> dict:
    """Z `nmcli -t -f GENERAL.STATE,GENERAL.DEVICES con show <id>` udělá `{"nm_state","nm_device"}`.

    Neaktivní profil nemá sekci GENERAL (prázdný výstup) → `inactive`; nenulový rc → `missing`.
    """
    if rc != 0:
        return {"nm_state": "missing", "nm_device": None}
    state, device = "inactive", None
    for line in text.splitlines():
        key, _, val = line.partition(":")
        key, val = key.strip(), val.strip()
        if key == "GENERAL.STATE" and val:
            state = val.lower()
        elif key == "GENERAL.DEVICES" and val:
            device = val
    return {"nm_state": state, "nm_device": device}


# ─── Internet: TCP sonda ─────────────────────────────────────────────────────
async def tcp_probe(host: str, port: int, timeout: float = 8.0) -> bool:
    """TCP connect (bez dat) — sonda internetu nezávislá na HTTP i DNS; nikdy nevyhazuje."""
    try:
        _, writer = await asyncio.wait_for(asyncio.open_connection(host, port), timeout=timeout)
    except Exception:  # noqa: BLE001 — OSError, TimeoutError, …
        return False
    writer.close()
    try:
        await writer.wait_closed()
    except Exception:  # noqa: BLE001
        pass
    return True


# ─── Systémové metriky ───────────────────────────────────────────────────────
def parse_meminfo(text: str) -> float | None:
    """Procento volné paměti z obsahu `/proc/meminfo` (MemAvailable/MemTotal, fallback MemFree)."""
    values: dict[str, float] = {}
    for line in text.splitlines():
        key, _, rest = line.partition(":")
        parts = rest.split()
        if not parts:
            continue
        num = to_num(parts[0])
        if num is not None:
            values[key.strip()] = num
    total = values.get("MemTotal")
    avail = values.get("MemAvailable", values.get("MemFree"))
    if not total or avail is None:
        return None
    return round(100.0 * avail / total, 1)


def parse_throttled(text: str) -> str | None:
    """`throttled=0x50000` → `0x50000`."""
    s = (text or "").strip()
    if not s:
        return None
    _, _, val = s.partition("=")
    val = val.strip() or s
    return val if val.lower().startswith("0x") else None


def read_cpu_temp(path: str = THERMAL_PATH) -> float | None:
    """Teplota CPU ve °C z `/sys/class/thermal`; None mimo Raspberry."""
    try:
        with open(path, "r", encoding="ascii") as f:
            return round(int(f.read().strip()) / 1000.0, 1)
    except (OSError, ValueError):
        return None


def read_throttled() -> str | None:
    """`vcgencmd get_throttled` → hex maska (`0x0` = OK); None když příkaz chybí/selže."""
    try:
        proc = subprocess.run(["vcgencmd", "get_throttled"], capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    return parse_throttled(proc.stdout)


def disk_free_pct(path: str = "/") -> float:
    """Procento volného místa na svazku; při chybě 0.0 (bezpečná strana pro alarm)."""
    try:
        usage = shutil.disk_usage(path)
    except OSError:
        return 0.0
    if usage.total <= 0:
        return 0.0
    return round(100.0 * usage.free / usage.total, 1)


def mem_free_pct(path: str = MEMINFO_PATH) -> float:
    """Procento dostupné RAM; při chybě 0.0."""
    try:
        with open(path, "r", encoding="ascii") as f:
            val = parse_meminfo(f.read())
    except OSError:
        return 0.0
    return val if val is not None else 0.0


def read_uptime_s(path: str = UPTIME_PATH) -> float | None:
    """Uptime systému v sekundách z `/proc/uptime`."""
    try:
        with open(path, "r", encoding="ascii") as f:
            return float(f.read().split()[0])
    except (OSError, ValueError, IndexError):
        return None


def read_load1() -> float | None:
    try:
        return round(os.getloadavg()[0], 2)
    except (OSError, AttributeError):
        return None


def sys_metrics() -> dict:
    """Souhrn systémových metrik pro payload `health.sys` (kontrakt §14)."""
    return {
        "cpu_temp": read_cpu_temp(),
        "throttled": read_throttled(),
        "disk_free_pct": disk_free_pct("/"),
        "mem_free_pct": mem_free_pct(),
        "load1": read_load1(),
        "uptime_s": read_uptime_s(),
    }
