"""Kroky kompletní diagnostiky pobočky mimo síť (kontrakt §24, režim `full`):
`software`, `config`, `zones`, `power`, `cameras`. Každý krok je izolovaný — volá ho
`NetworkDiagnostics.run` s limitem a chyba jednoho neshodí běh. Vše čitelné bez rootu.

Bezpečnost HW testu zón: zámek se NIKDY nespíná (jen se čte stav relé); test světla/zelené/tónu
(`ZoneController.test_sequence`) běží SEKVENČNĚ (audio selektor je exkluzivní) a jen v zóně
bez relace, bez poruchy, s online I/O, při `ctrl.ready` a `diagnostics.zone_test`.
"""
from __future__ import annotations

import asyncio
import dataclasses
import logging
import os
import time
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any

import httpx

from .health import run_cmd
from .mpv_player import MUSIC_EXTENSIONS
from .zone import ACTIVE_STATES

if TYPE_CHECKING:  # pragma: no cover
    from .diagnostics import NetworkDiagnostics

log = logging.getLogger("motogo.diagnostics")

SERVICES = ("motogo-controller", "motogo-health", "motogo-ui")
ZONE_TEST_BUDGET_S = 15.0     # HW test zóny (světlo, zelená 1 s, tón 3 s, RPC Shelly) se nespustí, zbývá-li méně
ZONE_TEST_TIMEOUT_S = 30.0    # limit jednoho HW testu; po něm test doběhne na pozadí (obnova světla/signálu/tónu)
REBOOT_REQUIRED = "/run/reboot-required"
ROLES = ("lock", "contact", "light", "audio", "red", "green")
POWER_KEYS = {
    "battery_soc": ("battery_soc", "soc", "SOC", "stateOfCharge"),
    "battery_voltage": ("battery_voltage", "batteryVoltage", "vBat", "battery_v"),
    "battery_power_w": ("battery_power_w", "batteryPower", "pBat", "battery_w"),
    "pv_power_w": ("pv_power_w", "pvPower", "pv_w", "solar_w", "pPv"),
    "load_power_w": ("load_power_w", "loadPower", "load_w", "consumption_w", "pLoad"),
    "grid_present": ("grid_present", "gridPresent", "grid", "mains"),
}
MAX_CAMERAS = 20


def _iso(ts: float | None) -> str | None:
    return None if ts is None else datetime.fromtimestamp(float(ts), timezone.utc).isoformat(timespec="seconds")


def _age_s(iso: Any) -> float | None:
    try:
        return round(max(0.0, (datetime.now(timezone.utc) - datetime.fromisoformat(str(iso))).total_seconds()), 1)
    except (TypeError, ValueError):
        return None


def _try(fn, default=None):
    try:
        return fn()
    except Exception:  # noqa: BLE001 — chybějící úložiště/atribut nesmí shodit krok
        return default


def _ref(r) -> str | None:
    return None if r is None else f"{r.dev}:{r.idx}"


