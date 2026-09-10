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
| `reboot` | `wait_idle?` (bool), `wait_idle_s?` | bez `wait_idle`: complete, pak `sudo systemctl reboot`; selhání sudo → `log_event` (Velín vidí důvod). S `wait_idle:true` (Velín „Restart OS“ v bloku Aktualizace řídicích jednotek): `ctrl.updater.start('reboot', params)` → hned `{scheduled:true, wait_idle_s}`, reboot až když je box volný (§25; `update.kind='reboot'`, `waiting` → `rebooting`, selhání `failed` `reboot_failed: rc=N`; `last` se NEpřepisuje). `restart`/`reboot` = `TERMINAL_COMMANDS` (dokončí se před ukončením procesu) |
| `update_software` | `ref?` (sha 7–40 hex), `rollout_id?`, `wait_idle_s?` (0–14400, výchozí 1800) | `ctrl.updater.start('software', params)` (§25) — jen NAPLÁNUJE a hned vrací `(True, {scheduled:true, ref, wait_idle_s})`; v klidu `sudo /usr/local/sbin/motogo-update` (root-owned kopie `scripts/update.sh`: `git fetch` + `git merge --ff-only <ref\|@{upstream}>` jako vlastník checkoutu, pip v rozsazích requirements, restart; timeout 900 s). Odmítne `invalid_ref`, `update_in_progress` (+`state`, `kind`; po timeoutu `reason:'timeout_orphan'`, `retry_after_s`). Výsledek Velín pozná z hlášené verze / `status.update`, ne z výsledku příkazu |
| `update_system` | `rollout_id?`, `wait_idle_s?`, `auto_reboot?` (bool) | `ctrl.updater.start('system', params)` → `(True, {scheduled:true, wait_idle_s, auto_reboot})`; v klidu `sudo /usr/local/sbin/motogo-sysupdate` (apt full-upgrade, timeout 2700 s), `REBOOT_REQUIRED=0\|1` z výstupu → `last.reboot_required`; chybí-li skript → `failed` `sysupdate_missing: …` (bez sudo); `auto_reboot` + nové jádro → znovu počkat na klid → `sudo systemctl reboot`. Není HW ani TERMINAL příkaz |
| `http_get` / `camera_control` | `url` | httpx GET (timeout 6 s) |
| `diagnostics` | `mode?` (`full` výchozí \| `network` = jen síť), `cameras?` (`[{name, kind, snapshot_url, stream_url}]`, max 20 — uloží se do kv `diag_cameras` i pro lokální běhy), `reason?` | `ctrl.diagnostics.start(source='velin', reason, mode=…, cameras=…)` — kompletní diagnostika pobočky na pozadí (§24), `{ok, started, id, mode}` / `already_running`; není HW příkaz (funguje i při `not ready`) |

Příkazy `pending` nevyzvednuté do 10 min označí `kiosk_fetch_commands` jako `expired` (`20260910b_kiosk_commands_ttl.sql`) — Velín tak nečeká věčně na offline jednotku.
Neznámý příkaz → `(False, {"error":"unknown_command"})`.
Dokud běží root skript aktualizace (`updater.state == 'running'`) nebo trvá ochranná lhůta po jeho timeoutu
(`updater.script_running`), `execute` odmítá `restart`/`reboot` s `(False, {error:'update_in_progress', command, state, kind})`
(`update_blocks`) — restart unity by zabil git/pip/apt uprostřed běhu; controller v tom případě příkaz nepotvrzuje předem.

## 14. Status payload (`BoxController.snapshot()` = UI state = `kiosk_report_status`)

```json
{"ts":"2026-09-09T10:00:00+02:00","version":"1.0.0+abc123","uptime_s":123,"ready":true,"branch_name":"Brno",
 "internet":true,"config_source":"remote|local","config_problems":[],
 "modules":{"wav645":true,"wav617a":true,"wav617b":true,"shelly1":true,"shelly2":true,"shelly3":true,"shelly4":true},
 "audio":{"playing_zone":null,"player_ok":true,"playlist_count":12,"device":"alsa/plughw:CARD=Headphones"},
 "diagnostics":{"running":false,"id":null,"mode":"full","step":null,"step_title":null,"done":[],"steps":["system","…","summary"],
                "elapsed_s":null,"error":null,
                "last":{"id":"…","ts":"…","ok":true,"mode":"full","problems":0,"warnings":1,"hosts":7,"zones_ok":9,"zones_total":9,"duration_s":95.2,"source":"velin"}},
 "update":{"state":"idle","kind":null,"ref":null,"since":null,"error":null,
           "last":{"kind":"software","state":"done","ref":"8ceff42","rollout_id":"uuid|null","started_at":"…","finished_at":"…",
                   "error":null,"reboot_required":null,"output_tail":"…"}},
 "health":{"lte":{"state":"connected","operator":"T-Mobile CZ","rssi":-71,"rsrp":-98,"reconnects":0,"usb_resets":0},
           "sys":{"cpu_temp":48.2,"throttled":"0x0","disk_free_pct":81,"mem_free_pct":60,"load1":0.3,"uptime_s":9999,
                  "reboot_required":false,"os":"Debian GNU/Linux 12 (bookworm)","kernel":"6.6.51+rpt-rpi-2712","last_unattended_at":"…|null"},
           "internet":true,"ts":"…"},
 "zones":[{"zone":1,"door_id":"uuid|null","box_number":1,"kind":"motorcycle","label":"Kóje 1","state":"SECURED",
           "door_closed":true,"fault":null,"light":false,"signal":"red","music":false,"latch_released":false,"degraded":false,
           "session_started_at":null,"booking_id":null,"last_event":"DOOR_CLOSED"}],
 "notice":null}
```

