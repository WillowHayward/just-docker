#!/usr/bin/env bash
# Import integration checks; no Docker daemon or SOPS keys needed.
set -euo pipefail
shared="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
consumer="$tmp/consumer space"
mkdir -p "$consumer/vendor" "$consumer/test stack" "$tmp/bin"
ln -s "$shared" "$consumer/vendor/shared"
printf "import 'vendor/shared/justfile'\n" > "$consumer/justfile"
touch "$consumer/test stack/compose.yml"
printf 'IMPORT_TEST_VALUE=root\n' > "$consumer/config.env"
printf 'IMPORT_TEST_VALUE=local\n' > "$consumer/.env"
printf 'IMPORT_TEST_VALUE=stack\n' > "$consumer/test stack/config.env"
printf 'IMPORT_TEST_VALUE=stack-local\n' > "$consumer/test stack/.env"
cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
[[ "$PWD" == "$IMPORT_TEST_ROOT/test stack" ]]
[[ "$IMPORT_TEST_VALUE" == stack-local ]]
[[ "$SECRETS_DIR" == "$PWD/.decrypted" ]]
[[ "$1" == compose && "$2" == --file && "$3" == "$PWD/compose.yml" ]]
shift 3
[[ "$1" == version ]] && exit 0
[[ "$*" == "config --quiet" ]] && exit 0
printf '%s\n' "$@"
DOCKER
chmod +x "$tmp/bin/docker"
export PATH="$tmp/bin:$PATH" IMPORT_TEST_ROOT="$consumer"
cd "$consumer/test stack"
output="$(just check 'test stack')"
[[ "$output" == "" ]]
output="$(just logs 'test stack' --tail 50)"
[[ "$output" == $'logs\n-f\n--tail\n50' ]]
output="$(just pull 'test stack')"
[[ "$output" == pull ]]
output="$(just down 'test stack')"
[[ "$output" == down ]]
[[ ! -d .decrypted ]]
if just check missing > "$tmp/missing.log" 2>&1; then
    echo 'Expected a missing stack to fail' >&2
    exit 1
fi
printf 'Import integration checks passed\n'
