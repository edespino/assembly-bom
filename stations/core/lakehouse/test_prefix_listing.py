"""prefix_listing treats a missing S3 prefix as an empty listing."""
import importlib.util
import os
import unittest
from pathlib import Path

os.environ["LAKE_PREFIX"] = "rtest"

_path = Path(__file__).with_name("publish.py")
_spec = importlib.util.spec_from_file_location("lakehouse_publish", _path)
if _spec is None or _spec.loader is None:
    raise RuntimeError(f"cannot load {_path}")
publish = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(publish)


class PrefixListingTest(unittest.TestCase):
    def test_missing_prefix_is_empty(self):
        self.assertEqual(publish.prefix_listing(1, "", ""), "")

    def test_success_returns_stdout(self):
        text = "2026-11-09 01:08:15 12 rtest/keep.txt\n"
        self.assertEqual(publish.prefix_listing(0, text, ""), text)

    def test_stderr_is_a_failure(self):
        with self.assertRaises(SystemExit) as caught:
            publish.prefix_listing(1, "", "AccessDenied")
        self.assertIn("AccessDenied", str(caught.exception))

    def test_exit_0_with_stderr_is_a_failure(self):
        with self.assertRaises(SystemExit) as caught:
            publish.prefix_listing(0, "", "warning")
        self.assertIn("warning", str(caught.exception))

    def test_exit_1_with_stdout_is_a_failure(self):
        with self.assertRaises(SystemExit) as caught:
            publish.prefix_listing(1, "not-empty\n", "")
        self.assertIn("not-empty", str(caught.exception))

    def test_other_exit_is_a_failure(self):
        with self.assertRaises(SystemExit) as caught:
            publish.prefix_listing(2, "", "")
        self.assertIn("exit 2", str(caught.exception))

    def test_data_keys_skip_metadata(self):
        listing = (
            "2026-11-09 01:08:15 12 rtest/aml/transactions/data/file.parquet\n"
            "2026-11-09 01:08:15 4 rtest/aml/transactions/metadata/snap.parquet\n"
            "2026-11-09 01:08:15 1 rtest/keep.txt\n"
        )
        self.assertEqual(
            publish.data_parquet_keys(listing),
            ["rtest/aml/transactions/data/file.parquet"],
        )


if __name__ == "__main__":
    unittest.main()
