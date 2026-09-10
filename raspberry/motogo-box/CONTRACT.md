# MotoGo Box (Raspberry Pi 5) — kontrakt modulů

Tento dokument je závazné rozhraní mezi moduly programu `motogo_box`. Každý modul
se implementuje PŘESNĚ podle signatur níže (názvy, parametry, návratové typy),
aby šly moduly psát nezávisle a integrovat bez úprav. Sdílené typy jsou v
`motogo_box/models.py`, konfigurace v `motogo_box/config.py` (oba už existují —
NEMĚNIT, jen používat).

Zdroj požadavků: uživatelská specifikace „Implementační specifikace řídicího
systému – 9zónový MotoGo box" (§1–§13) + existující kiosk backend Supabase
(tabulky `branch_kiosk_config`, `kiosk_devices`, `branch_doors`,
`branch_service_codes`, `kiosk_commands`, `branch_door_events`, `kiosk_logs`,
RPC `kiosk_*`). Logika/flow zůstává z tabletového kiosku
(`Motogo-app-main/motogo-locker-kiosk`), mění se jen hardwarová vrstva.

Konvence: Python 3.11, `asyncio`, typové anotace, docstringy česky, identifikátory
anglicky. Žádný modul nesmí přesáhnout ~350 řádků (rozděl do více souborů).
Závislosti: `httpx`, `aiohttp`, `pyyaml`, `websockets` (viz `requirements.txt`).
Logování přes `logging.getLogger("motogo.<modul>")`.

---

## 0. Přehled procesů

| systemd unit | proces | obsah |
|---|---|---|
| `motogo-controller.service` | `python -m motogo_box controller` | Modbus I/O, Shelly signalizace, audio, stavové automaty zón, Supabase sync, lokální HTTP/WS server pro UI, vzdálené příkazy, status report, systemd watchdog |
| `motogo-health.service` | `python -m motogo_box health` | LTE watchdog (ModemManager/NetworkManager), USB reset modemu, reboot policy, teploty/disk/throttling → `POST http://127.0.0.1:8080/api/health` |
| `motogo-ui.service` | `cage -- chromium --kiosk http://127.0.0.1:8080/` | Dotykové UI na EDATEC (1920×1080) |

`python -m motogo_box simulate` spustí lokální simulátor hardwaru (vývoj/testy).

---

## 1. `models.py` (HOTOVO — jen používat)

Enumy `ZoneState`, `Signal`, `EventKind`; dataclassy `HwRef`, `ZoneHw`, `Zone`,
`ZoneStatus`, `ResolveResult`, `Event`, `ServiceDoor`. Viz soubor.

## 2. `config.py` (HOTOVO — jen používat)

- `load_local(path: str | None = None) -> LocalConfig` — `/etc/motogo/config.yaml`
  (nebo env `MOTOGO_CONFIG`); env override `MOTOGO_DEVICE_ID`, `MOTOGO_DEVICE_TOKEN`.
- `load_hardware_file(path) -> dict` — výchozí HW mapa (`config/brno-9zone.yaml`).
- `merge_hardware(local: dict, remote: dict | None) -> dict` — remote (Velín
  `branch_kiosk_config.hardware`) přepisuje lokální po top-level klíčích
  (`devices`, `timings`, `polling`, `contacts`, `security`, `audio`, `signal`);
  klíč `zones` remote NIKDY nenese (zóny = `branch_doors.hw`).
- `HardwareConfig.from_dict(d: dict, doors: list[dict] | None = None) -> HardwareConfig`
  — zóny se berou z `doors` (řádky `branch_doors` s neprázdným `hw`); pokud žádné,
  z lokálního `d["zones"]` (door_id=None, box_number=zone).
- `validate_hardware(hw: HardwareConfig) -> list[str]` — seznam problémů (prázdný = OK).

## 3. `modbus.py` — raw Modbus TCP klient (bez pymodbus)

```python
class ModbusError(Exception): ...

class ModbusTcpClient:
    def __init__(self, host: str, port: int = 502, unit_id: int = 1, *,
                 timeout_ms: int = 500, retry_delays_ms: Sequence[int] = (100, 250, 500),
                 offline_after: int = 3, name: str = "") -> None
    name: str
    online: bool                      # False po `offline_after` po sobě jdoucích neúspěšných requestech
    failures: int                     # po sobě jdoucí neúspěchy
    on_online_change: Callable[[str, bool], None] | None
    async def connect(self) -> None   # idempotentní, chybu spolkne (online se řeší při requestu)
    async def close(self) -> None
    async def request(self, pdu: bytes) -> bytes
        # MBAP (transaction id++, protocol 0, length, unit) + PDU; jeden request
        # v letu (asyncio.Lock); při timeoutu/chybě spojení reconnect + retry dle
        # retry_delays_ms; exception response (fc | 0x80) → ModbusError okamžitě
        # (bez retry). Vrací PDU odpovědi (bez MBAP). Po vyčerpání retry → ModbusError.
    async def read_coils(self, addr: int, count: int) -> list[bool]            # FC01
    async def read_discrete_inputs(self, addr: int, count: int) -> list[bool]  # FC02
    async def read_holding_registers(self, addr: int, count: int) -> list[int] # FC03
    async def write_coil(self, addr: int, on: bool) -> None                    # FC05 0xFF00/0x0000
    async def write_coil_raw(self, addr: int, value: int) -> None              # FC05 s libovolnou 16bit hodnotou (flash-on)
    async def write_register(self, addr: int, value: int) -> None              # FC06
```
Pomocné čisté funkce (testovatelné bez sítě): `build_mbap(tid, unit, pdu) -> bytes`,
`parse_response(frame: bytes, expect_tid: int) -> bytes`, `bits_from_bytes(data, count) -> list[bool]`.

## 4. `io_devices.py` — Waveshare moduly nad Modbus

