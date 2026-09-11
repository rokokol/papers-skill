#!/usr/bin/env python3
"""Print the tool names a stdio MCP server advertises, one per line.

Usage: mcp-tools.py [--args] SERVER_COMMAND [ARG...]

Speaks the JSON-RPC handshake the MCP protocol requires (initialize, the initialized
notification, tools/list) over the server's stdin and stdout, and prints the names in the
order the server lists them, following nextCursor until the last page. With --args it
prints one "tool argument" line per argument in each tool's inputSchema instead, so a
caller can check argument names too. The server's log lines on stderr are dropped; a
stdout line that is not JSON is skipped, since some servers print a banner before speaking
the protocol, and so is any message that is not the reply to the request just sent, such
as a notification the server volunteers.

Exit 1 when the server never answers, or answers with an error, so a caller reading an
empty list is told; 2 on a usage error.
"""

import json
import subprocess
import sys

TIMEOUT = 60


def main(argv: list[str]) -> int:
    args = argv[1:]
    with_args = bool(args) and args[0] == "--args"
    if with_args:
        args = args[1:]
    if not args:
        print((__doc__ or "").strip(), file=sys.stderr)
        return 2
    proc = subprocess.Popen(
        args,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    stdin, stdout = proc.stdin, proc.stdout
    assert stdin is not None and stdout is not None
    next_id = 0

    def send(message: dict) -> None:
        stdin.write(json.dumps(message) + "\n")
        stdin.flush()

    def request(method: str, params: dict) -> dict | None:
        """Send a request and return its reply, skipping every other line the server writes"""
        nonlocal next_id
        next_id += 1
        send({"jsonrpc": "2.0", "id": next_id, "method": method, "params": params})
        while True:
            line = stdout.readline()
            if not line:
                return None
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(message, dict) and message.get("id") == next_id:
                return message

    def stop() -> None:
        stdin.close()
        try:
            proc.wait(timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()

    reply = request(
        "initialize",
        {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "mcp-tools", "version": "0"},
        },
    )
    if reply is None or "result" not in reply:
        stop()
        print("mcp-tools: the server did not answer initialize", file=sys.stderr)
        return 1
    send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    tools: list[dict] = []
    cursor = None
    while True:
        reply = request("tools/list", {"cursor": cursor} if cursor else {})
        if reply is None or "result" not in reply:
            stop()
            print("mcp-tools: the server did not answer tools/list", file=sys.stderr)
            return 1
        tools.extend(reply["result"].get("tools", []))
        cursor = reply["result"].get("nextCursor")
        if not cursor:
            break
    stop()
    for tool in tools:
        if with_args:
            for argument in tool.get("inputSchema", {}).get("properties", {}):
                print(tool["name"], argument)
        else:
            print(tool["name"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