Hodnoty `state` = `ZoneState.value` (velká písmena), `signal` = `Signal.value` (malá písmena: red, green, green_pulse, red_blink, both_blink, off).

`diagnostics` = `NetworkDiagnostics.status()` (§24): `mode` full|network, `steps` = pořadí kroků dle režimu (`STEPS` / `NETWORK_STEPS`),
`step_title` ze `STEP_TITLES`, `last` = souhrn posledního reportu (`problems`/`warnings` = počty, `zones_*` jen u full). Velín
(`BranchRpiDiagnostics.jsx`) z něj během čekání na report ukazuje „krok X (n/m)“; displej průběh „(n/m, s)“.

`update` = `SoftwareUpdater.status()` (§25): `state` ∈ `idle|waiting|running|rebooting|done|failed`, `kind` ∈
`software|system|reboot|null`, `ref` (cílový commit), `since` (= `started_at`), `error`; `last` = poslední dokončený běh
software/OS (`Storage.kv['last_update']`, přežije restart i reboot; běh `reboot` ho nepřepisuje): `{kind, state, ref, rollout_id,
started_at, finished_at, error, reboot_required, output_tail, reboot_at?}` — `kiosk_rollout_tick` z něj čte výsledek OS
aktualizace (`kind='system'`, `state='done'`, `finished_at`). Velín: řádek „Aktualizace: čeká na klid / probíhá / selhalo“
(`BranchRpiZones.jsx`), tabulka jednotek (`FleetUpdates.jsx`). `health.sys` OS pole viz §17.

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
- `POST /api/diagnostics/run {"service_token"} | {"code"}` + volitelné `"mode": "full"|"network"` (jiné/chybí → full)
  → spustí diagnostiku pobočky (§24); service_token → `diagnostics.start('service_panel', mode=…)`; `code` jde přes
  `controller_codes.submit_code(ctrl, code, "diag_ui", diagnostics_only=True)` s hintem `diagnostics.pending_mode = mode`
  (ve `finally` vždy `None`): lokální diagnostický kód, servisní heslo s účelem `diagnostics` nebo běžné servisní heslo
  (spustí JEN diagnostiku, bez servisního tokenu); zákaznický PIN/kód rezervace je tu `invalid_code` a počítá se do
  lockoutu; neplatný → 403 `{ok:false, error, message, locked_until}`. Lockout blokuje i diagnostický kód (kromě
  `/api/diagnostics/run` se service_token). Odpověď `{ok, started, id, mode}` / `{ok:false, error:'already_running', id, mode}`.
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
jednotka nedostupná". Klávesnice fyzická (numpad) funguje také. **Diagnostika pobočky** (`ui/diag.js`,
overlay `#diag`, z-index nad setupem): otevře se po diagnostickém kódu z hlavní klávesnice (`/api/pin` →
`kind: "diagnostics"`), tlačítkem „🔍 Diagnostika pobočky (kód z config.yaml)“ na setup obrazovce (zadání kódu
textovou klávesnicí → `/api/diagnostics/run`) nebo ze servisního panelu „🔍 Diagnostika pobočky“ (service_token);
vše `mode: 'full'`. Zobrazuje průběh (`snapshot().diagnostics`: krok, n/m, s) a po dokončení report z
`GET /api/diagnostics`: souhrn („✔ Pobočka/Síť je v pořádku“ / „⚠ N problémů, M varování“ + režim, zóny OK x/y,
moduly, LAN, kontrol, seznam problémů), sekce **Protokol** (za každou sekci `protocol` badge stavu + tabulka
Kontrola | Stav | Zjištění | Co s tím; hint jen u warn/fail), pak detail (systém, rozhraní/brány/DNS, LTE, internet,
Velín, konfigurovaná zařízení, hosty v LAN, ARP, **Zóny a periferie** (stav, dveře, kontakt z modulu, test
světlo/signál/audio, zámek, Shelly, problémy), **Napájení (FV)**, **Kamery**, **Software**, kroky); starší report bez
`protocol` = jen detail. „↻ Spustit znovu“ = full; hláška „Diagnostika spuštěna — trvá 1–4 min.“

## 17. `health.py`

