"""Diagnostika sítě řídicí jednotky — `NetworkDiagnostics` (kontrakt §24).

Spouští se (1) diagnostickým kódem z displeje (`diagnostics.code` v config.yaml —
funguje i před spárováním), (2) servisním heslem z Velína s účelem `diagnostics`
(nebo běžným servisním heslem ze servisního panelu), (3) příkazem `diagnostics`
z Velína. Běží jako jeden task na pozadí (další požadavek během běhu → `already_running`),
po dokončení se report uloží do `Storage.kv` (`last_diagnostics`), odešle do Velína
RPC `kiosk_report_diagnostics` (přes outbox — nespárované zařízení ho pošle po spárování)
a zapíše souhrnnou událost `DIAGNOSTICS` (`kiosk_log_event`, zdroj `diagnostics`).
Zobrazení na displeji: `GET /api/diagnostics` + `snapshot()['diagnostics']` (progres).
"""
from __future__ import annotations

import asyncio
import hmac
import logging
import platform
import socket
import time
import uuid
from typing import TYPE_CHECKING, Any, Awaitable, Callable
from urllib.parse import urlsplit

import httpx

from . import net_scan
from .health_probe import sys_metrics
from .models import Event, EventKind, now_iso
from .pins import normalize_code

if TYPE_CHECKING:  # pragma: no cover
    from .controller import BoxController

log = logging.getLogger("motogo.diagnostics")

KV_LAST = "last_diagnostics"
STEPS = ("system", "interfaces", "lte", "internet", "supabase", "devices", "lan", "arp", "summary")
STEP_TITLES = {"system": "Systém", "interfaces": "Síťová rozhraní", "lte": "LTE modem", "internet": "Internet a DNS",
               "supabase": "Spojení s Velínem", "devices": "Konfigurovaná zařízení", "lan": "Scan LAN",
               "arp": "Tabulka sousedů (ARP)", "summary": "Vyhodnocení"}
INTERNET_TCP = ("1.1.1.1", 443)
MODBUS_PORTS = (502,)                  # identifikace Waveshare (FC01/FC02)
WEB_PORTS = (80, 8080, 443, 8443)      # identifikace Shelly (RPC) / HTTP banner


