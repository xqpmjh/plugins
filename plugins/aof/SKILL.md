---
name: aof
description: Toggle the aof output contract for this session, its auto-start switch, and the HTML sub-mode. The toggle itself is performed by the aof UserPromptSubmit hook.
argument-hint: "[on|off|status|auto on|auto off|html on|html off]"
disable-model-invocation: true
---

The aof plugin's UserPromptSubmit hook processes this command before this text reaches you and reports the result as additional context in this same turn, in a block that starts with `[aof]`.

Report that result to the user in one or two sentences, stating exactly what the block says (session state, source, html, auto, and anything it says did not apply). If this turn contains no `[aof]` block, tell the user the toggle failed because the aof hook did not run, so the aof state is unknown; do not claim aof is on or off. Do nothing else in this turn.
