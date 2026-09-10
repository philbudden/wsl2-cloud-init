#!/usr/bin/env bash
# Destructive integration test for a disposable Ubuntu 24.04 systemd environment.
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
readonly BOOTSTRAP="$REPO_ROOT/scripts/bootstrap.sh"
readonly VALIDATE="$REPO_ROOT/scripts/validate.sh"
readonly TEST_USER='wsl-bootstrap-test'
readonly TEST_SUDOERS='/etc/sudoers.d/wsl-bootstrap-test'
FAKE_BIN=$(mktemp -d)
readonly FAKE_BIN
readonly -a DOCKER_CONFLICTS=(docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc)

fail() {
  printf 'bootstrap-integration-test: %s\n' "$*" >&2
  exit 1
}

[[ ${WSL_BOOTSTRAP_TEST_DISPOSABLE:-} == '1' ]] || fail 'set WSL_BOOTSTRAP_TEST_DISPOSABLE=1 to acknowledge this destructive test'
[[ $EUID -eq 0 ]] || fail 'run as root in a disposable Ubuntu 24.04 environment'
# shellcheck disable=SC1091
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == '24.04' && $VERSION_CODENAME == noble ]] || fail 'requires Ubuntu 24.04 (Noble)'
[[ $(ps -p 1 -o comm= | tr -d '[:space:]') == systemd ]] || fail 'requires systemd as PID 1'

cleanup() {
  rm -f "$TEST_SUDOERS"
  userdel --remove "$TEST_USER" 2>/dev/null || true
  rm -rf "$FAKE_BIN"
}
trap cleanup EXIT

apt-get update
apt-get remove -y "${DOCKER_CONFLICTS[@]}" || true
rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc
systemctl stop docker.service docker.socket 2>/dev/null || true

id "$TEST_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$TEST_USER"
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$TEST_USER" >"$TEST_SUDOERS"
chmod 0440 "$TEST_SUDOERS"
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
chmod 0755 "$FAKE_BIN/curl"
if PATH="$FAKE_BIN:$PATH" "$BOOTSTRAP" "$TEST_USER"; then
  fail 'forced Docker-key retrieval failure unexpectedly succeeded'
fi
"$BOOTSTRAP" "$TEST_USER"

if ! uname -r | grep -qi 'microsoft.*wsl2'; then
  cat >"$FAKE_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf '6.6.0-microsoft-standard-WSL2\n'
EOF
  cat >"$FAKE_BIN/cloud-init" <<'EOF'
#!/usr/bin/env bash
case $1 in
  schema) exit 0 ;;
  status) printf 'status: disabled\n'; exit 0 ;;
esac
exit 64
EOF
  cat >"$FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
[[ $1 == '-n' ]] && shift
exec "$@"
EOF
  chmod 0755 "$FAKE_BIN/uname" "$FAKE_BIN/cloud-init" "$FAKE_BIN/sudo"
  VALIDATE_PATH="$FAKE_BIN:$PATH"
else
  VALIDATE_PATH=$PATH
fi

test -r /etc/apt/keyrings/docker.asc
grep -Fx 'URIs: https://download.docker.com/linux/ubuntu' /etc/apt/sources.list.d/docker.sources
grep -Fx 'Suites: noble' /etc/apt/sources.list.d/docker.sources
for package in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
  dpkg-query --show "$package" >/dev/null
done
systemctl is-enabled --quiet docker.service
systemctl is-active --quiet docker.service
id -nG "$TEST_USER" | tr ' ' '\n' | grep -Fx docker
test -d "/home/$TEST_USER/Developer"
test "$(stat -c '%U' "/home/$TEST_USER/Developer")" == "$TEST_USER"
docker version >/dev/null
docker compose version >/dev/null
docker buildx version >/dev/null
docker info >/dev/null
runuser --login "$TEST_USER" --command 'docker info >/dev/null'
test -f /var/lib/wsl-development-environment/bootstrap-success
printf 'preserve me\n' >"/home/$TEST_USER/Developer/bootstrap-rerun-sentinel"
chown "$TEST_USER:$TEST_USER" "/home/$TEST_USER/Developer/bootstrap-rerun-sentinel"
runuser --login "$TEST_USER" --command "PATH=$VALIDATE_PATH $VALIDATE"

"$BOOTSTRAP" "$TEST_USER"
grep -c '^Types: deb$' /etc/apt/sources.list.d/docker.sources | grep -Fx 1
id -nG "$TEST_USER" | tr ' ' '\n' | grep -cFx docker | grep -Fx 1
test "$(stat -c '%U' "/home/$TEST_USER/Developer")" == "$TEST_USER"
test -f "/home/$TEST_USER/Developer/bootstrap-rerun-sentinel"
runuser --login "$TEST_USER" --command "PATH=$VALIDATE_PATH $VALIDATE"

printf 'bootstrap-integration-test.sh: PASS\n'
