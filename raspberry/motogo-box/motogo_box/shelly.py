"""Shelly Pro RGBWW PM (režim Lights ×5) — lokální HTTP RPC + signalizace zón.

Kontrakt §5, specifikace §7: `POST http://<host>/rpc` s JSON
`{"id":n,"method":"Light.Set","params":{"id":light_id,"on":bool,"brightness":..,"transition_duration":..}}`.
Každé zařízení má jednoho `httpx.AsyncClient`; po `offline_after` po sobě jdoucích
neúspěších je zařízení `online=False`, první úspěch ho vrátí online.

`SignalController` drží poslední požadovaný vzor per zóna a pro blikání/pulzování
spouští jeden `asyncio.Task` na zónu (při změně vzoru se zruší).
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any, Callable

import httpx

from .config import DeviceCfg, SignalCfg
from .models import HwRef, Signal, ZoneHw

log = logging.getLogger("motogo.shelly")

LIGHT_IDS = (0, 1, 2, 3, 4)
MODBUS_DEFAULT_PORT = 502   # DeviceCfg.port default — pro Shelly znamená „bez portu"
PULSE_LOW_BRIGHTNESS = 15   # dolní úroveň jasu při GREEN_PULSE


def shelly_base_url(host: str, port: int | None = None) -> str:
    """Sestaví base URL. `host` může být 'ip', 'ip:port' nebo 'http://…'.

    Port 502 (Modbus default v `DeviceCfg`) se pro Shelly ignoruje.
    """
    h = (host or "").strip().rstrip("/")
    if h.startswith("http://") or h.startswith("https://"):
        return h
    if port is not None and port != MODBUS_DEFAULT_PORT and ":" not in h:
        return f"http://{h}:{int(port)}"
    return f"http://{h}"


class ShellyRgbww:
    """Jeden modul Shelly Pro RGBWW PM (5 světel, id 0–4)."""

    def __init__(self, name: str, host: str, *, timeout_s: float = 2.0, offline_after: int = 3,
                 port: int | None = None) -> None:
        self.name = name
        self.base_url = shelly_base_url(host, port)
        self.timeout_s = float(timeout_s)
        self.offline_after = max(1, int(offline_after))
        self.online: bool = True
        self.failures: int = 0
        self.on_online_change: Callable[[str, bool], None] | None = None
        self._client: httpx.AsyncClient | None = None
        self._req_id = 0

    @classmethod
    def from_device(cls, dev: DeviceCfg, *, timeout_s: float = 2.0, offline_after: int = 3) -> "ShellyRgbww":
        """Vytvoří klienta z `DeviceCfg` (port 502 = default Modbus → nepoužije se)."""
        return cls(dev.name, dev.host, timeout_s=timeout_s, offline_after=offline_after, port=dev.port)

    def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(base_url=self.base_url, timeout=self.timeout_s)
        return self._client

    def _mark(self, ok: bool) -> None:
        """Aktualizuje čítač selhání a stav online; změnu ohlásí callbackem."""
        was = self.online
        if ok:
            self.failures = 0
            self.online = True
        else:
            self.failures += 1
            if self.failures >= self.offline_after:
                self.online = False
        if was != self.online:
            log.log(logging.INFO if self.online else logging.WARNING,
                    "Shelly %s je %s", self.name, "online" if self.online else "OFFLINE")
            if self.on_online_change is not None:
                try:
                    self.on_online_change(self.name, self.online)
                except Exception:  # noqa: BLE001 — callback nesmí shodit I/O vrstvu
                    log.exception("on_online_change selhal (%s)", self.name)

    async def rpc(self, method: str, params: dict[str, Any]) -> Any:
        """Obecné RPC volání; vrací `result` nebo None při chybě (chybu loguje)."""
        self._req_id += 1
        body = {"id": self._req_id, "method": method, "params": params}
        try:
            resp = await self._get_client().post("/rpc", json=body)
        except httpx.HTTPError as exc:
            self._mark(False)
            log.warning("Shelly %s %s: síťová chyba: %s", self.name, method, exc)
            return None
        except Exception as exc:  # noqa: BLE001 — httpx může vyhodit i jiné výjimky
            self._mark(False)
            log.warning("Shelly %s %s: chyba: %s", self.name, method, exc)
            return None
        if resp.status_code < 200 or resp.status_code >= 300:
            self._mark(False)
            log.warning("Shelly %s %s: HTTP %s %s", self.name, method, resp.status_code, resp.text[:200])
            return None
        try:
            data = resp.json()
        except ValueError:
            self._mark(False)
            log.warning("Shelly %s %s: neplatná JSON odpověď", self.name, method)
            return None
        if isinstance(data, dict) and data.get("error"):
            # Zařízení odpovědělo — je online, ale příkaz odmítlo (např. špatné id).
            self._mark(True)
            log.warning("Shelly %s %s: RPC chyba %s", self.name, method, data.get("error"))
            return None
        self._mark(True)
        return data.get("result", data) if isinstance(data, dict) else data

    async def light_set(self, light_id: int, on: bool, brightness: int | None = None,
                        transition_s: float | None = None) -> bool:
        """`Light.Set` — vrací True při úspěchu. Chyby loguje, nevyhazuje."""
        params: dict[str, Any] = {"id": int(light_id), "on": bool(on)}
        if brightness is not None:
            params["brightness"] = max(0, min(100, int(brightness)))
        if transition_s is not None:
            params["transition_duration"] = max(0.0, float(transition_s))
        return (await self.rpc("Light.Set", params)) is not None

    async def all_off(self) -> bool:
        """Vypne všech 5 světel; True jen pokud všechna potvrdila."""
        ok = True
        for lid in LIGHT_IDS:
            ok = await self.light_set(lid, False) and ok
        return ok

    async def close(self) -> None:
        if self._client is not None:
            client, self._client = self._client, None
            try:
                await client.aclose()
            except Exception:  # noqa: BLE001
                log.debug("Zavření klienta %s selhalo", self.name, exc_info=True)


class SignalController:
    """Řídí červenou/zelenou signalizaci všech zón přes Shelly moduly."""

    def __init__(self, shellies: dict[str, ShellyRgbww], cfg: SignalCfg) -> None:
        self.shellies = shellies
        self.cfg = cfg
        self._current: dict[int, Signal] = {}
        self._confirmed: dict[int, bool] = {}     # Shelly potvrdilo poslední vzor (jinak obnovit)
        self._tasks: dict[int, asyncio.Task] = {}
        self._hw: dict[int, ZoneHw] = {}
        self._refreshing = asyncio.Lock()
        for dev in shellies.values():
            dev.on_online_change = self._online_changed

    def _online_changed(self, name: str, online: bool) -> None:
        """Po návratu Shelly online se všem jeho zónám vzor znovu pošle (`refresh_unconfirmed`)."""
        if not online:
            return
        for zone, hw in self._hw.items():
            if any(r is not None and r.dev == name for r in (hw.red, hw.green)):
                self._confirmed[zone] = False

    # ─── veřejné API ────────────────────────────────────────────────────────
    def current(self, zone: int) -> Signal:
        """Poslední požadovaný vzor zóny (výchozí OFF)."""
        return self._current.get(zone, Signal.OFF)

    def online(self, name: str) -> bool:
        dev = self.shellies.get(name)
        return bool(dev.online) if dev is not None else False

    async def set(self, zone_hw: ZoneHw, signal: Signal) -> None:
        """Nastaví vzor; stejný, Shelly POTVRZENÝ vzor znovu nic neposílá (idempotentní).

        Nepotvrzený vzor (timeout/HTTP chyba) se při dalším `set` téhož vzoru pošle znovu
        a navíc ho pravidelně obnovuje `refresh_unconfirmed` — signalizace se po výpadku
        Shelly sama srovná se stavem zóny.
        """
        zone = zone_hw.zone
        self._hw[zone] = zone_hw
        if self._current.get(zone) == signal and self._confirmed.get(zone, False):
            return
        self._current[zone] = signal
        self._confirmed[zone] = await self._apply(zone_hw, signal)

    async def refresh(self, zone_hw: ZoneHw) -> None:
        """Vynutí znovuposlání aktuálního vzoru (např. po návratu Shelly online)."""
        self._hw[zone_hw.zone] = zone_hw
        self._confirmed[zone_hw.zone] = await self._apply(zone_hw, self.current(zone_hw.zone))

    def unconfirmed(self) -> list[int]:
        return [z for z, hw in self._hw.items() if not self._confirmed.get(z, True)]

    async def refresh_unconfirmed(self) -> int:
        """Znovu pošle vzory, které Shelly nepotvrdilo; offline Shelly nejdřív sonduje
        (`Shelly.GetDeviceInfo`), aby se návrat online poznal i bez jiné komunikace.
        Vrací počet obnovených zón. Běží nejvýš jednou najednou (volá tick smyčka na pozadí)."""
        if self._refreshing.locked():
            return 0
        async with self._refreshing:
            for dev in self.shellies.values():
                if not dev.online:
                    await dev.rpc("Shelly.GetDeviceInfo", {})
            done = 0
            for zone in self.unconfirmed():
                hw = self._hw.get(zone)
                if hw is None:
                    continue
                refs = [r for r in (hw.red, hw.green) if r is not None]
                if refs and not any(self.online(r.dev) for r in refs):
                    continue          # stále offline — bez zbytečných timeoutů
                await self.refresh(hw)
                done += 1 if self._confirmed.get(zone) else 0
            if done:
                log.info("Signalizace obnovena u %d zón", done)
            return done

    async def all_off(self) -> None:
        """Zruší všechny tasky a vypne všechna světla všech Shelly."""
        for zone in list(self._tasks):
            await self._cancel_task(zone)
        # Paralelně per zařízení — při nedostupném Shelly by sekvenční průchod (4 × 5 × timeout)
        # zdržel start i stop o desítky sekund.
        results = await asyncio.gather(*(dev.all_off() for dev in self.shellies.values()), return_exceptions=True)
        ok_devs: set[str] = set()
        for dev, res in zip(self.shellies.values(), results):
            if isinstance(res, BaseException):
                log.error("Shelly %s: all_off selhal: %r", dev.name, res)
            elif res:
                ok_devs.add(dev.name)
        for zone, hw in list(self._hw.items()):
            self._current[zone] = Signal.OFF
            self._confirmed[zone] = all(r is None or r.dev in ok_devs for r in (hw.red, hw.green))

    async def close(self) -> None:
        for zone in list(self._tasks):
            await self._cancel_task(zone)
        for dev in self.shellies.values():
            await dev.close()

    # ─── interní ────────────────────────────────────────────────────────────
    async def _apply(self, hw: ZoneHw, signal: Signal) -> bool:
        """Pošle vzor na Shelly; True = všechna okamžitá `Light.Set` potvrzena."""
        await self._cancel_task(hw.zone)
        b, t = self.cfg.brightness, self.cfg.transition_s
        ok = True
        if signal == Signal.RED:
            ok = await self._send(hw.red, True, b, t) and ok
            ok = await self._send(hw.green, False, None, t) and ok
        elif signal == Signal.GREEN:
            ok = await self._send(hw.green, True, b, t) and ok
            ok = await self._send(hw.red, False, None, t) and ok
        elif signal == Signal.OFF:
            ok = await self._send(hw.red, False, None, t) and ok
            ok = await self._send(hw.green, False, None, t) and ok
        elif signal == Signal.GREEN_PULSE:
            ok = await self._send(hw.red, False, None, t)
            self._start_task(hw.zone, self._pulse_loop(hw))
        elif signal == Signal.RED_BLINK:
            ok = await self._send(hw.green, False, None, t)
            self._start_task(hw.zone, self._blink_loop(hw, [hw.red]))
        elif signal == Signal.BOTH_BLINK:
            self._start_task(hw.zone, self._blink_loop(hw, [hw.red, hw.green]))
        else:  # pragma: no cover — všechny hodnoty enumu jsou pokryté
            log.error("Neznámý signál %r pro zónu %s", signal, hw.zone)
            ok = False
        return ok

    async def _send(self, ref: HwRef | None, on: bool, brightness: int | None,
                    transition_s: float | None) -> bool:
        """Light.Set na kanál dle HwRef; chybějící ref nebo neznámé zařízení přeskočí."""
        if ref is None:
            return True
        dev = self.shellies.get(ref.dev)
        if dev is None:
            log.debug("Signál: neznámé Shelly '%s' — přeskočeno", ref.dev)
            return True     # chyba konfigurace (hlásí validate_hardware), ne výpadek → neobnovovat dokola
        return await dev.light_set(ref.idx, on, brightness, transition_s)

    def _start_task(self, zone: int, coro) -> None:
        task = asyncio.create_task(coro, name=f"signal-zone-{zone}")
        self._tasks[zone] = task

    async def _cancel_task(self, zone: int) -> None:
        task = self._tasks.pop(zone, None)
        if task is None:
            return
        if not task.done():
            task.cancel()
        try:
            await task
        except (asyncio.CancelledError, Exception):  # noqa: BLE001 — task je ukončený
            pass

    async def _blink_loop(self, hw: ZoneHw, refs: list[HwRef | None]) -> None:
        """Střídavě on/off na daných kanálech každých `blink_ms` (bez přechodu)."""
        period = max(0.05, self.cfg.blink_ms / 1000.0)
        on = True
        try:
            while True:
                for ref in refs:
                    await self._send(ref, on, self.cfg.brightness if on else None, 0.0)
                await asyncio.sleep(period)
                on = not on
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 — smyčka nesmí tiše zemřít bez logu
            log.exception("Blink task zóny %s selhal", hw.zone)

    async def _pulse_loop(self, hw: ZoneHw) -> None:
        """Zelená plynule pulzuje mezi 15 a plným jasem s přechodem `pulse_ms`."""
        period = max(0.1, self.cfg.pulse_ms / 1000.0)
        high = True
        try:
            while True:
                level = self.cfg.brightness if high else PULSE_LOW_BRIGHTNESS
                await self._send(hw.green, True, level, period)
                await asyncio.sleep(period)
                high = not high
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001
            log.exception("Pulse task zóny %s selhal", hw.zone)
