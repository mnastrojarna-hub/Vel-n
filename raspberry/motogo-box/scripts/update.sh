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
#      `git fetch origin` JAKO VLASTNÍK checkoutu (jeho credential helper / deploy key — root žádné
#      nemá a nesmí nechávat v checkoutu root-owned soubory) a pak `git merge --ff-only` na cíl:
#      existuje-li regulární soubor /var/lib/motogo/update_ref (zapsal controller z params.ref příkazu
#      update_software; obsah ^[0-9a-f]{7,40}$, jiný obsah = varování a ignoruje se, hodnota se nikdy
#      neechuje) → tento commit, jinak @{upstream} větve. Soubor se po přečtení smaže. Cíl, který není
#      dopředným potomkem HEAD (ff selže) = konec s kódem 3, nic se neinstaluje — rollback se dělá
#      revert commitem v main, ne couváním checkoutu.
# Poté: rsync do /opt/motogo, pip jako motogo (jen v mezích requirements.txt, bez slepého --upgrade),
# root-owned kopie skriptů do /usr/local/sbin (motogo-update, motogo-usbreset, motogo-sysupdate),
# změněné systemd unity + sudoers + polkit pravidlo + unattended-upgrades konfigurace (52motogo-unattended
# + drop-in apt-daily-upgrade.timer), restart motogo-controller + motogo-health. Venv patří uživateli
# motogo → root ho NIKDY nespouští (verze se zjišťuje přes runuser -u motogo). Log: /var/log/motogo-update.log.
# Návratové kódy: 0 OK, 2 chyba vstupu/zdroje, 3 git fetch/ff-merge selhal.
set -euo pipefail

APP_DIR="/opt/motogo"
VENV="$APP_DIR/venv"
LOG="/var/log/motogo-update.log"
SRC_FILE="/etc/motogo/source_dir"
REF_FILE="/var/lib/motogo/update_ref"   # zapisuje controller (uživatel motogo) — čte se jen jako regulární soubor
POLKIT_RULE="50-motogo-kiosk.rules"
APT_CONF="52motogo-unattended"
APT_TIMER_DIR="/etc/systemd/system/apt-daily-upgrade.timer.d"
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
# Jen jeden běh najednou (controller to hlídá také; pojistka pro souběh s ručním spuštěním).
LOCK="/run/lock/motogo-update.lock"
mkdir -p "$(dirname "$LOCK")" 2>/dev/null || true
exec 9>"$LOCK"
if ! flock -n 9; then log "CHYBA: motogo-update už běží"; exit 2; fi
# Spuštěno z controlleru (sudo) → běží v cgroupě motogo-controller.service; restart/pád služby by
# rsync/pip uprostřed zabil. Proto se skript znovu spustí ve vlastním transientním scope systemd
# (prostředí i argumenty se dědí; zámek převezme nový běh). Bez systemd-run pokračuje na místě.
if [[ -z "${MOTOGO_UPDATE_SCOPE:-}" ]] && command -v systemd-run >/dev/null 2>&1 \
   && systemd-run --scope --quiet --unit="motogo-update-probe-$$" true >/dev/null 2>&1; then
  export MOTOGO_UPDATE_SCOPE=1
  flock -u 9; exec 9>&-
  exec systemd-run --scope --quiet --unit="motogo-update-$$" "$0" "$@"
fi
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
# Cílový commit z Velína: /var/lib/motogo/update_ref leží v adresáři uživatele motogo → root ho čte JEN jako
# regulární soubor (ne symlink), obsah se validuje dřív, než se kdekoli použije, a do logu se nikdy nevypisuje.
# Soubor se vždy smaže (i neplatný / bez gitu), aby starý cíl nepřežil do dalšího běhu.
target_ref=""
if [[ -e "$REF_FILE" || -L "$REF_FILE" ]]; then
  if [[ -f "$REF_FILE" && ! -L "$REF_FILE" ]]; then
    ref_raw="$(head -c 64 "$REF_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$ref_raw" =~ ^[0-9a-f]{7,40}$ ]]; then target_ref="$ref_raw"
    else log "UPOZORNĚNÍ: $REF_FILE má neplatný obsah (očekávám sha commitu 7–40 hex znaků) — ignoruji, jedu na větev"; fi
  else
    log "UPOZORNĚNÍ: $REF_FILE není regulární soubor — ignoruji, jedu na větev"
  fi
  rm -f "$REF_FILE" 2>/dev/null || true