```python
class HealthMonitor:
    def __init__(self, cfg: HealthCfg, controller_url: str = "http://127.0.0.1:8080") -> None
    async def run(self) -> None   # smyčka každých cfg.check_interval_s (30):
        # internet = HTTP GET cfg.probe_url (timeout 8 s) ; LTE info: `mmcli -m any -J` (signal/operator/state), `nmcli -t -f GENERAL.STATE dev show <iface>`;
        # sys: /sys/class/thermal/thermal_zone0/temp, `vcgencmd get_throttled`, shutil.disk_usage('/'), /proc/meminfo, os.getloadavg(), /proc/uptime ;
        #      OS (2026-09-10): /run/reboot-required, PRETTY_NAME z /etc/os-release, os.uname().release, mtime /var/lib/apt/periodic/upgrade-stamp
        # politika: failures>=cfg.reconnect_after (5) → `nmcli con up <cfg.nm_connection>` ; reconnect_failures>=cfg.usb_reset_after (5) → `sudo <cfg.usb_reset_script>` (bez argumentů; VID:PID bere skript z `/etc/motogo/modem_vidpid`) ; SIM locked/missing → `lte.error`, politika se přeskočí ;
        # dále >= cfg.reboot_after (3 USB resety bez úspěchu) a uptime > cfg.min_uptime_before_reboot_s (1800) → `sudo systemctl reboot`
        # každý cyklus POST controller_url/api/health {internet, lte, sys, ts, actions:[…]} ; sd_notify WATCHDOG=1
def read_cpu_temp() -> float | None ; def read_throttled() -> str | None ; def disk_free_pct(path='/') -> float ; def mem_free_pct() -> float
async def run_cmd(*args, timeout: float = 20) -> tuple[int, str]   # subprocess, nikdy nevyhazuje
```
`HealthCfg` v `config.py` (sekce `health` v config.yaml): `check_interval_s, probe_url,
nm_connection ('motogo-lte'), modem_vid_pid ('1e0e:9001'), usb_reset_script, reconnect_after,
usb_reset_after, reboot_after, min_uptime_before_reboot_s`.

`health_probe.sys_metrics()` = `health.sys` `{cpu_temp, throttled, disk_free_pct, mem_free_pct, load1, uptime_s, reboot_required,
os, kernel, last_unattended_at}` — OS pole se čtou jen ze souborů (bez rootu, bez apt): `reboot_required` = existuje
`/run/reboot-required`, `os` = `PRETTY_NAME` z `/etc/os-release`, `kernel` = `os.uname().release`, `last_unattended_at` = ISO mtime
`/var/lib/apt/periodic/upgrade-stamp` (poslední běh unattended-upgrades), jinak `null`. **`/run/reboot-required` na Debianu/RPi OS
nevzniká sám** (píše ho jen ubuntí `update-notifier-common`) — zakládá ho `motogo-sysupdate` (po `full-upgrade`) a hook
`DPkg::Post-Invoke` v `/etc/apt/apt.conf.d/52motogo-unattended` (po každém běhu apt/dpkg vč. unattended-upgrades), když je
v `/lib/modules` nainstalované novější jádro běžící varianty (přípona za poslední pomlčkou, např. `rpi-2712`) než `uname -r`
(sysupdate navíc když apt nastavil linux-image/raspberrypi-kernel/libc6/libssl/systemd/dbus); názvy balíků do
`/run/reboot-required.pkgs`. Velín z toho ukazuje chip „Restart OS potřebný“; restart jen z Velína (§25).

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
`velin/src/pages/BranchRpiDiagnostics.jsx` — blok „Kompletní diagnostika pobočky (Raspberry)": tlačítko
„🔍 Kompletní diagnostika — <jednotka>“ (příkaz `diagnostics {mode:'full', cameras, reason:'velin'}`; `cameras` z props
`BranchSelfService.jsx`) + malé „jen síť“ (`mode:'network'`), pak polling `kiosk_diagnostics` á 5 s do 300 s a průběh
„krok X (n/m)“ z `kiosk_devices.status.diagnostics`; seznam běhů (chip OK / N problémů / M varování, režim, zóny x/y,
moduly, LAN, trvání) + „Protokol“ (`BranchRpiDiagProtocol.jsx`: hlavička, „Kde je problém“, „Varování“, sekce s tabulkou
a sbalenými OK kontrolami, sbalený „Technický detail sítě“ = `BranchRpiDiagNetwork.jsx`, **Stáhnout protokol (.txt)**
`diagnostika-<pobocka>-<YYYYMMDD-HHMM>.txt` + **Kopírovat**); starší report bez `protocol` → jen síťový detail (§24).
`ServiceCodesBlock` má select „Účel“ (`action`: servisní panel | jen diagnostika).

## 24. Diagnostika pobočky — `diagnostics.py` + `diag_steps.py` + `diag_protocol.py` + `diag_hints.py` + `net_scan.py`

