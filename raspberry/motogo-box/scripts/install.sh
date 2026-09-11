#!/usr/bin/env bash
# MotoGo Box — instalace na Raspberry Pi OS Bookworm 64-bit (Lite). Idempotentní: lze
# spouštět opakovaně, existující konfigurace (/etc/motogo/*.yaml, NM profily) nepřepisuje.
#
# Použití (z rozbaleného adresáře raspberry/motogo-box):
#   sudo ./scripts/install.sh
# Volitelné proměnné prostředí (jinak se instalátor ptá interaktivně, pokud má terminál):
#   MOTOGO_DEVICE_ID=<uuid>  MOTOGO_DEVICE_TOKEN=<uuid>  MOTOGO_APN=internet.t-mobile.cz
#   MOTOGO_SIM_PIN=1234      (prázdné = SIM bez PINu; zapíše se do NM profilu motogo-lte, [gsm] pin=)
#   MOTOGO_DIAG_CODE=<kód>   (kód diagnostiky sítě z displeje, [0-9a-z-]{4,32}; při založení config.yaml se
#                             jinak vygeneruje náhodný „diagNNNN“; existující kód se BEZ této proměnné nemění)
#   MOTOGO_MODEM_VIDPID=1e0e:9001  (USB ID modemu → /etc/motogo/modem_vidpid pro motogo-usbreset)
#   MOTOGO_SKIP_APT=1 (přeskočí apt), MOTOGO_NO_START=1 (na konci služby nespouští)
# Rozhodnutí k souborovému systému: root zůstává READ-WRITE, overlay se NEzapíná (krok 14, README).
# OS záplaty: unattended-upgrades (jen Debian security, v noci 04:00, bez restartu — krok 11); úplný
# apt full-upgrade + restart OS jen z Velína (příkaz update_system → /usr/local/sbin/motogo-sysupdate).
set -euo pipefail

APP_DIR="/opt/motogo"
ETC_DIR="/etc/motogo"
DATA_DIR="/var/lib/motogo"
APP_USER="motogo"
APP_GROUPS="audio,video,input,render,dialout,plugdev,netdev"
NM_DIR="/etc/NetworkManager/system-connections"
LTE_PROF="$NM_DIR/motogo-lte.nmconnection"
POLKIT_RULE="50-motogo-kiosk.rules"
APT_CONF="52motogo-unattended"
APT_TIMER_DIR="/etc/systemd/system/apt-daily-upgrade.timer.d"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APT_PKGS=(python3 python3-venv python3-pip git mpv cage chromium network-manager modemmanager
          alsa-utils rsync curl usbutils kbd fonts-dejavu fonts-noto-color-emoji unattended-upgrades)

step() { echo; echo "──── $* ────"; }
ok()   { echo "  ✔ $*"; }
warn() { echo "  ! $*"; }
die()  { echo "CHYBA: $*" >&2; exit 1; }
as_app() { runuser -u "$APP_USER" -- "$@"; }   # venv patří motogo → root ho nikdy nespouští (pip ani python)

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
step "1/14 Balíčky (apt)"
if [[ "${MOTOGO_SKIP_APT:-0}" == "1" ]]; then
  warn "apt přeskočen (MOTOGO_SKIP_APT=1)"
else
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends "${APT_PKGS[@]}"
  # polkit (logind chvt pro motogo-ui): Bookworm = polkitd, starší image = policykit-1
  apt-get install -y -qq --no-install-recommends polkitd >/dev/null 2>&1 \
    || apt-get install -y -qq --no-install-recommends policykit-1 >/dev/null 2>&1 || warn "polkit nenainstalován"
  ok "nainstalováno: ${APT_PKGS[*]} polkitd"
fi
command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1 || warn "chromium nenalezeno — UI nepoběží"
command -v chvt >/dev/null 2>&1 || warn "chvt (balík kbd) chybí — motogo-ui spoléhá jen na polkit pravidlo"

# ── 2. uživatel ────────────────────────────────────────────────────────────────
step "2/14 Uživatel $APP_USER"
if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "/home/$APP_USER" --shell /usr/sbin/nologin "$APP_USER"
  ok "uživatel vytvořen"
