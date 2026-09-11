"""Diagnostika pobočky řídicí jednotky — `NetworkDiagnostics` (kontrakt §24).

Režimy: `full` (výchozí — síť + software, konfigurace, zóny a periferie, napájení FV, kamery
+ protokol) a `network` (jen síťové kroky, rychlý běh). Spouští se (1) diagnostickým kódem
z displeje (`diagnostics.code` v config.yaml — funguje i před spárováním), (2) servisním heslem
z Velína s účelem `diagnostics` (nebo běžným servisním heslem ze servisního panelu), (3) příkazem
`diagnostics` z Velína (`params {mode, cameras, reason}`). Běží jako jeden task na pozadí (další
požadavek během běhu → `already_running`), po dokončení se report uloží do `Storage.kv`
(`last_diagnostics`), odešle do Velína RPC `kiosk_report_diagnostics` (přes outbox) a zapíše
souhrnnou událost `DIAGNOSTICS`. Nové kroky: `diag_steps.py`; protokol a souhrn: `diag_protocol.py`.
Zobrazení na displeji: `GET /api/diagnostics` + `snapshot()['diagnostics']` (progres).
"""
from __future__ import annotations

import asyncio
import hmac
import ipaddress
import logging
import platform
import socket
import time
import uuid
from typing import TYPE_CHECKING, Any, Awaitable, Callable
from urllib.parse import urlsplit

import httpx

from . import diag_steps, net_scan
from .diag_protocol import STEP_TITLES, build_protocol, build_summary
from .health_probe import sys_metrics
from .models import Event, EventKind, now_iso
from .pins import normalize_code

if TYPE_CHECKING:  # pragma: no cover
    from .controller import BoxController

log = logging.getLogger("motogo.diagnostics")

KV_LAST = "last_diagnostics"
KV_CAMERAS = "diag_cameras"
NETWORK_STEPS = ("system", "interfaces", "lte", "internet", "supabase", "devices", "lan", "arp", "summary")
STEPS = ("system", "interfaces", "lte", "internet", "supabase", "devices", "software", "config", "zones", "power",
         "cameras", "lan", "arp", "summary")
FULL_ONLY = ("software", "config", "zones", "power", "cameras")
MODES = ("full", "network")
INTERNET_TCP = ("1.1.1.1", 443)
MODBUS_PORTS = (502,)                  # identifikace Waveshare (FC01/FC02)
WEB_PORTS = (80, 8080, 443, 8443)      # identifikace Shelly (RPC) / HTTP banner
MAX_CAMERAS = 20