# ─── software ────────────────────────────────────────────────────────────────
async def software(diag: "NetworkDiagnostics", report: dict) -> dict:
    ctrl = diag.ctrl
    services: dict[str, str | None] = {}
    for unit in SERVICES:
        rc, out = await run_cmd("systemctl", "is-active", unit, timeout=5)
        state = (out or "").strip().split("\n")[0].strip()
        services[unit] = state if rc in (0, 3) and state in ("active", "inactive", "failed", "activating", "deactivating") else None
    rc, out = await run_cmd("systemctl", "--failed", "--no-legend", "--plain", timeout=5)
    failed_units = sum(1 for ln in (out or "").splitlines() if ln.strip()) if rc == 0 else None
    audio = getattr(ctrl, "audio", None)
    ast = _try(lambda: audio.status() if audio is not None and hasattr(audio, "status") else {}) or {}
    player = getattr(audio, "player", None)
    music_dir = str(getattr(getattr(ctrl.local, "paths", None), "music_dir", "") or "")
    music_files = _try(lambda: sum(1 for n in os.listdir(music_dir) if n.lower().endswith(MUSIC_EXTENSIONS)))
    storage = ctrl.storage
    recent: list[dict] = []
    for ev in _try(lambda: storage.events_recent(200), []) or []:
        if str(ev.get("level")) in ("error", "crash") and (_age_s(ev.get("ts")) or 0) <= 24 * 3600:
            recent.append({"ts": ev.get("ts"), "kind": ev.get("kind"), "message": str(ev.get("message") or "")[:200]})
        if len(recent) >= 10:
            break
    cache = _try(storage.load_code_cache) or {}
    saved_at = _try(storage.code_cache_saved_at)
    realtime = getattr(ctrl, "realtime", None) or getattr(ctrl, "_realtime", None)
    health = ctrl.health if isinstance(getattr(ctrl, "health", None), dict) else {}
    updater_last = getattr(getattr(ctrl, "updater", None), "last", None)
    return {
        "version": ctrl.version, "uptime_s": int(time.monotonic() - ctrl._started_at), "ready": bool(ctrl.ready),
        "config_source": ctrl.hardware.source, "config_problems": list(ctrl.config_problems),
        "services": services, "failed_units": failed_units,
        "audio": {"player_ok": bool(audio and getattr(audio, "player_ok", False)),
                  "playlist_count": int(ast.get("playlist_count", getattr(player, "playlist_count", 0)) or 0),
                  "device": ast.get("device", getattr(player, "device", None)), "music_files": music_files,
                  "mode": ast.get("mode"), "players": ast.get("players"), "library": ast.get("library")},
        "realtime": {"connected": getattr(realtime, "connected", None)},
        "api": {"online": getattr(ctrl.api, "online", None), "paired": bool(getattr(ctrl.api, "paired", False))},
        "outbox_pending": _try(storage.outbox_count), "events_total": _try(storage.events_count),
        "recent_errors": recent, "lockout_until": _iso(_try(storage.lockout_until)),
        "code_cache": {"saved_at": _iso(saved_at), "age_s": None if saved_at is None else round(time.time() - saved_at),
                       "codes": len(cache.get("codes") or []), "service_codes": len(cache.get("service_codes") or [])},
        "last_update": dict(updater_last) if isinstance(updater_last, dict) else None,
        "reboot_required": _try(lambda: os.path.exists(REBOOT_REQUIRED)),
        "health_age_s": _age_s(health.get("ts")) if health.get("ts") else None,
    }


# ─── config ──────────────────────────────────────────────────────────────────
async def config(diag: "NetworkDiagnostics", report: dict) -> dict:
    ctrl = diag.ctrl
    hw = ctrl.hardware
    zones, seen, dups = [], {}, []
    for z in hw.zones:
        roles = {r: _ref(getattr(z.hw, r)) for r in ROLES}
        for role, ref in roles.items():
            if ref is None:
                continue
            kind = "input" if role == "contact" else ("light" if role in ("red", "green") else "coil")
            key = (ref, kind)
            if key in seen:
                dups.append(f"{ref} sdílí zóna {seen[key][0]} ({seen[key][1]}) a zóna {z.number} ({role})")
            seen.setdefault(key, (z.number, role))
        zones.append({"zone": z.number, "label": z.display_name, "kind": z.kind, "door_id": z.door_id,
                      "box_number": z.box_number, "roles": roles, "missing": [r for r in ROLES if roles[r] is None]})
    doors_without_hw: list[str] = []
    remote = _try(lambda: ctrl.storage.kv_get("remote_config"))
    if hw.source == "remote" and isinstance(remote, dict):
        for d in remote.get("doors") or []:
            if isinstance(d, dict) and not (isinstance(d.get("hw"), dict) and d["hw"].get("zone") is not None):
                doors_without_hw.append(str(d.get("label") or f"Kóje {d.get('box_number')}"))
    t = hw.timings
    tp: list[str] = []
    if not 100 <= int(t.lock_pulse_ms) <= 5000:
        tp.append(f"lock_pulse_ms {t.lock_pulse_ms} mimo 100–5000 ms")
    if int(t.door_open_timeout_s) < 5:
        tp.append(f"door_open_timeout_s {t.door_open_timeout_s} < 5 s")
    if int(t.maximum_session_s) < 60:
        tp.append(f"maximum_session_s {t.maximum_session_s} < 60 s")
    if int(t.light_after_close_s) < int(t.music_after_close_s):
        tp.append(f"light_after_close_s {t.light_after_close_s} < music_after_close_s {t.music_after_close_s}")
    return {"branch_name": ctrl.branch_name, "source": hw.source, "zones_total": len(zones), "zones": zones,
            "doors_without_hw": doors_without_hw, "duplicates": dups, "timings": dataclasses.asdict(t), "timings_problems": tp,
            "devices": {n: {"type": d.type, "host": d.host, "port": d.port} for n, d in hw.devices.items()},
            "power_status_url": getattr(ctrl, "power_status_url", None), "cameras_provided": len(diag.cameras_list()),
            "security": dataclasses.asdict(hw.security)}


