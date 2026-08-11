#!/usr/bin/env python3
# Copyright (c) 2026 Ling
# SPDX-License-Identifier: MIT

"""Owner-only local file helpers shared by Agent Island scripts."""

from __future__ import annotations

import os
from pathlib import Path
import stat
import tempfile


def ensure_private_parent(path: Path) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    metadata = os.lstat(path.parent)
    if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.geteuid():
        raise PermissionError(f"unsafe Agent Island data directory: {path.parent}")
    os.chmod(path.parent, 0o700)


def _validate_existing_target(path: Path) -> None:
    try:
        metadata = os.lstat(path)
    except FileNotFoundError:
        return
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.geteuid():
        raise PermissionError(f"unsafe Agent Island data file: {path}")


def _validate_descriptor(descriptor: int, path: Path) -> None:
    metadata = os.fstat(descriptor)
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.geteuid():
        raise PermissionError(f"unsafe Agent Island data file: {path}")


def append_private_text(path: Path, text: str) -> None:
    ensure_private_parent(path)
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT
    for optional_flag in ("O_CLOEXEC", "O_NONBLOCK", "O_NOFOLLOW"):
        flags |= getattr(os, optional_flag, 0)
    descriptor = os.open(path, flags, 0o600)
    try:
        _validate_descriptor(descriptor, path)
        os.fchmod(descriptor, 0o600)
        _write_all(descriptor, text.encode("utf-8"))
    finally:
        os.close(descriptor)


def write_private_text(path: Path, text: str) -> None:
    ensure_private_parent(path)
    _validate_existing_target(path)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        _write_all(descriptor, text.encode("utf-8"))
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(temporary, path)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def read_private_text(path: Path, maximum_bytes: int = 2 * 1024 * 1024) -> str:
    flags = os.O_RDONLY
    for optional_flag in ("O_CLOEXEC", "O_NONBLOCK", "O_NOFOLLOW"):
        flags |= getattr(os, optional_flag, 0)
    descriptor = os.open(path, flags)
    try:
        _validate_descriptor(descriptor, path)
        os.fchmod(descriptor, 0o600)
        chunks: list[bytes] = []
        size = 0
        while True:
            chunk = os.read(descriptor, min(65_536, maximum_bytes + 1 - size))
            if not chunk:
                return b"".join(chunks).decode("utf-8")
            chunks.append(chunk)
            size += len(chunk)
            if size > maximum_bytes:
                raise ValueError(f"Agent Island data file is too large: {path}")
    finally:
        os.close(descriptor)


def _write_all(descriptor: int, data: bytes) -> None:
    offset = 0
    while offset < len(data):
        written = os.write(descriptor, data[offset:])
        if written <= 0:
            raise OSError("private write made no progress")
        offset += written