```python
class NetworkDiagnostics:
    def __init__(self, ctrl: BoxController)       # cfg = ctrl.local.diagnostics (DiagnosticsCfg); mode="full"; pending_mode=None
    def matches_local_code(self, code: str) -> bool   # diagnostics.code (normalize, case-insensitive, compare_digest)
    def start(self, source: str, reason: str | None = None, *, mode: str | None = None, cameras: list | None = None) -> dict
        # {ok, started, id, mode} | {ok:false, error:'already_running', id, mode}; mode None → pending_mode nebo "full",
        # neznámý → "full"; cameras (list dictů, max MAX_CAMERAS=20) se VŽDY uloží do Storage.kv['diag_cameras']
    def status(self) -> dict   # {running, id, mode, step, step_title, done[], steps[] (NETWORK_STEPS|STEPS dle mode), elapsed_s, error,
                               #  last:{id, ts, ok, mode, problems:int, warnings:int, hosts, zones_ok, zones_total, duration_s, source}|null}
    def last_report(self) -> dict | None          # Storage.kv 'last_diagnostics'
    def cameras_list(self) -> list[dict]          # kamery z parametrů běhu, jinak kv 'diag_cameras' (max 20)
    def time_left(self) -> float | None           # deadline − now (None mimo běh); diag_steps.zones podle něj HW test nespustí
    async def run(self, source, reason) -> dict   # kroky dle mode, každý izolovaně; pak protocol + summary, uložení, odeslání, událost
    async def cancel(self) / async def wait(self)
```
**Režimy** `MODES = ("full", "network")`, výchozí **full** všude (Velín, kód z displeje, servisní heslo, `/api/diagnostics/run`).
`STEPS` (full): system → interfaces → lte → internet → supabase → devices → **software → config → zones → power → cameras**
→ lan → arp → summary (HW testy zón před dlouhým scanem LAN, aby se stihly v limitu). `NETWORK_STEPS` = bez
`FULL_ONLY = (software, config, zones, power, cameras)`. Limit běhu `timeout_s` (network, 120 s) / `full_timeout_s`
(full, 240 s), min. 20 s; `deadline` (monotonic) — každý krok dostane `wait_for(zbytek)`; timeout kroku → `report[name] =
_partial[name]` (rozpracované `lan`/`zones` zůstávají), `steps[name] = {ok:false, error:'timeout', partial:bool, ms}`;
výjimka kroku → `report[name] = None`, `{ok:false, error:str, ms}`. Jeden běh najednou.

**Zdroje spuštění** (vše full, není-li `mode` řečen): lokální kód (`submit_code`: lockout → lokální diag. kód → `not_ready`
→ resolve; `kind:"diagnostics"`; offline servisní heslo z cache starší než 72 h → `service_cache_expired`), servisní heslo
`action == "diagnostics"` (`ResolveResult.is_diagnostics`) nebo běžné servisní heslo v okně diagnostiky (`diagnostics_only`)
— obojí přes `controller_codes.start_diagnostics` → `start(mode = diagnostics.pending_mode or "full")`; `POST
/api/diagnostics/run {service_token|code, mode?}` (§16: service_token → `start('service_panel', mode=…)`, code → hint
`pending_mode = mode`, po návratu vždy `None`); příkaz `diagnostics {mode?, cameras?, reason?}` (§13, source `velin`).

**Report** `{id, ts, source, reason, mode, version, device_id, branch_name, paired, steps{name:{ok, ms, error?, partial?}},
system{hostname, kernel, machine, python, time, ntp_synced, metrics, controller_uptime_s, ready, config_source, config_problems[]},
interfaces{interfaces[], default_routes[], dns[]}, lte, internet{dns[], tcp, http[], ok}, supabase{url, paired, device_id,
outbox_pending, ok, ms, branch_name, error}, devices[{name, type, host, port, reachable, ms, error, ping_ms, identified,
online}], software, config, zones[], power, cameras[] (jen full), lan{subnets[], skipped_subnets[], skipped[], ports[],
scanned_hosts, hosts[{ip, mac, ports{port:ms}, configured_as, modbus, shelly, http}], partial}, arp[≤256], duration_s,
protocol[], summary, finished_at}` → kv `last_diagnostics`, `api.report_diagnostics` (outbox → RPC `kiosk_report_diagnostics`,
limit 512 KiB: `max_hosts`, arp ≤ 256, `recent_errors` ≤ 10, `raw_keys` ≤ 64, kamery ≤ 20), událost `EventKind.DIAGNOSTICS`
(`kiosk_log_event`, zdroj `diagnostics`, level info|warn, `success = summary.ok`): message „Diagnostika pobočky: OK | N problémů,
M varování (Z/Ztot zón OK, H zařízení v LAN, D s)“ (zóny jen když krok `zones` běžel), `detail{source, report_id, mode,
problems[≤20], warnings[≤20], hosts, internet, checks}`.

**Nové kroky (`diag_steps.py`, `async fn(diag, report)`, vše jen čtení, bez rootu):**
- `software`: `{version, uptime_s, ready, config_source, config_problems[], services{"motogo-controller"|"motogo-health"|"motogo-ui":
  active|inactive|failed|activating|deactivating|null} (systemctl is-active), failed_units:int|null, audio{player_ok, playlist_count,
  device, music_files:int|null}, realtime{connected:bool|null}, api{online, paired}, outbox_pending, events_total,
  recent_errors[{ts, kind, message}] (≤10, level error/crash za 24 h), lockout_until:iso|null, code_cache{saved_at, age_s, codes,
  service_codes}, last_update:dict|null (updater.last), reboot_required:bool|null (/run/reboot-required), health_age_s:float|null}`.