```python
class RelayModule:
    name: str; client: ModbusTcpClient; coils: int; inputs: int
    online -> bool (property, = client.online)
    async def start(self) -> None                 # connect + (WAV617) set_normal_mode
    async def read_coils(self) -> list[bool]
    async def set_coil(self, idx: int, on: bool) -> bool   # zapíše a OVĚŘÍ čtením (§12: příkaz vždy ověřit); vrací skutečný stav == on
    async def all_off(self) -> bool                # FC05 na 0x00FF hodnota 0x0000, poté ověří read_coils == all False; při neúspěchu zkusí coil po coilu
    async def pulse(self, idx: int, ms: int) -> bool
        # WAV645: hardware flash-on: write_coil_raw(0x0200 + idx, max(1, round(ms/100))) (jednotka 100 ms),
        #         poté ověří, že relé je sepnuté (read_coils) — bez čekání na vypnutí.
        # WAV617: software: set_coil(idx, True); sleep(ms); set_coil(idx, False) v try/finally.
    async def read_inputs(self) -> list[bool]     # FC02 0x0000..; RelayModule bez vstupů vrací []

class Wav645(RelayModule): coils=16, inputs=0, HW_FLASH=True
class Wav617(RelayModule): coils=8, inputs=8, HW_FLASH=False
    async def set_normal_mode(self) -> bool       # FC06 0x1000+r = 0 pro r∈0..7, ověří FC03 0x1000 x8 == [0]*8

def make_module(name: str, dev: DeviceCfg, polling: PollingCfg) -> RelayModule   # dle dev.type ('wav645'|'wav617')

class IoBus:
    def __init__(self, hw: HardwareConfig) -> None       # vytvoří moduly pro devices typu wav645/wav617
    modules: dict[str, RelayModule]
    async def start(self) -> None                        # start všech modulů (chyby loguje, nepadá)
    async def stop(self) -> None
    def is_online(self, name: str) -> bool               # neznámé jméno → False
    def get(self, name: str) -> RelayModule              # KeyError při neznámém
    async def all_off(self) -> dict[str, bool]           # all_off na všech modulech (výsledek per modul)
    async def set(self, ref: HwRef, on: bool) -> bool    # set_coil dle ref.dev/ref.idx; offline/chyba → False
    async def pulse(self, ref: HwRef, ms: int) -> bool
    async def read_all_inputs(self) -> dict[str, list[bool] | None]   # None = modul offline / chyba
    def input_value(self, snapshot: dict[str, list[bool] | None], ref: HwRef) -> bool | None
```

## 5. `shelly.py` — Shelly Pro RGBWW PM (Lights ×5) + signalizace

```python
class ShellyRgbww:
    def __init__(self, name: str, host: str, *, timeout_s: float = 2.0, offline_after: int = 3) -> None
    online: bool
    async def light_set(self, light_id: int, on: bool, brightness: int | None = None,
                        transition_s: float | None = None) -> bool
        # POST http://<host>/rpc  {"id":1,"method":"Light.Set","params":{"id":light_id,"on":on,"brightness":..,"transition_duration":..}}
    async def all_off(self) -> bool                 # Light.Set off pro id 0..4
    async def close(self) -> None

class SignalController:
    def __init__(self, shellies: dict[str, ShellyRgbww], cfg: SignalCfg) -> None
    def current(self, zone: int) -> Signal          # poslední požadovaný stav (default OFF)
    async def set(self, zone_hw: ZoneHw, signal: Signal) -> None
        # zruší běžící blink/pulse task zóny a nastaví vzor:
        #  RED: red on 100 / green off; GREEN: green on 100 / red off; OFF: obojí off;
        #  GREEN_PULSE: red off, green střídá brightness 15↔100 s transition cfg.pulse_ms (loop task);
        #  RED_BLINK: green off, red on/off každých cfg.blink_ms; BOTH_BLINK: obě on/off každých cfg.blink_ms.
        # Chybějící ref (None) přeskočí. Chyby HTTP loguje, nevyhazuje.
    async def all_off(self) -> None                 # zruší tasky, all_off na všech Shelly
    async def close(self) -> None
    def online(self, name: str) -> bool
```

## 6. `audio.py` — mpv + reléový selektor reproduktorů

```python
class MpvPlayer:
    def __init__(self, socket_path: str, music_dir: str, device: str | None = None) -> None
    async def start(self) -> None        # spawn: mpv --idle=yes --no-video --no-terminal --input-ipc-server=<sock> --volume=0 --loop-playlist=inf [--audio-device=<device>] ; čeká na socket
    async def stop(self) -> None         # ukončí proces
    async def command(self, *args) -> Any            # JSON IPC {"command":[...]}
    async def load_playlist(self, shuffle: bool = True) -> int   # loadfile pro soubory (mp3/ogg/flac/wav) v music_dir; vrací počet
    async def play(self) -> None ; async def pause(self) -> None
    async def set_volume(self, vol: int) -> None
    async def fade(self, to: int, ms: int, steps: int = 10) -> None
    alive -> bool

class AudioSelector:
    def __init__(self, bus: IoBus, zones: list[Zone], cfg: AudioCfg) -> None
    active_zone: int | None
    async def select(self, zone: int) -> bool
        # §8: (1) volající ztlumil; (2) VŠECHNA audio relé všech zón off (ověřeno); (3) sleep cfg.selector_settle_ms;
        # (4) set audio coil zóny on (ověřeno, jinak False + vše off); (5) sleep cfg.selector_on_ms. Nikdy ne 2 relé současně.
    async def release(self) -> None      # všechna audio relé off, active_zone=None

class AudioController:
    def __init__(self, player: MpvPlayer, selector: AudioSelector, cfg: AudioCfg) -> None
    playing_zone: int | None
    async def start(self) -> None ; async def close(self) -> None
    async def play_zone(self, zone: int) -> bool
        # asyncio.Lock; pokud hraje jiná zóna → stop(fade) ; pak selector.select, play, fade-in na cfg.volume
    async def stop(self, fade: bool = True) -> None   # fade-out cfg.fade_out_ms → pause → sleep settle → selector.release
    async def all_off(self) -> None                   # bez fade: pause, volume 0, release
    async def test_tone(self, zone: int, seconds: int = 5) -> bool   # play_zone, sleep, stop
```

