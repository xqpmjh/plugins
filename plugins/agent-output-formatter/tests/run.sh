#!/bin/bash
# aof tests — feeds hook JSON to bin/aof-hook.sh in an isolated AOF_HOME.
# Run: bash tests/run.sh

set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${HERE}/bin/aof-hook.sh"
export AOF_HOME
TOP="$(mktemp -d "${TMPDIR:-/tmp}/aof-test.XXXXXX")"
AOF_HOME="${TOP}/home"; mkdir -p "$AOF_HOME"
# hook() runs inside $(...), so non-zero exits are recorded in a file outside
# AOF_HOME (reset_state wipes AOF_HOME) and counted at the end.
RCLOG="${TOP}/rc.log"; : >"$RCLOG"
unset AOF_DISABLE AOF_DEBUG AOF_JQ
export CLAUDE_PLUGIN_ROOT="$HERE"

pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$*"; }

reset_state() { find "$AOF_HOME" -mindepth 1 -delete 2>/dev/null; }

# hook EVENT SID [PROMPT|SOURCE] -> prints additionalContext ("" if none); sets rc
hook() {
  local ev="$1" sid="$2" extra="${3-}" json
  if [ "$ev" = UserPromptSubmit ]; then
    json=$(jq -n --arg e "$ev" --arg s "$sid" --arg p "$extra" '{hook_event_name:$e, session_id:$s, prompt:$p} | if $s == "" then del(.session_id) else . end')
  else
    json=$(jq -n --arg e "$ev" --arg s "$sid" --arg src "$extra" '{hook_event_name:$e, session_id:$s, source:$src} | if $s == "" then del(.session_id) else . end')
  fi
  out=$(printf '%s' "$json" | "$HOOK"); rc=$?
  [ "$rc" = 0 ] || printf 'exit code %s for %s/%s\n' "$rc" "$ev" "$extra" >>"$RCLOG"
  if [ -n "$out" ]; then
    printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext'
  fi
}

state_of() { sed -n "s/^$2=//p" "${AOF_HOME}/sessions/$1" 2>/dev/null; }

expect_contains() { case "$2" in *"$3"*) ok ;; *) bad "$1: expected to contain '$3'"; esac; }
expect_absent() { case "$2" in *"$3"*) bad "$1: expected NOT to contain '$3'" ;; *) ok ;; esac; }
expect_empty() { [ -z "$2" ] && ok || bad "$1: expected no output, got: ${2:0:120}"; }
expect_eq() { [ "$2" = "$3" ] && ok || bad "$1: expected '$3', got '$2'"; }

S=sess-0001

# --- command matching ------------------------------------------------------
reset_state
o=$(hook UserPromptSubmit $S "/aof");            expect_contains "bare /aof" "$o" "输出契约"; expect_eq "bare /aof state" "$(state_of $S state)" on
o=$(hook UserPromptSubmit $S "/aof on");         expect_contains "on twice" "$o" "already on"; expect_absent "on twice no dup contract" "$o" "输出契约"
o=$(hook UserPromptSubmit $S "/aof off");        expect_contains "off" "$o" "no longer apply"; expect_eq "off state" "$(state_of $S state)" off
o=$(hook UserPromptSubmit $S "/AOF ON");         expect_eq "uppercase" "$(state_of $S state)" on
o=$(hook UserPromptSubmit $S "/aof　off");       expect_eq "full-width space" "$(state_of $S state)" off
o=$(hook UserPromptSubmit $S "/aof:aof on");     expect_eq "namespaced" "$(state_of $S state)" on
o=$(hook UserPromptSubmit $S "  /aof off  ");    expect_eq "surrounding blanks" "$(state_of $S state)" off
o=$(hook UserPromptSubmit $S "请看 /aof on");    expect_empty "mid-sentence /aof" "$o"; expect_eq "mid-sentence state" "$(state_of $S state)" off
o=$(hook UserPromptSubmit $S $'/aof on\n其他内容'); expect_empty "multi-line" "$o"; expect_eq "multi-line state" "$(state_of $S state)" off
o=$(hook UserPromptSubmit $S "/aofx");           expect_empty "/aofx" "$o"
o=$(hook UserPromptSubmit $S "/aof bogus");      expect_contains "bogus" "$o" "Unrecognised"; expect_eq "bogus state" "$(state_of $S state)" off
o=$(hook UserPromptSubmit $S "/aof status");     expect_contains "status" "$o" "Session state: off"

