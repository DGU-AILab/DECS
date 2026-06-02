#!/usr/bin/env python3
import argparse
import shlex
import subprocess
from pathlib import Path

from variant_matrix import build_tags, load_manifest


CPU_SMOKE = r"""
set -euo pipefail
command -v python
command -v jupyter
command -v micromamba
test -x /entrypoint.sh
python - <<'PY'
import os
import tensorflow as tf

expected = os.environ.get("DECS_TENSORFLOW_VERSION")
actual = tf.__version__.split("+", 1)[0]
print("tensorflow", tf.__version__)
print("expected", expected)
if expected and actual != expected:
    raise SystemExit(f"TensorFlow version mismatch: {actual} != {expected}")
PY
jupyter --version
micromamba --version
"""

GPU_SMOKE = r"""
set -euo pipefail
nvidia-smi
python - <<'PY'
import tensorflow as tf

gpus = tf.config.list_physical_devices("GPU")
print("tensorflow", tf.__version__)
print("gpus", gpus)
if not gpus:
    raise SystemExit("TensorFlow did not detect a GPU")
PY
"""


def select_variants(manifest, selected):
    if not selected:
        return manifest["variants"]
    matches = [variant for variant in manifest["variants"] if variant["id"] == selected]
    if not matches:
        raise SystemExit(f"variant not found: {selected}")
    return matches


def run(cmd, dry_run):
    print(shlex.join(cmd))
    if not dry_run:
        subprocess.run(cmd, check=True)


def main():
    parser = argparse.ArgumentParser(description="Run local smoke tests for DECS image variants.")
    parser.add_argument("--manifest", default="image-variants.json")
    parser.add_argument("--repository")
    parser.add_argument("--date-tag")
    parser.add_argument("--variant")
    parser.add_argument("--gpu", action="store_true", help="Require GPU visibility through Docker.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    manifest = load_manifest(repo_root / args.manifest)
    repository = args.repository or manifest["repository"]
    date_tag = args.date_tag or manifest["default_date_tag"]

    for variant in select_variants(manifest, args.variant):
        image = build_tags(repository, variant, date_tag)[0]
        run(["docker", "image", "inspect", image], args.dry_run)

        cmd = ["docker", "run", "--rm", "--entrypoint", "bash"]
        if args.gpu:
            cmd.extend(["--gpus", "all"])
        cmd.extend([image, "-lc", CPU_SMOKE])
        run(cmd, args.dry_run)

        if args.gpu:
            run(["docker", "run", "--rm", "--gpus", "all", "--entrypoint", "bash", image, "-lc", GPU_SMOKE], args.dry_run)


if __name__ == "__main__":
    main()