## 7. `storage.py` — SQLite (`<data_dir>/motogo.db`), synchronní `sqlite3`

```python
class Storage:
    def __init__(self, path: str) -> None       # vytvoří schéma (kv, code_cache, outbox, pin_attempts, events)
    def kv_get(self, key: str, default: Any = None) -> Any ; def kv_set(self, key: str, value: Any) -> None   # JSON
    def save_code_cache(self, payload: dict) -> None ; def load_code_cache(self) -> dict | None
    def outbox_add(self, kind: str, payload: dict) -> int
    def outbox_pending(self, limit: int = 50) -> list[tuple[int, str, dict]]
    def outbox_done(self, oid: int) -> None ; def outbox_fail(self, oid: int) -> None   # attempts+1; >50 pokusů → smaž
    def pin_attempt(self, ok: bool, masked: str) -> None
    def pin_failures_since(self, since_ts: float) -> int
    def lockout_until(self) -> float | None ; def set_lockout_until(self, ts: float | None) -> None
    def event_add(self, event: Event) -> None       # ring buffer max 5000
    def events_recent(self, limit: int = 100) -> list[dict]
    def close(self) -> None
```

## 8. `pins.py`

```python
PIN_RE = re.compile(r"^\d{6}$")
def normalize_code(text: str) -> str            # strip, bez mezer
def is_pin(code: str) -> bool                   # přesně 6 číslic
def mask(code: str) -> str                      # "12••••"
def hmac_code(device_id: str, device_token: str, code: str) -> str
    # hmac.new(device_token.lower().encode(), f"{device_id.lower()}:{code}".encode(), "sha256").hexdigest()  — MUSÍ odpovídat SQL v kiosk_sync_config
class PinGuard:
    def __init__(self, storage: Storage, sec: SecurityCfg, clock: Callable[[], float] = time.time) -> None
    def locked_until(self) -> float | None       # None = neuzamčeno
    def register_failure(self, masked: str) -> float | None   # vrací lockout_until pokud právě uzamklo
    def register_success(self, masked: str) -> None
class LocalResolver:
    """Offline ověření proti cache z kiosk_sync_config (hashe) nebo kiosk_sync_codes (plaintext, legacy)."""
    def __init__(self, device_id: str, device_token: str) -> None
    def resolve(self, code: str, cache: dict | None, now: datetime) -> ResolveResult | None
```

## 9. `supabase_api.py` — PostgREST RPC (anon klíč, auth zařízení = device_id+token)

```python
class ApiError(Exception): ...
class SupabaseApi:
    def __init__(self, url: str, anon_key: str, device_id: str, device_token: str,
                 storage: Storage, version: str) -> None
    online: bool                                  # výsledek posledního volání
    def set_device(self, device_id: str, device_token: str) -> None
    async def rpc(self, name: str, params: dict, timeout_s: float = 10) -> Any
        # POST {url}/rest/v1/rpc/{name}; headers apikey, Authorization: Bearer <anon>, Content-Type: application/json
        # HTTP != 2xx → ApiError(status, text). Síťová chyba → ApiError. Nastaví online.
    async def heartbeat(self) -> dict | None      # kiosk_heartbeat(p_app_version=version, p_platform='rpi'); None při chybě/unauthorized
    async def resolve_code(self, code: str) -> dict | None    # kiosk_resolve_code; None JEN při síťové chybě (ok:false vrací dict)
    async def sync_config(self) -> dict | None    # kiosk_sync_config (nová RPC); při 404 (RPC ještě není) → fallback kiosk_sync_codes a označí payload["legacy"]=True
    async def log_open(self, door_id, kind, booking_id, success, detail) -> None      # při chybě → outbox('log_open')
    async def log_event(self, level, source, message, detail=None) -> None           # při chybě → outbox('log_event')
    async def fetch_commands(self) -> list[dict]
    async def complete_command(self, command_id: str, success: bool, result: dict) -> None   # při chybě → outbox
    async def report_status(self, status: dict) -> None      # kiosk_report_status (nová RPC); 404 ignoruj
    async def report_power(self, payload: dict) -> None
    async def flush_outbox(self) -> int                       # odešle čekající; vrací počet odeslaných
    async def validate_pairing(self, device_id: str, token: str) -> str | None   # None = OK, jinak text chyby
    async def close(self) -> None
```

## 10. `realtime.py`

```python
class RealtimeListener:
    def __init__(self, url: str, anon_key: str, topic: str, on_wake: Callable[[], Awaitable[None]]) -> None
        # topic = f"kiosk:{device_id}" → phoenix topic f"realtime:{topic}"
    async def run(self) -> None      # nekonečná smyčka s reconnectem (backoff 5→60 s); wss://<host>/realtime/v1/websocket?apikey=<anon>&vsn=1.0.0
        # join: {"topic":"realtime:kiosk:<id>","event":"phx_join","payload":{"config":{"broadcast":{"self":false},"presence":{"key":""},"postgres_changes":[]}},"ref":"1"}
        # heartbeat každých 25 s: {"topic":"phoenix","event":"heartbeat","payload":{},"ref":...}
        # zpráva event=="broadcast" && payload.event=="cmd" → await on_wake()
    def stop(self) -> None
    connected: bool
```

## 11. `zone.py` — stavový automat jedné zóny (§9, §12)

