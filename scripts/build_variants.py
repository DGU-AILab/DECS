#!/usr/bin/env python3
import argparse
import json
import shlex
import subprocess
from pathlib import Path

from variant_matrix import build_tags, load_manifest


BUILD_ARG_KEYS = [
    ("BASE_IMAGE", "base_image"),
    ("DECS_IMAGE_VARIANT", "id"),
    ("CUDA_VERSION", "cuda_version"),
    ("TENSORFLOW_VERSION", "tensorflow_version"),
    ("TENSORFLOW_PACKAGE", "tensorflow_package"),
    ("PYTHON_VERSION", "python_version"),
    ("UBUNTU_VERSION", "ubuntu_version"),
    ("MIN_NVIDIA_DRIVER", "min_nvidia_driver"),
]


def select_variants(manifest, selected):
    variants = manifest["variants"]
    if not selected:
        return variants
    matches = [variant for variant in variants if variant["id"] == selected]
    if not matches:
        raise SystemExit(f"variant not found: {selected}")
    return matches


def build_command(variant, repository, date_tag, no_cache):
    cmd = ["docker", "build", "-f", "Dockerfile"]
    if no_cache:
        cmd.append("--no-cache")

    for docker_arg, key in BUILD_ARG_KEYS:
        cmd.extend(["--build-arg", f"{docker_arg}={variant[key]}"])

    for tag in build_tags(repository, variant, date_tag):
        cmd.extend(["-t", tag])

    cmd.append(".")
    return cmd


def main():
    parser = argparse.ArgumentParser(description="Build DECS Docker image variants.")
    parser.add_argument("--manifest", default="image-variants.json")
    parser.add_argument("--repository")
    parser.add_argument("--date-tag")
    parser.add_argument("--variant")
    parser.add_argument("--push", action="store_true")
    parser.add_argument("--no-cache", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    manifest = load_manifest(repo_root / args.manifest)
    repository = args.repository or manifest["repository"]
    date_tag = args.date_tag or manifest["default_date_tag"]

    for variant in select_variants(manifest, args.variant):
        tags = build_tags(repository, variant, date_tag)
        cmd = build_command(variant, repository, date_tag, args.no_cache)
        print(shlex.join(cmd))
        if not args.dry_run:
            subprocess.run(cmd, cwd=repo_root, check=True)

        if args.push:
            for tag in tags:
                push_cmd = ["docker", "push", tag]
                print(shlex.join(push_cmd))
                if not args.dry_run:
                    subprocess.run(push_cmd, check=True)


if __name__ == "__main__":
    main()
