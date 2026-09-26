# just-docker

Reusable just recipes & scripts for Docker engagement, including SOPS/age secrets.

## Install in a stack repository

Requires Bash, Git, [just](https://github.com/casey/just) with import support,
Docker Compose v2, and SOPS with access to your age identity.

```sh
git submodule add git@github.com:WillowHayward/just-docker.git just-docker
```

Create a root `justfile` containing:

```just
import 'just-docker/justfile'
```

Commit `.gitmodules`, the submodule pointer, and your justfile. After cloning:

```sh
git submodule update --init --recursive
just --list
just check my-stack
just up my-stack
```

The import exposes `check`, `config`, `up`, `run`, `down`, `restart`, `pull`,
`logs`, and `update-keys`. `run` starts Compose in the foreground; `logs` follows
logs and accepts extra Compose logs arguments, e.g. `just logs my-stack --tail 50`.
The default recipe lists commands. Keep local recipes in the consuming justfile.

To upgrade, update the submodule checkout to the desired revision and commit its
new pointer in the consuming repository.

## Repository layout

```text
justfile
just-docker/                 # submodule
.sops.yaml                   # your SOPS recipient rules
config.env                  # optional shared non-secret settings
.env                        # optional local settings; gitignored
my-stack/
  compose.yml
  config.env                # optional stack settings
  .env                      # optional stack-local settings; gitignored
  secrets/
    password.sops.txt
    application.sops.env
  hooks/                    # optional executable lifecycle scripts
    preflight
    pre-up
    post-up
    cleanup
  .decrypted/               # generated; gitignored
```

Add `.env` and `**/.decrypted/` to the consuming repository's `.gitignore`.
Environment files are sourced as Bash in the order shown above (root config,
root local, stack config, stack local); later values win. Use trusted files.
Provide the age identity through SOPS's normal configuration, such as
`SOPS_AGE_KEY_FILE`. Keep private keys outside version control.

Stacks resolve relative to the consuming root justfile, even when invoked from
inside a stack. Scripts resolve relative to the imported justfile, so the
submodule can also live at a different path. Direct script usage resolves stacks
from the current directory, or from `JUST_DOCKER_ROOT` when set.

`check`, `config`, `up`, `run`, and `restart` decrypt `secrets/*.sops.*` into
`.decrypted/`, removing `.sops` from each filename. The directory has mode 700
and successfully decrypted files have mode 600. Existing decrypted files are
replaced. Successful `up` and `restart` retain `.decrypted/` for running containers;
`down` removes it after Compose successfully stops the stack. Other decrypting
commands also retain files on success. Reference these files via
`./.decrypted/password.txt` or `${SECRETS_DIR}/password.txt` in Compose.
`check` validates without starting containers; `config` prints resolved values
and can expose secrets. `pull` and `logs` load environment settings but do not
decrypt secrets, so Compose files using decrypted env files need a prior check
or startup.

`just update-keys` applies the consumer's `.sops.yaml` rules to files matching
`*/secrets/*.sops.*`, skipping Git metadata and decrypted directories. It modifies
encrypted files; review and commit the resulting changes.

## Lifecycle hooks

Place executable scripts in `<stack>/hooks/`; missing hooks are silently skipped.
Hooks run as separate processes from the stack directory, with the same exported
configuration as Compose, including `SECRETS_DIR` pointing at `.decrypted/`.
Hook environment changes do not propagate back to the runner. Use `chmod +x`
on each hook. Present but non-executable hooks fail clearly.

```text
up:      preflight → pre-up → compose up -d → post-up → cleanup
down:    preflight → pre-down → compose down → post-down → cleanup
restart: preflight → pre-restart
           → pre-down → compose down → post-down
           → pre-up → compose up -d → post-up
         → post-restart → cleanup
```

The runner checks the stack, command, Compose file, and Docker/Compose availability
before invoking hooks. It loads root `config.env`, root `.env`, stack `config.env`,
and stack `.env` in that order. Preflight runs before decryption. For `up`, secrets
are decrypted before `pre-up`; for `restart`, they are decrypted after `post-down`
and before `pre-up`. `down` does not decrypt secrets. Compose configuration is
validated with `docker compose config --quiet` after each `pre-up`/`pre-down`
and before the corresponding Compose action. Other commands also validate
configuration (`config` validates while printing it).

Any failing step stops the lifecycle. An EXIT trap invokes `cleanup` even if
preflight, decryption, validation, another hook, or Compose fails. Secret removal
is separate from the cleanup hook: newly prepared secrets are removed if startup
fails before Compose reports success, and secrets are removed after a successful
Compose down unless the restart subsequently starts successfully. Once Compose up
succeeds, secrets remain even if a post-up, post-restart, or cleanup hook fails.
Failures before decryption or successful shutdown leave existing secrets untouched.
A failed Compose up can partially start containers; failure cleanup still removes
newly prepared secrets in that case. Cleanup hooks must tolerate partial preparation
and must not delete `.decrypted/` while containers need it. The original failure status wins; a cleanup failure after
an otherwise successful lifecycle becomes the exit status. INT and TERM trigger
cleanup with status 130 and 143 respectively; SIGKILL cannot be trapped.
Early validation failures before hooks/decryption do not invoke cleanup.

Only `up`, `down`, and `restart` invoke hooks. `run` (including direct-script aliases
`foreground` and `fg`) keeps its existing foreground behavior. No pull, build,
backup, restore, or update hooks are implemented. The `justfile` remains a thin
command interface.

### Example: Certbot with SOPS

There is no Certbot stack in this repository. In a consuming Certbot stack with
`secrets/cloudflare.sops.ini`, a `hooks/pre-up` script could check that its decrypted
DNS credentials are ready and prepare a directory for persistent certificates:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Environment and SOPS decryption are handled by the runner.
test -s "$SECRETS_DIR/cloudflare.ini" || {
    echo "Missing Certbot DNS credentials" >&2
    exit 1
}
mkdir -p ./letsencrypt
```

Run `chmod +x certbot/hooks/pre-up`. Mount `./letsencrypt` in Compose for persistent
certificate storage, and mount `${SECRETS_DIR}/cloudflare.ini` read-only for DNS
credentials. These credentials remain available after startup for later renewals.
Hooks should never print secret contents. A cleanup hook can remove additional
stack-specific temporary files; leave `.decrypted/` management to the runner.

## Development

Run `bash tests/test-import.sh` and `bash tests/test-lifecycle.sh`. They use Docker
and SOPS stand-ins to cover imports, paths with spaces, environment precedence,
log arguments, hook order, failure propagation, and secret cleanup. No Docker
daemon or SOPS keys are needed.
