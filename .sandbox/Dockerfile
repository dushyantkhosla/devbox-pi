# syntax=docker/dockerfile:1
FROM node:24-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# uv manages project Python versions; additional tools are installed on demand.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git nano ripgrep sudo tar tmux zsh \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

ARG USER_UID=1000
ARG USER_GID=1000

# Set ownership in the install layer to avoid duplicating Pi's files in a later layer.
RUN curl -fsSL https://pi.dev/install.sh -o /tmp/pi-install.sh \
    && PI_CODING_AGENT_DIR=/opt/pi/agent sh /tmp/pi-install.sh \
    && rm /tmp/pi-install.sh \
    && npm cache clean --force \
    && chown -R "${USER_UID}:${USER_GID}" /opt/pi

# Reuse an existing group when its GID matches (e.g. macOS staff is GID 20).
# Keep the account/home paths stable so existing Pi volumes remain usable.
RUN if ! getent group "${USER_GID}" >/dev/null; then \
    groupmod --gid "${USER_GID}" node; \
    fi \
    && usermod --uid "${USER_UID}" --gid "${USER_GID}" --shell /bin/zsh node \
    && printf 'node ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node \
    && mkdir -p /workspace /home/node/.pi/agent /home/node/.agents/skills \
    && chown -R "${USER_UID}:${USER_GID}" /workspace /home/node \
    && git config --system --add safe.directory /workspace

RUN printf '%s\n' \
    '#!/bin/sh' \
    'case "$1" in' \
    '    *Username*github.com*) printf "%s\n" "x-access-token" ;;' \
    '    *Password*github.com*) printf "%s\n" "$GITHUB_PAT" ;;' \
    '    *) exit 1 ;;' \
    'esac' \
    > /usr/local/bin/git-askpass \
    && chmod 0755 /usr/local/bin/git-askpass

COPY entrypoint.sh /usr/local/bin/start-pi-dev
RUN chmod 0755 /usr/local/bin/start-pi-dev

USER node
ENV HOME=/home/node \
    SHELL=/bin/zsh \
    PATH=/opt/pi/agent/bin:/home/node/.local/bin:${PATH}

RUN curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o /tmp/ohmyzsh-install.sh \
    && sh /tmp/ohmyzsh-install.sh --unattended --skip-chsh \
    && rm /tmp/ohmyzsh-install.sh

COPY --chown=${USER_UID}:${USER_GID} .zshrc .tmux.conf /home/node/

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/start-pi-dev"]
CMD ["sleep", "infinity"]
