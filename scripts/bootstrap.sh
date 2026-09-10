#!/usr/bin/env bash
# Phase 1 rendering stub. Provisioning is deliberately introduced in Phase 2.
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <linux-username>" >&2
  exit 64
fi

printf 'Cloud-init rendering snapshot prepared for %s. Bootstrap provisioning is not implemented in Phase 1.\n' "$1"
