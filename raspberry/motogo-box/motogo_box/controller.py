"""`BoxController` — mozek boxu (kontrakt §12, §14, §15).

Drží hardwarovou konfiguraci, I/O sběrnici, signalizaci, audio a stavové
automaty zón; zpracovává kódy z UI, vzdálené příkazy z Velína, synchronizaci
a hlášení stavu. Periodické smyčky jsou v `controller_loops.py`, texty a
mapování událostí v `controller_codes.py`.
"""
from __future__ import annotations

import asyncio
import copy
import json
import logging
import time

from . import commands, controller_codes as cc, controller_hw as chw, controller_loops as loops, sdnotify
from .audio import AudioController
from .audio_build import audio_signature, build_audio, make_music_library
from .config import WARNING_PREFIX, HardwareConfig, LocalConfig, blocking_problems, validate_hardware
from .diagnostics import NetworkDiagnostics
from .io_devices import IoBus
from .models import Event, EventKind, Signal, now_iso
from .outdoor import OutdoorController
from .pins import LocalResolver, PinGuard
from .realtime import RealtimeListener
from .shelly import ShellyRgbww, SignalController
from .storage import Storage
from .supabase_api import SupabaseApi
from .updater import SoftwareUpdater
from .zone import ACTIVE_STATES, ZoneController

log = logging.getLogger("motogo.controller")

NOTICE_TTL_S = 20.0


