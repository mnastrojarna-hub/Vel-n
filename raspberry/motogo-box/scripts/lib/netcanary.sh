#!/usr/bin/env bash
# MotoGo Box — síťový canary pro update.sh (2026-09-26, po incidentu s „bránou kabelem“):
# ŽÁDNÁ změna síťových profilů z aktualizace nesmí nechat jednotku offline. Před síťovým blokem se změří internet
# a zazálohují profily NM; po bloku se měří znovu (3× během ~60 s). Byl-li internet PŘED změnou v pořádku a PO ní ne,
# profily se vrátí ze zálohy (nmcli con reload + con up) a do /var/lib/motogo/net_rollback se zapíše značka, kterou
# controller při startu nahlásí do kiosk_logs jako NET_FIX (error) — aby bylo vždy jasné, co se stalo.
# Použití (source z update.sh):  netcanary_begin ; …síťové změny… ; netcanary_end
# Testovatelné: NETCANARY_SLEEP=0, NETCANARY_PROFILE_DIR, NETCANARY_STATE_DIR, NETCANARY_MARKER, falešné curl/nmcli v PATH.
NETCANARY_PROFILE_DIR="${NETCANARY_PROFILE_DIR:-/etc/NetworkManager/system-connections}"
NETCANARY_STATE_DIR="${NETCANARY_STATE_DIR:-/var/lib/motogo/netcanary}"
NETCANARY_MARKER="${NETCANARY_MARKER:-/var/lib/motogo/net_rollback}"
NETCANARY_SLEEP="${NETCANARY_SLEEP:-20}"
NETCANARY_PROFILES=(motogo-lan motogo-lte)
NETCANARY_BEFORE=""          # ok | fail | "" (neměřeno)

_nc_log() { if declare -F log >/dev/null 2>&1; then log "canary: $*"; else echo "canary: $*"; fi; }

netcanary_probe() {  # 0 = internet OK (HTTP 204 od Google, nebo TCP 1.1.1.1:443), 1 = ne
  local code
  code="$(curl -sS -m 8 -o /dev/null -w '%{http_code}' https://www.google.com/generate_204 2>/dev/null || true)"
  [[ "$code" == "204" ]] && return 0
  timeout 6 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' 2>/dev/null && return 0
  return 1
}

netcanary_begin() {
  mkdir -p "$NETCANARY_STATE_DIR" 2>/dev/null || true
  local p
  for p in "${NETCANARY_PROFILES[@]}"; do
    [[ -f "$NETCANARY_PROFILE_DIR/$p.nmconnection" ]] && cp -a "$NETCANARY_PROFILE_DIR/$p.nmconnection" "$NETCANARY_STATE_DIR/$p.pre" 2>/dev/null
  done
  if netcanary_probe; then NETCANARY_BEFORE="ok"; else NETCANARY_BEFORE="fail"; fi
  _nc_log "internet před síťovými změnami: $NETCANARY_BEFORE"
}

netcanary_end() {
  [[ "$NETCANARY_BEFORE" == "ok" ]] || { _nc_log "před změnami internet nebyl ($NETCANARY_BEFORE) — rollback se neřeší"; return 0; }
  local i
  for i in 1 2 3; do
    if netcanary_probe; then _nc_log "internet po síťových změnách OK (pokus $i)"; return 0; fi
    (( i < 3 )) && sleep "$NETCANARY_SLEEP"
  done
  _nc_log "CHYBA: internet po síťových změnách nefunguje → vracím profily NM ze zálohy"
  local p restored=()
  for p in "${NETCANARY_PROFILES[@]}"; do
    if [[ -f "$NETCANARY_STATE_DIR/$p.pre" ]]; then
      install -m 600 -o root -g root "$NETCANARY_STATE_DIR/$p.pre" "$NETCANARY_PROFILE_DIR/$p.nmconnection" 2>/dev/null \
        || cp "$NETCANARY_STATE_DIR/$p.pre" "$NETCANARY_PROFILE_DIR/$p.nmconnection"
      restored+=("$p")
    fi
  done
  nmcli con reload >/dev/null 2>&1 || true
  for p in "${restored[@]}"; do nmcli -w 30 con up "$p" >/dev/null 2>&1 || true; done
  local verdict="fail"
  netcanary_probe && verdict="ok"
  printf '{"ts":"%s","restored":"%s","internet_after_rollback":"%s"}\n' "$(date -Is)" "${restored[*]}" "$verdict" > "$NETCANARY_MARKER" 2>/dev/null || true
  chmod 644 "$NETCANARY_MARKER" 2>/dev/null || true
  _nc_log "profily vráceny (${restored[*]:-žádné}); internet po rollbacku: $verdict; značka $NETCANARY_MARKER"
  return 0
}
