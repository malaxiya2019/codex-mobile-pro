# Taskmaster

Taskmaster is a completion guard for coding agents.

It addresses a common failure mode: the agent makes partial progress, writes a
summary, and stops before the user goal is actually finished.

## Philosophy

Taskmaster is built around one idea: progress is not completion.

- Evidence over narrative:
  The agent should not be allowed to stop based on a convincing summary alone.
  Completion must be explicit and machine-checkable.
- Same-session recovery:
  When a turn is incomplete, the right move is to continue in the same running
  session, not restart from scratch.
- Goal re-anchoring:
  Compliance prompts force the model back to the user’s actual request, not its
  own local notion of “good enough”.
- Automation-safe signaling:
  A deterministic done token makes completion parseable for wrappers and
  CI-style flows.

## Core Contract

A run is complete only when the assistant emits:

```text
TASKMASTER_DONE::<session_id>
```

If that token is missing at stop time, Taskmaster blocks stop and pushes the
current turn to continue. Codex monitoring stays active for later turns in the
same long-lived session.

### Enforcement Prompt

Taskmaster uses one shared compliance prompt for both Codex and Claude.

- Codex: the wrapper/injector path injects this shared prompt back into the
  same running session when stop conditions are not met.
- Claude: the Stop hook returns this same shared prompt as the block reason.

The shared prompt source lives in `taskmaster-compliance-prompt.sh`.

## How It Works

- Codex path:
  - Runs through a wrapper (`codex` shim / `codex-taskmaster` launcher).
  - Enables Codex session logs.
  - Watches `task_complete` / `turn_complete` events.
  - If done token is missing, injects a continuation prompt into the same
    running Codex process via expect PTY.
  - A done token suppresses injection for that completed turn only; it does
    not permanently disable Taskmaster for future turns in the same session.
- Claude path:
  - Registers a `Stop` command hook.
  - Hook runs `check-completion.sh`.
  - If done token is missing, the stop is blocked with corrective feedback.

## Install

```bash
bash ~/.codex/skills/taskmaster/install.sh
```

Auto-detection behavior:
- Installs Codex integration when `codex` or `~/.codex` exists.
- Installs Claude integration when `claude` or `~/.claude` exists.
- If both are present, installs both.
- If neither is detected, defaults to both.

Optional target override:

```bash
TASKMASTER_INSTALL_TARGET=codex bash ~/.codex/skills/taskmaster/install.sh
TASKMASTER_INSTALL_TARGET=claude bash ~/.codex/skills/taskmaster/install.sh
TASKMASTER_INSTALL_TARGET=both bash ~/.codex/skills/taskmaster/install.sh
```

Installed artifacts:
- Codex:
  - `~/.codex/skills/taskmaster/`
  - `~/.codex/bin/codex-taskmaster`
  - `~/.codex/bin/codex` (shim to Taskmaster wrapper)
- Claude:
  - `~/.claude/skills/taskmaster/`
  - `~/.claude/hooks/taskmaster-check-completion.sh`
  - Stop-hook entry added to `~/.claude/settings.json`

## Usage

### Codex

Run normally:

```bash
codex [args]
```

Explicit alias is also available:

```bash
codex-taskmaster [args]
```

Interactive resume is also supported:

```bash
codex resume [session-or-thread]
```

### Claude

Run Claude normally after install. Taskmaster hook enforcement is automatic.

## Configuration

- `TASKMASTER_MAX` (default `0`):
  - Limits stop-block warnings in hook checks.
  - `0` means unlimited warnings.

## Uninstall

```bash
bash ~/.codex/skills/taskmaster/uninstall.sh
```

Auto-detection behavior mirrors install and removes Taskmaster from detected
Codex/Claude environments.

Optional target override:

```bash
TASKMASTER_UNINSTALL_TARGET=codex bash ~/.codex/skills/taskmaster/uninstall.sh
TASKMASTER_UNINSTALL_TARGET=claude bash ~/.codex/skills/taskmaster/uninstall.sh
TASKMASTER_UNINSTALL_TARGET=both bash ~/.codex/skills/taskmaster/uninstall.sh
```

## Requirements

- `bash`
- `jq`
- Codex integration:
  - Codex CLI
  - `expect`
- Claude integration:
  - Claude Code with `Stop` hooks enabled
  - `python3` (for install/uninstall settings updates)

## License

MIT
