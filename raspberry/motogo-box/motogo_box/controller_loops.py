"""Periodické smyčky `BoxController` (kontrakt §12): poll kontaktů, tick zón,
heartbeat, sync, příkazy, status, outbox, power a systemd watchdog.

Každá smyčka je samostatná korutina nad instancí controlleru; chyby uvnitř
jedné iterace se logují a smyčka běží dál (nesmí nikdy spadnout).

Poll kontaktů čte každý Modbus modul vlastním taskem (`InputPoller`), aby retry
řetězec jednoho nedostupného modulu (~2,9 s) nezdržel zóny ostatních modulů
(SPEC §6: 100 ms; §12: výpadek jednoho modulu nesmí zhoršit bezpečnost ostatních).

Vzdálené příkazy: ID zpracovaných příkazů se ukládají do `Storage.kv`, takže se po
restartu procesu (restart/reboot/update_software, pád, watchdog) NEPROVEDOU znovu,
i když jejich potvrzení (`kiosk_complete_command`) zůstalo v outboxu.
"""
from __future__ import annotations

import asyncio
import logging
import time
from collections import deque
from dataclasses import dataclass
from typing import TYPE_CHECKING

import httpx

from . import sdnotify
from .modbus import ModbusError

if TYPE_CHECKING:  # pragma: no cover
    from .controller import BoxController
    from .io_devices import RelayModule
    from .zone import ZoneController

log = logging.getLogger("motogo.loops")

TICK_S = 0.25
POLL_HEALTHY_S = 5.0
SIGNAL_REFRESH_S = 5.0         # obnova nepotvrzené signalizace Shelly (výpadek/restart Shelly)
MAX_HANDLED_IDS = 500
KV_HANDLED_COMMANDS = "handled_commands"
BUS_RECOVERY_S = 1.0          # perioda `read_all_inputs` pro obnovu nezdravých modulů (sondy, reinit)
OUTBOX_SCAN_LIMIT = 500


@dataclass
class Debounce:
    """Stav sw debounce jednoho kontaktu (hodnota musí být stabilní `software_debounce_ms`)."""

    raw: bool | None = None
    since: float = 0.0
    passed: bool | None = None
    passed_any: bool = False


# ─── poll kontaktů ───────────────────────────────────────────────────────────
class InputPoller:
    """Per-modul čtení vstupů vlastním taskem; momentka se skládá z posledních hodnot.

    Zdravý modul (online, bez čekající obnovy) čte jeho task přímo (FC02; WAV645 bez
    vstupů sondou FC01), takže retry řetězec nedostupného modulu blokuje JEN jeho zóny.
    Nezdravý modul dostává None (= io_offline) a jeho obnovu (sonda offline modulu,
    Normal mode + all_off) řeší `IoBus.read_all_inputs()` volané na pozadí nejvýš
    každou `BUS_RECOVERY_S`. Modul, jehož čtení právě běží déle než `stale_s`
    (probíhá retry), je `stale` — jeho zónám se nic nedoručí (žádná nová informace),
    stejně jako dosud při zablokovaném pollu.
    """

    def __init__(self, ctrl: "BoxController") -> None:
        self.ctrl = ctrl
        self.values: dict[str, list[bool] | None] = {}
        self.read_at: dict[str, float] = {}
        self._tasks: list[asyncio.Task] = []
        self._bus_task: asyncio.Task | None = None
        self._bus_at = 0.0

    def start(self) -> None:
        for name in list(self.ctrl.io.modules):
            self._tasks.append(asyncio.create_task(self._reader(name), name=f"motogo.poll.{name}"))

    async def stop(self) -> None:
        tasks = list(self._tasks)
        if self._bus_task is not None:
            tasks.append(self._bus_task)
        await cancel_all(tasks)
        self._tasks.clear()
        self._bus_task = None

    def poll_s(self) -> float:
        return max(0.02, self.ctrl.hardware.polling.door_input_poll_ms / 1000.0)

    def stale_s(self) -> float:
        """Nejdelší doba, po kterou je hodnota čerstvá: jeden Modbus timeout + dvě periody + rezerva."""
        p = self.ctrl.hardware.polling
        return (max(1, p.modbus_timeout_ms) + 2 * max(20, p.door_input_poll_ms)) / 1000.0 + 0.1

    def snapshot(self, now: float) -> tuple[dict[str, list[bool] | None], set[str]]:
        """(momentka ve tvaru `read_all_inputs`, jména modulů bez čerstvé hodnoty)."""
        stale_s = self.stale_s()
        snap: dict[str, list[bool] | None] = {}
        stale: set[str] = set()
        for name in self.ctrl.io.modules:
            at = self.read_at.get(name)
            if at is None or now - at > stale_s:
                stale.add(name)
            else:
                snap[name] = self.values.get(name)
        return snap, stale

    def _healthy(self, name: str) -> bool:
        module = self.ctrl.io.modules.get(name)
        return (module is not None and self.ctrl.io.is_online(name)
                and not getattr(module, "needs_reinit", False))

    async def _reader(self, name: str) -> None:
        while True:
            module = self.ctrl.io.modules.get(name)
            if module is None:
                return
            if self._healthy(name):
                values = await self._read(module)
                if values is None and self._healthy(name):
                    # Přechodná chyba (modul je dál online) — žádná nová informace; hodnota jen
                    # zestárne (stale). io_offline vyhlásí až skutečný přechod modulu do offline.
                    await asyncio.sleep(self.poll_s())
                    continue
            else:
                values = None
                self._ensure_bus_recovery()
            self.values[name] = values
            self.read_at[name] = time.monotonic()
            await asyncio.sleep(self.poll_s())

    @staticmethod
    async def _read(module: "RelayModule") -> list[bool] | None:
        """Vstupy modulu; modul bez vstupů se sonduje čtením relé → []. Chyba → None."""
        try:
            if module.inputs:
                return await module.read_inputs()
            await module.read_coils()
            return []
        except ModbusError as exc:
            log.debug("%s: čtení vstupů selhalo: %s", module.name, exc)
        except Exception:  # noqa: BLE001
            log.exception("%s: čtení vstupů selhalo", module.name)
        return None

    def _ensure_bus_recovery(self) -> None:
        """Na pozadí nechá `IoBus` obnovit nezdravé moduly (sonda / reinit), nejvýš 1× za `BUS_RECOVERY_S`."""
        now = time.monotonic()
        if self._bus_task is not None and not self._bus_task.done():
            return
        if now - self._bus_at < BUS_RECOVERY_S:
            return
        self._bus_at = now
        self._bus_task = asyncio.create_task(self._bus_recovery(), name="motogo.poll.recovery")

    async def _bus_recovery(self) -> None:
        try:
            await self.ctrl.io.read_all_inputs()
        except Exception:  # noqa: BLE001
            log.exception("poll: obnova sběrnice selhala")


