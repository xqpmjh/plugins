#!/bin/bash
# aof hook — single entry point for UserPromptSubmit and SessionStart.
#
# Reads the hook JSON on stdin and, when there is something to say, prints
# {"hookSpecificOutput":{"hookEventName":..., "additionalContext":...}}.
# Every path exits 0: a broken aof must never block a prompt or a session.
#
# State (written only by this hook; sandboxed Bash cannot write here, but the
# Edit/Write tools can if permissions allow — forging it only toggles formatting):
#   $AOF_HOME/config                  auto=on|off          (default off)
#   $AOF_HOME/sessions/<session_id>   state=on|off, source=auto|manual, html=on|off
#
# Env:
#   AOF_DISABLE=1   do nothing (evaluations, automation)
#   AOF_HOME        state dir, default ~/.claude/aof (tests point it elsewhere)
#   AOF_JQ          jq binary, default jq
#   AOF_DEBUG=1     append decision logs to $AOF_HOME/debug.log

set -u

[ "${AOF_DISABLE:-}" = "1" ] && exit 0

JQ="${AOF_JQ:-jq}"
command -v "$JQ" >/dev/null 2>&1 || exit 0

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
[ -n "${AOF_HOME:-}" ] || { [ -n "${HOME:-}" ] || exit 0; AOF_HOME="${HOME}/.claude/aof"; }
CONFIG="${AOF_HOME}/config"
SESS_DIR="${AOF_HOME}/sessions"
CONTRACT="${ROOT}/rules/contract.md"
HTML_RULES="${ROOT}/rules/html.md"
TEMPLATE="${ROOT}/templates/page.html"

dbg() {
  [ "${AOF_DEBUG:-}" = "1" ] || return 0
  mkdir -p "${AOF_HOME}" 2>/dev/null &&
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"${AOF_HOME}/debug.log" 2>/dev/null
  return 0
}

input=$(cat)
event=$(printf '%s' "$input" | "$JQ" -r '.hook_event_name // empty' 2>/dev/null) || exit 0
sid=$(printf '%s' "$input" | "$JQ" -r '.session_id // empty' 2>/dev/null) || exit 0
valid_sid=0
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,128}$ ]] && valid_sid=1
SESS_FILE="${SESS_DIR}/${sid}"
# Log the sid only once validated, so a crafted sid cannot forge log lines.
if [ "$valid_sid" = 1 ]; then dbg "event=${event} sid=${sid}"; else dbg "event=${event} sid=<invalid>"; fi

# All rule files must be present; otherwise aof stays silent (no state change).
rules_ok=0
[ -r "$CONTRACT" ] && [ -r "$HTML_RULES" ] && rules_ok=1

# --- small helpers ---------------------------------------------------------

# kv_get FILE KEY -> value of the first KEY=... line, empty if absent
kv_get() {
  [ -f "$1" ] || return 0
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1
}

# atomic_write FILE CONTENT — temp file in the same dir, then rename
atomic_write() {
  local dir tmp
  dir=$(dirname "$1")
  mkdir -p "$dir" 2>/dev/null || return 1
  tmp=$(mktemp "${dir}/.aof.XXXXXX" 2>/dev/null) || return 1
  # A temp file left by a failed write is removed by the 14-day cleanup.
  printf '%s\n' "$2" >"$tmp" 2>/dev/null && mv -f "$tmp" "$1" 2>/dev/null
}

# html_rules — rules/html.md with {{TEMPLATE}} replaced by the template path.
# awk with index() instead of sed, so |, & or \ in the path are taken literally.
html_rules() {
  AOF_T="$TEMPLATE" awk '{
    out = ""; s = $0
    while ((i = index(s, "{{TEMPLATE}}")) > 0) {
      out = out substr(s, 1, i - 1) ENVIRON["AOF_T"]; s = substr(s, i + 12)
    }
    print out s
  }' "$HTML_RULES" 2>/dev/null
}

auto_cfg() {
  local v
  v=$(kv_get "$CONFIG" auto)
  [ "$v" = "on" ] && echo on || echo off
}

load_state() {
  st_state=$(kv_get "$SESS_FILE" state)
  st_source=$(kv_get "$SESS_FILE" source)
  st_html=$(kv_get "$SESS_FILE" html)
  [ "$st_state" = "on" ] || st_state=off
  [ "$st_source" = "auto" ] || st_source=manual
  [ "$st_html" = "on" ] || st_html=off
}

save_state() {
  atomic_write "$SESS_FILE" "state=${st_state}
source=${st_source}
html=${st_html}"
}

emit() {
  "$JQ" -n --arg ev "$event" --arg ctx "$1" \
    '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}}'
}

state_summary() {
  local html="$st_html"
  [ "$st_state" = off ] && [ "$st_html" = on ] && html="on (inactive while aof is off)"
  echo "[aof] Session state: ${st_state} (source: ${st_source}); HTML sub-mode: ${html}; auto-start for new sessions: $(auto_cfg). State file: ${SESS_FILE}"
}

# Contract (+ HTML rules when the sub-mode is on), framed as the content the
# user switched on, so it reads as user configuration rather than an order.
contract_block() {
  local out
  out="[aof] The user enabled the aof output contract for this session. Its text follows; it applies to final replies until a later [aof] block says the session state is off.

$(cat "$CONTRACT" 2>/dev/null)"
  if [ "$st_html" = "on" ]; then
    out="${out}

$(html_rules)"
  fi
  printf '%s' "$out"
}

