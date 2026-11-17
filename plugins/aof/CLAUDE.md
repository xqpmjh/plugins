# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

One Claude Code plugin, **aof** (this directory, `plugins/aof/` in the plugins repository): a per-session toggle that injects an evidence-bound output contract for Chinese/English technical writing, with an auto-start switch and an optional HTML sub-mode. It lives in the `xqpmjh/plugins` monorepo; the repository-level rules are in the root `CLAUDE.md`.

Current status (2026-10-09): the plugin is kept but **not installed**. The user chose a thin, non-enforced layer instead, the 「输出格式（软约束）」 subsection under 「中文表达」 in the global `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`. Those two subsections must stay in sync with each other. `rules/contract.md` is the strict layer, kept for later. Do not expand it or push installing aof unless the user asks. If they do, run the comparison eval first (below).

`Karpathy-ASD-STE100/` is downloaded background material (磊叔's 10-rule prompt, the 14-page 《中文技术表达规范》, the ASD-STE100 PDFs and a test report, about 90 MB). It sits in the git-ignored `local/aof/Karpathy-ASD-STE100/` at the repository root, outside the plugin directory so it is not packaged with the plugin. The dated research and evaluation records (formerly `docs/`) are kept locally in `local/aof/docs/`, not tracked, because they quote private instructions and local paths. aof installs as a skills-dir plugin, not from a marketplace.

## Commands

```
bash tests/run.sh                                      # full suite, prints "N passed, M failed"; exit 1 on any failure
shellcheck -S warning bin/aof-hook.sh tests/run.sh   # clean at warning level; info-level SC2015/SC2016 are expected
claude plugin validate .
```

There is no single-test runner. `tests/run.sh` is one linear script whose sections each start with `reset_state`; to iterate on one case, copy the harness header (lines 1–45) plus that section into a scratch script. The suite uses a temporary `AOF_HOME`, so it never touches `~/.claude/aof/`.

Install (user-run; the sandbox cannot write `~/.claude/skills`): `ln -s ~/Codes/xqpmjh/plugins/plugins/aof ~/.claude/skills/aof`, then `/reload-plugins`, then check that `claude plugin list` shows `aof@skills-dir`. Uninstall: `trash ~/.claude/skills/aof`.

## Architecture

`bin/aof-hook.sh` is the only component that holds logic or changes state. `hooks/hooks.json` wires it to two events:

- **UserPromptSubmit.** `parse_command` (jq) matches only a whole single-line `/aof …` or `/aof:aof …` prompt, before the skill expands. It writes state and emits `additionalContext`: a state summary, plus the contract on an off→on transition. On ordinary prompts it emits `rules/reminder.txt` while the session is on.
- **SessionStart.** `startup|clear|fork` apply auto-start. `resume` applies it only when the session has no state file yet and auto=on; otherwise it injects nothing, because the contract is already in the transcript. `compact` re-injects the contract. This event also deletes session files idle for more than 14 days, never the current session's own file.

`SKILL.md` (at the plugin root, so it is invoked as `/aof`) holds no rules. It only tells the model to report the hook's `[aof]` block, and to say the toggle failed if the block is absent. Rules are injected through the hook only, so that compaction cannot leave two copies.

State lives in `~/.claude/aof/`, which can be overridden with `AOF_HOME`: `config` holds `auto=on|off`; `sessions/<session_id>` holds `state`, `source` and `html`. Writes are atomic (temp file + `mv`). session_id must match `^[A-Za-z0-9_-]{1,128}$`. The plugin must not touch anything outside its own folder and this state dir; the user explicitly wants "delete one symlink = fully restored", so ask before adding any external touchpoint (status line, settings, global files).

Env flags: `AOF_DISABLE=1` (silent no-op, for `claude -p` evals), `AOF_DEBUG=1` (writes `$AOF_HOME/debug.log`), `AOF_HOME`, `AOF_JQ`.

## Invariants to preserve when editing the hook

- Every path exits 0, and a missing `jq`, a missing `HOME`, missing rule files or garbage stdin produce no output. aof must never block a prompt or a session.
- The script runs under macOS `/bin/bash` 3.2: no associative arrays, no `${var,,}`, no `mapfile`. Bash pattern substitution keeps quotes literally there, so `{{TEMPLATE}}` is substituted with awk `index()` instead of sed or `${//}`. This keeps `|`, `&` and `\` in paths literal.
- `additionalContext` over 10,000 chars is spilled to a file and only a 2,000-char preview reaches the model. Tests assert `contract.md` is under 9,000 chars and the largest injection is under 9,500; keep the core rules within the first 2,000 chars.
- `parse_command` skips prompts over 512 chars, because the trim regex is quadratic. A test asserts that an 80 KB prompt finishes in under 3 s.
- Injected text is phrased as user-enabled configuration ("[aof] The user enabled…"), not as orders, so the model does not read it as prompt injection.

## Rule files

- `rules/contract.md`: the strict layer. It states that the baseline is the global CLAUDE.md 「中文表达」 and contains only rules stricter than that baseline; do not duplicate baseline rules into it.
- `rules/html.md`: HTML sub-mode. Pages go to `/tmp/claude/aof/pages/` via a quoted heredoc. They must not use `open`, which the sandbox blocks, and must not contain `<script>` or event attributes.
- Deliberately excluded: sentence-length lint, word lists, and any claim of ASD-STE100 compliance (the source spec calls fixed thresholds "假精确").

## Evaluation gate for the strict layer

The contract is an untested draft. Earlier evidence: the ASD test showed 1 clear win out of 8, with output 28% longer. Before expanding the contract, compare the current global CLAUDE.md with and without the contract added through `--append-system-prompt-file`, using `claude -p` serially 1–2 s apart with `AOF_DISABLE=1`. Use the 8 exercises from spec §26 plus the 8 ASD report tasks, scored blind. Headless `claude -p` cannot reach the API from inside the sandbox, so the user must run it from an unsandboxed shell. If the contract arm does not beat the baseline, cut the contract.
