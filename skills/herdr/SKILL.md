---
name: herdr
description: Working knowledge of herdr (herdr.dev), the terminal workspace manager and coding-agent orchestrator (client-server, tmux-like persistence, agent state tracking). Use this skill whenever the user mentions herdr, asks about terminal workspaces/panes/tabs, attaching/detaching/resuming terminal sessions, orchestrating multiple coding agents, remote-attaching to another machine's terminal, or herdr config. ALSO use it proactively whenever HERDR_ENV=1 appears in the environment — that means you are running inside a herdr pane and can orchestrate panes/agents via the herdr CLI (e.g. spawn a real-TTY pane for interactive prompts like `op signin`).
---

# herdr

herdr is a terminal workspace manager built to run and supervise multiple coding agents (Claude Code, Codex, Cursor, etc.). Think tmux + an agent-state sidebar + a CLI/socket API that makes everything scriptable.

## Mental model

Hierarchy: **workspace → tab → pane → agent**.

- **Workspace**: top-level project container. Convention: one per repo/task/investigation.
- **Tab**: layout container inside a workspace.
- **Pane**: a real terminal (process preserved across client detach). Splits: `right` or `down`.
- **Agent**: a recognized process in a pane. States: `working`, `blocked` (needs input/approval), `done` (finished, unreviewed), `idle`, `unknown`.

**Client-server**: the server owns panes/processes; the client is just UI. Detach with `ctrl+b q` (everything keeps running), reattach by running `herdr`. Prefix key: `ctrl+b`.

## Detecting you're inside herdr

If `HERDR_ENV=1` is set, you are inside a herdr pane. Also available: `HERDR_PANE_ID`, `HERDR_TAB_ID`, `HERDR_WORKSPACE_ID`, `HERDR_SOCKET_PATH`. This means the `herdr` CLI can control the session you're in.

### Proven pattern: real TTY for interactive prompts

Sandboxed/hookless shells often lack a TTY (e.g. `op signin` fails with "inappropriate ioctl for device"). Fix: spawn a pane next to the user and run the command there — the user types the password in that pane while you wait for the result:

```bash
herdr pane split --pane $HERDR_PANE_ID --direction down --ratio 0.3 --focus
# → returns JSON with the new pane_id, e.g. w3:p3
herdr pane run w3:p3 'eval "$(op signin)" && do-the-thing && echo SENTINEL_OK'
herdr wait output w3:p3 --match "SENTINEL_OK|Error" --regex --timeout 180000 --source recent
herdr pane read w3:p3 --source recent-unwrapped --lines 15   # confirm result
herdr pane close w3:p3                                        # clean up
```

## Essential commands

```bash
# Panes
herdr pane list / get <id> / split / close / focus / zoom / move
herdr pane run <id> '<command>'          # types command + Enter
herdr pane send-text <id> '<text>'       # literal text, no Enter
herdr pane send-keys <id> enter ctrl+c   # key sequences
herdr pane read <id> --source visible|recent|recent-unwrapped [--lines N]

# Agents
herdr agent start <name> --cwd <dir> [--split right|--workspace ID] -- claude
herdr agent list / read <target> / send <target> '<text>' / attach <target>
herdr agent wait <target> --status idle|blocked --timeout <ms>
herdr agent explain <target>             # debug why state detection is wrong

# Blocking waits (great for scripting)
herdr wait output <pane> --match '<pattern>' [--regex] [--timeout MS]
herdr wait agent-status <pane> --status done [--timeout MS]

# Workspaces / worktrees (parallel agents on one repo without collisions)
herdr workspace create --cwd <dir> --label '<name>'
herdr worktree create --cwd <repo> --branch <branch> --label '<name>'

# Server / sessions
herdr server stop | reload-config
herdr session list | attach <name>       # named sessions = independent servers
herdr status
```

Most commands return JSON — parse `pane_id` etc. from it. Full reference: [references/cli.md](references/cli.md).

## State & persistence rules (what survives what)

| Event | Processes | Layout/cwd | Agent conversations |
|---|---|---|---|
| Detach/reattach | survive | survives | survive (nothing stopped) |
| Server stop / reboot | **die** | restored from `session.json` | auto-resume ONLY with integration installed |
| `herdr update --handoff` | best-effort survive | survives | survive (experimental) |

- Clean shutdown before a reboot: `herdr server stop` (guarantees a fresh snapshot; usually fine without it).
- Screen contents are NOT restored by default; `[experimental] pane_history = true` enables it but writes pane output (possibly secrets) to disk — recommend leaving off.
- Claude Code sessions are always manually recoverable with `claude --resume` in the pane's cwd, even without herdr's help.

## Integrations (critical for reliable agent state)

Without an integration, herdr guesses agent state by reading the screen. With it, the agent reports state via hooks → reliable sidebar state + native session auto-resume after server restarts.

In this sandbox the Claude Code integration is already installed in the image — do not reinstall it. For other agents:

```bash
herdr integration install <name>
herdr integration status
```

Gotchas learned the hard way:
- The install writes a herdr-managed hook into the agent's `~/.claude/hooks/` and registers it in `settings.json` with a machine-absolute path; treat both as installed software, not config to edit.
- Installing mid-session does not help the *current* agent session (its `SessionStart` hook already fired) — only future sessions auto-resume.

## Remote attach

```bash
herdr --remote <ssh-host>        # host from ~/.ssh/config works, e.g. `herdr --remote fedora`
herdr --remote ssh://user@host:2222
```

Local herdr becomes a thin client of the remote server: remote workspaces/agents, local keybindings and clipboard. Plain SSH transport — needs sshd on the target, key in `authorized_keys`, and herdr installed on both ends (it offers to install remotely if missing). Both machines can be attached simultaneously.

### Phone access (no config needed)

herdr's TUI is responsive — "mobile-first when the terminal gets small": on narrow screens it swaps to a touch-sized workspace switcher automatically. There is no app or web UI; from a phone you use an SSH client (Termius/Blink/Termux), `ssh` into the machine and run `herdr` to attach to the running server. Per-device SSH key in `authorized_keys`; off-LAN reach via Tailscale or similar rather than router port-forwarding.

The mobile layout triggers on terminal width: `[ui] mobile_width_threshold` (default **64** columns). Phone SSH clients with small fonts often report >64 cols and keep the desktop sidebar — raise the threshold (e.g. 100) or enlarge the phone font (`tput cols` to check). Manual sidebar toggle: `ctrl+b b` (`toggle_sidebar`).

## Config

`~/.config/herdr/config.toml` (TOML). Apply changes with `herdr server reload-config`. High-value settings: `[ui] agent_panel_sort = "priority"` (attention-sorted sidebar), `[ui.toast] delivery = "system"` (OS notifications when agents block/finish), `[ui.sound]`, `[session] resume_agents_on_restore` (default true). Details: [references/config-and-state.md](references/config-and-state.md).

In this sandbox the default config is seeded from the image into `~/.config/herdr/config.toml`; edit it there and apply with `herdr server reload-config`.

## Rechecking facts (source of truth)

herdr evolves fast; when unsure or when behavior contradicts this skill, re-fetch the official docs instead of guessing:

- https://herdr.dev/docs/concepts/ — hierarchy, modes, client-server
- https://herdr.dev/docs/agents/ — detection, states, integrations, manifests
- https://herdr.dev/docs/session-state/ — the survives-what matrix, handoff
- https://herdr.dev/docs/persistence-remote/ — detach, named sessions, --remote
- https://herdr.dev/docs/configuration/ — all config.toml options
- https://herdr.dev/docs/cli-reference/ — every command and flag