```python
EventSink = Callable[[Event], Awaitable[None]]
class ZoneController:
    def __init__(self, zone: Zone, io: IoBus, signals: SignalController, audio: AudioController,
                 hw: HardwareConfig, emit: EventSink, clock: Callable[[], float] = time.monotonic) -> None
    zone: Zone ; state: ZoneState ; fault: str | None ; door_closed: bool | None ; booking_id: str | None
    light_on: bool ; session_started: float | None ; overtime: bool
    def status(self) -> ZoneStatus
    def io_ready(self) -> bool
        # online: wav645 (lock dev), modul kontaktu, modul světla; Shelly červené/zelené (pokud definované)
    async def startup(self, door_closed: bool | None) -> None
        # §12 kroky 6–7: zavřené+funkční → SECURED + RED; None → FAULT 'io_offline' + BOTH_BLINK; otevřené → FAULT 'open_at_startup' + RED_BLINK (event CONTACT_FAULT/FORCED_OPEN)
    async def on_input(self, door_closed: bool | None) -> None
        # volá poller po sw debounce (cfg.polling.software_debounce_ms). Přechody:
        #  SECURED + otevřeno (stabilní ≥ forced_open_debounce_ms) → FAULT 'forced_open', RED_BLINK, event FORCED_OPEN (success False)
        #    VÝJIMKA (paměťový zámek IBFM 9500): po OPEN_TIMEOUT zůstává zámek mechanicky odjištěný do prvního otevření
        #    (`latch_released=True`) → pozdní otevření = pokračování relace (`_late_open_locked`: obnoví booking, DOOR_OPEN,
        #    světlo, GREEN, hudba, event DOOR_OPENED late_open=True warn), NE forced_open. Latch se maže při dalším grantu/otevření.
        #  FAULT 'forced_open'/'open_at_startup' + zavřeno → SECURED, RED, event DOOR_CLOSED
        #  WAITING_FOR_OPEN + otevřeno → DOOR_OPEN, event DOOR_OPENED (zámek už bez napětí — pulz byl HW)
        #  DOOR_OPEN + zavřeno stabilně ≥ door_close_debounce_ms → CLOSED_CONFIRMATION, RED, event DOOR_CLOSED (+ SESSION_COMPLETED)
        #  CLOSED_CONFIRMATION + otevřeno → zpět DOOR_OPEN (stejná relace)
        #  None (modul kontaktu offline) v jakémkoli stavu → FAULT 'io_offline', BOTH_BLINK, hudba stop, event IO_OFFLINE; návrat hodnoty → startup(door_closed)
        #  jiný modul offline (zámek/světlo/Shelly) během aktivní relace (WAITING/DOOR_OPEN/CLOSED_CONF) → relace pokračuje
        #    v režimu `degraded=True` (nový přístup zamítnut io_ready=False); io_offline až po skončení relace (evaluate po SECURED)
    async def grant_access(self, *, booking_id: str | None, kind: str, source: str) -> tuple[bool, str]
        # §9 „Platný PIN" kroky 4–12: io_ready? ne → (False,'io_offline'); state ∉ {SECURED, CLOSED_CONFIRMATION} → (False,'busy'/'door_open');
        # door_closed is not True → (False,'door_open'); reset_session (ukončí doběh); světlo ON (ověřeno); GREEN; audio.play_zone; io.pulse(lock, lock_pulse_ms, retry=False)
        # — gate drží max(pulse, zaokrouhlení na kroky 100 ms WAV645); neúspěch → světlo/zelená zpět, (False,'lock_failed'); po pomalých krocích znovu kontrola dveří/modulů;
        # event ACCESS_GRANTED (booking_id, kind, source); state WAITING_FOR_OPEN; návrat (True,'ok')
    async def tick(self) -> None
        # WAITING_FOR_OPEN: > door_open_timeout_s → hudba stop, světlo off, RED, SECURED, event OPEN_TIMEOUT; latch_released=True + _late_booking (viz pozdní otevření)
        # DOOR_OPEN: > maximum_session_s a not overtime → overtime=True, hudba stop, GREEN_PULSE, event SESSION_OVERTIME (warn); dále každých overtime_alert_minutes → event SESSION_OVERTIME_ALERT
        # CLOSED_CONFIRMATION: po music_after_close_s hudba stop; po light_after_close_s světlo off → SECURED (RED už svítí) → evaluate (degraded → io_offline)
    async def force_secure(self) -> None      # all_off pro zónu: hudba stop (pokud hraje tato zóna), světlo off, RED (nebo RED_BLINK při faultu), state dle door_closed
    async def set_light(self, on: bool) -> bool
    async def set_signal(self, signal: Signal) -> None      # ruční override (Velín)
    async def test_sequence(self) -> dict     # BEZ zámku: světlo on → GREEN 1 s → obnoví předchozí signál/světlo; audio test 3 s jen když nic nehraje;
                                              # vrací {light:bool, signal:bool, audio:bool|None}; při aktivní relaci {'error':'busy'} (nic nesepne)
```
Pravidla: nikdy nesepnout zámek mimo `grant_access`; zámek jen HW pulz; hudbu ovládat výhradně přes `audio` (exkluzivita).

**Souběh více zón (rozhodnutí uživatele, SPEC §13.7 = ANO):** každá zóna má nezávislou relaci, víc
kójí smí být otevřených současně. Povinné zábrany: (a) `BoxController.lock_gate: asyncio.Lock` —
`grant_access` drží gate po dobu pulzu zámku (`await io.pulse(...)` + `asyncio.sleep(lock_pulse_ms/1000)`
uvnitř gate), takže dva zámky nikdy nemají impulz zároveň; (b) audio: `audio.play_zone(new)` u nové
relace převezme reproduktor (stará zóna přestane hrát, její stav zůstává DOOR_OPEN); zóna volá
`audio.stop()` jen pokud `audio.playing_zone == zone.number` (viz výše) — hudba se do dřívější kóje
nevrací; (c) světla/signalizace per zóna bez omezení. `audio.stop_zone(zone)` je atomické (pod zámkem přehrávače)
— zastaví jen pokud stále hraje daná zóna, takže doběh staré relace nikdy neutne hudbu nové.

