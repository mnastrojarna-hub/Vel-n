#!/usr/bin/env bash
# MotoGo Box — aktualizace software v /opt/motogo. Volá se ručně (sudo) nebo příkazem
# `update_software` z Velína (sudo /usr/local/sbin/motogo-update — root-owned kopie tohoto skriptu).
#
# Zdroj nové verze (v tomto pořadí):
#   1. argument $1 = adresář s balíkem (raspberry/motogo-box nebo kořen repa Vel-n),
#   2. /etc/motogo/source_dir (uložil install.sh) — je-li to git checkout repa, nejdřív `git pull --ff-only`.
# Poté: rsync do /opt/motogo, pip (jako uživatel motogo), root-owned kopie skriptů do /usr/local/sbin,
# změněné systemd unity + sudoers, restart motogo-controller + motogo-health.
# Log: /var/log/motogo-update.log
set -euo pipefail

APP_DIR="/opt/motogo"
VENV="$APP_DIR/venv"
LOG="/var/log/motogo-update.log"
SRC="${1:-}"
SERVICES="motogo-controller motogo-health"
APP_USER="motogo"

log() {
  local msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
  echo "$msg"
  echo "$msg" >> "$LOG" 2>/dev/null || true
}
version() { (cd "$APP_DIR" && "$VENV/bin/python" -m motogo_box version 2>/dev/null) || echo '?'; }

if [[ "$(id -u)" -ne 0 ]]; then echo "Spusť jako root (sudo)"; exit 2; fi
touch "$LOG" 2>/dev/null || true
log "=== update start (zdroj: ${SRC:-/etc/motogo/source_dir}) ==="
before="$(version)"

# ── zdroj ─────────────────────────────────────────────────────────────────────
if [[ -z "$SRC" && -r /etc/motogo/source_dir ]]; then
  SRC="$(head -n1 /etc/motogo/source_dir | tr -d '[:space:]')"
fi
[[ -n "$SRC" ]] || { log "CHYBA: není znám zdroj (argument ani /etc/motogo/source_dir)"; exit 2; }
if git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  repo_root="$(git -C "$SRC" rev-parse --show-toplevel)"
  git config --global --add safe.directory "$repo_root" >/dev/null 2>&1 || true
  log "git pull --ff-only v $repo_root ($(git -C "$repo_root" rev-parse --abbrev-ref HEAD))"
  if ! git -C "$repo_root" pull --ff-only 2>&1 | tee -a "$LOG"; then
    log "UPOZORNĚNÍ: git pull selhal (síť/konflikt) — instaluji stávající stav checkoutu"
  fi
fi
# kořen repa → podadresář s balíkem
if [[ ! -d "$SRC/motogo_box" && -d "$SRC/raspberry/motogo-box/motogo_box" ]]; then
  SRC="$SRC/raspberry/motogo-box"
fi
[[ -d "$SRC/motogo_box" ]] || { log "CHYBA: $SRC neobsahuje balík motogo_box"; exit 2; }

# ── kopie ─────────────────────────────────────────────────────────────────────
log "rsync $SRC → $APP_DIR"
rsync -a --delete \
  --exclude venv --exclude '.git' --exclude '__pycache__' --exclude '.pytest_cache' \
  "$SRC"/ "$APP_DIR"/ 2>&1 | tee -a "$LOG"
# Program: root-owned (motogo jen čte); venv patří uživateli motogo (pip bez rootu).
chown -R root:root "$APP_DIR"
chmod -R a+rX "$APP_DIR"
chmod 755 "$APP_DIR"/scripts/*.sh
[[ -d "$VENV" ]] && chown -R "$APP_USER:$APP_USER" "$VENV"

log "pip install -r requirements.txt (uživatel $APP_USER)"
if ! sudo -u "$APP_USER" "$VENV/bin/pip" install --quiet --upgrade -r "$APP_DIR/requirements.txt" 2>&1 | tee -a "$LOG"; then
  log "UPOZORNĚNÍ: pip install selhal (offline?) — pokračuji se stávajícími balíky"
fi

# ── root-owned kopie skriptů pro sudo (nikdy nespouštět soubory zapisovatelné uživatelem motogo) ──
install -m 755 -o root -g root "$APP_DIR/scripts/update.sh"          /usr/local/sbin/motogo-update
install -m 755 -o root -g root "$APP_DIR/scripts/usbreset-modem.sh"  /usr/local/sbin/motogo-usbreset

# ── změněné unity/sudoers (jen aktualizace souborů, enable zůstává) ───────────
for unit in motogo-controller.service motogo-health.service motogo-ui.service; do
  if [[ -f "$APP_DIR/systemd/$unit" ]] && ! cmp -s "$APP_DIR/systemd/$unit" "/etc/systemd/system/$unit"; then
    install -m 644 -o root -g root "$APP_DIR/systemd/$unit" "/etc/systemd/system/$unit"; log "aktualizována unit $unit"
    systemctl daemon-reload
  fi
done
if [[ -f "$APP_DIR/systemd/motogo-sudoers" ]] && visudo -c -q -f "$APP_DIR/systemd/motogo-sudoers"; then
  install -m 440 -o root -g root "$APP_DIR/systemd/motogo-sudoers" /etc/sudoers.d/motogo
else
  log "UPOZORNĚNÍ: motogo-sudoers chybí nebo má chybu syntaxe — ponechávám stávající"
fi

after="$(version)"
log "verze: $before → $after"
log "restart: $SERVICES"
# Restart až po dokončení skriptu, aby příkaz z Velína stihl nahlásit výsledek (controller se ukončí).
systemd-run --on-active=2 --quiet --unit="motogo-update-restart-$$" \
  /usr/bin/systemctl restart $SERVICES 2>/dev/null \
  || systemctl restart $SERVICES
log "=== update hotov ==="
