#!/usr/bin/env bash
# Validate the installed Ubuntu 24.04 WSL development baseline as its normal user.
set -Eeuo pipefail

readonly OS_RELEASE_FILE='/etc/os-release'
readonly BOOTSTRAP_MARKER='/var/lib/wsl-development-environment/bootstrap-success'
readonly DOCKER_SOCKET='/var/run/docker.sock'

failures=0
skip_network_smoke_test=false

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

skip() {
  printf 'SKIP: %s\n' "$1"
}

check() {
  local label=$1
  shift
  if "$@"; then
    pass "$label"
  else
    fail "$label"
  fi
}

parse_arguments() {
  case $# in
    0) ;;
    1)
      [[ $1 == '--skip-network-smoke-test' ]] || {
        printf 'Usage: %s [--skip-network-smoke-test]\n' "$0" >&2
        exit 64
      }
      skip_network_smoke_test=true
      ;;
    *)
      printf 'Usage: %s [--skip-network-smoke-test]\n' "$0" >&2
      exit 64
      ;;
  esac
}

check_ubuntu_noble() {
  [[ -r $OS_RELEASE_FILE ]] || return 1
  # shellcheck disable=SC1090
  . "$OS_RELEASE_FILE"
  [[ ${ID:-} == ubuntu && ${VERSION_ID:-} == '24.04' && ${VERSION_CODENAME:-} == noble ]]
}

check_wsl2() {
  local kernel
  kernel=$(uname -r)
  [[ $kernel =~ [Mm]icrosoft && $kernel =~ [Ww][Ss][Ll]2 ]]
}

check_systemd() {
  local state
  [[ $(ps -p 1 -o comm= | tr -d '[:space:]') == systemd ]] || return 1
  state=$(systemctl is-system-running 2>/dev/null || true)
  [[ $state == running || $state == degraded ]]
}

check_cloud_init() {
  local status status_exit
  command -v cloud-init sudo >/dev/null || return 1
  sudo -n cloud-init schema --system >/dev/null || return 1

  status=$(sudo -n cloud-init status --long 2>&1)
  status_exit=$?
  case $status in
    *'status: done'*) ;;
    *'status: disabled'*)
      printf 'cloud-init reports disabled after WSL provisioning; checking bootstrap marker and cloud-final state.\n' >&2
      ;;
    *)
      printf '%s\n' "$status" >&2
      return 1
      ;;
  esac
  (( status_exit == 0 )) || [[ $status == *'status: disabled'* ]] || return 1
  [[ -r $BOOTSTRAP_MARKER ]] || return 1
  ! systemctl is-failed --quiet cloud-final.service
}

check_baseline_commands() {
  local command
  for command in git ssh curl file gcc make; do
    command -v "$command" >/dev/null || return 1
  done
}

check_developer_directory() {
  [[ -d "$HOME/Developer" && -O "$HOME/Developer" && -w "$HOME/Developer" ]]
}

check_docker_cli() {
  docker version >/dev/null
}

check_docker_compose() {
  docker compose version >/dev/null
}

check_docker_buildx() {
  docker buildx version >/dev/null
}

check_docker_service() {
  systemctl is-enabled --quiet docker.service && systemctl is-active --quiet docker.service
}

check_docker_group() {
  id -nG | tr ' ' '\n' | grep -Fx docker >/dev/null
}

check_docker_daemon() {
  [[ -S $DOCKER_SOCKET && -r $DOCKER_SOCKET && -w $DOCKER_SOCKET ]] && docker info >/dev/null
}

check_hello_world() {
  docker run --rm hello-world >/dev/null
}

main() {
  failures=0
  skip_network_smoke_test=false
  parse_arguments "$@"

  check 'Ubuntu 24.04 (Noble)' check_ubuntu_noble
  check 'WSL2 kernel environment' check_wsl2
  check 'systemd is PID 1 and operational' check_systemd
  check 'cloud-init configuration and bootstrap completion' check_cloud_init
  check 'normal non-root user session' test "$(id -u)" -ne 0
  check 'baseline commands (git, ssh, curl, file, gcc, make)' check_baseline_commands
  check 'Developer directory is owned and writable by the current user' check_developer_directory
  check 'Docker CLI' check_docker_cli
  check 'Docker Compose plugin' check_docker_compose
  check 'Docker Buildx plugin' check_docker_buildx
  check 'docker.service is enabled and active' check_docker_service
  check 'current user is in docker group' check_docker_group
  check 'Docker socket and daemon access without sudo' check_docker_daemon

  if $skip_network_smoke_test; then
    skip 'Docker hello-world smoke test (network-dependent; full validation remains incomplete)'
  else
    check 'Docker hello-world smoke test' check_hello_world
  fi

  if (( failures > 0 )); then
    printf 'Validation failed: %d required check(s) failed.\n' "$failures" >&2
    return 1
  fi
  if $skip_network_smoke_test; then
    printf 'Validation passed required local checks; network smoke test was skipped.\n'
  else
    printf 'Validation passed all required checks.\n'
  fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
