---
name: prompt-history-bar
description: Install, configure, or troubleshoot a Claude Code status line that shows recent prompts for the current project in a right-side column. Use when the user asks about prompt history in the status bar, a history sidebar, recent inputs shown in the status line, or wants to install, customize, or share this statusline setup.
---

# Prompt History Bar

Adds a right-side column to the Claude Code status line: the most recent prompts
entered in the current project, newest at the bottom, each with an age. The left
side keeps the usual project, model, effort, and context information.

Data comes from `<config>/history.jsonl`, which Claude Code writes locally. The
script makes no network requests and registers no hooks.

## Install

The plugin is installed under Claude Code's plugin directory, or as a personal
skill under `~/.claude/skills/prompt-history-bar/`. In both cases, run the
installer from the skill directory:

```bash
# Personal skill
python3 ~/.claude/skills/prompt-history-bar/scripts/install.py

# Plugin (the variable is expanded in skill content)
python3 ${CLAUDE_PLUGIN_ROOT}/skills/prompt-history-bar/scripts/install.py
```

`install.py` is the installer. `install.sh` and `uninstall.sh` are thin wrappers
that call it, kept for compatibility; some install channels drop shell scripts,
so prefer the `.py` paths when both exist.

The installer copies the runtime to `<config>/statusline/prompt-history-bar/`
and adds or replaces the `statusLine` key in `<config>/settings.json`.

**Ask the user before running it.** This edits their global settings. Show them
the exact command first, preferably with `--dry-run`:

```bash
python3 .../install.py --dry-run --lang en
```

Then run it after they agree.

Options:

| Option | Effect |
|---|---|
| `--lang en\|zh` | Age labels in English (default) or Chinese |
| `--paste` | Show the agent's reply line (or the paste's first line) instead of `[paste]` |
| `--session` | Show only the current session's prompts instead of the whole directory |
| `--refresh N` | Also re-run the status line every N seconds (whole number, minimum 1), so the bar and its age labels update while Claude is busy or idle |
| `--force` | Replace a different existing `statusLine` command (backup kept) |
| `--dry-run` | Print the change; write nothing |
| `--uninstall` | Remove the `statusLine` entry |
| `--purge` | With `--uninstall`, also delete the runtime copy |

Without `--force`, the installer refuses to overwrite an existing `statusLine`
that points somewhere else. Every write is backed up as
`settings.json.bak.YYYYMMDD-HHMMSS` and validated before it replaces the file.

Re-running the installer with different flags builds a different `statusLine`
command, which the helper treats as a conflict and refuses without `--force`.
To refresh the runtime files only, repeat the flags from the original install
(for example `--lang zh --paste`). To change them deliberately, pass the new
flags together with `--force`; the settings file is backed up first.

After installing, start a new Claude Code session or reload settings. The status
line is skipped until the workspace trust prompt is accepted.

## Configuration

Set these in the environment that launches Claude Code (for example
`~/.zshrc`):

| Variable | Meaning |
|---|---|
| `CLAUDE_HISTORY_LANG` | `en` (default) or `zh` |
| `CLAUDE_HISTORY_PASTE` | `1` to show the agent's reply line, or the paste's first line |
| `CLAUDE_HISTORY_CHOICES` | `0` to hide choice-box answers (default: shown) |
| `CLAUDE_HISTORY_CANCELLED` | `0` to keep prompts cancelled with Esc before the agent answered (default: hidden) |
| `CLAUDE_HISTORY_SCOPE` | `session` to list only the running session's prompts (default: whole directory) |
| `CLAUDE_HISTORY_WIDTH` | Force a terminal width in cells |
| `CLAUDE_HISTORY_STYLE` | ANSI style for the history cells |
| `DEBUG` | `1` to log width decisions under the state directory |

The status line input JSON does not include terminal dimensions. Width comes
from tmux when `TMUX_PANE` is set, then from `COLUMNS` (which Claude Code sets
for status line commands), then `/dev/tty`, then the last successful value,
then 120. tmux gives the most reliable width; set `CLAUDE_HISTORY_WIDTH` when
running elsewhere.

## Troubleshooting

- **Nothing appears.** Accept the workspace trust prompt. Check
  `disableAllHooks: true` in settings (it disables the status line too), and
  check that managed settings are not overriding `statusLine`.
- **Only the left column appears.** The current project has no entries in
  `history.jsonl`, or the file is missing. Visiting a project creates entries.
- **The right column is misaligned.** Width detection failed. Set
  `CLAUDE_HISTORY_WIDTH`, or run Claude Code inside tmux.
- **Prompts from a parent directory appear.** That is intentional inside a git
  repository: if the exact directory has no entries, parents are tried up to the
  git root (four levels at most). Without a `.git` above it, only the exact
  directory is matched.
