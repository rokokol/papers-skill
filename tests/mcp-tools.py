#!/usr/bin/env python3
"""Print the tool names a stdio MCP server advertises, one per line.

Usage: mcp-tools.py SERVER_COMMAND [ARG...]

Speaks the JSON-RPC handshake the MCP protocol requires (initialize, the initialized
notification, tools/list) over the server's stdin and stdout, and prints the names in the
order the server lists them. The server's log lines on stderr are dropped; a stdout line
that is not JSON is skipped, since some servers print a banner before speaking the protocol.
Exit 1 when the server never answers tools/list, so a caller reading an empty list is told.
"""

import json
import subprocess
import sys


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print((__doc__ or "").strip(), file=sys.stderr)
        return 2
    proc = subprocess.Popen(
        argv[1:],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    stdin, stdout = proc.stdin, proc.stdout
    assert stdin is not None and stdout is not None

    def send(message: dict) -> None:
        stdin.write(json.dumps(message) + "\n")
        stdin.flush()

    def receive() -> dict | None:
        while True:
            line = stdout.readline()
            if not line:
                return None
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue

    send(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "mcp-tools", "version": "0"},
            },
        }
    )
    if receive() is None:
        print("mcp-tools: the server did not answer initialize", file=sys.stderr)
        return 1
    send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    reply = receive()
    stdin.close()
    proc.wait(timeout=30)
    if reply is None or "result" not in reply:
        print("mcp-tools: the server did not answer tools/list", file=sys.stderr)
        return 1
    for tool in reply["result"]["tools"]:
        print(tool["name"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
