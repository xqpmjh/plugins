# aof (agent-output-formatter)

One Claude Code plugin, **aof**. aof adds a session toggle for an evidence-bound output contract, an auto-start switch and an optional HTML sub-mode.

Background material lives in `local/aof/Karpathy-ASD-STE100/` at the repository root (git-ignored, not part of the plugin). aof borrows ideas from the 《中文技术表达规范》 (C01–C24) and carlstack's "中文技術寫作借用 STE". It does **not** implement or claim ASD-STE100 compliance, and it has no sentence-length lint or word lists.

The contract is an untested rule draft until the comparison evaluation below has been run.

## Install

aof is a skills-directory plugin: any folder under `~/.claude/skills/` with a `.claude-plugin/plugin.json` loads as a plugin in every session, with no install step. Link it in:

```
ln -s ~/Codes/xqpmjh/plugins/plugins/aof ~/.claude/skills/aof
```

Start a new session (or run `/reload-plugins`) so the hooks load. `claude plugin list` should show `aof@skills-dir` as loaded. Edits to this directory take effect at the next session start or `/reload-plugins`.

aof touches nothing outside its own folder except its state directory `~/.claude/aof/`, which the hook creates on first `/aof` use.

## Use

| Command | Effect |
| :--- | :--- |
| `/aof` or `/aof on` | Turn aof on for this session and inject the contract |
| `/aof off` | Turn aof off; the hook tells the model the earlier contract no longer applies |
| `/aof status` | Report session state, source, html, auto |
| `/aof auto on` / `/aof auto off` | Auto-start aof in sessions started or cleared from now on (the current session is unchanged) |
| `/aof html on` / `/aof html off` | HTML sub-mode (turns aof on if it was off) |

Arguments are case-insensitive and may be separated by full-width spaces. Only a single-line message consisting solely of the command counts. `/aof` inside a sentence, or as the first line of a multi-line message, is ignored.

## How it works

`bin/aof-hook.sh` is the only component that changes state. It runs for two events:

- **UserPromptSubmit.** It parses the raw `/aof …` text before the skill expands and writes the state. It then injects the result: a one-line state summary, plus the contract when aof turns on. On ordinary prompts it injects a short reminder while aof is on.
- **SessionStart.** On startup, clear or fork it applies auto-start. On compact it re-injects the contract. On resume it applies auto-start only when the session has no state file yet and auto is on; otherwise it injects nothing, because the contract is already in the transcript.

The skill body only asks the model to report the hook's `[aof]` block. If that block is missing, the model must say the toggle failed rather than claim a state.

State lives in `~/.claude/aof/`:
- `config` holds `auto=on|off`.
- `sessions/<session_id>` holds `state`, `source` and `html`. Every prompt refreshes the file's mtime. At session start, files idle for more than 14 days are deleted; the starting session's own file is never deleted.

Hooks run outside the Bash sandbox, and `~/.claude/aof/` is not in the sandbox write allowlist, so the model cannot flip the switch from sandboxed Bash. The Edit/Write tools are governed by permissions, not the sandbox. To block those too, add `Edit(~/.claude/aof/**)` and `Write(~/.claude/aof/**)` deny rules. Forging state only toggles formatting rules.

Environment variables:
- `AOF_DISABLE=1` turns the hook off entirely. Use it for `claude -p` evaluations and automation.
- `AOF_DEBUG=1` logs decisions to `~/.claude/aof/debug.log`.
- `AOF_HOME` overrides the state directory.

The HTML sub-mode writes self-contained pages from `templates/page.html` to `/tmp/claude/aof/pages/` and prints the path. The sandbox blocks `open`, so open the page yourself.

## Known gaps

- `/clear`, `/branch` and `--fork-session` start a new session_id. Manual aof state does not carry over; auto-start does.
- Subagents do not receive the contract. The main loop applies it when relaying their output.
- On `--resume`, earlier reminders are replayed from the transcript as-is.
- Not yet verified in a real session:
  - that a symlinked folder under `~/.claude/skills/` loads as a plugin (the docs confirm symlinked skill folders, not symlinked plugin folders; if it doesn't load, move the folder there instead);
  - that the hook's `prompt` field holds the raw `/aof …` text;
  - that the model does not treat the injected text as prompt injection;
  - that `/aof` works in plan mode.

## Test

```
bash tests/run.sh
```

The suite covers command matching, the SessionStart transitions, malformed session IDs, missing `jq`, `AOF_DISABLE`, size limits, 14-day cleanup (including that active and resuming sessions keep their state), sed-special characters in the plugin path, missing rule files, long prompts, non-zero exit codes and empty or garbage stdin. It uses a temporary `AOF_HOME`.

## Uninstall

```
trash ~/.claude/skills/aof
```

This removes the hook and the skill. Nothing reads or writes `~/.claude/aof/` afterwards, and it keeps your auto setting if you link aof back in. To remove every trace, also run `trash ~/.claude/aof`.
