#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "${JUST_DOCKER_ROOT:-$PWD}" && pwd)"

STACK="${1:-}"
COMMAND="${2:-}"

if [[ -z "$STACK" || -z "$COMMAND" ]]; then
    echo "Usage: $0 <stack> <check|config|up|run|down|restart|pull|logs>"
    exit 1
fi

STACK_DIR="$ROOT/$STACK"
COMPOSE_FILE="$STACK_DIR/compose.yml"

SECRETS_DIR="$STACK_DIR/secrets"
DECRYPTED_DIR="$STACK_DIR/.decrypted"

if [[ ! -d "$STACK_DIR" ]]; then
    echo "Unknown stack: $STACK"
    exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "No compose.yml found for stack: $STACK"
    exit 1
fi

load_env() {
    set -a

    [[ -f "$ROOT/config.env" ]] && source "$ROOT/config.env"
    [[ -f "$ROOT/.env" ]] && source "$ROOT/.env"
    [[ -f "$STACK_DIR/config.env" ]] && source "$STACK_DIR/config.env"
    [[ -f "$STACK_DIR/.env" ]] && source "$STACK_DIR/.env"

    set +a
}

decrypt_secrets() {
    rm -rf "$DECRYPTED_DIR"
    mkdir -p "$DECRYPTED_DIR"
    chmod 700 "$DECRYPTED_DIR"

    [[ -d "$SECRETS_DIR" ]] || return 0

    while IFS= read -r -d '' source; do
        filename="$(basename "$source")"
        target="$DECRYPTED_DIR/${filename/.sops/}"

        echo "Decrypting: $STACK/secrets/$filename"

        sops --decrypt "$source" > "$target"
        chmod 600 "$target"
    done < <(
        find "$SECRETS_DIR" \
            -maxdepth 1 \
            -type f \
            -name '*.sops.*' \
            -print0
    )
}

compose() {
    (
        cd "$STACK_DIR"

        SECRETS_DIR="$DECRYPTED_DIR" \
            docker compose \
                --file "$COMPOSE_FILE" \
                "$@"
    )
}

case "$COMMAND" in
    check)
        load_env
        decrypt_secrets
        compose config -q
        ;;

    config)
        load_env
        decrypt_secrets
        compose config
        ;;
    up)
        load_env
        decrypt_secrets
        compose up -d
        ;;

    run|foreground|fg)
        load_env
        decrypt_secrets
        compose up
        ;;

    down)
        load_env
        compose down
        rm -rf "$DECRYPTED_DIR"
        ;;

    restart)
        load_env
        compose down
        decrypt_secrets
        compose up -d
        ;;

    pull)
        load_env
        compose pull
        ;;

    logs)
        load_env
        shift 2
        compose logs -f "$@"
        ;;

    *)
        echo "Unknown command: $COMMAND"
        echo "Usage: $0 <stack> <check|config|up|run|down|restart|pull|logs>"
        exit 1
        ;;
esac
