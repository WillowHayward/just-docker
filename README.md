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
replaced; `down` removes them after Compose succeeds. Reference these files via
`./.decrypted/password.txt` or `${SECRETS_DIR}/password.txt` in Compose.
`check` validates without starting containers; `config` prints resolved values
and can expose secrets. `pull` and `logs` load environment settings but do not
decrypt secrets, so Compose files using decrypted env files need a prior check
or startup.

`just update-keys` applies the consumer's `.sops.yaml` rules to files matching
`*/secrets/*.sops.*`, skipping Git metadata and decrypted directories. It modifies
encrypted files; review and commit the resulting changes.

## Development

Run `bash tests/test-import.sh` to check imports, paths with spaces, environment
precedence, log arguments, and cleanup using a Docker stand-in.
