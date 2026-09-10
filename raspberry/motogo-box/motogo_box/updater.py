"""Aktualizace software a OS z Velína — `SoftwareUpdater` (kontrakt §13, §14, §25).

Příkazy `update_software` / `update_system` se jen NAPLÁNUJÍ (odpověď Velínu odchází hned),
vlastní běh je jeden task na pozadí: počká, až v boxu nikdo není (žádná aktivní relace,
neběží diagnostika — nejdéle `wait_idle_s`, pak pokračuje s varováním), a spustí přes sudo
root skript (`motogo-update` = git ff-merge + pip + restart služby, `motogo-sysupdate` =
apt full-upgrade). Výsledek posledního běhu je trvale v `Storage.kv['last_update']`
(přežije restart i reboot — tick Velína z něj čte výsledek OS aktualizace) a průběh je v
`snapshot()['update']`. Cíl software aktualizace (commit) se předává souborem
`<data_dir>/update_ref`; bez `ref` se soubor smaže a skript aktualizuje na větev.
Spouštění procesu, hodiny i spánek jsou injektovatelné (testy běží bez čekání).

Meze: `cancel()` (stop controlleru) ani timeout NEzastaví root skript — sudo lze zabít, ale
apt/git pod ním běží dál (motogo mu signál poslat nesmí). Po timeoutu proto platí ochranná
lhůta (`script_running`): další `start()` i příkazy `restart`/`reboot` (commands.py) se
odmítají s `update_in_progress`, dokud lhůta nevyprší nebo se proces nerestartuje. Během
`running` se `restart`/`reboot` odmítají také (restart unity by zabil apt uprostřed dpkg).
"""
from __future__ import annotations

import asyncio
import logging
import os
import re
import time
from typing import TYPE_CHECKING, Any, Awaitable, Callable

from .models import Event, EventKind, now_iso

if TYPE_CHECKING:  # pragma: no cover
    from .controller import BoxController

log = logging.getLogger("motogo.updater")

KV_LAST = "last_update"
UPDATE_SCRIPT = "/usr/local/sbin/motogo-update"        # root-owned kopie scripts/update.sh (sudoers)
SYSUPDATE_SCRIPT = "/usr/local/sbin/motogo-sysupdate"  # root-owned kopie scripts/sysupdate.sh (sudoers)
REF_FILE = "update_ref"
SOFTWARE_TIMEOUT_S = 900.0
SYSTEM_TIMEOUT_S = 2700.0
REBOOT_TIMEOUT_S = 60.0
DEFAULT_WAIT_IDLE_S = 1800
MAX_WAIT_IDLE_S = 14400
IDLE_POLL_S = 5.0
OUTPUT_TAIL = 2000
KINDS = ("software", "system", "reboot")   # reboot = restart OS z Velína až v klidu (`wait_idle`)
REF_RE = re.compile(r"^[0-9a-f]{7,40}$")
REBOOT_RE = re.compile(r"^REBOOT_REQUIRED=([01])\s*$", re.MULTILINE)

# runner(argv, timeout_s) → (returncode | None při timeoutu, výstup)
Runner = Callable[[list[str], float], Awaitable[tuple[int | None, str]]]


