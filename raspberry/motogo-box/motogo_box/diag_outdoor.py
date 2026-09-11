"""Venek (zóna bez dveří — venkovní osvětlení + hudba venku, kontrakt §B/§C) v kompletní
diagnostice: krok `zones` doplní `report["outdoor"]` (čtení relé světla + HW test
`OutdoorController.test_sequence()` pod stejným štítem/limitem jako zóny), krok `config` položku
`config["outdoor"]`, protokol skupinu „Venek (zóna N)“ v sekci zón a položku „Venek“ v konfiguraci,
souhrn klíč `summary.outdoor` (`ok|fail|skip|None`). Venek se NEpočítá do `zones_total/zones_ok`.

Vše přes duck typing (`getattr(ctrl, "outdoor", None)`, `hardware.outdoor`) — bez venku / bez modulu se
nic nepřidá. Světlo se NIKDY nespíná, když venku běží relace (`active`); zámek ani kontakt venek nemá.
`diag_steps` a `diag_protocol` tento modul importují lokálně (staví na jejich `_hw_test`, `item`, …).
"""
from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .diag_hints import hint
from .diag_protocol import RANK, SKIP_CZ, item
from .diag_steps import ZONE_TEST_BUDGET_S, ZONE_TEST_TIMEOUT_S, _hw_test, _read_coils, _try

if TYPE_CHECKING:  # pragma: no cover
    from .diagnostics import NetworkDiagnostics

HINT_KEYS = {"light": "outdoor_light", "audio": "outdoor_audio"}      # ostatní klíče nálezů → zone.<key>
ROLE_CZ = {"light": "venkovní světlo", "audio": "hudba venku", "io": "I/O", "test": "HW test"}
SKIP_OUTDOOR = {**SKIP_CZ, "session_active": "venku běží relace", "io_offline": "modul venkovního světla je offline",
                "not_configured": "venek není nastaven"}


def ref_str(r) -> str | None:
    """`wav617b[0]` — stejný zápis jako `OutdoorController.status()["light_ref"]`."""
    return None if r is None else f"{r.dev}[{r.idx}]"


def outdoor_cfg(ctrl):
    """`OutdoorCfg` venku: z HW mapy (`hardware.outdoor`), jinak z runtime (`ctrl.outdoor.cfg`); None = bez venku."""
    cfg = getattr(getattr(ctrl, "hardware", None), "outdoor", None)
    return cfg if cfg is not None else getattr(getattr(ctrl, "outdoor", None), "cfg", None)


# ─── krok config ─────────────────────────────────────────────────────────────
def outdoor_config(ctrl) -> dict:
    """`config["outdoor"]` = kanonický `OutdoorCfg.to_dict()` + `configured`/`present` (bez venku obojí False)."""
    cfg = outdoor_cfg(ctrl)
    d = _try(cfg.to_dict) if cfg is not None and hasattr(cfg, "to_dict") else None
    return {**(d if isinstance(d, dict) else {}), "configured": bool(getattr(cfg, "configured", False)),
            "present": bool(getattr(cfg, "present", False))}


