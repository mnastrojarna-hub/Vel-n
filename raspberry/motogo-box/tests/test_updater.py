"""Testy `SoftwareUpdater` (aktualizace software/OS z Velína, §25) s falešným controllerem,
injektovaným runnerem procesů a hodinami — nic reálně nespí ani nespouští sudo."""
from __future__ import annotations

import asyncio

from motogo_box import updater as up
from motogo_box.storage import Storage
from motogo_box.updater import SoftwareUpdater


# ─── falešné prostředí ───────────────────────────────────────────────────────
class FakeApi:
    version = "1.0.0+test123"

    def __init__(self) -> None:
        self.events: list[tuple[str, str, str, dict]] = []
        self.block: asyncio.Event | None = None      # nastaveno → log_event čeká (pomalé LTE)

    async def log_event(self, level, source, message, detail=None):
        if self.block is not None:
            await self.block.wait()
        self.events.append((level, source, message, detail or {}))


def outbox(ctrl) -> list[tuple[str, dict]]:
    return [(kind, payload) for _, kind, payload in ctrl.storage.outbox_pending()]


class FakeDiag:
    running = False


class FakeCtrl:
    def __init__(self, tmp_path, with_storage: bool = True) -> None:
        self.storage = Storage(str(tmp_path / "u.db")) if with_storage else None
        self.api = FakeApi()
        self.diagnostics = FakeDiag()
        self.active: list[int] = []

    def _sessions_active(self) -> list[int]:
        return list(self.active)


class FakeRunner:
    """`results[argv[1]]` = (rc, výstup); `on_call` hook (např. „během apt přišel zákazník“)."""

    def __init__(self, results: dict | None = None, on_call=None) -> None:
        self.results = results or {}
        self.calls: list[tuple[list[str], float]] = []
        self.on_call = on_call

    async def __call__(self, argv, timeout_s):
        self.calls.append((list(argv), timeout_s))
        if self.on_call:
            self.on_call(argv)
        return self.results.get(argv[1], (0, "ok\n"))


class Clock:
    def __init__(self) -> None:
        self.t = 1000.0

    def __call__(self) -> float:
        return self.t


def make(tmp_path, results=None, on_call=None, with_storage=True):
    ctrl = FakeCtrl(tmp_path, with_storage)
    clock, runner = Clock(), FakeRunner(results, on_call)

    async def sleep(s: float) -> None:
        clock.t += s
        await asyncio.sleep(0)

    u = SoftwareUpdater(ctrl, runner=runner, clock=clock, sleep=sleep, data_dir=str(tmp_path))
    u.script_exists = lambda _p: True          # na testovacím stroji /usr/local/sbin/motogo-sysupdate není
    return ctrl, u, runner, clock


async def spin(n: int = 4) -> None:
    for _ in range(n):
        await asyncio.sleep(0)


# ─── software ────────────────────────────────────────────────────────────────
async def test_software_waits_for_active_session_then_runs(tmp_path):
    ctrl, u, runner, clock = make(tmp_path)
    ctrl.active = [1]
    ok, res = u.start("software", {"ref": "8CEFF42ab", "rollout_id": "r-1"})
    assert ok and res == {"scheduled": True, "wait_idle_s": 1800, "ref": "8ceff42ab"}
    await spin()
    assert u.state == "waiting" and runner.calls == [] and u.running
    assert u.status()["state"] == "waiting" and u.status()["since"] and u.status()["ref"] == "8ceff42ab"
    ctrl.active = []
    await u.wait()
    assert u.state == "done" and u.error is None and not u.running
    assert runner.calls == [(["sudo", up.UPDATE_SCRIPT], up.SOFTWARE_TIMEOUT_S)]
    assert (tmp_path / "update_ref").read_text() == "8ceff42ab\n"
    last = ctrl.storage.kv_get("last_update")
    assert last["state"] == "done" and last["kind"] == "software" and last["ref"] == "8ceff42ab"
    assert last["rollout_id"] == "r-1" and last["finished_at"] and last["output_tail"] == "ok\n"
    assert u.status()["last"]["state"] == "done"
    # update.sh restartuje proces za 2 s → událost „dokončeno“ jde rovnou do outboxu, ne přes RPC
    assert ctrl.api.events == []
    assert [(k, p["p_level"], p["p_source"], p["p_app_version"]) for k, p in outbox(ctrl)] == [
        ("log_event", "info", "update", "1.0.0+test123")]
    assert outbox(ctrl)[0][1]["p_detail"]["ref"] == "8ceff42ab"
    ev = ctrl.storage.events_recent(1)[0]
    assert ev["success"] is True and ev["detail"]["source"] == "update"


