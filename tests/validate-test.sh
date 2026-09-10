#!/usr/bin/env bash
# Unit tests for validation aggregation, root rejection, and smoke-test skipping.
# shellcheck disable=SC2317
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
readonly VALIDATE="$REPO_ROOT/scripts/validate.sh"
TEMP_ROOT=$(mktemp -d)
readonly TEMP_ROOT
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
  printf 'validate-test: %s\n' "$*" >&2
  exit 1
}

# shellcheck disable=SC1090
source "$VALIDATE"

check_ubuntu_noble() { return 0; }
check_wsl2() { return 0; }
check_systemd() { return 0; }
check_cloud_init() { return 0; }
check_baseline_commands() { return 0; }
check_developer_directory() { return 0; }
check_docker_cli() { return 0; }
check_docker_compose() { return 0; }
check_docker_buildx() { return 0; }
check_docker_service() { return 0; }
check_docker_group() { return 0; }
check_docker_daemon() { return 0; }
check_hello_world() { return 0; }
id() {
  [[ $1 == '-u' ]] || return 1
  printf '1000\n'
}

if ! main --skip-network-smoke-test >"$TEMP_ROOT/skip.out" 2>&1; then
  fail 'skip-network-smoke-test should leave otherwise successful validation green'
fi
grep -Fq 'SKIP: Docker hello-world smoke test' "$TEMP_ROOT/skip.out" || fail 'network skip was not labelled'

check_ubuntu_noble() { return 1; }
check_docker_cli() { return 1; }
if main --skip-network-smoke-test >"$TEMP_ROOT/aggregate.out" 2>&1; then
  fail 'multiple required failures unexpectedly returned success'
fi
grep -Fq 'FAIL: Ubuntu 24.04 (Noble)' "$TEMP_ROOT/aggregate.out" || fail 'OS failure was not reported'
grep -Fq 'FAIL: Docker CLI' "$TEMP_ROOT/aggregate.out" || fail 'Docker failure was not reported'
grep -Fq 'Validation failed: 2 required check(s) failed.' "$TEMP_ROOT/aggregate.out" || fail 'failure count was not aggregated'

if "$VALIDATE" --skip-network-smoke-test >"$TEMP_ROOT/root.out" 2>&1; then
  fail 'validation unexpectedly accepted a root session'
fi
grep -Fq 'FAIL: normal non-root user session' "$TEMP_ROOT/root.out" || fail 'root-session rejection was not reported'

printf 'validate-test.sh: PASS\n'
