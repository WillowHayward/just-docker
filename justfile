set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Resolve the consumer and this imported file independently.
just_docker_root := justfile_directory()
just_docker_script := source_directory() / "scripts/docker.sh"

# Show available commands
default:
    @just --list

# Validate a stack's Compose configuration
check stack:
    JUST_DOCKER_ROOT={{quote(just_docker_root)}} {{quote(just_docker_script)}} {{quote(stack)}} check

# Show the fully-resolved Compose configuration (may include secrets)
config stack:
    JUST_DOCKER_ROOT={{quote(just_docker_root)}} {{quote(just_docker_script)}} {{quote(stack)}} config

up stack:
    JUST_DOCKER_ROOT={{quote(just_docker_root)}} {{quote(just_docker_script)}} {{quote(stack)}} up

run stack:
    JUST_DOCKER_ROOT={{quote(just_docker_root)}} {{quote(just_docker_script)}} {{quote(stack)}} run

down stack:
    JUST_DOCKER_ROOT={{quote(just_docker_root)}} {{quote(just_docker_script)}} {{quote(stack)}} down

restart stack:
    JUST_DOCKER_ROOT={{quote(just_docker_root)}} {{quote(just_docker_script)}} {{quote(stack)}} restart

pull stack:
    JUST_DOCKER_ROOT={{quote(just_docker_root)}} {{quote(just_docker_script)}} {{quote(stack)}} pull

logs stack *args:
    JUST_DOCKER_ROOT={{quote(just_docker_root)}} {{quote(just_docker_script)}} {{quote(stack)}} logs {{args}}

# Apply the consumer's SOPS recipient rules to encrypted secrets
update-keys:
    cd {{quote(just_docker_root)}} && find . -type d \( -name .git -o -name .decrypted \) -prune -o -type f -path '*/secrets/*.sops.*' -exec sops updatekeys -y {} \;
