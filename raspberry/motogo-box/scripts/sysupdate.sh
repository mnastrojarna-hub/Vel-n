#!/usr/bin/env bash
# MotoGo Box — aktualizace operačního systému (Debian / Raspberry Pi OS): apt full-upgrade na pokyn
# Velína (příkaz `update_system` → `sudo /usr/local/sbin/motogo-sysupdate`, root-owned kopie tohoto
# skriptu; sudoers ho povoluje JEN bez argumentů) nebo ručně jako root.
#
# Bezpečnostní záplaty mezi tím instaluje unattended-upgrades sám (systemd/52motogo-unattended, v noci
# ve 4:00). Tento skript dělá ÚPLNÝ upgrade: apt-get update → full-upgrade (konfigurace balíků se
# nepřepisuje: --force-confdef/--force-confold) → autoremove --purge → clean.
# Skript NIKDY nerestartuje služby motogo-* ani systém — restart OS po novém jádru rozhoduje controller
# (auto_reboot z Velína, až je kóje volná). Žádné argumenty (ani od roota — vše je pevně dané).
# Výstup: poslední dva řádky jsou VŽDY `REBOOT_REQUIRED=0|1` (existuje /run/reboot-required) a
# `UPGRADED=<n>` (počet povýšených balíků z výstupu apt) — controller je parsuje.
# POZOR: Debian / Raspberry Pi OS soubor /run/reboot-required samy NIKDY nezakládají (píše ho jen ubuntí
# balík update-notifier-common, který v Debianu není) → příznak vytváří MotoGo: tento skript po
# full-upgrade (nové jádro v /lib/modules pro běžící variantu, nebo apt nastavil jádro / libc6 / libssl /
# systemd / dbus) a pro unattended-upgrades hook DPkg::Post-Invoke v systemd/52motogo-unattended.
# Stejný soubor čte health_probe (health.sys.reboot_required → Velín chip „Restart OS potřebný“).
# Log: /var/log/motogo-sysupdate.log (root-owned; symlink → /dev/null, do symlinku root nikdy nepíše).
# Návratové kódy: 0 OK, 2 chyba (root, argumenty, souběh, apt selhal — controller ohlásí selhání).
set -euo pipefail

LOG="/var/log/motogo-sysupdate.log"
LOCK="/run/lock/motogo-sysupdate.lock"
[[ -L "$LOG" ]] && LOG=/dev/null      # do symlinku root nikdy nepíše

log() {
  local msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
  echo "$msg"
  echo "$msg" >> "$LOG" 2>/dev/null || true
  command -v logger >/dev/null 2>&1 && logger -t motogo-sysupdate -- "$*" || true
}