OFF_TEXT="[aof] The user switched aof off for this session. The aof output contract and aof HTML rules earlier in this conversation no longer apply; replies follow the user's normal instructions only."

USAGE="[aof] Unrecognised argument; nothing was changed. Usage: /aof [on|off|status|auto on|auto off|html on|html off]."

# --- SessionStart ----------------------------------------------------------

handle_session_start() {
  local source_ev
  source_ev=$(printf '%s' "$input" | "$JQ" -r '.source // empty' 2>/dev/null)
  dbg "session_start source=${source_ev}"

  local had_file=0
  [ "$valid_sid" = 1 ] && [ -f "$SESS_FILE" ] && had_file=1

  # Housekeeping: drop session state untouched for 14 days. Runs after had_file
  # and never removes this session's own file. Prompts touch the file, so only
  # sessions idle for 14 days age out.
  [ -d "$SESS_DIR" ] && find "$SESS_DIR" -type f -mtime +14 ! -path "$SESS_FILE" -delete 2>/dev/null

  [ "$valid_sid" = 1 ] || exit 0
  [ "$rules_ok" = 1 ] || exit 0
  load_state

  case "$source_ev" in
    startup | clear | fork)
      if [ "$had_file" = 0 ] && [ "$(auto_cfg)" = on ]; then
        st_state=on st_source=auto st_html=off
        save_state && emit "$(contract_block)"
      elif [ "$had_file" = 1 ] && [ "$st_state" = on ]; then
        emit "$(contract_block)"
      fi
      ;;
    resume)
      # The contract is already in the resumed transcript when state is on.
      if [ "$had_file" = 0 ] && [ "$(auto_cfg)" = on ]; then
        st_state=on st_source=auto st_html=off
        save_state && emit "$(contract_block)"
      fi
      ;;
    compact)
      [ "$st_state" = on ] && emit "$(contract_block)"
      ;;
  esac
  exit 0
}

# --- UserPromptSubmit ------------------------------------------------------

# Prints the normalised argument string ("" for bare /aof) when the whole
# prompt is a single-line /aof command; prints NOCMD otherwise.
parse_command() {
  printf '%s' "$input" | "$JQ" -r '
    (.prompt // "")
    # Commands are short; skip the regexes on long input (the trim is quadratic).
    | if length > 512 then "" else . end
    | gsub("^[\\s　]+|[\\s　]+$"; "")
    | if test("[\\n\\r]") then "NOCMD"
      else [capture("^/(?:aof|aof:aof)(?<rest>(?:[ \\t　]+.*)?)$"; "i")]
           | if length == 0 then "NOCMD"
             else "CMD:" + (.[0].rest | gsub("^[ \\t　]+"; "") | gsub("[ \\t　]+"; " ") | ascii_downcase)
             end
      end' 2>/dev/null
}

handle_prompt() {
  local parsed arg was
  parsed=$(parse_command)
  dbg "prompt parsed=${parsed}"

  if [ "${parsed#CMD:}" = "$parsed" ]; then
    # Ordinary prompt: no output. Touch the state file so an active session is
    # not aged out by the 14-day cleanup.
    [ "$valid_sid" = 1 ] && [ "$rules_ok" = 1 ] || exit 0
    [ -f "$SESS_FILE" ] && touch "$SESS_FILE" 2>/dev/null
    exit 0
  fi

  arg="${parsed#CMD:}"
  if [ "$valid_sid" = 0 ]; then
    emit "[aof] The hook received no valid session_id, so the session state was not changed."
    exit 0
  fi
  if [ "$rules_ok" = 0 ]; then
    emit "[aof] The plugin's rule files are missing under ${ROOT}/rules, so the session state was not changed."
    exit 0
  fi
  load_state
  was="$st_state"

  case "$arg" in
    "" | on)
      st_state=on st_source=manual
      save_state || { emit "[aof] Could not write ${SESS_FILE}; state not changed."; exit 0; }
      if [ "$was" = on ]; then
        emit "$(state_summary) aof was already on; the contract delivered earlier still applies."
      else
        emit "$(state_summary)

$(contract_block)"
      fi
      ;;
    off)
      st_state=off
      save_state || { emit "[aof] Could not write ${SESS_FILE}; state not changed."; exit 0; }
      emit "$(state_summary)

${OFF_TEXT}"
      ;;
    status)
      emit "$(state_summary)"
      ;;
    "auto on" | "auto off")
      atomic_write "$CONFIG" "auto=${arg#auto }" ||
        { emit "[aof] Could not write ${CONFIG}; auto-start not changed."; exit 0; }
      emit "$(state_summary) Auto-start changes apply to sessions started or cleared from now on; this session's state is unchanged."
      ;;
    "html on")
      st_html=on
      if [ "$was" = off ]; then st_state=on st_source=manual; fi
      save_state || { emit "[aof] Could not write ${SESS_FILE}; state not changed."; exit 0; }
      if [ "$was" = off ]; then
        emit "$(state_summary)

$(contract_block)"
      else
        emit "$(state_summary)

$(html_rules)"
      fi
      ;;
    "html off")
      st_html=off
      save_state || { emit "[aof] Could not write ${SESS_FILE}; state not changed."; exit 0; }
      emit "$(state_summary) The aof HTML rules no longer apply; do not produce aof pages."
      ;;
    *)
      emit "$(state_summary)

${USAGE}"
      ;;
  esac
  exit 0
}

case "$event" in
  SessionStart) handle_session_start ;;
  UserPromptSubmit) handle_prompt ;;
esac
exit 0
