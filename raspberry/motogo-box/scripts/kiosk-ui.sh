#!/usr/bin/env bash
# MotoGo Box — start dotykového UI (Wayland kiosk: cage + Chromium). Spouští motogo-ui.service.
# 1) počká, až controller odpovídá na http://127.0.0.1:8080/ (UI se servíruje odtud),
# 2) spustí cage s Chromiem v kiosk režimu; při pádu se vrátí a systemd službu restartuje.
set -euo pipefail

URL="${MOTOGO_UI_URL:-http://127.0.0.1:8080/}"
WAIT_MAX_S="${MOTOGO_UI_WAIT_S:-120}"
LOG_TAG="motogo-ui"

log() { echo "[$LOG_TAG] $*"; }

# ── prohlížeč: chromium (Bookworm) nebo chromium-browser (starší image) ─────────
BROWSER=""
for candidate in chromium chromium-browser; do
  if command -v "$candidate" >/dev/null 2>&1; then BROWSER="$candidate"; break; fi
done
if [[ -z "$BROWSER" ]]; then
  log "CHYBA: chromium ani chromium-browser není nainstalované (apt install chromium)"; exit 1
fi
if ! command -v cage >/dev/null 2>&1; then
  log "CHYBA: cage není nainstalované (apt install cage)"; exit 1
fi

# ── XDG_RUNTIME_DIR: PAM/logind ho nastaví; záloha, kdyby chyběl ──────────────
if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
fi
export WLR_LIBINPUT_NO_DEVICES="${WLR_LIBINPUT_NO_DEVICES:-1}"   # start i bez připojeného dotyku

# ── čekání na controller (UI se načítá z něj) ───────────────────────────────────
waited=0
until curl -fsS --max-time 2 -o /dev/null "$URL"; do
  if (( waited == 0 )); then log "čekám na controller na $URL…"; fi
  sleep 2; waited=$((waited + 2))
  if (( waited >= WAIT_MAX_S )); then
    log "controller neodpovídá po ${WAIT_MAX_S}s — spouštím UI (zobrazí banner: Řídicí jednotka nedostupná)"
    break
  fi
done

# ── profil Chromia: čistý start (žádné dialogy o pádu/obnově relace) ───────────
PROFILE="${XDG_RUNTIME_DIR}/motogo-chromium"
mkdir -p "$PROFILE"
rm -f "$PROFILE/SingletonLock" "$PROFILE/SingletonSocket" "$PROFILE/SingletonCookie" 2>/dev/null || true
if [[ -f "$PROFILE/Default/Preferences" ]]; then
  sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/; s/"exited_cleanly":false/"exited_cleanly":true/' \
    "$PROFILE/Default/Preferences" 2>/dev/null || true
fi

log "spouštím cage + $BROWSER → $URL"
exec cage -- "$BROWSER" \
  --kiosk \
  --ozone-platform=wayland \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-pinch \
  --overscroll-history-navigation=0 \
  --check-for-update-interval=31536000 \
  --touch-events=enabled \
  --window-size=1920,1080 \
  --autoplay-policy=no-user-gesture-required \
  --user-data-dir="$PROFILE" \
  --no-first-run \
  --disable-features=TranslateUI \
  --password-store=basic \
  "$URL"
