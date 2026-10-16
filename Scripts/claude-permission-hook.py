#!/usr/bin/env python3
"""Claude Code PreToolUse hook that asks NotchHover for a decision.

Sends the pending tool call to the app over loopback and blocks until a human
clicks Approve or Deny in the notch. Anything unexpected -- app not running,
bad token, timeout -- falls back to "ask", which is Claude Code's own prompt.
It never approves on its own.
"""

import json
import os
import socket
import sys

CONFIG_PATH = os.path.expanduser("~/Library/Application Support/NotchHover/bridge.json")
CONNECT_TIMEOUT = 5
DECISION_TIMEOUT = 55

REASONS = {
    "allow": "Approved in NotchHover",
    "deny": "Denied in NotchHover",
    "ask": "NotchHover deferred to the normal prompt",
}


def emit(decision, reason):
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )
    sys.stdout.write("\n")
    sys.exit(0)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        emit("ask", "NotchHover: unreadable hook payload")

    try:
        with open(CONFIG_PATH) as handle:
            config = json.load(handle)
    except Exception:
        emit("ask", "NotchHover is not running")

    request = {
        "token": config.get("token", ""),
        "tool": payload.get("tool_name", ""),
        "input": payload.get("tool_input", {}),
        "cwd": payload.get("cwd", ""),
        "session": payload.get("session_id", ""),
    }

    try:
        connection = socket.create_connection(("127.0.0.1", config["port"]), timeout=CONNECT_TIMEOUT)
        connection.settimeout(DECISION_TIMEOUT)
        connection.sendall((json.dumps(request) + "\n").encode("utf-8"))

        buffer = b""
        while b"\n" not in buffer:
            chunk = connection.recv(4096)
            if not chunk:
                break
            buffer += chunk
        connection.close()
        response = json.loads(buffer.decode("utf-8").strip())
    except Exception as error:
        emit("ask", "NotchHover unavailable: %s" % error)

    decision = response.get("decision", "ask")
    if decision not in REASONS:
        decision = "ask"
    emit(decision, REASONS[decision])


main()