class NetworkDiagnostics:
    """Jeden běh = report `{id, ts, mode, …, protocol, summary}`; `status()` = krátký stav pro UI/Velín."""

    def __init__(self, ctrl: "BoxController") -> None:
        self.ctrl = ctrl
        self.cfg = ctrl.local.diagnostics
        self.running = False
        self.mode: str = "full"
        self.pending_mode: str | None = None          # hint z `/api/diagnostics/run` pro start přes kód
        self.step: str | None = None
        self.done: list[str] = []
        self.started_at: float | None = None
        self.deadline: float | None = None           # monotonic; kroky (HW test zón) podle něj hlídají zbývající čas
        self._task: asyncio.Task | None = None
        self.current_id: str | None = None
        self.last_error: str | None = None
        self._cameras: list[dict] | None = None
        self._partial: dict[str, Any] = {}           # rozpracované výsledky kroků (přežijí timeout kroku)
        self._last_summary: dict | None = self._summary_of(self.last_report())   # snapshot() ho čte 5× za s

    # ─── kód / stav ──────────────────────────────────────────────────────
    def matches_local_code(self, code: str) -> bool:
        cfg_code = normalize_code(str(self.cfg.code or "")).lower()
        code = normalize_code(code or "").lower()
        return bool(cfg_code) and hmac.compare_digest(cfg_code.encode("utf-8"), code.encode("utf-8"))

    def last_report(self) -> dict | None:
        rep = self.ctrl.storage.kv_get(KV_LAST)
        return rep if isinstance(rep, dict) else None

    def cameras_list(self) -> list[dict]:
        """Kamery pro krok `cameras`: z parametrů běhu, jinak poslední seznam od Velína (`kv diag_cameras`)."""
        cams = self._cameras
        if cams is None:
            cams = self.ctrl.storage.kv_get(KV_CAMERAS)
        return [c for c in (cams if isinstance(cams, list) else []) if isinstance(c, dict)][:MAX_CAMERAS]

    @staticmethod
    def _summary_of(last: dict | None) -> dict | None:
        if not last:
            return None
        summary = last.get("summary") or {}
        return {"id": last.get("id"), "ts": last.get("ts"), "ok": summary.get("ok"), "mode": last.get("mode") or "network",
                "problems": len(summary.get("problems") or []), "warnings": len(summary.get("warnings") or []),
                "hosts": summary.get("hosts"), "zones_ok": summary.get("zones_ok"), "zones_total": summary.get("zones_total"),
                "duration_s": last.get("duration_s"), "source": last.get("source")}

    def status(self) -> dict:
        return {
            "running": self.running, "id": self.current_id, "mode": self.mode, "step": self.step,
            "step_title": STEP_TITLES.get(self.step or "", self.step), "done": list(self.done),
            "steps": list(NETWORK_STEPS if self.mode == "network" else STEPS),
            "elapsed_s": int(time.monotonic() - self.started_at) if self.running and self.started_at else None,
            "error": self.last_error,
            "last": dict(self._last_summary) if self._last_summary else None,
        }

    # ─── spuštění ────────────────────────────────────────────────────────
    def start(self, source: str, reason: str | None = None, *, mode: str | None = None,
              cameras: list | None = None) -> dict:
        """Spustí běh na pozadí; `{ok, started, id, mode}` nebo `{ok:false, error:'already_running', id}`.

        `mode` = full (výchozí) | network; None → `pending_mode` (hint z webu) nebo full.
        `cameras` (seznam z Velína) se uloží do kv `diag_cameras` pro lokální běhy bez Velína.
        """
        mode = str(mode or self.pending_mode or "full").lower()
        self.pending_mode = None
        if mode not in MODES:
            mode = "full"
        if isinstance(cameras, list):
            cams = [c for c in cameras if isinstance(c, dict)][:MAX_CAMERAS]
            try:
                self.ctrl.storage.kv_set(KV_CAMERAS, cams)
            except Exception:  # noqa: BLE001
                log.exception("Uložení seznamu kamer selhalo")
        if self.running and self._task is not None and not self._task.done():
            return {"ok": False, "error": "already_running", "id": self.current_id, "mode": self.mode}
        self._cameras = [c for c in cameras if isinstance(c, dict)] if isinstance(cameras, list) else None
        self.current_id = uuid.uuid4().hex[:12]
        self.mode = mode
        self.running, self.step, self.done, self.last_error = True, None, [], None
        self.started_at = time.monotonic()
        self._task = asyncio.create_task(self._run_safe(source, reason or source), name="motogo.diagnostics")
        log.info("Diagnostika %s (%s) spuštěna (%s)", self.current_id, mode, source)
        return {"ok": True, "started": True, "id": self.current_id, "mode": mode}

    def time_left(self) -> float | None:
        """Zbývající čas běhu v s (None mimo běh) — HW test zóny se nespustí, když by se nestihl."""
        return None if self.deadline is None else self.deadline - time.monotonic()

    async def cancel(self) -> None:
        if self._task is not None and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass
        self.running = False

    async def wait(self) -> dict | None:
        """(testy) počká na dokončení běžícího běhu a vrátí report."""
        if self._task is not None:
            try:
                return await self._task
            except Exception:  # noqa: BLE001
                return None
        return self.last_report()

    async def _run_safe(self, source: str, reason: str) -> dict:
        try:
            return await self.run(source, reason)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 — chyba mimo kroky (souhrn, uložení) nesmí zmizet beze stopy
            self.last_error = f"{type(exc).__name__}: {str(exc)[:200]}"
            log.exception("Diagnostika %s selhala", self.current_id)
            raise
        finally:
            self.running, self.step = False, None

    def _steps(self) -> list[tuple[str, Callable[[dict], Awaitable[Any]]]]:
        """Pořadí kroků: HW testy zón dřív než dlouhý scan LAN, aby se stihly v limitu."""
        full = self.mode != "network"
        table: list[tuple[str, Any]] = [
            ("system", self._system), ("interfaces", self._interfaces), ("lte", self._lte),
            ("internet", self._internet), ("supabase", self._supabase), ("devices", self._devices),
            ("software", self._delegate(diag_steps.software)), ("config", self._delegate(diag_steps.config)),
            ("zones", self._delegate(diag_steps.zones)), ("power", self._delegate(diag_steps.power)),
            ("cameras", self._delegate(diag_steps.cameras)), ("lan", self._lan), ("arp", self._arp),
        ]
        return [(n, fn) for n, fn in table if full or n not in FULL_ONLY]

    def _delegate(self, fn):
        async def run(report: dict):
            return await fn(self, report)
        return run

    async def run(self, source: str, reason: str) -> dict:
        """Provede všechny kroky (každý izolovaně, s limitem), uloží, odešle a zaloguje report."""
        ctrl = self.ctrl
        t0 = time.monotonic()
        report: dict[str, Any] = {
            "id": self.current_id or uuid.uuid4().hex[:12], "ts": now_iso(), "source": source, "reason": reason, "mode": self.mode,
            "version": ctrl.version, "device_id": ctrl._device_id() or None, "branch_name": ctrl.branch_name,
            "paired": bool(getattr(ctrl.api, "paired", False)), "steps": {},
        }
        limit = self.cfg.timeout_s if self.mode == "network" else getattr(self.cfg, "full_timeout_s", 240)
        deadline = self.deadline = t0 + max(20, int(limit))
        self._partial = {}
        self.last_error = None
        for name, fn in self._steps():
            self.step = name
            ts = time.monotonic()
            left = deadline - ts
            try:
                if left <= 0:
                    raise asyncio.TimeoutError()
                report[name] = await asyncio.wait_for(fn(report), timeout=left)
                report["steps"][name] = {"ok": True, "ms": round((time.monotonic() - ts) * 1000)}
            except asyncio.CancelledError:
                raise
            except asyncio.TimeoutError:
                # co se stihlo, zůstává (scan LAN s desítkami hostů, část zón) — jen označeno jako neúplné
                report[name] = self._partial.get(name)
                report["steps"][name] = {"ok": False, "error": "timeout", "partial": report[name] is not None,
                                         "ms": round((time.monotonic() - ts) * 1000)}
            except Exception as exc:  # noqa: BLE001 — jeden krok nesmí shodit celý běh
                log.exception("Diagnostika: krok %s selhal", name)
                report[name] = None
                report["steps"][name] = {"ok": False, "error": str(exc)[:200], "ms": round((time.monotonic() - ts) * 1000)}
            self.done.append(name)
        self.step = "summary"
        report["duration_s"] = round(time.monotonic() - t0, 1)
        report["protocol"] = build_protocol(report)
        report["summary"] = build_summary(report, report["protocol"])
        self.done.append("summary")
        report["finished_at"] = now_iso()
        self._last_summary = self._summary_of(report)
        try:
            ctrl.storage.kv_set(KV_LAST, report)
        except Exception:  # noqa: BLE001
            log.exception("Uložení reportu diagnostiky selhalo")
        try:
            await ctrl.api.report_diagnostics(report)
        except Exception:  # noqa: BLE001
            log.exception("Odeslání reportu diagnostiky selhalo")
        self.deadline = None
        s = report["summary"]
        verdict = "OK" if s["ok"] else f"{len(s['problems'])} problémů, {len(s.get('warnings') or [])} varování"
        # zóny do textu jen když krok `zones` běžel (režim full) — v režimu network by „0/0 zón OK“ mátlo
        zones_txt = f"{s.get('zones_ok')}/{s.get('zones_total')} zón OK, " if isinstance(report.get("zones"), list) else ""
        await ctrl.emit(Event(kind=EventKind.DIAGNOSTICS, success=bool(s["ok"]), level="info" if s["ok"] else "warn",
                              message=f"Diagnostika pobočky: {verdict} ({zones_txt}{s['hosts']} zařízení v LAN, {report['duration_s']} s)",
                              detail={"source": source, "report_id": report["id"], "mode": self.mode, "problems": s["problems"][:20],
                                      "warnings": (s.get("warnings") or [])[:20], "hosts": s["hosts"], "internet": s.get("internet"),
                                      "checks": s.get("checks")}))
        log.info("Diagnostika %s hotova za %s s: %s", report["id"], report["duration_s"], s["problems"] or "OK")
        return report

    # ─── síťové kroky ────────────────────────────────────────────────────
    async def _system(self, report: dict) -> dict:
        rc, out = await net_scan.run_cmd("timedatectl", "show", "-p", "NTPSynchronized", "-p", "TimeUSec", timeout=5)
        ntp = dict(ln.split("=", 1) for ln in out.splitlines() if "=" in ln) if rc == 0 else {}
        u = platform.uname()
        metrics = await asyncio.get_running_loop().run_in_executor(None, sys_metrics)   # vcgencmd = subprocess.run
        return {"hostname": socket.gethostname(), "kernel": u.release, "machine": u.machine, "python": platform.python_version(),
                "time": now_iso(), "ntp_synced": {"yes": True, "no": False}.get(ntp.get("NTPSynchronized", ""), None),
                "metrics": metrics, "controller_uptime_s": int(time.monotonic() - self.ctrl._started_at),
                "ready": self.ctrl.ready, "config_source": self.ctrl.hardware.source,
                "config_problems": list(self.ctrl.config_problems)}

    async def _interfaces(self, report: dict) -> dict:
        ifaces, routes = await net_scan.interfaces(), await net_scan.routes()
        return {"interfaces": ifaces, "default_routes": routes, "dns": net_scan.dns_servers()}

    async def _lte(self, report: dict) -> dict:
        return await net_scan.lte_info(self.ctrl.local.health.nm_connection)

    async def _internet(self, report: dict) -> dict:
        urls = [u for u in (self.cfg.internet_urls or []) if isinstance(u, str) and u.startswith("http")]
        names = {urlsplit(u).hostname for u in urls} | {urlsplit(self.ctrl.local.supabase.url).hostname}
        dns = [await net_scan.resolve(h) for h in sorted(n for n in names if n)]
        ok, ms, err = await net_scan.tcp_probe(*INTERNET_TCP, timeout_s=3.0)
        probes = []
        async with httpx.AsyncClient(timeout=6.0, follow_redirects=True) as c:
            for u in urls:
                t = time.monotonic()
                try:
                    r = await c.get(u)
                    probes.append({"url": u, "status": r.status_code, "ms": round((time.monotonic() - t) * 1000), "error": None})
                except Exception as exc:  # noqa: BLE001
                    probes.append({"url": u, "status": None, "ms": round((time.monotonic() - t) * 1000), "error": type(exc).__name__})
        http_ok = any(p["status"] is not None and p["status"] < 500 for p in probes)
        dns_ok = any(d.get("addresses") for d in dns)
        # bez HTTP sond (prázdné internet_urls / bez DNS) rozhoduje TCP na 1.1.1.1 + DNS
        return {"dns": dns, "tcp": {"host": INTERNET_TCP[0], "port": INTERNET_TCP[1], "open": ok, "ms": ms, "error": err},
                "http": probes, "ok": http_ok or (not probes and ok and (dns_ok or not dns))}

    async def _supabase(self, report: dict) -> dict:
        api = self.ctrl.api
        out: dict[str, Any] = {"url": self.ctrl.local.supabase.url, "paired": bool(getattr(api, "paired", False)),
                               "device_id": self.ctrl._device_id() or None, "outbox_pending": None}
        try:
            out["outbox_pending"] = self.ctrl.storage.outbox_count()
        except Exception:  # noqa: BLE001
            pass
        if not out["paired"]:
            out.update({"ok": None, "error": "not_paired"})
            return out
        t = time.monotonic()
        res = await api.heartbeat()
        out.update({"ok": isinstance(res, dict), "ms": round((time.monotonic() - t) * 1000),
                    "branch_name": (res or {}).get("branch_name") if isinstance(res, dict) else None,
                    "error": None if isinstance(res, dict) else "heartbeat_failed"})
        return out

    async def _devices(self, report: dict) -> list[dict]:
        polling = self.ctrl.hardware.polling
        out: list[dict] = []
        for name, dev in self.ctrl.hardware.devices.items():
            port = dev.port if dev.type != "shelly_rgbww" or dev.port != 502 else 80
            open_, ms, err = await net_scan.tcp_probe(dev.host, port, timeout_s=max(0.3, polling.modbus_timeout_ms / 1000))
            item: dict[str, Any] = {"name": name, "type": dev.type, "host": dev.host, "port": port, "reachable": open_,
                                    "ms": ms, "error": err, "ping_ms": await net_scan.ping(dev.host), "identified": None,
                                    "online": (self.ctrl.io.is_online(name) if dev.type != "shelly_rgbww" else self.ctrl.signals.online(name))}
            if open_:
                if dev.type == "shelly_rgbww":
                    item["identified"] = await net_scan.shelly_identify(dev.host, port)
                else:
                    item["identified"] = await net_scan.modbus_identify(dev.host, port, dev.unit_id, polling.modbus_timeout_ms)
            out.append(item)
        return out

    async def _lan(self, report: dict) -> dict:
        """TCP scan LAN: jen podsítě rozhraní BEZ výchozí brány (eth*) a privátní IPv4 — nikdy WWAN/LTE
        (metrovaná linka, cizí síť operátora) — plus `scan_subnets`. Identifikace hostů běží souběžně
        (semafor), rozpracovaný výsledek přežije timeout kroku (`self._partial`)."""
        ifc = report.get("interfaces") or {}
        wan_devs = {str(r.get("dev")) for r in ifc.get("default_routes") or [] if r.get("dev")}
        subnets: list[str] = []
        skipped: list[dict] = []
        for it in ifc.get("interfaces") or []:
            for a in it.get("ipv4") or []:
                if not (a.get("addr") and a.get("prefix")):
                    continue
                cidr = f"{a['addr']}/{a['prefix']}"
                try:
                    private = ipaddress.ip_address(str(a["addr"])).is_private
                except ValueError:
                    continue
                if it.get("name") in wan_devs or not private or str(it.get("name") or "").startswith(("wwan", "ppp", "wwp")):
                    skipped.append({"subnet": cidr, "reason": "wan"})
                else:
                    subnets.append(cidr)
        subnets += [x for x in (self.cfg.scan_subnets or []) if isinstance(x, str)]
        subnets = list(dict.fromkeys(subnets))          # bez duplicit (rozhraní + scan_subnets)
        hosts: dict[str, None] = {}
        scanned: list[str] = []
        for cidr in subnets:
            hs = net_scan.subnet_hosts(cidr, self.cfg.max_hosts)
            if hs:
                scanned.append(cidr)
                hosts.update(dict.fromkeys(hs))
            else:
                skipped.append({"subnet": cidr, "reason": "too_large_or_invalid"})
        ports = sorted({int(p) for p in (self.cfg.scan_ports or []) if str(p).isdigit() and 1 <= int(p) <= 65535}) or [502, 80]
        out: dict[str, Any] = {"subnets": scanned, "skipped_subnets": [x["subnet"] for x in skipped], "skipped": skipped,
                               "ports": ports, "scanned_hosts": len(hosts), "hosts": [], "partial": True}
        self._partial["lan"] = out
        found = await net_scan.scan_hosts(hosts, ports, timeout_s=self.cfg.scan_timeout_ms / 1000, concurrency=self.cfg.scan_concurrency)
        configured: dict[str, list[str]] = {}
        for n, d in self.ctrl.hardware.devices.items():
            configured.setdefault(d.host, []).append(n)      # více jmen = IP konflikt v konfiguraci
        arp = {a["ip"]: a["mac"] for a in await net_scan.arp_table()}
        sem = asyncio.Semaphore(8)

        async def identify(ip: str, open_ports: dict) -> None:
            item: dict[str, Any] = {"ip": ip, "mac": arp.get(ip), "ports": open_ports,
                                    "configured_as": ", ".join(configured.get(ip, [])) or None,
                                    "modbus": None, "shelly": None, "http": None}
            async with sem:
                mb_port = next((p for p in MODBUS_PORTS if p in open_ports), None)
                if mb_port is not None:
                    item["modbus"] = await net_scan.modbus_identify(ip, mb_port)
                web_port = next((p for p in WEB_PORTS if p in open_ports), None)
                if web_port is not None:
                    item["shelly"] = await net_scan.shelly_identify(ip, web_port) if web_port not in (443, 8443) else None
                    if item["shelly"] is None:
                        item["http"] = await net_scan.http_info(ip, web_port)
            out["hosts"].append(item)

        await asyncio.gather(*(identify(ip, p) for ip, p in found.items()))
        out["hosts"].sort(key=lambda h: ipaddress.ip_address(h["ip"]))
        out["partial"] = False
        return out

    async def _arp(self, report: dict) -> list[dict]:
        return (await net_scan.arp_table())[:256]
