#!/usr/bin/env bash
# MotoGo Box — aplikuje LAN profil (eth0 statická 192.168.50.10/24, bez výchozí brány) — SPEC §4.
# Použití: sudo set-static-lan.sh [cesta k .nmconnection]   (výchozí /opt/motogo/systemd/motogo-lan.nmconnection)
# Postup: 1) profil do NM, 2) `nmcli connection up motogo-lan` — NM tím ATOMICKY nahradí aktivní profil
# na eth0 (typicky DHCP „Wired connection 1“), 3) konkurenčním profilům eth0 vypne autoconnect.
# Nikdy nevolá `connection down` aktivního profilu (eth0 by zůstalo bez adresy až do restartu).
# Přes SSH na eth0 spojení SPADNE (IP se změní na 192.168.50.10) — proto se skript sám odpojí od
# terminálu (setsid/nohup) a doběhne; výstup je v /var/log/motogo-set-static-lan.log.
# Nakonec ověří, že výchozí trasa NEVEDE přes eth0 (internet musí jít přes LTE).
set -euo pipefail

SRC="${1:-/opt/motogo/systemd/motogo-lan.nmconnection}"
DST="/etc/NetworkManager/system-connections/motogo-lan.nmconnection"
LAN_IP="192.168.50.10"
LOGF="/var/log/motogo-set-static-lan.log"

if [[ "$(id -u)" -ne 0 ]]; then echo "Spusť jako root (sudo)"; exit 2; fi
if ! command -v nmcli >/dev/null 2>&1; then echo "nmcli chybí — nainstaluj network-manager"; exit 2; fi
[[ -f "$SRC" ]] || { echo "Profil $SRC nenalezen"; exit 2; }

via_ssh() {  # je mezi předky sshd? (proměnné SSH_* sudo maže, proto strom procesů)
  local p=$PPID c
  while [[ -n "$p" && "$p" -gt 1 ]]; do
    c="$(ps -o comm= -p "$p" 2>/dev/null || true)"
    [[ "$c" == sshd* ]] && return 0
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ' || true)"
  done
  return 1
}
if [[ -z "${MOTOGO_LAN_DETACHED:-}" ]] && via_ssh; then
  echo "UPOZORNĚNÍ: běžíš přes SSH — eth0 dostane ${LAN_IP}/24, toto spojení nejspíš spadne."
  echo "Skript pokračuje na pozadí (log $LOGF); potom se připoj znovu: ssh <uživatel>@${LAN_IP}"
  : > "$LOGF"
  MOTOGO_LAN_DETACHED=1 setsid nohup "$0" "$@" >>"$LOGF" 2>&1 </dev/null &
  sleep 8; cat "$LOGF"
  grep -q '^OK: motogo-lan aktivní' "$LOGF" && exit 0 || exit 1
fi

install -m 600 -o root -g root "$SRC" "$DST"
nmcli connection reload
# 1) nový profil nahoru — NM nahradí aktivní profil na eth0 atomicky (bez mezistavu bez adresy)
nmcli connection up motogo-lan
sleep 2
# 2) jiné profily na eth0 (např. výchozí "Wired connection 1" s DHCP) by po restartu přinesly default route:
#    jen autoconnect=no, žádné `connection down` (aktivní už je motogo-lan).
while IFS=: read -r name uuid type device; do
  [[ "$type" == "802-3-ethernet" && "$name" != "motogo-lan" ]] || continue
  echo "Vypínám autoconnect u konkurenčního profilu eth0: $name"
  nmcli connection modify "$uuid" connection.autoconnect no || true
done < <(nmcli -t -f NAME,UUID,TYPE,DEVICE connection show)

echo "── eth0 ──"
ip -4 addr show dev eth0 | sed 's/^/  /'
echo "── trasy ──"
ip route | sed 's/^/  /'

if ! ip -4 addr show dev eth0 | grep -q "inet ${LAN_IP}/24"; then
  echo "CHYBA: eth0 nemá ${LAN_IP}/24"; exit 1
fi
if ip route | grep -E '^default' | grep -q 'dev eth0'; then
  echo "CHYBA: výchozí trasa vede přes eth0 — internet musí jít přes LTE (SPEC §4)"; exit 1
fi
if ip route | grep -qE '^default'; then
  echo "OK: výchozí trasa: $(ip route | grep -E '^default' | head -1)"
else
  echo "UPOZORNĚNÍ: žádná výchozí trasa (LTE ještě není připojené) — I/O síť ale funguje"
fi
echo "OK: motogo-lan aktivní, eth0 = ${LAN_IP}/24 bez výchozí brány"
