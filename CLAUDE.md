# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A monorepo of independent Claude Code plugins. Each plugin under `plugins/<name>/` has its own `CLAUDE.md` with architecture, invariants and test commands; read it before editing that plugin. Rules here apply to the repository as a whole.

## Layout and conventions

- One plugin per `plugins/<name>/` directory, with its own `.claude-plugin/plugin.json`, `README.md`, `CLAUDE.md` and tests. Do not share code between plugins; a plugin must work when its directory is copied out alone.
- `.claude-plugin/marketplace.json` at the repository root lists every plugin with `"source": "./plugins/<name>"`. When adding, removing or re-versioning a plugin, update its entry there, its own `plugin.json`, and the index table in the root `README.md`. A version number lives in `plugin.json` and in the marketplace entry; bump both.
- Plugins have no marketplace of their own; only the root `.claude-plugin/marketplace.json` is served. Skill-hub packaging for `prompt-history-bar` (`package-skill.sh`, `SUBMISSION.md`) stays with the plugin.
- Validate with `claude plugin validate plugins/<name>` and `claude plugin validate .` (non-strict; a plugin-level `CLAUDE.md` is developer context and triggers a strict-mode warning).
- `local/` is git-ignored and holds reference material and stray files that are deliberately not tracked (`local/aof/docs/` research records that quote private instructions and local paths; `local/aof/Karpathy-ASD-STE100/`, about 90 MB of third-party downloads; a loose screenshot from prompt-history-bar). It does not exist in a fresh clone. Tracked code must not depend on it; documentation may mention it.
- There are no sub-repositories or subtrees. The former standalone repositories (`prompt-history-bar`, `agent-output-formatter`) were merged in by plain copy.

## Git

- Commit identity is the GitHub noreply one (`xqpmjh`), never a company identity.
- Do not push, create remote repositories, or archive other repositories without the user's explicit instruction.