async def test_software_wait_idle_timeout_continues_anyway(tmp_path):
    ctrl, u, runner, clock = make(tmp_path)
    ctrl.active = [2]
    ok, _ = u.start("software", {"wait_idle_s": 20})
    assert ok
    await u.wait()
    assert runner.calls and u.state == "done" and clock.t >= 1020.0


async def test_software_diagnostics_running_blocks(tmp_path):
    ctrl, u, runner, _ = make(tmp_path)
    ctrl.diagnostics.running = True
    u.start("software", {})
    await spin()
    assert u.state == "waiting" and runner.calls == []
    ctrl.diagnostics.running = False
    await u.wait()
    assert u.state == "done"


async def test_software_without_ref_removes_ref_file(tmp_path):
    ctrl, u, runner, _ = make(tmp_path)
    (tmp_path / "update_ref").write_text("deadbeef\n")
    ok, res = u.start("software", {"ref": ""})
    assert ok and res["ref"] is None
    await u.wait()
    assert not (tmp_path / "update_ref").exists() and u.state == "done"


async def test_invalid_ref_and_kind(tmp_path):
    ctrl, u, runner, _ = make(tmp_path)
    assert u.start("software", {"ref": "main"}) == (False, {"error": "invalid_ref"})
    assert u.start("software", {"ref": "abc12"}) == (False, {"error": "invalid_ref"})
    assert u.start("firmware", {})[1]["error"] == "invalid_kind"
    assert u.state == "idle" and runner.calls == []


async def test_update_in_progress(tmp_path):
    ctrl, u, runner, _ = make(tmp_path)
    ctrl.active = [1]
    assert u.start("software", {})[0]
    await spin()
    ok, res = u.start("system", {})
    assert not ok and res == {"error": "update_in_progress", "state": "waiting", "kind": "software"}
    ctrl.active = []
    await u.wait()
    assert u.start("system", {})[0]          # po dokončení lze znovu
    await u.wait()


async def test_software_failed_rc_logs_error(tmp_path):
    ctrl, u, runner, _ = make(tmp_path, {up.UPDATE_SCRIPT: (3, "fatal: not fast-forward\n")})
    u.start("software", {"ref": "abcdef1"})
    await u.wait()
    assert u.state == "failed" and u.error == "rc=3"
    level, source, msg, detail = ctrl.api.events[-1]
    assert level == "error" and source == "update" and "selhala" in msg and "fast-forward" in detail["tail"]
    assert ctrl.storage.kv_get("last_update")["state"] == "failed"
    assert ctrl.storage.events_recent(1)[0]["level"] == "error"


async def test_software_timeout_blocks_retry_until_window_passes(tmp_path):
    ctrl, u, runner, clock = make(tmp_path, {up.UPDATE_SCRIPT: (None, "timeout")})
    u.start("software", {})
    await u.wait()
    assert u.state == "failed" and u.error == "timeout" and not u.running
    assert u.script_running                     # sudo zabito, root skript možná běží dál
    ok, res = u.start("software", {})
    assert not ok and res["error"] == "update_in_progress" and res["reason"] == "timeout_orphan"
    assert 0 < res["retry_after_s"] <= up.SOFTWARE_TIMEOUT_S and len(runner.calls) == 1
    clock.t += up.SOFTWARE_TIMEOUT_S
    assert not u.script_running
    runner.results[up.UPDATE_SCRIPT] = (0, "ok\n")
    assert u.start("software", {})[0]
    await u.wait()
    assert u.state == "done" and len(runner.calls) == 2


async def test_system_timeout_blocks_for_system_window(tmp_path):
    ctrl, u, runner, clock = make(tmp_path, {up.SYSUPDATE_SCRIPT: (None, "timeout")})
    u.start("system", {"auto_reboot": True})
    await u.wait()
    assert u.state == "failed" and u.error == "timeout" and u.script_running
    assert ctrl.storage.kv_get("last_update")["state"] == "failed"
    clock.t += up.SYSTEM_TIMEOUT_S - 1
    assert u.script_running and not u.start("software", {})[0]
    clock.t += 1
    assert not u.script_running and not u.running


async def test_script_running_only_while_script_runs(tmp_path):
    ctrl, u, runner, _ = make(tmp_path)
    ctrl.active = [1]
    u.start("software", {})
    await spin()
    assert u.running and not u.script_running   # čeká na klid — restart nic nerozbije
    ctrl.active = []
    await u.wait()
    assert not u.script_running


