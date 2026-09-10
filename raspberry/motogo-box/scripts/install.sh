#!/usr/bin/env bash
# MotoGo Box — instalace na Raspberry Pi OS Bookworm 64-bit (Lite). Idempotentní: lze
# spouštět opakovaně, existující konfigurace (/etc/motogo/*.yaml, NM profily) nepřepisuje.
#
# Použití (z rozbaleného adresáře raspberry/motogo-box):
#   sudo ./scripts/install.sh
# Volitelné proměnné prostředí (jinak se instalátor ptá interaktivně, pokud má terminál):
#   MOTOGO_DEVICE_ID=<uuid>  MOTOGO_DEVICE_TOKEN=<uuid>  MOTOGO_APN=internet.t-mobile.cz
#   MOTOGO_DIAG_CODE=<kód>  (kód pro diagnostiku sítě z displeje; výchozí netdiag)
#   MOTOGO_SKIP_APT=1 (přeskočí apt), MOTOGO_NO_START=1 (na konci služby nespouští)
set -euo pipefail

APP_DIR="/opt/motogo"
ETC_DIR="/etc/motogo"
DATA_DIR="/var/lib/motogo"
APP_USER="motogo"
APP_GROUPS="audio,video,input,render,dialout,plugdev,netdev"
NM_DIR="/etc/NetworkManager/system-connections"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APT_PKGS=(python3 python3-venv python3-pip git mpv cage chromium network-manager modemmanager
          alsa-utils rsync curl usbutils fonts-dejavu fonts-noto-color-emoji)

