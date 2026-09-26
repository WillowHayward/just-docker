# Project basics

just-docker provides reusable just recipes and a Bash runner for Docker Compose
stacks with SOPS/age secrets. Consumers normally import this repository's
`justfile` through a Git submodule. See `README.md` for setup and usage.

## Structure and conventions

- `justfile`: user-facing commands; keep orchestration in `scripts/docker.sh`.
- `scripts/docker.sh`: environment loading, validation, secrets, and lifecycle
  orchestration. Docker Compose manages containers; stack hooks manage
  stack-specific preparation and cleanup.
- `tests/test-import.sh`: import resolution, paths, environment, and CLI checks.
- `tests/test-lifecycle.sh`: hook ordering, failures, and secret retention/cleanup.
- Keep the implementation straightforward Bash with `set -euo pipefail`, quoted
  paths, and small reusable functions. Avoid adding dependencies.
- Preserve consumer-relative stack resolution and support paths with spaces.
- Load environment files in order: root `config.env`, root `.env`, stack
  `config.env`, stack `.env`. Later values win.
- Execute hooks as separate processes from the stack directory, never source
  them. Missing hooks are normal. Restart deliberately performs down then up.
- Retain `.decrypted/` after successful up/restart because running containers may
  depend on it, including when a subsequent hook fails. Remove it after successful
  shutdown or failed preparation/startup according to the runner's cleanup rules.
  Keep cleanup hooks separate from secret removal and preserve original failures.
- Never commit decrypted secrets or private keys. Keep secret directories mode
  700 and decrypted files mode 600.
- Update the README when commands or lifecycle behavior change.

## Validation

For runner or recipe changes, run:

```sh
bash tests/test-import.sh
bash tests/test-lifecycle.sh
git diff --check
```

Tests use Docker/SOPS stand-ins; no Docker daemon or SOPS keys are needed. The
import test requires `just`. If ShellCheck is available, also run:

```sh
shellcheck -e SC1091 scripts/docker.sh tests/*.sh
```

SC1091 is excluded because environment files belong to consuming repositories.

## Commits

Use Conventional Commits for every commit:

```text
<type>[optional scope][!]: <description>
```

Use types such as `feat`, `fix`, `docs`, `refactor`, `test`, and `chore`. Write a
short, imperative description and keep commits focused. Mark breaking changes
with `!` or a `BREAKING CHANGE:` footer explaining the impact and migration.

Examples:

```text
feat(hooks): add lifecycle hooks
fix(secrets): retain decrypted files while containers run
docs: document contributor guidelines
```
