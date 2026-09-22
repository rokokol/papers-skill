#!/usr/bin/env bash
# The gate for this repository: lint what it ships, hold the skill to the family's shape,
# and tie the documents to the packaged server, so a tool or a source the skill names is one
# the server actually has. Each check is proven able to fail on a planted defect: a check
# that has never been red is a decoration.
#
# What this gate cannot cover is the skill's behaviour in a conversation — which mode it
# picks, what a reading subagent returns — because that is done by a model, and a test that
# calls a model costs money and passes by chance. Those rules live in SKILL.md's "Before the
# report" list and are held by reading the digests.
#
# Nothing here touches the network: the server is started from the flake's package and asked
# what it offers, which it answers without a request. Needs: actionlint, shellcheck, shfmt,
# jq, python3 and the packaged paper-search-mcp — from the flake's dev shell, never from
# PATH's luck.
#
#   nix develop -c ./check.sh
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

# One source of truth for what gets linted. A second copy of this list drifts, and a
# drifted list lies about what was checked.
scripts=(check.sh check-skill.sh check-pins.sh check-changelog.sh check-interface.sh vendor-sync.sh)
docs=(SKILL.md README.md references/*.md)
skill_name=papers

fail() {
  echo "check: $1" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

missing=()
for tool in actionlint shellcheck shfmt jq python3 paper-search paper-search-mcp; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
((${#missing[@]} == 0)) ||
  fail "missing: ${missing[*]} — they are pinned in the flake, so run this as: nix develop -c ./check.sh"

echo "== the scripts parse and lint"
for s in "${scripts[@]}"; do bash -n "$s"; done
shellcheck "${scripts[@]}"
shfmt -d -i 2 -ci "${scripts[@]}"
python3 -m py_compile tests/mcp-tools.py tools/*.py

echo "== the Nix this repository holds is formatted"
# A `formatter` output nothing runs is a declaration, not a rule. nixfmt rather than
# `nix fmt`, because the second needs the flake and this is the binary the wrapper calls.
# find rather than a glob: a .nix file under nix/ is as much this repository's as flake.nix,
# and a glob that misses one reads as a clean run.
# find rather than git ls-files, because a gate that runs on a copy carrying no .git would
# then see an empty list, which reads the same way
nixfiles=()
while IFS= read -r f; do nixfiles+=("$f"); done < <(find . -name '*.nix' -type f -not -path '*/.git/*')
((${#nixfiles[@]})) || fail "no .nix file is tracked here, yet the flake declares a formatter"
nixfmt --check "${nixfiles[@]}" ||
  fail "a .nix file here is not what nixfmt writes — run nix fmt"

echo "== the workflows are valid, and their tools come from the lock rather than a registry"
[[ -d .github/workflows ]] || fail ".github/workflows is missing — nothing gates this repository"
actionlint
# The pin guard, vendored from the ci skill: it proves on every run that it catches each
# unpinned shape and stays quiet on the pinned spellings, then scans the workflows
./check-pins.sh

echo "== the vendored copies are still the blobs their lock lines record"
./vendor-sync.sh check

echo "== SKILL.md loads, every reference is reachable, and every link and anchor resolves"
# The one gate every skill repository shares, vendored from the ci skill. It plants a
# defect per check on every run, so nothing here has to prove it separately
./check-skill.sh -n "$skill_name" .

echo "== the changelog obeys the versioning skill's rules"
# Pinned: without -t a changelog moved wholesale to another template stays green, which is
# the versioning skill's PITFALLS.md
./check-changelog.sh -n -t '## {date}' CHANGELOG.md

echo "== the skill fits in what an agent loads"
# SKILL.md is the routing layer; the references are where length belongs. Counted in words:
# paragraphs are never hard-wrapped, so a line count measures nothing
max_words=2500
too_long() { # too_long FILE -> 0 when FILE is over the budget
  (($(wc -w <"$1") > max_words))
}
if too_long SKILL.md; then
  fail "SKILL.md is $(wc -w <SKILL.md | tr -d ' ') words — over $max_words, move the detail into references/"
fi
# And the budget is awake: one word over it is caught
awk -v n="$max_words" 'BEGIN { for (i = 0; i <= n; i++) printf "word "; print "" }' >"$work/long.md"
too_long "$work/long.md" ||
  fail "the length budget passed a document over it — the check measures nothing"

echo "== every MCP tool and argument the documents name is one the packaged server advertises"
# The documents tell a subagent which tools to call, and with which arguments. A name the
# server does not have sends the subagent to WebFetch in silence, which is the failure the
# skill exists to prevent, and a renamed argument breaks every call while the name still
# matches; so both are held to the server itself rather than to a list kept here. The
# declared list is the server's own answer, a tool per line and a "tool argument" pair per
# argument, since an argument means something only beside its tool
python3 tests/mcp-tools.py paper-search-mcp | sort -u >"$work/tools.txt"
[[ -s "$work/tools.txt" ]] || fail "the server advertised no tools"
python3 tests/mcp-tools.py --args paper-search-mcp >"$work/args.txt"
[[ -s "$work/args.txt" ]] || fail "the server advertised no tool arguments"
sort -u "$work/tools.txt" "$work/args.txt" >"$work/declared.txt"
# The ci skill's check-interface.sh, vendored. The claims it reads: an MCP name anywhere,
# since no sentence says mcp__paper-search__ in passing; call notation; and a span that is
# wholly a tool name. A placeholder such as read_<source>_paper or read_SOURCE_paper stands
# for every read tool, and each must take the argument. It plants its own defects on every
# run, in documents built from this same list. A wrong name shown on purpose is excused in
# check-interface.allow, which no agent loads
./check-interface.sh -d "$work/declared.txt" -x check-interface.allow -p mcp__paper-search__ -a -c \
  -s '(search|read|download|get)_[A-Za-z_<>]+' "${docs[@]}"

echo "== every source the documents route to is one the CLI lists, and has a read tool"
paper-search sources 2>/dev/null | jq -r '.sources[]' | sort -u >"$work/sources.txt"
[[ -s "$work/sources.txt" ]] || fail "the CLI listed no sources"
sort -u "$work/sources.txt" "$work/tools.txt" >"$work/known.txt"
# The routing columns of references/sources.md — Primary and Secondary of the area table,
# Source of the identifier table — hold sources in backticks, and here and there a tool,
# such as search_papers for a bare title. Every word there must be one or the other: the
# words are taken from the columns rather than filtered by the CLI's list, which is what let
# a made-up source through before
routed() { # routed FILE -> the backticked words in its routing columns
  # shellcheck disable=SC2016 # the backticks are the documents' own markdown, not a subshell
  awk -F '|' '/^\| Area \|/ { t = 1; next } /^\| The user gives \|/ { t = 2; next }
    !/^\|/ { t = 0 } /^\|---/ { next } t == 1 { print $3, $4 } t == 2 { print $3 }' "$1" |
    grep -oE '`[a-z_]+`' | tr -d '`' | sort -u
}
routed references/sources.md >"$work/routed.txt"
[[ -s "$work/routed.txt" ]] || fail "no routing column was read from references/sources.md — its tables moved"
unknown=$(comm -23 "$work/routed.txt" "$work/known.txt")
[[ -z "$unknown" ]] || fail "references/sources.md routes to what the CLI and the server do not have: $(tr '\n' ' ' <<<"$unknown")"
# And the check is awake: a routing table naming a made-up source beside a real one is caught
printf "| Area | Primary | Secondary | Notes |\n|---|---|---|---|\n| x | \`nowhere\`, \`arxiv\` | \`openalex\` | n |\n" >"$work/bad-source.md"
[[ "$(routed "$work/bad-source.md" | comm -23 - "$work/known.txt")" == nowhere ]] ||
  fail "a routing table naming the made-up source nowhere passed the source check — it compares nothing"
# A subagent reads with read_SOURCE_paper, and the reader prompt's SOURCE row lists the
# values it may take; each must have a read tool. The row, not a list kept here, is the
# source of that set, so a value added to it is checked the day it is added
read_sources() { # read_sources FILE -> the lowercase values its SOURCE row offers
  # shellcheck disable=SC2016 # the backticks are the documents' own markdown, not a subshell
  grep -E '^\| `SOURCE` \|' "$1" | grep -oE '`[a-z]+`' | tr -d '`' | sort -u
}
read_sources references/reader.md >"$work/read-sources.txt"
[[ -s "$work/read-sources.txt" ]] || fail "references/reader.md offers no SOURCE value — its table moved"
while read -r source; do
  grep -qx "read_${source}_paper" "$work/tools.txt" ||
    fail "references/reader.md offers SOURCE $source, but the server has no read_${source}_paper"
done <"$work/read-sources.txt"
# And that check is awake: a SOURCE row offering a source with no read tool is caught
printf "| \`SOURCE\` | one of \`arxiv\`, \`nowhere\` |\n" >"$work/bad-read.md"
read_sources "$work/bad-read.md" >"$work/bad-read-sources.txt"
missing_read=$(while read -r source; do grep -qx "read_${source}_paper" "$work/tools.txt" || echo "$source"; done <"$work/bad-read-sources.txt")
[[ "$missing_read" == nowhere ]] || fail "a SOURCE row offering nowhere passed the read-tool check — it compares nothing"

echo "check: green"
