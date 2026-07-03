#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$ROOT_DIR/Dockerfile"

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