async def test_failed_log_cancelled_during_rpc_goes_to_outbox(tmp_path):
    ctrl, u, runner, _ = make(tmp_path, {up.UPDATE_SCRIPT: (3, "fatal\n")})
    ctrl.api.block = asyncio.Event()             # RPC visí (LTE) → přijde stop() → cancel
    u.start("software", {})
    await spin(6)
    assert u.state == "failed" and u.running and ctrl.api.events == []
    await u.cancel()
    assert not u.running
    assert [(k, p["p_level"], p["p_source"]) for k, p in outbox(ctrl)] == [("log_event", "error", "update")]


# ─── system ──────────────────────────────────────────────────────────────────
SYS_OUT = "Reading package lists...\nUPGRADED=4\nREBOOT_REQUIRED=1\n"


async def test_system_auto_reboot_waits_for_idle(tmp_path):
    ctrl, u, runner, _ = make(tmp_path)

    def customer_arrives(argv):
        if argv[1] == up.SYSUPDATE_SCRIPT:
            ctrl.active = [3]           # během apt přišel zákazník → reboot počká

    runner.on_call = customer_arrives
    runner.results[up.SYSUPDATE_SCRIPT] = (0, SYS_OUT)
    ok, res = u.start("system", {"auto_reboot": True, "rollout_id": "r-2", "wait_idle_s": 600})
    assert ok and res == {"scheduled": True, "wait_idle_s": 600, "auto_reboot": True}
    await spin(6)
    assert [c[0][1] for c in runner.calls] == [up.SYSUPDATE_SCRIPT]
    assert u.state == "waiting" and u.last["state"] == "done" and u.last["reboot_required"] is True
    assert runner.calls[0][1] == up.SYSTEM_TIMEOUT_S
    ctrl.active = []
    await u.wait()
    assert u.state == "rebooting"
    assert runner.calls[-1][0] == ["sudo", "systemctl", "reboot"]
    saved = ctrl.storage.kv_get("last_update")
    assert saved["state"] == "done" and saved["reboot_required"] is True and saved["reboot_at"]
    assert [(e[0], e[1]) for e in ctrl.api.events] == [("info", "sysupdate"), ("info", "sysupdate")]


async def test_system_second_start_during_done_log_rpc_is_refused_and_reboot_happens(tmp_path):
    ctrl, u, runner, _ = make(tmp_path, {up.SYSUPDATE_SCRIPT: (0, SYS_OUT)})
    ctrl.api.block = asyncio.Event()             # log_event „dokončeno“ visí na LTE
    u.start("system", {"auto_reboot": True})
    await spin(6)
    assert u.last["state"] == "done" and u.state == "waiting" and u.running
    ok, res = u.start("software", {"ref": "abcdef1"})    # Velín klikl „Aktualizovat software“
    assert not ok and res == {"error": "update_in_progress", "state": "waiting", "kind": "system"}
    ctrl.api.block.set()
    await u.wait()
    assert u.state == "rebooting" and u.reboot_required is True
    assert [c[0][1] for c in runner.calls] == [up.SYSUPDATE_SCRIPT, "systemctl"]
    assert [(e[0], e[1]) for e in ctrl.api.events] == [("info", "sysupdate"), ("info", "sysupdate")]


async def test_system_without_auto_reboot_only_reports(tmp_path):
    ctrl, u, runner, _ = make(tmp_path, {up.SYSUPDATE_SCRIPT: (0, SYS_OUT)})
    u.start("system", {"auto_reboot": False})
    await u.wait()
    assert u.state == "done" and u.reboot_required is True
    assert [c[0][1] for c in runner.calls] == [up.SYSUPDATE_SCRIPT]
    assert "restart OS" in ctrl.api.events[-1][2]


async def test_system_no_reboot_needed(tmp_path):
    ctrl, u, runner, _ = make(tmp_path, {up.SYSUPDATE_SCRIPT: (0, "UPGRADED=0\nREBOOT_REQUIRED=0\n")})
    u.start("system", {"auto_reboot": True})
    await u.wait()
    assert u.state == "done" and u.reboot_required is False and len(runner.calls) == 1


async def test_system_failed(tmp_path):
    ctrl, u, runner, _ = make(tmp_path, {up.SYSUPDATE_SCRIPT: (2, "E: Unable to lock\n")})
    u.start("system", {"auto_reboot": True})
    await u.wait()
    assert u.state == "failed" and u.error == "rc=2" and len(runner.calls) == 1
    assert ctrl.api.events[-1][:2] == ("error", "sysupdate")
    assert ctrl.storage.kv_get("last_update")["state"] == "failed"