# ─── krok zones ──────────────────────────────────────────────────────────────
async def outdoor_one(diag: "NetworkDiagnostics", report: dict) -> dict | None:
    """Když je venek nastaven: `report["outdoor"]` (a `diag._partial["outdoor"]`), jinak None a nic.
    Dict vzniká PŘED HW testem a plní se průběžně — při timeoutu kroku zůstane v reportu, co se stihlo."""
    ctrl = diag.ctrl
    o = getattr(ctrl, "outdoor", None)
    cfg = getattr(o, "cfg", None)
    if o is None or not getattr(cfg, "configured", False):
        return None
    st = _try(o.status, {}) or {}
    aud = getattr(ctrl, "audio", None)
    findings: list[dict] = []
    out: dict[str, Any] = {"zone": cfg.zone, "light": {"ref": ref_str(cfg.light), "module_online": None, "coil_on": None},
                           "audio_out": cfg.audio_out or None, "mode": getattr(aud, "mode", None), "active": bool(st.get("active")),
                           "tested": False, "skipped_reason": None, "light_ok": None, "audio_ok": None, "findings": findings, "problems": []}
    report["outdoor"] = diag._partial["outdoor"] = out

    def add(key: str, status: str, message: str, **extra: Any) -> None:
        findings.append({"key": key, "status": status, "message": message, **extra})
        out["problems"].append(message)

    light = cfg.light
    if light is not None:                                   # jen ČTENÍ relé — spíná až test_sequence (a nikdy při relaci)
        online = bool(_try(lambda: ctrl.io.is_online(light.dev), False))
        out["light"]["module_online"] = online
        if not online:
            add("io", "fail", f"venkovní světlo: modul {light.dev} offline")
        else:
            coils = await _read_coils(ctrl, light.dev)
            if coils is not None and 0 <= light.idx < len(coils):
                out["light"]["coil_on"] = bool(coils[light.idx])
    skipped = None
    if not diag.cfg.zone_test:
        skipped = "zone_test_disabled"
    elif not getattr(ctrl, "ready", False):
        skipped = "not_ready"
    elif out["active"]:
        skipped = "session_active"
    elif light is not None and not out["light"]["module_online"]:
        skipped = "io_offline"
    elif (left := diag.time_left()) is not None and left < ZONE_TEST_BUDGET_S:
        skipped = "timeout"
    else:
        res = await _hw_test(o)
        err = None if res is None else res.get("error")
        if res is None:
            skipped = "timeout"
            add("test", "warn", f"HW test venku nedoběhl do {int(ZONE_TEST_TIMEOUT_S)} s (pomalé moduly) — dokončí se na pozadí a světlo se obnoví")
        elif err in ("busy", "not_configured"):
            skipped = "session_active" if err == "busy" else err
        elif err:
            add("test", "fail", f"HW test venku selhal: {err}")
        else:
            out["tested"] = True
            out["light_ok"] = None if light is None else bool(res.get("light"))
            out["audio_ok"] = None if res.get("audio") is None else bool(res.get("audio"))
            if out["light_ok"] is False:
                add("light", "fail", f"venkovní světlo: relé {light.dev} R{light.idx + 1} nepotvrdilo sepnutí", dev=light.dev, ch=light.idx + 1)
            if out["audio_ok"] is False:
                player = "běží" if getattr(aud, "player_ok", False) else "neběží"
                add("audio", "fail", f"hudba venku: tón se nepřehrál na výstupu {cfg.audio_out} (mpv {player})")
    out["skipped_reason"] = skipped
    return out


# ─── protokol ────────────────────────────────────────────────────────────────
def _hint(f: dict) -> str:
    key = str(f.get("key") or "problem")
    return hint(HINT_KEYS.get(key, f"zone.{key}"), dev=f.get("dev") or "?", ch=f.get("ch") or "?")


def _tick(v) -> str:
    return "✔" if v else "✘" if v is False else "–"


