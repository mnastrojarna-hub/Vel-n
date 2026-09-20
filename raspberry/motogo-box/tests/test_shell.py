"""Testy servisního terminálu na displeji (kontrakt §27) — `motogo_box/shell.py`."""
from __future__ import annotations

import time

import pytest

from motogo_box import shell
from motogo_box.models import EventKind


class FakeCtrl:
    """Minimální controller: drží stav odemčení, tokeny a posbírané události (audit)."""

    def __init__(self) -> None:
        self.shell_until = 0.0
        self.shell_tokens: dict[str, float] = {}
        self.events: list = []

    async def emit(self, event) -> None:
        self.events.append(event)


@pytest.fixture()
def ctrl() -> FakeCtrl:
    return FakeCtrl()


# ─── nabídka a tokeny ────────────────────────────────────────────────────────
def test_menu_never_leaks_argv():
    menu = shell.menu()
    assert menu and all("argv" not in p for p in menu)          # co se spustí, rozhoduje jednotka
    assert all(p.get("id") and p.get("label") and p.get("group") for p in menu)
    assert {p["id"] for p in menu} >= {"net.addr", "net.lan_up", "lte.modem", "sys.failed", "log.controller"}


def test_token_issue_expire_and_reject(ctrl):
    token = shell.issue_token(ctrl)
    assert shell.check_token(ctrl, token) is True
    assert shell.check_token(ctrl, "cizí") is False
    assert shell.check_token(ctrl, None) is False
    ctrl.shell_tokens[token] = time.time() - 1                   # prošlý se zahodí
    assert shell.check_token(ctrl, token) is False and token not in ctrl.shell_tokens


def test_issue_token_survives_controller_without_store():
    class Slotted:
        __slots__ = ()

    assert shell.issue_token(Slotted()) is None                  # nesmí shodit ověření kódu


# ─── odemčení volného psaní ──────────────────────────────────────────────────
def test_unlock_clamps_and_locks(ctrl):
    assert shell.unlock(ctrl, 30)["free"] is True
    assert 29 * 60 <= shell.free_seconds(ctrl) <= 30 * 60
    shell.unlock(ctrl, 9999)                                     # strop
    assert shell.free_seconds(ctrl) <= shell.FREE_MAX_MINUTES * 60
    shell.unlock(ctrl, 1)                                        # minimum
    assert shell.free_seconds(ctrl) >= shell.FREE_MIN_MINUTES * 60 - 1
    assert shell.unlock(ctrl, 0) == {"free": False, "free_s": 0}
    assert shell.unlock(ctrl, "nesmysl")["free"] is True          # vadná hodnota → výchozích 30 min


def test_state_expires_by_itself(ctrl):
    ctrl.shell_until = time.time() - 1
    assert shell.state(ctrl) == {"free": False, "free_s": 0}


# ─── spouštění ───────────────────────────────────────────────────────────────
async def test_preset_runs_and_is_audited(ctrl):
    res = await shell.run(ctrl, preset_id="sys.disk")
    assert res["ok"] is True and res["rc"] == 0 and "/" in res["output"]
    assert ctrl.events and ctrl.events[-1].kind is EventKind.SHELL
    assert ctrl.events[-1].detail["preset"] == "sys.disk" and ctrl.events[-1].detail["free_text"] is False


async def test_unknown_preset_and_bad_arg(ctrl):
    assert (await shell.run(ctrl, preset_id="rm.all"))["error"] == "unknown_preset"
    for bad in ("", "8.8.8.8; rm -rf /", "$(whoami)", "a" * (shell.ARG_MAX + 1)):
        assert (await shell.run(ctrl, preset_id="net.ping", arg=bad))["error"] == "invalid_arg"
    assert ctrl.events == []                                     # odmítnuté se nespouští, tedy ani neloguje


async def test_free_text_needs_unlock(ctrl):
    assert (await shell.run(ctrl, command="echo ahoj"))["error"] == "locked"
    assert (await shell.run(ctrl, command="   "))["error"] == "empty"
    shell.unlock(ctrl, 30)
    res = await shell.run(ctrl, command="echo ahoj")
    assert res["ok"] is True and res["output"].strip() == "ahoj" and res["free_s"] > 0
    assert ctrl.events[-1].detail["free_text"] is True and "echo ahoj" in ctrl.events[-1].message
    assert ctrl.events[-1].detail["auth"] == "diag_code"


async def test_service_password_writes_freely_offline(ctrl):
    """Servisní heslo (`service=True`) nepotřebuje Velín — terminál musí fungovat i na offline pobočce."""
    assert shell.state(ctrl)["free"] is False            # nic odemčeného z Velína
    res = await shell.run(ctrl, command="echo offline", service=True)
    assert res["ok"] is True and res["output"].strip() == "offline"
    assert ctrl.events[-1].detail["auth"] == "service_code"
    # diagnostický kód na tomtéž boxu volné psaní pořád nemá
    assert (await shell.run(ctrl, command="echo ne"))["error"] == "locked"


async def test_free_text_reports_failures_and_trims_output(ctrl):
    shell.unlock(ctrl, 30)
    bad = await shell.run(ctrl, command="exit 3")
    assert bad["ok"] is False and bad["rc"] == 3 and ctrl.events[-1].level == "warn"

    long = await shell.run(ctrl, command=f"printf 'x%.0s' $(seq 1 {shell.OUTPUT_LIMIT + 500})")
    assert long["truncated"] is True and len(long["output"]) <= shell.OUTPUT_LIMIT + 40
    assert len(ctrl.events[-1].detail["output"]) <= shell.LOG_OUTPUT_LIMIT


async def test_run_survives_missing_binary_and_audit_failure(ctrl):
    res = await shell.run(ctrl, preset_id="log.update")           # soubor na vývojovém stroji nemusí být
    assert "rc" in res and isinstance(res["output"], str)

    class Broken(FakeCtrl):
        async def emit(self, event):
            raise RuntimeError("outbox mimo")

    ok = await shell.run(Broken(), preset_id="sys.disk")
    assert ok["ok"] is True                                       # selhání auditu nesmí shodit odpověď displeji