async def poll_loop(ctrl: "BoxController") -> None:
    """Každých `door_input_poll_ms` složí momentku vstupů a po sw debounce předá hodnoty zónám."""
    deb: dict[int, Debounce] = {}
    poller = InputPoller(ctrl)
    poller.start()
    try:
        while True:
            try:
                now = time.monotonic()
                snap, stale = poller.snapshot(now)
                if len(stale) < len(ctrl.io.modules) or not ctrl.io.modules:
                    ctrl.last_poll = now      # aspoň jeden modul doručuje → poll žije (watchdog)
                debounce_s = ctrl.hardware.polling.software_debounce_ms / 1000.0
                for zc in list(ctrl.zones.values()):
                    ref = zc.zone.hw.contact
                    if ref is not None and ref.dev in stale:
                        continue              # modul právě v retry — bez nové informace
                    d = deb.setdefault(zc.number, Debounce())
                    raw = ctrl.door_value(snap, zc)
                    if raw is None:
                        d.raw, d.since, d.passed, d.passed_any = None, now, None, True
                        await _safe_input(zc, None)
                        continue
                    if raw != d.raw:
                        d.raw, d.since = raw, now
                    if now - d.since >= debounce_s or not d.passed_any:
                        d.passed, d.passed_any = raw, True
                        await _safe_input(zc, raw)
            except Exception:  # noqa: BLE001
                log.exception("poll_loop: iterace selhala")
            await asyncio.sleep(poller.poll_s())
    finally:
        await poller.stop()


async def _safe_input(zc: "ZoneController", value: bool | None) -> None:
    try:
        await zc.on_input(value)
    except Exception:  # noqa: BLE001
        log.exception("Zóna %s: on_input(%r) selhal", zc.number, value)


async def tick_loop(ctrl: "BoxController") -> None:
    """Každých 250 ms zavolá `tick()` všech zón (timeouty, overtime, doběh světla/hudby);
    každých `SIGNAL_REFRESH_S` na pozadí obnoví signalizaci, kterou Shelly nepotvrdilo."""
    last_refresh = 0.0
    refresh_task: asyncio.Task | None = None
    while True:
        for zc in list(ctrl.zones.values()):
            try:
                await zc.tick()
            except Exception:  # noqa: BLE001
                log.exception("Zóna %s: tick selhal", zc.number)
        now = time.monotonic()
        if now - last_refresh >= SIGNAL_REFRESH_S and (refresh_task is None or refresh_task.done()):
            last_refresh = now
            refresh = getattr(ctrl.signals, "refresh_unconfirmed", None)
            if refresh is not None:
                refresh_task = asyncio.create_task(refresh(), name="motogo.signal_refresh")
        await asyncio.sleep(TICK_S)


