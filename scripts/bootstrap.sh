#!/usr/bin/env bash
# Provision the shared Ubuntu 24.04 WSL development baseline as root.
set -Eeuo pipefail

readonly BOOTSTRAP_VERSION='phase-2'
readonly OS_RELEASE_FILE="${WSL_DEVELOPMENT_ENVIRONMENT_OS_RELEASE_FILE:-/etc/os-release}"
readonly DOCKER_KEYRING_DIR='/etc/apt/keyrings'
readonly DOCKER_KEYRING_PATH="$DOCKER_KEYRING_DIR/docker.asc"
readonly DOCKER_SOURCE_PATH='/etc/apt/sources.list.d/docker.sources'
readonly SUCCESS_MARKER_DIR='/var/lib/wsl-development-environment'
readonly SUCCESS_MARKER_PATH="$SUCCESS_MARKER_DIR/bootstrap-success"
readonly -a BASELINE_PACKAGES=(
  ca-certificates curl file git openssh-client procps build-essential
)
readonly -a DOCKER_PACKAGES=(
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
)

log() {
  printf '[wsl-development-environment] %s\n' "$*"
}

die() {
  printf '[wsl-development-environment] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ $EUID -eq 0 ]] || die 'bootstrap.sh must run as root.'
}

require_target_user() {
  [[ $# -eq 1 ]] || die "Usage: $0 <linux-username>"
  TARGET_USER=$1
  [[ $TARGET_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Invalid Linux username: $TARGET_USER"
  getent passwd "$TARGET_USER" >/dev/null || die "Linux user does not exist: $TARGET_USER"
  TARGET_GROUP=$(id -gn "$TARGET_USER")
}

require_ubuntu_noble() {
  [[ -r $OS_RELEASE_FILE ]] || die "Unable to read OS release information: $OS_RELEASE_FILE"
  # shellcheck disable=SC1090
  . "$OS_RELEASE_FILE"
  [[ ${ID:-} == 'ubuntu' && ${VERSION_ID:-} == '24.04' && ${VERSION_CODENAME:-} == 'noble' ]] || \
    die 'This bootstrap supports Ubuntu 24.04 (Noble) only.'
  DOCKER_SUITE=$VERSION_CODENAME
}

require_systemd() {
  [[ $(ps -p 1 -o comm= | tr -d '[:space:]') == 'systemd' ]] || \
    die 'systemd must be PID 1 before Docker can be provisioned.'
}

require_docker_architecture() {
  DOCKER_ARCHITECTURE=${WSL_DEVELOPMENT_ENVIRONMENT_DOCKER_ARCHITECTURE:-$(dpkg --print-architecture)}
  case $DOCKER_ARCHITECTURE in
    amd64|arm64|armhf|ppc64el|s390x) ;;
    *) die "Unsupported Docker apt architecture: $DOCKER_ARCHITECTURE" ;;
  esac
}

write_docker_repository() {
  local key_temp source_temp
  install -d -m 0755 "$DOCKER_KEYRING_DIR"
  key_temp=$(mktemp "$DOCKER_KEYRING_DIR/docker.asc.XXXXXX")
  source_temp=$(mktemp "${DOCKER_SOURCE_PATH}.XXXXXX")
  trap 'rm -f "${key_temp:-}" "${source_temp:-}"' RETURN

  log 'Fetching Docker apt signing key.'
  curl --fail --silent --show-error --location --retry 3 \
    --output "$key_temp" \
    'https://download.docker.com/linux/ubuntu/gpg'
  install -o root -g root -m 0644 "$key_temp" "$DOCKER_KEYRING_PATH"

  cat >"$source_temp" <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $DOCKER_SUITE
Components: stable
Architectures: $DOCKER_ARCHITECTURE
Signed-By: $DOCKER_KEYRING_PATH
EOF
  install -o root -g root -m 0644 "$source_temp" "$DOCKER_SOURCE_PATH"
  trap - RETURN
  rm -f "$key_temp" "$source_temp"
}

report_docker_service_failure() {
  log 'docker.service diagnostics follow.'
  systemctl status docker.service --no-pager --full || true
  journalctl --unit docker.service --no-pager --lines 100 || true
}

enable_docker_service() {
  if ! systemctl enable --now docker.service; then
    report_docker_service_failure
    die 'Unable to enable and start docker.service.'
  fi
  if ! systemctl is-enabled --quiet docker.service || ! systemctl is-active --quiet docker.service; then
    report_docker_service_failure
    die 'docker.service did not reach enabled and active state.'
  fi
}

check_installation() {
  local binary
  for binary in git ssh curl file gcc docker; do
    command -v "$binary" >/dev/null || die "Required command is unavailable: $binary"
  done
  docker version >/dev/null
  docker compose version >/dev/null
  docker buildx version >/dev/null
  docker info >/dev/null
}

write_success_marker() {
  install -d -o root -g root -m 0755 "$SUCCESS_MARKER_DIR"
  printf 'bootstrap_version=%s\ncompleted_at=%s\ntarget_user=%s\n' \
    "$BOOTSTRAP_VERSION" "$(date --iso-8601=seconds)" "$TARGET_USER" \
    | install -o root -g root -m 0644 /dev/stdin "$SUCCESS_MARKER_PATH"
}

main() {
  require_root
  require_target_user "$@"
  require_ubuntu_noble
  require_docker_architecture
  require_systemd

  export DEBIAN_FRONTEND=noninteractive
  log 'Updating Ubuntu package metadata and shared baseline.'
  apt-get update
  apt-get -y upgrade
  apt-get install -y "${BASELINE_PACKAGES[@]}"

  write_docker_repository
  log 'Refreshing package metadata after adding Docker apt repository.'
  apt-get update
  apt-get install -y "${DOCKER_PACKAGES[@]}"

  enable_docker_service
  usermod --append --groups docker "$TARGET_USER"
  install -d -o "$TARGET_USER" -g "$TARGET_GROUP" -m 0755 "/home/$TARGET_USER/Developer"

  check_installation
  write_success_marker
  log "Bootstrap completed successfully for $TARGET_USER. Restart WSL before using Docker without sudo."
}

main "$@"