- `config`: `{branch_name, source, zones_total, zones[{zone, label, kind, door_id, box_number, roles{lock,contact,light,audio,red,green:
  "dev:idx"|null}, missing[role]}], doors_without_hw[label] (jen source remote: kv remote_config.doors bez hw.zone), duplicates[str]
  (stejný dev:idx ve dvou rolích téhož druhu coil/input/light), timings{…}, timings_problems[str] (lock_pulse_ms mimo 100–5000,
  door_open_timeout_s < 5, maximum_session_s < 60, light_after_close_s < music_after_close_s), devices{name:{type, host, port}},
  power_status_url, cameras_provided:int, security{…}}`.
- `zones` (list dle čísla zóny, **SEKVENČNĚ** — audio selektor je exkluzivní; `_partial['zones']` přežije timeout): per `ZoneController`
  `{zone, label, kind, door_id, box_number, state, fault, door_closed, session_active, contact_raw:bool|null (io.read_all_inputs()
  jednou + input_value; True = zavřeno dle closed_level), contact_consistent:bool|null (== door_closed), io_problems[], lock{configured,
  module_online, coil_off:bool|null} (read_coils — JEN ČTENÍ), tested, skipped_reason, light, signal, audio (bool|null),
  shelly{red{on, brightness}|null, green{…}|null, expected: red|green|off|…, matches:bool|null}, findings[{key, status, message, dev?,
  ch?}], problems[str] (= messages)}`. **Bezpečnost HW testu** (`zc.test_sequence()`: světlo ON → zelená 1 s → `finally` obnova
  signálu i světla → tón 3 s; `audio.test_tone` tón zastaví i při zrušení) — kontroly v tomto pořadí dávají `skipped_reason`:
  `zone_test_disabled` (cfg.zone_test False) · `not_ready` (ctrl.ready False) · `fault` · `session_active` (state ∈ ACTIVE_STATES, nebo test
  vrátil `{error:'busy'}`) · `io_offline` (`zc.io_ready()` False) · `timeout` (`time_left() < ZONE_TEST_BUDGET_S = 15 s` → test se vůbec
  nespustí; nebo test nedoběhl do `ZONE_TEST_TIMEOUT_S = 30 s` — běží pod `asyncio.shield`, dokončí se na pozadí, nález `test` warn).
  **Zámek se NIKDY nespíná.** `audio = None`, když reproduktor hraje jinde. `findings.key`: `contact` (modul nečte vstup / nenastaven /
  program × modul nesouhlasí — fail), `lock` (nenastaven / modul offline / relé SEPNUTÉ v klidu — fail), `fault` (io_offline fail, jinak
  warn), `io` (fail), `test` (warn), `light` (fail, + `dev`, `ch`), `signal`, `audio` (fail), `shelly` (Light.GetStatus neodpovídá /
  stav ≠ `signals.current(zone)` — fail; blikání → `matches None`).
- `power`: `{configured, url, ok:bool|null, status, ms, error, values{battery_soc, battery_voltage, battery_power_w, pv_power_w,
  load_power_w, grid_present}|null, raw_keys[≤64]}` — GET `ctrl.power_status_url` (timeout `camera_timeout_s`), JSON zploštěný o 1
  úroveň, klíče přes aliasy `POWER_KEYS`; nenastaveno → `configured False, ok None`.
- `cameras`: pro každou kameru (`cameras_list()`, ≤ 20) a každé http(s) `snapshot_url` / `stream_url`: `{name, kind, url_kind:
  snapshot|stream, url, ok, status, ms, error, content_type}`; stream = `client.stream("GET")` bez čtení těla; `control_url` se netestuje.

**Protokol (`diag_protocol.py`)** — JEDINÝ formát, který displej i Velín vykreslují: `build_protocol(report) -> [section]`, sekce
v pořadí `system, software*, network, lte, internet, velin, modules, config*, zones*, power*, cameras*, lan, steps` (* jen když krok
v reportu je = full; krok běžel a selhal → 1 položka `<key>.step` skip). `section = {key, title, status, items[]}`, `item = {id, label,
status: ok|warn|fail|skip, value, message, hint? (jen warn/fail; `diag_hints.hint(key, **fmt)` z tabulky `HINTS` — modul, kanál, IP
doplněné), group?: true}`. `group: true` = souhrnná položka zóny `zone.N` (value „stav, dveře, test: světlo ✔ zelená ✔ tón –“, message
„N nálezů: …“ / „Test přeskočen: <SKIP_CZ>.“ / „Vše v pořádku.“) — do `summary.checks/problems/warnings` se NEPOČÍTÁ; každý nález má
vlastní položku `zone.N.<key>[.n]` (label „Kóje 3 — světlo“). `section_status` = nejhorší z položek (fail > warn > ok), skip
neovlivňuje, bez položek = skip; vadná data jedné sekce → položka `<sec>.error` warn (protokol nespadne). `STEP_TITLES` zde.
**Summary** `build_summary(report, protocol)`: `{ok: bool (žádný fail), problems[str] („label: message“ fail položek), warnings[str],
checks{total, ok, warn, fail, skip}, mode, zones_total (při timeoutu kroku zones ≥ config.zones_total), zones_tested, zones_ok (zóny bez
fail nálezu), sections{key: status}}` + legacy klíče `hosts, internet, lte, devices_ok, devices_total` (RPC `kiosk_report_diagnostics`
z `ok/problems/summary` plní sloupce — beze změny).