fi
for g in ${APP_GROUPS//,/ }; do getent group "$g" >/dev/null || groupadd "$g"; done
usermod -a -G "$APP_GROUPS" "$APP_USER"
ok "skupiny: $APP_GROUPS"

# ── 3. kopie programu do /opt/motogo ──────────────────────────────────────────
step "3/14 Program → $APP_DIR"
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
# root-owned kopie skriptů pro sudo (viz systemd/motogo-sudoers — povoleny JEN bez argumentů)
install -m 755 -o root -g root "$APP_DIR/scripts/update.sh"         /usr/local/sbin/motogo-update
install -m 755 -o root -g root "$APP_DIR/scripts/usbreset-modem.sh" /usr/local/sbin/motogo-usbreset
install -m 755 -o root -g root "$APP_DIR/scripts/sysupdate.sh"      /usr/local/sbin/motogo-sysupdate
ok "sudo skripty: /usr/local/sbin/motogo-update, motogo-usbreset, motogo-sysupdate (root:root)"
# Zdroj pro budoucí aktualizace (update.sh / příkaz update_software z Velína) — root-owned soubor,
# přes sudo je to JEDINÝ přijímaný zdroj. git pull dělá update.sh jako vlastník checkoutu.
mkdir -p "$ETC_DIR"
if [[ "$SRC_DIR" != "$APP_DIR" ]]; then
  echo "$SRC_DIR" > "$ETC_DIR/source_dir"; chown root:root "$ETC_DIR/source_dir"; chmod 644 "$ETC_DIR/source_dir"
  src_owner="$(stat -c %U "$SRC_DIR")"
  if runuser -u "$src_owner" -- git -C "$SRC_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ok "zdroj aktualizací: $SRC_DIR (git checkout uživatele $src_owner → update = git fetch + ff-merge jako $src_owner + rsync;"
    echo "    bezobslužný update z Velína potřebuje u $src_owner credential helper / deploy key bez hesla)"
  else
    ok "zdroj aktualizací: $SRC_DIR (bez gitu → update = rsync; nový balík rozbal na stejné místo)"
  fi
  [[ "$src_owner" != "$APP_USER" ]] || warn "zdroj patří uživateli $APP_USER — motogo-update ho odmítne (nesmí z něj brát sudoers/unity)"
else
  warn "instaluješ přímo z $APP_DIR — vzdálený update_software nebude mít odkud brát novou verzi (ručně jako root: motogo-update /cesta)"
fi

# ── 4. venv + závislosti ──────────────────────────────────────────────────────
step "4/14 Python venv"
if [[ ! -x "$APP_DIR/venv/bin/python" ]]; then
  mkdir -p "$APP_DIR/venv"; chown "$APP_USER:$APP_USER" "$APP_DIR/venv"
  as_app python3 -m venv "$APP_DIR/venv" || die "python3 -m venv selhal (chybí python3-venv?)"
  ok "venv vytvořen"
fi
chown -R "$APP_USER:$APP_USER" "$APP_DIR/venv"
# pip kroky tolerují chybějící internet (LTE ještě nejede, eth0 = izolovaná I/O síť): varování, instalace pokračuje.
as_app "$APP_DIR/venv/bin/pip" install --quiet --upgrade pip 2>/dev/null || warn "pip upgrade přeskočen (offline?)"
if as_app "$APP_DIR/venv/bin/pip" install --quiet -r "$APP_DIR/requirements.txt"; then
  ok "requirements nainstalovány (v mezích requirements.txt)"
else
  warn "pip install -r requirements.txt selhal (offline?) — po připojení: sudo /usr/local/sbin/motogo-update"
fi
app_version() { (cd "$APP_DIR" && as_app "$APP_DIR/venv/bin/python" -m motogo_box version 2>/dev/null) || echo '?'; }
ok "verze programu: $(app_version)"

# ── 5. konfigurace /etc/motogo ────────────────────────────────────────────────
step "5/14 Konfigurace $ETC_DIR"
mkdir -p "$ETC_DIR"
ask MOTOGO_APN "APN operátora (např. internet.t-mobile.cz, internet, ointernet)" "internet"
config_created=0
if [[ -f "$ETC_DIR/config.yaml" ]]; then
  ok "config.yaml existuje — ponechán (ID/token lze změnit v UI → Přepárovat)"
else
  echo "  Párování zařízení: ID + token vytvoříš ve Velíně → Pobočky → Samoobsluha → Řídicí jednotka (Raspberry)."
  echo "  (Lze nechat prázdné a spárovat později z dotykového UI.)"
  ask MOTOGO_DEVICE_ID "DEVICE_ID (uuid)" ""
  ask MOTOGO_DEVICE_TOKEN "DEVICE_TOKEN (uuid)" ""
  cp "$APP_DIR/config/config.example.yaml" "$ETC_DIR/config.yaml"
  sed -i "s|^  id: \"\"|  id: \"${MOTOGO_DEVICE_ID}\"|; s|^  token: \"\"|  token: \"${MOTOGO_DEVICE_TOKEN}\"|" "$ETC_DIR/config.yaml"
  config_created=1
  ok "config.yaml vytvořen z config.example.yaml"
fi
# Diagnostický kód (diagnostics.code): zadáním na displeji (i před spárováním) se spustí kompletní diagnostika
# sítě (rozhraní, LTE, internet, Velín, scan LAN, Waveshare/Shelly) → displej + Velín. Žádný veřejný default:
# při založení config.yaml se vygeneruje náhodný kód; existující kód se mění JEN přes env MOTOGO_DIAG_CODE.
diag_explicit=0; [[ -n "${MOTOGO_DIAG_CODE:-}" ]] && diag_explicit=1
cur_diag="$(sed -n '/^diagnostics:/,/^[a-z_]*:/ s/^  code: *"\?\([^"#]*\)"\?.*/\1/p' "$ETC_DIR/config.yaml" | head -1 | tr -d '[:space:]')"
(( config_created )) && cur_diag=""   # čerstvá kopie vzoru má kód prázdný → vygenerovat náhodný
if (( diag_explicit || config_created )) || [[ -z "$cur_diag" ]]; then
  gen="$(printf 'diag%04d' "$(( $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 10000 ))")"
  while :; do
    ask MOTOGO_DIAG_CODE "Diagnostický kód pro displej ([0-9a-z-]{4,32})" "${cur_diag:-$gen}"
    [[ "$MOTOGO_DIAG_CODE" =~ ^[0-9a-z-]{4,32}$ ]] && break
    (( INTERACTIVE && ! diag_explicit )) || die "MOTOGO_DIAG_CODE '$MOTOGO_DIAG_CODE' neodpovídá ^[0-9a-z-]{4,32}$"
    warn "neplatný kód — jen malá písmena, číslice a pomlčka, 4–32 znaků"; MOTOGO_DIAG_CODE=""
  done
  if grep -q '^diagnostics:' "$ETC_DIR/config.yaml"; then
    sed -i "/^diagnostics:/,/^[a-z_]*:/ s|^  code: .*|  code: \"${MOTOGO_DIAG_CODE}\"|" "$ETC_DIR/config.yaml"
  else
    printf '\ndiagnostics:\n  code: "%s"\n' "${MOTOGO_DIAG_CODE}" >> "$ETC_DIR/config.yaml"
  fi
  ok "diagnostický kód nastaven: ${MOTOGO_DIAG_CODE}"
else
  MOTOGO_DIAG_CODE="$cur_diag"
  ok "diagnostický kód ponechán: ${MOTOGO_DIAG_CODE} (změna: MOTOGO_DIAG_CODE=<kód> sudo ./scripts/install.sh)"
fi
chown root:"$APP_USER" "$ETC_DIR/config.yaml"; chmod 640 "$ETC_DIR/config.yaml"   # obsahuje token
# USB zvuková karta (AXAGON) pro audio.device: výchozí ALSA zařízení RPi 5 je HDMI monitoru → kóje by mlčely.
detect_usb_card() { aplay -l 2>/dev/null | sed -n 's/^card [0-9]*: \([^ ]*\) \[\([^]]*\)\].*/\1 \2/p' \
                    | grep -i -m1 -E 'usb|axagon' | cut -d' ' -f1 || true; }
USB_CARD="$(detect_usb_card)"; hw_created=0
if [[ -f "$ETC_DIR/hardware.yaml" ]]; then
  ok "hardware.yaml existuje — ponechán (Velín má přednost)"
else
  hw_created=1
  install -m 644 "$APP_DIR/config/brno-9zone.yaml" "$ETC_DIR/hardware.yaml"
  if [[ -n "$USB_CARD" ]]; then
    sed -i "/^audio:/,/^[a-z_]*:/ s|^  device: .*|  device: \"alsa/plughw:CARD=${USB_CARD}\"   # USB karta nalezená instalátorem (aplay -l)|" "$ETC_DIR/hardware.yaml"
  fi
  ok "hardware.yaml = výchozí mapa Brno 9 zón${USB_CARD:+, audio.device = alsa/plughw:CARD=$USB_CARD}"
fi
[[ -n "$USB_CARD" ]] || warn "USB zvuková karta nenalezena (aplay -l) — připoj AXAGON kartu a nastav audio.device (Velín / hardware.yaml)"
if (cd "$APP_DIR" && as_app "$APP_DIR/venv/bin/python" -m motogo_box check-config "$ETC_DIR/hardware.yaml" >/dev/null); then
  ok "hardware.yaml je konzistentní"
else
  warn "hardware.yaml má problémy — spusť: cd $APP_DIR && venv/bin/python -m motogo_box check-config $ETC_DIR/hardware.yaml"
fi

# ── 6. data + logy ─────────────────────────────────────────────────────────────
step "6/14 Data $DATA_DIR"
# music = ručně nahrané soubory (legacy, cíl „všechny kóje“); music/tracks = skladby stažené z Velína
# (bucket branch-music, index v kv music_index) — jen motogo do nich zapisuje (music_sync).
mkdir -p "$DATA_DIR/music/tracks"
chown -R "$APP_USER:$APP_USER" "$DATA_DIR"; chmod 750 "$DATA_DIR" "$DATA_DIR/music" "$DATA_DIR/music/tracks"
# Logy sudo skriptů patří rootu (skripty běží jako root). Soubor vlastněný motogo = symlink → root by psal kamkoli;
# starší instalace (chown motogo) se opraví.
for f in /var/log/motogo-update.log /var/log/motogo-usbreset.log /var/log/motogo-sysupdate.log; do
  if [[ -L "$f" || ( -e "$f" && "$(stat -c %u "$f")" != "0" ) ]]; then rm -f "$f"; fi
  touch "$f"; chmod 644 "$f"
done
# Ruční soubory: jednotka (music_sync.legacy_files → mpv_player.MUSIC_EXTENSIONS) hraje mp3/ogg/oga/opus/flac/wav/m4a/aac/wma/aiff/webm/mkv.
n_legacy="$(find "$DATA_DIR/music" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.ogg' -o -iname '*.oga' -o -iname '*.opus' \
            -o -iname '*.flac' -o -iname '*.wav' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.wma' \
            -o -iname '*.aiff' -o -iname '*.aif' -o -iname '*.webm' -o -iname '*.mkv' \) | wc -l)"
n_tracks="$(find "$DATA_DIR/music/tracks" -maxdepth 1 -type f ! -name '*.part' | wc -l)"
ok "hudba: $n_tracks skladeb z Velína v $DATA_DIR/music/tracks (stahuje jednotka sama), $n_legacy ručních souborů (mp3/ogg/opus/flac/wav/m4a/aac/wma/aiff/webm/mkv) v $DATA_DIR/music"
ok "logy /var/log/motogo-*.log root-owned"

# ── 7. audio: ALSA výstupy + udev pojmenování karet ───────────────────────────
step "7/14 Audio (ALSA výstupy, režim selector/multi, udev pojmenování USB karet)"
# selector = jeden zesilovač + relé (audio.device, krok 5); multi = každá kóje/šatna/venek vlastní ALSA výstup
# (audio.outputs) — čísla karet se po restartu prohazují, proto stálá jména podle USB portu (udev ATTR{id}).
AUDIO_RULES="70-motogo-audio.rules"; LIVE_RULES="/etc/udev/rules.d/$AUDIO_RULES"
AUDIO_RULES_STATE="nenainstalováno"
has_rules() { [[ -f "$1" ]] && grep -Eq '^[[:space:]]*[^#[:space:]]' "$1"; }   # aspoň jeden nekomentářový řádek
# Živý soubor je konfigurace pobočky (jako hardware.yaml): má-li aktivní pravidla, šablona z repa ho NEpřepíše.
if has_rules "$LIVE_RULES"; then
  AUDIO_RULES_STATE="existující aktivní pravidla — ponechána (šablona z $APP_DIR/systemd se nekopíruje)"
elif [[ -s "$APP_DIR/systemd/$AUDIO_RULES" ]]; then
  install -m 644 -o root -g root "$APP_DIR/systemd/$AUDIO_RULES" "$LIVE_RULES"
  if has_rules "$LIVE_RULES"; then AUDIO_RULES_STATE="aktivní pravidla (nainstalována ze šablony)"
  else AUDIO_RULES_STATE="jen šablona (samé komentáře, bez účinku)"; fi
else
  warn "$APP_DIR/systemd/$AUDIO_RULES chybí/prázdné — udev pojmenování karet přeskočeno"
fi
# Pravidla aplikovat (a počkat na udev) PŘED výpisem karet — jinak by výpis i hardware.yaml nesly stará jména.
if has_rules "$LIVE_RULES"; then
  udevadm control --reload && udevadm trigger --subsystem-match=sound && udevadm settle --timeout=5 || true
  ok "$LIVE_RULES — $AUDIO_RULES_STATE (jména karet: cat /proc/asound/cards)"
  new_card="$(detect_usb_card)"
  if (( hw_created )) && [[ -n "$new_card" && "$new_card" != "$USB_CARD" ]]; then
    sed -i "/^audio:/,/^[a-z_]*:/ s|^  device: .*|  device: \"alsa/plughw:CARD=${new_card}\"   # USB karta nalezená instalátorem (aplay -l)|" "$ETC_DIR/hardware.yaml"
    ok "hardware.yaml audio.device přepsáno na alsa/plughw:CARD=$new_card (karta přejmenována udev pravidlem)"
  fi
  [[ -z "$new_card" ]] || USB_CARD="$new_card"
elif [[ -f "$LIVE_RULES" ]]; then
  ok "$LIVE_RULES — $AUDIO_RULES_STATE; pro multi odkomentuj pravidla podle USB portů (upravuj ŽIVÝ soubor, install.sh ho ponechá)"
fi
n_cards=0
if command -v aplay >/dev/null 2>&1; then
  n_cards="$(aplay -l 2>/dev/null | sed -n 's/^card \([0-9]*\):.*/\1/p' | sort -u | wc -l || true)"
  echo "  ALSA karty (aplay -l): $n_cards"
  aplay -l 2>/dev/null | sed -n 's/^card \([0-9]*\): \([^ ]*\) \[\([^]]*\)\].*/    card \1: CARD=\2  (\3)/p' | sort -u || true
  echo "  ALSA zařízení pro audio.outputs[].device (aplay -L, jen plughw):"
  aplay -L 2>/dev/null | sed -n 's/^plughw:CARD=\([^,]*\).*/    alsa\/plughw:CARD=\1/p' | sort -u || true
  (( n_cards > 0 )) || warn "aplay -l nevidí žádnou kartu — zvuk nepůjde (připoj USB karty)"
else
  warn "aplay chybí (alsa-utils) — výpis karet přeskočen"
fi
echo "  → režim multi (nezávislé kanály kóje 1–7, šatna, venek): výstupy (název → ALSA zařízení) a kanál venek"
echo "    nastav ve Velíně → Pobočky → Samoobsluha → hardware → Audio; hudbu nahraj tamtéž v bloku „Hudba pobočky“."
echo "    Ověření kanálu: speaker-test -D plughw:CARD=<jméno> -c2 -t wav -l1 ; stav mpv: api/state → audio.players"

# ── 8. udev + modem ────────────────────────────────────────────────────────────
step "8/14 udev (SIM7600 → /dev/motogo-lte-at) + VID:PID modemu"
install -m 644 "$APP_DIR/systemd/99-motogo-lte.rules" /etc/udev/rules.d/99-motogo-lte.rules
udevadm control --reload && udevadm trigger --subsystem-match=tty || true
ok "pravidlo nainstalováno"
# VID:PID pro motogo-usbreset: sudoers skript povoluje jen bez argumentů → čte tento root-owned soubor
ask MOTOGO_MODEM_VIDPID "USB VID:PID LTE modemu" "1e0e:9001"
MOTOGO_MODEM_VIDPID="${MOTOGO_MODEM_VIDPID,,}"
[[ "$MOTOGO_MODEM_VIDPID" =~ ^[0-9a-f]{4}:[0-9a-f]{4}$ ]] || die "MOTOGO_MODEM_VIDPID '$MOTOGO_MODEM_VIDPID' není ve tvaru 1e0e:9001"
printf '%s\n' "$MOTOGO_MODEM_VIDPID" > "$ETC_DIR/modem_vidpid"; chown root:root "$ETC_DIR/modem_vidpid"; chmod 644 "$ETC_DIR/modem_vidpid"
ok "modem $MOTOGO_MODEM_VIDPID → $ETC_DIR/modem_vidpid (musí odpovídat health.modem_vid_pid v config.yaml)"

# ── 9. NetworkManager profily ─────────────────────────────────────────────────
step "9/14 Síť (NetworkManager: motogo-lte + motogo-lan)"
systemctl enable --now NetworkManager ModemManager >/dev/null 2>&1 || true
mkdir -p "$NM_DIR"
# PIN SIM: bez něj zůstane modem ve stavu „locked“ a LTE nikdy nenaběhne (health hlásí lte.error=sim_locked).
pin_explicit=0; [[ -n "${MOTOGO_SIM_PIN+x}" ]] && pin_explicit=1
cur_pin=""; [[ -f "$LTE_PROF" ]] && cur_pin="$(sed -n '/^\[gsm\]/,/^\[/ s/^pin=//p' "$LTE_PROF" | head -1)"
(( pin_explicit )) || ask MOTOGO_SIM_PIN "PIN SIM karty (prázdné = SIM bez PINu${cur_pin:+; Enter = ponechat uložený, '-' = smazat})" "$cur_pin"
MOTOGO_SIM_PIN="${MOTOGO_SIM_PIN:-}"; [[ "$MOTOGO_SIM_PIN" == "-" ]] && MOTOGO_SIM_PIN=""
[[ -z "$MOTOGO_SIM_PIN" || "$MOTOGO_SIM_PIN" =~ ^[0-9]{4,8}$ ]] || die "MOTOGO_SIM_PIN musí být 4–8 číslic (nebo prázdné)"
write_gsm_pin() {  # write_gsm_pin <profil> <pin|""> — [gsm] pin=… + pin-flags=0 (NM PIN uloží a zadá sám); prázdný = řádky pryč
  sed -i '/^\[gsm\]/,/^\[/{/^pin=/d;/^pin-flags=/d}' "$1"
  [[ -z "$2" ]] || sed -i -e "/^\[gsm\]/a pin-flags=0" -e "/^\[gsm\]/a pin=$2" "$1"
}
if [[ -f "$LTE_PROF" ]]; then
  ok "motogo-lte existuje — ponechán"
  if [[ "${MOTOGO_APN}" != "internet" ]] && ! grep -q "^apn=${MOTOGO_APN}$" "$LTE_PROF"; then
    sed -i "s|^apn=.*|apn=${MOTOGO_APN}|" "$LTE_PROF"; ok "APN aktualizováno na ${MOTOGO_APN}"
  fi
else
  sed "s|^apn=.*|apn=${MOTOGO_APN}|" "$APP_DIR/systemd/motogo-lte.nmconnection" > "$LTE_PROF"
  ok "motogo-lte vytvořen (APN ${MOTOGO_APN})"
fi
write_gsm_pin "$LTE_PROF" "$MOTOGO_SIM_PIN"
SIM_PIN_STATE="${MOTOGO_SIM_PIN:+nastaven (pin-flags=0)}"; SIM_PIN_STATE="${SIM_PIN_STATE:-žádný (SIM bez PINu)}"
ok "PIN SIM: $SIM_PIN_STATE"
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
echo "  → statickou LAN aplikuj: sudo $APP_DIR/scripts/set-static-lan.sh (přes SSH na eth0 spojení spadne — skript doběhne sám)"

# ── 10. sudoers + polkit ───────────────────────────────────────────────────────
step "10/14 sudoers + polkit"
visudo -c -q -f "$APP_DIR/systemd/motogo-sudoers" || die "motogo-sudoers má chybu syntaxe"
install -m 440 -o root -g root "$APP_DIR/systemd/motogo-sudoers" /etc/sudoers.d/motogo
ok "/etc/sudoers.d/motogo (reboot, restart motogo-*, motogo-usbreset|motogo-update|motogo-sysupdate BEZ argumentů, nmcli lte, mmcli signal-setup)"
# polkit: motogo smí org.freedesktop.login1.chvt — cage (motogo-ui na tty7) volá logind Session.Activate; pro
# NEaktivní session by polkit chtěl auth_admin → cage spadne. Unit dělá `chvt 7` před startem, pravidlo je pojistka.
mkdir -p /etc/polkit-1/rules.d
install -m 644 -o root -g root "$APP_DIR/systemd/$POLKIT_RULE" "/etc/polkit-1/rules.d/$POLKIT_RULE"
ok "/etc/polkit-1/rules.d/$POLKIT_RULE (chvt pro motogo-ui; polkitd si rules.d načte sám)"

# ── 11. OS záplaty (unattended-upgrades) ──────────────────────────────────────
step "11/14 OS záplaty: unattended-upgrades (jen Debian security, v noci 04:00, bez restartu)"
# Bezpečnostní záplaty se instalují samy v noci; restart OS NIKDY automaticky (Automatic-Reboot false) —
# jen z Velína (příkaz reboot / update_system s auto_reboot po jádru, až je kóje volná). Úplný apt
# full-upgrade dělá /usr/local/sbin/motogo-sysupdate na pokyn Velína.
if command -v unattended-upgrade >/dev/null 2>&1; then
  ok "balík unattended-upgrades nainstalován"
else
  warn "balík unattended-upgrades chybí${MOTOGO_SKIP_APT:+ (MOTOGO_SKIP_APT=1)} — záplaty OS se nebudou instalovat samy (apt-get install unattended-upgrades)"
fi
mkdir -p /etc/apt/apt.conf.d
install -m 644 -o root -g root "$APP_DIR/systemd/$APT_CONF" "/etc/apt/apt.conf.d/$APT_CONF"
ok "/etc/apt/apt.conf.d/$APT_CONF (Origins-Pattern = Debian-Security, Automatic-Reboot false, Periodic 1, hook nové jádro → /run/reboot-required)"
mkdir -p "$APT_TIMER_DIR"
install -m 644 -o root -g root "$APP_DIR/systemd/apt-daily-upgrade-override.conf" "$APT_TIMER_DIR/motogo.conf"
systemctl daemon-reload
if systemctl cat apt-daily-upgrade.timer >/dev/null 2>&1; then
  if systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1; then
    ok "apt-daily-upgrade.timer: OnCalendar 04:00 ± 20 min, bez dohánění po startu ($APT_TIMER_DIR/motogo.conf), povolen"
  else
    warn "apt-daily-upgrade.timer se nepodařilo povolit — systemctl status apt-daily-upgrade.timer"
  fi
else
  warn "apt-daily-upgrade.timer neexistuje (balík apt?) — drop-in $APT_TIMER_DIR/motogo.conf ponechán pro později"
fi

# ── 12. systemd ────────────────────────────────────────────────────────────────
step "12/14 systemd služby"
for unit in motogo-controller.service motogo-health.service motogo-ui.service; do
  install -m 644 "$APP_DIR/systemd/$unit" "/etc/systemd/system/$unit"
done
systemctl daemon-reload
systemctl enable motogo-controller motogo-health motogo-ui >/dev/null 2>&1
ok "unity nainstalovány a povoleny (motogo-ui: chvt 7 před startem)"
# UI běží na tty7 vlastní službou — getty tam nesmí (kolize o terminál).
systemctl disable --now getty@tty7.service >/dev/null 2>&1 || true
systemctl mask getty@tty7.service >/dev/null 2>&1 || true
ok "getty@tty7 vypnut (tty7 patří motogo-ui)"
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_boot_behaviour B1 >/dev/null 2>&1 || true   # konzole bez autologinu, bez desktopu
fi
systemctl set-default multi-user.target >/dev/null 2>&1 || true

# ── 13. RTC + firmware ─────────────────────────────────────────────────────────
step "13/14 RTC baterie (dobíjení) v config.txt"
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

# ── 14. souborový systém ──────────────────────────────────────────────────────
step "14/14 Souborový systém: rw root, BEZ overlay (rozhodnutí k SPEC §11)"
cat <<'TXT'
  Rozhodnutí: root zůstává read-write, overlay root (raspi-config → Overlay File System) se NEZAPÍNÁ.
  Důvod: /var/lib/motogo (SQLite cache kódů + fronta událostí, health.json, hudba), /var/log a NM profily
  musí přežít restart; overlay by je při každém výpadku 230 V (FVE střídač) zahodil a oddělený rw oddíl
  program ani instalátor nepodporují. Ochrana dat: SQLite WAL, průmyslová microSD (pSLC/„High Endurance“, A2)
  a záložní napájení RPi (UPS). Overlay nikdy nezapínat před go-live ani bez přesunu dat (viz README).
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
echo "  data/hudba:  $DATA_DIR, $DATA_DIR/music (ruční soubory = společná), $DATA_DIR/music/tracks (skladby z Velína, sync automaticky)"
echo "  OS záplaty:  unattended-upgrades $(command -v unattended-upgrade >/dev/null 2>&1 && echo 'ano' || echo 'CHYBÍ') (jen Debian security, 04:00, bez restartu);"
echo "               apt full-upgrade + restart OS jen z Velína (update_system → motogo-sysupdate, log /var/log/motogo-sysupdate.log)"
echo "  LTE:         APN ${MOTOGO_APN}, PIN SIM $SIM_PIN_STATE, modem ${MOTOGO_MODEM_VIDPID}   (nmcli con show motogo-lte; mmcli -m any)"
echo "  zvuk:        ${USB_CARD:+USB karta „$USB_CARD“ → audio.device alsa/plughw:CARD=$USB_CARD}${USB_CARD:-USB zvuková karta NENALEZENA — nastav audio.device (aplay -l)} (režim selector)"
echo "               režim multi: $n_cards ALSA karet; výstupy + venek nastav ve Velíně (Samoobsluha → hardware → Audio);"
echo "               udev jména karet: /etc/udev/rules.d/$AUDIO_RULES — $AUDIO_RULES_STATE"
echo "  diagnostika: kód „${MOTOGO_DIAG_CODE}“ na displeji (nebo Velín → Diagnostika sítě) = scan sítě + report do Velína"
echo "  UI:          motogo-ui na tty7 (chvt 7 + polkit chvt pro motogo); LAN: sudo $APP_DIR/scripts/set-static-lan.sh"
echo "  logy:        journalctl -u motogo-controller -u motogo-health -u motogo-ui -f"
echo "  stav:        curl -s http://127.0.0.1:8080/api/state | python3 -m json.tool"
echo "  Další kroky: 1) na displeji zadat diagnostický kód → ověřit LTE/LAN/moduly, 2) spárovat zařízení (UI nebo config.yaml),"
echo "               3) nastavit Waveshare/Shelly (HARDWARE.md), 4) servisní heslo → servisní panel → test každé zóny,"
echo "               5) hudba: Velín → Samoobsluha → Hudba pobočky (nahrát, přiřadit kójím; multi = výstupy v hardware → Audio),"
echo "               6) po odladění restart (RTC dtparam)."
echo "═══════════════════════════════════════════════════════════════════════"
