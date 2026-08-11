#!/usr/bin/env python3
# Copyright (c) 2026 Ling
# SPDX-License-Identifier: MIT

import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "Tests" / "AgentIslandTests" / "Fixtures"
BRIDGE_PATH = ROOT / "scripts" / "agent-island-bridge.py"
SPEC = importlib.util.spec_from_file_location("agent_island_bridge", BRIDGE_PATH)
assert SPEC and SPEC.loader
BRIDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BRIDGE)

FIXTURE_NAMES = (
    "claude-permission-request-2.1.191.json",
    "claude-ask-user-question-2.1.191.json",
    "claude-elicitation-2.1.191.json",
)


class ClaudeHookFixtureReplayTests(unittest.TestCase):
    def test_raw_hooks_replay_through_production_normalizer(self) -> None:
        for name in FIXTURE_NAMES:
            with self.subTest(fixture=name):
                fixture = json.loads((FIXTURES / name).read_text(encoding="utf-8"))
                self.assertEqual("Claude Code", fixture["provider"])
                self.assertEqual(
                    "documentation-derived-and-local-version-pinned",
                    fixture["provenance"]["kind"],
                )
                self.assertTrue(fixture["providerVersion"])

                raw_hook = fixture["rawHook"]
                event = BRIDGE.event_name(raw_hook, None)
                actual = BRIDGE.socket_request(
                    "claude",
                    event,
                    fixture["bridgeFrame"],
                    raw_hook,
                )
                self.assertEqual(fixture["normalizedRequest"], actual)

    def test_only_verified_claude_interactions_get_inline_schemas(self) -> None:
        self.assertEqual(
            "claude_permission_request",
            BRIDGE.response_schema("claude", "permissionrequest"),
        )
        self.assertEqual(
            "claude_pre_tool_ask_user_question",
            BRIDGE.response_schema("claude", "askuserquestion"),
        )
        self.assertEqual(
            "claude_elicitation",
            BRIDGE.response_schema("claude", "elicitation"),
        )
        self.assertEqual("status_only", BRIDGE.response_schema("claude", "unknown"))

    def test_event_retention_prunes_old_rows_and_writes_a_private_marker(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-island-retention-") as directory:
            root = Path(directory)
            events = root / "events.jsonl"
            policy = root / "data-retention.json"
            marker = root / "events-pruned-at"
            now = time.time()
            events.write_text(
                "\n".join(
                    [
                        json.dumps({"ts": now - 8 * 24 * 60 * 60, "message": "expired"}),
                        json.dumps({"ts": now, "message": "current"}),
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            policy.write_text(json.dumps({"eventLog": "7_days"}), encoding="utf-8")

            previous = (
                BRIDGE.EVENTS_PATH,
                BRIDGE.DATA_RETENTION_PATH,
                BRIDGE.EVENTS_PRUNE_MARKER_PATH,
            )
            try:
                BRIDGE.EVENTS_PATH = events
                BRIDGE.DATA_RETENTION_PATH = policy
                BRIDGE.EVENTS_PRUNE_MARKER_PATH = marker
                BRIDGE.prune_events()
            finally:
                (
                    BRIDGE.EVENTS_PATH,
                    BRIDGE.DATA_RETENTION_PATH,
                    BRIDGE.EVENTS_PRUNE_MARKER_PATH,
                ) = previous

            retained = events.read_text(encoding="utf-8")
            self.assertNotIn("expired", retained)
            self.assertIn("current", retained)
            self.assertTrue(marker.exists())
            self.assertEqual(0o600, events.stat().st_mode & 0o777)
            self.assertEqual(0o600, marker.stat().st_mode & 0o777)

    def test_private_append_uses_owner_only_directory_and_file_modes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-island-private-log-") as directory:
            path = Path(directory) / "state" / "bridge.log"
            BRIDGE.append_private_text(path, "first\n")
            BRIDGE.append_private_text(path, "second\n")
            self.assertEqual("first\nsecond\n", path.read_text(encoding="utf-8"))
            self.assertEqual(0o700, path.parent.stat().st_mode & 0o777)
            self.assertEqual(0o600, path.stat().st_mode & 0o777)

    def test_auto_approval_rejects_sensitive_or_out_of_workspace_reads(self) -> None:
        safe = {
            "tool_name": "Read",
            "cwd": "/work/project",
            "tool_input": {"file_path": "/work/project/README.md"},
        }
        sensitive = {
            "tool_name": "Read",
            "cwd": "/work/project",
            "tool_input": {"file_path": "/work/project/.env"},
        }
        outside = {
            "tool_name": "Grep",
            "cwd": "/work/project",
            "tool_input": {"path": "/Users/example/.ssh"},
        }
        missing = {"tool_name": "Read", "cwd": "/work/project", "tool_input": {}}
        relative_escape = {
            "tool_name": "Grep",
            "cwd": "/work/project",
            "tool_input": {"path": "../another-project"},
        }
        broad_workspace = {
            "tool_name": "Glob",
            "cwd": str(Path.home()),
            "tool_input": {"path": "."},
        }

        self.assertEqual("safe_read", BRIDGE.classify_tool_risk(safe)["risk"])
        for payload in (sensitive, outside, missing, relative_escape, broad_workspace):
            with self.subTest(payload=payload):
                risk = BRIDGE.classify_tool_risk(payload)
                self.assertEqual("manual_sensitive_read", risk["risk"])
                self.assertFalse(risk["auto_approval_eligible"])


if __name__ == "__main__":
    unittest.main()
