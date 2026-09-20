#!/usr/bin/env bash
# MotoGo Box — USB reset LTE modemu (SIM7600E-H, VID:PID 1e0e:9001). Volá health monitor přes sudo
# (/usr/local/sbin/motogo-usbreset — root-owned kopie; sudoers povoluje JEN bez argumentů), když
# opakované reconnecty nepomohly.
# VID:PID: 1) argument — JEN při ručním spuštění rootem (přes sudo od uživatele motogo se odmítá),
#          2) /etc/motogo/modem_vidpid (root-owned, zapisuje install.sh z MOTOGO_MODEM_VIDPID),
#          3) výchozí 1e0e:9001.
# Postup: najde zařízení v /sys/bus/usb/devices podle idVendor/idProduct, unbind + bind
# přes /sys/bus/usb/drivers/usb; záloha: authorized 0/1 JEN na tom zařízení (vynutí re-enumeraci).
# Pak počká na re-enumeraci, RESTARTUJE ModemManager a počká, až modem uvidí (ověřený ruční postup
# z 2026-09-20 — bez restartu MM skončí v PPP fallbacku na ttyUSB2). Celý běh trvá až ~90 s,
# proto health volá skript s timeoutem `usb_reset_timeout_s` (180 s) a drží cooldown.
# Modem, který na sběrnici vůbec není, se NEřeší resetem celé USB (odpojilo by to dotyk EDATEC
# a USB zvukovou kartu) — skript skončí kódem 3 a politika health eskaluje na reboot.
# Stav (sysfs port z posledního nálezu) leží v /run/motogo-usbreset/ (root, tmpfs) — nikdy
# v adresáři zapisovatelném uživatelem motogo (symlink → root by přepsal libovolný soubor).
# Použití: usbreset-modem.sh [VID:PID]   (jen root přímo)
set -euo pipefail

DEFAULT_VIDPID="1e0e:9001"
VIDPID_FILE="/etc/motogo/modem_vidpid"
LOG="/var/log/motogo-usbreset.log"
STATE_DIR="/run/motogo-usbreset"
PORT_FILE="$STATE_DIR/modem-port"     # sysfs jméno portu modemu z posledního úspěšného nálezu
[[ -L "$LOG" ]] && LOG=/dev/null      # do symlinku root nikdy nepíše

log() {
  local msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
  echo "$msg"
  echo "$msg" >> "$LOG" 2>/dev/null || true
  command -v logger >/dev/null 2>&1 && logger -t motogo-usbreset -- "$*" || true
}
valid_vidpid() { [[ "$1" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$ ]]; }

if [[ "$(id -u)" -ne 0 ]]; then
  log "CHYBA: skript potřebuje root (sudo)"; exit 2
