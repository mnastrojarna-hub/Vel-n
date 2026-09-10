"""Sondy pro diagnostiku sítě (`diagnostics.py`): rozhraní, routy, DNS, ARP, TCP scan
podsítě, identifikace Modbus (Waveshare) a Shelly, HTTP banner, ping, LTE.

Vše je bez vedlejších účinků (jen čtení + TCP connect / HTTP GET / Modbus FC01–02).
Primárně `ip -j …`; kde `ip` chybí (vývoj mimo Raspberry), fallback na `/proc`, `/sys`
a ioctl. Každá funkce vrací JSON-serializovatelná data a NIKDY nevyhazuje.
"""
from __future__ import annotations

import asyncio
import fcntl
import ipaddress
import json
import logging
import re
import socket
import struct
import time
from typing import Any, Iterable

import httpx

from .health import run_cmd
from .health_probe import parse_mmcli_modem, parse_mmcli_signal, parse_nmcli_connection
from .modbus import ModbusError, ModbusTcpClient

log = logging.getLogger("motogo.netscan")

SIOCGIFADDR, SIOCGIFNETMASK = 0x8915, 0x891B
_TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.I | re.S)
_PING_RE = re.compile(r"time[=<]([\d.]+)\s*ms")


def _ms(t0: float) -> float:
    return round((time.monotonic() - t0) * 1000.0, 1)


async def _ip_json(*args: str) -> list | None:
    rc, out = await run_cmd("ip", "-j", *args, timeout=5)
    if rc != 0:
        return None
    try:
        data = json.loads(out or "[]")
    except ValueError:
        return None
    return data if isinstance(data, list) else None


# ─── rozhraní / routy / DNS / ARP ───────────────────────────────────────────
def _ioctl_ipv4(name: str, req: int) -> str | None:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            res = fcntl.ioctl(s.fileno(), req, struct.pack("256s", name[:15].encode()))
        return socket.inet_ntoa(res[20:24])
    except OSError:
        return None


def _read(path: str) -> str:
    try:
        with open(path, "r", encoding="ascii") as f:
            return f.read().strip()
    except OSError:
        return ""


def _interfaces_fallback() -> list[dict]:
    out: list[dict] = []
    try:
        names = [n for _, n in socket.if_nameindex()]
    except OSError:
        names = []
    for name in names:
        if name == "lo":
            continue
        addr, mask = _ioctl_ipv4(name, SIOCGIFADDR), _ioctl_ipv4(name, SIOCGIFNETMASK)
        ipv4 = []
        if addr:
            prefix = ipaddress.IPv4Network(f"0.0.0.0/{mask}").prefixlen if mask else 24
            ipv4.append({"addr": addr, "prefix": prefix})
        out.append({"name": name, "mac": _read(f"/sys/class/net/{name}/address") or None,
                    "state": _read(f"/sys/class/net/{name}/operstate") or "unknown", "ipv4": ipv4, "ipv6": []})
    return out


async def interfaces() -> list[dict]:
    """`[{name, mac, state, mtu, ipv4:[{addr,prefix}], ipv6:[{addr,prefix}]}]` bez `lo`."""
    data = await _ip_json("addr")
    if data is None:
        return _interfaces_fallback()
    out: list[dict] = []
    for it in data:
        if not isinstance(it, dict) or it.get("ifname") == "lo":
            continue
        v4, v6 = [], []
        for a in it.get("addr_info") or []:
            entry = {"addr": a.get("local"), "prefix": a.get("prefixlen")}
            (v4 if a.get("family") == "inet" else v6).append(entry)
        out.append({"name": it.get("ifname"), "mac": it.get("address"), "state": str(it.get("operstate") or "").lower(),
                    "mtu": it.get("mtu"), "ipv4": v4, "ipv6": v6})
    return out


async def routes() -> list[dict]:
    """Výchozí brány: `[{gateway, dev, metric, dst}]` (z `ip -j route`, fallback /proc/net/route)."""
    data = await _ip_json("route")
    if data is not None:
        return [{"dst": r.get("dst"), "gateway": r.get("gateway"), "dev": r.get("dev"), "metric": r.get("metric")}
                for r in data if isinstance(r, dict) and r.get("dst") == "default"]
    out: list[dict] = []
    for line in _read("/proc/net/route").splitlines()[1:]:
        f = line.split()
        if len(f) >= 7 and f[1] == "00000000":
            gw = socket.inet_ntoa(struct.pack("<L", int(f[2], 16)))
            out.append({"dst": "default", "gateway": gw, "dev": f[0], "metric": int(f[6])})
    return out


