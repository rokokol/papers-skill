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
scripts=(check.sh check-skill.sh check-pins.sh check-changelog.sh vendor-sync.sh)
docs=(SKILL.md references/sources.md references/reader.md references/digest-template.md references/profile.md)
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
python3 -m py_compile tests/mcp-tools.py

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
./check-changelog.sh -n CHANGELOG.md

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

echo "== every MCP tool the documents name is one the packaged server advertises"
# The documents tell a subagent which tools to call by name. A name the server does not
# have sends the subagent to WebFetch in silence, which is the failure the skill exists to
# prevent, so the names are checked against the server itself rather than against a list
python3 tests/mcp-tools.py paper-search-mcp | sort -u >"$work/tools.txt"
[[ -s "$work/tools.txt" ]] || fail "the server advertised no tools"
named_tools() { # named_tools FILE... -> the tool names the files call by their MCP name
  # Upper case is allowed so the reader prompt's read_SOURCE_paper placeholder is taken
  # whole and can be excluded by name, rather than truncated into a false finding
  grep -ohE 'mcp__paper-search__[A-Za-z_]+' "$@" | sed 's/^mcp__paper-search__//' | sort -u
}
named_tools "${docs[@]}" >"$work/named.txt"
[[ -s "$work/named.txt" ]] || fail "the documents name no MCP tool at all — the reader prompt lost its calls"
# The reader prompt writes read_SOURCE_paper with the source as a placeholder; every source
# that has a read tool is checked instead, in the sources check below
grep -v '^read_SOURCE_paper$' "$work/named.txt" >"$work/named-concrete.txt" || true
unknown=$(comm -23 "$work/named-concrete.txt" "$work/tools.txt")
[[ -z "$unknown" ]] || fail "the documents name tools the server does not have: $(tr '\n' ' ' <<<"$unknown")"
# And the check is awake: a document naming a tool that does not exist is caught
printf 'call mcp__paper-search__read_everything_paper first\n' >"$work/bad-tool.md"
named_tools "$work/bad-tool.md" >"$work/bad-named.txt"
[[ -n "$(comm -23 "$work/bad-named.txt" "$work/tools.txt")" ]] ||
  fail "a planted unknown tool name passed the tool check — it compares nothing"

echo "== every source the documents route to is one the CLI lists, and has a read tool"
paper-search sources 2>/dev/null | jq -r '.sources[]' | sort -u >"$work/sources.txt"
[[ -s "$work/sources.txt" ]] || fail "the CLI listed no sources"
# The routing tables name sources in backticks; scholar and the fallback connectors are
# named by the server too, so the list is the CLI's own
named_sources() { # named_sources FILE -> the backticked lowercase words that are sources
  # shellcheck disable=SC2016 # the backticks are the documents' own markdown, not a subshell
  grep -oE '`[a-z_]+`' "$1" | tr -d '`' | sort -u | comm -12 - "$work/sources.txt"
}
named_sources references/sources.md >"$work/named-sources.txt"
(($(wc -l <"$work/named-sources.txt") >= 8)) ||
  fail "references/sources.md names fewer than 8 known sources — the routing tables were lost"
# Every source the identifier table routes a read to must have a read_<source>_paper tool;
# pmc and europepmc are deliberately absent, the table sends their ids through pubmed
for source in arxiv pubmed biorxiv medrxiv semantic crossref openalex; do
  grep -qx "read_${source}_paper" "$work/tools.txt" ||
    fail "the identifier table routes reads to $source, but the server has no read_${source}_paper"
done
# And the check is awake: a routing table that names a made-up source is caught, because
# the made-up name is not in the CLI's list and so falls out of the intersection
# shellcheck disable=SC2016 # the backticks are the planted document's markdown
printf 'route it to `nowhere` and `arxiv`\n' >"$work/bad-source.md"
[[ "$(named_sources "$work/bad-source.md" | tr '\n' ' ')" == "arxiv " ]] ||
  fail "the source filter kept a source the CLI does not list — it filters nothing"

echo "check: green"