def items(r: dict) -> list[dict]:
    """Skupina do sekce zón: `outdoor` (group) + `outdoor.light` + `outdoor.audio`; report bez venku → []."""
    o = r.get("outdoor")
    if not isinstance(o, dict):
        return []
    f, lt, skip = o.get("findings") or [], o.get("light") or {}, o.get("skipped_reason")
    label = f"Venek (zóna {o.get('zone')})" if o.get("zone") is not None else "Venek"
    worst = max((RANK.get(x.get("status"), 0) for x in f), default=0)
    st = {3: "fail", 2: "warn"}.get(worst) or ("skip" if skip else "ok")
    coil = {True: "svítí", False: "zhasnuté"}.get(lt.get("coil_on"), "?")
    val = (f"světlo {lt.get('ref')} {coil}" if lt.get("ref") else "bez světla") + (", relace" if o.get("active") else "") \
        + (f", test: světlo {_tick(o.get('light_ok'))} hudba {_tick(o.get('audio_ok'))}" if o.get("tested") else "")
    msg = f"{len(f)} nálezů: " + ", ".join(dict.fromkeys(ROLE_CZ.get(x.get("key"), str(x.get("key"))) for x in f)) if f else \
        f"Test přeskočen: {SKIP_OUTDOOR.get(skip, skip)}." if skip else "Vše v pořádku."
    it = [{**item("outdoor", label, st, val, msg, _hint(f[0]) if f else None), "group": True}]
    skip_msg = f"Test přeskočen: {SKIP_OUTDOOR.get(skip, skip)}." if skip else "Test neproběhl."
    # světlo: nálezy světla/I/O/testu; bez relé v mapě = skip
    lf = [x for x in f if x.get("key") != "audio"]
    if not lt.get("ref"):
        it.append(item("outdoor.light", f"{label} — venkovní světlo", "skip", None, "Venkovní světlo není v HW mapě (jen hudba venku)."))
    elif lf:
        it.append(item("outdoor.light", f"{label} — venkovní světlo", lf[0].get("status") or "warn", None, "; ".join(str(x.get("message") or "") for x in lf), _hint(lf[0])))
    elif o.get("tested"):
        it.append(item("outdoor.light", f"{label} — venkovní světlo", "ok", f"relé {lt.get('ref')} sepnulo a obnovilo se"))
    else:
        it.append(item("outdoor.light", f"{label} — venkovní světlo", "skip", None, skip_msg))
    # hudba: jen multi; selektor / bez výstupu / hraje = skip
    af = [x for x in f if x.get("key") == "audio"]
    if not o.get("audio_out"):
        it.append(item("outdoor.audio", f"{label} — hudba venku", "skip", None, "Hudba venku není nastavena (audio výstup venku)."))
    elif o.get("mode") == "selector":
        it.append(item("outdoor.audio", f"{label} — hudba venku", "skip", o.get("audio_out"), "Venek hraje jen v režimu multi (audio selektor tón venku nepřehraje)."))
    elif af:
        it.append(item("outdoor.audio", f"{label} — hudba venku", af[0].get("status") or "warn", None, str(af[0].get("message") or ""), _hint(af[0])))
    elif o.get("tested"):
        ok = o.get("audio_ok")
        it.append(item("outdoor.audio", f"{label} — hudba venku", "ok" if ok else "skip", o.get("audio_out"),
                       "" if ok else "Hudba venku právě hraje — tón se netestoval."))
    else:
        it.append(item("outdoor.audio", f"{label} — hudba venku", "skip", o.get("audio_out"), skip_msg))
    return it


def config_item(c: dict) -> dict | None:
    """Položka „Venek“ sekce konfigurace; starší report bez `config.outdoor` → None (bez položky)."""
    o = c.get("outdoor")
    if not isinstance(o, dict):
        return None
    if not o.get("configured"):
        if not o.get("present"):
            return item("config.outdoor", "Venek", "skip", None, "Venek není nastaven (zóna bez dveří: venkovní světlo + hudba venku).")
        return item("config.outdoor", "Venek", "warn", None, "Venek je v HW mapě, ale nemá světlo ani audio výstup.", hint("outdoor_config"))
    lt, au = o.get("light") or {}, o.get("audio") or {}
    parts = [f"zóna {o.get('zone')}" if o.get("zone") is not None else "bez čísla zóny"]
    if lt.get("dev") is not None:
        parts.append(f"světlo {lt.get('dev')} R{int(lt.get('coil') or 0) + 1}")
    if au.get("out"):
        parts.append(f"audio {au.get('out')}" + (f" (relé {au.get('dev')} R{int(au.get('coil') or 0) + 1})" if au.get("dev") is not None else ""))
    if o.get("light_after_close_s") is not None:
        parts.append(f"doběh světla {o.get('light_after_close_s')} s")
    return item("config.outdoor", "Venek", "ok", " — ".join(parts[:1] + [", ".join(parts[1:])]) if len(parts) > 1 else parts[0])


def summary(r: dict) -> str | None:
    """`summary.outdoor`: None = report bez venku; fail = nález fail; ok = otestováno bez chyb; skip = jen čtení."""
    o = r.get("outdoor")
    if not isinstance(o, dict):
        return None
    if any(f.get("status") == "fail" for f in o.get("findings") or []):
        return "fail"
    return "ok" if o.get("tested") else "skip"
