import hashlib
import difflib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "flutter_compat", Path(__file__).parents[1] / "prepare_flutter_compat.py"
)
compat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compat)


class FlutterCompatibilityInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / compat.SOURCE
        self.source.parent.mkdir(parents=True)
        self.stock = ("before\n" + compat.ANCHOR + "after\n").encode()
        self.expected = ("before\n" + compat.ANCHOR + compat.GUARD + "after\n").encode()
        patch_file = self.root / "fixture.patch"
        patch_file.write_text("".join(difflib.unified_diff(
            self.stock.decode().splitlines(True), self.expected.decode().splitlines(True),
            fromfile="a/" + str(compat.SOURCE), tofile="b/" + str(compat.SOURCE))))
        context = patch.object(compat, "PATCH_FILE", patch_file)
        context.start()
        self.addCleanup(context.stop)
        self.source.write_bytes(self.stock)
        for name, value in [("STOCK_SHA", self.stock), ("PATCHED_SHA", self.expected)]:
            context = patch.object(compat, name, hashlib.sha256(value).hexdigest())
            context.start()
            self.addCleanup(context.stop)

    def test_apply_is_idempotent_and_restore_is_exact(self):
        compat.prepare(self.root)
        self.assertEqual(self.source.read_bytes(), self.expected)
        timestamp = self.source.stat().st_mtime_ns
        compat.prepare(self.root)
        self.assertEqual(self.source.stat().st_mtime_ns, timestamp)
        compat.prepare(self.root, restore=True)
        self.assertEqual(self.source.read_bytes(), self.stock)

    def test_check_requires_patch_without_writing(self):
        with self.assertRaises(ValueError):
            compat.prepare(self.root, check=True)
        self.assertEqual(self.source.read_bytes(), self.stock)
        compat.prepare(self.root)
        compat.prepare(self.root, check=True)

    def test_unknown_sdk_is_never_modified(self):
        unknown = self.stock + b"unreviewed SDK change\n"
        self.source.write_bytes(unknown)
        with self.assertRaises(ValueError):
            compat.prepare(self.root)
        self.assertEqual(self.source.read_bytes(), unknown)

    def test_failed_publication_preserves_source_and_removes_staging_file(self):
        with patch.object(compat.os, "replace", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                compat.prepare(self.root)
        self.assertEqual(self.source.read_bytes(), self.stock)
        self.assertEqual(list(self.source.parent.glob("*.comicnotes-tmp")), [])

    def test_invalid_patch_preserves_source(self):
        compat.PATCH_FILE.write_text("invalid patch\n")
        with self.assertRaises(ValueError):
            compat.prepare(self.root)
        self.assertEqual(self.source.read_bytes(), self.stock)

    def test_intermediate_backport_migrates_and_restores(self):
        intermediate = self.expected
        composite = self.expected + b"composite fix\n"
        compat.PATCH_FILE.write_text("".join(difflib.unified_diff(
            self.stock.decode().splitlines(True), composite.decode().splitlines(True),
            fromfile="a/" + str(compat.SOURCE), tofile="b/" + str(compat.SOURCE))))
        with patch.object(compat, "ANCHOR_ONLY_SHA", hashlib.sha256(intermediate).hexdigest()), \
             patch.object(compat, "PATCHED_SHA", hashlib.sha256(composite).hexdigest()):
            self.source.write_bytes(intermediate)
            compat.prepare(self.root)
            self.assertEqual(self.source.read_bytes(), composite)
            compat.prepare(self.root, restore=True)
            self.assertEqual(self.source.read_bytes(), self.stock)
            self.source.write_bytes(intermediate)
            compat.prepare(self.root, restore=True)
            self.assertEqual(self.source.read_bytes(), self.stock)

    def test_valid_patch_with_wrong_result_checksum_preserves_source(self):
        # Add a valid extra change, but retain the expected published checksum.
        changed = self.expected + b"unexpected change\n"
        compat.PATCH_FILE.write_text("".join(difflib.unified_diff(
            self.stock.decode().splitlines(True), changed.decode().splitlines(True),
            fromfile="a/" + str(compat.SOURCE), tofile="b/" + str(compat.SOURCE))))
        with self.assertRaises(ValueError):
            compat.prepare(self.root)
        self.assertEqual(self.source.read_bytes(), self.stock)


if __name__ == "__main__":
    unittest.main()
