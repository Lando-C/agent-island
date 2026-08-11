#!/usr/bin/env python3
# Copyright (c) 2026 Ling
# SPDX-License-Identifier: MIT

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from agent_island_local_data import append_private_text, read_private_text, write_private_text


class LocalDataSecurityTests(unittest.TestCase):
    def test_private_helpers_reject_symbolic_links(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-island-local-data-") as directory:
            root = Path(directory) / "state"
            path = root / "events.jsonl"
            write_private_text(path, "one\n")
            append_private_text(path, "two\n")
            self.assertEqual("one\ntwo\n", read_private_text(path))
            self.assertEqual(0o700, root.stat().st_mode & 0o777)
            self.assertEqual(0o600, path.stat().st_mode & 0o777)

            target = root / "target"
            target.write_text("unchanged", encoding="utf-8")
            link = root / "link"
            link.symlink_to(target)
            for operation in (
                lambda: append_private_text(link, "bad"),
                lambda: write_private_text(link, "bad"),
                lambda: read_private_text(link),
            ):
                with self.assertRaises((OSError, PermissionError)):
                    operation()
            self.assertEqual("unchanged", target.read_text(encoding="utf-8"))

    def test_manual_event_writer_uses_private_projection(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-island-event-") as directory:
            test_home = Path(directory) / "home"
            test_home.mkdir()
            environment = dict(os.environ, HOME=str(test_home))
            subprocess.run(
                [
                    "/bin/bash",
                    str(ROOT / "scripts" / "agent-island-event"),
                    "codex",
                    "cli",
                    "working",
                    "Fixture",
                    "Local only",
                ],
                check=True,
                capture_output=True,
                text=True,
                env=environment,
            )
            state_root = test_home / ".agent-island"
            events = state_root / "events.jsonl"
            payload = json.loads(events.read_text(encoding="utf-8"))
            self.assertEqual("Fixture", payload["title"])
            self.assertEqual(0o700, state_root.stat().st_mode & 0o777)
            self.assertEqual(0o600, events.stat().st_mode & 0o777)


if __name__ == "__main__":
    unittest.main()