fi
if as_user "$src_owner" git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  repo_root="$(as_user "$src_owner" git -C "$SRC" rev-parse --show-toplevel)"
  owner="$(stat -c %U "$repo_root")"
  branch="$(as_user "$owner" git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  log "git fetch origin v $repo_root (větev $branch, jako uživatel $owner)"
  if ! as_user "$owner" git -C "$repo_root" fetch --quiet origin 2>&1 | tee -a "$LOG"; then
    log "CHYBA: git fetch selhal (síť, přihlášení k remote) — nic se neinstaluje"
    log "       bezobslužný update potřebuje u uživatele $owner credential helper nebo deploy key bez hesla"
    exit 3
  fi
  if [[ -n "$target_ref" ]]; then merge_target="$target_ref"; log "git merge --ff-only $target_ref (cíl z Velína)"
  else merge_target='@{upstream}'; log "git merge --ff-only @{upstream}"; fi
  if ! as_user "$owner" git -C "$repo_root" merge --ff-only --quiet "$merge_target" 2>&1 | tee -a "$LOG"; then
    log "CHYBA: git merge --ff-only selhal — cíl není dopředný potomek HEAD (rollback = revert commit v main),"
    log "       neznámý commit (není v origin) nebo větev bez upstreamu / lokální změny — nic se neinstaluje"
    exit 3
  fi
  head_sha="$(as_user "$owner" git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo '?')"
  # Cíl, který je PŘEDKEM HEAD, git při --ff-only tiše nechá („Already up to date“) → box by hlásil starou
  # verzi a rollout ve Velíně by vypršel. Proto: HEAD musí být přesně cílový commit, jinak selhání.
  if [[ -n "$target_ref" ]] \
     && [[ "$(as_user "$owner" git -C "$repo_root" rev-parse --verify --quiet "${target_ref}^{commit}" 2>/dev/null)" \
           != "$(as_user "$owner" git -C "$repo_root" rev-parse HEAD 2>/dev/null)" ]]; then
    log "CHYBA: checkout zůstal na $head_sha — cíl $target_ref není dopředný potomek HEAD (starší commit / jiná větev);"
    log "       návrat na starší verzi = revert commit v main, ne couvání checkoutu — nic se neinstaluje"
    exit 3
  fi
  log "checkout na $head_sha"
elif [[ -n "$target_ref" ]]; then
  log "UPOZORNĚNÍ: zdroj $SRC není git checkout — cílový commit z Velína nelze použít, instaluji obsah adresáře"
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
install -m 755 -o root -g root "$APP_DIR/scripts/sysupdate.sh"       /usr/local/sbin/motogo-sysupdate

# unattended-upgrades: balík instaluje install.sh (krok 10) — boxy instalované starší verzí ho nemají a bez něj
# se záplaty OS v noci neinstalují. Doinstalovat (bez apt-get update: seznamy z instalace / z motogo-sysupdate;
# omezeno časem, aby update_software z Velína (900 s) stihl doběhnout). MOTOGO_SKIP_APT=1 = jen ruční běh (sudo env_reset).
if ! command -v unattended-upgrade >/dev/null 2>&1; then
  if [[ "${MOTOGO_SKIP_APT:-0}" == "1" ]]; then
    log "UPOZORNĚNÍ: balík unattended-upgrades chybí (MOTOGO_SKIP_APT=1) — záplaty OS se neinstalují samy; spusť install.sh nebo apt-get install unattended-upgrades"
  else
    log "balík unattended-upgrades chybí — instaluji (apt-get install, max 4 min)"
    if DEBIAN_FRONTEND=noninteractive timeout 240 apt-get install -y -qq --no-install-recommends \
         -o DPkg::Lock::Timeout=120 unattended-upgrades 2>&1 | tee -a "$LOG" >/dev/null; then
      systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
      log "unattended-upgrades nainstalován (záplaty Debian security v noci 04:00, bez restartu)"
    else
      log "UPOZORNĚNÍ: instalace unattended-upgrades selhala (offline / zámek apt / staré seznamy) — záplaty OS se neinstalují samy;"
      log "       spusť: sudo apt-get update && sudo apt-get install unattended-upgrades (nebo install.sh)"
    fi
  fi
fi

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
# unattended-upgrades (jen Debian security, v noci, bez restartu) + drop-in timeru — jako polkit: cmp + install
if [[ -f "$APP_DIR/systemd/$APT_CONF" ]] && ! cmp -s "$APP_DIR/systemd/$APT_CONF" "/etc/apt/apt.conf.d/$APT_CONF"; then
  mkdir -p /etc/apt/apt.conf.d
  install -m 644 -o root -g root "$APP_DIR/systemd/$APT_CONF" "/etc/apt/apt.conf.d/$APT_CONF"
  log "aktualizována konfigurace unattended-upgrades $APT_CONF"
fi
if [[ -f "$APP_DIR/systemd/apt-daily-upgrade-override.conf" ]] \
   && ! cmp -s "$APP_DIR/systemd/apt-daily-upgrade-override.conf" "$APT_TIMER_DIR/motogo.conf"; then
  mkdir -p "$APT_TIMER_DIR"
  install -m 644 -o root -g root "$APP_DIR/systemd/apt-daily-upgrade-override.conf" "$APT_TIMER_DIR/motogo.conf"
  systemctl daemon-reload
  log "aktualizován drop-in apt-daily-upgrade.timer (motogo.conf)"
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
