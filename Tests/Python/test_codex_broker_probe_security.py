#!/usr/bin/env python3
# Copyright (c) 2026 Ling
# SPDX-License-Identifier: MIT

import importlib.machinery
import importlib.util
from pathlib import Path
import os
import socket
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
PROBE_PATH = ROOT / "scripts" / "codex-broker-probe"
LOADER = importlib.machinery.SourceFileLoader("codex_broker_probe", str(PROBE_PATH))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC
PROBE = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(PROBE)


class CodexBrokerProbeSecurityTests(unittest.TestCase):
    def test_only_owner_controlled_unix_sockets_are_trusted(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-island-broker-") as directory:
            root = Path(directory)

            trusted_parent = root / "cxc-trusted"
            trusted_parent.mkdir(mode=0o700)
            trusted_path = trusted_parent / "broker.sock"
            broker = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            broker.bind(str(trusted_path))
            broker.close()

            regular_parent = root / "cxc-regular"
            regular_parent.mkdir(mode=0o700)
            regular_path = regular_parent / "broker.sock"
            regular_path.write_text("not a socket", encoding="utf-8")

            symlink_parent = root / "cxc-symlink"
            symlink_parent.mkdir(mode=0o700)
            symlink_path = symlink_parent / "broker.sock"
            symlink_path.symlink_to(trusted_path)

            writable_parent = root / "cxc-writable"
            writable_parent.mkdir(mode=0o700)
            os.chmod(writable_parent, 0o777)
            writable_path = writable_parent / "broker.sock"
            writable_broker = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            writable_broker.bind(str(writable_path))
            writable_broker.close()

            self.assertTrue(PROBE.trusted_socket(str(trusted_path)))
            self.assertFalse(PROBE.trusted_socket(str(regular_path)))
            self.assertFalse(PROBE.trusted_socket(str(symlink_path)))
            self.assertFalse(PROBE.trusted_socket(str(writable_path)))


if __name__ == "__main__":
    unittest.main()