## 12. `controller.py` — `BoxController`

```python
class BoxController:
    def __init__(self, local: LocalConfig, storage: Storage, api: SupabaseApi, version: str) -> None
    ready: bool ; branch_name: str | None ; hardware: HardwareConfig ; zones: dict[int, ZoneController]
    io: IoBus ; signals: SignalController ; audio: AudioController ; health: dict ; last_error: str | None
    ui_notice: dict | None                     # {"title","subtitle","kind","ts"} pro UI (identify apod.)
    async def start(self) -> None
        # 1) načti HW: local hardware_file + storage.kv 'remote_config' (poslední sync) → HardwareConfig
        # 2) vytvoř IoBus/Signal/Audio/zóny; 3) §12 startup: io.start → io.all_off → signals.all_off → audio.all_off
        #    → read_all_inputs → zone.startup(...) pro každou; 4) ready=True; 5) spusť tasky:
        #    poll_loop (io_poll_ms, sw debounce, zone.on_input), tick_loop (250 ms), heartbeat_loop (intervals.heartbeat_s),
        #    sync_loop (intervals.sync_s), command_loop (intervals.command_poll_s + wake z realtime), status_loop
        #    (intervals.status_report_s), outbox_loop (60 s), realtime listener, power_loop (pokud power_status_url), watchdog (sdnotify)
    async def stop(self) -> None               # zruš tasky, audio.all_off, io.all_off, signals: zavřené zóny RED, ostatní off
    async def submit_code(self, code: str, source: str = "ui") -> dict
        # {"ok":bool,"kind":"motorcycle|accessories|service|invalid","error":str|None,"message":str,"zone":int|None,
        #  "locked_until":float|None,"doors":[ServiceDoor…] (jen service), "service_token":str|None}
        # kroky: normalize; PinGuard.locked → error 'locked'; 6 číslic nebo neprázdné (servisní heslo) ; api.resolve_code →
        # None (síť) → LocalResolver; invalid → register_failure; service → vydej service_token (10 min);
        # zákazník → najdi zónu (door_id, pak box_number) → zone.grant_access; log_open(...)
    def check_service_token(self, token: str | None) -> bool
    async def service_open(self, door_id: str | None, zone: int | None) -> dict     # grant_access(kind='service', source='service_panel')
    async def handle_command(self, cmd: dict) -> None    # → commands.execute → api.complete_command
    async def resync(self) -> dict          # api.sync_config → uložit kv 'remote_config' + code cache; při změně devices/zones → rebuild (all_off + nové zóny) ; vrací {changed:bool, problems:[…]}
    def snapshot(self) -> dict              # viz §14 payload statusu (pro UI i kiosk_report_status)
    async def all_off(self) -> None         # audio.all_off, io.all_off (vše), signals.all_off, zóny force_secure
    async def emit(self, event: Event) -> None   # storage.event_add + log_open/log_event dle druhu (viz §15) + UI
    def find_zone(self, *, door_id: str | None = None, zone: int | None = None, box_number: int | None = None) -> ZoneController | None
```

## 13. `commands.py`

```python
async def execute(ctrl: BoxController, command: str, params: dict) -> tuple[bool, dict]
```
| command | params | akce |
|---|---|---|
| `open_door` | `door_id` / `zone` / `box_number` (+ ignoruje `relay_url`,`light_url`) | plná přístupová sekvence zóny (`grant_access(kind='service', source='velin')`) |
| `music_on` | `zone?` | `audio.play_zone(zone or první zóna)` |
| `music_off` | – | `audio.stop()` |
| `light_on` / `light_off` | `zone`/`door_id` | `zone.set_light` |
| `set_signal` | `zone`, `signal` (red/green/off/green_pulse/red_blink/both_blink) | `zone.set_signal` |
| `zone_test` | `zone` | `zone.test_sequence()` |
| `audio_test` | `zone`, `seconds?` | `audio.test_tone` |
| `all_off` | – | `ctrl.all_off()` |
| `identify` | `label?` | ui_notice „Tady jsem" + 3× bliknutí zelené všech zón, pak obnovit |
| `reload` / `sync_config` | – | `ctrl.resync()` → `{ok, error?, deferred?}`; při aktivní relaci se přestavba zón odloží (config se stáhne, zóny až po SECURED) |
| `restart` | – | complete_command PŘED ukončením, pak `os._exit(0)` (systemd restartuje) |
| `reboot` | – | complete, pak `sudo systemctl reboot`; selhání sudo → `log_event` (Velín vidí důvod). `restart`/`reboot` = `TERMINAL_COMMANDS` (dokončí se před ukončením procesu) |
| `update_software` | – | `sudo /usr/local/sbin/motogo-update` (root-owned kopie `scripts/update.sh`: git pull --ff-only jako vlastník checkoutu, pip v rozsazích requirements, restart; chyba pullu → exit 3, nic se neinstaluje) |
| `http_get` / `camera_control` | `url` | httpx GET (timeout 6 s) |
| `diagnostics` | `reason?` | `ctrl.diagnostics.start(source='velin')` — běží na pozadí (§24), `{ok, started, id}` / `already_running`; není HW příkaz (funguje i při `not ready`) |

Příkazy `pending` nevyzvednuté do 10 min označí `kiosk_fetch_commands` jako `expired` (`20260910b_kiosk_commands_ttl.sql`) — Velín tak nečeká věčně na offline jednotku.
Neznámý příkaz → `(False, {"error":"unknown_command"})`.

## 14. Status payload (`BoxController.snapshot()` = UI state = `kiosk_report_status`)

