#!/usr/bin/env bash
# Needs bash 3.2 and POSIX tools only, so it runs on a macOS runner unchanged. Taken from
# https://github.com/rokokol/skill-authoring-skill through the vendoring cascade
# (references/bump-cascade.md in https://github.com/rokokol/ci-skill): a copy is never
# edited in place, a fix is made there. What it accepts is usage() below, and nowhere else
set -euo pipefail

usage() {
  cat <<'EOF'
The gate a skill repository needs, in one file that travels. It proves that SKILL.md is
loadable at all, that every file under references/ is reachable from SKILL.md by
following links, and that every relative link and heading anchor in the docs resolves —
then proves each of those checks able to fail, on throwaway copies of the repository
with one planted defect each, every time it runs. A check that has never been red is a
decoration, and a copy of this file is falsified in its own repository on every run. It
has no repo-specific part, and belongs in a repository's own gate

  check-skill.sh [--strict] [-n NAME] [DIR]

DIR is the skill's repository (default: the current directory). -n NAME is what the
readme and the install symlink call the skill, which the frontmatter must agree with
Nothing here reaches the network
Exit 1 with `check-skill: <what>` on the first finding, 2 on a usage error

Two tiers. An error is what stops a skill loading or leaves a reference unread, and it
is the first finding: exit 1, the message on stderr. A warning is a rule of the family
the skill breaks without breaking: `check-skill: warning: FILE:LINE: ID: what` on
stdout, the exit code unchanged, and under GITHUB_ACTIONS a ::warning annotation as
well. --strict turns every warning into a finding: the lines go to stderr too and the
run exits 1 after the scan

A line that is right for a reason is excused in check-skill.allow beside SKILL.md, a
file no agent loads: one entry per line, `ID PATH [TEXT]`, excusing warnings of ID in
PATH, or only those on lines that contain TEXT when it is given; `#` opens a comment.
An entry that excuses nothing is an error, like a malformed one: left in place, it
would silently excuse the next real violation that lands on that path

CHECK_SKILL_NESTED=1 skips the self-falsification and runs only the checks. The planted
copies are run that way, and so should a gate that runs this script inside copies of its
own repository or calls it more than once in one run. The first call of every run keeps
it: the defects are planted into a copy of the repository being checked, so what it
proves changes with that repository

The warnings, by the id each line carries:
  layout-section     a Layout heading in SKILL.md or a reference: readme content,
                     loaded on every request
  install-section    an Install, Installation, Setup or Checkout heading in SKILL.md
  history-wording    used to, previously, formerly: a rule is written as acting
  pseudo-citation    a path/to/file.ext:NN citation into a checkout the reader may lack
  discovery-date     a date beside found, fixed, decided…: when a defect was found
                     bounds nothing
  cross-skill-link   a runtime link to another skill's repository, or outside this one
  harness-file       CLAUDE.md, GEMINI.md or .cursorrules named alone, without
                     AGENTS.md beside it
  prompt-idiom       MUST or CRITICAL in capitals, IMPORTANT:, take a deep breath,
                     comprehensive, Red Flags
  model-id           a concrete model id where an example should say <model>
  recheck-instruction  double-check, verify your work, a reviewing agent as a step: a
                     review happens when the user asks, not on the skill's say-so
  unverified-source  a fetch-failure note beside a claim
  trigger-duplicate  a trigger listed twice in the description
  readme-badge       the readme's badge row does not open with the Agent Skill badge
  harness-badge      the readme carries a harness badge, claiming a dependency
EOF
}

self=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")
want_name=""
strict=""
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
    --strict)
      strict=1
      shift
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
# <<< rather than a pipe even here, where `head` writes its line and leaves nothing to
# kill: the rule holds for every reader that stops early, and a checker that spells its
# own exception is a checker nobody can hold to it
grep -qx -- '---' <<<"$(head -n 1 SKILL.md)" || fail "SKILL.md does not open with a frontmatter block"
front=$(sed -n '2,/^---$/p' SKILL.md)
[[ "$(printf '%s\n' "$front" | tail -n 1)" == "---" ]] ||
  fail "SKILL.md's frontmatter is never closed by a second ---"