if [[ "$(id -u)" -ne 0 ]]; then echo "Spusť jako root (sudo)"; exit 2; fi
if [[ $# -gt 0 ]]; then
  # Přes sudo od uživatele motogo se argumenty odmítají vždy; skript žádné nepřijímá ani od roota.
  log "CHYBA: motogo-sysupdate nepřijímá argumenty${SUDO_USER:+ (sudo od uživatele $SUDO_USER)}"; exit 2
fi
touch "$LOG" 2>/dev/null || true

# Jen jeden běh najednou (controller to hlídá také; pojistka pro ruční spuštění).
mkdir -p "$(dirname "$LOCK")" 2>/dev/null || true
exec 9>"$LOCK"
if ! flock -n 9; then log "CHYBA: motogo-sysupdate už běží"; exit 2; fi
# Spuštěno z controlleru (sudo) → běží v cgroupě motogo-controller.service; restart/pád služby (watchdog)
# by apt zabil uprostřed dpkg. Proto se skript znovu spustí ve vlastním transientním scope systemd
# (prostředí se dědí; zámek převezme nový běh). Bez systemd-run pokračuje na místě.
if [[ -z "${MOTOGO_SYSUPDATE_SCOPE:-}" ]] && command -v systemd-run >/dev/null 2>&1 \
   && systemd-run --scope --quiet --unit="motogo-sysupdate-probe-$$" true >/dev/null 2>&1; then
  export MOTOGO_SYSUPDATE_SCOPE=1
  flock -u 9; exec 9>&-
  exec systemd-run --scope --quiet --unit="motogo-sysupdate-$$" "$0"
fi

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C                      # souhrn apt v angličtině → spolehlivé parsování počtu balíků
export NEEDRESTART_MODE=l            # needrestart (je-li nainstalován) jen vypíše, nic nerestartuje
# DPkg::Lock::Timeout: počká, když zrovna běží unattended-upgrades (jinak by apt hned selhal).
APT_OPTS=(-y -q -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
TMP_OUT="$(mktemp /run/motogo-sysupdate.XXXXXX)"
trap 'rm -f "$TMP_OUT"' EXIT

os_name="$( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-?}" )"
log "=== sysupdate start ($os_name, jádro $(uname -r)) ==="

log "apt-get update"
if ! apt-get update -qq -o Acquire::Retries=3 -o DPkg::Lock::Timeout=600 2>&1 | tee -a "$LOG"; then
  log "CHYBA: apt-get update selhal (síť / zrcadlo) — nic se neinstaluje"; exit 2
fi

# `-q` (ne -qq): jen s ním apt vypíše souhrn „N upgraded, M newly installed, …“, z něhož se bere UPGRADED.
log "apt-get full-upgrade"
if ! apt-get "${APT_OPTS[@]}" full-upgrade 2>&1 | tee -a "$LOG" "$TMP_OUT" >/dev/null; then
  log "CHYBA: apt-get full-upgrade selhal — viz $LOG (dpkg --configure -a; apt-get -f install)"; exit 2
fi
upgraded="$(sed -n 's/^\([0-9]\+\) upgraded, [0-9]\+ newly installed.*/\1/p' "$TMP_OUT" | tail -n1)"
if [[ ! "$upgraded" =~ ^[0-9]+$ ]]; then
  upgraded="$(grep -c '^Setting up ' "$TMP_OUT" || true)"   # záloha: dpkg řádky
  [[ "$upgraded" =~ ^[0-9]+$ ]] || upgraded=0
fi

log "apt-get autoremove --purge + clean"
apt-get "${APT_OPTS[@]}" autoremove --purge 2>&1 | tee -a "$LOG" >/dev/null \
  || log "UPOZORNĚNÍ: autoremove selhal — pokračuji"
apt-get clean 2>&1 | tee -a "$LOG" >/dev/null || true

# Příznak restartu vytváří MotoGo (Debian ho sám nezakládá — viz hlavička): (a) v /lib/modules je pro běžící
# variantu jádra (přípona za poslední pomlčkou, např. rpi-2712 — RPi OS instaluje i -rpi-v8, proto se
# porovnává JEN stejná varianta) novější nainstalované jádro než uname -r; (b) apt právě nastavil balík
# jádra / libc6 / libssl / systemd / dbus. Ne-pravdivé → soubor zůstává, jak byl (mohl vzniknout dřív).
running="$(uname -r)"; flavour="${running##*-}"
newest_kernel="$(ls -d /lib/modules/*-"$flavour"/modules.dep 2>/dev/null \
                 | sed 's|^/lib/modules/||; s|/modules.dep$||' | sort -V | tail -n1 || true)"
reboot_pkgs="$(awk '$1=="Setting" && $2=="up" && $3 ~ /^(linux-image-|raspberrypi-kernel|libc6($|:)|libssl[0-9]|systemd($|:)|dbus($|:))/ {print $3}' \
               "$TMP_OUT" 2>/dev/null | sort -u | tr '\n' ' ' || true)"
need_reboot=""
[[ -n "$newest_kernel" && "$newest_kernel" != "$running" ]] && need_reboot="linux-image-$newest_kernel"
[[ -n "$reboot_pkgs" ]] && need_reboot="${need_reboot:+$need_reboot }${reboot_pkgs% }"
if [[ -n "$need_reboot" ]]; then
  touch /run/reboot-required 2>/dev/null || true
  tr ' ' '\n' <<<"$need_reboot" >> /run/reboot-required.pkgs 2>/dev/null || true
  [[ -n "$newest_kernel" && "$newest_kernel" != "$running" ]] && log "nové jádro $newest_kernel (běží $running)"
fi

reboot_required=0
if [[ -e /run/reboot-required ]]; then
  reboot_required=1
  pkgs="$(tr '\n' ' ' < /run/reboot-required.pkgs 2>/dev/null | cut -c1-200 || true)"
  log "restart OS potřebný (nové jádro / knihovny)${pkgs:+: $pkgs} — rozhodne controller / Velín, skript nerestartuje"
fi
log "=== sysupdate hotov: povýšeno $upgraded balíků, reboot_required=$reboot_required ==="
echo "REBOOT_REQUIRED=$reboot_required"
echo "UPGRADED=$upgraded"
exit 0
