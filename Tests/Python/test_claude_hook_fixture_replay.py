#!/usr/bin/env python3
# Copyright (c) 2026 Ling
# SPDX-License-Identifier: MIT

import importlib.util
import json
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
