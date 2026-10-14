#!/bin/bash
set -euo pipefail

# Mark each volume separately; subsequent starts must not overwrite local edits.
if [[ ! -f "$HOME/.pi/.seeded-from-host" ]]; then
    mkdir -p "$HOME/.pi/agent"
    for entry in settings.json models.json auth.json agents prompts skills themes extensions; do
        if [[ -e "/seed/pi/$entry" || -L "/seed/pi/$entry" ]]; then
            tar --exclude=node_modules --exclude=.venv --exclude=__pycache__ \
                -C /seed/pi -cf - "$entry" \
                | tar --no-same-owner --no-same-permissions -C "$HOME/.pi/agent" -xf -
        fi
    done
    find "$HOME/.pi/agent" \( -type d -o -type f \) -exec chmod u+rwX {} +
    if [[ -f "$HOME/.pi/agent/auth.json" ]]; then
        chmod 600 "$HOME/.pi/agent/auth.json"
    fi
    touch "$HOME/.pi/.seeded-from-host"
    printf '%s\n' 'Seeded Pi configuration and authentication (excluding sessions and host installation).'
fi

if [[ ! -f "$HOME/.agents/skills/.seeded-from-host" ]]; then
    tar --exclude=node_modules --exclude=.venv --exclude=__pycache__ \
        -C /seed/skills -cf - . \
        | tar --no-same-owner --no-same-permissions -C "$HOME/.agents/skills" -xf -
    find "$HOME/.agents/skills" \( -type d -o -type f \) -exec chmod u+rwX {} +
    touch "$HOME/.agents/skills/.seeded-from-host"
    printf '%s\n' 'Seeded shared skills.'
fi

git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
exec "$@"