class NetworkDiagnostics:
    """Jeden běh = report `{id, ts, …, summary}`; `status()` = krátký stav pro UI/Velín."""

    def __init__(self, ctrl: "BoxController") -> None:
        self.ctrl = ctrl
        self.cfg = ctrl.local.diagnostics
        self.running = False
        self.step: str | None = None
        self.done: list[str] = []
        self.started_at: float | None = None
        self._task: asyncio.Task | None = None
        self.current_id: str | None = None
        self.last_error: str | None = None

    # ─── kód / stav ──────────────────────────────────────────────────────
    def matches_local_code(self, code: str) -> bool:
        cfg_code = normalize_code(str(self.cfg.code or "")).lower()
        code = normalize_code(code or "").lower()
        return bool(cfg_code) and hmac.compare_digest(cfg_code.encode("utf-8"), code.encode("utf-8"))

    def last_report(self) -> dict | None:
        rep = self.ctrl.storage.kv_get(KV_LAST)
        return rep if isinstance(rep, dict) else None

    def status(self) -> dict:
        last = self.last_report()
        summary = (last or {}).get("summary") or {}
        return {
            "running": self.running, "id": self.current_id, "step": self.step,
            "step_title": STEP_TITLES.get(self.step or "", self.step), "done": list(self.done), "steps": list(STEPS),
            "elapsed_s": round(time.monotonic() - self.started_at, 1) if self.running and self.started_at else None,
            "error": self.last_error,
            "last": {"id": last.get("id"), "ts": last.get("ts"), "ok": summary.get("ok"),
                     "problems": len(summary.get("problems") or []), "hosts": summary.get("hosts"),
                     "duration_s": last.get("duration_s"), "source": last.get("source")} if last else None,
        }

    # ─── spuštění ────────────────────────────────────────────────────────
    def start(self, source: str, reason: str | None = None) -> dict:
        """Spustí běh na pozadí; `{ok, started, id}` nebo `{ok:false, error:'already_running', id}`."""
        if self.running and self._task is not None and not self._task.done():
            return {"ok": False, "error": "already_running", "id": self.current_id}
        self.current_id = uuid.uuid4().hex[:12]
        self.running, self.step, self.done, self.last_error = True, None, [], None
        self.started_at = time.monotonic()
        self._task = asyncio.create_task(self._run_safe(source, reason or source), name="motogo.diagnostics")
        log.info("Diagnostika sítě %s spuštěna (%s)", self.current_id, source)
        return {"ok": True, "started": True, "id": self.current_id}

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
        finally:
            self.running, self.step = False, None

    async def run(self, source: str, reason: str) -> dict:
        """Provede všechny kroky (každý izolovaně, s limitem), uloží, odešle a zaloguje report."""
        ctrl = self.ctrl
        t0 = time.monotonic()
        report: dict[str, Any] = {
            "id": self.current_id or uuid.uuid4().hex[:12], "ts": now_iso(), "source": source, "reason": reason,
            "version": ctrl.version, "device_id": ctrl._device_id() or None, "branch_name": ctrl.branch_name,
            "paired": bool(getattr(ctrl.api, "paired", False)), "steps": {},
        }
        steps: list[tuple[str, Callable[[dict], Awaitable[Any]]]] = [
            ("system", self._system), ("interfaces", self._interfaces), ("lte", self._lte),
            ("internet", self._internet), ("supabase", self._supabase), ("devices", self._devices),
            ("lan", self._lan), ("arp", self._arp),
        ]
        deadline = t0 + max(20, int(self.cfg.timeout_s))
        for name, fn in steps:
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
                report[name] = None
                report["steps"][name] = {"ok": False, "error": "timeout", "ms": round((time.monotonic() - ts) * 1000)}
            except Exception as exc:  # noqa: BLE001 — jeden krok nesmí shodit celý běh
                log.exception("Diagnostika: krok %s selhal", name)
                report[name] = None
                report["steps"][name] = {"ok": False, "error": str(exc)[:200], "ms": round((time.monotonic() - ts) * 1000)}
            self.done.append(name)
        self.step = "summary"
        report["summary"] = self._summary(report)
        self.done.append("summary")
        report["duration_s"] = round(time.monotonic() - t0, 1)
        report["finished_at"] = now_iso()
        try:
            ctrl.storage.kv_set(KV_LAST, report)
        except Exception:  # noqa: BLE001
            log.exception("Uložení reportu diagnostiky selhalo")
        try:
            await ctrl.api.report_diagnostics(report)
        except Exception:  # noqa: BLE001
            log.exception("Odeslání reportu diagnostiky selhalo")
        summary = report["summary"]
        await ctrl.emit(Event(kind=EventKind.DIAGNOSTICS, success=bool(summary["ok"]),
                              level="info" if summary["ok"] else "warn",
                              message=f"Diagnostika sítě: {'OK' if summary['ok'] else str(len(summary['problems'])) + ' problémů'}"
                                      f" ({summary['hosts']} zařízení v LAN, {report['duration_s']} s)",
                              detail={"source": source, "report_id": report["id"], "problems": summary["problems"][:20],
                                      "hosts": summary["hosts"], "internet": summary.get("internet")}))
        log.info("Diagnostika %s hotova za %s s: %s", report["id"], report["duration_s"], summary["problems"] or "OK")
        return report

    # ─── kroky ───────────────────────────────────────────────────────────
    async def _system(self, report: dict) -> dict:
        rc, out = await net_scan.run_cmd("timedatectl", "show", "-p", "NTPSynchronized", "-p", "TimeUSec", timeout=5)
        ntp = dict(ln.split("=", 1) for ln in out.splitlines() if "=" in ln) if rc == 0 else {}
        u = platform.uname()
        return {"hostname": socket.gethostname(), "kernel": u.release, "machine": u.machine, "python": platform.python_version(),
                "time": now_iso(), "ntp_synced": {"yes": True, "no": False}.get(ntp.get("NTPSynchronized", ""), None),
                "metrics": sys_metrics(), "controller_uptime_s": int(time.monotonic() - self.ctrl._started_at),
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
        return {"dns": dns, "tcp": {"host": INTERNET_TCP[0], "port": INTERNET_TCP[1], "open": ok, "ms": ms, "error": err},
                "http": probes, "ok": any(p["status"] is not None and p["status"] < 500 for p in probes)}

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
        subnets: list[str] = []
        for it in (report.get("interfaces") or {}).get("interfaces") or []:
            for a in it.get("ipv4") or []:
                if a.get("addr") and a.get("prefix"):
                    subnets.append(f"{a['addr']}/{a['prefix']}")
        subnets += [s for s in (self.cfg.scan_subnets or []) if isinstance(s, str)]
        subnets = list(dict.fromkeys(subnets))          # bez duplicit (rozhraní + scan_subnets)
        hosts: dict[str, None] = {}
        scanned: list[str] = []
        for cidr in subnets:
            hs = net_scan.subnet_hosts(cidr, self.cfg.max_hosts)
            if hs:
                scanned.append(cidr)
                hosts.update(dict.fromkeys(hs))
        ports = [int(p) for p in (self.cfg.scan_ports or []) if str(p).isdigit()] or [502, 80]
        found = await net_scan.scan_hosts(hosts, ports, timeout_s=self.cfg.scan_timeout_ms / 1000, concurrency=self.cfg.scan_concurrency)
        configured: dict[str, list[str]] = {}
        for n, d in self.ctrl.hardware.devices.items():
            configured.setdefault(d.host, []).append(n)      # více jmen = IP konflikt v konfiguraci
        arp = {a["ip"]: a["mac"] for a in await net_scan.arp_table()}
        result: list[dict] = []
        for ip, open_ports in found.items():
            item: dict[str, Any] = {"ip": ip, "mac": arp.get(ip), "ports": open_ports,
                                    "configured_as": ", ".join(configured.get(ip, [])) or None,
                                    "modbus": None, "shelly": None, "http": None}
            mb_port = next((p for p in MODBUS_PORTS if p in open_ports), None)
            if mb_port is not None:
                item["modbus"] = await net_scan.modbus_identify(ip, mb_port)
            web_port = next((p for p in WEB_PORTS if p in open_ports), None)
            if web_port is not None:
                item["shelly"] = await net_scan.shelly_identify(ip, web_port) if web_port not in (443, 8443) else None
                if item["shelly"] is None:
                    item["http"] = await net_scan.http_info(ip, web_port)
            result.append(item)
        return {"subnets": scanned, "skipped_subnets": [s for s in subnets if s not in scanned], "ports": ports,
                "scanned_hosts": len(hosts), "hosts": result}

    async def _arp(self, report: dict) -> list[dict]:
        return await net_scan.arp_table()

    # ─── vyhodnocení ─────────────────────────────────────────────────────
    def _summary(self, r: dict) -> dict:
        p: list[str] = []
        sysinfo, ifc, lte, inet, sb, lan = (r.get(k) or {} for k in ("system", "interfaces", "lte", "internet", "supabase", "lan"))
        for name, st in (r.get("steps") or {}).items():
            if not st.get("ok"):
                p.append(f"Krok „{STEP_TITLES.get(name, name)}“ selhal: {st.get('error')}")
        routes = ifc.get("default_routes") or []
        if not routes:
            p.append("Chybí výchozí brána (žádná default route) — internet nemůže fungovat.")
        elif str(routes[0].get("dev") or "").startswith("eth"):
            p.append(f"Výchozí brána vede přes {routes[0].get('dev')} (LAN modulů) místo LTE — zkontroluj profil motogo-lan (never-default).")
        if not ifc.get("dns"):
            p.append("Není nastaven žádný DNS server (/etc/resolv.conf).")
        if lte and lte.get("state") not in (None, "connected", "unavailable"):
            p.append(f"LTE modem není připojen (stav: {lte.get('state')}, NM: {lte.get('nm_state')}).")
        elif lte.get("state") == "unavailable":
            p.append("ModemManager nevidí žádný modem (mmcli) — LTE nedostupné.")
        if inet and not inet.get("ok"):
            p.append("Internet nedostupný (HTTP sondy selhaly)." + ("" if any(d.get("addresses") for d in inet.get("dns") or []) else " DNS nepřekládá."))
        if sb.get("paired") and sb.get("ok") is False:
            p.append("Velín (Supabase) neodpovídá na heartbeat — zkontroluj internet / párování.")
        if not sb.get("paired"):
            p.append("Zařízení není spárované s Velínem (report se odešle po spárování).")
        for d in r.get("devices") or []:
            if not d.get("reachable"):
                p.append(f"Zařízení {d['name']} ({d['type']}) na {d['host']}:{d['port']} neodpovídá ({d.get('error') or 'timeout'}).")
            elif d["type"] in ("wav645", "wav617"):
                g = (d.get("identified") or {}).get("guess")
                if g is None:
                    p.append(f"{d['name']} na {d['host']} má otevřený port {d['port']}, ale nemluví Modbus (jiné zařízení?).")
                elif g != d["type"] and g != "modbus":
                    p.append(f"{d['name']} je nastaveno jako {d['type']}, ale na {d['host']} odpovídá {g}.")
            elif d["type"] == "shelly_rgbww" and not d.get("identified"):
                p.append(f"{d['name']} na {d['host']} neodpovídá jako Shelly (RPC Shelly.GetDeviceInfo).")
        hosts_by_ip = {h["host"]: [] for h in r.get("devices") or []}
        for d in r.get("devices") or []:
            hosts_by_ip[d["host"]].append(d["name"])
        for ip, names in hosts_by_ip.items():
            if len(names) > 1:
                p.append(f"Více zařízení sdílí IP {ip}: {', '.join(names)}.")
        unknown = [h["ip"] for h in lan.get("hosts") or [] if not h.get("configured_as") and (h.get("modbus") or h.get("shelly"))]
        if unknown:
            p.append("V LAN jsou Modbus/Shelly zařízení mimo konfiguraci: " + ", ".join(unknown[:8]) + ".")
        if lan.get("skipped_subnets"):
            p.append("Přeskočené podsítě (příliš velké): " + ", ".join(lan["skipped_subnets"]) + ".")
        m = sysinfo.get("metrics") or {}
        if (m.get("cpu_temp") or 0) > 75:
            p.append(f"Vysoká teplota CPU {m['cpu_temp']} °C.")
        if m.get("throttled") not in (None, "0x0"):
            p.append(f"Raspberry hlásí throttling/podpětí ({m['throttled']}).")
        if m.get("disk_free_pct") is not None and m["disk_free_pct"] < 10:
            p.append(f"Málo místa na disku ({m['disk_free_pct']} % volných).")
        if sysinfo.get("ntp_synced") is False:
            p.append("Čas není synchronizovaný (NTP) — platnost kódů se může vyhodnotit špatně.")
        for cp in sysinfo.get("config_problems") or []:
            p.append(f"Konfigurace: {cp}")
        return {"ok": not p, "problems": p, "hosts": len(lan.get("hosts") or []), "internet": bool(inet.get("ok")),
                "lte": lte.get("state"), "devices_ok": sum(1 for d in r.get("devices") or [] if d.get("reachable")),
                "devices_total": len(r.get("devices") or [])}
