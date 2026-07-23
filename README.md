# sandbox

Docker sandbox for running coding agents unattended. You choose which repos the sandbox gets; the agent works on disposable copies of them and can't touch your files — the only way its changes come back is a `git push` you review. Recreate the container and you're back to a clean slate.

## Setup

```bash
git clone https://github.com/emateu/sandbox.git && cd sandbox
cp .env.example .env
$EDITOR .env                  # fill every required field; comments show how
./tools/preflight.sh          # checks the host before you spend a build on it
docker compose up -d --build
docker exec -it sandbox zsh   # repos at ~/Code; run `claude` or `herdr`
```

Create and fill `.env` before running helper tools. Then run `./tools/preflight.sh`: it
fails on invalid required build settings and reports host setup or credential concerns
as errors or warnings before you build.

## Contents

Fedora 44 (digest-pinned) · container user matching your host UID/GID · zsh + oh-my-zsh · Node (fnm) · bun · git, gh, vim, jq · Claude Code CLI · herdr with its Claude Code integration and skill.

Tools install through their official installers at whatever version is latest when the layer builds; rebuild with `--no-cache` to refresh them.

## GitHub access

`GH_TOKEN` (a fine-grained PAT) authenticates `gh` directly and `git` through gh's credential helper. SSH remotes (`git@github.com:...`) are rewritten to https on the fly via `url.insteadOf`, so existing checkouts push fine without any key in the container.

## Helper tools

- `tools/preflight.sh` — validate the host before building. Run it after editing `.env`, and any time the build or the container misbehaves.
- [`tools/oauth-token/`](tools/oauth-token/README.md) — generate `CLAUDE_CODE_OAUTH_TOKEN` and keep it fresh. `get-token.sh` does a one-time browser OAuth login (macOS or Linux) and writes it to an existing `.env`; the container's `claude` wrapper then refreshes it from a stored refresh token on each launch. An alternative to `claude setup-token`.
- `tools/ephemeral-browser.sh [url]` — headed Chrome in a throwaway temp profile, deleted on exit.

## npm registries

Projects with a committed `.npmrc` just work. For registries configured at user level (`~/.npmrc` with registry + key), mount the file read-only via the override — see the `.example`. It can't live in the base compose: on hosts without the file, docker would create a root-owned directory in its place. Prefer a read-only token if yours can publish.

## What the container sees

Your `~/Code` is mounted **read-only** at `/mnt/seed`. At startup the entrypoint copies the repos listed in `SANDBOX_REPOS` into the container's own `~/Code` — that's where the agent works. The host filesystem can't be written from inside; changes leave via `git push` only.

Your agent skills ride along the same way: `~/.claude/skills` is mounted read-only and copied in at startup, and `~/.agents` is mounted read-only so skill symlinks resolve. The one writable host mount is `tools/oauth-token`, deliberately — token rotation has to persist. Everything else is image-baked and gone on recreate.

The container uses the UID/GID configured in `.env`. Match them to `id -u` and `id -g`: on Linux, those IDs own files created in bind mounts; on macOS, Docker Desktop remaps bind-mount ownership, but accurate values keep the setup portable.

Host-specific mounts go in `docker-compose.override.yml` (gitignored, merged automatically) — see the `.example`.

## The working copies

In `.env`:

```bash
SANDBOX_REPOS="myorg/api client-site"        # paths relative to ~/Code
SANDBOX_COPY_EXCLUDES="node_modules"         # dirs skipped while copying
```

How it behaves:

- The copy is a snapshot of the working tree **as-is** — uncommitted changes and untracked files (yes, `.env`s) travel too. That's the point: the sandbox reproduces your current state without per-project configuration.
- `SANDBOX_COPY_EXCLUDES` skips directories at any depth (nested `node_modules` in monorepos included). Empty means copy everything; the mechanism has no opinion, the suggested value does — platform-specific artifacts wouldn't survive the macOS → Linux jump anyway, so reinstall inside.
- Repos are copied only when absent from the container's `~/Code`: restarts keep work in progress, recreating the container (`docker compose down && up -d`) starts over from a fresh copy of the host's current state. Push before you recreate.
- Getting work out: the copied repo keeps its `origin`, and the container rewrites ssh remotes to https with `GH_TOKEN`, so `git push` works as usual. Review as a PR, pull on the host if you like it.
- Changed the list? Recreate the container — already-copied repos are left as they are, new entries are copied in.

## Lifecycle

```bash
docker compose up -d --force-recreate   # fresh environment, same image
docker compose up -d --build            # rebuild after image changes
docker compose build --no-cache         # refresh tool versions (nothing is pinned)
docker compose down --rmi all           # remove everything
```

## License

[MIT](LICENSE)
