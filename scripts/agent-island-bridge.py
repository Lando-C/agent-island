#!/usr/bin/env python3
"""Agent Island hook bridge.

Reads Claude Code / Codex hook JSON from stdin, normalizes the event into a
small status frame, appends it to ~/.agent-island/events.jsonl, then returns a
pass-through hook response that does not take over approval.

Event normalization follows the provider/event split used by DevIsland
(MIT, Copyright (c) 2026 nangchang), simplified for status monitoring only.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


EVENTS_PATH = Path.home() / ".agent-island" / "events.jsonl"
LOG_PATH = Path.home() / ".agent-island" / "bridge.log"
AUTO_APPROVAL_PATH = Path.home() / ".agent-island" / "auto-approval.json"

READ_ONLY_TOOLS = {
    "read",
    "grep",
    "glob",
    "ls",
    "todoread",
}

DANGEROUS_TOOLS = {
    "write",
    "edit",
    "multiedit",
    "notebookedit",
    "delete",
    "move",
    "bash",
    "shell",
    "terminal",
}

DANGEROUS_SHELL_TOKENS = (
    "rm ",
    "rm -",
    "sudo ",
    "chmod ",
    "chown ",
    "mv ",
    "cp ",
    "dd ",
    "mkfs",
    "diskutil ",
    "launchctl ",
    "kill ",
    "pkill ",
    "git push --force",
    "git push -f",
    "git reset --hard",
    "git clean ",
    ">",
    ">>",
    "| sh",
    "| bash",
)

SAFE_SHELL_PREFIXES = (
    "pwd",
    "ls",
    "git status",
    "git diff",
    "git log",
    "rg ",
    "grep ",
    "find ",
    "cat ",
    "sed -n",
    "head ",
    "tail ",
    "wc ",
)


def normalize_name(value: str) -> str:
    return value.lower().replace("_", "").replace("-", "")


def log(message: str) -> None:
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as fh:
            fh.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}\n")
    except Exception:
        pass


def read_payload() -> dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        value = json.loads(raw)
        return value if isinstance(value, dict) else {"payload": value}
    except Exception as exc:
        log(f"json parse failed: {exc}")
        return {"raw": raw[:4000]}


def infer_source(payload: dict[str, Any], explicit: str | None) -> str:
    if explicit:
        return explicit
    text = " ".join(str(payload.get(k, "")) for k in ("cli_source", "agent", "source", "app", "model"))
    if "codex" in text.lower():
        return "codex"
    if "claude" in text.lower():
        return "claude"

    event = normalize_name(str(payload.get("hook_event_name") or payload.get("event") or ""))
    if event == "pretooluse" and payload.get("tool_name"):
        return "codex"
    if payload.get("permission_type") is not None:
        return "claude"
    return "claude"


def event_name(payload: dict[str, Any], event_arg: str | None) -> str:
    return normalize_name(str(
        event_arg
        or payload.get("hook_event_name")
        or payload.get("event")
        or payload.get("hookEventName")
        or ""
    ))


def tool_name(payload: dict[str, Any]) -> str:
    for key in ("tool_name", "toolName", "name"):
        value = payload.get(key)
        if isinstance(value, str) and value:
            return value
    tool_call = payload.get("toolCall")
    if isinstance(tool_call, dict) and tool_call.get("name"):
        return str(tool_call["name"])
    return ""


def nested_value(value: Any, *keys: str) -> Any:
    current = value
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def shell_command(payload: dict[str, Any]) -> str:
    for path in (
        ("command",),
        ("tool_input", "command"),
        ("toolInput", "command"),
        ("input", "command"),
        ("parameters", "command"),
        ("toolCall", "input", "command"),
        ("toolCall", "parameters", "command"),
    ):
        value = nested_value(payload, *path)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def request_id(payload: dict[str, Any]) -> str:
    for path in (
        ("tool_use_id",),
        ("toolUseId",),
        ("permission_request_id",),
        ("permissionRequestId",),
        ("request_id",),
        ("requestId",),
        ("id",),
        ("toolCall", "id"),
        ("tool_call", "id"),
    ):
        value = nested_value(payload, *path)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def tool_input_value(payload: dict[str, Any]) -> Any:
    for path in (
        ("tool_input",),
        ("toolInput",),
        ("input",),
        ("parameters",),
        ("toolCall", "input"),
        ("toolCall", "parameters"),
    ):
        value = nested_value(payload, *path)
        if value not in (None, "", {}, []):
            return value
    return None


def compact_text(value: Any, limit: int = 240) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        text = value
    else:
        try:
            text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        except Exception:
            text = str(value)
    text = " ".join(text.replace("\n", " ").replace("\t", " ").split())
    if len(text) > limit:
        return text[: max(1, limit - 1)] + "…"
    return text


def tool_input_summary(payload: dict[str, Any]) -> str:
    command = shell_command(payload)
    if command:
        return "command: " + compact_text(command, 220)

    value = tool_input_value(payload)
    if isinstance(value, dict):
        for key in ("file_path", "filepath", "path", "pattern", "query", "url", "description"):
            item = value.get(key)
            if isinstance(item, str) and item.strip():
                return f"{key}: {compact_text(item, 180)}"
        return compact_text(value, 240)

    return compact_text(value, 240)


def classify_tool_risk(payload: dict[str, Any]) -> dict[str, Any]:
    tool = tool_name(payload).strip()
    normalized = tool.lower().replace("_", "").replace("-", "")
    command = shell_command(payload)
    lowered_command = command.lower()

    if normalized in READ_ONLY_TOOLS:
        return {
            "risk": "safe_read",
            "reason": f"{tool or 'tool'} is read-only",
            "auto_approval_eligible": True,
        }

    if normalized in {"bash", "shell", "terminal"}:
        if not command:
            return {
                "risk": "manual_shell",
                "reason": "shell command is missing; require human review",
                "auto_approval_eligible": False,
            }
        if any(token in lowered_command for token in DANGEROUS_SHELL_TOKENS):
            return {
                "risk": "dangerous_shell",
                "reason": "shell command contains write/destructive token",
                "auto_approval_eligible": False,
            }
        if any(lowered_command == prefix or lowered_command.startswith(prefix) for prefix in SAFE_SHELL_PREFIXES):
            return {
                "risk": "manual_safe_shell",
                "reason": "shell command appears read-only but still needs explicit shell policy",
                "auto_approval_eligible": False,
            }
        return {
            "risk": "manual_shell",
            "reason": "shell command is not on the read-only allowlist",
            "auto_approval_eligible": False,
        }

    if normalized in DANGEROUS_TOOLS:
        return {
            "risk": "dangerous_tool",
            "reason": f"{tool or 'tool'} can modify files/system state",
            "auto_approval_eligible": False,
        }

    if not normalized:
        return {
            "risk": "unknown",
            "reason": "no tool name provided",
            "auto_approval_eligible": False,
        }

    return {
        "risk": "manual_unknown",
        "reason": f"{tool} is not classified",
        "auto_approval_eligible": False,
    }


def auto_approval_settings() -> dict[str, Any]:
    try:
        if AUTO_APPROVAL_PATH.exists():
            value = json.loads(AUTO_APPROVAL_PATH.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                return value
    except Exception as exc:
        log(f"auto approval settings read failed: {exc}")
    return {"enabled": False, "allow_read_only": True}


def should_auto_allow(source: str, event: str, payload: dict[str, Any]) -> bool:
    if event != "permissionrequest":
        return False
    settings = auto_approval_settings()
    if not bool(settings.get("enabled", False)):
        return False
    if source != "claude":
        # Codex approval response schema is kept status-only until verified.
        return False
    risk = classify_tool_risk(payload)
    return bool(settings.get("allow_read_only", True)) and risk["risk"] == "safe_read"


def session_id(payload: dict[str, Any]) -> str:
    for key in ("session_id", "sessionId", "conversationId", "thread_id", "threadId"):
        value = payload.get(key)
        if value:
            return str(value)
    return ""


def cwd(payload: dict[str, Any]) -> str:
    for key in ("cwd", "workspace", "workspaceRoot"):
        value = payload.get(key)
        if value:
            return str(value)
    return ""


def first_nonempty(*values: Any) -> str:
    for value in values:
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return ""


def normalized_tty(value: str | None) -> str:
    tty = (value or "").strip()
    if not tty or tty in {"??", "-", "?"}:
        return ""
    if tty.startswith("/dev/"):
        return tty
    if tty.startswith("tty"):
        return f"/dev/{tty}"
    return f"/dev/tty{tty}"


def process_tty(start_pid: int, depth: int = 8) -> str:
    seen: set[int] = set()
    pid = start_pid
    for _ in range(depth):
        if pid <= 0 or pid in seen:
            break
        seen.add(pid)
        try:
            output = subprocess.check_output(
                ["/bin/ps", "-p", str(pid), "-o", "ppid=,tty="],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
        except Exception:
            break
        if not output:
            break
        parts = output.split()
        if len(parts) >= 2:
            tty = normalized_tty(parts[1])
            if tty:
                return tty
        try:
            pid = int(parts[0])
        except Exception:
            break
    return ""


def parse_tmux_socket(tmux_env: str | None) -> str:
    value = (tmux_env or "").strip()
    if not value:
        return ""
    socket = value.split(",", 1)[0]
    return socket if socket.startswith("/") else ""


def tmux_executable() -> str:
    for path in ("/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"):
        if os.path.exists(path) and os.access(path, os.X_OK):
            return path
    return "tmux"


def tmux_client_for_tty(socket: str, tty: str) -> str:
    if not tty:
        return ""
    command = [tmux_executable()]
    if socket:
        command += ["-S", socket]
    command += ["list-clients", "-F", "#{client_name}|#{client_tty}"]
    try:
        output = subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL, timeout=0.8)
    except Exception:
        return ""
    tty_name = tty.rsplit("/", 1)[-1]
    for line in output.splitlines():
        if "|" not in line:
            continue
        client, client_tty = line.split("|", 1)
        client_tty = normalized_tty(client_tty)
        if client_tty == tty or client_tty.rsplit("/", 1)[-1] == tty_name:
            return client
    return ""


def terminal_app_from_bundle(bundle_id: str) -> str:
    lower = bundle_id.lower()
    if "iterm" in lower:
        return "iTerm2"
    if "apple.terminal" in lower:
        return "Terminal"
    if "ghostty" in lower:
        return "Ghostty"
    if "wezterm" in lower:
        return "WezTerm"
    if "kitty" in lower:
        return "kitty"
    if "kaku" in lower:
        return "Kaku"
    if "cmux" in lower:
        return "cmux"
    if "warp" in lower:
        return "Warp"
    if "alacritty" in lower:
        return "Alacritty"
    return ""


def terminal_app_from_term_program(term_program: str) -> str:
    lower = term_program.lower()
    if "iterm" in lower:
        return "iTerm2"
    if "apple_terminal" in lower or lower == "terminal":
        return "Terminal"
    if "ghostty" in lower:
        return "Ghostty"
    if "wezterm" in lower:
        return "WezTerm"
    if "kitty" in lower:
        return "kitty"
    if "warp" in lower:
        return "Warp"
    if "alacritty" in lower:
        return "Alacritty"
    return ""


def terminal_app_from_commands(commands: list[str]) -> str:
    joined = "\n".join(commands).lower()
    if "iterm.app" in joined or "iterm2" in joined:
        return "iTerm2"
    if "terminal.app" in joined and "ghostty" not in joined:
        return "Terminal"
    if "ghostty" in joined:
        return "Ghostty"
    if "wezterm" in joined:
        return "WezTerm"
    if "kitty" in joined:
        return "kitty"
    if "kaku" in joined:
        return "Kaku"
    if "cmux" in joined:
        return "cmux"
    if "warp" in joined:
        return "Warp"
    if "alacritty" in joined:
        return "Alacritty"
    return ""


def terminal_bundle_id(app: str) -> str:
    return {
        "iTerm2": "com.googlecode.iterm2",
        "Terminal": "com.apple.Terminal",
        "Ghostty": "com.mitchellh.ghostty",
        "WezTerm": "com.github.wez.wezterm",
        "kitty": "net.kovidgoyal.kitty",
        "cmux": "com.cmuxterm.app",
        "Warp": "dev.warp.Warp-Stable",
    }.get(app, "")


def terminal_metadata(payload: dict[str, Any], pid: int) -> dict[str, str]:
    env = os.environ
    commands = process_chain(pid)
    tty = first_nonempty(
        payload.get("terminal_tty"),
        payload.get("tty"),
        normalized_tty(env.get("TTY")),
        process_tty(pid),
    )
    raw_bundle_id = first_nonempty(
        payload.get("terminal_bundle_id"),
        env.get("__CFBundleIdentifier"),
    )
    bundle_app = terminal_app_from_bundle(raw_bundle_id)
    bundle_id = raw_bundle_id if bundle_app else ""
    app = first_nonempty(
        payload.get("terminal_app"),
        bundle_app,
        terminal_app_from_term_program(env.get("TERM_PROGRAM", "")),
        terminal_app_from_commands(commands),
    )
    if not bundle_id:
        bundle_id = terminal_bundle_id(app)

    tmux_socket = first_nonempty(payload.get("terminal_tmux_socket"), parse_tmux_socket(env.get("TMUX")))
    tmux_client = first_nonempty(payload.get("terminal_tmux_client"), env.get("TMUX_CLIENT"), tmux_client_for_tty(tmux_socket, tty))

    return {
        "cwd": cwd(payload) or env.get("PWD", ""),
        "terminal_app": app,
        "terminal_bundle_id": bundle_id,
        "terminal_tty": tty,
        "terminal_window_id": first_nonempty(payload.get("terminal_window_id"), env.get("WEZTERM_PANE"), env.get("KITTY_WINDOW_ID")),
        "terminal_tab_index": first_nonempty(payload.get("terminal_tab_index")),
        "terminal_session_id": first_nonempty(payload.get("terminal_session_id"), env.get("ITERM_SESSION_ID"), env.get("WEZTERM_PANE"), env.get("KITTY_WINDOW_ID")),
        "terminal_tmux_pane": first_nonempty(payload.get("terminal_tmux_pane"), env.get("TMUX_PANE")),
        "terminal_tmux_socket": tmux_socket,
        "terminal_tmux_client": tmux_client,
    }


def process_chain(start_pid: int, depth: int = 8) -> list[str]:
    commands: list[str] = []
    seen: set[int] = set()
    pid = start_pid
    for _ in range(depth):
        if pid <= 0 or pid in seen:
            break
        seen.add(pid)
        try:
            output = subprocess.check_output(
                ["/bin/ps", "-p", str(pid), "-o", "ppid=,command="],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
        except Exception:
            break
        if not output:
            break
        parts = output.split(None, 1)
        if len(parts) != 2:
            break
        try:
            pid = int(parts[0])
        except ValueError:
            break
        commands.append(parts[1])
    return commands


def is_codex_app(command: str) -> bool:
    value = command.lower()
    return (
        "/applications/codex.app/" in value
        or "/contents/resources/codex app-server" in value
        or value.endswith("/codex app-server")
        or " codex app-server " in value
    )


def is_codex_cli(command: str) -> bool:
    value = command.lower()
    return (
        "codex" in value
        and not is_codex_app(command)
        and " app-server" not in value
        and "mcp-server" not in value
        and "node_repl" not in value
        and (" /bin/codex" in value or "/bin/codex" in value or " codex " in value)
    )


def is_claude_app(command: str) -> bool:
    value = command.lower()
    return (
        "/applications/claude.app/" in value
        or (
            "/library/application support/claude/claude-code/" in value
            and "/claude.app/contents/macos/claude" in value
        )
    )


def is_claude_cli(command: str) -> bool:
    value = command.lower()
    return (
        not is_claude_app(command)
        and (
            "/bin/claude " in value
            or value.endswith("/bin/claude")
            or " claude --output-format" in value
        )
    )


def infer_surface(source: str, pid: int) -> str:
    commands = process_chain(pid)
    if source == "codex":
        if any(is_codex_app(command) for command in commands):
            return "app"
        if any(is_codex_cli(command) for command in commands):
            return "cli"
    if source == "claude":
        if any(is_claude_app(command) for command in commands):
            return "app"
        if any(is_claude_cli(command) for command in commands):
            return "cli"
    return "cli"


def classify(source: str, event: str, payload: dict[str, Any]) -> tuple[str, str, str]:
    tool = tool_name(payload)
    sid = session_id(payload)
    where = cwd(payload)
    suffix = f" · {os.path.basename(where)}" if where else ""

    if event in {"permissionrequest", "elicitation"}:
        title = f"{source.title()} 需要处理"
        detail = tool or "等待人工确认/输入"
        return "needs_attention", title, detail + suffix

    if event == "userpromptsubmit":
        title = f"{source.title()} 收到任务"
        detail = "等待模型开始执行"
        return "queued", title, detail + suffix

    if event in {"pretooluse", "beforetool", "preinvocation"}:
        title = f"{source.title()} 正在执行"
        detail = f"工具: {tool}" if tool else "任务执行中"
        return "working", title, detail + suffix

    if event in {"posttooluse", "afteragent"}:
        title = f"{source.title()} 正在推进"
        detail = f"完成工具: {tool}" if tool else "步骤完成，等待下一步"
        return "working", title, detail + suffix

    if event == "posttoolusefailure":
        title = f"{source.title()} 需要确认"
        detail = f"等待允许/处理: {tool}" if tool else "等待人工允许/处理"
        return "needs_attention", title, detail + suffix

    if event == "stopfailure":
        title = f"{source.title()} 异常"
        detail = f"工具失败: {tool}" if tool else "任务执行失败"
        return "error", title, detail + suffix

    if event in {"stop", "sessionend", "postinvocation"}:
        title = f"{source.title()} 本轮结束"
        detail = f"session {sid[:8]}" if sid else "等待下一步"
        return "idle", title, detail + suffix

    if event in {"sessionstart", "startup", "init"}:
        title = f"{source.title()} 会话开始"
        detail = f"session {sid[:8]}" if sid else "会话已启动"
        return "queued", title, detail + suffix

    if event == "subagentstop":
        title = f"{source.title()} 子任务结束"
        detail = str(payload.get("message") or payload.get("notification") or tool or "子任务结束")
        return "idle", title, detail[:180] + suffix

    if event == "precompact":
        title = f"{source.title()} 整理上下文"
        detail = str(payload.get("message") or payload.get("notification") or "正在压缩/整理上下文")
        return "working", title, detail[:180] + suffix

    if event == "notification":
        title = f"{source.title()} 通知"
        detail = str(payload.get("message") or payload.get("notification") or tool or "状态更新")
        lowered = detail.lower()
        if any(token in lowered for token in ("permission", "approval", "approve", "input", "blocked", "waiting for you", "needs your")):
            return "needs_attention", title, detail[:180] + suffix
        return "idle", title, detail[:180] + suffix

    return "working", f"{source.title()} 活动", (tool or event or "hook event") + suffix


def write_event(source: str, phase: str, title: str, message: str, payload: dict[str, Any]) -> None:
    EVENTS_PATH.parent.mkdir(parents=True, exist_ok=True)
    pid = os.getppid()
    terminal = terminal_metadata(payload, pid)
    risk = classify_tool_risk(payload)
    frame = {
        "agent": source,
        "surface": infer_surface(source, pid),
        "status": phase,
        "title": title,
        "message": message,
        "session": session_id(payload),
        "tool": tool_name(payload),
        "event": str(payload.get("hook_event_name") or payload.get("event") or ""),
        "pid": pid,
        "ts": time.time(),
        "tool_risk": risk["risk"],
        "tool_risk_reason": risk["reason"],
        "auto_approval_eligible": risk["auto_approval_eligible"],
    }
    req_id = request_id(payload)
    input_summary = tool_input_summary(payload)
    if req_id:
        frame["request_id"] = req_id
    if input_summary:
        frame["tool_input_summary"] = input_summary
    frame.update({key: value for key, value in terminal.items() if value})
    with EVENTS_PATH.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(frame, ensure_ascii=False, separators=(",", ":")) + "\n")
    prune_events()


def prune_events(max_lines: int = 2000) -> None:
    try:
        if EVENTS_PATH.stat().st_size < 1_000_000:
            return
        lines = EVENTS_PATH.read_text(encoding="utf-8").splitlines()
        if len(lines) > max_lines:
            EVENTS_PATH.write_text("\n".join(lines[-max_lines:]) + "\n", encoding="utf-8")
    except Exception as exc:
        log(f"event prune failed: {exc}")


def hook_response(source: str, event: str) -> dict[str, Any]:
    # Default is status-only. Auto approval is opt-in via
    # ~/.agent-island/auto-approval.json and is limited to verified read-only
    # Claude PermissionRequest tools; dangerous tools are never auto-approved.
    if source == "claude":
        if event == "permissionrequest":
            return {}
        return {"continue": True, "suppressOutput": True}
    if source == "codex":
        return {}
    return {}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", choices=["claude", "codex"], default=None)
    parser.add_argument("--event", default=None)
    args = parser.parse_args()

    payload = read_payload()
    source = infer_source(payload, args.source)
    event = event_name(payload, args.event)
    phase, title, detail = classify(source, event, payload)
    write_event(source, phase, title, detail, payload)
    if should_auto_allow(source, event, payload):
        log(f"auto approved read-only tool source={source} session={session_id(payload)} tool={tool_name(payload)}")
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            }
        }, separators=(",", ":")))
        return 0
    print(json.dumps(hook_response(source, event), separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
