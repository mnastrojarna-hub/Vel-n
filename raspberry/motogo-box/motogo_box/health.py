"""Health monitor (kontrakt §17) — `python -m motogo_box health` (motogo-health.service).

Smyčka každých `cfg.check_interval_s`:
1. sonda internetu: 3 nezávislé cíle souběžně (HTTP `cfg.probe_url`, HTTP google `generate_204`,
   TCP 1.1.1.1:443) — „down“ jen když selžou VŠECHNY (výpadek Supabase/DNS ≠ výpadek LTE),
2. LTE info z ModemManageru (`mmcli -J`) + stav NM profilu (`nmcli`),
3. systémové metriky (teplota, throttling, disk, RAM, load, uptime),
4. politika obnovy LTE (`LtePolicy`): reconnect → USB reset modemu → reboot; při `locked` (SIM PIN)
   nebo `failed` kvůli SIM politika STOJÍ a chyba jde do `lte.error` + logu (reboot PIN nezadá),
5. `POST <controller>/api/health` (3 s, chyby se ignorují) + `sd_notify WATCHDOG=1`.

Počítadla politiky přežívají restart služby v `<paths.data_dir>/health.json`. Procesy jdou přes
injektovatelné `run_cmd`, TCP sonda přes `tcp_probe` (testy bez sudo/sítě); sudo argv odpovídají
přesně aliasům v systemd/motogo-sudoers (motogo-usbreset se volá BEZ argumentů).
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from typing import Awaitable, Callable

import httpx

from .config import HealthCfg
from .health_probe import (  # noqa: F401 — veřejné API dle kontraktu §17
    disk_free_pct, lte_error, mem_free_pct, parse_meminfo, parse_mmcli_modem, parse_mmcli_signal,
    parse_nmcli_connection, read_cpu_temp, read_throttled, read_uptime_s, sys_metrics, tcp_probe,
)
from .models import now_iso

try:
    from .sdnotify import notify as sd_notify
except Exception:  # noqa: BLE001 — modul píše jiný agent; lokální záloha níže
    import socket

    def sd_notify(state: str) -> None:  # type: ignore[misc]
        """Záložní sd_notify: datagram na `NOTIFY_SOCKET`, bez socketu no-op."""
        addr = os.environ.get("NOTIFY_SOCKET")
        if not addr:
            return
        if addr.startswith("@"):
            addr = "\0" + addr[1:]
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
                sock.sendto(state.encode("utf-8"), addr)
        except OSError:
            pass

log = logging.getLogger("motogo.health")

DEFAULT_STATE_PATH = "/var/lib/motogo/health.json"
PROBE_TIMEOUT_S = 8.0
PROBE_URL_2 = "https://www.google.com/generate_204"   # nezávislý HTTP cíl mimo Supabase
PROBE_TCP = ("1.1.1.1", 443)                          # TCP connect bez DNS (výpadek DNS operátora ≠ výpadek LTE)
POST_TIMEOUT_S = 3.0
MMCLI_TIMEOUT_S = 15.0
SIGNAL_SETUP_RATE_S = 30
KILL_WAIT_S = 5.0            # po timeoutu: jak dlouho čekat na konec (ne)zabitého potomka

RunCmd = Callable[..., Awaitable[tuple[int, str]]]
TcpProbe = Callable[..., Awaitable[bool]]


async def run_cmd(*args: str, timeout: float = 20) -> tuple[int, str]:
    """Spustí proces a vrátí `(returncode, stdout+stderr)`; nikdy nevyhazuje (chyba → rc 127/124)."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
    except (OSError, ValueError) as exc:
        return 127, f"{args[0] if args else '?'}: {exc}"
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        try:
            proc.kill()
        except (ProcessLookupError, PermissionError):
            pass   # už skončil / potomek je sudo (root) — kill nesmí shodit cyklus health
        try:
            await asyncio.wait_for(proc.wait(), timeout=KILL_WAIT_S)
        except Exception:  # noqa: BLE001 — nezabitelný root potomek běží dál; nečekáme na něj
            pass
        return 124, f"timeout po {timeout:.0f} s: {' '.join(args)}"
    return proc.returncode if proc.returncode is not None else 1, out.decode("utf-8", "replace")


