#!/usr/bin/env bash
# MotoGo Box — USB reset LTE modemu (SIM7600E-H, VID:PID 1e0e:9001). Volá health monitor
# přes sudo (/usr/local/sbin/motogo-usbreset — root-owned kopie), když opakované reconnecty nepomohly.
# Postup: najde zařízení v /sys/bus/usb/devices podle idVendor/idProduct, unbind + bind
# přes /sys/bus/usb/drivers/usb; záloha: authorized 0/1 JEN na tom zařízení (vynutí re-enumeraci).
# Modem, který na sběrnici vůbec není, se NEřeší resetem celé USB (odpojilo by to dotyk EDATEC
# a USB zvukovou kartu) — skript skončí kódem 3 a politika health eskaluje na reboot.
# Použití: usbreset-modem.sh [VID:PID]   (výchozí 1e0e:9001)
set -euo pipefail

VIDPID="${1:-1e0e:9001}"
VID="${VIDPID%%:*}"; PID="${VIDPID##*:}"
LOG="/var/log/motogo-usbreset.log"
PORT_FILE="/var/lib/motogo/modem-port"     # sysfs jméno portu modemu z posledního úspěšného nálezu

log() {
  local msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
  echo "$msg"
  echo "$msg" >> "$LOG" 2>/dev/null || true
  command -v logger >/dev/null 2>&1 && logger -t motogo-usbreset -- "$*" || true
}

if [[ "$(id -u)" -ne 0 ]]; then
  log "CHYBA: skript potřebuje root (sudo)"; exit 2
fi
if [[ ! "$VID" =~ ^[0-9a-fA-F]{4}$ || ! "$PID" =~ ^[0-9a-fA-F]{4}$ ]]; then
  log "CHYBA: neplatné VID:PID '$VIDPID' (očekávám např. 1e0e:9001)"; exit 2
fi
VID="${VID,,}"; PID="${PID,,}"

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
  { mkdir -p "$(dirname "$PORT_FILE")" && echo "$name" > "$PORT_FILE"; } 2>/dev/null || true
  reset_device "$name" && ok=$((ok + 1)) || true
done

if (( found == 0 )); then
  # Modem zmizel ze sběrnice: zkusit jen jeho dřívější port (pokud tam ještě něco visí), nikdy celé USB.
  last="$(cat "$PORT_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ -n "$last" && -d "/sys/bus/usb/devices/$last" ]]; then
    log "modem $VID:$PID nenalezen — zkouším dřívější port $last"
    if reset_device "$last"; then sleep 10; exit 0; fi
  else
    log "modem $VID:$PID na USB nenalezen (dřívější port: ${last:-neznámý}) — bez zásahu, eskalace na reboot"
  fi
  exit 3
fi
# Modem se po resetu znovu enumeruje ~10–20 s; ModemManager + NM (autoconnect) LTE obnoví sami.
sleep 10
if command -v mmcli >/dev/null 2>&1; then
  log "stav ModemManageru: $(mmcli -L 2>&1 | tr -s ' \n' ' ' | cut -c1-160)"
fi
(( ok > 0 )) && exit 0 || exit 1