```json
{"ts":"2026-09-09T10:00:00+02:00","version":"1.0.0+abc123","uptime_s":123,"ready":true,"branch_name":"Brno",
 "internet":true,"config_source":"remote|local","config_problems":[],
 "modules":{"wav645":true,"wav617a":true,"wav617b":true,"shelly1":true,"shelly2":true,"shelly3":true,"shelly4":true},
 "audio":{"playing_zone":null,"player_ok":true,"playlist_count":12,"device":"alsa/plughw:CARD=Headphones"},
 "diagnostics":{"running":false,"last":{"id":"…","ok":true,"problems":0,"ts":"…"}},
 "health":{"lte":{"state":"connected","operator":"T-Mobile CZ","rssi":-71,"rsrp":-98,"reconnects":0,"usb_resets":0},
           "sys":{"cpu_temp":48.2,"throttled":"0x0","disk_free_pct":81,"mem_free_pct":60,"load1":0.3,"uptime_s":9999},"internet":true,"ts":"…"},
 "zones":[{"zone":1,"door_id":"uuid|null","box_number":1,"kind":"motorcycle","label":"Kóje 1","state":"SECURED",
           "door_closed":true,"fault":null,"light":false,"signal":"red","music":false,"latch_released":false,"degraded":false,
           "session_started_at":null,"booking_id":null,"last_event":"DOOR_CLOSED"}],
 "notice":null}
```

Hodnoty `state` = `ZoneState.value` (velká písmena), `signal` = `Signal.value` (malá písmena: red, green, green_pulse, red_blink, both_blink, off).

## 15. Události → Supabase

`kiosk_log_open(door_id, kind, booking_id, success, detail)` pro: ACCESS_GRANTED,
DOOR_OPENED, DOOR_CLOSED, SESSION_COMPLETED, OPEN_TIMEOUT, FORCED_OPEN (success=false),
PIN_INVALID (kind='invalid', success=false, detail.code_masked). `detail` vždy
`{"event":<EventKind>, "zone":n, "box_number":.., "source":..}` + extra.
`kiosk_log_event(level, source, message, detail)` pro: IO_OFFLINE/IO_ONLINE (warn/info,
source 'modbus'|'shelly'), SESSION_OVERTIME(+ALERT) (warn 'zone'), CONTACT_FAULT (error),
PIN_LOCKOUT (warn 'pin'), STARTUP (info 'controller', verze + problémy konfigurace),
LTE_RESET/REBOOT (warn 'lte', posílá health přes controller), CONFIG_PROBLEM (error 'config').

## 16. `webserver.py` + `ui/`

aiohttp na `local.web.host:port` (default 127.0.0.1:8080):
- `GET /` → `ui/index.html`; `GET /static/{file}` → `ui/`.
- `GET /api/state` → `ctrl.snapshot()`.
- `WS /ws` → po připojení a poté každou 1 s (nebo při změně) pošle `{"type":"state","state":<snapshot>}`.
- `POST /api/pin {"code"}` → `ctrl.submit_code(code, "ui")`.
- `POST /api/service/open {"service_token","door_id"|"zone"}` → `ctrl.service_open`.
- `POST /api/service/music {"service_token","zone","on":bool}`.
- `POST /api/service/light {"service_token","zone","on":bool}`.
- `POST /api/service/all_off {"service_token"}`.
- `POST /api/service/pair {"device_id","device_token"}` → `api.validate_pairing`; OK → `storage.kv_set('device_id'/'device_token')`, `api.set_device`, `ctrl.resync()`; bez tokenu povoleno JEN když zařízení není spárované.
- `POST /api/service/restart {"service_token"}` → `os._exit(0)`.
- `POST /api/health {…}` (jen 127.0.0.1) → `ctrl.health = payload`.
- `GET /api/events?limit=` → `storage.events_recent`.
- `GET /api/diagnostics[?report=0]` (jen 127.0.0.1) → `{ok, status: diagnostics.status(), report: poslední report|null}`.
- `POST /api/diagnostics/run {"service_token"} | {"code"}` → spustí diagnostiku (§24); `code` jde přes
  `ctrl.submit_code(code, "diag_ui", diagnostics_only=True)`: lokální diagnostický kód, servisní heslo
  s účelem `diagnostics` nebo běžné servisní heslo (spustí JEN diagnostiku, bez servisního tokenu);
  zákaznický PIN/kód rezervace je tu `invalid_code` a počítá se do lockoutu; neplatný → 403
  `{ok:false, error, message, locked_until}`. Lockout blokuje i diagnostický kód (kromě `/api/diagnostics/run`
  se service_token).
Chybové odpovědi `{"ok":false,"error":"…"}`; neplatný service_token → 403.

UI (`ui/index.html`, `ui/app.js`, `ui/style.css`; vanilla JS, žádné CDN, offline):
1920×1080, tmavé téma jako Flutter kiosk (gradient #0f1a14→#1a2e22, zelená #74FB71,
červená #dc2626, amber). Hlavička: logo (`ui/logo.svg`/text) „MotoGo24 / PŮJČOVNA MOTOREK" + název pobočky
+ indikátor online. Výzva „Zadejte přístupový kód", maskované pole (● za každý znak,
`mask_pin_on_screen`), numerická klávesnice (velká tlačítka ≥ 120 px) + tlačítko
„ABC" přepínající na QWERTY (servisní hesla), ⌫, Smazat, OK. Timeout zadávání
`pin_entry_timeout_s` (vymaže vstup). Overlay stavů (working/success/error, auto-hide
6 s, texty z Flutter kiosku: „Ověřuji kód…", „Otevřeno — Po vyzvednutí oblečení zavřete
dveře a zadejte kód k motorce.", „Příjemnou cestu! 🏍️", „Neplatný kód", „Zkuste to
prosím znovu nebo kontaktujte podporu: +420 774 256 271."). Servisní panel (jen po
servisním heslu): mřížka zón (stav, dveře, signál, tlačítka Otevřít/Světlo/Hudba),
Vše vypnout, stav zařízení (online, ID, verze, moduly, LTE), Přepárovat (formulář),
Restart. Setup obrazovka když není spárováno. Spodní lišta: 9 dlaždic zón (barva dle
signálu/stavu) pro rychlou orientaci. Při ztrátě WS → reconnect + banner „Řídicí
jednotka nedostupná". Klávesnice fyzická (numpad) funguje také. **Diagnostika sítě** (`ui/diag.js`,
overlay `#diag`, z-index nad setupem): otevře se po diagnostickém kódu z hlavní klávesnice (`/api/pin` →
`kind: "diagnostics"`), tlačítkem na setup obrazovce (zadání kódu textovou klávesnicí → `/api/diagnostics/run`)
nebo ze servisního panelu (service_token); zobrazuje průběh (`snapshot().diagnostics`) a po dokončení
celý report (souhrn + problémy, systém, rozhraní/brány/DNS, LTE, internet, Velín, konfigurovaná
zařízení, hosty v LAN, ARP, kroky) z `GET /api/diagnostics`; „Spustit znovu".

