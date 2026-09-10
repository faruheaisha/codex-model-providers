#!/usr/bin/env bash
# codex-switch.sh - switch the active model provider of Codex by rewriting the
# top-level keys of $CODEX_HOME/config.toml. POSIX-ish bash + awk only: no jq,
# no python, no bash 4 features (so macOS /bin/bash 3.2 works).
#
# On Windows use codex-switch.ps1 instead: under Git Bash/MSYS `$HOME` is a
# POSIX path (/c/Users/you) and Codex, a native Windows binary, will not accept
# the expanded path.
#
# Presets live in $CODEX_HOME/provider-presets.conf and use the same format as
# the PowerShell script:
#
#     [deepseek]
#     model = deepseek-flash
#     model_provider = deepseek
#     model_catalog_json = $HOME/.codex/model-catalog.deepseek.json
#     web_search = disabled
#
# An empty value removes the key, which is how you return to the built-in
# OpenAI provider and its stock catalog.
#
# Usage:
#   ./codex-switch.sh --list
#   ./codex-switch.sh --preset deepseek
#   ./codex-switch.sh --preset gpt --model gpt-5.6-terra
#   ./codex-switch.sh --status
#   ./codex-switch.sh --preset gpt --restart

set -eu

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG="${CODEX_HOME_DIR}/config.toml"
PRESETS="${CODEX_HOME_DIR}/provider-presets.conf"
PRESET=""
MODEL=""
MODE="switch"
RESTART=0

while [ $# -gt 0 ]; do
  case "$1" in
    --preset|-p) PRESET="${2:-}"; shift 2 ;;
    --model|-m) MODEL="${2:-}"; shift 2 ;;
    --list|-l) MODE="list"; shift ;;
    --status|-s) MODE="status"; shift ;;
    --config) CONFIG="${2:-}"; shift 2 ;;
    --presets) PRESETS="${2:-}"; shift 2 ;;
    --restart) RESTART=1; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ "$MODE" = "switch" ] && [ -z "$PRESET" ]; then MODE="list"; fi

if [ ! -f "$PRESETS" ]; then
  mkdir -p "$(dirname "$PRESETS")"
  cat > "$PRESETS" <<'EOF'
# Presets used by codex-switch.sh / codex-switch.ps1.
# Empty value = remove the key from config.toml.

[gpt]
model = gpt-5.6-sol
model_provider =
model_catalog_json =
web_search =

[deepseek]
model = deepseek-flash
model_provider = deepseek
model_catalog_json = ~/.codex/model-catalog.deepseek.json
web_search = disabled
EOF
  echo "Created default presets: $PRESETS"
fi

if [ ! -f "$CONFIG" ]; then
  echo "config.toml not found: $CONFIG" >&2
  exit 1
fi

if [ "$MODE" = "list" ]; then
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*\[.*\][[:space:]]*$/ {
      section = $0
      sub(/^[[:space:]]*\[/, "", section)
      sub(/\][[:space:]]*$/, "", section)
      if (!seen[section]++) { order[++n] = section }
      next
    }
    section != "" && /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*=/ {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      key = line
      sub(/[[:space:]]*=.*$/, "", key)
      value = line
      sub(/^[^=]*=[[:space:]]*/, "", value)
      gsub(/^"|"$/, "", value)
      if (value != "") { keys[section] = (section in keys ? keys[section] ", " : "") key }
    }
    END {
      for (i = 1; i <= n; i++) printf "  %-12s -> %s\n", order[i], keys[order[i]]
    }
  ' "$PRESETS"
  echo
  echo "Use: codex-switch.sh --preset <name>"
  exit 0
fi

if [ "$MODE" = "status" ]; then
  echo "config   : $CONFIG"
  awk '
    /^[[:space:]]*\[/ { exit }
    /^[[:space:]]*model[[:space:]]*=/ {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/^"|"$/, "", v); print "model    : " v
    }
    /^[[:space:]]*model_provider[[:space:]]*=/ {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/^"|"$/, "", v); print "provider : " v
    }
    /^[[:space:]]*model_catalog_json[[:space:]]*=/ {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/^"|"$/, "", v); print "catalog  : " v
    }
    /^[[:space:]]*web_search[[:space:]]*=/ {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/^"|"$/, "", v); print "web_search: " v
    }
  ' "$CONFIG"
  exit 0
