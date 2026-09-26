#!/usr/bin/env bash
# MotoGo Box — přepnutí modemu SIM7600E-H mezi režimy QMI a RNDIS (jedním příkazem, idempotentně).
# Instaluje se jako /usr/local/sbin/motogo-lte-mode (root-owned; sudoers povoluje JEN `rndis`, `qmi`, `status`).
# Spouští ho: health monitor SÁM (≥ `rndis_auto_after` USB resetů za 24 h → rndis; RNDIS bez internetu
# ≥ `rndis_revert_after_s` → zpět qmi) a příkaz `lte_mode` z Velína (tlačítka na kartě jednotky).
#
# Proč: SIM7600 na QMI kanálu (qmi_wwan/cdc-wdm0) padá z USB (`Unexpected error -71`, á 10–15 min,
# HARDWARE.md). V RNDIS je modem obyčejná síťová karta usb0 s DHCP od modemu — qmi_wwan se nepoužije vůbec.
#
#   motogo-lte-mode rndis   — záloha QMI profilu → RNDIS profil `motogo-lte` (usb0), udev, služba startu
#                              datového spojení, modem_vidpid 1e0e:9011, health.lte_mode: rndis, ModemManager
#                              vypnout, AT+CUSBPIDSWITCH=9011, počkat na re-enumeraci, start dat, nahodit profil
#   motogo-lte-mode qmi     — přesný opak (obnoví zálohovaný QMI profil, ModemManager zapnout, PID 9001)
#   motogo-lte-mode status  — režim v config.yaml, PID modemu na USB, typ profilu, rozhraní a výchozí trasa
# Na konci (rndis/qmi) se odloženě restartuje motogo-health (čte config při startu) — přes systemd-run,
# aby restart nezabil volajícího (health sám tento skript spouští přes sudo).
set -euo pipefail

APP_DIR="/opt/motogo"
ETC_DIR="/etc/motogo"
CFG="$ETC_DIR/config.yaml"
NM_DIR="/etc/NetworkManager/system-connections"
PROF="$NM_DIR/motogo-lte.nmconnection"
QMI_BACKUP="$ETC_DIR/motogo-lte.qmi.nmconnection"
APN_FILE="$ETC_DIR/apn"
VIDPID_FILE="$ETC_DIR/modem_vidpid"
RNDIS_BIN="/usr/local/sbin/motogo-lte-rndis"
UDEV_RULE="99-motogo-lte-rndis.rules"
RNDIS_SVC="motogo-lte-rndis.service"
VID="1e0e"; PID_QMI="9001"; PID_RNDIS="9011"
LOG="/var/log/motogo-lte-mode.log"
[[ -L "$LOG" ]] && LOG=/dev/null

log() {
  local msg; msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
  echo "$msg"; echo "$msg" >> "$LOG" 2>/dev/null || true
  command -v logger >/dev/null 2>&1 && logger -t motogo-lte-mode -- "$*" || true
}
[[ "$(id -u)" -eq 0 ]] || { log "CHYBA: potřebuje root"; exit 2; }

