#!/usr/bin/env python3
import argparse
import re
import secrets
import shlex
import subprocess
from datetime import date, timedelta
from pathlib import Path

from variant_matrix import build_tags, load_manifest


def select_variants(manifest, selected):
    if not selected:
        return manifest["variants"]
    matches = [variant for variant in manifest["variants"] if variant["id"] == selected]
    if not matches:
        raise SystemExit(f"variant not found: {selected}")
    return matches


def safe_name(value):
    return re.sub(r"[^a-zA-Z0-9]", "", value).lower()[:24]


def random_password(length):
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def resolve_uid_script(uid_root):
    candidates = [
        uid_root / "legacy" / "script_test" / "create_container.sh",
        uid_root / "script_test" / "create_container.sh",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    tried = "\n".join(f"  - {candidate}" for candidate in candidates)
    raise SystemExit(f"uid dry-run wrapper not found. Tried:\n{tried}")


def main():
    parser = argparse.ArgumentParser(
        description="Exercise the UID dry-run create-container wrapper with DECS image tags."
    )
    parser.add_argument("--manifest", default="image-variants.json")
    parser.add_argument("--repository", default="dguailab/decs")
    parser.add_argument("--date-tag")
    parser.add_argument("--variant")
    parser.add_argument("--uid-root", default="/home/jy/uid")
    parser.add_argument("--domain", default="LAB")
    parser.add_argument("--server-number", default="10")
    parser.add_argument("--created-by", default="decs-test")
    parser.add_argument("--email", default="decs-smoke@example.invalid")
    parser.add_argument("--phone", default="000-0000-0000")
    parser.add_argument("--enable-vnc", action="store_true")
    parser.add_argument("--print-only", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    manifest = load_manifest(repo_root / args.manifest)
    date_tag = args.date_tag or manifest["default_date_tag"]
    uid_script = resolve_uid_script(Path(args.uid_root))

    repository_name = args.repository.rsplit("/", 1)[-1]
    expiration = (date.today() + timedelta(days=7)).isoformat()
    user_password = random_password(20)
    vnc_password = random_password(8)

    for variant in select_variants(manifest, args.variant):
        tag = build_tags(args.repository, variant, date_tag)[0].split(":", 1)[1]
        username = f"decs{safe_name(variant['id'])}"
        cmd = [
            str(uid_script),
            "--name",
            "DECS Smoke Test",
            "--username",
            username,
            "--no-group",
            "--domain",
            args.domain,
            "--server-number",
            str(args.server_number),
            "--expiration-date",
            expiration,
            "--image",
            repository_name,
            "--version",
            tag,
            "--no-container-name",
            "--no-additional-ports",
            "--created-by",
            args.created_by,
            "--email",
            args.email,
            "--phone",
            args.phone,
            "--note",
            f"DECS image dry-run smoke for {variant['id']}",
            "--user-password",
            user_password,
        ]
        if args.enable_vnc:
            cmd.extend(["--enable-vnc", "true", "--vnc-password", vnc_password])

        print(shlex.join(cmd))
        if not args.print_only:
            subprocess.run(cmd, check=True)


if __name__ == "__main__":
    main()
