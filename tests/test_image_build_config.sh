#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$ROOT_DIR/Dockerfile"
CHROME_WRAPPER="$ROOT_DIR/decs-chrome"

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

line_number() {
  local pattern="$1"
  local line
  line="$(grep -nF -- "$pattern" "$DOCKERFILE" | head -n1 | cut -d: -f1)"
  [[ -n "$line" ]] || fail "missing line for '$pattern'"
  printf '%s\n' "$line"
}

assert_contains "$DOCKERFILE" "ARG CONDA_VERSION=26.3.2" "conda version pin"
assert_contains "$DOCKERFILE" '"conda=${CONDA_VERSION}"' "conda install pin"
assert_contains "$DOCKERFILE" 'ARG CONDA_PACKAGES=' "conda package list override"
assert_contains "$DOCKERFILE" 'jupyter_client<8.9' "jupyter client compatible with TensorFlow 2.13 typing_extensions"
assert_contains "$DOCKERFILE" 'krb5-user' "Kerberos client package"
assert_contains "$DOCKERFILE" 'acl' "POSIX ACL tools for Kerberos group sharing"
assert_contains "$DOCKERFILE" 'COPY decs-chrome /usr/local/bin/decs-chrome' "Chrome wrapper installed"
assert_contains "$DOCKERFILE" 'chmod +x /entrypoint.sh /usr/local/bin/decs-chrome' "Chrome wrapper executable"

bash -n "$CHROME_WRAPPER"
assert_contains "$CHROME_WRAPPER" '/var/tmp/decs-chrome-${safe_user}-${uid}' "Chrome profile lives under var tmp"
assert_contains "$CHROME_WRAPPER" '--user-data-dir=$profile_dir' "Chrome wrapper sets profile dir"
assert_contains "$CHROME_WRAPPER" '--disk-cache-dir=$cache_dir/disk' "Chrome wrapper sets disk cache dir"
assert_contains "$CHROME_WRAPPER" '--password-store=basic' "Chrome wrapper avoids keyring writes"
assert_contains "$CHROME_WRAPPER" 'XDG_DATA_HOME="${DECS_CHROME_XDG_DATA_HOME:-$profile_dir/xdg-data}"' "Chrome wrapper keeps NSS data off NFS home"
assert_contains "$CHROME_WRAPPER" 'dbus-run-session -- "${chrome_args[@]}"' "Chrome wrapper supplies DBus session when needed"
assert_contains "$CHROME_WRAPPER" '--disable-component-update' "Chrome wrapper reduces background updater noise"
assert_contains "$CHROME_WRAPPER" '--disable-sync' "Chrome wrapper avoids account sync background writes"
assert_contains "$CHROME_WRAPPER" '--log-level=3' "Chrome wrapper keeps GUI logs quiet"

conda_clean_line="$(line_number "&& conda clean -afy")"
conda_init_line="$(line_number "&& conda init bash")"
pip_tf_line="$(line_number '&& python -m pip install --no-cache-dir "${TENSORFLOW_PACKAGE}"')"

if (( conda_clean_line >= pip_tf_line )); then
  fail "conda clean must run before TensorFlow pip install"
fi

if (( conda_init_line >= pip_tf_line )); then
  fail "conda init must run before TensorFlow pip install"
fi

echo "ok - image build config tests passed"