fi
if [[ $# -gt 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  log "CHYBA: přes sudo (uživatel $SUDO_USER) nelze zadat VID:PID — čte se z $VIDPID_FILE"; exit 2
fi
# Hodnota se validuje DŘÍV, než se kdy objeví v logu (do logu nesmí přijít cizí text).
VIDPID="${1:-}"
if [[ -n "$VIDPID" ]]; then
  valid_vidpid "$VIDPID" || { log "CHYBA: neplatný argument VID:PID (očekávám tvar 1e0e:9001)"; exit 2; }
else
  if [[ -f "$VIDPID_FILE" && "$(stat -c %u "$VIDPID_FILE")" == "0" ]]; then
    VIDPID="$(head -n1 "$VIDPID_FILE" | tr -d '[:space:]')"
  fi
  if ! valid_vidpid "$VIDPID"; then
    [[ -z "$VIDPID" ]] || log "UPOZORNĚNÍ: $VIDPID_FILE má neplatný obsah — používám výchozí $DEFAULT_VIDPID"
    VIDPID="$DEFAULT_VIDPID"
  fi
fi
VIDPID="${VIDPID,,}"; VID="${VIDPID%%:*}"; PID="${VIDPID##*:}"

reset_device() {  # reset_device <sysfs jméno zařízení, např. 1-1.3>; vrací 0 při úspěchu
  local name="$1" dev="/sys/bus/usb/devices/$1"
  if [[ -e /sys/bus/usb/drivers/usb/unbind && -e /sys/bus/usb/drivers/usb/bind ]] \
     && echo "$name" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null; then
    sleep 3
    if echo "$name" > /sys/bus/usb/drivers/usb/bind 2>/dev/null; then
      log "unbind/bind $name OK"; return 0
    fi
    log "bind $name selhal — zkouším authorized"
  else
    log "unbind $name nedostupný — zkouším authorized"
  fi
  if [[ -w "$dev/authorized" ]]; then
    echo 0 > "$dev/authorized" 2>/dev/null || true
    sleep 3
    if echo 1 > "$dev/authorized" 2>/dev/null; then
      log "authorized 0/1 $name OK"; return 0
    fi
  fi
  log "reset $name selhal (unbind i authorized)"
  return 1
}

found=0; ok=0
for dev in /sys/bus/usb/devices/*; do
  [[ -f "$dev/idVendor" && -f "$dev/idProduct" ]] || continue
  [[ "$(cat "$dev/idVendor")" == "$VID" && "$(cat "$dev/idProduct")" == "$PID" ]] || continue
  found=$((found + 1))
  name="$(basename "$dev")"
  log "modem $VID:$PID nalezen jako $name ($(cat "$dev/product" 2>/dev/null || echo '?')) — reset"
  { mkdir -p -m 700 "$STATE_DIR" && echo "$name" > "$PORT_FILE"; } 2>/dev/null || true
  reset_device "$name" && ok=$((ok + 1)) || true
done

if (( found == 0 )); then
  # Modem zmizel ze sběrnice: zkusit jen jeho dřívější port (pokud tam ještě něco visí), nikdy celé USB.
  # Jméno portu se validuje (např. 1-1.3) — nikdy se neresetuje kořenový hub (usb1) apod.
  last="$(cat "$PORT_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
  [[ "$last" =~ ^[0-9]+-[0-9.]+$ ]] || last=""
  if [[ -n "$last" && -d "/sys/bus/usb/devices/$last" ]]; then
    log "modem $VID:$PID nenalezen — zkouším dřívější port $last"
    if reset_device "$last"; then sleep 10; exit 0; fi
  else
    log "modem $VID:$PID na USB nenalezen (dřívější port: ${last:-neznámý}) — bez zásahu, eskalace na reboot"
  fi
  exit 3
fi
# ── po resetu: počkat na re-enumeraci a PŘEKOPNOUT ModemManager ──────────────
# Ověřeno na pobočce (2026-09-20): po samotném unbind/bind ModemManager cdc-wdm0 neuchopí
# („unhandled port type") a spojí se náhradně přes PPP na ttyUSB2 — pomalé a nestabilní.
# Teprve restart MM ho nechá nasondovat QMI (primary port cdc-wdm0) a NM pak sám nahodí motogo-lte.
if (( ok == 0 )); then
  log "reset se nepovedl u žádné instance modemu"
  exit 1
fi

wait_for() {  # wait_for <sekundy> <popis> <příkaz…> — čeká, než příkaz uspěje
  local deadline=$(( SECONDS + $1 )) desc="$2"; shift 2
  while (( SECONDS < deadline )); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 1
  done
  log "UPOZORNĚNÍ: $desc se nedostavil do ${deadline} s"
  return 1
}

# 1) re-enumerace USB (cdc-wdm* nebo ttyUSB* — co se objeví dřív), max 20 s
wait_for 20 "re-enumerace modemu" bash -c 'compgen -G "/dev/cdc-wdm*" >/dev/null || compgen -G "/dev/ttyUSB*" >/dev/null' || true

# 2) restart ModemManageru — bez něj zůstane MM v PPP fallbacku
if command -v systemctl >/dev/null 2>&1; then
  if systemctl restart ModemManager 2>>"$LOG"; then
    log "ModemManager restartován"
  else
    log "UPOZORNĚNÍ: restart ModemManageru selhal"
  fi
fi

# 3) čekat, až MM modem uvidí (sondování trvá i ~45 s)
if command -v mmcli >/dev/null 2>&1; then
  if wait_for 60 "modem v ModemManageru" bash -c 'mmcli -L 2>/dev/null | grep -q Modem'; then
    port="$(mmcli -m any 2>/dev/null | grep -i 'primary port' | head -n1 | sed 's/.*: *//' | tr -d ' ')"
    log "ModemManager vidí modem, primary port: ${port:-?}"
    case "$port" in
      cdc-wdm*) : ;;   # QMI, správně
      "")       log "UPOZORNĚNÍ: primary port se nepodařilo zjistit" ;;
      *)        log "UPOZORNĚNÍ: primary port $port (ne cdc-wdm) — MM jede v PPP fallbacku, LTE bude pomalé" ;;
    esac
  else
    log "UPOZORNĚNÍ: ModemManager modem nenašel ani po 60 s"
  fi
fi
exit 0