class LtePolicy:
    """Čistá rozhodovací logika obnovy LTE (bez I/O) — testovatelná s falešnými hodinami.

    Žebříček: `reconnect_after` po sobě jdoucích výpadků → `reconnect`; `usb_reset_after`
    reconnectů bez obnovy → `usb_reset`; `reboot_after` USB resetů bez obnovy a
    uptime ≥ `min_uptime_before_reboot_s` → `reboot`. Návrat internetu vše vynuluje.
    """

    def __init__(self, cfg: HealthCfg, clock: Callable[[], float] = time.time) -> None:
        self.cfg = cfg
        self.clock = clock
        self.internet_failures = 0      # po sobě jdoucí neúspěšné sondy
        self.reconnect_failures = 0     # reconnecty bez obnovy (od posledního USB resetu)
        self.usb_resets_pending = 0     # USB resety bez obnovy (od posledního rebootu/online)
        self.reconnects = 0             # celkem (přežívá restart služby)
        self.usb_resets = 0
        self.reboots = 0
        self.last_online: float | None = None
        self.last_action: str | None = None
        self.last_action_at: float | None = None

    def step(self, internet_ok: bool, uptime_s: float) -> list[str]:
        """Jeden krok politiky; vrací seznam akcí k provedení (`reconnect`/`usb_reset`/`reboot`)."""
        if internet_ok:
            self.internet_failures = 0
            self.reconnect_failures = 0
            self.usb_resets_pending = 0
            self.last_online = self.clock()
            return []
        self.internet_failures += 1
        cfg = self.cfg
        if (self.usb_resets_pending >= max(1, cfg.reboot_after)
                and uptime_s >= cfg.min_uptime_before_reboot_s):
            self.usb_resets_pending = 0
            self.reconnect_failures = 0
            self.internet_failures = 0
            self.reboots += 1
            return self._mark("reboot")
        if self.internet_failures < max(1, cfg.reconnect_after):
            return []
        self.internet_failures = 0
        if self.reconnect_failures >= max(1, cfg.usb_reset_after):
            self.reconnect_failures = 0
            self.usb_resets_pending += 1
            self.usb_resets += 1
            return self._mark("usb_reset")
        self.reconnect_failures += 1
        self.reconnects += 1
        return self._mark("reconnect")

    def _mark(self, action: str) -> list[str]:
        self.last_action, self.last_action_at = action, self.clock()
        return [action]

    def to_dict(self) -> dict:
        return {
            "internet_failures": self.internet_failures, "reconnect_failures": self.reconnect_failures,
            "usb_resets_pending": self.usb_resets_pending, "reconnects": self.reconnects,
            "usb_resets": self.usb_resets, "reboots": self.reboots, "last_online": self.last_online,
            "last_action": self.last_action, "last_action_at": self.last_action_at,
        }

    def load(self, d: dict | None) -> None:
        """Obnoví počítadla z uloženého stavu (neznámé/vadné hodnoty ignoruje)."""
        if not isinstance(d, dict):
            return
        for key in ("internet_failures", "reconnect_failures", "usb_resets_pending",
                    "reconnects", "usb_resets", "reboots"):
            try:
                setattr(self, key, max(0, int(d.get(key, 0) or 0)))
            except (TypeError, ValueError):
                pass
        for key in ("last_online", "last_action_at"):
            v = d.get(key)
            setattr(self, key, float(v) if isinstance(v, (int, float)) else None)
        la = d.get("last_action")
        self.last_action = la if isinstance(la, str) else None


