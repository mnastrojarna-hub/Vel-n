#!/usr/bin/env bash
# MotoGo Box — aplikuje LAN profil (eth0 statická 192.168.50.10/24, bez výchozí brány) — SPEC §4.
# Použití: sudo set-static-lan.sh [cesta k .nmconnection]   (výchozí /opt/motogo/systemd/motogo-lan.nmconnection)
# Po aplikaci ověří, že výchozí trasa NEVEDE přes eth0 (internet musí jít přes LTE).
set -euo pipefail

SRC="${1:-/opt/motogo/systemd/motogo-lan.nmconnection}"
DST="/etc/NetworkManager/system-connections/motogo-lan.nmconnection"
LAN_IP="192.168.50.10"

if [[ "$(id -u)" -ne 0 ]]; then echo "Spusť jako root (sudo)"; exit 2; fi
if ! command -v nmcli >/dev/null 2>&1; then echo "nmcli chybí — nainstaluj network-manager"; exit 2; fi
[[ -f "$SRC" ]] || { echo "Profil $SRC nenalezen"; exit 2; }

install -m 600 -o root -g root "$SRC" "$DST"
nmcli connection reload
# Případné jiné profily na eth0 (např. výchozí "Wired connection 1" s DHCP) by přinesly default route.
while IFS=: read -r name uuid type device; do
  [[ "$type" == "802-3-ethernet" && "$name" != "motogo-lan" ]] || continue
  echo "Vypínám autoconnect u konkurenčního profilu eth0: $name"
  nmcli connection modify "$uuid" connection.autoconnect no || true
  nmcli connection down "$uuid" >/dev/null 2>&1 || true
done < <(nmcli -t -f NAME,UUID,TYPE,DEVICE connection show)

nmcli connection up motogo-lan
sleep 2

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
