# pi-dev — minimal trusted Pi sandbox

A small, trusted development container for the [Pi coding agent](https://pi.dev). Project files are bind-mounted read-write; host Pi configuration is copied into independent writable volumes. Extra tools are installed on demand.

## Layout

```text
project/
  compose.yml        # development container + optional PostgreSQL
  .sandbox/
    Dockerfile       # build context; avoids colliding with production Dockerfile
    .dockerignore
    entrypoint.sh    # baked to /usr/local/bin/start-pi-dev
    .zshrc
    .tmux.conf
```

`entrypoint.sh`, `.zshrc`, and `.tmux.conf` are baked into the image; editing them requires a rebuild. The build context is only `.sandbox/`, not the whole project, and your application Dockerfile remains separate.

If you already have a `compose.yml`, merge the `pi` service and named volumes instead of overwriting it. Reuse your existing database service when appropriate; adapt the connection URLs to its name and credentials.

## Quickstart

Copy `compose.yml` and `.sandbox/` into your project root. Docker and the Compose plugin are required, and both host directories must exist and be readable: `~/.pi/agent` and `~/.agents/skills`.

Export credentials and commit identity in the shell that launches Compose:

```sh
export GITHUB_PAT="your-fine-grained-github-token"
export GIT_USER_NAME="Your Name"
export GIT_USER_EMAIL="your-github-noreply-address"

# Optional: match your host user, especially on native Linux.
export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"
```

Compose reads exported variables or an optional project `.env`; it does not read your host `.zshrc`. Keep any `.env` containing secrets out of version control.

From the directory containing `compose.yml`:

```sh
docker compose up --build -d                 # Pi environment only, no database
docker compose exec pi tmux new-session -A -s dev
```

Inside tmux, run `pi` from your project directory. Detach with `Ctrl-b d`, and reattach using the same command. Tmux sessions survive detaches, but not container restarts. A plain shell is also available with `docker compose exec pi zsh`.

PostgreSQL is started separately when needed:

```sh
docker compose up -d db
```

For an existing environment whose UID/GID you are changing, follow the ownership steps below before starting Pi.

## Image

- Base: `node:24-bookworm-slim`
- Pi installed in image from official `pi.dev` installer (`latest`) at `/opt/pi/agent`
- `uv` / `uvx` copied from official `uv` image
- Baked baseline only: `bash ca-certificates curl git nano ripgrep sudo tar tmux zsh`
- Deliberately **not** baked in: system Python / `python3-venv`, `pnpm`, compilers, browsers, `gh`, other extras

Python comes from `uv`, which downloads an interpreter when the requested version is unavailable. For an existing project, use its Python requirement or `.python-version`:

```sh
uv sync
uv run python --version
```

To choose a version explicitly, use `uv sync --python 3.13`; for a standalone virtual environment, use `uv venv --python 3.13`.

The project `.venv` lives in the normal `.:/workspace` bind mount and persists on the host. A virtual environment generally references its underlying interpreter rather than containing a fully independent copy. That uv-managed interpreter and download cache are disposable, so after recreation you may need to download Python again and recreate/sync the environment. No extra cache volumes are created.

The agent has passwordless `sudo` and can `apt-get install` at runtime. Runtime `apt` installs are lost on recreation — bake in later only what you decide to keep.

User stays `node` with `HOME=/home/node` to preserve existing state.

## UID / GID

`Dockerfile` takes `USER_UID` / `USER_GID` from `${HOST_UID:-1000}` / `${HOST_GID:-1000}`.

Matching IDs is mostly useful on native Linux so bind-mounted files are owned by you. It tolerates shared existing groups (e.g. macOS `gid 20`) without blindly renaming them.

```sh
export HOST_UID="$(id -u)" HOST_GID="$(id -g)"
# or put HOST_UID / HOST_GID in an optional `.env` (non-secret).
# Compose interpolates it. Keep secrets out of git.
```

If you change IDs with **existing** volumes, fix ownership once (never recursive-`chown` the workspace):

```sh
docker compose stop pi
docker compose build pi
docker compose run --rm --no-deps --user root --entrypoint sh pi -c \
  'chown -R "$(id -u node):$(id -g node)" /home/node/.pi /home/node/.agents/skills'
docker compose up -d pi
```

## Entrypoint and first-use seed

One Bash entrypoint: `/usr/local/bin/start-pi-dev` (from `.sandbox/entrypoint.sh`). It seeds on first use only, sets global Git identity, then `exec`s the CMD (`sleep infinity` by default).

Host seeds (both host dirs must exist, `create_host_path: false`):

- `${HOME}/.pi/agent` → read-only `/seed/pi`
- `${HOME}/.agents/skills` → read-only `/seed/skills`

Individual Pi files inside may or may not exist. On first run only:

- `pi-data` (`/home/node/.pi`) gets allowlisted copies: `settings.json`, `models.json`, `auth.json`, `agents/`, `prompts/`, `skills/`, `themes/`, `extensions/`
- `node_modules` / `.venv` / `__pycache__` are recursively excluded
- Top-level host `sessions/` / `install/` / `bin/` and other unlisted dirs are not copied
- Copied `auth.json` is `chmod 600`
- Shared skills are copied to `agent-skills` volume (`/home/node/.agents/skills`)

Copies are writable; originals are untouched. Seed mounts stay mounted readable/live, but the running config is independent after seeding. Symlinks are preserved; absolute host paths may need adjustment.

Markers prevent re-seeding:

- `/home/node/.pi/.seeded-from-host`
- `/home/node/.agents/skills/.seeded-from-host`

Restarts/rebuilds do not overwrite the copies. To deliberately reimport host configuration and skills:

```sh
docker compose exec pi rm -f /home/node/.pi/.seeded-from-host /home/node/.agents/skills/.seeded-from-host
docker compose restart pi
```

This overwrites the selected copied files, including authentication, but does not purge container-only files. Stop Pi before reseeding; do not use volume deletion as a routine refresh mechanism.

If an already-seeded volume is missing auth, copy it explicitly inside `pi` (no bootstrap commands):

```sh
docker compose exec pi sh -c 'cp /seed/pi/auth.json /home/node/.pi/agent/auth.json && chmod 600 /home/node/.pi/agent/auth.json'
```

## Workspace, Git, env, network

- Project root → `.:/workspace`, plain bind mount, no dependency overlays. Edits and generated `.venv` / `node_modules` persist on the host. Do not mix Linux-built deps with macOS executions.
- Required exported env: `GITHUB_PAT`, `GIT_USER_NAME`, `GIT_USER_EMAIL`. Container uses GitHub HTTPS `askpass` with `x-access-token` + `PAT`. No SSH or global Git host mount.
- Optional explicit keys only: `OPENROUTER_API_KEY`, `OPENCODE_API_KEY`, `TYPESAFE_API_KEY`. No OpenAI-key forwarding or broad `env_file`. Copied provider logins are available immediately if valid; credentials can still expire or require another login.
- No Docker socket. You manage extra services; Pi just starts ordinary dev servers itself.
- Only app ports, loopback-bound: `127.0.0.1:${FASTAPI_PORT:-8000}:8000` and `127.0.0.1:${SVELTEKIT_PORT:-5173}:5173`. Apps must listen on `0.0.0.0` inside.
- Shell: Zsh / OMZ Agnoster, plugins `git colorize history-substring-search themes z`; tmux `screen-256color`, `Tc` override, mouse on, 50k history, extended keys.

## Database (opt-in)

`db` is `postgres:17-alpine` with `profile: db` — not started by default. No published ports; no `expose` needed. Reach it at `db:5432`.

```sh
docker compose up -d db   # explicitly enable
docker compose stop db    # stop later
```

Data in `postgres-data:/var/lib/postgresql/data`. `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` default to `postgres` / `postgres` / `appdb` and are shared via nested Compose interpolation:

- `DATABASE_URL` default: `postgresql+psycopg://postgres:postgres@db:5432/appdb`
- `POSTGRES_URL` default: plain `postgresql://...` for `libpq`

Either can be explicitly overridden. Development defaults only.

## Security

This is a trusted development environment, not a hardened security sandbox. Pi can edit your host project, read the live read-only seed mounts, and access forwarded or copied credentials. Read-only mounts prevent writes, not reads. Passwordless sudo grants root access inside the container; avoid using it to edit `/workspace`, since that can create root-owned host files on native Linux. No host home directory, SSH directory, or Docker socket is mounted.

## Image name, state, upgrades

Image is `${COMPOSE_PROJECT_NAME}-pi:local` — computed from directory / `-p` / env / top-level `name`. No fixed `container_name`. Each project gets its own state volumes. Original host directories are never modified.

```sh
docker compose build --no-cache pi && docker compose up -d  # upgrade
docker compose down      # preserves named volumes
docker compose down -v   # deletes Pi config/auth/sessions/skills/DB, never the bind workspace
```