# --- reminder only while on --------------------------------------------------
o=$(hook UserPromptSubmit $S "hello");           expect_empty "plain prompt while off" "$o"
hook UserPromptSubmit $S "/aof on" >/dev/null
o=$(hook UserPromptSubmit $S "hello");           expect_contains "plain prompt while on" "$o" "Session state: on"; expect_absent "reminder no contract" "$o" "输出契约"

# --- html sub-mode -----------------------------------------------------------
o=$(hook UserPromptSubmit $S "/aof html on");    expect_contains "html on" "$o" "HTML 子模式"; expect_contains "html template path" "$o" "templates/page.html"; expect_absent "html placeholder replaced" "$o" "{{TEMPLATE}}"
o=$(hook UserPromptSubmit $S "hello");           expect_contains "reminder html" "$o" "HTML sub-mode is on"
o=$(hook UserPromptSubmit $S "/aof html off");   expect_eq "html off" "$(state_of $S html)" off
reset_state
o=$(hook UserPromptSubmit $S "/aof html on");    expect_contains "html on from off brings contract" "$o" "输出契约"; expect_eq "html on from off state" "$(state_of $S state)" on

# --- auto switch and SessionStart ---------------------------------------------
reset_state
o=$(hook SessionStart $S startup);               expect_empty "startup auto off" "$o"
o=$(hook UserPromptSubmit $S "/aof auto on");    expect_eq "auto on config" "$(sed -n 's/^auto=//p' "$AOF_HOME/config")" on; [ "$(state_of $S state)" != on ] && ok || bad "auto on must not turn this session on"
o=$(hook SessionStart sess-new startup);         expect_contains "startup auto on" "$o" "输出契约"; expect_eq "startup auto source" "$(state_of sess-new source)" auto
o=$(hook SessionStart sess-new resume);          expect_empty "resume no reinject" "$o"
o=$(hook SessionStart sess-new compact);         expect_contains "compact reinject" "$o" "输出契约"
hook UserPromptSubmit sess-new "/aof off" >/dev/null
o=$(hook SessionStart sess-new compact);         expect_empty "compact while off" "$o"
o=$(hook SessionStart sess-new resume);          expect_empty "resume keeps manual off despite auto" "$o"
o=$(hook SessionStart sess-clr clear);           expect_contains "clear with auto on" "$o" "输出契约"
o=$(hook SessionStart sess-res resume);          expect_contains "resume unknown session with auto on" "$o" "输出契约"
hook UserPromptSubmit $S "/aof auto off" >/dev/null
o=$(hook SessionStart sess-x startup);           expect_empty "startup after auto off" "$o"

# --- input anomalies -----------------------------------------------------------
o=$(hook UserPromptSubmit "" "/aof on");         expect_contains "missing sid" "$o" "no valid session_id"
o=$(hook UserPromptSubmit "../x" "/aof on");     expect_contains "traversal sid" "$o" "no valid session_id"
[ -e "${AOF_HOME}/x" ] && bad "traversal wrote outside sessions/" || ok
o=$(hook UserPromptSubmit "../x" "hello");       expect_empty "traversal sid plain prompt" "$o"
o=$(hook SessionStart "a/b" startup);            expect_empty "slash sid session start" "$o"
o=$(printf 'not json' | "$HOOK"); rc=$?;         expect_eq "garbage stdin rc" "$rc" 0; expect_empty "garbage stdin" "$o"
o=$(printf '' | "$HOOK"); rc=$?;                 expect_eq "empty stdin rc" "$rc" 0; expect_empty "empty stdin" "$o"

