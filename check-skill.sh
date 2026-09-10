#!/usr/bin/env bash
# The gate a skill repository needs, in one file that travels. It proves that SKILL.md is
# loadable at all, that every file under references/ is reachable from SKILL.md by
# following links, and that every relative link and heading anchor in the docs resolves —
# then proves each of those checks able to fail, on throwaway copies of the repository
# with one planted defect each, every time it runs. A check that has never been red is a
# decoration, and a copy of this file is falsified in its own repository on every run.
#
#   check-skill.sh [-n NAME] [DIR]
#
# DIR is the skill's repository (default: the current directory). -n NAME is what the
# readme and the install symlink call the skill, which the frontmatter must agree with.
# Exit 1 with `check-skill: <what>` on the first finding, 2 on a usage error.
#
# Nothing here reaches the network. Needs bash 3.2 and POSIX tools only, so it runs on a
# macOS runner unchanged. It has no repo-specific part: another repository takes it through
# the vendoring cascade (references/bump-cascade.md in https://github.com/rokokol/ci-skill),
# never edits its copy in place, and calls it from its own gate.
set -euo pipefail

# The whole header, however long it grows: up to the first line that is not a comment
usage() { sed -n '2,/^[^#]/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; }

self=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")
want_name=""
while (($#)); do
  case "$1" in
    -n)
      # Not ${2:?}: that exits 1 with bash's own message, and a usage error is exit 2
      (($# >= 2)) || {
        echo "check-skill: -n needs a name" >&2
        exit 2
      }
      want_name="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      usage >&2
      exit 2
      ;;
    *) break ;;
  esac
done
(($# <= 1)) || {
  usage >&2
  exit 2
}
root="${1:-.}"
[[ -d "$root" ]] || {
  echo "check-skill: $root is not a directory" >&2
  exit 2
}
root=$(cd -- "$root" && pwd)
cd "$root"

fail() {
  echo "check-skill: $1" >&2
  exit 1
}

# ---- SKILL.md loads at all -----------------------------------------------------------
# A skill whose frontmatter is malformed, misnamed or oversized is simply never loaded,
# and nothing says so: the agent just never reaches for it.

[[ -f SKILL.md ]] || fail "no SKILL.md in $root — there is nothing for an agent to load"
head -n 1 SKILL.md | grep -qx -- '---' || fail "SKILL.md does not open with a frontmatter block"
front=$(sed -n '2,/^---$/p' SKILL.md)
[[ "$(printf '%s\n' "$front" | tail -n 1)" == "---" ]] ||
  fail "SKILL.md's frontmatter is never closed by a second ---"
front=$(printf '%s\n' "$front" | sed '$d')

front_value() { # front_value KEY -> the scalar, quotes stripped, a block scalar joined
  printf '%s\n' "$front" | awk -v key="$1" -v q="'" '
    found { if ($0 ~ /^[ \t]+/) { sub(/^[ \t]+/, ""); out = out (out == "" ? "" : " ") $0; next } else exit }
    index($0, key ":") == 1 {
      found = 1
      v = $0; sub("^" key ":[ \t]*", "", v)
      if (v ~ /^[>|]/) next
      out = v; exit
    }
    END {
      sub(/^"/, "", out); sub(/"$/, "", out)
      if (substr(out, 1, 1) == q) out = substr(out, 2)
      if (substr(out, length(out)) == q) out = substr(out, 1, length(out) - 1)
      print out
    }'
}

for key in name description license; do
  printf '%s\n' "$front" | grep -q "^$key:" ||
    fail "SKILL.md's frontmatter has no $key — an agent will not load a skill without one"
  [[ -n "$(front_value "$key")" ]] || fail "SKILL.md's frontmatter leaves $key empty"
done
name=$(front_value name)
[[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#name} -le 64 ]] ||
  fail "'$name' is not a valid skill name — lowercase letters, digits and single hyphens, at most 64 characters"
[[ -z "$want_name" || "$name" == "$want_name" ]] ||
  fail "SKILL.md calls the skill '$name', but the readme and the symlink call it '$want_name'"
# Characters, not bytes: continuation bytes dropped, so a Cyrillic trigger word counts once
desc_chars=$(($(front_value description | LC_ALL=C tr -d '\200-\277' | wc -c) - 1))
((desc_chars <= 1024)) ||
  fail "the description is $desc_chars characters long, over the 1024 an agent will load"

# ---- links, and what they reach --------------------------------------------------------

links_in() { # links_in DOC -> one link target per line; code fences and spans are not links
  awk -v q="'" '
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)
      while (match(line, /\]\([^)]*\)/)) {
        t = substr(line, RSTART + 2, RLENGTH - 3)
        sub("[ \t]+[\"" q "].*$", "", t)
        sub(/^</, "", t); sub(/>$/, "", t)
        print t
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$1"
}

# resolve DOC TARGET -> the target's path relative to the repository root, normalized;
# empty for an external URL
resolve() {
  local doc="$1" target="$2" path
  case "$target" in
    [a-z]*://* | mailto:* | //*) return 0 ;;
    /*) path=".$target" ;;
    *) path="$(dirname -- "$doc")/$target" ;;
  esac
  if [[ -e "$path" ]]; then
    path=$(cd -- "$(dirname -- "$path")" && pwd)/$(basename -- "$path")
    path="${path#"$root/"}"
  fi
  printf '%s\n' "$path"
}

# The punctuation GitHub drops from a heading that a byte-wise tr cannot tell from a
# letter: em and en dash, guillemets, curly double and single quotes, the ellipsis
unicode_punct=$(printf '\342\200\224 \342\200\223 \302\253 \302\273 \342\200\234 \342\200\235 \342\200\230 \342\200\231 \342\200\246')

anchors_of() { # anchors_of FILE -> one GitHub-style anchor per heading, duplicates suffixed
  awk -v punct="$unicode_punct" '
    BEGIN { n = split(punct, drop, " ") }
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    /^##?#?#?#?#?([ \t]|$)/ {
      h = $0; sub(/^#+[ \t]*/, "", h); sub(/[ \t]+#+[ \t]*$/, "", h)
      for (i = 1; i <= n; i++) gsub(drop[i], "", h)
      print h
    }
  ' "$1" |
    LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cd 'a-z0-9 _\200-\377\n-' | tr ' ' '-' |
    awk '{ if (seen[$0]++) print $0 "-" seen[$0] - 1; else print }'
}

is_reached() {
  local r
  for r in "${reached[@]}"; do [[ "$r" == "$1" ]] && return 0; done
  return 1
}

# Every file under references/ must be reachable from SKILL.md by following links —
# transitively, since SKILL.md may delegate to a reference that links on. A reference
# nothing points at is never loaded, so it rots unread while reading as maintained.
# README.md and CHANGELOG.md are written for people, not loaded by an agent, so a link
# from them reaches nothing: the walk does not pass through either.
reached=(SKILL.md)
i=0
while ((i < ${#reached[@]})); do
  doc="${reached[$i]}"
  i=$((i + 1))
  [[ "$doc" == *.md && -f "$doc" ]] || continue
  case "$doc" in README.md | CHANGELOG.md) continue ;; esac
  while IFS= read -r link; do
    target="${link%%#*}"
    [[ -n "$target" ]] || continue
    path=$(resolve "$doc" "$target")
    [[ -n "$path" && -e "$path" ]] || continue # a dead link is the next section's finding
    is_reached "$path" || reached+=("$path")
  done < <(links_in "$doc")
done

nrefs=0
if [[ -d references ]]; then
  while IFS= read -r ref; do
    nrefs=$((nrefs + 1))
    is_reached "$ref" ||
      fail "$ref exists but no chain of links from SKILL.md reaches it — it will rot unread"
  done < <(find references -type f | sed 's|^\./||' | sort)
  ((nrefs > 0)) || fail "references/ is empty — delete the directory or put a reference in it"
fi

# Every relative link resolves to a file that exists, and every #anchor to a heading in it
docs=(SKILL.md)
for f in README.md CHANGELOG.md; do
  if [[ -f "$f" ]]; then docs+=("$f"); fi
done
if [[ -d references ]]; then
  while IFS= read -r f; do docs+=("$f"); done < <(find references -type f -name '*.md' | sort)
fi
nlinks=0
for doc in "${docs[@]}"; do
  while IFS= read -r link; do
    target="${link%%#*}"
    anchor="${link#*#}"
    [[ "$anchor" != "$link" ]] || anchor=""
    if [[ -n "$target" ]]; then
      path=$(resolve "$doc" "$target")
      [[ -n "$path" ]] || continue
      nlinks=$((nlinks + 1))
      [[ -e "$path" ]] || fail "$doc links to $target, which does not exist"
    else
      path="$doc"
    fi
    [[ -n "$anchor" && -f "$path" && "$path" == *.md ]] || continue
    anchors_of "$path" | grep -qxF -- "$anchor" ||
      fail "$doc links to #$anchor in $path, where no heading has that anchor"
  done < <(links_in "$doc")
done

# ---- every check above is able to fail ----------------------------------------------
# On a copy of the repository with one defect planted, this same script must go red, and
# for that defect's own reason: a gate whose findings all come from one over-broad branch
# reads as thorough while testing one thing. A nested run skips this section, so the
# copies are checked once each rather than recursively.

if [[ -n "${CHECK_SKILL_NESTED:-}" ]]; then
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
nargs=()
[[ -z "$want_name" ]] || nargs=(-n "$want_name")

copy() { # copy NAME -> the path of a fresh copy of the repository, .git left behind
  local c="$work/$1"
  mkdir -p "$c"
  tar --exclude=.git -cf - . | tar -xf - -C "$c"
  printf '%s\n' "$c"
}

nested() { # nested COPY [ARGS...] -> this script on the copy, falsification skipped
  local c="$1"
  shift
  CHECK_SKILL_NESTED=1 "$self" "$@" "$c"
}

planted=0
# The count lives here rather than beside each call, so a new planted case cannot be left
# out of the number the summary line reports
expect_red() { # expect_red COPY FRAGMENT WHAT [ARGS...]
  local c="$1" want="$2" what="$3" out
  shift 3
  if out=$(nested "$c" "$@" 2>&1); then
    fail "a copy with $what passed — the check cannot catch it"
  fi
  case "$out" in
    *"$want"*) ;;
    *) fail "a copy with $what was rejected for the wrong reason: $out" ;;
  esac
  planted=$((planted + 1))
}

c=$(copy clean)
nested "$c" "${nargs[@]+"${nargs[@]}"}" >/dev/null 2>&1 ||
  fail "a faithful copy of the repository was rejected — the copy step is broken, not the repository"

c=$(copy fenced)
# shellcheck disable=SC2016 # the backticks are a markdown fence, not a command substitution
printf '\n```\n[not a link](references/not-there.md)\n```\n' >>"$c/SKILL.md"
nested "$c" "${nargs[@]+"${nargs[@]}"}" >/dev/null 2>&1 ||
  fail "a link inside a code fence was treated as a link"

c=$(copy no-frontmatter)
printf 'no frontmatter here\n' >"$c/SKILL.md"
expect_red "$c" "does not open with a frontmatter" "no frontmatter" "${nargs[@]+"${nargs[@]}"}"

c=$(copy unclosed)
sed '1!{/^---$/d;}' SKILL.md >"$c/SKILL.md"
expect_red "$c" "never closed" "an unclosed frontmatter" "${nargs[@]+"${nargs[@]}"}"

c=$(copy no-license)
grep -v '^license:' SKILL.md >"$c/SKILL.md"
expect_red "$c" "has no license" "no license key" "${nargs[@]+"${nargs[@]}"}"

c=$(copy bad-name)
sed 's/^name:.*/name: Not_Valid/' SKILL.md >"$c/SKILL.md"
expect_red "$c" "not a valid skill name" "an invalid name" "${nargs[@]+"${nargs[@]}"}"

c=$(copy other-name)
expect_red "$c" "call it 'some-other-name'" "a name the symlink disagrees with" -n some-other-name

c=$(copy long-description)
sed "s/^description:.*/description: $(printf '%1100s' '' | tr ' ' x)/" SKILL.md >"$c/SKILL.md"
expect_red "$c" "characters long" "an oversized description" "${nargs[@]+"${nargs[@]}"}"

c=$(copy orphan)
mkdir -p "$c/references"
printf '# nothing points here\n' >"$c/references/nothing-points-here.md"
expect_red "$c" "reaches it" "a reference nothing links to" "${nargs[@]+"${nargs[@]}"}"

c=$(copy dead-link)
printf '\n[gone](references/nothing-here.md)\n' >>"$c/SKILL.md"
expect_red "$c" "does not exist" "a dead link" "${nargs[@]+"${nargs[@]}"}"

c=$(copy dead-anchor)
printf '\n[gone](#no-such-heading-anywhere)\n' >>"$c/SKILL.md"
expect_red "$c" "no heading has that anchor" "a dead anchor" "${nargs[@]+"${nargs[@]}"}"
echo "check-skill: SKILL.md loads as '$name', $nrefs references reachable, $nlinks links resolve, $planted planted defects caught"
