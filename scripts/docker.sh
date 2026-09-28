#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "${JUST_DOCKER_ROOT:-$PWD}" && pwd)"

STACK="${1:-}"
COMMAND="${2:-}"

if [[ -z "$STACK" || -z "$COMMAND" ]]; then
    echo "Usage: $0 <stack> <check|config|up|run|exec|compose|down|restart|pull|logs>"
    exit 1
fi

STACK_DIR="$ROOT/$STACK"
COMPOSE_FILE="$STACK_DIR/compose.yml"

ENCRYPTED_DIR="$STACK_DIR/secrets"
DECRYPTED_DIR="$STACK_DIR/.decrypted"

case "$COMMAND" in
    check|config|up|run|foreground|fg|exec|compose|down|restart|pull|logs) ;;
    *) echo "Unknown command: $COMMAND" >&2; exit 1 ;;
esac

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
    REMOVE_SECRETS=true

    rm -rf "$DECRYPTED_DIR"
    mkdir -p "$DECRYPTED_DIR"
    chmod 700 "$DECRYPTED_DIR"

    [[ -d "$ENCRYPTED_DIR" ]] || return 0

    while IFS= read -r -d '' source; do
        filename="$(basename "$source")"
        target="$DECRYPTED_DIR/${filename/.sops/}"

        echo "Decrypting: $STACK/secrets/$filename"

        sops --decrypt "$source" > "$target"
        chmod 600 "$target"
    done < <(
        find "$ENCRYPTED_DIR" \
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

run_hook() {
    local hook="$STACK_DIR/hooks/$1"

    [[ -e "$hook" || -L "$hook" ]] || return 0

    if [[ ! -f "$hook" || ! -x "$hook" ]]; then
        echo "Hook is not an executable file: $hook" >&2
        return 1
    fi

    echo "Running hook: $STACK/hooks/$1" >&2
    (cd "$STACK_DIR" && "$hook")
}

cleanup() {
    local status=$?
    local cleanup_status=0

    trap - EXIT

    # Disable errexit so a failing hook cannot prevent secret removal.
    set +e

    if [[ "$LIFECYCLE" == true ]]; then
        run_hook cleanup
        cleanup_status=$?

        if (( cleanup_status != 0 )); then
            echo "Cleanup hook failed (status $cleanup_status)" >&2
        fi
    fi

    if [[ "$REMOVE_SECRETS" == true ]]; then
        rm -rf "$DECRYPTED_DIR"
        local removal_status=$?

        if (( removal_status != 0 )); then
            echo "Failed to remove decrypted secrets: $DECRYPTED_DIR" >&2

            (( cleanup_status != 0 )) || cleanup_status=$removal_status
        fi
    fi

    (( status != 0 )) || status=$cleanup_status
    exit "$status"
}

start_stack() {
    run_hook pre-up
    compose config --quiet
    compose up -d

    # Containers may need these files even if a later hook fails.
    REMOVE_SECRETS=false

    run_hook post-up
}

stop_stack() {
    run_hook pre-down
    compose config --quiet
    compose down

    REMOVE_SECRETS=true

    run_hook post-down
}

load_env

export SECRETS_DIR="$DECRYPTED_DIR"

command -v docker >/dev/null || {
    echo "Docker is not available" >&2
    exit 1
}

compose version >/dev/null || {
    echo "Docker Compose is not available" >&2
    exit 1
}

LIFECYCLE=false
REMOVE_SECRETS=false

case "$COMMAND" in
    up|down|restart)
        LIFECYCLE=true
        ;;
esac

# Arm cleanup before hooks or decryption can leave partially prepared state.
case "$COMMAND" in
    check|config|up|run|foreground|fg|exec|compose|down|restart)
        trap cleanup EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        ;;
esac

if [[ "$LIFECYCLE" == true ]]; then
    run_hook preflight
fi

case "$COMMAND" in
    check)
        decrypt_secrets
        compose config --quiet
        REMOVE_SECRETS=false
        ;;

    config)
        decrypt_secrets
        compose config
        REMOVE_SECRETS=false
        ;;

    up)
        decrypt_secrets
        start_stack
        ;;

    run|foreground|fg)
        decrypt_secrets
        compose config --quiet
        compose up
        REMOVE_SECRETS=false
        ;;

    exec)
        shift 2

        if (( $# == 0 )); then
            echo "Usage: $0 <stack> exec <service> <command...>" >&2
            exit 1
        fi

        decrypt_secrets
        compose exec "$@"

        # Stack may still be using decrypted bind-mounted secrets.
        REMOVE_SECRETS=false
        ;;

    compose)
        shift 2

        if (( $# == 0 )); then
            echo "Usage: $0 <stack> compose <compose args...>" >&2
            exit 1
        fi

        decrypt_secrets
        compose "$@"

        # Generic compose operations may create/start containers which
        # continue to depend on files in .decrypted.
        REMOVE_SECRETS=false
        ;;

    down)
        stop_stack
        ;;

    restart)
        run_hook pre-restart
        stop_stack

        decrypt_secrets
        start_stack

        run_hook post-restart
        ;;

    pull)
        compose config --quiet
        compose pull
        ;;

    logs)
        compose config --quiet
        shift 2
        compose logs -f "$@"
        ;;
esac
