"""Vstupní bod: `python -m motogo_box controller|health|simulate|check-config`."""
from __future__ import annotations

import asyncio
import logging
import os
import signal
import sys

from . import full_version, sdnotify
from .config import HardwareConfig, load_hardware_file, load_local, validate_hardware


def _setup_logging(level: str) -> None:
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        stream=sys.stdout,
    )


async def _run_controller() -> None:
    from .controller import BoxController
    from .storage import Storage
    from .supabase_api import SupabaseApi
    from .webserver import WebServer

    local = load_local()
    _setup_logging(local.log_level)
    log = logging.getLogger("motogo.main")
    os.makedirs(local.paths.data_dir, exist_ok=True)
    storage = Storage(os.path.join(local.paths.data_dir, "motogo.db"))
    device_id = storage.kv_get("device_id") or local.device.id
    device_token = storage.kv_get("device_token") or local.device.token
    version = full_version()
    api = SupabaseApi(local.supabase.url, local.supabase.anon_key, device_id, device_token, storage, version)
    ctrl = BoxController(local, storage, api, version)
    web = WebServer(ctrl, api, storage, local)

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)

    await web.start()
    # Start HW vrstvy může trvat sekundy (moduly offline → retry); SIGTERM ho musí umět přerušit,
    # jinak by systemd při stopu čekal na doběhnutí startu (TimeoutStopSec).
    start_task = asyncio.create_task(ctrl.start(), name="motogo.start")
    stop_task = asyncio.create_task(stop.wait(), name="motogo.stop_wait")
    await asyncio.wait({start_task, stop_task}, return_when=asyncio.FIRST_COMPLETED)
    if start_task.done():
        if start_task.exception() is not None:  # UI musí běžet i při chybě HW, chybu ukáže
            exc = start_task.exception()
            log.error("Start controlleru selhal", exc_info=exc)
            ctrl.last_error = f"Start řídicí jednotky selhal: {exc}"
            # Type=notify: bez READY=1 by systemd službu po TimeoutStartSec zabil a restartoval
            # v nekonečné smyčce; takto běží UI se srozumitelnou chybou a health/servis dál fungují.
            sdnotify.notify(f"READY=1\nSTATUS=start selhal: {str(exc)[:120]}")
        log.info("MotoGo Box %s běží (web %s:%s)", version, local.web.host, local.web.port)
        await stop_task
    else:
        log.warning("Ukončení vyžádáno během startu — přerušuji start")
        start_task.cancel()
        await asyncio.gather(start_task, return_exceptions=True)
    log.info("Ukončuji…")
    await ctrl.stop()
    await web.stop()
    await api.close()
    storage.close()


async def _run_health() -> None:
    from .health import HealthMonitor

    local = load_local()
    _setup_logging(local.log_level)
    mon = HealthMonitor(local.health, controller_url=f"http://{local.web.host}:{local.web.port}",
                        state_path=os.path.join(local.paths.data_dir, "health.json"))
    await mon.run()


async def _run_simulator() -> None:
    from .tools.simulator import run_simulator

    _setup_logging("INFO")
    await run_simulator()


def _check_config(path: str) -> int:
    hw = HardwareConfig.from_dict(load_hardware_file(path))
    problems = validate_hardware(hw)
    print(f"Zařízení: {', '.join(hw.devices)}")
    print(f"Zón: {len(hw.zones)}")
    for z in hw.zones:
        print(f"  zóna {z.number}: {z.hw.to_dict()}")
    if problems:
        print("PROBLÉMY:")
        for p in problems:
            print("  -", p)
        return 1
    print("OK — konfigurace je konzistentní.")
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    cmd = argv[0] if argv else "controller"
    if cmd == "controller":
        asyncio.run(_run_controller())
    elif cmd == "health":
        asyncio.run(_run_health())
    elif cmd == "simulate":
        asyncio.run(_run_simulator())
    elif cmd == "check-config":
        return _check_config(argv[1] if len(argv) > 1 else "config/brno-9zone.yaml")
    elif cmd in ("version", "--version"):
        print(full_version())
    else:
        print("Použití: python -m motogo_box controller|health|simulate|check-config <hardware.yaml>|version")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
