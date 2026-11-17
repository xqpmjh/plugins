# plugins

Claude Code plugins by [xqpmjh](https://github.com/xqpmjh), one directory per plugin under `plugins/`. Skills that are not plugins live in the sibling `xqpmjh/skills` repository.

| Plugin | What it does | Status |
| :--- | :--- | :--- |
| [`prompt-history-bar`](plugins/prompt-history-bar/) | Right-side column of recent prompts in the Claude Code status line | Has its own installer and skill-hub package |
| [`aof`](plugins/agent-output-formatter/) | Per-session toggle for an evidence-bound output contract, with an HTML sub-mode | Kept, not installed (see its `CLAUDE.md`) |

## Layout

```
.claude-plugin/marketplace.json   marketplace listing every plugin below
plugins/<dir>/                    one plugin: .claude-plugin/plugin.json, its own README.md and CLAUDE.md, tests (directory name may differ from the plugin name)
```

Each plugin directory is self-contained. Read its `README.md` for install and use, and its `CLAUDE.md` for development rules and test commands. Run its tests from inside that directory.

## Marketplace

```text
/plugin marketplace add xqpmjh/plugins
/plugin install prompt-history-bar@xqpmjh-plugins
```

The repository root is the marketplace (`.claude-plugin/marketplace.json`). Not yet verified end to end with a real `marketplace add`; only `claude plugin validate` has been run.

## Local-only material

`local/` is git-ignored and absent from clones: `aof` research records, third-party background material, and a stray screenshot. See the root `CLAUDE.md`.

## Not in this repository

- Plugins that belong to an employer or another organisation stay in their own repositories.
- Plain skills (no hooks, no plugin manifest) go to `xqpmjh/skills`.