usb_pid_present() {  # usb_pid_present <pid> — modem s daným PID je na USB
  local d
  for d in /sys/bus/usb/devices/*; do
    [[ -f "$d/idVendor" && -f "$d/idProduct" ]] || continue
    [[ "$(cat "$d/idVendor")" == "$VID" && "$(cat "$d/idProduct")" == "$1" ]] && return 0
  done
  return 1
}
usb_mode() { usb_pid_present "$PID_RNDIS" && echo rndis || { usb_pid_present "$PID_QMI" && echo qmi || echo none; }; }
cfg_mode() { grep -E '^[[:space:]]+lte_mode:' "$CFG" 2>/dev/null | head -n1 | sed -E 's/.*lte_mode:[[:space:]]*//; s/[#].*//; s/["'"'"' ]//g' | tr 'A-Z' 'a-z' || true; }
prof_type() { grep -E '^type=' "$PROF" 2>/dev/null | head -n1 | cut -d= -f2 || true; }

wait_for() {  # wait_for <s> <popis> <příkaz…>
  local limit="$1" desc="$2"; shift 2
  local deadline=$(( SECONDS + limit ))
  while (( SECONDS < deadline )); do "$@" >/dev/null 2>&1 && return 0; sleep 2; done
  log "UPOZORNĚNÍ: $desc se nedostavil do ${limit} s"; return 1
}

set_cfg() {  # set_cfg <lte_mode> <vid:pid> — přepíše/doplní klíče v sekci health: config.yaml (komentáře zůstávají)
  local mode="$1" vidpid="$2" py="$APP_DIR/venv/bin/python"
  [[ -x "$py" ]] || py="python3"
  [[ -f "$CFG" ]] || { log "UPOZORNĚNÍ: $CFG neexistuje — health.lte_mode nenastaveno"; return 1; }
  cp -a "$CFG" "$CFG.bak-ltemode" 2>/dev/null || true
  "$py" - "$CFG" "$mode" "$vidpid" <<'PY'
import re, sys
path, mode, vidpid = sys.argv[1:4]
lines = open(path, encoding="utf-8").read().splitlines()
want = {"lte_mode": mode, "modem_vid_pid": f'"{vidpid}"'}
out, in_health, done = [], False, set()
for ln in lines:
    top = re.match(r"^([A-Za-z_][\w]*):", ln)
    if top:
        if in_health:
            for k, v in want.items():
                if k not in done:
                    out.append(f"  {k}: {v}"); done.add(k)
        in_health = top.group(1) == "health"
    elif in_health:
        m = re.match(r"^(\s+)(lte_mode|modem_vid_pid):", ln)
        if m and m.group(2) in want:
            ln = f"{m.group(1)}{m.group(2)}: {want[m.group(2)]}"; done.add(m.group(2))
    out.append(ln)
if in_health:
    for k, v in want.items():
        if k not in done:
            out.append(f"  {k}: {v}"); done.add(k)
if not done:
    out += ["", "health:"] + [f"  {k}: {v}" for k, v in want.items()]
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
  log "config.yaml: health.lte_mode: $mode, health.modem_vid_pid: $vidpid"
}

restart_health_later() {
  # controller čte health cfg jen pro diagnostiku; health ji drží od startu → restart až po doběhu skriptu
  if command -v systemd-run >/dev/null 2>&1; then
    systemd-run --quiet --no-block --on-active=5 --unit "motogo-lte-mode-restart-$$" \
      systemctl restart motogo-health && log "motogo-health se restartuje za 5 s (nový režim)" && return 0
  fi
  setsid bash -c 'sleep 5; systemctl restart motogo-health' >/dev/null 2>&1 < /dev/null &
  log "motogo-health se restartuje za 5 s (nový režim, fallback)"
}

to_rndis() {
  log "=== přepnutí modemu do RNDIS (USB: $(usb_mode), config: ${1:-?}, profil: $(prof_type)) ==="
  [[ -x "$RNDIS_BIN" ]] || { log "CHYBA: chybí $RNDIS_BIN (update.sh ho instaluje)"; exit 4; }
  # 1) záloha QMI profilu + APN (RNDIS start posílá AT+CGDCONT s tímhle APN)
  if [[ "$(prof_type)" == "gsm" ]]; then
    install -m 600 -o root -g root "$PROF" "$QMI_BACKUP"; log "QMI profil zálohován → $QMI_BACKUP"
  fi
  local apn=""
  [[ -f "$QMI_BACKUP" ]] && apn="$(grep -E '^apn=' "$QMI_BACKUP" | head -n1 | cut -d= -f2- || true)"
  [[ -z "$apn" && -f "$APN_FILE" ]] && apn="$(cat "$APN_FILE")"
  [[ -n "$apn" ]] && { printf '%s\n' "$apn" > "$APN_FILE"; chmod 644 "$APN_FILE"; log "APN: $apn → $APN_FILE"; }
  # 2) RNDIS profil pod stejným jménem motogo-lte (health/sudoers/terminál nic dalšího neřeší), udev, služba
  install -m 600 -o root -g root "$APP_DIR/systemd/motogo-lte-rndis.nmconnection" "$PROF"
  install -m 644 -o root -g root "$APP_DIR/systemd/$UDEV_RULE" "/etc/udev/rules.d/$UDEV_RULE"
  udevadm control --reload >/dev/null 2>&1 || true
  install -m 644 -o root -g root "$APP_DIR/systemd/$RNDIS_SVC" "/etc/systemd/system/$RNDIS_SVC"
  systemctl daemon-reload; systemctl enable "$RNDIS_SVC" >/dev/null 2>&1 || true
  printf '%s:%s\n' "$VID" "$PID_RNDIS" > "$VIDPID_FILE"; chmod 644 "$VIDPID_FILE"
  set_cfg rndis "$VID:$PID_RNDIS" || true
  # 3) ModemManager pryč — v RNDIS by se AT portů chytal a rušil datové spojení (usbreset-modem.sh s tím počítá)
  systemctl disable --now ModemManager >/dev/null 2>&1 && log "ModemManager vypnut" || true
  nmcli con reload >/dev/null 2>&1 || true
  # 4) modem přepnout (sám se restartuje ~30–40 s) a počkat na PID 9011
  if usb_pid_present "$PID_RNDIS"; then
    log "modem už je v RNDIS (PID $PID_RNDIS)"
  else
    "$RNDIS_BIN" enable || log "UPOZORNĚNÍ: AT přepnutí selhalo (AT port neodpověděl?) — zkusím počkat na PID $PID_RNDIS"
    wait_for 90 "modem s PID $PID_RNDIS na USB" usb_pid_present "$PID_RNDIS" || true
    sleep 5
  fi
  # 5) datové spojení + profil
  "$RNDIS_BIN" start || log "UPOZORNĚNÍ: start datového spojení selhal (služba $RNDIS_SVC to zkusí po bootu)"
  nmcli -w 30 con up motogo-lte >/dev/null 2>&1 && log "profil motogo-lte (RNDIS/usb0) nahozen" \
    || log "UPOZORNĚNÍ: nmcli con up motogo-lte selhal — NM ho zkusí sám (autoconnect)"
  log "=== hotovo: RNDIS (USB: $(usb_mode)); trasa: $(ip route 2>/dev/null | grep -E '^default' | tr '\n' ';' || true) ==="
  restart_health_later
}

to_qmi() {
  log "=== návrat modemu do QMI (USB: $(usb_mode), config: ${1:-?}, profil: $(prof_type)) ==="
  if usb_pid_present "$PID_QMI"; then
    log "modem už je v QMI (PID $PID_QMI)"
  elif [[ -x "$RNDIS_BIN" ]]; then
    "$RNDIS_BIN" disable || log "UPOZORNĚNÍ: AT přepnutí zpět selhalo — zkusím počkat na PID $PID_QMI"
  fi
  # profil: záloha, jinak šablona z repa s uloženým APN
  if [[ -f "$QMI_BACKUP" ]]; then
    install -m 600 -o root -g root "$QMI_BACKUP" "$PROF"; log "QMI profil obnoven ze zálohy"
  else
    local apn="internet"; [[ -f "$APN_FILE" ]] && apn="$(cat "$APN_FILE")"
    sed "s|^apn=.*|apn=${apn}|" "$APP_DIR/systemd/motogo-lte.nmconnection" > "$PROF"; chmod 600 "$PROF"
    log "QMI profil vytvořen ze šablony (APN $apn) — bez zálohy: PIN SIM případně doplň (install.sh)"
  fi
  systemctl disable --now "$RNDIS_SVC" >/dev/null 2>&1 || true
  rm -f "/etc/udev/rules.d/$UDEV_RULE"; udevadm control --reload >/dev/null 2>&1 || true
  printf '%s:%s\n' "$VID" "$PID_QMI" > "$VIDPID_FILE"; chmod 644 "$VIDPID_FILE"
  set_cfg qmi "$VID:$PID_QMI" || true
  wait_for 90 "modem s PID $PID_QMI na USB" usb_pid_present "$PID_QMI" || true
  sleep 5
  systemctl enable --now ModemManager >/dev/null 2>&1 && log "ModemManager zapnut" || true
  nmcli con reload >/dev/null 2>&1 || true
  wait_for 60 "modem v ModemManageru" bash -c 'mmcli -L 2>/dev/null | grep -q Modem' || true
  nmcli -w 30 con up motogo-lte >/dev/null 2>&1 && log "profil motogo-lte (QMI) nahozen" \
    || log "UPOZORNĚNÍ: nmcli con up motogo-lte selhal — NM ho zkusí sám (autoconnect)"
  log "=== hotovo: QMI (USB: $(usb_mode)); trasa: $(ip route 2>/dev/null | grep -E '^default' | tr '\n' ';' || true) ==="
  restart_health_later
}

case "${1:-}" in
  status)
    echo "config: $(cfg_mode)"; echo "usb: $(usb_mode)"; echo "profile: $(prof_type)"
    echo "modem_vidpid: $(cat "$VIDPID_FILE" 2>/dev/null || echo '?')"
    echo "ModemManager: $(systemctl is-active ModemManager 2>/dev/null || true)"
    ip -br addr show 2>/dev/null | grep -E '^(wwan|usb)' || true
    ip route 2>/dev/null | grep -E '^default' || echo "default route: none"
    ;;
  rndis) to_rndis "$(cfg_mode)" ;;
  qmi)   to_qmi   "$(cfg_mode)" ;;
  *) echo "Použití: $0 {rndis|qmi|status}" >&2; exit 1 ;;
esac