## 17. `health.py`

```python
class HealthMonitor:
    def __init__(self, cfg: HealthCfg, controller_url: str = "http://127.0.0.1:8080") -> None
    async def run(self) -> None   # smyčka každých cfg.check_interval_s (30):
        # internet = HTTP GET cfg.probe_url (timeout 8 s) ; LTE info: `mmcli -m any -J` (signal/operator/state), `nmcli -t -f GENERAL.STATE dev show <iface>`;
        # sys: /sys/class/thermal/thermal_zone0/temp, `vcgencmd get_throttled`, shutil.disk_usage('/'), /proc/meminfo, os.getloadavg(), /proc/uptime
        # politika: failures>=cfg.reconnect_after (5) → `nmcli con up <cfg.nm_connection>` ; reconnect_failures>=cfg.usb_reset_after (5) → `sudo <cfg.usb_reset_script>` (bez argumentů; VID:PID bere skript z `/etc/motogo/modem_vidpid`) ; SIM locked/missing → `lte.error`, politika se přeskočí ;
        # dále >= cfg.reboot_after (3 USB resety bez úspěchu) a uptime > cfg.min_uptime_before_reboot_s (1800) → `sudo systemctl reboot`
        # každý cyklus POST controller_url/api/health {internet, lte, sys, ts, actions:[…]} ; sd_notify WATCHDOG=1
def read_cpu_temp() -> float | None ; def read_throttled() -> str | None ; def disk_free_pct(path='/') -> float ; def mem_free_pct() -> float
async def run_cmd(*args, timeout: float = 20) -> tuple[int, str]   # subprocess, nikdy nevyhazuje
```
`HealthCfg` v `config.py` (sekce `health` v config.yaml): `check_interval_s, probe_url,
nm_connection ('motogo-lte'), modem_vid_pid ('1e0e:9001'), usb_reset_script, reconnect_after,
usb_reset_after, reboot_after, min_uptime_before_reboot_s`.

## 18. `sdnotify.py`

`def notify(state: str) -> None` (datagram na `NOTIFY_SOCKET`, bez socketu no-op),
`async def watchdog_loop(interval_s: float, healthy: Callable[[], bool]) -> None`
(posílá `WATCHDOG=1` jen když `healthy()`).

## 19. `__main__.py` (HOTOVO — jen používat)

`controller` | `health` | `simulate` | `check-config <hardware.yaml>`.

## 20. `tools/simulator.py`

`async def run_simulator(host='127.0.0.1', base_port=15020, shelly_base_port=18031, control_port=18099)`:
Modbus TCP servery WAV645 (port base) a WAV617-A/B (base+1, base+2): implementují FC01/02/03/05/06,
0x00FF all on/off, 0x0200+n flash-on (auto vypnutí po n×100 ms), 0x1000–0x1007 mode registry,
vstupy nastavitelné přes `POST http://127.0.0.1:18099/sim/input {"dev":"wav617a","input":0,"value":true}`
a `GET /sim/state` (stav coils/inputs/lights). Fake Shelly (4×, porty 18031–18034): `POST /rpc` Light.Set/Light.GetStatus.
`config/sim-9zone.yaml` = brno mapa s localhost adresami/porty (stejné zóny).
Třídy `SimRelayModule`, `SimShelly` použitelné v testech in-process (`await start()` / `await stop()`).

## 21. Testy (`tests/`, pytest + pytest-asyncio, `asyncio_mode=auto` v `pytest.ini`)

- `test_config.py`: brno mapa načte 9 zón; každá zóna má lock/contact/light/audio/red/green; žádné dva zámky/audio relé/signál kanály nesdílí stejný coil; `merge_hardware` remote přepíše timings; `validate_hardware` hlásí neznámé zařízení.
- `test_modbus.py`: MBAP framing/parsing; exception response; klient proti simulátoru (read/write/flash-on); offline po 3 selháních na neexistující port.
- `test_io.py`: `all_off` ověřený; `pulse` na WAV645 = flash (coil se sám vypne); WAV617 `set_normal_mode`.
- `test_zone.py`: fake IoBus/Signal/Audio (in-memory); průchod SECURED→ACCESS_GRANTED→WAITING→DOOR_OPEN→CLOSED_CONFIRMATION→SECURED s falešnými hodinami; open timeout; forced open; io offline → přístup zamítnut; overtime.
- `test_pins.py`: hmac shoda s referenční hodnotou; lockout 5 pokusů/5 min → 15 min; LocalResolver na hashované i legacy cache.
- `test_audio.py`: selector nikdy nesepne 2 relé, pořadí kroků, fade.

---

## 22. Backend (SQL) — `supabase/migrations/20260909_kiosk_rpi_controller.sql`