def dns_servers() -> list[str]:
    return [ln.split()[1] for ln in _read("/etc/resolv.conf").splitlines()
            if ln.startswith("nameserver") and len(ln.split()) > 1]


async def arp_table() -> list[dict]:
    """`[{ip, mac, dev, state}]` — sousedé (po scanu podsítě je tabulka naplněná)."""
    data = await _ip_json("neigh")
    if data is not None:
        return [{"ip": n.get("dst"), "mac": n.get("lladdr"), "dev": n.get("dev"),
                 "state": ",".join(n.get("state") or [])} for n in data if isinstance(n, dict) and n.get("lladdr")]
    out: list[dict] = []
    for line in _read("/proc/net/arp").splitlines()[1:]:
        f = line.split()
        if len(f) >= 6 and f[3] != "00:00:00:00:00:00":
            out.append({"ip": f[0], "mac": f[3], "dev": f[5], "state": "reachable" if f[2] == "0x2" else "stale"})
    return out


async def resolve(host: str, timeout_s: float = 4.0) -> dict:
    """DNS překlad: `{host, addresses[], ms, error}`."""
    t0 = time.monotonic()
    try:
        infos = await asyncio.wait_for(asyncio.get_running_loop().getaddrinfo(host, None), timeout=timeout_s)
        addrs = sorted({i[4][0] for i in infos})
        return {"host": host, "addresses": addrs, "ms": _ms(t0), "error": None}
    except (OSError, asyncio.TimeoutError) as exc:
        return {"host": host, "addresses": [], "ms": _ms(t0), "error": str(exc) or type(exc).__name__}


# ─── TCP / HTTP / ping ───────────────────────────────────────────────────────
async def tcp_probe(host: str, port: int, timeout_s: float = 0.6) -> tuple[bool, float, str | None]:
    """TCP connect: `(open, ms, error)`."""
    t0 = time.monotonic()
    try:
        _r, w = await asyncio.wait_for(asyncio.open_connection(host, port), timeout=timeout_s)
        w.close()
        try:
            await w.wait_closed()
        except Exception:  # noqa: BLE001
            pass
        return True, _ms(t0), None
    except asyncio.TimeoutError:
        return False, _ms(t0), "timeout"
    except OSError as exc:
        return False, _ms(t0), exc.strerror or type(exc).__name__


def subnet_hosts(cidr: str, max_hosts: int = 1024) -> list[str]:
    """Adresy hostů podsítě (`strict=False`); větší než `max_hosts` → prázdný seznam (neskenuje se)."""
    try:
        net = ipaddress.ip_network(cidr, strict=False)
    except ValueError:
        return []
    if net.version != 4 or net.num_addresses - 2 > max_hosts:
        return []
    return [str(h) for h in net.hosts()]


async def scan_hosts(hosts: Iterable[str], ports: Iterable[int], *, timeout_s: float = 0.6,
                     concurrency: int = 96) -> dict[str, dict[int, float]]:
    """TCP scan: `{ip: {port: ms}}` jen pro otevřené porty."""
    sem = asyncio.Semaphore(max(1, int(concurrency)))
    found: dict[str, dict[int, float]] = {}

    async def one(ip: str, port: int) -> None:
        async with sem:
            ok, ms, _ = await tcp_probe(ip, port, timeout_s)
        if ok:
            found.setdefault(ip, {})[port] = ms

    await asyncio.gather(*(one(ip, p) for ip in hosts for p in ports))
    return {ip: dict(sorted(v.items())) for ip, v in sorted(found.items(), key=lambda kv: ipaddress.ip_address(kv[0]))}


async def http_info(host: str, port: int = 80, timeout_s: float = 2.0) -> dict | None:
    """`GET /` → `{status, server, title}`; nic neposlouchá → None."""
    scheme = "https" if port in (443, 8443) else "http"
    try:
        async with httpx.AsyncClient(timeout=timeout_s, verify=False, follow_redirects=False) as c:
            r = await c.get(f"{scheme}://{host}:{port}/")
    except Exception:  # noqa: BLE001
        return None
    m = _TITLE_RE.search(r.text[:20000] if r.text else "")
    return {"status": r.status_code, "server": r.headers.get("server"),
            "title": re.sub(r"\s+", " ", m.group(1)).strip()[:80] if m else None}