**`DiagnosticsCfg`** (`config.yaml` → `diagnostics:`): `code`, `scan_ports`, `scan_timeout_ms`, `scan_concurrency`, `scan_subnets`,
`max_hosts`, `internet_urls`, `timeout_s = 120` (network), **`full_timeout_s = 240`**, **`zone_test = True`** (False = zóny se jen čtou,
nic se nespíná), **`camera_timeout_s = 6`** (HTTP sondy kamer i měniče FV).

**Displej** (`ui/diag.js`, §16) a **Velín** (`BranchRpiDiagnostics.jsx` blok + `BranchRpiDiagProtocol.jsx` protokol/export .txt +
`BranchRpiDiagNetwork.jsx` technický detail sítě; §23) vykreslují `protocol` shodně; starší reporty bez `protocol` = jen síťový detail.

`net_scan`: `interfaces()` (`ip -j addr`, fallback ioctl), `routes()`, `dns_servers()`, `arp_table()`, `resolve()`, `tcp_probe()`,
`subnet_hosts()`, `scan_hosts()` (semafor `scan_concurrency`), `http_info()`, `ping()`, `modbus_identify()` (FC01 16/8 + FC02 8 →
wav645/wav617/modbus), `shelly_identify()` (`/rpc/Shelly.GetDeviceInfo`, Gen1 `/shelly`), `lte_info()`; nic nezapisuje do zařízení.
Testy: `tests/test_diagnostics.py` (síť, kódy, web API, příkaz), `tests/test_diag_protocol.py` + `tests/diag_fakes.py` (full běh,
bezpečnostní pravidla zón, Shelly, power/kamery, rozpočet a shield HW testu, agregace protokolu, hinty).

## 25. Hromadná aktualizace z Velína (rollout) — `updater.py` + `supabase/migrations/20260910c_kiosk_fleet_updates.sql`

Zadání (2026-09-10): Velín rozešle „aktualizuj se“ všem RPi jednotkám a ohlídá výsledek podle hlášené verze
(`kiosk_heartbeat.p_app_version` = `"<__version__>+<git sha7>"`, `full_version()`). Pojistky: (1) NIKDY slepě při každém
pushi — vědomě tlačítkem, nebo noční automatika (`nightly_hour`, výchozí 03:00 Prahy); box sám odloží restart programu,
dokud je v kóji zákazník (`wait_idle_s`); (2) postupně: kanárek → soak → zbytek; (3) OS: bezpečnostní záplaty
`unattended-upgrades` (04:00 ± 20 min, bez restartu), `apt full-upgrade` + restart po jádru jen z Velína.

**Tabulky** (RLS `<tabulka>_admin` FOR ALL `is_admin()`): `kiosk_releases(id, commit UNIQUE 40 hex, version, message, author,
committed_at, files_changed, created_at)`; `kiosk_fleet_settings` singleton `id=true` (`nightly_enabled`, `nightly_hour` 0–23,
`canary_device_id`, `soak_minutes` 5–1440, `wait_idle_s` 0–14400, `system_enabled`, `system_every_days` 1–365,
`system_auto_reboot`, `last_nightly_date`, `last_system_date`); `kiosk_rollouts(id, kind software|system, mode manual|nightly,
status canary|soak|rollout|done|failed|cancelled, release_id, target_commit, canary_device_id, soak_minutes, wait_idle_s,
auto_reboot, created_by, canary_started_at, canary_done_at, soak_until, rollout_started_at, finished_at, error, result jsonb,
note)`; `kiosk_rollout_devices(rollout_id, device_id, role canary|fleet, status pending|commanded|updated|failed|offline|skipped,
command_id, commanded_at, version_before, version_after, detail)`. `kiosk_commands.command` CHECK + `update_system`.

**RPC** (SECURITY DEFINER, GRANT authenticated + service_role, REVOKE public; guard `auth.uid() IS NOT NULL AND NOT is_admin()`
→ `{ok:false, error:'forbidden'}` — cron bez uid a service_role projdou; advisory lock = max. 1 aktivní rollout):
- `kiosk_version_matches(p_app_version, p_commit) → boolean` (IMMUTABLE, GRANT i anon): sha za `+` ≥ 7 hex a prefix commitu.
- `kiosk_rollout_start(p_kind, p_release_id, p_canary_device_id, p_soak_minutes, p_wait_idle_s, p_auto_reboot, p_mode='manual')`
  → `{ok:true, id, status:'canary'|'soak'}` | `{ok:false, error: forbidden|invalid_kind|invalid_mode|rollout_active(+id)|
  release_not_found|no_canary|canary_not_found}`. Kanárek NULL = naposledy viděná online (< 90 s) aktivní RPi jednotka; zadaný
  musí být aktivní RPi (tablet ne). Flotila = ostatní aktivní RPi → `pending` (nikdy neviděné `skipped` `{reason:'never_seen'}`).
  Kanárek už na cíli → rovnou `soak`; jinak INSERT `kiosk_commands` (`update_software {ref, rollout_id, wait_idle_s}` /
  `update_system {rollout_id, wait_idle_s, auto_reboot}`) → řádek `commanded` + `version_before`. Hodnoty ořezány na CHECK rozsahy.