step() { echo; echo "──── $* ────"; }
ok()   { echo "  ✔ $*"; }
warn() { echo "  ! $*"; }
die()  { echo "CHYBA: $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "spusť jako root: sudo $0"
[[ -f "$SRC_DIR/motogo_box/__main__.py" ]] || die "spouštěj ze složky raspberry/motogo-box (nenalezen motogo_box/)"
if [[ "$(uname -m)" != "aarch64" ]]; then warn "architektura $(uname -m) — očekáváno aarch64 (Raspberry Pi OS 64-bit)"; fi
if ! grep -qi bookworm /etc/os-release 2>/dev/null; then warn "OS není Bookworm — balíčky (chromium, cage) se mohou lišit"; fi

INTERACTIVE=0; [[ -t 0 && -t 1 ]] && INTERACTIVE=1
ask() {  # ask VAR "Popis" [default] — jen když proměnná není v env a je terminál
  local var="$1" prompt="$2" def="${3:-}" val
  if [[ -n "${!var:-}" ]]; then return 0; fi
  if (( INTERACTIVE )); then
    read -r -p "  $prompt${def:+ [$def]}: " val || true
    printf -v "$var" '%s' "${val:-$def}"
  else
    printf -v "$var" '%s' "$def"
  fi
}

# ── 1. balíčky ─────────────────────────────────────────────────────────────────
step "1/12 Balíčky (apt)"
if [[ "${MOTOGO_SKIP_APT:-0}" == "1" ]]; then
  warn "apt přeskočen (MOTOGO_SKIP_APT=1)"
else
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends "${APT_PKGS[@]}"
  ok "nainstalováno: ${APT_PKGS[*]}"
fi
command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1 || warn "chromium nenalezeno — UI nepoběží"

# ── 2. uživatel ────────────────────────────────────────────────────────────────
step "2/12 Uživatel $APP_USER"
if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "/home/$APP_USER" --shell /usr/sbin/nologin "$APP_USER"
  ok "uživatel vytvořen"
fi
for g in ${APP_GROUPS//,/ }; do getent group "$g" >/dev/null || groupadd "$g"; done
usermod -a -G "$APP_GROUPS" "$APP_USER"
ok "skupiny: $APP_GROUPS"

# ── 3. kopie programu do /opt/motogo ──────────────────────────────────────────
step "3/12 Program → $APP_DIR"
mkdir -p "$APP_DIR"
if [[ "$SRC_DIR" == "$APP_DIR" ]]; then
  ok "instaluji přímo z $APP_DIR (bez kopie)"
else
  rsync -a --delete --exclude venv --exclude '__pycache__' --exclude '.pytest_cache' "$SRC_DIR"/ "$APP_DIR"/
  ok "zkopírováno z $SRC_DIR"
fi
chmod 755 "$APP_DIR"/scripts/*.sh
# Program vlastní root (uživatel motogo jen čte) — skripty spouštěné přes sudo nesmí být zapisovatelné
# procesem controlleru. Zapisovat smí motogo jen do venv (pip) a do /var/lib/motogo.
chown -R root:root "$APP_DIR"; chmod -R a+rX "$APP_DIR"
# root-owned kopie skriptů pro sudo (viz systemd/motogo-sudoers)
install -m 755 -o root -g root "$APP_DIR/scripts/update.sh"         /usr/local/sbin/motogo-update
install -m 755 -o root -g root "$APP_DIR/scripts/usbreset-modem.sh" /usr/local/sbin/motogo-usbreset
ok "sudo skripty: /usr/local/sbin/motogo-update, /usr/local/sbin/motogo-usbreset (root:root)"
# Zdroj pro budoucí aktualizace (update.sh / příkaz update_software z Velína)
mkdir -p "$ETC_DIR"
if [[ "$SRC_DIR" != "$APP_DIR" ]]; then
  echo "$SRC_DIR" > "$ETC_DIR/source_dir"
  if git -C "$SRC_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git config --global --add safe.directory "$(git -C "$SRC_DIR" rev-parse --show-toplevel)" >/dev/null 2>&1 || true
    ok "zdroj aktualizací: $SRC_DIR (git checkout → update = git pull + rsync)"
  else
    ok "zdroj aktualizací: $SRC_DIR (bez gitu → update = rsync; nový balík rozbal na stejné místo)"
  fi
else
  warn "instaluješ přímo z $APP_DIR — vzdálený update_software nebude mít odkud brát novou verzi (zadej ho ručně: motogo-update /cesta)"
fi

# ── 4. venv + závislosti ──────────────────────────────────────────────────────
step "4/12 Python venv"
if [[ ! -x "$APP_DIR/venv/bin/python" ]]; then
  mkdir -p "$APP_DIR/venv"; chown "$APP_USER:$APP_USER" "$APP_DIR/venv"
  sudo -u "$APP_USER" python3 -m venv "$APP_DIR/venv"
  ok "venv vytvořen"
fi
chown -R "$APP_USER:$APP_USER" "$APP_DIR/venv"
sudo -u "$APP_USER" "$APP_DIR/venv/bin/pip" install --quiet --upgrade pip
sudo -u "$APP_USER" "$APP_DIR/venv/bin/pip" install --quiet -r "$APP_DIR/requirements.txt"
app_version() { (cd "$APP_DIR" && "$APP_DIR/venv/bin/python" -m motogo_box version 2>/dev/null) || echo '?'; }
ok "requirements nainstalovány ($(app_version))"

# ── 5. konfigurace /etc/motogo ────────────────────────────────────────────────
step "5/12 Konfigurace $ETC_DIR"
mkdir -p "$ETC_DIR"
ask MOTOGO_APN "APN operátora (např. internet.t-mobile.cz, internet, ointernet)" "internet"
if [[ -f "$ETC_DIR/config.yaml" ]]; then
  ok "config.yaml existuje — ponechán (ID/token lze změnit v UI → Přepárovat)"
else
  echo "  Párování zařízení: ID + token vytvoříš ve Velíně → Pobočky → Samoobsluha → Řídicí jednotka (Raspberry)."
  echo "  (Lze nechat prázdné a spárovat později z dotykového UI.)"
  ask MOTOGO_DEVICE_ID "DEVICE_ID (uuid)" ""
  ask MOTOGO_DEVICE_TOKEN "DEVICE_TOKEN (uuid)" ""
  cp "$APP_DIR/config/config.example.yaml" "$ETC_DIR/config.yaml"
  sed -i "s|^  id: \"\"|  id: \"${MOTOGO_DEVICE_ID}\"|; s|^  token: \"\"|  token: \"${MOTOGO_DEVICE_TOKEN}\"|" "$ETC_DIR/config.yaml"
  ok "config.yaml vytvořen z config.example.yaml"
fi
# Diagnostický kód: zadáním na displeji (i před spárováním) se spustí kompletní diagnostika sítě
# (rozhraní, LTE, internet, Velín, scan LAN, identifikace Waveshare/Shelly) — zobrazí se a odešle do Velína.
echo "  Diagnostika sítě: kód, který zadáš na displeji (hlavní klávesnice nebo setup → „Diagnostika sítě“)."
ask MOTOGO_DIAG_CODE "Diagnostický kód" "netdiag"
if grep -q '^diagnostics:' "$ETC_DIR/config.yaml"; then
  sed -i "/^diagnostics:/,/^[a-z_]*:/ s|^  code: .*|  code: \"${MOTOGO_DIAG_CODE}\"|" "$ETC_DIR/config.yaml"
else
  printf '\ndiagnostics:\n  code: "%s"\n' "${MOTOGO_DIAG_CODE}" >> "$ETC_DIR/config.yaml"
fi
ok "diagnostický kód nastaven (diagnostics.code)"
chown root:"$APP_USER" "$ETC_DIR/config.yaml"; chmod 640 "$ETC_DIR/config.yaml"   # obsahuje token
if [[ -f "$ETC_DIR/hardware.yaml" ]]; then
  ok "hardware.yaml existuje — ponechán (Velín má přednost)"
else
  install -m 644 "$APP_DIR/config/brno-9zone.yaml" "$ETC_DIR/hardware.yaml"
  ok "hardware.yaml = výchozí mapa Brno 9 zón"
fi
if (cd "$APP_DIR" && "$APP_DIR/venv/bin/python" -m motogo_box check-config "$ETC_DIR/hardware.yaml" >/dev/null); then
  ok "hardware.yaml je konzistentní"
else
  warn "hardware.yaml má problémy — spusť: cd $APP_DIR && venv/bin/python -m motogo_box check-config $ETC_DIR/hardware.yaml"
fi

# ── 6. data ────────────────────────────────────────────────────────────────────
step "6/12 Data $DATA_DIR"
mkdir -p "$DATA_DIR/music"
chown -R "$APP_USER:$APP_USER" "$DATA_DIR"; chmod 750 "$DATA_DIR"
touch /var/log/motogo-update.log /var/log/motogo-usbreset.log
chown "$APP_USER:$APP_USER" /var/log/motogo-update.log /var/log/motogo-usbreset.log
n="$(find "$DATA_DIR/music" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.ogg' -o -iname '*.flac' -o -iname '*.wav' \) | wc -l)"
ok "hudba: $n souborů v $DATA_DIR/music (nahraj mp3/ogg/flac/wav)"

# ── 7. udev ────────────────────────────────────────────────────────────────────
step "7/12 udev (SIM7600 → /dev/motogo-lte-at)"
install -m 644 "$APP_DIR/systemd/99-motogo-lte.rules" /etc/udev/rules.d/99-motogo-lte.rules
udevadm control --reload && udevadm trigger --subsystem-match=tty || true
ok "pravidlo nainstalováno"

# ── 8. NetworkManager profily ─────────────────────────────────────────────────
step "8/12 Síť (NetworkManager: motogo-lte + motogo-lan)"
systemctl enable --now NetworkManager ModemManager >/dev/null 2>&1 || true
mkdir -p "$NM_DIR"
if [[ -f "$NM_DIR/motogo-lte.nmconnection" ]]; then
  ok "motogo-lte existuje — ponechán"
  if [[ "${MOTOGO_APN}" != "internet" ]] && ! grep -q "^apn=${MOTOGO_APN}$" "$NM_DIR/motogo-lte.nmconnection"; then
    sed -i "s|^apn=.*|apn=${MOTOGO_APN}|" "$NM_DIR/motogo-lte.nmconnection"; ok "APN aktualizováno na ${MOTOGO_APN}"
  fi
else
  sed "s|^apn=.*|apn=${MOTOGO_APN}|" "$APP_DIR/systemd/motogo-lte.nmconnection" > "$NM_DIR/motogo-lte.nmconnection"
  ok "motogo-lte vytvořen (APN ${MOTOGO_APN})"
fi
if [[ -f "$NM_DIR/motogo-lan.nmconnection" ]]; then
  ok "motogo-lan existuje — ponechán"
else
  cp "$APP_DIR/systemd/motogo-lan.nmconnection" "$NM_DIR/motogo-lan.nmconnection"
  ok "motogo-lan vytvořen (eth0 192.168.50.10/24, bez výchozí brány)"
fi
chmod 600 "$NM_DIR"/motogo-*.nmconnection; chown root:root "$NM_DIR"/motogo-*.nmconnection
nmcli connection reload || warn "nmcli reload selhal (NetworkManager neběží?)"
# Profil, který NM odmítne (chyba v souboru), se tiše nenačte → LTE by nikdy nenaběhlo; ověřit hned.
for prof in motogo-lte motogo-lan; do
  if nmcli -t -f NAME con show 2>/dev/null | grep -qx "$prof"; then ok "NM profil $prof načten"
  else warn "NM profil $prof NENÍ načten — zkontroluj: journalctl -u NetworkManager | grep $prof"; fi
done
echo "  → statickou LAN aplikuj: sudo $APP_DIR/scripts/set-static-lan.sh (ověří, že default route nevede přes eth0)"

# ── 9. sudoers ─────────────────────────────────────────────────────────────────
step "9/12 sudoers"
visudo -c -q -f "$APP_DIR/systemd/motogo-sudoers" || die "motogo-sudoers má chybu syntaxe"
install -m 440 -o root -g root "$APP_DIR/systemd/motogo-sudoers" /etc/sudoers.d/motogo
ok "/etc/sudoers.d/motogo (reboot, restart motogo-*, /usr/local/sbin/motogo-usbreset|update, nmcli lte, mmcli signal-setup)"

# ── 10. systemd ────────────────────────────────────────────────────────────────
step "10/12 systemd služby"
for unit in motogo-controller.service motogo-health.service motogo-ui.service; do
  install -m 644 "$APP_DIR/systemd/$unit" "/etc/systemd/system/$unit"
done
systemctl daemon-reload
systemctl enable motogo-controller motogo-health motogo-ui >/dev/null 2>&1
ok "unity nainstalovány a povoleny"
# UI běží na tty7 vlastní službou — getty tam nesmí (kolize o terminál).
systemctl disable --now getty@tty7.service >/dev/null 2>&1 || true
systemctl mask getty@tty7.service >/dev/null 2>&1 || true
ok "getty@tty7 vypnut (tty7 patří motogo-ui)"
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_boot_behaviour B1 >/dev/null 2>&1 || true   # konzole bez autologinu, bez desktopu
fi
systemctl set-default multi-user.target >/dev/null 2>&1 || true

# ── 11. RTC + firmware ─────────────────────────────────────────────────────────
step "11/12 RTC baterie (dobíjení) v config.txt"
BOOT_CFG=/boot/firmware/config.txt; [[ -f "$BOOT_CFG" ]] || BOOT_CFG=/boot/config.txt
if [[ -f "$BOOT_CFG" ]]; then
  if grep -q '^dtparam=rtc_bbat_vchg=3000000' "$BOOT_CFG"; then
    ok "rtc_bbat_vchg už nastaveno"
  else
    sed -i '/^dtparam=rtc_bbat_vchg=/d' "$BOOT_CFG"
    printf '\n# MotoGo Box: dobíjení RTC baterie (Raspberry Pi 5 RTC battery)\ndtparam=rtc_bbat_vchg=3000000\n' >> "$BOOT_CFG"
    ok "přidáno dtparam=rtc_bbat_vchg=3000000 (platí po restartu)"
  fi
else
  warn "config.txt nenalezen — RTC dobíjení nastav ručně"
fi

# ── 12. overlayfs (volitelné) ─────────────────────────────────────────────────
step "12/12 Read-only root (volitelné, SPEC §11)"
cat <<'TXT'
  Až bude vše odladěné, lze zapnout overlay root (SD karta v read-only, zápisy jen do RAM):
    sudo raspi-config → Performance Options → Overlay File System → Enable  (nebo: raspi-config nonint enable_overlayfs)
  POZOR: /var/lib/motogo (SQLite cache kódů, fronta událostí, hudba) a /var/log pak nepřežijí restart —
  před zapnutím přesuň data na samostatný zapisovatelný oddíl/USB a upravte paths.data_dir v config.yaml.
  Instalátor overlay NEZAPÍNÁ.
TXT

# ── start ──────────────────────────────────────────────────────────────────────
if [[ "${MOTOGO_NO_START:-0}" == "1" ]]; then
  warn "služby nespuštěny (MOTOGO_NO_START=1)"
else
  systemctl restart motogo-controller motogo-health || true
  systemctl restart motogo-ui || true
  sleep 3
fi
echo
echo "════════════════════════ MotoGo Box — shrnutí ════════════════════════"
for s in motogo-controller motogo-health motogo-ui; do
  printf '  %-18s %s\n' "$s" "$(systemctl is-active "$s" 2>/dev/null || echo '?')"
done
echo "  program:     $APP_DIR ($(app_version))"
echo "  konfigurace: $ETC_DIR/config.yaml, $ETC_DIR/hardware.yaml (zdroj update: $ETC_DIR/source_dir)"
echo "  data/hudba:  $DATA_DIR, $DATA_DIR/music"
echo "  LTE APN:     ${MOTOGO_APN}   (nmcli con show motogo-lte)"
echo "  diagnostika: kód „${MOTOGO_DIAG_CODE}“ na displeji (nebo Velín → Diagnostika sítě) = scan sítě + report do Velína"
echo "  LAN:         sudo $APP_DIR/scripts/set-static-lan.sh"
echo "  logy:        journalctl -u motogo-controller -u motogo-health -u motogo-ui -f"
echo "  stav:        curl -s http://127.0.0.1:8080/api/state | python3 -m json.tool"
echo "  Další kroky: 1) na displeji zadat diagnostický kód → ověřit LTE/LAN/moduly, 2) spárovat zařízení (UI nebo config.yaml),"
echo "               3) nastavit Waveshare/Shelly (HARDWARE.md), 4) servisní heslo → servisní panel → test každé zóny,"
echo "               5) po odladění restart (RTC dtparam)."
echo "═══════════════════════════════════════════════════════════════════════"
