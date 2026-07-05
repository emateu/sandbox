# herdr CLI reference

Condensed from https://herdr.dev/docs/cli-reference/ (re-fetch that URL if a flag seems missing or renamed).

## Launch & status

```
herdr                                  # launch or attach to default session
herdr --session <name>                 # named session (independent server)
herdr --remote <host>                  # SSH attach, local keybindings
herdr --remote <host> --remote-keybindings server
herdr --remote <host> --handoff        # experimental live handoff
herdr --no-session                     # single-process escape hatch (debug)
herdr --default-config                 # print default config.toml
herdr --version
herdr update [--handoff]               # install from configured channel
herdr channel show | set preview | set stable
herdr status [server|client]
```

## Server

```
herdr server                           # run headless server explicitly
herdr server stop
herdr server reload-config             # apply reloadable settings live
herdr server agent-manifests [--json]
herdr server update-agent-manifests [--json]
herdr server reload-agent-manifests    # after local manifest edits
```

## Sessions

```
herdr session list [--json]
herdr session attach <name>
herdr session stop <name> [--json]
herdr session delete <name> [--json]
```

## Workspaces

```
herdr workspace list
herdr workspace create [--cwd PATH] [--label TEXT] [--env K=V] [--focus|--no-focus]
herdr workspace get|focus|close <id>
herdr workspace rename <id> <label>
```

## Worktrees (git worktree as workspace)

```
herdr worktree list [--workspace ID|--cwd PATH] [--json]
herdr worktree create [--workspace ID|--cwd PATH] [--branch NAME] [--base REF]
                      [--path PATH] [--label TEXT] [--focus|--no-focus] [--json]
herdr worktree open   (--path PATH|--branch NAME) [--workspace ID|--cwd PATH]
                      [--label TEXT] [--focus|--no-focus] [--json]
herdr worktree remove --workspace ID [--force] [--json]
```

Checkouts land in `[worktrees].directory` as `<dir>/<repo>/<branch-slug>`.

## Tabs

```
herdr tab list [--workspace ID]
herdr tab create [--workspace ID] [--cwd PATH] [--label TEXT] [--env K=V] [--focus|--no-focus]
herdr tab get|focus|close <id>
herdr tab rename <id> <label>
```

## Panes

```
herdr pane list [--workspace ID]
herdr pane current | get <id> | layout | process-info | edges
herdr pane neighbor --direction left|right|up|down [--pane ID|--current]
herdr pane focus --direction <dir> [--pane ID|--current]
herdr pane resize --direction <dir> [--amount FLOAT] [--pane ID|--current]
herdr pane zoom [<id>] [--toggle|--on|--off]
herdr pane rename <id> <label>|--clear
herdr pane split [<id>] --direction right|down [--ratio FLOAT] [--cwd PATH]
                 [--env K=V] [--focus|--no-focus]        # returns JSON with new pane_id
herdr pane swap --direction <dir> | --source-pane ID --target-pane ID
herdr pane move <id> --tab <tab_id> --split right|down [--target-pane ID] [--ratio F]
herdr pane move <id> --new-tab [--workspace ID] [--label TEXT]
herdr pane move <id> --new-workspace [--label TEXT] [--tab-label TEXT]
herdr pane close <id>
```

### Read pane output

```
herdr pane read <id> [--source visible|recent|recent-unwrapped|detection] [--lines N] [--ansi]
```

Sources: `visible` = rendered screen (UI feedback) · `recent` = scrollback with wrapping ·
`recent-unwrapped` = scrollback without soft wraps (best for logs) · `detection` = bottom-buffer snapshot used by agent state detection.

### Send input

```
herdr pane send-text <id> <text>       # literal text, no Enter
herdr pane send-keys <id> <key> ...    # e.g. enter, esc, ctrl+c, shift+tab, f1, C-c
herdr pane run <id> <command>          # command + Enter
```

### Agent/metadata reporting (for integrations)

```
herdr pane report-agent <id> --source ID --agent LABEL --state idle|working|blocked|unknown
                        [--message TEXT] [--custom-status TEXT] [--seq N]
                        [--agent-session-id ID] [--agent-session-path PATH]
herdr pane report-metadata <id> --source ID [--title TEXT|--clear-title]
                        [--display-agent TEXT] [--custom-status TEXT (32ch)]
                        [--state-label STATUS=TEXT (80ch)] [--ttl-ms N]
```

## Agents

Targets: terminal IDs, unique agent names, detected labels, or pane IDs.

```
herdr agent list
herdr agent get <target>
herdr agent read <target> [--source ...] [--lines N] [--format text|ansi]
herdr agent send <target> <text>
herdr agent rename <target> <name>|--clear
herdr agent focus <target>
herdr agent wait <target> --status idle|working|blocked|unknown [--timeout MS]
herdr agent attach <target> [--takeover]     # detach: ctrl+b q
herdr agent start <name> [--cwd PATH] [--workspace ID] [--tab ID] [--split right|down]
                 [--env K=V] [--focus|--no-focus] -- <argv...>
herdr agent explain <target> [--json|--verbose]   # debug state detection
```

## Waits (blocking, for scripting)

```
herdr wait output <pane> --match <text> [--regex] [--source ...] [--lines N] [--timeout MS]
herdr wait agent-status <pane> --status idle|working|blocked|done|unknown [--timeout MS]
```

## Integrations

```
herdr integration install <name>    # pi omp claude codex copilot devin droid kimi
                                    # opencode kilo hermes qodercli cursor
herdr integration uninstall <name>
herdr integration status [--outdated-only]
```

## Direct terminal attach

```
herdr terminal attach <terminal_id> [--takeover]
herdr terminal title set <title> | clear
```

## Notifications

```
herdr notification show <title> [--body TEXT] [--position top-left|top-right|bottom-left|bottom-right]
                        [--sound none|done|request]
```

## Plugins

```
herdr plugin install <owner>/<repo>[/subdir] [--ref REF] [--yes]
herdr plugin list|uninstall|enable|disable
herdr plugin link <path> [--disabled] | unlink <id>
herdr plugin action list|invoke <action_id>
herdr plugin pane open --plugin ID --entrypoint ID [--placement overlay|split|tab|zoomed]
```

## Environment variables

| Var | Meaning |
|---|---|
| `HERDR_ENV=1` | current process runs inside a herdr pane |
| `HERDR_PANE_ID` / `HERDR_TAB_ID` / `HERDR_WORKSPACE_ID` | IDs of the enclosing pane/tab/workspace |
| `HERDR_SOCKET_PATH` | server socket |
| `HERDR_CONFIG_PATH` | override config file path |
| `HERDR_SESSION` | select named session for CLI commands |
| `HERDR_AGENT` | force agent detection inside VMs/sandbox wrappers |
| `HERDR_REMOTE_BINARY` | custom binary path for remote deploy |
| `HERDR_LOG` | log filter, e.g. `HERDR_LOG=herdr=debug` |
| `HERDR_DISABLE_SOUND` | suppress audio |