# ─── zones ───────────────────────────────────────────────────────────────────
async def zones(diag: "NetworkDiagnostics", report: dict) -> list[dict]:
    ctrl = diag.ctrl
    zcs = sorted((getattr(ctrl, "zones", None) or {}).values(), key=lambda z: z.number)
    out: list[dict] = []
    diag._partial["zones"] = out          # rozpracované zóny přežijí timeout kroku
    if not zcs:
        return out
    snapshot = await ctrl.io.read_all_inputs() if hasattr(ctrl.io, "read_all_inputs") else {}
    for zc in zcs:                        # SEKVENČNĚ — audio selektor je exkluzivní
        out.append(await _zone_one(diag, zc, snapshot or {}))
    return out


def _closed_level(ctrl, zc) -> bool:
    lvl = zc.zone.hw.closed_level
    return bool(lvl if lvl is not None else getattr(ctrl.hardware, "contacts_closed_level", 1))


async def _zone_one(diag: "NetworkDiagnostics", zc, snapshot: dict) -> dict:
    ctrl, hw, z = diag.ctrl, zc.zone.hw, zc.zone
    state = getattr(zc.state, "value", zc.state)
    fault = getattr(zc, "fault", None)
    findings: list[dict] = []

    def add(key: str, status: str, message: str, **extra: Any) -> None:
        findings.append({"key": key, "status": status, "message": message, **extra})

    active = zc.state in ACTIVE_STATES
    contact_raw = None
    if hw.contact is not None:
        raw = _try(lambda: ctrl.io.input_value(snapshot, hw.contact))
        contact_raw = None if raw is None else (bool(raw) == _closed_level(ctrl, zc))
        if raw is None:
            add("contact", "fail", f"dveřní kontakt: modul {hw.contact.dev} nečte vstup DI{hw.contact.idx + 1} (offline)")
    else:
        add("contact", "fail", "dveřní kontakt: není nastaven v HW mapě")
    consistent = None if contact_raw is None or zc.door_closed is None else contact_raw == zc.door_closed
    if consistent is False:
        add("contact", "fail", f"dveřní kontakt: program hlásí {'zavřeno' if zc.door_closed else 'otevřeno'}, modul "
                               f"{hw.contact.dev} DI{hw.contact.idx + 1} čte {'zavřeno' if contact_raw else 'otevřeno'}")
    io_problems = _try(zc.io_problems, []) or []
    lock = {"configured": hw.lock is not None, "module_online": None, "coil_off": None}
    if hw.lock is None:
        add("lock", "fail", "zámek: není nastaven v HW mapě")
    else:
        lock["module_online"] = bool(_try(lambda: ctrl.io.is_online(hw.lock.dev), False))
        if not lock["module_online"]:
            add("lock", "fail", f"zámek: modul {hw.lock.dev} offline")
        else:
            coils = await _read_coils(ctrl, hw.lock.dev)      # jen ČTENÍ — zámek se nikdy nespíná
            if coils is not None and 0 <= hw.lock.idx < len(coils):
                lock["coil_off"] = not coils[hw.lock.idx]
                if not lock["coil_off"]:
                    add("lock", "fail", f"zámek: relé {hw.lock.dev} R{hw.lock.idx + 1} je SEPNUTÉ v klidu — NEBEZPEČÍ, odpojte modul")
    if fault:
        add("fault", "fail" if fault == "io_offline" else "warn", f"zóna v poruše {fault}" + (f" ({', '.join(io_problems)})" if io_problems else ""))
    elif io_problems:
        add("io", "fail", "I/O nedostupné: " + ", ".join(io_problems))
    tested, skipped, light, signal, audio = False, None, None, None, None
    if not diag.cfg.zone_test:
        skipped = "zone_test_disabled"
    elif not getattr(ctrl, "ready", False):
        skipped = "not_ready"
    elif fault:
        skipped = "fault"
    elif active:
        skipped = "session_active"
    elif not _try(zc.io_ready, False):
        skipped = "io_offline"
    elif (left := diag.time_left()) is not None and left < ZONE_TEST_BUDGET_S:
        skipped = "timeout"                # test by se do limitu běhu nevešel — raději vůbec nespínat
    else:
        aud = getattr(ctrl, "audio", None)
        speaker_busy = getattr(aud, "playing_zone", None) is not None
        res = await _hw_test(zc)
        if res is None:
            skipped = "timeout"
            add("test", "warn", f"HW test zóny nedoběhl do {int(ZONE_TEST_TIMEOUT_S)} s (pomalé moduly/Shelly) — "
                                "dokončí se na pozadí a světlo/signalizace se obnoví")
        elif res.get("error") == "busy":
            skipped = "session_active"
        else:
            tested, light, signal = True, bool(res.get("light")), bool(res.get("signal"))
            audio = None if speaker_busy else bool(res.get("audio"))
            if not light:
                what = f"relé {hw.light.dev} R{hw.light.idx + 1} nepotvrdilo sepnutí" if hw.light else "není nastaveno v HW mapě"
                add("light", "fail", f"světlo: {what}", dev=hw.light.dev if hw.light else None, ch=hw.light.idx + 1 if hw.light else None)
            if not signal:
                devs = ", ".join(sorted({r.dev for r in (hw.red, hw.green) if r is not None})) or "?"
                add("signal", "fail", f"signalizace: Shelly {devs} offline")
            if audio is False:
                sel = f"selektor {hw.audio.dev} R{hw.audio.idx + 1}" if hw.audio else "bez audio selektoru"
                player = "běží" if getattr(aud, "player_ok", False) else "neběží"
                add("audio", "fail", f"audio: tón se nepřehrál (mpv {player}, {sel})")
    shelly = await _shelly_state(ctrl, zc, add)
    return {"zone": zc.number, "label": z.display_name, "kind": z.kind, "door_id": z.door_id, "box_number": z.box_number,
            "state": state, "fault": fault, "door_closed": zc.door_closed, "session_active": active,
            "contact_raw": contact_raw, "contact_consistent": consistent, "io_problems": io_problems, "lock": lock,
            "tested": tested, "skipped_reason": skipped, "light": light, "signal": signal, "audio": audio,
            "shelly": shelly, "findings": findings, "problems": [f["message"] for f in findings]}