front=$(printf '%s\n' "$front" | sed '$d')

front_value() { # front_value KEY -> the scalar, quotes stripped, a block scalar joined
  # <<< and not a printf into the pipe: the program below exits as soon as it has the
  # value, and a producer whose reader stops early dies of SIGPIPE, which pipefail then
  # makes the status of a pipeline that did its job
  awk -v key="$1" -v q="'" '
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
    }' <<<"$front"
}

for key in name description license; do
  # <<< rather than a pipe: `grep -q` closes the pipe at its match and the producer's next
  # write dies of SIGPIPE, which pipefail makes the status of a pipeline that succeeded
  grep -q "^$key:" <<<"$front" ||
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

# links_in DOC [numbered] -> one link target per line; code fences and spans are not links.
# Numbered, each line is "LINE<TAB>target"
links_in() {
  awk -v q="'" -v numbered="${2:-}" '
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)
      while (match(line, /\]\([^)]*\)/)) {
        t = substr(line, RSTART + 2, RLENGTH - 3)
        sub("[ \t]+[\"" q "].*$", "", t)
        sub(/^</, "", t); sub(/>$/, "", t)
        print (numbered ? NR "\t" : "") t
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$1"
}

# resolve DOC TARGET -> the target's path relative to the repository root, normalized;
# empty for an external URL, absolute for a file outside the repository
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
runtime=(SKILL.md) # what an agent loads: SKILL.md and the references
if [[ -d references ]]; then
  while IFS= read -r f; do runtime+=("$f"); done < <(find references -type f -name '*.md' | sort)
fi
docs=(SKILL.md)
for f in README.md CHANGELOG.md; do
  if [[ -f "$f" ]]; then docs+=("$f"); fi
done
for f in "${runtime[@]}"; do
  [[ "$f" == SKILL.md ]] || docs+=("$f")
done
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
    # Into a variable first: piped straight into grep -q, the awk writing the anchors is
    # killed by SIGPIPE when grep stops reading at the match, and under pipefail that reads
    # as a heading that does not exist
    anchors=$(anchors_of "$path")
    grep -qxF -- "$anchor" <<<"$anchors" ||
      fail "$doc links to #$anchor in $path, where no heading has that anchor"
  done < <(links_in "$doc")
done

# ---- the rules a skill can break without breaking ---------------------------------------
# None of these stops a skill loading, so none is an error: a consumer's gate stays green
# and the line is pointed at. Each is a heuristic over prose, and a line that is right for
# a reason is excused in check-skill.allow rather than by weakening the pattern. The
# excuses live in their own file because a marker on the line itself would be loaded by
# the agent with the rest of the runtime, and would cost every request the tokens the
# rule exists to save.

allow_id=()
allow_path=()
allow_text=()
allow_line=()
allow_used=()
if [[ -f check-skill.allow ]]; then
  k=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    k=$((k + 1))
    case "$line" in '' | '#'*) continue ;; esac
    read -r id path text <<<"$line"
    [[ -n "$id" && -n "$path" ]] || fail "check-skill.allow:$k: expected ID PATH [TEXT], got: $line"
    allow_id+=("$id")
    allow_path+=("$path")
    allow_text+=("$text")
    allow_line+=("$k")
    allow_used+=("")
  done <check-skill.allow
fi