# ─── síťové smyčky ───────────────────────────────────────────────────────────
async def heartbeat_loop(ctrl: "BoxController") -> None:
    """`kiosk_heartbeat` → název pobočky + konfigurace power pollingu."""
    while True:
        try:
            if _paired(ctrl):
                res = await ctrl.api.heartbeat()
                if isinstance(res, dict) and res.get("ok", True):
                    ctrl.apply_heartbeat(res)
        except Exception:  # noqa: BLE001
            log.exception("heartbeat_loop: selhal")
        await asyncio.sleep(max(5, ctrl.local.intervals.heartbeat_s))


async def sync_loop(ctrl: "BoxController") -> None:
    """Pravidelná synchronizace konfigurace a kódů z Velína."""
    while True:
        await asyncio.sleep(max(10, ctrl.local.intervals.sync_s))
        try:
            if _paired(ctrl):
                await ctrl.resync()
        except Exception:  # noqa: BLE001
            log.exception("sync_loop: resync selhal")


def _paired(ctrl: "BoxController") -> bool:
    """Nespárované zařízení nevolá RPC (PostgREST by odmítl prázdné uuid) — párování spustí resync samo."""
    paired = getattr(ctrl.api, "paired", None)
    return bool(paired) if paired is not None else bool(getattr(ctrl.api, "device_id", ""))


class HandledCommands:
    """ID zpracovaných příkazů — v paměti (`ctrl.handled_commands`) i v `Storage.kv`.

    Ukládá se PŘED provedením příkazu, takže restart/pád uprostřed provádění
    (restart, reboot, open_door…) příkaz po startu neprovede podruhé. Ořez drží
    NEJNOVĚJŠÍ `MAX_HANDLED_IDS` položek (deque), ne náhodný výběr.
    """

    def __init__(self, ctrl: "BoxController") -> None:
        self.ctrl = ctrl
        ids: list[str] = []
        try:
            raw = ctrl.storage.kv_get(KV_HANDLED_COMMANDS)
        except Exception:  # noqa: BLE001
            log.exception("handled_commands: načtení z kv selhalo")
            raw = None
        if isinstance(raw, list):
            ids = [str(x) for x in raw if x]
        ids.extend(cid for cid in ctrl.handled_commands if cid not in ids)
        self._ids: deque[str] = deque(ids[-MAX_HANDLED_IDS:], maxlen=MAX_HANDLED_IDS)
        ctrl.handled_commands = set(self._ids)

    def __contains__(self, cid: str) -> bool:
        return cid in self.ctrl.handled_commands

    def add(self, cid: str) -> None:
        if cid in self:
            return
        self._ids.append(cid)
        self.ctrl.handled_commands = set(self._ids)
        try:
            self.ctrl.storage.kv_set(KV_HANDLED_COMMANDS, list(self._ids))
        except Exception:  # noqa: BLE001
            log.exception("handled_commands: uložení do kv selhalo")


def _completion_queued(ctrl: "BoxController", cid: str) -> bool:
    """True, když potvrzení příkazu `cid` čeká v outboxu (v pochybnostech True — nic nehlásit)."""
    try:
        pending = ctrl.storage.outbox_pending(OUTBOX_SCAN_LIMIT)
    except Exception:  # noqa: BLE001
        log.exception("outbox: čtení selhalo")
        return True
    return any(kind == "complete_command" and str(payload.get("p_command_id") or "") == cid
               for _oid, kind, payload in pending)


async def _settle_unfinished(ctrl: "BoxController", cmd: dict, reported: set[str]) -> None:
    """Příkaz už zpracovaný, ale ve Velíně stále `pending`: potvrzení čeká v outboxu → nic;
    jinak (pád/restart před potvrzením) ho JEDNOU uzavřít jako nepotvrzený — nikdy neopakovat."""
    cid, command = str(cmd.get("id") or ""), str(cmd.get("command") or "")
    if cid in reported or _completion_queued(ctrl, cid):
        return
    reported.add(cid)
    log.warning("Příkaz %s (%s) už byl zpracován, ve Velíně zůstal pending — uzavírám bez opakování", cid, command)
    await ctrl.api.complete_command(cid, False, {
        "error": "not_confirmed", "command": command,
        "message": "Příkaz byl zpracován dříve, ale potvrzení výsledku se nedochovalo "
                   "(restart/výpadek řídicí jednotky) — neopakuje se.",
    })


