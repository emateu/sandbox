# oauth-token

Generates and keeps `CLAUDE_CODE_OAUTH_TOKEN` (in the repo `.env`) — the token the
sandbox container needs to run Claude Code unattended. It replicates
`claude setup-token` (OAuth 2.0 + PKCE against Claude's public client).

## Quick start — from a fresh clone

```bash
cp .env.example .env
$EDITOR .env                  # fill HOST_UID, HOST_GID, and USERNAME first
./tools/oauth-token/get-token.sh
```

It prompts for your email (hidden — kept out of shell history, argv, `ps`, and logs),
launches a real Chrome, drives the claude.ai login, and asks you for the code
claude.com emails you. Paste it and `CLAUDE_CODE_OAUTH_TOKEN` lands in `.env`. The
browser is scripted over CDP; your only inputs are those two prompts.

The helper requires an existing, completed `.env`; it fills the token key but does not
create the file. If login reports a missing `.env`, create it from `.env.example`, fill
the required user settings, then run `node tools/oauth-token/refresh.mjs` to write the
already-saved token.

Supply the email non-interactively with `OAUTH_EMAIL=you@example.com
./tools/oauth-token/get-token.sh` (a positional `get-token.sh you@example.com` works
too, but is visible in history / `ps`).

Prereqs: `node`, `npm`, and Chrome/Chromium on the host. macOS `Google Chrome.app` is
auto-detected; on Linux, the flatpak `com.google.Chrome` or a `google-chrome` /
`chromium` binary, plus a display (headless Linux works if `xvfb` is installed — a
virtual display is used automatically). macOS always has a display.

## Keeping it fresh — `refresh`

The `access_token` lasts 8h but comes with a `refresh_token` valid ~28 days. A refresh
rotates the `refresh_token` and resets its 28-day window, so periodic refreshing keeps
the token valid with no browser and no interaction:

```bash
node tools/oauth-token/refresh.mjs
```

Run it before `docker compose up`, or on a timer more frequent than every 28 days. It
has no dependencies (pure HTTP). The browser login is only needed for the first token,
or to recover after a >28-day gap or a revoke.

| command | when | browser? | you? |
|---|---|---|---|
| `get-token.sh` | first time / after >28d / revoke | yes (real, headed) | paste the email code |
| `refresh.mjs`  | routinely | no | no |

## Inside the sandbox container

The Fedora 44 container is headless with no browser, so the **login never runs
there** — you bootstrap it once on a machine with a display (host / laptop / Mac). What
runs in the container is the **refresh**: the `claude()` wrapper calls
`refresh.mjs --print` before each launch and exports a valid `CLAUDE_CODE_OAUTH_TOKEN`
from the mounted `refresh_token`. It refreshes only near expiry, and a lockfile makes
it safe when several agents launch at once.

Already wired: `docker-compose.yml` mounts this dir at `~/.oauth-token` and sets
`OAUTH_TOKEN_STORE`; the `Dockerfile` `claude()` wrapper reads it. If the store is
absent, the wrapper falls back to `CLAUDE_CODE_OAUTH_TOKEN` from `.env`. Rebuild with
`docker compose up -d --build` after adding the tool.

## What you provide (account owner)

- **`get-token.sh`:** your email (prompted hidden, or `OAUTH_EMAIL`) + the one-time
  code from your inbox.
- **`refresh.mjs`:** nothing — runs on the stored `refresh_token`.

## The secret

The `refresh_token` (the long-lived credential) lives in `.tokens.json`, **gitignored**,
`chmod 600`. To keep it in 1Password instead, point `OAUTH_TOKEN_STORE` at a file your
`op` wrapper materializes, or adapt `loadStore`/`saveStore` in `lib.mjs`.

## Files

| file | role |
|---|---|
| `get-token.sh` | one-command bootstrap: Chrome + login + update an existing `.env` |
| `login.mjs` | drives the OAuth login over CDP; prompts for the email code |
| `refresh.mjs` | `refresh_token` → `access_token` → `.env` (no browser) |
| `lib.mjs` | shared OAuth / PKCE / store / `.env` helpers |

## Config (env)

| var | default |
|---|---|
| `OAUTH_TOKEN_STORE` | `./.tokens.json` |
| `OAUTH_ENV_PATH` | repo `../../.env` |
| `OAUTH_ENV_KEY` | `CLAUDE_CODE_OAUTH_TOKEN` |
| `OAUTH_EMAIL` | — |
| `CHROME_PORT` / `CHROME_PROFILE` | `9223` / `~/.cache/oauth-token-chrome` |

## Why a real, headed browser (not obscura / headless)

claude.ai is behind Cloudflare, which challenges headless and synthetic browsers
(obscura and headless Chrome both get *"Just a moment…"*). Getting past that would mean
building a bot-detection bypass — out of scope. A real, **headed** Chrome passes because
it's a genuine browser doing a genuine login. Since `refresh` handles the day-to-day,
that browser is needed only rarely.
