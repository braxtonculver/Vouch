#!/usr/bin/env bash
# gamecheck — ProtonDB + AreWeAntiCheat via fzf
# Deps: fzf, curl, python3
#
# Created by Thrausi
#
# ── Hyprland popup keybind ────────────────────────────────────────────────────
# bind = $mainMod, G, exec, [float; size 960 640; center] 'TERMINAL' -e 'SCRIPTDIR'
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT=$(realpath "$0")
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/gamecheck"
AWACY_CACHE="$CACHE_DIR/awacy.json"
AWACY_URL="https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/master/games.json"

mkdir -p "$CACHE_DIR"

# ── Colors ────────────────────────────────────────────────────────────────────
R=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
SILVER=$'\033[0;37m'
ORANGE=$'\033[0;33m'

tier_color() {
  case "$1" in
  platinum) printf '%s' "$CYAN" ;;
  gold) printf '%s' "$YELLOW" ;;
  silver) printf '%s' "$SILVER" ;;
  bronze) printf '%s' "$ORANGE" ;;
  borked) printf '%s' "$RED" ;;
  *) printf '%s' "$DIM" ;;
  esac
}

awacy_color() {
  case "$1" in
  Supported) printf '%s' "$GREEN" ;;
  Running) printf '%s' "$YELLOW" ;;
  Planned) printf '%s' "$BLUE" ;;
  Broken) printf '%s' "$RED" ;;
  Denied) printf '%s' "$RED" ;;
  *) printf '%s' "$DIM" ;;
  esac
}

# ── AWACY cache ───────────────────────────────────────────────────────────────
ensure_awacy() {
  if [[ ! -f "$AWACY_CACHE" ]]; then
    printf "${DIM}Fetching AreWeAntiCheat database...${R}\n" >&2
    if ! curl -sf --max-time 30 "$AWACY_URL" -o "${AWACY_CACHE}.tmp" 2>/dev/null; then
      rm -f "${AWACY_CACHE}.tmp"
      # Not fatal — AWACY info will just be unavailable
      return 1
    fi
    mv "${AWACY_CACHE}.tmp" "$AWACY_CACHE"
  else
    local age=$(($(date +%s) - $(stat -c %Y "$AWACY_CACHE")))
    if ((age > 86400)); then
      (curl -sf --max-time 30 "$AWACY_URL" -o "${AWACY_CACHE}.tmp" 2>/dev/null &&
        mv "${AWACY_CACHE}.tmp" "$AWACY_CACHE" ||
        rm -f "${AWACY_CACHE}.tmp") &
    fi
  fi
}