async def _flush_outbox(ctrl: "BoxController") -> int:
    """`api.flush_outbox` pod zámkem (command_loop i outbox_loop) — položka se nikdy neodešle 2×."""
    lock = getattr(ctrl, "outbox_lock", None)
    if lock is None:
        lock = ctrl.outbox_lock = asyncio.Lock()
    async with lock:
        return int(await ctrl.api.flush_outbox() or 0)


async def command_loop(ctrl: "BoxController") -> None:
    """Stahuje čekající příkazy (`kiosk_fetch_commands`); realtime wake zkracuje čekání.

    Před každým stažením nejdřív odešle outbox (potvrzení z minulého běhu — restart,
    reboot, update_software), aby se už provedené příkazy nestáhly jako `pending`.
    """
    handled = HandledCommands(ctrl)
    reported: set[str] = set()
    while True:
        try:
            await _flush_outbox(ctrl)
            for cmd in (await ctrl.api.fetch_commands() if _paired(ctrl) else []) or []:
                if not isinstance(cmd, dict):
                    continue
                cid = str(cmd.get("id") or "")
                if not cid:
                    continue
                if cid in handled:
                    await _settle_unfinished(ctrl, cmd, reported)
                    continue
                handled.add(cid)          # persistovat PŘED provedením (restart/pád = neopakovat)
                await ctrl.handle_command(cmd)
        except Exception:  # noqa: BLE001
            log.exception("command_loop: selhal")
        try:
            await asyncio.wait_for(ctrl.wake.wait(), timeout=max(2, ctrl.local.intervals.command_poll_s))
        except asyncio.TimeoutError:
            pass
        ctrl.wake.clear()


async def status_loop(ctrl: "BoxController") -> None:
    """`kiosk_report_status(snapshot())` každých `status_report_s`."""
    while True:
        await asyncio.sleep(max(5, ctrl.local.intervals.status_report_s))
        try:
            if _paired(ctrl):
                await ctrl.api.report_status(ctrl.snapshot())
        except Exception:  # noqa: BLE001
            log.exception("status_loop: report_status selhal")


async def outbox_loop(ctrl: "BoxController") -> None:
    """Odesílá čekající záznamy z outboxu (logy/příkazy vzniklé offline)."""
    while True:
        await asyncio.sleep(max(10, ctrl.local.intervals.outbox_flush_s))
        try:
            sent = await _flush_outbox(ctrl)
            if sent:
                log.info("outbox: odesláno %s záznamů", sent)
        except Exception:  # noqa: BLE001
            log.exception("outbox_loop: flush selhal")


async def power_loop(ctrl: "BoxController") -> None:
    """Stahuje JSON stav elektrárny z `power_status_url` a hlásí ho do Velína."""
    while ctrl.power_status_url:
        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                r = await client.get(ctrl.power_status_url)
            if r.status_code < 400:
                payload = r.json()
                if isinstance(payload, dict):
                    await ctrl.api.report_power(payload)
            else:
                log.warning("power_loop: HTTP %s z %s", r.status_code, ctrl.power_status_url)
        except (httpx.HTTPError, ValueError) as exc:
            log.warning("power_loop: %s", exc)
        except Exception:  # noqa: BLE001
            log.exception("power_loop: selhal")
        await asyncio.sleep(max(10, int(ctrl.power_poll_s or 60)))


async def watchdog_loop(ctrl: "BoxController") -> None:
    """systemd watchdog: `WATCHDOG=1` jen když poll smyčka běžela v posledních 5 s."""
    interval = sdnotify.watchdog_interval_s()
    if interval is None:
        log.info("WATCHDOG_USEC není nastaven — watchdog neběží")
        return
    await sdnotify.watchdog_loop(
        interval, lambda: bool(getattr(ctrl, "rebuilding", False)) or time.monotonic() - ctrl.last_poll < POLL_HEALTHY_S)


HW_LOOPS = (poll_loop, tick_loop)
NET_LOOPS = (heartbeat_loop, sync_loop, command_loop, status_loop, outbox_loop, watchdog_loop)


def spawn(loops, ctrl: "BoxController") -> list[asyncio.Task]:
    """Vytvoří tasky pro zadané smyčky (pojmenované pro čitelné logy)."""
    return [asyncio.create_task(fn(ctrl), name=f"motogo.{fn.__name__}") for fn in loops]


async def cancel_all(tasks: list[asyncio.Task]) -> None:
    for t in tasks:
        t.cancel()
    for t in tasks:
        try:
            await t
        except (asyncio.CancelledError, Exception):  # noqa: BLE001
            pass
    tasks.clear()
