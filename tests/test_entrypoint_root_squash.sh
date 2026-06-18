#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRYPOINT="$ROOT_DIR/entrypoint.sh"
SMOKE_PLAYBOOK="$ROOT_DIR/tests/ansible/decs_image_smoke.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  grep -qF -- "$pattern" "$file" || fail "$label: missing '$pattern'"
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -qF -- "$pattern" "$file"; then
    fail "$label: unexpected '$pattern'"
  fi
}

bash -n "$ENTRYPOINT"

assert_contains "$ENTRYPOINT" 'TARGET_UID="${TARGET_UID:-${UID:-}}"' "TARGET_UID fallback"
assert_contains "$ENTRYPOINT" 'TARGET_GID="${TARGET_GID:-${GID:-${TARGET_UID:-}}}"' "TARGET_GID fallback"
assert_contains "$ENTRYPOINT" 'useradd -M' "useradd does not create NFS home"
assert_contains "$ENTRYPOINT" 'pre-create this directory on the NAS' "root_squash missing home guidance"
assert_contains "$ENTRYPOINT" 'run_as_user mkdir -p "$JUPYTER_DIR" "$JUPYTER_CONFIG_DIR"' "user-owned Jupyter dirs"
assert_contains "$ENTRYPOINT" 'run_as_user bash -c' "user-owned home writes"
assert_contains "$ENTRYPOINT" 'sudo -H -u "$USER_ID" env HOME="$USER_HOME" USER="$USER_ID"' "Jupyter runs as user"
assert_contains "$ENTRYPOINT" 'c.NotebookApp.allow_root = False' "Jupyter does not run as root"
assert_not_contains "$ENTRYPOINT" 'chown -R "$USER_ID:$USER_GROUP" "/home/$USER_ID"' "no recursive root chown on NFS home"

assert_contains "$SMOKE_PLAYBOOK" "-e TARGET_UID={{ test_uid | quote }}" "smoke passes TARGET_UID"
assert_contains "$SMOKE_PLAYBOOK" "-e TARGET_GID={{ test_gid | quote }}" "smoke passes TARGET_GID"
assert_contains "$SMOKE_PLAYBOOK" '--mount type=bind,source={{ test_home_root | quote }},target=/smoke-home' "smoke helper mounts home root"
assert_contains "$SMOKE_PLAYBOOK" 'mkdir -p "/smoke-home/${TEST_USERNAME}"' "smoke pre-creates user home"
assert_contains "$SMOKE_PLAYBOOK" 'chown "${TEST_UID}:${TEST_GID}" "/smoke-home/${TEST_USERNAME}"' "smoke pre-creates home ownership"

echo "ok - entrypoint root_squash tests passed"