Idempotentní; přidává: `branch_kiosk_config.hardware jsonb DEFAULT '{}'`, `branch_doors.hw jsonb DEFAULT '{}'`,
`kiosk_devices.status jsonb DEFAULT '{}'` + `status_at timestamptz`; CHECK `kiosk_commands.command` rozšířený o
`light_on, light_off, set_signal, zone_test, audio_test, all_off, reboot, sync_config, update_software`;
RPC `kiosk_sync_config(p_device_id uuid, p_device_token uuid) RETURNS jsonb` → `{ok, synced_at, branch_name, hardware,
timings{door_open_seconds,light_seconds,music_seconds}, music_on_url, music_off_url, power_status_url, power_poll_seconds,
doors:[{id,door_kind,box_number,label,hw,relay_url,light_url}], service_codes:[{h}], codes:[{h,kind,booking_id,valid_from,valid_until,door_id,box_number}]}`
kde `h = encode(extensions.hmac(convert_to(p_device_id::text||':'||code,'UTF8'), convert_to(p_device_token::text,'UTF8'),'sha256'),'hex')`
(`SET search_path = public, extensions`); RPC `kiosk_report_status(p_device_id, p_device_token, p_status jsonb) RETURNS void`
(upsert `kiosk_devices.status/status_at`, touch last_seen). GRANT anon/authenticated/service_role, REVOKE public.

**`supabase/migrations/20260910_kiosk_diagnostics.sql`** (idempotentní): `branch_service_codes.action text
NOT NULL DEFAULT 'service'` CHECK (`service` | `diagnostics`); CHECK `kiosk_commands.command` + `diagnostics`;
tabulka `kiosk_diagnostics (id, device_id FK, branch_id FK, report_id, source, ok, problems jsonb, summary jsonb,
report jsonb, app_version, started_at, finished_at, created_at)` + indexy (branch_id/device_id, created_at DESC),
RLS `kiosk_diagnostics_admin FOR ALL is_admin()`; RPC `kiosk_report_diagnostics(p_device_id, p_device_token,
p_report jsonb) RETURNS jsonb` (`{ok, id}` / `{ok:false, error}`, drží posledních 30 reportů na zařízení);
`kiosk_sync_config.service_codes` nově `[{h, action, label}]`; `kiosk_resolve_code` u servisního hesla vrací
i `action` a `label` (tablety ignorují).

## 23. Velín

`velin/src/pages/BranchRpiZones.jsx` (živý stav zón + příkazy per zóna/celek) a
`velin/src/pages/BranchRpiHardware.jsx` (editor `hardware` + `hw` per dveře, tlačítko
„Načíst výchozí mapu Brno (9 zón)"). Napojení v `BranchSelfService.jsx` (import + render
bloků; existující bloky beze změny). Příkazy přes existující `kiosk_commands` insert.
`velin/src/pages/BranchRpiDiagnostics.jsx` — blok „Diagnostika sítě (Raspberry)": tlačítko Spustit
(příkaz `diagnostics`, pak polling `kiosk_diagnostics` á 5 s do 150 s), seznam reportů (ok/problémy/
internet/LTE/moduly/hosty) + detail (načte `report` jsonb; tabulky jako na displeji + celý JSON).
`ServiceCodesBlock` má select „Účel“ (`action`: servisní panel | jen diagnostika).

## 24. `diagnostics.py` + `net_scan.py` — diagnostika sítě

```python
class NetworkDiagnostics:
    def __init__(self, ctrl: BoxController)                 # cfg = ctrl.local.diagnostics (DiagnosticsCfg)
    def matches_local_code(self, code: str) -> bool         # diagnostics.code (normalize, case-insensitive, compare_digest)
    def start(self, source: str, reason: str | None = None) -> dict   # {ok, started, id} | {ok:false, error:'already_running', id}
    def status(self) -> dict     # {running, id, step, step_title, done[], steps[], elapsed_s, error, last:{id, ts, ok, problems, hosts, duration_s, source}|null}
    def last_report(self) -> dict | None                    # Storage.kv 'last_diagnostics'
    async def run(self, source, reason) -> dict             # kroky system→interfaces→lte→internet→supabase→devices→lan→arp→summary
    async def cancel(self) / async def wait(self)
```
Zdroje spuštění: lokální kód (`submit_code`: lockout → lokální diag. kód → `not_ready` → resolve;
`kind:"diagnostics"`; offline servisní heslo z cache starší než 72 h → `service_cache_expired`),
servisní heslo s `action == "diagnostics"` (`ResolveResult.is_diagnostics`; offline z cache
`service_codes[{h, action}]`), `/api/diagnostics/run` (service_token / code), příkaz `diagnostics`.
Report (`{id, ts, source, reason, version, device_id, branch_name, paired, steps{name:{ok, ms, error}},
system, interfaces{interfaces[], default_routes[], dns[]}, lte, internet{dns[], tcp, http[], ok},
supabase{paired, ok, ms, branch_name, outbox_pending, error}, devices[{name, type, host, port, reachable, ms,
error, ping_ms, identified, online}], lan{subnets[], skipped_subnets[], ports[], scanned_hosts,
hosts[{ip, mac, ports{port:ms}, configured_as, modbus, shelly, http}]}, arp[], summary{ok, problems[],
hosts, internet, lte, devices_ok, devices_total}, duration_s, finished_at}`) se uloží do kv, pošle
`api.report_diagnostics` (outbox `report_diagnostics` → RPC `kiosk_report_diagnostics`) a zaloguje
`EventKind.DIAGNOSTICS` (`kiosk_log_event`, zdroj `diagnostics`). Každý krok má vlastní try/except a
společný limit `timeout_s`; jeden běh najednou. `net_scan`: `interfaces()` (`ip -j addr`, fallback
ioctl), `routes()`, `dns_servers()`, `arp_table()`, `resolve()`, `tcp_probe()`, `subnet_hosts()`,
`scan_hosts()` (semafor `scan_concurrency`), `http_info()`, `ping()`, `modbus_identify()` (FC01 16/8 +
FC02 8 → wav645/wav617/modbus), `shelly_identify()` (`/rpc/Shelly.GetDeviceInfo`, Gen1 `/shelly`),
`lte_info()`; nic nezapisuje do zařízení.