- **Pasted text shows `[paste]`.** Enable the preview with
  `CLAUDE_HISTORY_PASTE=1`. An input that is only a paste is listed only when
  the preview has a line to show; with the preview off, or when no line has
  readable text, it is skipped. The preview is the agent's first reply line from
  the session transcript; before the reply, or without a transcript, it is the
  command after the paste's shell prompt. `[paste]` appears only next to typed text.
- **Uninstall.** Run
  `python3 ~/.claude/statusline/prompt-history-bar/install.py --uninstall [--purge]`,
  or `install.py --uninstall --purge` from the skill directory. The
  `uninstall.sh` wrapper in either directory does the same thing.

## Privacy

The script reads only local files:

- `<config>/history.jsonl` — the prompt history it displays.
- `<config>/projects/*/<session>.jsonl` (the session transcript) — choice-box
  answers and Esc-cancelled prompts on every render unless both
  `CLAUDE_HISTORY_CHOICES=0` and `CLAUDE_HISTORY_CANCELLED=0`, and the agent's reply
  line when `CLAUDE_HISTORY_PASTE=1`.
- `<config>/paste-cache/<hash>.txt` — only when `CLAUDE_HISTORY_PASTE=1`.
- Git branch via `git -C <project> rev-parse` for the left column.

Nothing is uploaded. The history column displays prompt text on screen, so be
careful when screen-sharing or recording.

## How it works

`statusline.py` reads Claude Code's JSON from stdin, builds up to four left rows,
and calls `history_bar.render_statusline`. The history reader scans
`history.jsonl` backwards in 64 KiB blocks and stops as soon as it has enough
entries for the current project, so its cost does not grow with the file size.
It accepts both the logical project path and its realpath, tries parents up to
the git root (four levels at most; none when there is no `.git`), and ignores bash-mode inputs (`!...`), UI commands (`/effort`,
`/model`, ...), exit words, stray inputs of at most two characters with no
letters (`` ` ``, `1`), bare shell commands (`ls`, `git status`), pasted `git status` / `ls -l` output, and inputs that are only image
placeholders (an input that is only a paste is shown as its first line with the
preview on, and skipped otherwise; `[Image #N]` is dropped from entries that also have text, along
with the separators and invisible characters left at the front, such as the `，`
in `[Image #1] ，说明`).
An input that immediately repeats the previous one in the same project (for
example a resend after a dropped connection) shows once, at its newest time;
the same text with different pasted content stays separate.

A transcript stored inline, without a `[Pasted text ...]` placeholder, keeps
its command; a leading host, bracket, PowerShell, or glyph prompt is stripped
before display. A bare `$`/`%` line is left alone so ordinary text keeps its
subject.

With the paste preview on, a paste is shown as the first line of the agent's
reply to it, read from the session transcript (`<config>/projects/*/<session>.jsonl`)
and paired with the prompt by time; Markdown markers are removed. Until the agent
has written text, or when the transcript is missing, the preview is the first line
of the pasted content.

Answers picked in a choice box (`AskUserQuestion`) are not typed prompts and are
absent from `history.jsonl`. The bar reads them from the session transcript's
`toolUseResult.answers` and lists them in time order, marked `↳`, as
`question → answer` (the question is cut to 16 cells so the answer stays
visible, and a trailing "(Recommended)" tag is dropped); several questions in
one box are joined with ` / `. A rejected box has no answer and is not shown.
Set `CLAUDE_HISTORY_CHOICES=0` to turn this off.

A prompt cancelled with Esc before the agent wrote any text or called a tool
is not shown either: the transcript records an `[Request interrupted by user]`
turn right after it and no agent work in between. An interrupt after the agent
has started (a reply or a tool call), or a rejected tool call, keeps the
prompt, since the question was real. Set `CLAUDE_HISTORY_CANCELLED=0` to keep
cancelled prompts. Only the newest three sessions in the list are checked, and
the last 4 MiB of each transcript.

When the pasted content is the preview, and its first line
looks like a shell prompt (`[user@host dir]$ ...`, `user@host ~ % ...`,
`(base) user@host:~$ ...`, `PS C:\> ...`, or a Starship module line such as
`~/proj on  main ❯ ...`), the prompt says nothing about intent, so it is
stripped and the command after it is shown. A line that is only a prompt is
skipped in favour of the next non-empty line. Bare `#` and `>` are not prompt
signals, so script comments and quoted lines still preview.

With enough entries the history uses two columns, aligned to the terminal
edge; with fewer it is a single column that starts right after the left rows
and takes the remaining width. A long prompt wraps onto spare rows of its column (newest first)
and is cut with `…` only when the rows run out. If the pane is too narrow it
falls back to one column, then to the left column alone rather than
overflowing.
