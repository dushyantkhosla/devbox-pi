# pi-dev — minimal trusted Pi sandbox

A small, trusted development container for the [Pi coding agent](https://pi.dev). Project files are bind-mounted read-write; host Pi config is copied once into writable volumes. Extra tools are installed on demand.

## Layout

```text
project/
  compose-pi-devbox.yml   # dev container + optional PostgreSQL
  .sandbox/
    Dockerfile            # build context; only .sandbox/ is sent
    .dockerignore
    entrypoint.sh         # baked to /usr/local/bin/start-pi-dev
    .zshrc
    .tmux.conf
```

`entrypoint.sh`, `.zshrc`, and `.tmux.conf` are baked into the image; editing them requires a rebuild. If you already have a Compose file, merge the `pi` service and volumes rather than overwriting it, and adapt the `db` service and connection URLs.

## Quickstart

Copy `compose-pi-devbox.yml` and `.sandbox/` into the project root. Docker and the Compose plugin are required. Both host dirs must exist and be readable: `~/.pi/agent` and `~/.agents/skills`.

Export credentials and Git identity in the launching shell (or an optional project `.env`; keep secrets out of git):

```sh
export GITHUB_PAT="your-fine-grained-github-token"
export GIT_USER_NAME="Your Name"
export GIT_USER_EMAIL="your-github-noreply-address"

# Optional: match host user, especially on native Linux.
export HOST_UID="$(id -u)" HOST_GID="$(id -g)"
```

The Compose file is not auto-discovered, so pass it explicitly. (Optional: `export COMPOSE_FILE=compose-pi-devbox.yml` once, then drop `-f`.)

```sh
docker compose -f compose-pi-devbox.yml up --build -d
docker compose -f compose-pi-devbox.yml exec pi tmux new-session -A -s dev
```

Inside tmux, run `pi` from your project dir. Detach with `Ctrl-b d`, reattach with the same `exec` command. Tmux survives detaches, not container restarts. A plain shell is `docker compose -f compose-pi-devbox.yml exec pi zsh`.

PostgreSQL is opt-in:

```sh
docker compose -f compose-pi-devbox.yml up -d db
```

## Image

- Base `node:24-bookworm-slim`; Pi from the official `pi.dev` installer (`latest`) at `/opt/pi/agent`; `uv` / `uvx` from the official uv image.
- Baked tools: `bash ca-certificates curl git nano ripgrep sudo tar tmux zsh`.
- `python` / `python3` are a uv-managed CPython 3.14, installed at container start via `uv python install 3.14 --default`.
- Not baked: system Python, `pnpm`, compilers, browsers, `gh`.
- Passwordless `sudo` is available; runtime `apt-get` installs are lost on recreation — bake in what you keep.
- User stays `node` with `HOME=/home/node`.

Project Python comes from `uv`, which downloads the requested version on demand. Use the project's requirement or `.python-version`:

```sh
uv sync
uv run python --version
uv sync --python 3.13   # or: uv venv --python 3.13
```

The project `.venv` lives in the `.:/workspace` bind mount and persists on the host. uv-managed interpreters and the download cache are disposable, so they may need re-downloading after recreation.

## UID / GID

Build args `USER_UID` / `USER_GID` default to `1000`. Matching IDs mainly matters on native Linux for bind-mount ownership; an existing group with the same GID is reused, not renamed.

If you change IDs with existing volumes, fix ownership once (never recursive-`chown` the workspace):

```sh
docker compose -f compose-pi-devbox.yml stop pi
docker compose -f compose-pi-devbox.yml build pi
docker compose -f compose-pi-devbox.yml run --rm --no-deps --user root --entrypoint sh pi -c \
  'chown -R "$(id -u node):$(id -g node)" /home/node/.pi /home/node/.agents/skills'
docker compose -f compose-pi-devbox.yml up -d pi
```

## Seeding

`/usr/local/bin/start-pi-dev` seeds once, sets global Git identity, then execs the CMD (`sleep infinity` by default). Read-only host mounts (must exist): `${HOME}/.pi/agent` → `/seed/pi` and `${HOME}/.agents/skills` → `/seed/skills`.

First run copies an allowlist into writable volumes: `settings.json`, `models.json`, `auth.json`, `agents/`, `prompts/`, `skills/`, `themes/`, `extensions/` into `pi-data` (`/home/node/.pi`), and shared skills into `agent-skills`. It excludes `node_modules`, `.venv`, `__pycache__` and skips `sessions/`, `install/`, `bin/`. Copied `auth.json` is `chmod 600`. Markers prevent re-seeding on restart or rebuild.

To re-import host config and skills, stop Pi, then:

```sh
docker compose -f compose-pi-devbox.yml exec pi rm -f /home/node/.pi/.seeded-from-host /home/node/.agents/skills/.seeded-from-host
docker compose -f compose-pi-devbox.yml restart pi
```

This overwrites the copied files (including auth) but does not purge container-only files. To copy just auth:

```sh
docker compose -f compose-pi-devbox.yml exec pi sh -c 'cp /seed/pi/auth.json /home/node/.pi/agent/auth.json && chmod 600 /home/node/.pi/agent/auth.json'
```

## Workspace, Git, env, network

- `.:/workspace` is a plain bind mount; edits and generated `.venv` / `node_modules` persist on the host. Don't mix Linux-built deps with macOS runs.
- Required env: `GITHUB_PAT`, `GIT_USER_NAME`, `GIT_USER_EMAIL`. Git uses HTTPS askpass with `x-access-token` + PAT; no SSH mount.
- Optional keys: `OPENROUTER_API_KEY`, `OPENCODE_API_KEY`, `TYPESAFE_API_KEY`. No broad `env_file` or OpenAI-key forwarding.
- No Docker socket; manage extra services yourself.
- Published ports are loopback-bound: `127.0.0.1:${FASTAPI_PORT:-8000}:8000` and `127.0.0.1:${SVELTEKIT_PORT:-5173}:5173`. Apps must listen on `0.0.0.0` inside.
- Shell: Zsh + OMZ Agnoster (plugins `git colorize history-substring-search themes z`); tmux with mouse and 50k history.

## Database (opt-in)

`db` is `postgres:17-alpine` under `profile: db` — not started by default, no published ports, reachable at `db:5432`.

```sh
docker compose -f compose-pi-devbox.yml up -d db
docker compose -f compose-pi-devbox.yml stop db
```

Data lives in `postgres-data:/var/lib/postgresql/data`. `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` default to `postgres` / `postgres` / `appdb`. `DATABASE_URL` (SQLAlchemy) and `POSTGRES_URL` (libpq) are derived from those and can be overridden. Development defaults only.

## Security

A trusted development environment, not a hardened sandbox. Pi can edit your host project, read the live seed mounts, and use forwarded or copied credentials. Read-only mounts prevent writes, not reads. Passwordless sudo grants root inside the container; avoid editing `/workspace` with it, which can create root-owned host files on native Linux. No host home, SSH directory, or Docker socket is mounted.

## State and upgrades

Image is `${COMPOSE_PROJECT_NAME}-pi:local` (derived from directory / `-p` / env / top-level `name`); there is no fixed `container_name`, so each project gets its own volumes.

```sh
docker compose -f compose-pi-devbox.yml build --no-cache pi && docker compose -f compose-pi-devbox.yml up -d
docker compose -f compose-pi-devbox.yml down      # keeps named volumes
docker compose -f compose-pi-devbox.yml down -v   # deletes Pi state/auth/skills + DB data, never the bind workspace
```