async def ping(host: str, timeout_s: float = 1.5) -> float | None:
    """ICMP ping (`ping -c1`) → RTT ms; bez binárky / bez odpovědi → None."""
    rc, out = await run_cmd("ping", "-c", "1", "-W", str(max(1, int(timeout_s))), host, timeout=timeout_s + 2)
    m = _PING_RE.search(out) if rc == 0 else None
    return float(m.group(1)) if m else None


# ─── identifikace zařízení ───────────────────────────────────────────────────
async def modbus_identify(host: str, port: int = 502, unit_id: int = 1, timeout_ms: int = 800) -> dict | None:
    """Zkusí FC01/FC02: `{modbus:true, coils, inputs, guess}`; guess wav645 (16 relé) / wav617 (8 relé + 8 DI)."""
    client = ModbusTcpClient(host, port, unit_id, timeout_ms=timeout_ms, retry_delays_ms=(), offline_after=1)
    coils = inputs = 0
    try:
        for n in (16, 8):
            try:
                coils = len(await client.read_coils(0, n))
                break
            except ModbusError:
                continue
        try:
            inputs = len(await client.read_discrete_inputs(0, 8))
        except ModbusError:
            inputs = 0
    except (OSError, asyncio.TimeoutError):
        return None
    finally:
        try:
            await client.close()
        except Exception:  # noqa: BLE001
            pass
    if not coils and not inputs:
        return None
    guess = "wav645" if coils >= 16 else "wav617" if coils == 8 and inputs == 8 else "modbus"
    return {"modbus": True, "coils": coils, "inputs": inputs, "guess": guess}


async def shelly_identify(host: str, port: int = 80, timeout_s: float = 2.0) -> dict | None:
    """Shelly Gen2+ `Shelly.GetDeviceInfo` (fallback Gen1 `/shelly`) → `{id, model, mac, fw, app, gen}`."""
    base = f"http://{host}" + (f":{port}" if port not in (80, 502) else "")
    try:
        async with httpx.AsyncClient(timeout=timeout_s) as c:
            r = await c.get(f"{base}/rpc/Shelly.GetDeviceInfo")
            if r.status_code == 200:
                d = r.json()
                if isinstance(d, dict) and isinstance(d.get("result"), dict):   # obálka {id, src, result}
                    d = d["result"]
                if isinstance(d, dict) and (d.get("id") or d.get("model") or d.get("app")):
                    return {"id": d.get("id"), "model": d.get("model"), "mac": d.get("mac"), "fw": d.get("fw_id") or d.get("ver"),
                            "app": d.get("app"), "gen": d.get("gen")}
            r = await c.get(f"{base}/shelly")
            if r.status_code == 200:
                d = r.json()
                if isinstance(d, dict) and (d.get("type") or d.get("mac")):
                    return {"id": d.get("id"), "model": d.get("type") or d.get("model"), "mac": d.get("mac"),
                            "fw": d.get("fw") or d.get("fw_id"), "app": d.get("app"), "gen": d.get("gen") or 1}
    except Exception:  # noqa: BLE001 — httpx / JSON / neplatná odpověď
        return None
    return None


# ─── LTE ─────────────────────────────────────────────────────────────────────
async def lte_info(nm_connection: str = "motogo-lte") -> dict:
    """Stav modemu z `mmcli`/`nmcli` (parsery z health_probe); bez ModemManageru → `state: unavailable`."""
    rc, out = await run_cmd("mmcli", "-m", "any", "-J", timeout=8)
    if rc != 0:
        info: dict[str, Any] = {"state": "unavailable", "error": (out or "").strip()[:160] or f"mmcli rc={rc}"}
    else:
        info = parse_mmcli_modem(out)
        rc2, out2 = await run_cmd("mmcli", "-m", "any", "--signal-get", "-J", timeout=8)
        if rc2 == 0:
            info.update(parse_mmcli_signal(out2))
    rc3, out3 = await run_cmd("nmcli", "-t", "-f", "GENERAL.STATE,GENERAL.DEVICES", "con", "show", nm_connection, timeout=8)
    info.update(parse_nmcli_connection(rc3, out3))
    info["nm_connection"] = nm_connection
    return info