async def _hw_test(zc) -> dict | None:
    """`zc.test_sequence()` pod `asyncio.shield` — zrušení (limit běhu / `cancel()`) test NEPŘERUŠÍ uprostřed
    (obnova světla, signálu a zastavení tónu v `test_sequence` musí vždy doběhnout). Vlastní limit
    `ZONE_TEST_TIMEOUT_S` → None (test dobíhá na pozadí); výjimka testu → `{"error": …}`."""
    async def guarded() -> dict:
        try:
            res = await zc.test_sequence()
            return res if isinstance(res, dict) else {"error": "invalid_result"}
        except Exception as exc:  # noqa: BLE001 — chyba testu = nález zóny, ne pád kroku (a ne „exception never retrieved“)
            log.exception("Zóna %s: HW test selhal", zc.number)
            return {"error": f"{type(exc).__name__}: {str(exc)[:120]}"}

    try:
        return await asyncio.wait_for(asyncio.shield(guarded()), timeout=ZONE_TEST_TIMEOUT_S)
    except asyncio.TimeoutError:
        return None


async def _read_coils(ctrl, dev: str) -> list[bool] | None:
    try:
        return list(await ctrl.io.get(dev).read_coils())
    except Exception:  # noqa: BLE001
        return None


async def _shelly_state(ctrl, zc, add) -> dict:
    """Skutečný stav červené/zelené (`Light.GetStatus`) vs. požadovaný vzor `signals.current(zone)`."""
    hw = zc.zone.hw
    signals = ctrl.signals
    expected = getattr(_try(lambda: signals.current(zc.number)), "value", "off")
    out: dict[str, Any] = {"red": None, "green": None, "expected": expected, "matches": None}
    shellies = getattr(signals, "shellies", None) or {}
    for role in ("red", "green"):
        ref = getattr(hw, role)
        dev = shellies.get(ref.dev) if ref is not None else None
        if ref is None or dev is None:
            continue
        res = await dev.rpc("Light.GetStatus", {"id": ref.idx})
        if isinstance(res, dict):
            out[role] = {"on": bool(res.get("output")), "brightness": res.get("brightness")}
        else:
            add("shelly", "fail", f"signalizace: Shelly {ref.dev} světlo {ref.idx} ({role}) neodpovídá na Light.GetStatus")
    want = {"red": (True, False), "green": (False, True), "off": (False, False)}.get(expected)
    if want is None:
        return out                       # blikání/pulz — okamžitý stav nelze porovnat
    names = {"red": "červená", "green": "zelená"}
    ok = True
    for role, exp_on in zip(("red", "green"), want):
        st, ref = out[role], getattr(hw, role)
        if ref is None or st is None:
            if ref is not None:
                ok = None if ok is not False else ok
            continue
        if st["on"] != exp_on:
            ok = False
            add("shelly", "fail", f"{names[role]} signalizace má {'svítit' if exp_on else 'být zhasnutá'}, "
                                  f"Shelly {ref.dev} světlo {ref.idx} je {'zapnuté' if st['on'] else 'vypnuté'}")
    out["matches"] = ok
    return out