async def test_system_reboot_failure_reported(tmp_path):
    ctrl, u, runner, _ = make(tmp_path, {up.SYSUPDATE_SCRIPT: (0, SYS_OUT), "systemctl": (1, "sudo: denied")})
    u.start("system", {"auto_reboot": True})
    await u.wait()
    assert u.state == "failed" and u.error.startswith("reboot_failed")
    assert ctrl.api.events[-1][:2] == ("error", "sysupdate")
    saved = ctrl.storage.kv_get("last_update")       # tick Velína nesmí jednotku označit „updated“
    assert saved["state"] == "failed" and saved["error"] == "reboot_failed: rc=1" and saved["reboot_required"] is True
    assert u.last == saved


# ─── stav, kv, pomocné ───────────────────────────────────────────────────────
def test_parse_reboot_required():
    assert up.parse_reboot_required(SYS_OUT) is True
    assert up.parse_reboot_required("REBOOT_REQUIRED=0\n") is False
    assert up.parse_reboot_required("nothing") is None
    assert up.parse_reboot_required("") is None


async def test_last_loaded_from_kv_and_storage_none_tolerated(tmp_path):
    ctrl, u, runner, _ = make(tmp_path)
    u.start("software", {})
    await u.wait()
    again = SoftwareUpdater(ctrl, runner=runner, data_dir=str(tmp_path))
    assert again.state == "idle" and again.last["state"] == "done"
    assert again.status() == {"state": "idle", "kind": None, "ref": None, "since": None, "error": None,
                              "last": again.last}
    ctrl2, u2, runner2, _ = make(tmp_path, with_storage=False)
    assert u2.last is None
    u2.start("software", {"ref": "0123456789abcdef"})
    await u2.wait()
    assert u2.state == "done" and u2.last["state"] == "done" and runner2.calls


async def test_wait_idle_s_clamped_and_cancel(tmp_path):
    ctrl, u, runner, _ = make(tmp_path)
    assert u.start("software", {"wait_idle_s": "abc"})[1]["wait_idle_s"] == 1800
    await u.wait()
    assert u.start("software", {"wait_idle_s": 99999})[1]["wait_idle_s"] == up.MAX_WAIT_IDLE_S
    await u.wait()
    ctrl.active = [1]
    u.start("software", {"wait_idle_s": -5})
    await spin()
    await u.cancel()
    assert not u.running


async def test_run_process_returns_rc_and_output():
    rc, out = await up.run_process(["/bin/sh", "-c", "echo hi; exit 4"], 5.0)
    assert rc == 4 and out.strip() == "hi"
    rc, out = await up.run_process(["/definitely/not/here"], 5.0)
    assert rc == -1 and "selhalo" in out


async def test_system_fails_fast_when_sysupdate_script_missing(tmp_path):
    """Starší box (před prvním během nového motogo-update): jasná chyba, sudo se nespouští."""
    ctrl, u, runner, clock = make(tmp_path)
    u.script_exists = lambda _p: False
    ok, res = u.start("system", {"wait_idle_s": 10, "auto_reboot": True})
    assert ok and res["scheduled"] is True
    await u.wait()
    assert u.state == "failed" and u.error.startswith("sysupdate_missing")
    assert runner.calls == []
    assert ctrl.storage.kv_get("last_update")["state"] == "failed"
    assert ctrl.api.events and ctrl.api.events[-1][0] == "error"


async def test_reboot_kind_waits_for_idle_and_keeps_last(tmp_path):
    """`reboot` s `wait_idle` (Velín „Restart OS“): čeká na klid, `last` z předchozí OS aktualizace zůstává."""
    ctrl, u, runner, clock = make(tmp_path)
    ctrl.storage.kv_set("last_update", {"kind": "system", "state": "done", "finished_at": "x"})
    u.last = ctrl.storage.kv_get("last_update")
    ctrl.active = [3]
    ok, res = u.start("reboot", {"wait_idle": True, "wait_idle_s": 120})
    assert ok and res == {"scheduled": True, "wait_idle_s": 120}
    await spin()
    assert u.state == "waiting" and runner.calls == []
    ctrl.active = []
    await u.wait()
    assert runner.calls == [(["sudo", "systemctl", "reboot"], up.REBOOT_TIMEOUT_S)]
    assert u.state == "rebooting" and u.error is None
    assert ctrl.storage.kv_get("last_update") == {"kind": "system", "state": "done", "finished_at": "x"}
    assert ctrl.api.events[-1][:2] == ("info", "controller")


async def test_reboot_kind_failure_reported(tmp_path):
    ctrl, u, runner, clock = make(tmp_path, results={"systemctl": (1, "sudo: denied")})
    ok, _ = u.start("reboot", {"wait_idle": True})
    assert ok
    await u.wait()
    assert u.state == "failed" and u.error == "reboot_failed: rc=1"
    assert ctrl.api.events[-1][0] == "error" and u.last is None
