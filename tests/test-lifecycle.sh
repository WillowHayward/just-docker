#!/usr/bin/env bash
# Exercise real runner control flow with deterministic Docker/SOPS stand-ins.
set -euo pipefail
shared="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export JUST_DOCKER_ROOT="$tmp/root space" EVENTS="$tmp/events"
stack="$JUST_DOCKER_ROOT/test stack"
mkdir -p "$stack/hooks" "$stack/secrets" "$tmp/bin"
touch "$stack/compose.yml"
printf 'encrypted\n' > "$stack/secrets/token.sops.txt"
printf 'VALUE=root\n' > "$JUST_DOCKER_ROOT/config.env"
printf 'VALUE=local\n' > "$JUST_DOCKER_ROOT/.env"
printf 'VALUE=stack\n' > "$stack/config.env"
printf 'VALUE=stack-local\n' > "$stack/.env"
cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
[[ "$PWD" == "$JUST_DOCKER_ROOT/test stack" && "$VALUE" == stack-local ]]
[[ "$SECRETS_DIR" == "$PWD/.decrypted" ]]
shift 3
[[ "$1" == version ]] && exit "${VERSION_STATUS:-0}"
printf 'compose %s\n' "$*" >> "$EVENTS"
[[ "${FAIL_AT:-}" != "compose $*" ]] || exit 23
DOCKER
cat > "$tmp/bin/sops" <<'SOPS'
#!/usr/bin/env bash
printf 'secret\n'
exit "${SOPS_STATUS:-0}"
SOPS
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"
for hook in preflight pre-up post-up pre-down post-down pre-restart post-restart cleanup; do
    cat > "$stack/hooks/$hook" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$PWD" == "$JUST_DOCKER_ROOT/test stack" && "$VALUE" == stack-local ]]
[[ "$SECRETS_DIR" == "$PWD/.decrypted" ]]
hook="${0##*/}"
printf '%s\n' "$hook" >> "$EVENTS"
[[ "${FAIL_AT:-}" != "$hook" ]] || exit 23
[[ "$hook" != cleanup ]] || exit "${CLEANUP_STATUS:-0}"
HOOK
    chmod +x "$stack/hooks/$hook"
done
invoke() {
    : > "$EVENTS"
    local status=0
    bash "$shared/scripts/docker.sh" 'test stack' "$1" > "$tmp/output" 2>&1 || status=$?
    [[ "$status" == "$2" ]] || { cat "$tmp/output"; echo "Expected $2, got $status"; exit 1; }
}
expect() {
    diff -u <(printf '%s\n' "$1") "$EVENTS"
}
invoke up 0
expect $'preflight\npre-up\ncompose config --quiet\ncompose up -d\npost-up\ncleanup'
[[ "$(cat "$stack/.decrypted/token.txt")" == secret ]]
invoke down 0
expect $'preflight\npre-down\ncompose config --quiet\ncompose down\npost-down\ncleanup'
[[ ! -e "$stack/.decrypted" ]]
invoke restart 0
expect $'preflight\npre-restart\npre-down\ncompose config --quiet\ncompose down\npost-down\npre-up\ncompose config --quiet\ncompose up -d\npost-up\npost-restart\ncleanup'
[[ "$(cat "$stack/.decrypted/token.txt")" == secret ]]
for point in preflight pre-restart pre-down 'compose config --quiet' 'compose down' post-down pre-up 'compose up -d' post-up post-restart; do
    export FAIL_AT="$point" CLEANUP_STATUS=31
    mkdir -p "$stack/.decrypted"
    invoke restart 23
    [[ "$(tail -n 1 "$EVENTS")" == cleanup ]]
    case "$point" in
        preflight|pre-restart|pre-down|'compose config --quiet'|'compose down'|post-up|post-restart)
            [[ -d "$stack/.decrypted" ]] ;;
        *) [[ ! -e "$stack/.decrypted" ]] ;;
    esac
    # No later lifecycle events should follow a failed step.
    [[ "$(tail -n 2 "$EVENTS" | head -n 1)" == "$point" ]]
    grep -q 'Cleanup hook failed' "$tmp/output"
done
unset FAIL_AT CLEANUP_STATUS
for point in preflight pre-down 'compose down' post-down; do
    mkdir -p "$stack/.decrypted"
    printf 'existing secret\n' > "$stack/.decrypted/token.txt"
    export FAIL_AT="$point"
    invoke down 23
    if [[ "$point" == post-down ]]; then
        [[ ! -e "$stack/.decrypted" ]]
    else
        [[ "$(cat "$stack/.decrypted/token.txt")" == 'existing secret' ]]
    fi
done
unset FAIL_AT
export SOPS_STATUS=29
invoke up 29
expect $'preflight\ncleanup'
[[ ! -e "$stack/.decrypted" ]]
invoke check 29
[[ ! -e "$stack/.decrypted" ]]
unset SOPS_STATUS
export CLEANUP_STATUS=31
invoke up 31
[[ "$(cat "$stack/.decrypted/token.txt")" == secret ]]
unset CLEANUP_STATUS
chmod -x "$stack/hooks/pre-up"
invoke up 1
grep -q 'Hook is not an executable file' "$tmp/output"
[[ ! -e "$stack/.decrypted" ]]
chmod +x "$stack/hooks/pre-up"
cat > "$stack/hooks/pre-up" <<'SIGNAL'
#!/usr/bin/env bash
kill -TERM "$PPID"
SIGNAL
invoke up 143
[[ "$(tail -n 1 "$EVENTS")" == cleanup ]]
[[ ! -e "$stack/.decrypted" ]]
rm -rf "$stack/hooks"
invoke up 0
expect $'compose config --quiet\ncompose up -d'
[[ "$(cat "$stack/.decrypted/token.txt")" == secret ]]
invoke down 0
[[ ! -e "$stack/.decrypted" ]]
invoke check 0
[[ "$(cat "$stack/.decrypted/token.txt")" == secret ]]
[[ "$(stat -c %a "$stack/.decrypted")" == 700 ]]
[[ "$(stat -c %a "$stack/.decrypted/token.txt")" == 600 ]]
invoke unsupported 1
[[ ! -s "$EVENTS" ]]
export VERSION_STATUS=1
invoke up 1
grep -q 'Docker Compose is not available' "$tmp/output"
printf 'Lifecycle checks passed\n'