# ── --search QUERY ────────────────────────────────────────────────────────────
# Outputs: TYPE:ID \t NAME
#   steam:APPID  — found on Steam (may also be in AWACY)
#   awacy:SLUG   — non-Steam AWACY entry (no Steam appid)
do_search() {
  local query="${1:-}"
  [[ ${#query} -lt 2 ]] && exit 0

  local encoded
  encoded=$(python3 -c \
    "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" \
    "$query" 2>/dev/null) || encoded="${query// /+}"

  # Steam search
  local steam_json=""
  steam_json=$(curl -sf --max-time 10 \
    "https://store.steampowered.com/api/storesearch/?term=${encoded}&l=english&cc=US" \
    2>/dev/null) || true

  # AWACY non-Steam name search (only entries without a steam appid)
  local awacy_extra=""
  if [[ -f "$AWACY_CACHE" ]]; then
    awacy_extra=$(python3 -c "
import json, sys
query = '$query'.lower()
with open('$AWACY_CACHE') as f:
    data = json.load(f)
for g in data:
    name = g.get('name', '')
    slug = g.get('slug', '')
    steam = str(g.get('storeIds', {}).get('steam', ''))
    # Only emit if no Steam appid and name matches query
    if not steam and query in name.lower() and name and slug:
        print('awacy:' + slug + '\t' + name)
" 2>/dev/null) || true
  fi

  # Parse Steam results via python, cache names
  local steam_lines=""
  if [[ -n "$steam_json" ]]; then
    steam_lines=$(printf '%s' "$steam_json" | python3 -c "
import sys, json, os
cache_dir = '$CACHE_DIR'
data = json.load(sys.stdin)
for item in data.get('items', []):
    appid = str(item.get('id', ''))
    name  = item.get('name', '')
    if not appid or not name:
        continue
    with open(os.path.join(cache_dir, 'name_' + appid), 'w') as f:
        f.write(name)
    print('steam:' + appid + '\t' + name)
" 2>/dev/null) || true
  fi

  # Merge: Steam results first, then non-Steam AWACY entries
  printf '%s\n%s\n' "$steam_lines" "$awacy_extra" | grep -v '^$' || true
}

# ── --preview TYPE:ID ─────────────────────────────────────────────────────────
do_preview() {
  local id="${1:-}"
  [[ -z "$id" ]] && exit 0

  local type="${id%%:*}"
  local key="${id#*:}"

  local name="" steam_id="" awacy_status="not listed" anticheats="" notes="" native="False"

  # Resolve steam_id and AWACY data based on type
  if [[ "$type" == "steam" ]]; then
    steam_id="$key"
    [[ -f "$CACHE_DIR/name_$steam_id" ]] && name=$(cat "$CACHE_DIR/name_$steam_id")
    [[ -z "$name" ]] && name="App $steam_id"

    # AWACY lookup by steam appid
    if [[ -f "$AWACY_CACHE" ]]; then
      mapfile -t awacy_info < <(python3 -c "
import json
with open('$AWACY_CACHE') as f:
    data = json.load(f)
match = next((g for g in data if str(g.get('storeIds',{}).get('steam','')) == '$steam_id'), None)
if match:
    status   = match.get('status', 'Unknown')
    acs      = ', '.join(match.get('anticheats', []))
    notes    = match.get('notes', [])
    note_txt = ' | '.join(n[0] for n in notes if isinstance(n, list) and n) if notes else ''
    native   = str(match.get('native', False))
    print(status); print(acs); print(note_txt); print(native)
else:
    print('not listed'); print(''); print(''); print('False')
" 2>/dev/null)
      awacy_status="${awacy_info[0]:-not listed}"
      anticheats="${awacy_info[1]:-}"
      notes="${awacy_info[2]:-}"
      native="${awacy_info[3]:-False}"
    fi

  elif [[ "$type" == "awacy" ]]; then
    # Non-Steam AWACY entry — no ProtonDB possible
    if [[ -f "$AWACY_CACHE" ]]; then
      mapfile -t entry < <(python3 -c "
import json
with open('$AWACY_CACHE') as f:
    data = json.load(f)
match = next((g for g in data if g.get('slug','') == '$key'), None)
if match:
    name     = match.get('name', '$key')
    status   = match.get('status', 'Unknown')
    acs      = ', '.join(match.get('anticheats', []))
    notes    = match.get('notes', [])
    note_txt = ' | '.join(n[0] for n in notes if isinstance(n, list) and n) if notes else ''
    native   = str(match.get('native', False))
    print(name); print(status); print(acs); print(note_txt); print(native)
else:
    print('$key'); print('Unknown'); print(''); print(''); print('False')
" 2>/dev/null)
      name="${entry[0]:-$key}"
      awacy_status="${entry[1]:-Unknown}"
      anticheats="${entry[2]:-}"
      notes="${entry[3]:-}"
      native="${entry[4]:-False}"
    fi
  fi

  local ac
  ac=$(awacy_color "$awacy_status")
  local hr="${DIM}$(printf '─%.0s' {1..50})${R}"

  printf '\n'
  printf "  ${BOLD}%s${R}\n" "$name"
  [[ "$native" == "True" ]] && printf "  ${GREEN}  Native Linux port${R}\n"
  printf "  %b\n\n" "$hr"

  # AreWeAntiCheat
  printf "  ${BOLD}🛡  AreWeAntiCheat${R}\n"
  printf "  ┌──────────────────────────────────────────────\n"
  printf "  │  Status      %b${BOLD}%s${R}\n" "$ac" "$awacy_status"
  [[ -n "$anticheats" ]] && printf "  │  AntiCheat   %s\n" "$anticheats"
  [[ -n "$notes" ]] && printf "  │  Notes       %s\n" "$notes"
  if [[ "$awacy_status" == "not listed" ]]; then
    printf "  └─ ${DIM}not in AWACY database${R}\n\n"
  else
    printf "  └─ ${DIM}areweanticheatyet.com${R}\n\n"
  fi

  # ProtonDB — Steam games only
  if [[ -n "$steam_id" ]]; then
    local pdb_cache="$CACHE_DIR/pdb_${steam_id}.json"
    local pdb_age=9999999
    [[ -f "$pdb_cache" ]] && pdb_age=$(($(date +%s) - $(stat -c %Y "$pdb_cache")))
    if ((pdb_age > 43200)); then
      curl -sf --max-time 6 \
        "https://www.protondb.com/api/v1/reports/summaries/${steam_id}.json" \
        >"$pdb_cache" 2>/dev/null || echo '{}' >"$pdb_cache"
    fi

    mapfile -t pdb < <(python3 -c "
import json
with open('$pdb_cache') as f:
    d = json.load(f)
tier  = d.get('tier', 'no data')
s     = d.get('score')
score = (str(round(s * 100)) + '%') if s is not None else 'N/A'
conf  = d.get('confidence', 'N/A')
print(tier); print(score); print(conf)
" 2>/dev/null)
    local tier="${pdb[0]:-no data}"
    local score="${pdb[1]:-N/A}"
    local conf="${pdb[2]:-N/A}"
    local tc
    tc=$(tier_color "$tier")

    printf "  ${BOLD}  ProtonDB${R}\n"
    printf "  ┌──────────────────────────────────────────────\n"
    printf "  │  Tier        %b${BOLD}%s${R}\n" "$tc" "${tier^^}"
    printf "  │  Score       %s\n" "$score"
    printf "  │  Confidence  %s\n" "$conf"
    printf "  └─ ${DIM}protondb.com/app/%s${R}\n\n" "$steam_id"
  else
    printf "  ${DIM}  ProtonDB — no Steam release${R}\n\n"
  fi
}

# ── --protondb TYPE:ID ────────────────────────────────────────────────────────
do_protondb() {
  local id="${1:-}"
  local type="${id%%:*}"
  local key="${id#*:}"
  [[ "$type" == "steam" ]] && xdg-open "https://www.protondb.com/app/$key" 2>/dev/null
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  ensure_awacy &

  local selected
  selected=$(
    fzf \
      --disabled \
      --ansi \
      --delimiter=$'\t' \
      --with-nth=2 \
      --bind "change:reload:'$SCRIPT' --search {q} 2>/dev/null || true" \
      --bind "ctrl-p:toggle-preview" \
      --bind "ctrl-o:execute-silent('$SCRIPT' --protondb {1} >/dev/null 2>&1 &)" \
      --bind "ctrl-a:execute-silent(xdg-open 'https://areweanticheatyet.com' >/dev/null 2>&1 &)" \
      --preview "'$SCRIPT' --preview {1}" \
      --preview-window="right:55%:wrap" \
      --header $'󰊗 Game Compatibility \u2014 ProtonDB + AreWeAntiCheat\n  Ctrl-O: ProtonDB   Ctrl-A: AWAC   Ctrl-P: toggle preview' \
      --prompt "  " \
      --pointer "▶" \
      --layout=reverse \
      --height=95% \
      --border=rounded \
      --color='header:italic:dim,hl:cyan,hl+:cyan,pointer:cyan,border:dim'
  ) || exit 0

  [[ -z "$selected" ]] && exit 0

  local id name type key
  id=$(cut -f1 <<<"$selected")
  name=$(cut -f2- <<<"$selected")
  type="${id%%:*}"
  key="${id#*:}"

  printf "\n${BOLD}%s${R}\n\n" "$name"

  if [[ "$type" == "steam" ]]; then
    printf "  [1]  ProtonDB       →  protondb.com/app/%s\n" "$key"
    printf "  [2]  AreWeAntiCheat →  areweanticheatyet.com\n"
    printf "  [b]  Both\n\n"
    printf "Open in browser? [1/2/b/N] "
    local choice
    read -r choice
    case "$choice" in
    1) xdg-open "https://www.protondb.com/app/$key" 2>/dev/null ;;
    2) xdg-open "https://areweanticheatyet.com" 2>/dev/null ;;
    b | B)
      xdg-open "https://www.protondb.com/app/$key" 2>/dev/null
      sleep 0.3
      xdg-open "https://areweanticheatyet.com" 2>/dev/null
      ;;
    esac
  else
    printf "  [1]  AreWeAntiCheat →  areweanticheatyet.com\n\n"
    printf "Open in browser? [1/N] "
    local choice
    read -r choice
    [[ "$choice" == "1" ]] && xdg-open "https://areweanticheatyet.com" 2>/dev/null
  fi
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "${1:-}" in
--search) do_search "${2:-}" ;;
--preview) do_preview "${2:-}" ;;
--protondb) do_protondb "${2:-}" ;;
*) main ;;
esac
