# sandbox

Docker sandbox for running coding agents unattended, isolated from the host. The container sees your repos and your agent skills — no SSH key inside: GitHub access goes through a fine-grained PAT you can scope and revoke. Recreate the container and you get a fresh environment.

## Setup

```bash
git clone https://github.com/emateu/sandbox.git && cd sandbox
cp .env.example .env          # UID/GID/username, tokens (`claude setup-token`, GitHub PAT), git identity
docker compose up -d --build
docker exec -it sandbox zsh   # repos at ~/Code; run `claude` or `herdr`
```

## Contents

Fedora 44 (digest-pinned) · container user matching your host UID/GID · zsh + oh-my-zsh · Node (fnm) · bun · git, gh, vim, jq · Claude Code CLI · herdr with its Claude Code integration and skill.

## GitHub access

`GH_TOKEN` (a fine-grained PAT) authenticates `gh` directly and `git` through gh's credential helper. SSH remotes (`git@github.com:...`) are rewritten to https on the fly via `url.insteadOf`, so existing checkouts push fine without any key in the container.

## Volumes

| Host | Container | Notes |
|---|---|---|
| `~/Code` | `~/Code` | read-write |
| `~/.claude/skills` | `~/.claude/skills` | read-write; changes land on the host |
| `~/.agents` | `~/.agents` | resolves skill symlinks |

Host-specific mounts go in `docker-compose.override.yml` (gitignored, merged automatically) — see the `.example`.

## Lifecycle

```bash
docker compose up -d --force-recreate   # fresh environment, same image
docker compose up -d --build            # rebuild after image changes
docker compose down --rmi all           # remove everything
```

## License

[MIT](LICENSE)