excused() { # excused FILE LINE ID -> 0 when an entry covers it, and that entry is marked used
  local k text
  for ((k = 0; k < ${#allow_id[@]}; k++)); do
    [[ "${allow_id[$k]}" == "$3" && "${allow_path[$k]}" == "$1" ]] || continue
    if [[ -n "${allow_text[$k]}" ]]; then
      text=$(sed -n "${2}p" "$1")
      [[ "$text" == *"${allow_text[$k]}"* ]] || continue
    fi
    allow_used[k]=1
    return 0
  done
  return 1
}

nwarn=0
# A warning is human text and still goes to stdout, not stderr: the gates that run this
# script on a copy with a planted defect read the first stderr line as the reason the copy
# failed, and a warning there would be taken for it. DEVIATIONS.md in
# https://github.com/rokokol/skill-authoring-skill holds the reasoning
warn() { # warn FILE LINE ID WHAT
  ! excused "$1" "$2" "$3" || return 0
  nwarn=$((nwarn + 1))
  printf 'check-skill: warning: %s:%s: %s: %s\n' "$1" "$2" "$3" "$4"
  [[ -z "${GITHUB_ACTIONS:-}" ]] || printf '::warning file=%s,line=%s::%s: %s\n' "$1" "$2" "$3" "$4"
  [[ -z "$strict" ]] || printf 'check-skill: %s:%s: %s: %s\n' "$1" "$2" "$3" "$4" >&2
}

# lines_of FILE SPANS FENCES -> "LINE<TAB>text" for every line a warning may read: the
# frontmatter dropped, code spans stripped when SPANS is 1 and links with them when it is
# 2, fenced blocks kept only when FENCES is 1. A phrase inside backticks is mentioned, not
# used, and a phrase inside a link is somebody else's title
lines_of() {
  awk -v spans="$2" -v fences="$3" '
    NR == 1 && /^---$/ { front = 1; next }
    front { if (/^---$/) front = 0; next }
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence && !fences { next }
    {
      line = $0
      if (spans) gsub(/`[^`]*`/, "", line)
      if (spans == 2) gsub(/\[[^]]*\]\([^)]*\)/, "", line)
      print NR "\t" line
    }
  ' "$1"
}

# scan ID FILE SPANS FENCES LOWER RE UNLESS WHAT -> one warning per line of FILE whose
# text matches RE (lowercased first when LOWER is 1) and not UNLESS. RE is an awk regex
# handed over as a string, so a literal dot is [.] rather than an escape, which awk would
# eat on the way in
scan() {
  local id="$1" f="$2" n
  [[ -f "$f" ]] || return 0
  while IFS= read -r n; do
    warn "$f" "$n" "$id" "$8"
  done < <(lines_of "$f" "$3" "$4" | awk -v lower="$5" -v re="$6" -v unless="$7" '
    {
      t = substr($0, index($0, "\t") + 1)
      if (lower) t = tolower(t)
      if (t ~ re && (unless == "" || t !~ unless)) print substr($0, 1, index($0, "\t") - 1)
    }')
}

why() { # why ID -> what the warning of that id tells the reader
  case "$1" in
    layout-section) echo 'a Layout section lists files a person navigates; it is readme content, loaded on every request' ;;
    history-wording) echo 'a rule is written as acting; what it replaced belongs to git and the changelog' ;;
    pseudo-citation) echo 'a path:line citation assumes a checkout the reader may not have and a line that drifts' ;;
    discovery-date) echo 'a date that says when a defect was found bounds nothing; keep only a date that bounds a measurement' ;;
    harness-file) echo "one harness's file named as the rule; name the class, the agent's instructions (CLAUDE.md, AGENTS.md…)" ;;
    prompt-idiom) echo 'an idiom of old prompts; emphasis is used once and carries its reason' ;;
    model-id) echo 'a concrete model id is copied verbatim; an example says <model>' ;;
    unverified-source) echo 'a fetch-failure note beside a claim says the claim was not checked; verify it or remove it' ;;
    recheck-instruction) echo 'the model verifies as it works; a review by another agent happens when the user asks for one' ;;
  esac
}

# The rules over prose, all of them in one awk pass per document: a process per rule and
# document multiplied by every planted copy was most of what a run cost. Each rule reads
# the raw line, the line without code spans (1), or without spans and links (2); fenced
# lines only when it says so; lowercased when it says so; and matches RE but not UNLESS.
# The regexes are awk string literals, so a literal dot is [.] rather than an escape
# shellcheck disable=SC2016 # the backticks are markdown code spans inside an awk program
prose_rules='
  function r(i, s, f, l, e, u) { n++; id[n] = i; sp[n] = s; fe[n] = f; lo[n] = l; re[n] = e; un[n] = u }
  BEGIN {
    r("layout-section", 0, 0, 0, "^#+[ \t]+Layout[ \t]*$", "")
    # "is used to mean" is a purpose, not a past: the auxiliary before it tells them apart
    r("history-wording", 1, 0, 1, "(^|[^a-z0-9])(used to|previously|formerly)([^a-z0-9]|$)", "(^|[^a-z0-9])(is|are|was|were|be|been|being) used to([^a-z0-9]|$)")
    r("pseudo-citation", 0, 0, 0, "[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+[.](sh|md|yml|yaml|nix|py|ts|js|json|toml):[0-9]+", "")
    r("discovery-date", 1, 0, 1, "(found|discovered|noticed|caught|fixed|broke|decided|introduced|audited|reviewed)( on| in| at)? 20[0-9][0-9]-[01][0-9]-[0-3][0-9]", "")
    r("harness-file", 0, 0, 0, "CLAUDE[.]md|GEMINI[.]md|[.]cursorrules", "AGENTS[.]md")
    r("prompt-idiom", 1, 0, 0, "(^|[^A-Za-z0-9])(CRITICAL|MUST)([^A-Za-z0-9]|$)|IMPORTANT:", "")
    r("prompt-idiom", 2, 0, 1, "take a deep breath|red flags|comprehensive", "")
    r("model-id", 0, 1, 0, "claude-[a-z]+-[0-9]|(opus|sonnet|haiku)-[0-9]|gpt-[0-9]|gemini-[0-9]", "")
    r("unverified-source", 1, 0, 1, "fetch failed|could not (be )?fetch|canonical location", "")
    r("recheck-instruction", 1, 0, 1, "double-check|re-check|recheck|check your (own )?work|verify your (own )?(work|answer|result)|(review|check)( it| the result| the diff)? (by|with) (a |an |another )?(sub)?agent", "")
  }
  NR == 1 && /^---$/ { front = 1; next }
  front { if (/^---$/) front = 0; next }
  /^[ \t]*(```|~~~)/ { fence = !fence; next }
  {
    s0 = $0
    s1 = s0; gsub(/`[^`]*`/, "", s1)
    s2 = s1; gsub(/\[[^]]*\]\([^)]*\)/, "", s2)
    for (k = 1; k <= n; k++) {
      if (fence && !fe[k]) continue
      t = sp[k] == 2 ? s2 : (sp[k] == 1 ? s1 : s0)
      if (lo[k]) t = tolower(t)
      # one warning per id and line, where two rules share an id
      if (t ~ re[k] && (un[k] == "" || t !~ un[k]) && !(id[k] in seen)) { print NR "\t" id[k]; seen[id[k]] = 1 }
    }
    split("", seen)
  }'

for doc in "${runtime[@]}"; do
  while IFS=$'\t' read -r n id; do
    warn "$doc" "$n" "$id" "$(why "$id")"
  done < <(awk "$prose_rules" "$doc")
done
scan install-section SKILL.md 0 0 0 '^#+[ \t]+(Install|Installation|Setup|Checkout)[ \t]*$' '' \
  'install and setup are the readme'"'"'s; an agent that loaded the skill is past them'

# A link from runtime to a sibling skill is a dependency on a checkout that may not exist,
# and routing is the agent's instructions' job. The repository's own URL is not a sibling
for doc in "${runtime[@]}"; do
  while IFS=$'\t' read -r n link; do
    target="${link%%#*}"
    [[ -n "$target" ]] || continue
    case "$target" in
      http://github.com/* | https://github.com/*)
        repo="${target#*://github.com/}"
        repo="${repo#*/}"
        repo="${repo%%[/?#]*}"
        [[ "$repo" == *-skill && "$repo" != "$name-skill" && "$repo" != "$name" ]] || continue
        warn "$doc" "$n" cross-skill-link "links to $repo; runtime never routes to a sibling skill"
        ;;
      [a-z]*://* | mailto:* | //*) ;;
      *)
        # Only a climb can leave the repository, and resolving costs a subshell per link, so
        # a target with no .. in it is taken as inside without asking
        [[ "$target" == *..* ]] || continue
        path=$(resolve "$doc" "$target")
        [[ "$path" == /* ]] || continue
        warn "$doc" "$n" cross-skill-link "$target lies outside the repository, on this machine only"
        ;;
    esac
  done < <(links_in "$doc" numbered)
done

# The triggers are matched by meaning, so the same phrase twice only costs every request
desc=$(front_value description)
triggers="${desc##*Triggers:}"
if [[ "$triggers" != "$desc" ]]; then
  # `sed -n 1s…p` rather than `| head -n 1 |`, which stops reading and kills the grep
  dline=$(grep -n '^description:' SKILL.md | sed -n '1s/:.*//p')
  # Bytes, not the locale's collation: macOS's uniq compares in it, and there every
  # Cyrillic trigger collates equal to every other of the same word count — PITFALLS.md
  while IFS= read -r dup; do
    [[ -n "$dup" ]] || continue
    warn SKILL.md "$dline" trigger-duplicate "'$dup' is listed twice"
  done < <(printf '%s\n' "$triggers" | tr ',' '\n' | sed 's/^[ \t]*//; s/[ \t.]*$//' |
    LC_ALL=C tr '[:upper:]' '[:lower:]' | grep -v '^$' | LC_ALL=C sort | LC_ALL=C uniq -d)
fi

# The readme's badge row says what the skill depends on. It opens with the Agent Skill
# badge, since the format is the open standard every harness reads, and a harness badge
# beside it claims a dependency the skill does not have
if [[ -f README.md ]]; then
  # No early exit in the reader: it would leave lines_of writing into a closed pipe, and
  # under pipefail that SIGPIPE would end the run without a word
  first=$(lines_of README.md 0 0 | awk '
    { t = substr($0, index($0, "\t") + 1) }
    !found && t ~ /^[[]?![[]/ { print; found = 1 }')
  if [[ -n "$first" && "${first#*	}" != *img.shields.io/badge/Agent_Skill* ]]; then
    n="${first%%	*}"
    warn README.md "$n" readme-badge 'the badge row does not open with the Agent Skill badge'
  fi
  scan harness-badge README.md 0 0 0 'badge/Claude_Code|badge/Claude%20Code|badge/Codex|badge/Gemini' '' \
    'a harness badge claims a dependency; a skill is a directory with a SKILL.md, read by any harness'
fi

# An excuse that excuses nothing is a rule switched off in advance: the next real violation
# of that id on that path would be swallowed without a word. So it is an error, not one
# more warning, and the file is held to the warnings it actually prevents
for ((k = 0; k < ${#allow_id[@]}; k++)); do
  [[ -n "${allow_used[$k]}" ]] ||
    fail "check-skill.allow:${allow_line[$k]}: the entry for ${allow_id[$k]} in ${allow_path[$k]} excuses nothing — remove it"
done

if [[ -n "$strict" && "$nwarn" -gt 0 ]]; then
  fail "$nwarn warning(s) under --strict — fix each line or excuse it in check-skill.allow"
fi

# ---- every check above is able to fail ----------------------------------------------
# On a copy of the repository with one defect planted, this same script must go red, and
# for that defect's own reason: a gate whose findings all come from one over-broad branch
# reads as thorough while testing one thing. A warning is proven the same way, by a plant
# that must produce it and the same plant excused that must not. A nested run skips this
# section, so the copies are checked once each rather than recursively.

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

# A warning leaves the exit code alone and stderr empty; the plant's own line must be
# named. The copy's other warnings, if the repository has any, are not this test's concern
expect_warn() { # expect_warn COPY FRAGMENT WHAT
  local c="$1" want="$2" what="$3" out
  out=$(nested "$c" "${nargs[@]+"${nargs[@]}"}" 2>"$work/stderr") ||
    fail "a copy with $what was rejected, where only a warning was due: $(cat "$work/stderr")"
  [[ ! -s "$work/stderr" ]] ||
    fail "a copy with $what wrote to stderr without --strict: $(cat "$work/stderr")"
  case "$out" in
    *"warning: $want"*) ;;
    *) fail "a copy with $what did not warn about it: $out" ;;
  esac
  planted=$((planted + 1))
}

expect_quiet() { # expect_quiet COPY FRAGMENT WHAT — the plant's line is excused, so it is not named
  local c="$1" want="$2" what="$3" out
  out=$(nested "$c" "${nargs[@]+"${nargs[@]}"}" 2>&1) ||
    fail "a copy with $what was rejected: $out"
  case "$out" in
    *"warning: $want"*) fail "a copy with $what warned although the line is excused: $out" ;;
  esac
  planted=$((planted + 1))
}

# plant COPY TEXT -> a reference holding TEXT, reached from SKILL.md, and its path in the copy
plant() {
  local c="$1"
  mkdir -p "$c/references"
  printf '%s\n' "$2" >"$c/references/zz-planted.md"
  printf '\n[planted](references/zz-planted.md)\n' >>"$c/SKILL.md"
  printf 'references/zz-planted.md'
}

# append COPY TEXT -> TEXT appended to the copy's SKILL.md, and the line it landed on
append() {
  printf '\n%s\n' "$2" >>"$1/SKILL.md"
  wc -l <"$1/SKILL.md" | tr -d ' '
}

# excuse COPY ENTRY... -> the copy's check-skill.allow holding exactly these entries
excuse() {
  local c="$1"
  shift
  printf '%s\n' "$@" >"$c/check-skill.allow"
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

# The warnings: each plant must be named on its own line, and the same plant excused must
# not be. Plants that a heading or the description carries land in SKILL.md, the rest in
# a reference reached from it, so a plant never trips the reachability error instead
c=$(copy layout)
n=$(append "$c" '## Layout')
expect_warn "$c" "SKILL.md:$n: layout-section" "a Layout section"
c=$(copy layout-strict)
append "$c" '## Layout' >/dev/null
expect_red "$c" "under --strict" "a warning under --strict" --strict "${nargs[@]+"${nargs[@]}"}"
c=$(copy layout-excused)
n=$(append "$c" '## Layout')
excuse "$c" 'layout-section SKILL.md'
expect_quiet "$c" "SKILL.md:$n: layout-section" "an excused Layout section"

c=$(copy install)
n=$(append "$c" '## Install')
expect_warn "$c" "SKILL.md:$n: install-section" "an Install section"
c=$(copy install-excused)
n=$(append "$c" '## Install')
excuse "$c" 'install-section SKILL.md'
expect_quiet "$c" "SKILL.md:$n: install-section" "an excused Install section"

c=$(copy history)
p=$(plant "$c" 'This gate used to exit 1 here')
expect_warn "$c" "$p:1: history-wording" "history wording"
c=$(copy history-narrowed)
p=$(plant "$c" 'This gate used to exit 1 here
That one used to exit 2 there')
excuse "$c" "history-wording $p exit 1"
expect_quiet "$c" "$p:1: history-wording" "history wording excused by its text"
expect_warn "$c" "$p:2: history-wording" "history wording the excuse's text does not reach"
c=$(copy history-mentioned)
p=$(plant "$c" "Never write \`used to\` in a rule")
expect_quiet "$c" "$p:1: history-wording" "history wording mentioned in a code span"
c=$(copy history-purpose)
p=$(plant "$c" 'The term is used to mean any of the white-space bytes')
expect_quiet "$c" "$p:1: history-wording" "a purpose that reads as a past"

c=$(copy citation)
p=$(plant "$c" 'Measured in other-repo/templates/check.sh:42, the loop exits early')
expect_warn "$c" "$p:1: pseudo-citation" "a path:line citation"
c=$(copy citation-excused)
p=$(plant "$c" 'Measured in other-repo/templates/check.sh:42, the loop exits early')
excuse "$c" "pseudo-citation $p"
expect_quiet "$c" "$p:1: pseudo-citation" "an excused path:line citation"

c=$(copy date)
p=$(plant "$c" 'The defect was found on 2026-09-01 in the weekly run')
expect_warn "$c" "$p:1: discovery-date" "a discovery date"
c=$(copy date-excused)
p=$(plant "$c" 'The defect was found on 2026-09-01 in the weekly run')
excuse "$c" "discovery-date $p"
expect_quiet "$c" "$p:1: discovery-date" "an excused discovery date"

c=$(copy sibling-link)
p=$(plant "$c" 'See the [other skill](https://github.com/example/other-skill) for the rest')
expect_warn "$c" "$p:1: cross-skill-link" "a link to a sibling skill"
c=$(copy sibling-link-excused)
p=$(plant "$c" 'See the [other skill](https://github.com/example/other-skill) for the rest')
excuse "$c" "cross-skill-link $p other-skill"
expect_quiet "$c" "$p:1: cross-skill-link" "an excused link to a sibling skill"
c=$(copy own-link)
p=$(plant "$c" "See [this repository](https://github.com/example/$name-skill) itself")
expect_quiet "$c" "$p:1: cross-skill-link" "a link to the skill's own repository"
c=$(copy outside-link)
printf '# outside\n' >"$work/outside.md"
p=$(plant "$c" 'See [a file outside](../../outside.md) the repository')
expect_warn "$c" "$p:1: cross-skill-link" "a link outside the repository"

c=$(copy harness-file)
p=$(plant "$c" 'Put the rule in CLAUDE.md')
expect_warn "$c" "$p:1: harness-file" "one harness's file as the rule"
c=$(copy harness-file-excused)
p=$(plant "$c" 'Put the rule in CLAUDE.md')
excuse "$c" "harness-file $p"
expect_quiet "$c" "$p:1: harness-file" "an excused harness file"
c=$(copy harness-class)
p=$(plant "$c" 'Put the rule in the agent'"'"'s instructions (CLAUDE.md, AGENTS.md…)')
expect_quiet "$c" "$p:1: harness-file" "a harness file named as an example of the class"

c=$(copy idiom-caps)
p=$(plant "$c" 'You MUST always run the gate')
expect_warn "$c" "$p:1: prompt-idiom" "MUST in capitals"
c=$(copy idiom-phrase)
p=$(plant "$c" 'Take a deep breath and write a comprehensive plan')
expect_warn "$c" "$p:1: prompt-idiom" "an old prompt's phrase"
c=$(copy idiom-excused)
p=$(plant "$c" 'You MUST always run the gate')
excuse "$c" "prompt-idiom $p"
expect_quiet "$c" "$p:1: prompt-idiom" "an excused idiom"
c=$(copy idiom-title)
# A relative link rather than a URL: a consumer's own secret gate may read any URL with a
# path as an address it must not leak, and the plant travels into every consumer
p=$(plant "$c" 'See [A comprehensive study of pseudo-tested methods](zz-planted.md)')
expect_quiet "$c" "$p:1: prompt-idiom" "an idiom inside a linked title"

c=$(copy model-id)
p=$(plant "$c" '```
Assisted-by: Claude Code:claude-opus-4-1
```')
expect_warn "$c" "$p:2: model-id" "a concrete model id in a fence"
c=$(copy model-id-excused)
p=$(plant "$c" '```
Assisted-by: Claude Code:claude-opus-4-1
```')
excuse "$c" "model-id $p"
expect_quiet "$c" "$p:2: model-id" "an excused model id"
c=$(copy model-placeholder)
p=$(plant "$c" '```
Assisted-by: Claude Code:<model>
```')
expect_quiet "$c" "$p:2: model-id" "a <model> placeholder"

c=$(copy recheck)
p=$(plant "$c" 'Double-check your work, then have a subagent review the result')
expect_warn "$c" "$p:1: recheck-instruction" "a re-check instruction"
c=$(copy recheck-excused)
p=$(plant "$c" 'Double-check your work, then have a subagent review the result')
excuse "$c" "recheck-instruction $p"
expect_quiet "$c" "$p:1: recheck-instruction" "an excused re-check instruction"

c=$(copy unverified)
p=$(plant "$c" 'The limit is 30 (fetch failed while writing this; the page is the canonical location)')
expect_warn "$c" "$p:1: unverified-source" "a fetch-failure note"
c=$(copy unverified-excused)
p=$(plant "$c" 'The limit is 30 (fetch failed while writing this; the page is the canonical location)')
excuse "$c" "unverified-source $p"
expect_quiet "$c" "$p:1: unverified-source" "an excused fetch-failure note"

c=$(copy trigger-twice)
sed 's/^description:.*/description: "What it is. Use when needed. Triggers: alpha, beta, Alpha."/' SKILL.md >"$c/SKILL.md"
n=$(grep -n '^description:' "$c/SKILL.md" | sed -n '1s/:.*//p')
expect_warn "$c" "SKILL.md:$n: trigger-duplicate: 'alpha'" "a trigger listed twice"
c=$(copy trigger-twice-excused)
sed 's/^description:.*/description: "What it is. Use when needed. Triggers: alpha, beta, Alpha."/' SKILL.md >"$c/SKILL.md"
excuse "$c" 'trigger-duplicate SKILL.md'
expect_quiet "$c" "SKILL.md:$n: trigger-duplicate" "an excused duplicate trigger"

c=$(copy badge-order)
printf '# a skill\n\n![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat)\n[![Agent Skill](https://img.shields.io/badge/Agent_Skill-6E56CF?style=flat)](https://agentskills.io)\n' >"$c/README.md"
expect_warn "$c" "README.md:3: readme-badge" "a badge row not opening with Agent Skill"
c=$(copy badge-first)
printf '# a skill\n\n[![Agent Skill](https://img.shields.io/badge/Agent_Skill-6E56CF?style=flat)](https://agentskills.io)\n![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat)\n' >"$c/README.md"
expect_quiet "$c" "README.md:3: readme-badge" "a badge row opening with Agent Skill"
c=$(copy harness-badge)
printf '# a skill\n\n[![Agent Skill](https://img.shields.io/badge/Agent_Skill-6E56CF?style=flat)](https://agentskills.io)\n![Claude Code](https://img.shields.io/badge/Claude_Code-D97757?style=flat)\n' >"$c/README.md"
expect_warn "$c" "README.md:4: harness-badge" "a harness badge"
c=$(copy harness-badge-excused)
printf '# a skill\n\n[![Agent Skill](https://img.shields.io/badge/Agent_Skill-6E56CF?style=flat)](https://agentskills.io)\n![Claude Code](https://img.shields.io/badge/Claude_Code-D97757?style=flat)\n' >"$c/README.md"
excuse "$c" 'harness-badge README.md'
expect_quiet "$c" "README.md:4: harness-badge" "an excused harness badge"

# The allow file is held to what it prevents: an entry nothing uses is an error, and so is
# a line that is not an entry
c=$(copy stale-excuse)
excuse "$c" '# a comment and a blank line are not entries' '' 'layout-section SKILL.md'
expect_red "$c" "check-skill.allow:3: the entry for layout-section in SKILL.md excuses nothing" \
  "an excuse that excuses nothing" "${nargs[@]+"${nargs[@]}"}"
c=$(copy broken-excuse)
excuse "$c" 'layout-section'
expect_red "$c" "expected ID PATH" "an allow entry with no path" "${nargs[@]+"${nargs[@]}"}"

echo "check-skill: SKILL.md loads as '$name', $nrefs references reachable, $nlinks links resolve, $nwarn warnings, $planted planted defects caught"