- `kiosk_rollout_cancel(p_id)` → `{ok:true, id, status:'cancelled', expired_commands}` | `not_found` | `not_active(+status)`;
  pending příkazy rolloutu → `expired` (`result.error='cancelled'`).
- `kiosk_rollout_tick()` → `{ok:true, ticked:[ids], started: id|null, nightly_error?}` — pg_cron `kiosk-fleet-update-tick`
  (`*/5 * * * *`) + Velín „Zkontrolovat teď“; každý rollout ve vlastním bloku (chyba jednoho nezastaví ostatní).
- Interní (REVOKE public, bez GRANT): `kiosk_rollout_jts`, `kiosk_device_updated` (software = shoda verze s `target_commit`;
  system = `status.update.last` kind system / state done / `finished_at` ≥ od), `kiosk_device_update_error` (`update_failed: …`
  z `status.update.last` failed, nebo `command_failed|command_expired: …`), `kiosk_rollout_send_command`, `kiosk_rollout_counts`.

**Tick:** `canary` — kanárek aktualizován → řádek `updated`, rollout `soak` (`soak_until = now + soak_minutes`); chyba →
`failed` (`canary_failed: <detail>`, `canary_missing`); `now > canary_started_at + wait_idle_s + 45 min` → `canary_timeout`.
`soak` — `kiosk_logs` kanárka level error/crash od `canary_done_at` (mimo STARTUP událost controlleru) → `failed`
`canary_errors: N` (`result.errors` = posledních 5 zpráv); kanárek neviděn > 10 min → `canary_offline`; `now ≥ soak_until`
→ `rollout`. `rollout` — `pending/offline` online (< 90 s) → příkaz + `commanded`, jinak `offline`; `commanded` → `updated`
/ `failed` (chyba, nebo `timeout` po wait_idle_s + 45 min). Konec: nic otevřeného, nebo 24 h od `rollout_started_at`, nebo
po 2 h zbývají-li jen jednotky mrtvé už před rozesíláním → zbylé řádky `offline` (`{error:'unreachable'}`,
`result.offline_ids`), rollout `done`, resp. `failed` `devices_failed: N`. `result` vždy `{updated, failed, offline, skipped,
commanded, pending, total}`.
**Noční automatika** (hodina `Europe/Prague` = `nightly_hour`, žádný aktivní rollout): `nightly_enabled` ∧ `last_nightly_date
< dnes` ∧ nejnovější release (`committed_at DESC NULLS LAST, created_at DESC`) ∧ aspoň jedna aktivní RPi jednotka viděná
< 24 h není na jeho commitu → `kiosk_rollout_start('software', …, 'nightly')`; `last_nightly_date = dnes` i při neúspěchu
(žádné opakování téže noci). **OS:** `system_enabled` ∧ `last_system_date ≤ dnes − system_every_days` ∧ software dnes
nestartoval ani neselhal → `kiosk_rollout_start('system', NULL, …, system_auto_reboot, 'nightly')`; `last_system_date` se
posune až po ÚSPĚŠNÉM startu.

**Box (`SoftwareUpdater`, kinds `software|system|reboot`):** `start()` (§13) → jeden task: čeká na klid
(`ctrl._sessions_active()` prázdné a `diagnostics.running` False; poll 5 s, max `wait_idle_s`, pak pokračuje s varováním).
software: zapíše `<data_dir>/update_ref` (`<ref>\n`; bez ref soubor smaže → větev) → `sudo /usr/local/sbin/motogo-update`
(900 s) → rc 0 = `done` (proces se restartuje sám; `kiosk_log_event` jde přes outbox, nový proces ho pošle). system: chybí-li
`/usr/local/sbin/motogo-sysupdate` → `failed` `sysupdate_missing: …` (bez sudo); jinak `sudo …/motogo-sysupdate` (2700 s),
`REBOOT_REQUIRED=0|1` → `last.reboot_required`; `auto_reboot` ∧ reboot_required → znovu klid → `sudo systemctl reboot`
(`last` = done + `reboot_at` uloženo PŘED rebootem; selhání → `last` failed `reboot_failed: rc=N`). reboot (`wait_idle`):
klid → `rebooting` → `sudo systemctl reboot`; `last` se nepřepisuje. Timeout zabije jen sudo → ochranná lhůta (= timeout
skriptu): další `start()` i `restart`/`reboot` → `update_in_progress` (`reason:'timeout_orphan'`, `retry_after_s`). Výsledek:
`Storage.kv['last_update']`, `Event` (REMOTE_COMMAND, `detail.source` = `update`|`sysupdate`), `kiosk_log_event` (info/error).