# ─── power ───────────────────────────────────────────────────────────────────
async def power(diag: "NetworkDiagnostics", report: dict) -> dict:
    url = getattr(diag.ctrl, "power_status_url", None)
    out: dict[str, Any] = {"configured": bool(url), "url": url or None, "ok": None, "status": None, "ms": None,
                           "error": None, "values": None, "raw_keys": []}
    if not url:
        return out
    t = time.monotonic()
    try:
        async with httpx.AsyncClient(timeout=float(diag.cfg.camera_timeout_s)) as c:
            r = await c.get(url)
        out.update({"status": r.status_code, "ok": r.status_code < 400})
        if r.status_code >= 400:
            out["error"] = f"HTTP {r.status_code}"
        else:
            data = r.json()
            flat: dict[str, Any] = {}
            if isinstance(data, dict):
                for k, v in data.items():
                    if isinstance(v, dict):
                        flat.update({str(kk): vv for kk, vv in v.items() if not isinstance(vv, (dict, list))})
                    elif not isinstance(v, list):
                        flat[str(k)] = v
            else:
                out.update({"ok": False, "error": "JSON není objekt"})
            out["raw_keys"] = sorted(flat)[:64]
            out["values"] = {k: next((flat[a] for a in aliases if a in flat), None) for k, aliases in POWER_KEYS.items()}
    except Exception as exc:  # noqa: BLE001 — chyba sítě/JSON = nález, ne pád kroku
        out.update({"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:120]}"})
    out["ms"] = round((time.monotonic() - t) * 1000)
    return out


# ─── cameras ─────────────────────────────────────────────────────────────────
async def cameras(diag: "NetworkDiagnostics", report: dict) -> list[dict]:
    out: list[dict] = []
    timeout = float(diag.cfg.camera_timeout_s)
    async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as c:
        for cam in diag.cameras_list()[:MAX_CAMERAS]:
            for url_kind in ("snapshot", "stream"):
                url = cam.get(f"{url_kind}_url")
                if not isinstance(url, str) or not url.lower().startswith(("http://", "https://")):
                    continue
                item = {"name": str(cam.get("name") or "?"), "kind": cam.get("kind"), "url_kind": url_kind, "url": url,
                        "ok": False, "status": None, "ms": None, "error": None, "content_type": None}
                t = time.monotonic()
                try:
                    if url_kind == "snapshot":
                        r = await c.get(url)
                        item.update({"status": r.status_code, "content_type": r.headers.get("content-type")})
                    else:
                        async with c.stream("GET", url) as r:      # tělo streamu se nečte
                            item.update({"status": r.status_code, "content_type": r.headers.get("content-type")})
                    item["ok"] = item["status"] is not None and item["status"] < 400
                    if not item["ok"]:
                        item["error"] = f"HTTP {item['status']}"
                except Exception as exc:  # noqa: BLE001
                    item["error"] = f"{type(exc).__name__}: {str(exc)[:120]}"
                item["ms"] = round((time.monotonic() - t) * 1000)
                out.append(item)
    return out

