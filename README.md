# sandbox

Docker sandbox for running coding agents unattended, isolated from the host. The container sees your repos, one SSH key (read-only) and your agent skills. Recreate the container and you get a fresh environment.

## Setup

```bash
git clone https://github.com/emateu/sandbox.git && cd sandbox
cp .env.example .env          # UID/GID/username, SSH key path, token from `claude setup-token`
docker compose up -d --build
docker exec -it sandbox zsh   # repos at ~/Code; run `claude` or `herdr`
```

## Contents

Fedora 44 (digest-pinned) · container user matching your host UID/GID · zsh + oh-my-zsh · Node (fnm) · bun · git, gh, vim, jq · Claude Code CLI · herdr with its Claude Code integration and skill.

## Volumes

| Host | Container | Notes |
|---|---|---|
| `~/Code` | `~/Code` | read-write |
| `$SSH_KEY` (+ `.pub`) | `~/.ssh/id_ed25519` | read-only |
| `~/.claude/skills` | Claude home | read-write; changes land on the host |
| `~/.agents` | Claude home | resolves skill symlinks |

Host-specific mounts go in `docker-compose.override.yml` (gitignored, merged automatically) — see the `.example`.

## Lifecycle

```bash
docker compose up -d --force-recreate   # fresh environment, same image
docker compose up -d --build            # rebuild after image changes
docker compose down --rmi all           # remove everything
```

## License

[MIT](LICENSE)