# --- kill switch and missing jq ------------------------------------------------
reset_state
o=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"k1","prompt":"/aof on"}' | AOF_DISABLE=1 "$HOOK"); rc=$?
expect_eq "AOF_DISABLE rc" "$rc" 0; expect_empty "AOF_DISABLE output" "$o"; [ -e "${AOF_HOME}/sessions/k1" ] && bad "AOF_DISABLE wrote state" || ok
o=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"k2","prompt":"/aof on"}' | env PATH=/bin "$HOOK"); rc=$?
expect_eq "no jq rc" "$rc" 0; expect_empty "no jq output" "$o"

# --- rule sizes ----------------------------------------------------------------
n=$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "${HERE}/rules/contract.md")
[ "$n" -lt 9000 ] && ok || bad "contract.md is $n chars (limit 9000)"
hook UserPromptSubmit sz "/aof html on" >"${AOF_HOME}/full.txt"
n=$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "${AOF_HOME}/full.txt")
[ "$n" -lt 9500 ] && ok || bad "largest injection is $n chars (limit 9500, hook truncation at 10000)"

# --- 14-day cleanup --------------------------------------------------------------
reset_state
hook UserPromptSubmit old1 "/aof on" >/dev/null
touch -t 202001010000 "${AOF_HOME}/sessions/old1"
hook SessionStart fresh startup >/dev/null
[ -e "${AOF_HOME}/sessions/old1" ] && bad "stale session file not removed" || ok


# --- review regressions ------------------------------------------------------------
# 14-day cleanup must not delete the starting session's own file (resume must not
# flip a manual off to auto on), and prompts keep an active session's file fresh.
reset_state
hook UserPromptSubmit $S "/aof auto on" >/dev/null
hook UserPromptSubmit old2 "/aof off" >/dev/null
touch -t 202001010000 "${AOF_HOME}/sessions/old2"
o=$(hook SessionStart old2 resume);              expect_empty "stale own file resume no flip" "$o"; expect_eq "stale own file kept off" "$(state_of old2 state)" off
hook UserPromptSubmit act1 "/aof on" >/dev/null
touch -t 202001010000 "${AOF_HOME}/sessions/act1"
hook UserPromptSubmit act1 "hello" >/dev/null
hook SessionStart other startup >/dev/null
expect_eq "active session survives cleanup" "$(state_of act1 state)" on

# Template path with sed-special characters is substituted literally.
reset_state
weird="${AOF_HOME}/p|a&b"; mkdir -p "$weird"; cp -R "${HERE}/rules" "${HERE}/templates" "$weird/"
o=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"w1","prompt":"/aof html on"}' | CLAUDE_PLUGIN_ROOT="$weird" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
expect_contains "template path literal" "$o" "${weird}/templates/page.html"; expect_absent "template placeholder gone" "$o" "{{TEMPLATE}}"

# Missing rule files: no state change, explicit message, silent SessionStart.
reset_state
o=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"m1","prompt":"/aof on"}' | CLAUDE_PLUGIN_ROOT=/nonexistent "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
expect_contains "missing rules message" "$o" "rule files are missing"; [ -e "${AOF_HOME}/sessions/m1" ] && bad "missing rules wrote state" || ok

# HOME unset with no AOF_HOME: exit 0, no output.
o=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"h1","prompt":"/aof on"}' | env -u HOME -u AOF_HOME "$HOOK"); rc=$?
expect_eq "no HOME rc" "$rc" 0; expect_empty "no HOME output" "$o"

# Long prompts skip the parser quickly (the trim regex is quadratic).
long=$(python3 -c 'print("a" + " " * 80000 + "x", end="")')
t0=$(date +%s); o=$(hook UserPromptSubmit $S "$long"); t1=$(date +%s)
[ $((t1 - t0)) -lt 3 ] && ok || bad "long prompt took $((t1 - t0))s"

# Status after off with html still flagged says it is inactive.
reset_state
hook UserPromptSubmit $S "/aof html on" >/dev/null
o=$(hook UserPromptSubmit $S "/aof off");        expect_contains "off html inactive" "$o" "inactive while aof is off"

if [ -s "$RCLOG" ]; then
  while IFS= read -r line; do bad "$line"; done <"$RCLOG"
else
  ok
fi
find "$TOP" -mindepth 1 -delete 2>/dev/null; rmdir "$TOP" 2>/dev/null
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