**Skripty:** `motogo-update` (= `scripts/update.sh`, root, sudoers bez argumentů): flock `/run/lock/motogo-update.lock`
(souběh → „už běží“, exit 2); re-exec ve vlastním transientním scope (`systemd-run --scope --unit=motogo-update-<pid>`,
marker `MOTOGO_UPDATE_SCOPE`; bez systemd-run pokračuje na místě) — restart/pád `motogo-controller.service` nezabije
rsync/pip; čte `/var/lib/motogo/update_ref` jen jako regulární soubor (ne symlink), obsah `^[0-9a-f]{7,40}$` (jinak varování
bez echa hodnoty, jede na větev), soubor VŽDY smaže; `git fetch origin` jako vlastník checkoutu → `git merge --ff-only
<ref|@{upstream}>` → HEAD musí být přesně cíl (předek HEAD = „Already up to date“ → chyba). Exit 0 OK; 2 vstup/zdroj/souběh;
3 fetch selhal / ff-merge selhal / cíl není dopředný potomek HEAD (starší commit, jiná větev, neznámý sha) → rollback = revert
commit v main, ne couvání checkoutu. Instaluje i `motogo-sysupdate`, `52motogo-unattended`, drop-in timeru a chybí-li
`unattended-upgrades`, doinstaluje ho (max 240 s). `motogo-sysupdate` (= `scripts/sysupdate.sh`, žádné argumenty ani od roota):
flock `/run/lock/motogo-sysupdate.lock`, scope `motogo-sysupdate-<pid>` (`MOTOGO_SYSUPDATE_SCOPE`), `apt-get update` →
`full-upgrade` (`--force-confdef/--force-confold`, `DPkg::Lock::Timeout=600`) → `autoremove --purge` → `clean`; příznak
`/run/reboot-required` zakládá SÁM (§17); poslední dva řádky výstupu `REBOOT_REQUIRED=0|1` a `UPGRADED=<n>`; nikdy nerestartuje
služby ani systém; exit 0 / 2. Logy `/var/log/motogo-update.log`, `/var/log/motogo-sysupdate.log` (root-owned, symlink → /dev/null).

**Systém:** `systemd/52motogo-unattended` → `/etc/apt/apt.conf.d/` (`#clear Origins-Pattern` + jen `Debian-Security`,
`Automatic-Reboot "false"`, `Periodic` 1, `DPkg::Post-Invoke` hook → `/run/reboot-required`); `systemd/apt-daily-upgrade-override.conf`
→ `/etc/systemd/system/apt-daily-upgrade.timer.d/motogo.conf` (`OnCalendar=*-*-* 04:00`, `RandomizedDelaySec=20m`,
`Persistent=false`); `systemd/motogo-sudoers` `MOTOGO_SCRIPTS` + `/usr/local/sbin/motogo-sysupdate ""`; `install.sh` krok 10/13.

**Release evidence:** `.github/workflows/release-motogo-box.yml` — push do `main` v `raspberry/motogo-box/**` (nebo ručně,
vstup `commit` = plný sha z `main`; commit mimo main / neznámý se odmítne) → `INSERT INTO kiosk_releases (commit, version =
__version__ z daného commitu, message, author, committed_at, files_changed) ON CONFLICT DO NOTHING` přes `SUPABASE_DB_URL`
(psql, hodnoty jen přes `:'x'`); na tabulku čeká až ~5 min, jinak jen varování; commit starší (`committed_at`) než nejnovější
evidovaný se neeviduje (varování). Boxům nic nerozesílá.

**Velín:** `velin/src/pages/FleetUpdates.jsx` (+ `FleetUpdatesParts.jsx`, `fleetUpdateHelpers.js`) — sbalený blok
„Aktualizace řídicích jednotek (všechny pobočky)“ na stránce Pobočky: releasy, tabulka jednotek (verze/aktuálnost, `status.update`,
OS/jádro, „Restart OS potřebný“, tlačítka „Restart OS“ = `reboot {wait_idle:true, wait_idle_s}` a „Aktualizovat OS“ =
`update_system {auto_reboot:false, wait_idle_s}`), spuštění rolloutu (dialog: kanárek, soak, čekání na klid, u OS auto-reboot),
průběh (auto-refresh 15 s jen dokud běží; „Zrušit“, „Zkontrolovat teď“), nastavení (`kiosk_fleet_settings` upsert), historie 10.

**První rollout na stávajících boxech:** příkaz `update_software` vykoná ještě STARÝ controller + STARÝ `motogo-update`
(hned, bez čekání na klid, `git pull --ff-only` na větev; starý controller čeká na skript max 120 s — trvá-li déle, ohlásí
příkaz `failed` s `error: timeout`; `kiosk_device_update_error` tento výsledek IGNORUJE, rollout zůstává `canary` a rozhodne
hlášená verze nebo celkový timeout). Nový `update.sh` se tím stane `motogo-update`, ale `motogo-sysupdate`, `52motogo-unattended` a
`unattended-upgrades` se nainstalují až jeho DALŠÍM během. OS aktualizace před ním selže `sysupdate_missing`; náprava = znovu
„Aktualizovat software“.
