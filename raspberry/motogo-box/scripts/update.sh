#!/usr/bin/env bash
# MotoGo Box — aktualizace software v /opt/motogo. Volá se ručně (sudo) nebo příkazem
# `update_software` z Velína (sudo /usr/local/sbin/motogo-update — root-owned kopie tohoto skriptu;
# sudoers ho povoluje JEN bez argumentů).
#
# Zdroj nové verze:
#   1. argument $1 = adresář s balíkem (raspberry/motogo-box nebo kořen repa Vel-n) — JEN při ručním
#      spuštění rootem; přes sudo od uživatele motogo se argument odmítá (jinak by šlo podstrčit
#      vlastní sudoers/unity a získat root),
#   2. /etc/motogo/source_dir (root-owned, uložil install.sh). Je-li to git checkout, nejdřív
#      `git pull --ff-only` JAKO VLASTNÍK checkoutu (jeho credential helper / deploy key — root žádné
#      nemá a nesmí nechávat v checkoutu root-owned soubory); neúspěšný pull = konec s kódem 3
#      (Velín ukáže selhání), nic se neinstaluje.
# Poté: rsync do /opt/motogo, pip jako motogo (jen v mezích requirements.txt, bez slepého --upgrade),
# root-owned kopie skriptů do /usr/local/sbin, změněné systemd unity + sudoers + polkit pravidlo,
# restart motogo-controller + motogo-health. Venv patří uživateli motogo → root ho NIKDY nespouští
# (verze se zjišťuje přes runuser -u motogo). Log: /var/log/motogo-update.log (root-owned).
# Návratové kódy: 0 OK, 2 chyba vstupu/zdroje, 3 git pull selhal.
set -euo pipefail

APP_DIR="/opt/motogo"
VENV="$APP_DIR/venv"
LOG="/var/log/motogo-update.log"
SRC_FILE="/etc/motogo/source_dir"
POLKIT_RULE="50-motogo-kiosk.rules"
SRC="${1:-}"
SERVICES="motogo-controller motogo-health"
APP_USER="motogo"
[[ -L "$LOG" ]] && LOG=/dev/null      # do symlinku root nikdy nepíše

log() {
  local msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
  echo "$msg"
  echo "$msg" >> "$LOG" 2>/dev/null || true
}
as_user() { runuser -u "$1" -- "${@:2}"; }   # runuser nastaví HOME/USER cílového uživatele (git credentials, pip cache)
version() {
  [[ -x "$VENV/bin/python" ]] || { echo '?'; return 0; }
  (cd "$APP_DIR" && as_user "$APP_USER" "$VENV/bin/python" -m motogo_box version 2>/dev/null) || echo '?'
}

if [[ "$(id -u)" -ne 0 ]]; then echo "Spusť jako root (sudo)"; exit 2; fi
if [[ -n "$SRC" && -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  log "CHYBA: přes sudo (uživatel $SUDO_USER) nelze zadat zdrojový adresář — používá se jen $SRC_FILE"; exit 2
fi
touch "$LOG" 2>/dev/null || true
log "=== update start (zdroj: ${SRC:-$SRC_FILE}) ==="
before="$(version)"

# ── zdroj ─────────────────────────────────────────────────────────────────────
if [[ -z "$SRC" ]]; then
  if [[ ! -r "$SRC_FILE" || "$(stat -c %u "$SRC_FILE")" != "0" ]]; then
    log "CHYBA: $SRC_FILE chybí nebo nepatří rootu (spusť install.sh)"; exit 2
  fi
  SRC="$(head -n1 "$SRC_FILE" | tr -d '[:space:]')"
fi
[[ -n "$SRC" && -d "$SRC" ]] || { log "CHYBA: zdrojový adresář '${SRC:-?}' neexistuje"; exit 2; }
src_owner="$(stat -c %U "$SRC")"
if [[ "$src_owner" == "$APP_USER" ]]; then
  log "CHYBA: zdroj $SRC patří uživateli $APP_USER — z něj se sudoers/unity/skripty instalovat nesmí"; exit 2
fi
if as_user "$src_owner" git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  repo_root="$(as_user "$src_owner" git -C "$SRC" rev-parse --show-toplevel)"
  owner="$(stat -c %U "$repo_root")"
  branch="$(as_user "$owner" git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  log "git pull --ff-only v $repo_root (větev $branch, jako uživatel $owner)"
  if ! as_user "$owner" git -C "$repo_root" pull --ff-only 2>&1 | tee -a "$LOG"; then
    log "CHYBA: git pull selhal (síť, přihlášení k remote, konflikt / větev bez upstreamu) — nic se neinstaluje"
    log "       bezobslužný update potřebuje u uživatele $owner credential helper nebo deploy key bez hesla"
    exit 3
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

# pip jen doplní/vymění balíky, které NEsplňují rozsahy v requirements.txt (žádné slepé --upgrade).
# MOTOGO_PIP_UPGRADE=1 (jen ruční běh rootem; sudo env_reset ji maže) = nejnovější verze V RÁMCI rozsahů,
# --upgrade-strategy only-if-needed nesahá na nepřímé závislosti.
pip_args=(install --quiet -r "$APP_DIR/requirements.txt")
[[ "${MOTOGO_PIP_UPGRADE:-0}" == "1" ]] && pip_args+=(--upgrade --upgrade-strategy only-if-needed)
log "pip ${pip_args[*]} (uživatel $APP_USER)"
if ! as_user "$APP_USER" "$VENV/bin/pip" "${pip_args[@]}" 2>&1 | tee -a "$LOG"; then
  log "UPOZORNĚNÍ: pip install selhal (offline?) — pokračuji se stávajícími balíky"
fi

# ── root-owned kopie skriptů pro sudo (nikdy nespouštět soubory zapisovatelné uživatelem motogo) ──
install -m 755 -o root -g root "$APP_DIR/scripts/update.sh"          /usr/local/sbin/motogo-update
install -m 755 -o root -g root "$APP_DIR/scripts/usbreset-modem.sh"  /usr/local/sbin/motogo-usbreset

# ── změněné unity/sudoers/polkit (jen aktualizace souborů, enable zůstává) ───
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
if [[ -f "$APP_DIR/systemd/$POLKIT_RULE" ]] && ! cmp -s "$APP_DIR/systemd/$POLKIT_RULE" "/etc/polkit-1/rules.d/$POLKIT_RULE"; then
  mkdir -p /etc/polkit-1/rules.d
  install -m 644 -o root -g root "$APP_DIR/systemd/$POLKIT_RULE" "/etc/polkit-1/rules.d/$POLKIT_RULE"
  log "aktualizováno polkit pravidlo $POLKIT_RULE"
fi

after="$(version)"
if [[ "$before" == "$after" ]]; then log "verze: $after (beze změny verze — soubory přesto obnoveny)"
else log "verze: $before → $after"; fi
log "restart: $SERVICES"
# Restart až po dokončení skriptu, aby příkaz z Velína stihl nahlásit výsledek (controller se ukončí).
systemd-run --on-active=2 --quiet --unit="motogo-update-restart-$$" \
  /usr/bin/systemctl restart $SERVICES 2>/dev/null \
  || systemctl restart $SERVICES
log "=== update hotov ==="