class BoxController:
    """Řídicí jednotka pobočky: HW vrstva + zóny + Supabase + UI stav."""

    def __init__(self, local: LocalConfig, storage: Storage, api: SupabaseApi, version: str) -> None:
        self.local, self.storage, self.api, self.version = local, storage, api, version
        self.ready: bool = False
        self.rebuilding: bool = False      # přestavba HW vrstvy (watchdog toleruje, PIN/příkazy odmítá)
        self.branch_name: str | None = storage.kv_get("branch_name")
        self.hardware: HardwareConfig = HardwareConfig.from_dict({})
        self.zones: dict[int, ZoneController] = {}
        self.io: IoBus = IoBus(self.hardware)
        self.signals: SignalController = SignalController({}, self.hardware.signal)
        self.audio: AudioController | AudioMulti | None = None
        self.outdoor = OutdoorController(self.hardware.outdoor, self.io, self.hardware.timings, None)   # venek (§26)
        self.music = None                  # music_sync.MusicLibrary (None = modul chybí → legacy playlist)
        self.health: dict = {}
        self.last_error: str | None = None
        self.ui_notice: dict | None = None
        self.lock_gate = asyncio.Lock()
        self.resync_lock = asyncio.Lock()      # sync_loop, příkaz sync_config i párování → nikdy 2 přestavby naráz
        self.wake = asyncio.Event()
        self._last_wake = 0.0
        self.handled_commands: set[str] = set()
        self.last_poll: float = 0.0
        self.power_status_url: str | None = None
        self.power_poll_s: int = 60
        self.config_problems: list[str] = []
        self._local_hw_raw: dict = {}
        self._hw_signature: str = ""
        self._hw_tasks: list[asyncio.Task] = []
        self._net_tasks: list[asyncio.Task] = []
        self._power_task: asyncio.Task | None = None
        self._realtime: RealtimeListener | None = None
        self._realtime_device: str | None = None
        self.service_tokens: dict[str, float] = {}
        self._started_at = time.monotonic()
        self.pin_guard = PinGuard(storage, self.hardware.security)
        self.resolver = LocalResolver(self._device_id(), self._device_token())
        self.diagnostics = NetworkDiagnostics(self)      # diagnostika sítě (kód z displeje / Velín / servis)
        self.updater = SoftwareUpdater(self)             # aktualizace software/OS z Velína (§25) — běží v klidu

    # ─── konfigurace ─────────────────────────────────────────────────────────
    def _device_id(self) -> str:
        return str(getattr(self.api, "device_id", None) or self.local.device.id or "")

    def _device_token(self) -> str:
        return str(getattr(self.api, "device_token", None) or self.local.device.token or "")

    def door_value(self, snapshot: dict, zc: ZoneController) -> bool | None:
        """True = zavřeno dle `closed_level`, None = modul offline (viz `controller_hw.door_value`)."""
        return chw.door_value(self.io, self.hardware, zc, snapshot)

    # ─── životní cyklus ──────────────────────────────────────────────────────
    async def start(self) -> None:
        self._local_hw_raw = chw.load_local_hw(self.local)
        remote = self.storage.kv_get("remote_config")
        extra_problems: list[str] = []
        try:
            self.hardware = chw.build_hardware(self._local_hw_raw, remote)
        except Exception as exc:  # noqa: BLE001 — vadná uložená konfigurace nesmí zablokovat start (boot smyčka)
            log.error("Uložená konfigurace z Velína je neplatná (%s) — startuji s lokální mapou", exc)
            self.storage.kv_delete("remote_config")
            extra_problems.append(f"Konfigurace z Velína nejde načíst: {exc}")
            self.hardware = chw.build_hardware(self._local_hw_raw, None)
        if not self.branch_name and isinstance(remote, dict) and remote.get("branch_name"):
            self.branch_name = str(remote["branch_name"])     # offline start: název z poslední synchronizace
        self._hw_signature = self._signature(self.hardware)
        self.config_problems = extra_problems + validate_hardware(self.hardware)
        for p in self.config_problems:
            log.log(logging.WARNING if p.startswith(WARNING_PREFIX) else logging.ERROR, "Konfigurace: %s", p)
        await self._build_runtime()
        await self._hw_startup()
        self.ready = True
        sdnotify.notify("READY=1")
        await self.emit(Event(kind=EventKind.STARTUP, message=f"MotoGo Box {self.version} spuštěn",
                              level="error" if blocking_problems(self.config_problems) else "info",
                              detail={"version": self.version, "problems": self.config_problems,
                                      "config_source": self.hardware.source, "zones": len(self.zones)}))
        self._hw_tasks = loops.spawn(loops.HW_LOOPS, self)
        self._net_tasks = loops.spawn(loops.NET_LOOPS, self)
        self._start_realtime()

    async def _build_runtime(self) -> None:
        hw = self.hardware
        self.io = IoBus(hw)
        self.io.on_reinit = self._module_reinit     # obnova modulu (all_off) → znovu sepnout audio relé hrající zóny
        shellies = {n: ShellyRgbww.from_device(d, offline_after=hw.polling.device_offline_after_failures)
                    for n, d in hw.shelly_devices().items()}
        self.signals = SignalController(shellies, hw.signal)
        if self.music is None:      # knihovna hudby jen jednou (přežije přestavby; sync běží na pozadí)
            self.music = make_music_library(self.storage, self.local.paths.music_dir, self.local.supabase.url,
                                            self._music_changed)
        self.audio = build_audio(hw, self.local, self.io, self.music)   # selector | multi dle hw.audio.mode
        self.outdoor = OutdoorController(hw.outdoor, self.io, hw.timings, self.audio)   # venek: světlo + kanál outdoor
        self.zones = {}
        for z in hw.zones:
            zc = ZoneController(z, self.io, self.signals, self.audio, hw, self.emit)
            zc.lock_gate = self.lock_gate
            self.zones[z.number] = zc
        self.pin_guard.sec = hw.security

    async def _hw_startup(self) -> None:
        """§12: all relays off → Shelly off → audio off → načíst kontakty → stav zón."""
        await self.io.start()
        for name, ok in (await self.io.all_off()).items():
            module = self.io.modules.get(name)
            if not ok and module is not None and module.online:
                # Modul odpovídá, ale relé nezhasla (zaseklé/svařené) → zóny na něm zůstanou io_offline,
                # dokud opakovaná obnova (reinit = all_off) neprojde (§12 krok 1–2, ověření relé).
                log.error("%s: all_off při startu neprošlo — modul v obnově, jeho zóny jsou mimo provoz", name)
                self.io.mark_reinit(name)
        await self.signals.all_off()
        await self.audio.start()
        await self.audio.all_off()
        snap = await self.io.read_all_inputs()
        for zc in self.zones.values():
            await zc.startup(self.door_value(snap, zc))

    async def _rebuild(self) -> None:
        """Přestavba HW vrstvy po změně zařízení/zón (bezpečně vše vypnout, pak znovu nahodit).

        Po dobu přestavby je `ready=False` (PIN i HW příkazy se odmítají) a `rebuilding=True`
        (systemd watchdog nepovažuje chybějící poll za zamrznutí). Při chybě zůstane jednotka
        `ready=False` a podpis se vynuluje, aby další sync přestavbu zopakoval.
        """
        self.ready, self.rebuilding = False, True
        try:
            await loops.cancel_all(self._hw_tasks)
            await self._shutdown_hw(final=False)
            await self._build_runtime()
            await self._hw_startup()
            self._hw_tasks = loops.spawn(loops.HW_LOOPS, self)
            self.ready = True
        except Exception:
            self._hw_signature = ""
            raise
        finally:
            self.rebuilding = False

    async def _shutdown_hw(self, final: bool) -> None:
        """Bezpečné vypnutí v pořadí §12: relé (vč. zámků a audio selektorů) → audio → Shelly."""
        for step in (self.io.all_off, self.audio.all_off if self.audio else None, self.signals.all_off):
            if step is None:
                continue
            try:
                await step()
            except Exception:  # noqa: BLE001
                log.exception("Vypnutí HW selhalo (%s)", getattr(step, "__qualname__", step))
        if final:
            for zc in self.zones.values():
                if zc.door_closed is True and not zc.fault:
                    await zc.set_signal(Signal.RED)
        for closer in ((self.audio.close if self.audio else None), self.io.stop, self.signals.close):
            if closer is None:
                continue
            try:
                await closer()
            except Exception:  # noqa: BLE001
                log.exception("Zavření HW vrstvy selhalo")

    async def stop(self) -> None:
        self.ready = False
        if self._realtime is not None:
            self._realtime.stop()
        await loops.cancel_all(self._hw_tasks)
        await loops.cancel_all(self._net_tasks)
        if self._power_task is not None:
            await loops.cancel_all([self._power_task])
            self._power_task = None
        await self.diagnostics.cancel()
        await self.updater.cancel()
        await self._shutdown_hw(final=True)

    @staticmethod
    def _signature(hw: HardwareConfig) -> str:
        """Podpis HW + audio topologie (režim/výstupy/kanály = nové mpv procesy → přestavba)."""
        return chw.hw_signature(hw) + json.dumps(audio_signature(hw.audio), sort_keys=True, default=str)

    async def _music_changed(self) -> None:
        """Knihovna hudby dosynchronizována → enginu vyměnit playlisty (hrající kanály až po stopu)."""
        if self.audio is not None:
            await self.audio.reload_playlists()

    async def _module_reinit(self, name: str) -> None:
        if self.audio is not None:
            try:
                await self.audio.reselect_if_playing(name)
            except Exception:  # noqa: BLE001
                log.exception("Obnova audio relé po reinit %s selhala", name)
        try:
            await self.outdoor.on_module_reinit(name)      # venkovní světlo mělo svítit → znovu sepnout
        except Exception:  # noqa: BLE001
            log.exception("Obnova venkovního světla po reinit %s selhala", name)

    def _start_realtime(self) -> None:
        device_id = self._device_id()
        if not device_id or device_id == self._realtime_device:
            return
        if self._realtime is not None:
            self._realtime.stop()

        async def on_wake() -> None:
            now = time.monotonic()
            if now - self._last_wake < 2.0:      # veřejný broadcast topic: spam probuzení nesmí roztočit polling
                return
            self._last_wake = now
            self.wake.set()

        self._realtime = RealtimeListener(self.local.supabase.url, self.local.supabase.anon_key,
                                          f"kiosk:{device_id}", on_wake)
        self._realtime_device = device_id
        self._net_tasks.append(asyncio.create_task(self._realtime.run(), name="motogo.realtime"))

    def apply_heartbeat(self, res: dict) -> None:
        """Z odpovědi `kiosk_heartbeat`: název pobočky + power polling."""
        name = res.get("branch_name")
        if name and name != self.branch_name:
            self.branch_name = str(name)
            self.storage.kv_set("branch_name", self.branch_name)
        self.power_status_url = (res.get("power_status_url") or "").strip() or None
        self.power_poll_s = int(res.get("power_poll_seconds") or 60)
        if self.power_status_url and (self._power_task is None or self._power_task.done()):
            self._power_task = asyncio.create_task(loops.power_loop(self), name="motogo.power_loop")

    # ─── kódy ────────────────────────────────────────────────────────────────
    async def submit_code(self, code: str, source: str = "ui", *, diagnostics_only: bool = False) -> dict:
        """Kód z UI/Velína → ověření + otevření (viz `controller_codes.submit_code`)."""
        return await cc.submit_code(self, code, source, diagnostics_only=diagnostics_only)

    def check_service_token(self, token: str | None) -> bool:
        now = time.time()
        self.service_tokens = {t: exp for t, exp in self.service_tokens.items() if exp > now}
        return bool(token) and token in self.service_tokens

    async def service_open(self, door_id: str | None, zone: int | None) -> dict:
        if not self.ready:
            return {"ok": False, "error": "not_ready", "message": cc.error_text("not_ready"), "zone": None}
        zc = self.find_zone(door_id=door_id) if door_id else None
        if zc is None and zone is not None:
            zc = self.find_zone(zone=zone)
        if zc is None:
            return {"ok": False, "error": "zone_not_found", "message": "Zóna není nastavena.", "zone": None}
        ok, reason = await zc.grant_access(booking_id=None, kind="service", source="service_panel")
        return {"ok": ok, "error": None if ok else reason, "zone": zc.number,
                "message": cc.open_result_text(ok, reason, "service", zc.zone.display_name)}

    # ─── příkazy a sync ──────────────────────────────────────────────────────
    async def handle_command(self, cmd: dict) -> None:
        cid, command, params = str(cmd.get("id") or ""), str(cmd.get("command") or ""), cmd.get("params") or {}
        log.info("Příkaz z Velína %s: %s %s", cid, command, params)
        # proces skončí uvnitř execute → potvrdit PŘEDEM; ne když ho běžící aktualizace odmítne (update_blocks)
        terminal = command in commands.TERMINAL_COMMANDS and commands.update_blocks(self, command) is None
        if terminal:
            await self.api.complete_command(cid, True, {"scheduled": True})
        ok, result = await commands.execute(self, command, params)
        self.storage.event_add(Event(kind=EventKind.REMOTE_COMMAND, success=ok, message=f"Příkaz {command}",
                                     detail={"source": "velin", "command": command, "params": params, "result": result}))
        if not terminal:
            # reboot/update_software: proces běží dál, dokud sudo skutečně nezabere → Velín dostane
            # skutečný výsledek (selhání sudoers/timeout se neztratí); po úspěšném rebootu se
            # nedoručené potvrzení odešle z outboxu po startu.
            await self.api.complete_command(cid, ok, result)

    async def resync(self) -> dict:
        """Stažení konfigurace + kódů z Velína (`kiosk_sync_config`), bezpečné uplatnění změn.

        Pořadí: identita (resolver/realtime) → RPC → legacy plaintext přehashovat → sestavit
        a ZVALIDOVAT HW mapu → teprve potom uložit do kv (`remote_config` bez kódů) a code cache.
        Neparsovatelná nebo neplatná mapa se NIKDY neuloží (jinak by po restartu shodila start).
        Běží pod `resync_lock` (sync smyčka, příkaz sync_config a párování se nesmí prolnout).
        """
        async with self.resync_lock:
            return await self._resync_locked()

    def _sessions_active(self) -> list[int]:
        return [zc.number for zc in self.zones.values() if zc.state in ACTIVE_STATES]

    async def _resync_locked(self) -> dict:
        # Přepárování mohlo změnit identitu — resolver a realtime hned, nezávisle na výsledku RPC.
        self.resolver = LocalResolver(self._device_id(), self._device_token())
        self._start_realtime()
        payload = await self.api.sync_config()
        if not isinstance(payload, dict) or not payload.get("ok", True):
            return {"ok": False, "error": "sync_failed", "changed": False, "problems": self.config_problems}
        payload = cc.hash_legacy_payload(payload, self._device_id(), self._device_token())
        try:
            hw = chw.build_hardware(self._local_hw_raw, payload)
        except Exception as exc:  # noqa: BLE001 — neplatné hodnoty z Velína (typy, struktura)
            log.error("Konfigurace z Velína nejde načíst: %s", exc)
            await self.emit(Event(kind=EventKind.CONFIG_PROBLEM, success=False, level="error",
                                  message="Konfigurace z Velína nejde načíst", detail={"error": str(exc)}))
            self.storage.save_code_cache(payload)      # kódy na HW mapě nezávisí — cache aktualizovat
            return {"ok": False, "error": "config_invalid", "changed": False, "problems": [str(exc)]}
        problems = validate_hardware(hw)
        sig = self._signature(hw)
        changed = sig != self._hw_signature
        self.storage.save_code_cache(payload)
        if payload.get("branch_name"):
            self.apply_heartbeat({"branch_name": payload["branch_name"], "power_status_url": self.power_status_url,
                                  "power_poll_seconds": self.power_poll_s})
        if changed and blocking_problems(problems):
            log.error("Nová konfigurace má chyby, HW se nepřestavuje: %s", problems)
            await self.emit(Event(kind=EventKind.CONFIG_PROBLEM, success=False, level="error",
                                  message="Konfigurace z Velína je neplatná", detail={"problems": problems}))
            return {"ok": False, "error": "config_invalid", "changed": False, "problems": problems}
        active = self._sessions_active() if changed else []
        if active:
            # Přestavba = all_off (zhasnutí světla v obsazené kóji, konec relací) → počkat, až všechny
            # relace skončí; další sync (60 s) to zkusí znovu. Nová cache kódů už platí.
            log.warning("Změna HW mapy odložena — běží relace v zónách %s", active)
            return {"ok": True, "changed": False, "deferred": True, "active_zones": active, "problems": problems}
        self.storage.kv_set("remote_config", cc.config_part(payload))   # až po validaci, bez kódů
        if "music" in payload and self.music is not None:
            music = payload.get("music")
            self.music.start_sync(list(music.get("tracks") or []) if isinstance(music, dict) else [])
        self.hardware, self.config_problems, self._hw_signature = hw, problems, sig
        self.pin_guard.sec = hw.security
        if changed:
            log.warning("Změna zařízení/zón/pollingu — přestavuji HW vrstvu")
            await self._rebuild()
        else:
            self.signals.cfg = hw.signal
            self.audio.update_cfg(hw.audio, hw.timings)
            self.outdoor.update_cfg(hw.outdoor, hw.timings)
            for z in hw.zones:
                zc = self.zones.get(z.number)
                if zc is not None:
                    zc.hw, zc.zone = hw, z
        return {"ok": True, "changed": changed, "problems": problems}

    # ─── stav, události, pomocné ─────────────────────────────────────────────
    def snapshot(self) -> dict:
        notice = self.ui_notice
        if notice and time.time() - float(notice.get("ts") or 0) > NOTICE_TTL_S:
            self.ui_notice = notice = None
        modules = {n: self.io.is_online(n) for n in self.hardware.modbus_devices()}
        modules.update({n: self.signals.online(n) for n in self.hardware.shelly_devices()})
        return {
            "ts": now_iso(), "version": self.version, "uptime_s": int(time.monotonic() - self._started_at),
            "ready": self.ready, "branch_name": self.branch_name, "internet": bool(getattr(self.api, "online", False)),
            "config_source": self.hardware.source, "config_problems": list(self.config_problems),
            "modules": modules,
            "audio": self.audio.status() if self.audio else {
                "mode": self.hardware.audio.engine_mode, "playing_zone": None, "playing_zones": [], "channels": [],
                "player_ok": False, "playlist_count": 0, "device": None, "players": {}, "library": None},
            "health": self.health, "last_error": self.last_error,
            "zones": [zc.status().to_dict() for zc in sorted(self.zones.values(), key=lambda z: z.number)],
            "outdoor": self.outdoor.status(),
            "notice": copy.deepcopy(notice) if notice else None,
            "diagnostics": self.diagnostics.status(),
            "update": self.updater.status(),
        }

    async def all_off(self) -> None:
        """Vše bezpečně vypnout (audio, relé, Shelly) a zóny uvést do klidového stavu."""
        if self.audio:
            await self.audio.all_off()
        await self.outdoor.all_off()
        await self.io.all_off()
        await self.signals.all_off()
        for zc in self.zones.values():
            await zc.force_secure()

    async def emit(self, event: Event) -> None:
        """Lokální záznam + Supabase (fire-and-forget) + UI upozornění (§15)."""
        try:
            self.storage.event_add(event)
        except Exception:  # noqa: BLE001
            log.exception("Uložení události selhalo")
        if event.level == "error":
            self.last_error = event.message
        if event.kind in cc.NOTICE_KINDS:
            self.ui_notice = {"title": event.message, "kind": "error", "ts": time.time(),
                              "subtitle": "Kontaktujte podporu: " + cc.SUPPORT}
        detail = cc.open_detail(event)
        if event.kind in cc.LOG_OPEN_KINDS:
            coro = self.api.log_open(event.door_id, cc.log_open_kind(event), event.booking_id, event.success, detail)
        elif event.kind in cc.LOG_EVENT_SOURCES:
            coro = self.api.log_event(event.level, cc.LOG_EVENT_SOURCES[event.kind], event.message, detail)
        else:
            return
        task = asyncio.create_task(coro, name=f"motogo.log.{event.kind.value}")
        task.add_done_callback(_log_task_result)

    def find_zone(self, *, door_id: str | None = None, zone: int | None = None,
                  box_number: int | None = None) -> ZoneController | None:
        for zc in self.zones.values():
            if door_id is not None and zc.zone.door_id == door_id:
                return zc
        if zone is not None:
            return self.zones.get(int(zone))
        if box_number is not None:
            return next((zc for zc in self.zones.values() if zc.zone.box_number == box_number), None)
        return None


def _log_task_result(task: asyncio.Task) -> None:
    if task.cancelled():
        return
    exc = task.exception()
    if exc is not None:
        log.warning("Odeslání události %s selhalo: %s", task.get_name(), exc)
