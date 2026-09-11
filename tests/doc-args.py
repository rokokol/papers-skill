#!/usr/bin/env python3
"""Check the argument names the documents give MCP tools against the server's own.

Usage: doc-args.py ARGS_FILE DOC...

ARGS_FILE holds "tool argument" lines, as `mcp-tools.py --args` prints them. A document
gives a tool arguments in one of two shapes: call notation in backticks, where "…" stands
for arguments left out (`search_arxiv(…, sort_by)`), and the reader prompt's
"mcp__paper-search__TOOL with name VALUE, name VALUE", where the value is an upper-case
placeholder. A tool name may carry a placeholder, <source> or SOURCE, which stands for
every tool the name fits, and each of those must take the argument.

Prints one line per claim the server contradicts and exits 1 when there is any. Exits 2
when the documents make no claim at all, so a parser that stopped matching is not read as
agreement.
"""

import re
import sys
from collections import defaultdict

CALL = re.compile(r"`([A-Za-z_<>]+)\(([^)`]*)\)`")
# The clause ends at a full stop, a semicolon or the line's end: the prompt goes on to
# "then open the PDF", which would otherwise read as an argument called "the"
PROMPT = re.compile(r"mcp__paper-search__([A-Za-z_]+) with ([^.;\n]*)")
PROMPT_ARGUMENT = re.compile(r"\b([a-z][a-z_]*) [A-Z][A-Z_]+\b")
PLACEHOLDER = re.compile(r"<source>|SOURCE")
LEFT_OUT = {"…", "..."}


def tools_fitting(name: str, known: dict[str, set[str]]) -> list[str]:
    pattern = re.compile("[a-z]+".join(map(re.escape, PLACEHOLDER.split(name))) + r"\Z")
    return sorted(tool for tool in known if pattern.match(tool))


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print((__doc__ or "").strip(), file=sys.stderr)
        return 2
    known: dict[str, set[str]] = defaultdict(set)
    with open(argv[1], encoding="utf-8") as lines:
        for line in lines:
            tool, argument = line.split()
            known[tool].add(argument)

    claims: list[tuple[str, str, str]] = []
    for doc in argv[2:]:
        with open(doc, encoding="utf-8") as file:
            text = file.read()
        for name, arguments in CALL.findall(text):
            for argument in arguments.split(","):
                argument = argument.split("=")[0].strip()
                if argument and argument not in LEFT_OUT:
                    claims.append((doc, name, argument))
        for name, clause in PROMPT.findall(text):
            claims.extend((doc, name, argument) for argument in PROMPT_ARGUMENT.findall(clause))
    if not claims:
        print("doc-args: the documents give no tool any argument", file=sys.stderr)
        return 2

    contradictions = set()
    for doc, name, argument in claims:
        tools = tools_fitting(name, known)
        if not tools:
            contradictions.add(f"{doc}: {name} is no tool the server has")
        for tool in tools:
            if argument not in known[tool]:
                contradictions.add(f"{doc}: {tool} takes no argument {argument}")
    for line in sorted(contradictions):
        print(line)
    return 1 if contradictions else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
