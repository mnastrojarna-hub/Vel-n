#!/usr/bin/env bash
# MotoGo Box — přepnutí SIM7600E-H mezi QMI a RNDIS + start datového spojení (AT příkazy).
#
# ⚠ NEOTESTOVÁNO NA HARDWARU — určeno k ověření na DEV Pi, ne na pobočce. Do install.sh
# ani do update.sh se nic z toho nezapojuje; dokud se režim `rndis` ručně nezapne
# (`health.lte_mode: rndis` v /etc/motogo/config.yaml), jednotka jede dál přes QMI.
#
# Proč: SIM7600E-H na pobočce opakovaně zamrzá na QMI kanálu (`qmi_wwan … Unexpected error -71`
# á 10–15 min, viz HARDWARE.md). Hypotéza „vadný port/kabel/řadič" byla vyloučena přepojením
# na jiný řadič (3-2) — chyba přišla znovu. RNDIS obchází qmi_wwan úplně: modem se tváří jako
# síťová karta (usb0) s DHCP od modemu.
#
# Použití (jako root):
#   lte-rndis.sh probe     — najde AT port a vypíše aktuální režim, operátora a signál
#   lte-rndis.sh enable    — přepne na RNDIS (PID 9011) — modem se sám restartuje
#   lte-rndis.sh disable   — zpět na QMI (PID 9001)
#   lte-rndis.sh start     — spustí datové spojení (AT$QCRMCALL=1,1), jen v RNDIS
#   lte-rndis.sh status    — stav rozhraní usb0 + výchozí trasa
#
# AT port: /dev/motogo-lte-at (udev pravidlo 99-motogo-lte-rndis.rules), jinak se zkouší
# /dev/ttyUSB2 … /dev/ttyUSB0 — na dev Pi OVĚŘIT, který port odpovídá na `AT`.
set -euo pipefail

LOG="/var/log/motogo-lte-rndis.log"
[[ -L "$LOG" ]] && LOG=/dev/null
CANDIDATES=(/dev/motogo-lte-at /dev/ttyUSB2 /dev/ttyUSB3 /dev/ttyUSB1 /dev/ttyUSB0)
IFACE="${MOTOGO_RNDIS_IFACE:-usb0}"
AT_WAIT=3            # sekund na odpověď modemu

log() {
  local msg
  msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
  echo "$msg"
  echo "$msg" >> "$LOG" 2>/dev/null || true
}
[[ "$(id -u)" -eq 0 ]] || { log "CHYBA: potřebuje root"; exit 2; }

at_send() {  # at_send <port> <příkaz> — pošle AT příkaz a vypíše odpověď
  local port="$1" cmd="$2"
  exec 3<>"$port" || return 1
  printf '%s\r' "$cmd" >&3
  timeout "$AT_WAIT" cat <&3 &
  local reader=$!
  sleep "$AT_WAIT"
  kill "$reader" 2>/dev/null || true
  exec 3<&- 3>&- || true
}

find_at_port() {
  local port
  for port in "${CANDIDATES[@]}"; do
    [[ -c "$port" ]] || continue
    if at_send "$port" "AT" 2>/dev/null | grep -q "OK"; then
      echo "$port"; return 0
    fi
  done
  return 1
}

port_or_die() {
  local port
  port="$(find_at_port)" || { log "CHYBA: žádný AT port neodpověděl (zkoušeno: ${CANDIDATES[*]})"; exit 3; }
  log "AT port: $port"
  echo "$port"
}

case "${1:-}" in
  probe)
    port="$(port_or_die)"
    for cmd in "AT+CUSBPIDSWITCH?" "AT+CPSI?" "AT+COPS?" "AT+CSQ" "AT+CSCLK?"; do
      log "$cmd → $(at_send "$port" "$cmd" | tr -s '\r\n' ' ')"
    done
    ;;
  enable)
    port="$(port_or_die)"
    log "přepínám modem do RNDIS (PID 9011) — modem se restartuje, potrvá ~30 s"
    at_send "$port" "AT+CUSBPIDSWITCH=9011,1,1" | tr -s '\r\n' ' ' | while read -r l; do log "odpověď: $l"; done
    log "hotovo — po re-enumeraci zkontroluj: ip -br addr show $IFACE ; lsusb | grep 1e0e"
    log "POZOR: NM profil motogo-lte musí být pro RNDIS typu ethernet na $IFACE (systemd/motogo-lte-rndis.nmconnection)"
    ;;
  disable)
    port="$(port_or_die)"
    log "vracím modem do QMI (PID 9001)"
    at_send "$port" "AT+CUSBPIDSWITCH=9001,1,1" | tr -s '\r\n' ' ' | while read -r l; do log "odpověď: $l"; done
    ;;
  start)
    port="$(port_or_die)"
    log "startuji datové spojení (AT\$QCRMCALL=1,1)"
    at_send "$port" 'AT$QCRMCALL=1,1' | tr -s '\r\n' ' ' | while read -r l; do log "odpověď: $l"; done
    sleep 5
    ip -br addr show "$IFACE" 2>/dev/null | while read -r l; do log "$IFACE: $l"; done
    ;;
  status)
    ip -br addr show "$IFACE" 2>/dev/null | while read -r l; do log "$IFACE: $l"; done
    ip route | grep -E "^default" | while read -r l; do log "trasa: $l"; done
    ;;
  *)
    echo "Použití: $0 {probe|enable|disable|start|status}" >&2
    exit 1
    ;;
esac