fi

if ! grep -q "^\[$PRESET\]" "$PRESETS"; then
  echo "Unknown preset '$PRESET'. Available:" >&2
  grep -o '^\[[^]]*\]' "$PRESETS" | tr -d '[]' | sed 's/^/  /' >&2
  exit 1
fi

BACKUP_DIR="${CODEX_HOME_DIR}/backups"
mkdir -p "$BACKUP_DIR"
BACKUP="${BACKUP_DIR}/config.toml.$(date +%Y%m%d-%H%M%S)"
cp "$CONFIG" "$BACKUP"

TMP="$(mktemp "${TMPDIR:-/tmp}/codex-config.XXXXXX")"

awk -v preset="$PRESET" -v model_override="$MODEL" -v home="$HOME" '
  function expand(v) {
    if (substr(v, 1, 1) == "~") {
      sub(/^~[\/\\]*/, "", v)
      v = home "/" v
    }
    return v
  }
  # TOML basic strings treat backslash as an escape; escape it (and quotes) so
  # Windows-style values cannot break config.toml parsing.
  function toml(v) {
    gsub(/\\/, "\\\\", v)
    gsub(/"/, "\\\"", v)
    return v
  }
  NR == FNR {
    line = $0; sub(/\r$/, "", line)
    if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) next
    if (line ~ /^[[:space:]]*\[.*\][[:space:]]*$/) {
      section = line
      sub(/^[[:space:]]*\[/, "", section)
      sub(/\][[:space:]]*$/, "", section)
      next
    }
    if (section != "" && line ~ /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*=/) {
      key = line; sub(/^[[:space:]]*/, "", key); sub(/[[:space:]]*=.*$/, "", key)
      value = line; sub(/^[^=]*=[[:space:]]*/, "", value)
      gsub(/^"|"$/, "", value)
      managed[key] = 1
      if (section == preset) {
        value = expand(value)
        if (key == "model" && model_override != "") value = model_override
        val[key] = value
        tkeys[++tn] = key
      }
    }
    next
  }
  {
    line = $0; sub(/\r$/, "", line)
    if (!inbody) {
      if (line ~ /^[[:space:]]*\[/) {
        for (i = 1; i <= tn; i++) if (!written[tkeys[i]] && val[tkeys[i]] != "") {
          print tkeys[i] " = \"" toml(val[tkeys[i]]) "\""
        }
        if (!written["model"] && val["model"] != "") print "model = \"" toml(val["model"]) "\""
        print ""
        inbody = 1
        print line
        next
      }
      if (line ~ /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*=/) {
        key = line; sub(/^[[:space:]]*/, "", key); sub(/[[:space:]]*=.*$/, "", key)
        if (key in managed) {
          written[key] = 1
          if (val[key] != "") print key " = \"" toml(val[key]) "\""
          next
        }
      }
      if (line ~ /^[[:space:]]*$/) next
      print line
      next
    }
    print line
  }
  END {
    if (!inbody) {
      for (i = 1; i <= tn; i++) if (!written[tkeys[i]] && val[tkeys[i]] != "") {
        print tkeys[i] " = \"" toml(val[tkeys[i]]) "\""
      }
      if (!written["model"] && val["model"] != "") print "model = \"" toml(val["model"]) "\""
    }
  }
' "$PRESETS" "$CONFIG" > "$TMP"

mv "$TMP" "$CONFIG"

echo "Switched Codex to preset: $PRESET"
echo "  backup: $BACKUP"
echo
echo "Start a NEW task in Codex; running tasks keep their provider."

if [ "$RESTART" = "1" ]; then
  echo
  echo "Restarting the Codex desktop app..."
  pkill -f "ChatGPT.app" 2>/dev/null || true
  pkill -f "/app/ChatGPT" 2>/dev/null || true
  sleep 1
  if command -v codex >/dev/null 2>&1; then
    codex app >/dev/null 2>&1 &
  else
    echo "Start the Codex app manually." >&2
  fi
fi
