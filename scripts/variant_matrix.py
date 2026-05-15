#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path


def load_manifest(path):
    with Path(path).open(encoding="utf-8") as f:
        manifest = json.load(f)

    seen = set()
    for variant in manifest["variants"]:
        variant_id = variant["id"]
        if variant_id in seen:
            raise SystemExit(f"duplicate variant id: {variant_id}")
        seen.add(variant_id)
    return manifest


def build_tags(repository, variant, date_tag):
    tags = [f"{repository}:{variant['id']}-{date_tag}"]
    tags.extend(f"{repository}:{alias}" for alias in variant.get("aliases", []))
    return tags


def build_matrix(manifest, repository, date_tag, selected_variant=None):
    include = []
    for variant in manifest["variants"]:
        if selected_variant and variant["id"] != selected_variant:
            continue

        item = dict(variant)
        item["docker_tags"] = "\n".join(build_tags(repository, variant, date_tag))
        include.append(item)

    if not include:
        raise SystemExit(f"variant not found: {selected_variant}")

    return {"include": include}


def write_github_output(name, value):
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        print(f"{name}={value}")
        return

    with Path(output_path).open("a", encoding="utf-8") as f:
        if "\n" in value:
            f.write(f"{name}<<EOF\n{value}\nEOF\n")
        else:
            f.write(f"{name}={value}\n")


def main():
    parser = argparse.ArgumentParser(description="Generate GitHub Actions matrix from DECS image variants.")
    parser.add_argument("--manifest", default="image-variants.json")
    parser.add_argument("--repository")
    parser.add_argument("--date-tag")
    parser.add_argument("--variant")
    parser.add_argument("--github-output", action="store_true")
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    repository = args.repository or manifest["repository"]
    date_tag = args.date_tag or manifest["default_date_tag"]
    matrix = build_matrix(manifest, repository, date_tag, args.variant)
    matrix_json = json.dumps(matrix, separators=(",", ":"))

    if args.github_output:
        write_github_output("matrix", matrix_json)
    else:
        print(json.dumps(matrix, indent=2))


if __name__ == "__main__":
    main()