class HealthMonitor:
    """Provozní smyčka health služby (kontrakt §17)."""

    def __init__(self, cfg: HealthCfg, controller_url: str = "http://127.0.0.1:8080", *,
                 run_cmd: RunCmd = run_cmd, clock: Callable[[], float] = time.time,
                 state_path: str = DEFAULT_STATE_PATH, http: httpx.AsyncClient | None = None,
                 uptime: Callable[[], float | None] = read_uptime_s,
                 tcp_probe: TcpProbe = tcp_probe) -> None:
        self.cfg = cfg
        self.controller_url = controller_url.rstrip("/")
        self.run_cmd = run_cmd
        self.clock = clock
        self.state_path = state_path
        self._http = http
        self._uptime = uptime
        self._tcp_probe = tcp_probe
        self.policy = LtePolicy(cfg, clock)
        self.policy.load(self._load_state())
        self.last_payload: dict | None = None
        self.last_probe: dict[str, bool] = {}   # výsledek posledních sond per cíl
        self._signal_setup_done = False
        self._lte_error: str | None = None
        self._stop = asyncio.Event()

    # ─── perzistence ─────────────────────────────────────────────────────────
    def _load_state(self) -> dict | None:
        try:
            with open(self.state_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except FileNotFoundError:
            return None
        except (OSError, ValueError) as exc:
            log.warning("Stav health (%s) nelze načíst: %s", self.state_path, exc)
            return None

    def _save_state(self) -> None:
        tmp = self.state_path + ".tmp"
        try:
            os.makedirs(os.path.dirname(self.state_path) or ".", exist_ok=True)
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self.policy.to_dict(), f)
            os.replace(tmp, self.state_path)
        except OSError as exc:
            log.warning("Stav health (%s) nelze uložit: %s", self.state_path, exc)

    # ─── sondy ───────────────────────────────────────────────────────────────
    async def probe_internet(self) -> bool:
        """≥ 2 nezávislé cíle souběžně; internet je „down“ jen když selžou všechny."""
        targets = {"probe_url": self._http_probe(self.cfg.probe_url),
                   "google_204": self._http_probe(PROBE_URL_2),
                   "tcp_1.1.1.1": self._tcp_probe(*PROBE_TCP, timeout=PROBE_TIMEOUT_S)}
        results = await asyncio.gather(*targets.values())
        self.last_probe = dict(zip(targets, (bool(r) for r in results)))
        failed = [k for k, v in self.last_probe.items() if not v]
        if failed:
            log.info("Sonda internetu: nedostupné %s%s", ", ".join(failed),
                     "" if len(failed) == len(targets) else " — internet OK (ostatní cíle odpověděly)")
        return len(failed) < len(targets)

    async def _http_probe(self, url: str) -> bool:
        """HTTP GET; jakákoli HTTP odpověď (i 4xx/5xx) = spojení do internetu funguje."""
        try:
            await self._client().get(url, timeout=PROBE_TIMEOUT_S)
            return True
        except Exception as exc:  # noqa: BLE001 — httpx i DNS chyby
            log.debug("Sonda %s selhala: %s", url, exc)
            return False

    async def lte_info(self) -> dict:
        """Sloučí `mmcli -m any -J`, `--signal-get -J`, stav NM profilu a `error` (viz `lte_error`)."""
        rc, out = await self.run_cmd("mmcli", "-m", "any", "-J", timeout=MMCLI_TIMEOUT_S)
        modem = parse_mmcli_modem(out) if rc == 0 else {
            "state": "no_modem", "signal_quality": None, "operator": None,
            "access_tech": None, "registration": None, "failed_reason": None}
        signal = {"rssi": None, "rsrp": None, "rsrq": None, "snr": None, "refresh_rate": 0}
        if rc == 0:
            rc2, out2 = await self.run_cmd("mmcli", "-m", "any", "--signal-get", "-J", timeout=MMCLI_TIMEOUT_S)
            if rc2 == 0:
                signal = parse_mmcli_signal(out2)
            if signal["refresh_rate"] <= 0 and not self._signal_setup_done:
                # Bez --signal-setup ModemManager rozšířené metriky (RSRP…) neaktualizuje.
                # Modem.Signal.Setup vyžaduje polkit Device.Control → přes sudo (viz motogo-sudoers);
                # při neúspěchu se zkusí znovu v dalším cyklu.
                rc4, out4 = await self.run_cmd("sudo", "-n", "mmcli", "-m", "any",
                                               f"--signal-setup={SIGNAL_SETUP_RATE_S}", timeout=MMCLI_TIMEOUT_S)
                self._signal_setup_done = rc4 == 0
                if rc4 != 0:
                    log.info("mmcli --signal-setup selhal (rc=%s): %s", rc4, out4.strip()[:200])
        else:
            self._signal_setup_done = False
        rc3, out3 = await self.run_cmd("nmcli", "-t", "-f", "GENERAL.STATE,GENERAL.DEVICES",
                                       "con", "show", self.cfg.nm_connection, timeout=10)
        nm = parse_nmcli_connection(rc3, out3)
        p = self.policy
        return {**modem, **{k: v for k, v in signal.items() if k != "refresh_rate"}, **nm,
                "reconnects": p.reconnects, "usb_resets": p.usb_resets, "reboots": p.reboots,
                "internet_failures": p.internet_failures, "last_action": p.last_action,
                "error": lte_error(modem)}

    # ─── akce politiky ───────────────────────────────────────────────────────
    async def perform(self, action: str, payload: dict) -> None:
        """Provede akci z `LtePolicy.step`; `reboot` nejdřív ohlásí controlleru."""
        nm = self.cfg.nm_connection
        sd_notify("WATCHDOG=1")      # dlouhé akce (nmcli up až 30 s, USB reset až 60 s) — watchdog nesmí zabít obnovu
        if action == "reconnect":
            log.warning("LTE: internet nedostupný → reconnect profilu %s (celkem %d)", nm, self.policy.reconnects)
            await self.run_cmd("sudo", "-n", "nmcli", "con", "down", nm, timeout=30)
            rc, out = await self.run_cmd("sudo", "-n", "nmcli", "-w", "30", "con", "up", nm, timeout=45)
            if rc != 0:
                log.error("nmcli con up %s selhal (rc=%s): %s", nm, rc, out.strip()[:300])
        elif action == "usb_reset":
            log.warning("LTE: reconnecty nepomohly → USB reset modemu %s (celkem %d)",
                        self.cfg.modem_vid_pid, self.policy.usb_resets)
            # sudoers povoluje skript JEN bez argumentů; VID:PID čte skript z root-owned
            # /etc/motogo/modem_vidpid (install.sh, MOTOGO_MODEM_VIDPID) — má odpovídat cfg.modem_vid_pid.
            rc, out = await self.run_cmd("sudo", "-n", self.cfg.usb_reset_script, timeout=60)
            if rc != 0:
                log.error("USB reset selhal (rc=%s): %s", rc, out.strip()[:300])
        elif action == "reboot":
            log.critical("LTE: USB resety nepomohly → reboot systému")
            self._save_state()
            await self.post_health(payload)
            rc, out = await self.run_cmd("sudo", "-n", "systemctl", "reboot", timeout=30)
            if rc != 0:
                log.error("systemctl reboot selhal (rc=%s): %s", rc, out.strip()[:300])

    # ─── controller ──────────────────────────────────────────────────────────
    async def post_health(self, payload: dict) -> bool:
        try:
            r = await self._client().post(f"{self.controller_url}/api/health", json=payload,
                                          timeout=POST_TIMEOUT_S)
            return r.status_code < 300
        except Exception as exc:  # noqa: BLE001 — controller může být dole; není chyba health
            log.debug("POST /api/health selhal: %s", exc)
            return False

    def _client(self) -> httpx.AsyncClient:
        if self._http is None:
            self._http = httpx.AsyncClient()
        return self._http

    # ─── smyčka ──────────────────────────────────────────────────────────────
    async def cycle(self) -> dict:
        """Jeden průchod: sondy → politika → akce → POST → watchdog. Vrací payload."""
        internet = await self.probe_internet()
        lte = await self.lte_info()
        sysm = sys_metrics()
        uptime = self._uptime()
        error = lte.get("error")
        if error:
            # SIM PIN / chybějící SIM: reconnect, USB reset ani reboot nepomůže → politika stojí, jen hlásit.
            actions: list[str] = []
            if error != self._lte_error:
                log.error("LTE: modem hlásí %s (stav %s) — obnova pozastavena; PIN zadej do NM profilu "
                          "(install.sh, MOTOGO_SIM_PIN) nebo zkontroluj SIM", error, lte.get("state"))
        else:
            actions = self.policy.step(internet, uptime if uptime is not None else 0.0)
        self._lte_error = error
        self._save_state()
        payload = {"internet": internet, "lte": lte, "sys": sysm, "ts": now_iso(), "actions": actions}
        for action in actions:
            await self.perform(action, payload)
        if "reboot" not in actions:
            await self.post_health(payload)
        sd_notify("WATCHDOG=1")
        self.last_payload = payload
        return payload

    async def run(self) -> None:
        """Nekonečná smyčka každých `cfg.check_interval_s`; chyba cyklu nesmí službu shodit."""
        sd_notify("READY=1")
        interval = max(5, int(self.cfg.check_interval_s))
        log.info("Health monitor běží (interval %d s, sondy %s + %s + tcp %s:%d, profil %s)",
                 interval, self.cfg.probe_url, PROBE_URL_2, *PROBE_TCP, self.cfg.nm_connection)
        try:
            while not self._stop.is_set():
                started = time.monotonic()
                try:
                    payload = await self.cycle()
                    lte = payload["lte"]
                    err = f" error={lte['error']}" if lte.get("error") else ""
                    sd_notify(f"STATUS=internet={'ok' if payload['internet'] else 'DOWN'} "
                              f"lte={lte.get('state')} rssi={lte.get('rssi')}{err}")
                except Exception:  # noqa: BLE001
                    log.exception("Cyklus health selhal")
                    sd_notify("WATCHDOG=1")
                wait = max(1.0, interval - (time.monotonic() - started))
                try:
                    await asyncio.wait_for(self._stop.wait(), timeout=wait)
                except asyncio.TimeoutError:
                    pass
        finally:
            if self._http is not None:
                await self._http.aclose()
                self._http = None

    def stop(self) -> None:
        self._stop.set()
