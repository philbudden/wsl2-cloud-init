#!/usr/bin/env bash
# Focused guards that must fail before bootstrap changes apt configuration.
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
readonly BOOTSTRAP="$REPO_ROOT/scripts/bootstrap.sh"
TEMP_ROOT=$(mktemp -d)
readonly TEMP_ROOT
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
  printf 'bootstrap-failure-test: %s\n' "$*" >&2
  exit 1
}

expect_failure() {
  local label=$1
  shift
  if "$@" >"$TEMP_ROOT/$label.out" 2>&1; then
    fail "$label unexpectedly succeeded"
  fi
  printf 'PASS: %s\n' "$label"
}

[[ $EUID -eq 0 ]] || fail 'run this focused test as root so the bootstrap reaches its guards consistently'

cat >"$TEMP_ROOT/jammy-os-release" <<'EOF'
ID=ubuntu
VERSION_ID="22.04"
VERSION_CODENAME=jammy
EOF
cat >"$TEMP_ROOT/noble-os-release" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME=noble
EOF
cat >"$TEMP_ROOT/malformed-codename-os-release" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME="../bad"
EOF

expect_failure unsupported-release \
  env WSL_DEVELOPMENT_ENVIRONMENT_OS_RELEASE_FILE="$TEMP_ROOT/jammy-os-release" "$BOOTSTRAP" root
grep -Fq 'Ubuntu 24.04 (Noble) only' "$TEMP_ROOT/unsupported-release.out" || fail 'unsupported-release error was unclear'

expect_failure malformed-codename \
  env WSL_DEVELOPMENT_ENVIRONMENT_OS_RELEASE_FILE="$TEMP_ROOT/malformed-codename-os-release" "$BOOTSTRAP" root
grep -Fq 'Ubuntu 24.04 (Noble) only' "$TEMP_ROOT/malformed-codename.out" || fail 'malformed-codename error was unclear'

expect_failure malformed-architecture \
  env WSL_DEVELOPMENT_ENVIRONMENT_OS_RELEASE_FILE="$TEMP_ROOT/noble-os-release" \
  WSL_DEVELOPMENT_ENVIRONMENT_DOCKER_ARCHITECTURE='../bad' "$BOOTSTRAP" root
grep -Fq 'Unsupported Docker apt architecture' "$TEMP_ROOT/malformed-architecture.out" || fail 'malformed-architecture error was unclear'

expect_failure missing-user \
  env WSL_DEVELOPMENT_ENVIRONMENT_OS_RELEASE_FILE=/etc/os-release "$BOOTSTRAP" wsl_bootstrap_missing_user
grep -Fq 'Linux user does not exist' "$TEMP_ROOT/missing-user.out" || fail 'missing-user error was unclear'

expect_failure malformed-user \
  env WSL_DEVELOPMENT_ENVIRONMENT_OS_RELEASE_FILE=/etc/os-release "$BOOTSTRAP" 'BadUser'
grep -Fq 'Invalid Linux username' "$TEMP_ROOT/malformed-user.out" || fail 'malformed-user error was unclear'

printf 'bootstrap-failure-test.sh: PASS\n'