async def run_process(argv: list[str], timeout_s: float) -> tuple[int | None, str]:
    """Spustí proces (sudo …) a vrátí `(rc, stdout+stderr)`; timeout → `(None, …)`; nikdy nevyhazuje."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *argv, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
    except (OSError, ValueError) as exc:
        return -1, f"spuštění selhalo: {exc}"
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout_s)
    except asyncio.TimeoutError:
        try:
            proc.kill()
        except ProcessLookupError:
            pass
        return None, "timeout"
    return proc.returncode, (out or b"").decode("utf-8", "replace")


def parse_reboot_required(output: str) -> bool | None:
    """Z výstupu `motogo-sysupdate` vytáhne řádek `REBOOT_REQUIRED=0|1`; chybí → None."""
    m = REBOOT_RE.findall(output or "")
    return None if not m else m[-1] == "1"


def _wait_idle_param(params: dict) -> int:
    try:
        n = int(params.get("wait_idle_s", DEFAULT_WAIT_IDLE_S))
    except (TypeError, ValueError):
        n = DEFAULT_WAIT_IDLE_S
    return max(0, min(MAX_WAIT_IDLE_S, n))


class SoftwareUpdater:
    """Jeden běh naráz; `start()` plánuje, `status()` = klíč `update` ve snapshotu."""

    def __init__(self, ctrl: "BoxController", *, runner: Runner | None = None,
                 clock: Callable[[], float] = time.monotonic,
                 sleep: Callable[[float], Awaitable[Any]] = asyncio.sleep,
                 data_dir: str | None = None) -> None:
        self.ctrl = ctrl
        self.runner: Runner = runner or run_process
        self.clock, self.sleep = clock, sleep
        paths = getattr(getattr(ctrl, "local", None), "paths", None)
        self.data_dir = data_dir or str(getattr(paths, "data_dir", None) or "/var/lib/motogo")
        self.kind: str | None = None
        self.state: str = "idle"
        self.ref: str | None = None
        self.rollout_id: str | None = None
        self.started_at: str | None = None
        self.finished_at: str | None = None
        self.error: str | None = None
        self.reboot_required: bool | None = None
        self.output_tail: str | None = None
        self._task: asyncio.Task | None = None
        self._orphan_until: float = 0.0     # po timeoutu: root skript možná stále běží (do kdy blokovat)
        self.script_exists: Callable[[str], bool] = os.path.exists   # testy: injektovatelné
        self.last: dict | None = self._load_last()

    # ─── stav ────────────────────────────────────────────────────────────
    @property
    def running(self) -> bool:
        """Úloha žije — nezávisle na `state` (mezi `done` a rebootem se nesmí přijmout další běh)."""
        return self._task is not None and not self._task.done()

    @property
    def script_running(self) -> bool:
        """Root skript (apt/git) právě běží nebo po timeoutu možná běží → nerestartovat proces/OS."""
        return (self.running and self.state == "running") or self.clock() < self._orphan_until

    def current(self) -> dict:
        return {"kind": self.kind, "state": self.state, "ref": self.ref, "rollout_id": self.rollout_id,
                "started_at": self.started_at, "finished_at": self.finished_at, "error": self.error,
                "reboot_required": self.reboot_required, "output_tail": self.output_tail}

    def status(self) -> dict:
        """Krátký stav pro `snapshot()['update']` (Velín: čeká na klid / probíhá / selhalo)."""
        return {"state": self.state, "kind": self.kind, "ref": self.ref, "since": self.started_at,
                "error": self.error, "last": dict(self.last) if self.last else None}

    def _load_last(self) -> dict | None:
        storage = getattr(self.ctrl, "storage", None)
        try:
            last = storage.kv_get(KV_LAST) if storage is not None else None
        except Exception:  # noqa: BLE001 — poškozené kv nesmí zabránit startu
            log.exception("Načtení last_update selhalo")
            return None
        return last if isinstance(last, dict) else None

    def _save_last(self, **extra: Any) -> None:
        """`last` = aktuální běh (+ `extra`, např. `reboot_at`) → kv (chyba se jen zaloguje)."""
        self.last = {**self.current(), **extra}
        storage = getattr(self.ctrl, "storage", None)
        try:
            if storage is not None:
                storage.kv_set(KV_LAST, self.last)
        except Exception:  # noqa: BLE001
            log.exception("Uložení last_update selhalo")

    # ─── plánování ───────────────────────────────────────────────────────
    def start(self, kind: str, params: dict | None) -> tuple[bool, dict]:
        """Naplánuje běh; vrací HNED `(True, {scheduled, …})` — výsledek Velín pozná z verze/`status.update`."""
        params = params if isinstance(params, dict) else {}
        if kind not in KINDS:
            return False, {"error": "invalid_kind", "kind": kind}
        ref = str(params.get("ref") or "").strip().lower() or None
        if kind == "software" and ref is not None and not REF_RE.match(ref):
            return False, {"error": "invalid_ref"}
        if self.running:
            return False, {"error": "update_in_progress", "state": self.state, "kind": self.kind}
        if self.clock() < self._orphan_until:
            log.warning("Aktualizace %s odmítnuta: předchozí běh %s vypršel a root skript možná stále běží",
                        kind, self.kind)
            return False, {"error": "update_in_progress", "state": self.state, "kind": self.kind,
                           "reason": "timeout_orphan", "retry_after_s": int(self._orphan_until - self.clock())}
        wait_idle_s = _wait_idle_param(params)
        rollout_id = params.get("rollout_id")
        self.kind, self.state, self.ref = kind, "waiting", ref if kind == "software" else None
        self.rollout_id = str(rollout_id) if rollout_id else None
        self.started_at, self.finished_at, self.error = now_iso(), None, None
        self.reboot_required, self.output_tail = None, None
        auto_reboot = bool(params.get("auto_reboot")) if kind == "system" else False
        self._task = asyncio.create_task(self._run_safe(wait_idle_s, auto_reboot), name=f"motogo.update.{kind}")
        log.warning("Aktualizace %s naplánována (ref=%s, rollout=%s, čekání na klid max %d s)",
                    kind, ref, self.rollout_id, wait_idle_s)
        res: dict = {"scheduled": True, "wait_idle_s": wait_idle_s}
        if kind == "software":
            res["ref"] = ref
        elif kind == "system":
            res["auto_reboot"] = auto_reboot
        return True, res

    async def wait(self) -> dict | None:
        """(testy) počká na dokončení běžícího úkolu a vrátí `current()`."""
        if self._task is not None:
            try:
                await self._task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass
        return self.current()

    async def cancel(self) -> None:
        if self._task is not None and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass

    # ─── běh ─────────────────────────────────────────────────────────────
    async def _run_safe(self, wait_idle_s: int, auto_reboot: bool) -> None:
        try:
            if self.kind == "software":
                await self._run_software(wait_idle_s)
            elif self.kind == "reboot":
                await self._run_reboot(wait_idle_s)
            else:
                await self._run_system(wait_idle_s, auto_reboot)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 — chyba úlohy nesmí zůstat viset ve stavu waiting/running
            log.exception("Aktualizace %s spadla", self.kind)
            await self._finish("failed", f"{type(exc).__name__}: {str(exc)[:200]}")

    def _busy(self) -> list[str]:
        """Co brání aktualizaci: aktivní relace (`zone:N`) nebo běžící diagnostika."""
        reasons: list[str] = []
        sessions = getattr(self.ctrl, "_sessions_active", None)
        try:
            reasons += [f"zone:{z}" for z in (sessions() if callable(sessions) else [])]
        except Exception:  # noqa: BLE001
            log.exception("_sessions_active selhalo")
        if getattr(getattr(self.ctrl, "diagnostics", None), "running", False):
            reasons.append("diagnostics")
        return reasons

    async def _wait_idle(self, max_s: int) -> bool:
        """Čeká (poll 5 s), dokud v boxu někdo je; po `max_s` pokračuje i tak → False + warn."""
        t0 = self.clock()
        while True:
            busy = self._busy()
            if not busy:
                return True
            if self.clock() - t0 >= max_s:
                log.warning("Aktualizace %s: čekání na klid vypršelo (%d s), pokračuji — %s",
                            self.kind, max_s, ", ".join(busy))
                return False
            await self.sleep(IDLE_POLL_S)

    def _write_ref(self) -> None:
        """`<data_dir>/update_ref` = cílový commit; bez ref smazat (skript pak jede na @{upstream})."""
        path = os.path.join(self.data_dir, REF_FILE)
        if self.ref:
            with open(path, "w", encoding="ascii") as f:
                f.write(self.ref + "\n")
        elif os.path.lexists(path):
            os.remove(path)

    async def _run_software(self, wait_idle_s: int) -> None:
        idle = await self._wait_idle(wait_idle_s)
        try:
            self._write_ref()
        except OSError as exc:
            await self._finish("failed", f"ref_write_failed: {exc}")
            return
        self.state = "running"
        log.warning("Aktualizace software: %s (ref=%s, klid=%s)", UPDATE_SCRIPT, self.ref, idle)
        rc, out = await self.runner(["sudo", UPDATE_SCRIPT], SOFTWARE_TIMEOUT_S)
        self.output_tail = (out or "")[-OUTPUT_TAIL:]
        if rc == 0:
            await self._finish("done", None)       # proces se restartuje sám (systemd-run ve skriptu)
        else:
            self._mark_orphan(rc, SOFTWARE_TIMEOUT_S)
            await self._finish("failed", "timeout" if rc is None else f"rc={rc}")

    def _mark_orphan(self, rc: int | None, timeout_s: float) -> None:
        """Timeout zabil jen sudo; root skript může běžet dál → ochranná lhůta (další timeout_s)."""
        if rc is None:
            self._orphan_until = self.clock() + timeout_s
            log.error("Aktualizace %s: timeout %.0f s — root skript možná stále běží, další běh "
                      "a restart odmítám dalších %.0f s", self.kind, timeout_s, timeout_s)

    async def _run_system(self, wait_idle_s: int, auto_reboot: bool) -> None:
        if not self.script_exists(SYSUPDATE_SCRIPT):
            # Starší instalace: root-owned motogo-sysupdate nainstaluje až nový motogo-update
            # (první „Aktualizovat software“ na boxu) — jasná chyba místo „command not found“.
            await self._finish("failed", "sysupdate_missing: nejdřív spusťte Aktualizovat software "
                                         "(nainstaluje /usr/local/sbin/motogo-sysupdate)")
            return
        await self._wait_idle(wait_idle_s)
        self.state = "running"
        log.warning("Aktualizace OS: %s (auto_reboot=%s)", SYSUPDATE_SCRIPT, auto_reboot)
        rc, out = await self.runner(["sudo", SYSUPDATE_SCRIPT], SYSTEM_TIMEOUT_S)
        self.output_tail = (out or "")[-OUTPUT_TAIL:]
        self.reboot_required = parse_reboot_required(out or "")
        if rc != 0:
            self._mark_orphan(rc, SYSTEM_TIMEOUT_S)
            await self._finish("failed", "timeout" if rc is None else f"rc={rc}")
            return
        reboot = auto_reboot and bool(self.reboot_required)
        # `last` = done se uloží uvnitř _finish; stav ale přejde rovnou na `waiting` (reboot), aby se
        # během log RPC (LTE, až 10 s) nehlásilo `done` a nepřijal další běh
        await self._finish("done", None, next_state="waiting" if reboot else None)
        if reboot:
            await self._reboot(wait_idle_s)

    async def _run_reboot(self, wait_idle_s: int) -> None:
        """Příkaz `reboot` s `wait_idle` (Velín „Restart OS“): až bude box volný; `last` se NEPŘEPISUJE
        (tick Velína čte z něj výsledek OS aktualizace), stav jde jen do `snapshot()['update']`."""
        await self._wait_idle(wait_idle_s)
        self.state = "rebooting"
        await self._log("info", "controller", "Restart OS z Velína (box je volný)", {})
        log.warning("Restart OS z Velína (box je volný)")
        rc, out = await self.runner(["sudo", "systemctl", "reboot"], REBOOT_TIMEOUT_S)
        if rc != 0:
            self.state, self.error, self.finished_at = "failed", f"reboot_failed: rc={rc}", now_iso()
            await self._log("error", "controller", "Příkaz reboot selhal (sudo)",
                            {"rc": rc, "tail": (out or "")[-OUTPUT_TAIL:]})

    async def _reboot(self, wait_idle_s: int) -> None:
        """Po jádru: znovu počkat na klid, `last` už je uložený, pak `sudo systemctl reboot`."""
        await self._wait_idle(wait_idle_s)            # state je „waiting“ už z _finish(next_state)
        self.state = "rebooting"
        self._save_last(state="done", reboot_at=now_iso())   # last zůstává done (uložen PŘED rebootem)
        await self._log("info", "sysupdate", "Restart OS po aktualizaci jádra (box je volný)", {})
        log.warning("Aktualizace OS: restartuji systém (nové jádro)")
        rc, out = await self.runner(["sudo", "systemctl", "reboot"], REBOOT_TIMEOUT_S)
        if rc != 0:
            self.state, self.error, self.finished_at = "failed", f"reboot_failed: rc={rc}", now_iso()
            self._save_last()      # i `last` = failed → tick Velína nesmí jednotku označit „updated“
            await self._log("error", "sysupdate", "Restart OS po aktualizaci selhal (sudo)",
                            {"rc": rc, "tail": (out or "")[-OUTPUT_TAIL:]})

    # ─── dokončení ───────────────────────────────────────────────────────
    async def _finish(self, state: str, error: str | None, next_state: str | None = None) -> None:
        self.state, self.error, self.finished_at = state, error, now_iso()
        self._save_last()
        if next_state:
            self.state = next_state
        source = "update" if self.kind == "software" else "sysupdate"
        what = "software" if self.kind == "software" else "OS"
        detail = {"ref": self.ref, "rollout_id": self.rollout_id, "reboot_required": self.reboot_required,
                  "tail": self.output_tail, "error": error}
        if state == "done":
            msg = f"Aktualizace {what} dokončena" + (" — vyžaduje restart OS" if self.reboot_required else "")
            level = "info"
        else:
            msg = f"Aktualizace {what} selhala ({error})"
            level = "error"
        log.log(logging.INFO if level == "info" else logging.ERROR, "%s %s", msg, detail)
        storage = getattr(self.ctrl, "storage", None)
        try:
            if storage is not None:
                storage.event_add(Event(kind=EventKind.REMOTE_COMMAND, success=state == "done", level=level,
                                        message=msg, detail={"source": source, **detail}))
        except Exception:  # noqa: BLE001
            log.exception("Uložení události aktualizace selhalo")
        if state == "done" and self.kind == "software" and self._queue_log(level, source, msg, detail):
            return      # update.sh už naplánoval restart za 2 s — RPC by nestihlo, pošle ho outbox po startu
        await self._log(level, source, msg, detail)

    def _queue_log(self, level: str, source: str, message: str, detail: dict) -> bool:
        """`kiosk_log_event` rovnou do outboxu (formát jako `SupabaseApi.log_event`); False bez storage."""
        storage, api = getattr(self.ctrl, "storage", None), getattr(self.ctrl, "api", None)
        if storage is None or api is None:
            return False
        try:
            storage.outbox_add("log_event", {
                "p_level": level, "p_source": source, "p_message": str(message)[:4000],
                "p_detail": detail or {}, "p_app_version": getattr(api, "version", None)})
            return True
        except Exception:  # noqa: BLE001
            log.exception("Zařazení události aktualizace do outboxu selhalo")
            return False

    async def _log(self, level: str, source: str, message: str, detail: dict) -> None:
        api = getattr(self.ctrl, "api", None)
        if api is None:
            return
        try:
            await api.log_event(level, source, message, detail)
        except asyncio.CancelledError:      # stop během RPC (restart unity) → událost do outboxu, ne ztratit
            self._queue_log(level, source, message, detail)
            raise
        except Exception:  # noqa: BLE001 — log do Velína nesmí shodit úlohu
            log.exception("kiosk_log_event (%s) selhalo", source)
