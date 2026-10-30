#!/usr/bin/env python3
"""Apply the reviewed local accessibility backport to the pinned Flutter SDK.

Flutter 3.41.4 can merge distinct OverlayPortal traversal anchors, losing a
parent and freezing the native AX tree. The 3.41.4 backport only prevents
merging two different non-null anchors; ordinary unannotated content keeps its
existing merge behavior. See flutter/flutter#182444 and #190344.
Also backports the orphan traversal-node fix merged as flutter/flutter#193372
(b304cf18b6864d141cf08e26a07898901cddb4b5), including its prerequisite dirty-node
registration and hit-test filtering, adapted to 3.41.4. The patch preserves the
Flutter Authors' BSD license in the source file. SDK upgrades require review.
"""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import sys
import subprocess
import tempfile


SOURCE = Path("packages/flutter/lib/src/semantics/semantics.dart")
STOCK_SHA = "33d009f0da337e7accbdc22cbc02bcee6061e4862ec2738b8ae698401f0a96a7"
PATCHED_SHA = "20688689940ad19935cd3ed1ec78f9ea116ff7f73dcf954dd36890ccd50fd70a"
ANCHOR_ONLY_SHA = "5b7b588a2cfcfe72e1ba60181deb4178ee720bae31eb317cf4a96342817b688c"
PATCH_FILE = Path(__file__).with_name("flutter_semantics_3_41_4.patch")
ANCHOR = (
    "    if (_traversalChildIdentifier != other._traversalChildIdentifier) {\n"
    "      return false;\n"
    "    }\n"
)
GUARD = (
    "    if (_traversalParentIdentifier != null &&\n"
    "        other._traversalParentIdentifier != null &&\n"
    "        _traversalParentIdentifier != other._traversalParentIdentifier) {\n"
    "      return false;\n"
    "    }\n"
)


def prepare(root, *, check=False, restore=False):
    source = root / SOURCE
    original = source.read_bytes()
    digest = hashlib.sha256(original).hexdigest()
    desired = STOCK_SHA if restore else PATCHED_SHA
    if digest == desired:
        return "Flutter accessibility compatibility state already verified."
    if digest not in {STOCK_SHA, PATCHED_SHA, ANCHOR_ONLY_SHA}:
        raise ValueError(
            "Unsupported Flutter semantics source; review the SDK upgrade "
            "before applying this backport. No files changed."
        )
    if check:
        raise ValueError("Flutter accessibility backport is required; run this script without --check.")
    staged_source = original
    if digest == ANCHOR_ONLY_SHA:
        staged_source = original.decode("utf-8").replace(ANCHOR + GUARD, ANCHOR, 1).encode("utf-8")
        if hashlib.sha256(staged_source).hexdigest() != STOCK_SHA:
            raise ValueError("Intermediate backport checksum mismatch. No files changed.")
    if restore and digest == ANCHOR_ONLY_SHA:
        replacement = staged_source
    else:
        # Apply only in an isolated temporary tree; the SDK is published atomically
        # after verification, including on Windows. Git ships with every Flutter SDK.
        with tempfile.TemporaryDirectory(prefix="comicnotes-flutter-compat-") as directory:
            staging = Path(directory)
            candidate = staging / SOURCE
            candidate.parent.mkdir(parents=True)
            candidate.write_bytes(staged_source)
            command = ["git", "apply"]
            if restore:
                command.append("--reverse")
            command.append(str(PATCH_FILE.resolve()))
            result = subprocess.run(command, cwd=staging, capture_output=True, text=True)
            if result.returncode:
                raise ValueError("Flutter backport failed in staging. No SDK files changed.\n" + result.stderr)
            replacement = candidate.read_bytes()
    if hashlib.sha256(replacement).hexdigest() != desired:
        raise ValueError("Flutter backport checksum mismatch. No files changed.")
    temporary = source.with_name(source.name + ".comicnotes-tmp")
    try:
        temporary.write_bytes(replacement)
        os.replace(temporary, source)
    finally:
        temporary.unlink(missing_ok=True)
    return "Flutter accessibility backport " + ("restored to stock." if restore else "applied and verified.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter-root", type=Path)
    parser.add_argument("--flutter-bin", default="flutter")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--restore", action="store_true")
    args = parser.parse_args()
    root = args.flutter_root
    if root is None:
        executable = shutil.which(args.flutter_bin)
        if executable is None:
            parser.error("Flutter not found; provide --flutter-root or --flutter-bin.")
        root = Path(executable).resolve().parent.parent
    try:
        print(prepare(root, check=args.check, restore=args.restore))
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
