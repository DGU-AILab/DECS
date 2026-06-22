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
assert_contains "$ENTRYPOINT" 'KRB5CCNAME="${KRB5CCNAME:-${DECS_KRB5CCNAME:-}}"' "Kerberos ccache env fallback"
assert_contains "$ENTRYPOINT" 'DECS_KRB5_PRINCIPAL="${DECS_KRB5_PRINCIPAL:-${USER_ID}@${KRB5_REALM}}"' "Kerberos principal fallback"
assert_contains "$ENTRYPOINT" 'DECS_KERBEROS_HOST_KEYTAB="${DECS_KERBEROS_HOST_KEYTAB:-false}"' "host keytab mode default"
assert_contains "$ENTRYPOINT" 'DECS_USER_SUDO_MODE="${DECS_USER_SUDO_MODE:-restricted}"' "restricted sudo is default mode"
assert_contains "$ENTRYPOINT" 'DECS_SUPPLEMENTAL_GROUPS="${DECS_SUPPLEMENTAL_GROUPS:-}"' "supplemental groups env default"
assert_contains "$ENTRYPOINT" 'resolve_user_sudo_mode' "sudo mode resolver"
assert_contains "$ENTRYPOINT" 'DECS_USER_SUDO_MODE must be one of' "sudo mode validation"
assert_contains "$ENTRYPOINT" 'ensure_supplemental_groups' "supplemental group setup"
assert_contains "$ENTRYPOINT" 'groupadd -g "$group_gid" "$group_name"' "supplemental group creation"
assert_contains "$ENTRYPOINT" 'usermod -aG "$group_name" "$USER_ID"' "supplemental group membership"
assert_contains "$ENTRYPOINT" 'useradd -M' "useradd does not create NFS home"
assert_contains "$ENTRYPOINT" 'rm -f "/etc/sudoers.d/$USER_ID"' "Kerberos mode can remove passwordless sudo"
assert_contains "$ENTRYPOINT" 'gpasswd -d "$USER_ID" sudo' "Kerberos mode can remove sudo group membership"
assert_contains "$ENTRYPOINT" 'write_restricted_sudoers' "restricted sudo writer"
assert_contains "$ENTRYPOINT" '${USER_ID} ALL=(root) NOPASSWD: ALL' "restricted sudo root-only runas"
assert_contains "$ENTRYPOINT" '/usr/bin/sudo -u *' "restricted sudo blocks sudo user switching"
assert_contains "$ENTRYPOINT" '/usr/bin/setpriv' "restricted sudo blocks setpriv"
assert_contains "$ENTRYPOINT" '/usr/bin/chown' "restricted sudo blocks chown"
assert_contains "$ENTRYPOINT" '/usr/bin/mount' "restricted sudo blocks mount"
assert_contains "$ENTRYPOINT" '/bin/bash' "restricted sudo blocks direct shells"
assert_contains "$ENTRYPOINT" '/usr/bin/python3 -c *' "restricted sudo blocks interpreter one-liners"
assert_contains "$ENTRYPOINT" '/usr/bin/vim' "restricted sudo blocks vim"
assert_contains "$ENTRYPOINT" '/usr/bin/nano' "restricted sudo blocks nano"
assert_contains "$ENTRYPOINT" '/usr/bin/less' "restricted sudo blocks pager shell escapes"
assert_contains "$ENTRYPOINT" '/usr/bin/tee * /etc/sudoers*' "restricted sudo blocks protected tee writes"
assert_contains "$ENTRYPOINT" 'pre-create this directory on the NAS' "root_squash missing home guidance"
assert_contains "$ENTRYPOINT" 'ensure_kerberos_runtime' "Kerberos runtime setup"
assert_contains "$ENTRYPOINT" 'start_kerberos_home_watcher' "Kerberos home watcher"
assert_contains "$ENTRYPOINT" 'host-managed ticket refresh for ${DECS_KRB5_PRINCIPAL}' "host keytab wait guidance"
assert_contains "$ENTRYPOINT" 'Run: kinit ${DECS_KRB5_PRINCIPAL}' "Kerberos kinit fallback guidance"
assert_contains "$ENTRYPOINT" "export KRB5CCNAME=" "Kerberos profile export"
assert_contains "$ENTRYPOINT" "export DECS_KRB5_PRINCIPAL=" "Kerberos profile principal export"
assert_contains "$ENTRYPOINT" "decs-kerberos-status" "Kerberos status helper"
assert_contains "$ENTRYPOINT" "group-dir-share" "Kerberos group share helper"
assert_contains "$ENTRYPOINT" 'chgrp -- "$share_group" "$share_abs"' "share helper changes group as user"
assert_contains "$ENTRYPOINT" 'chmod 2770 "$share_abs"' "share helper sets setgid group permissions"
assert_contains "$ENTRYPOINT" 'setfacl -m "g:${share_group}:--x,m::rwx" "$current_path"' "share helper grants parent traverse ACL"
assert_contains "$ENTRYPOINT" 'setfacl -m "g:${share_group}:rwx,d:g:${share_group}:rwx,m::rwx" "$share_abs"' "share helper grants share ACL"
assert_contains "$ENTRYPOINT" 'run_as_user mkdir -p "$JUPYTER_DIR" "$JUPYTER_CONFIG_DIR"' "user-owned Jupyter dirs"
assert_contains "$ENTRYPOINT" 'run_as_user bash -c' "user-owned home writes"
assert_contains "$ENTRYPOINT" 'user_env+=(KRB5CCNAME="$KRB5CCNAME")' "Kerberos env passed to user processes"
assert_contains "$ENTRYPOINT" 'sudo -H -u "$USER_ID" env "${user_env[@]}"' "Jupyter runs as user with env array"
assert_contains "$ENTRYPOINT" 'c.NotebookApp.allow_root = False' "Jupyter does not run as root"
assert_not_contains "$ENTRYPOINT" 'chown -R "$USER_ID:$USER_GROUP" "/home/$USER_ID"' "no recursive root chown on NFS home"

assert_contains "$SMOKE_PLAYBOOK" "-e TARGET_UID={{ test_uid | quote }}" "smoke passes TARGET_UID"
assert_contains "$SMOKE_PLAYBOOK" "-e TARGET_GID={{ test_gid | quote }}" "smoke passes TARGET_GID"
assert_contains "$SMOKE_PLAYBOOK" '--mount type=bind,source={{ test_home_root | quote }},target=/smoke-home' "smoke helper mounts home root"
assert_contains "$SMOKE_PLAYBOOK" 'mkdir -p "/smoke-home/${TEST_USERNAME}"' "smoke pre-creates user home"
assert_contains "$SMOKE_PLAYBOOK" 'chown "${TEST_UID}:${TEST_GID}" "/smoke-home/${TEST_USERNAME}"' "smoke pre-creates home ownership"

echo "ok - entrypoint root_squash tests passed"
