#!/usr/bin/env bash
# Hold a skill's documents to the interface a foreign tool declares about itself: the
# commands of a CLI as its own help lists them, the tools and arguments an MCP server
# advertises, the fields an API accepts. When the tool renames one, a document that still
# teaches the old name teaches an agent to call something that does not exist, and nothing
# in the repository notices. Then it proves each of its checks able to fail, on planted
# documents built from the same declared list, every time it runs.
#
#   check-interface.sh -d FILE [-p PREFIX]... [-a] [-b] [-c] [-s ERE] [-f] DOC...
#
#   -d FILE    what the tool declares: one name per line, or a name and one argument it
#              takes per line. A name `*` gives its arguments to every name, and an
#              argument written <like-this> is a positional value, so bare words after
#              that name are values rather than flags. How the list is made is the calling
#              gate's own line: an MCP handshake, `tool help | awk …`, a recorded snapshot
#   -p PREFIX  a claim opens with PREFIX at the start of a code span, or of a line in a
#              fenced block after an optional `$ `: `PREFIX NAME key=… flag`; repeatable
#   -a         PREFIX opens a claim anywhere in a line, prose included — for a prefix no
#              sentence uses in passing, such as the full name of an MCP tool
#   -b         a code span that opens with a declared name is a claim too; an undeclared
#              first word there is taken for prose, and so are its bare words, which may
#              be quoted output or a shell line as easily as flags, so only its `key=`
#              arguments are held
#   -c         a code span in call notation, `NAME(arg, arg=…, …)`, is a claim
#   -s ERE     a code span that is wholly a name matching ERE is a claim to that name
#   -f         a bare lowercase word after a prefixed name is an argument, as a CLI's
#              flags are
#
# An argument is read as `key=value`, as `key VALUE` where VALUE is an upper-case or
# <angled> placeholder, and with -f as a bare word after a prefix. A claim ends at a shell operator, at
# the end of its span or line, or after a word ending in `.` or `;`. A name may hold a
# placeholder, <source> or SOURCE, which stands for every declared name it fits, and each
# of those must take the argument. A line carrying `check-interface: allow` — in an HTML
# comment, where a document shows a wrong call on purpose — is not read.
#
# Exit 0 when every claim holds, 1 with one `check-interface: FILE:LINE: <what>` line per
# finding, 2 on a usage error, an unreadable file, a declared list that names nothing, or
# documents that make no claim at all, so a notation that stopped matching is not read as
# agreement. Nothing here reaches the network. Needs bash 3.2 and POSIX tools only, so it
# runs on a macOS runner unchanged. It has no repo-specific part: another repository
# takes it through the vendoring cascade (references/bump-cascade.md in
# https://github.com/rokokol/ci-skill), never edits its copy in place, and calls it from
# its own gate.
set -euo pipefail

# The whole header, however long it grows: up to the first line that is not a comment
usage() { sed -n '2,/^[^#]/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; }

die() {
  printf 'check-interface: %s\n' "$1" >&2
  exit 2
}

fail() {
  printf 'check-interface: %s\n' "$1"
  exit 1
}

self=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")
declared="" prefixes="" first_prefix="" whole=""
anywhere=0 bare=0 calls=0 flags=0
# Every notation flag again, for the runs on planted documents
opts=()
while (($#)); do
  case "$1" in
    -d)
      # Not ${2:?}: that exits 1 with bash's own message, and a usage error is exit 2
      (($# >= 2)) || die "-d needs a file"
      declared=$2
      shift 2
      ;;
    -p)
      (($# >= 2)) || die "-p needs a prefix"
      [[ -n "$2" ]] || die "-p needs a prefix that is not empty"
      prefixes="$prefixes$2"$'\n'
      [[ -n "$first_prefix" ]] || first_prefix=$2
      opts+=(-p "$2")
      shift 2
      ;;
    -a)
      anywhere=1
      opts+=(-a)
      shift
      ;;
    -b)
      bare=1
      opts+=(-b)
      shift
      ;;
    -c)
      calls=1
      opts+=(-c)
      shift
      ;;
    -s)
      (($# >= 2)) || die "-s needs a pattern"
      whole=$2
      opts+=(-s "$2")
      shift 2
      ;;
    -f)
      flags=1
      opts+=(-f)
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      usage >&2
      exit 2
      ;;
    *) break ;;
  esac
done

[[ -n "$declared" ]] || die "-d FILE is required: the interface the tool declares"
[[ -f "$declared" && -r "$declared" ]] || die "$declared is not a readable file"
(($#)) || die "no document to check"
for doc in "$@"; do
  [[ -f "$doc" && -r "$doc" ]] || die "$doc is not a readable file"
done
[[ -n "$prefixes" || $bare == 1 || $calls == 1 || -n "$whole" ]] ||
  die "no notation given: a claim is found by -p, -b, -c or -s"
[[ $anywhere == 0 || -n "$prefixes" ]] || die "-a needs a -p, the prefix it finds anywhere"
[[ $flags == 0 || -n "$prefixes" ]] || die "-f needs a -p: flags are read after a prefixed name"
nnames=$(awk 'NF && $1 != "*" && $1 !~ /^#/ { print $1 }' "$declared" | sort -u | wc -l | tr -d ' ')
((nnames > 0)) || die "$declared declares no name: an empty interface would agree with anything"

# One pass over the declared list and the documents. Prints "F<tab>FILE:LINE: what" per
# finding and "C<tab>N" for the number of claims read. POSIX awk only: no gensub and no
# arrays of arrays. A quoted heredoc in a function, not a $( ) around one, which bash 3.2
# mis-parses when the text holds an unbalanced parenthesis, as the bracket below does
awk_program() {
  cat <<'AWK'
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function finding(what) { found[FILENAME ":" FNR ": " what] = 1 }
# <angled> placeholders, and runs of two or more capitals that touch no lowercase letter,
# stand for any lowercase segment of a name; camelCase capitals stay literal
function pattern_of(name,   n, out, before, run) {
  n = name
  gsub(/<[^>]*>/, "\001", n)
  out = ""
  while (match(n, /[A-Z][A-Z0-9]+/)) {
    before = substr(n, 1, RSTART - 1)
    run = substr(n, RSTART, RLENGTH)
    n = substr(n, RSTART + RLENGTH)
    if (before ~ /[a-z]$/ || n ~ /^[a-z]/) out = out before run
    else out = out before "\001"
  }
  return out n
}
# Fills fit[1..n] with the declared names NAME stands for, and returns n
function resolve(name,   p, i, n) {
  split("", fit)
  n = 0
  p = pattern_of(name)
  if (index(p, "\001") == 0) {
    if (name in declared) fit[++n] = name
    return n
  }
  gsub(/\001/, "[a-z0-9]+", p)
  p = "^" p "$"
  for (i = 1; i <= nn; i++) if (names[i] ~ p) fit[++n] = names[i]
  return n
}
function hold(arg, n,   i) {
  for (i = 1; i <= n; i++)
    if (!((fit[i] SUBSEP arg) in takes) && !(("*" SUBSEP arg) in takes))
      finding(fit[i] " takes no " arg)
}
function any_positional(n,   i) {
  for (i = 1; i <= n; i++) if (fit[i] in positional) return 1
  return 0
}
function is_placeholder(t) {
  sub(/[,.;]+$/, "", t)
  return t ~ /^([A-Z][A-Z0-9_]*|<[^>]*>|\.\.\.)$/ || t == "…"
}
function claim(text, strict,   name, rest, n, args, na, a, toks, nt, i, t, last) {
  if (!match(text, /^[A-Za-z0-9_:<>-]+/)) return
  name = substr(text, 1, RLENGTH)
  rest = substr(text, RLENGTH + 1)
  n = resolve(name)
  if (n == 0) {
    if (strict) {
      claims++
      if (index(pattern_of(name), "\001")) finding(name " fits no declared name")
      else finding(name " is not a declared name")
    }
    return
  }
  claims++
  if (rest ~ /^\(/) {
    rest = substr(rest, 2)
    i = index(rest, ")")
    if (i) rest = substr(rest, 1, i - 1)
    na = split(rest, args, ",")
    for (i = 1; i <= na; i++) {
      a = trim(args[i])
      sub(/[=:].*/, "", a)
      a = trim(a)
      if (a ~ /^[a-z_][A-Za-z0-9_]*$/) hold(a, n)
    }
    return
  }
  if (rest !~ /^[ \t]/) return
  # A quoted value becomes a byte no rule below reads: not a word, so not a flag, and not
  # a capital, so not a placeholder that would make the word before it an argument
  gsub(/"[^"]*"/, "\001", rest)
  gsub(sq "[^" sq "]*" sq, "\001", rest)
  nt = split(trim(rest), toks, /[ \t]+/)
  for (i = 1; i <= nt; i++) {
    t = toks[i]
    if (t ~ /^([|&;<>(){}#]|[0-9]+>)/) break
    last = t ~ /[.;]$/
    sub(/[,.;]+$/, "", t)
    if (t ~ /^[a-z][A-Za-z0-9_-]*=/) {
      sub(/=.*/, "", t)
      hold(t, n)
    } else if (t ~ /^[a-z][A-Za-z0-9_]*$/ && i < nt && is_placeholder(toks[i + 1])) {
      hold(t, n)
      i++
      last = toks[i] ~ /[.;]$/
    } else if (flags && strict && t ~ /^[a-z][a-z0-9_-]*$/ && !any_positional(n)) {
      hold(t, n)
    }
    if (last) break
  }
}
# A code span or a fenced line: a claim can only open it
function opening(s, fenced,   i, p) {
  for (i = 1; i <= np; i++) {
    p = pre[i]
    if (p != "" && substr(s, 1, length(p)) == p) {
      claim(substr(s, length(p) + 1), 1)
      return
    }
  }
  if (fenced) return
  if (calls && s ~ /^[A-Za-z0-9_:<>-]+\(/) {
    claim(s, 1)
    return
  }
  if (whole != "" && s ~ ("^(" whole ")$")) {
    claim(s, 1)
    return
  }
  if (bare && match(s, /^[A-Za-z0-9_:-]+/) && (substr(s, 1, RLENGTH) in declared)) claim(s, 0)
}
# Anywhere in a line, for -a: the prefix must not continue a longer word
function inside(s,   i, p, k, rest) {
  for (i = 1; i <= np; i++) {
    p = pre[i]
    if (p == "") continue
    rest = s
    while ((k = index(rest, p)) > 0) {
      if (k == 1 || substr(rest, k - 1, 1) !~ /[A-Za-z0-9_]/) claim(substr(rest, k + length(p)), 1)
      rest = substr(rest, k + length(p))
    }
  }
}
BEGIN {
  sq = sprintf("%c", 39)
  np = split(ENVIRON["CHECK_INTERFACE_PREFIXES"], pre, "\n")
  whole = ENVIRON["CHECK_INTERFACE_WHOLE"]
  claims = 0
}
FNR == NR {
  if (NF == 0 || $1 ~ /^#/) next
  if (!($1 in declared) && $1 != "*") names[++nn] = $1
  declared[$1] = 1
  if (NF >= 2) {
    takes[$1 SUBSEP $2] = 1
    if ($2 ~ /^</) positional[$1] = 1
  }
  next
}
FNR == 1 { fence = 0 }
/^[ \t]*(```|~~~)/ { fence = !fence; next }
/check-interface: allow/ { next }
fence {
  line = $0
  sub(/^[ \t]*(\$[ \t]+)?/, "", line)
  opening(line, 1)
  if (anywhere) inside(line)
  next
}
{
  rest = $0
  while (match(rest, /`[^`]+`/)) {
    # Taken before the call: match() inside it moves RSTART and RLENGTH, and the loop
    # would then never reach the end of the line
    span = substr(rest, RSTART + 1, RLENGTH - 2)
    rest = substr(rest, RSTART + RLENGTH)
    opening(span, 0)
  }
  if (anywhere) inside($0)
}
END {
  for (k in found) print "F\t" k
  print "C\t" claims
}
AWK
}

scan() { # scan DOC... -> the F and C lines for these documents
  CHECK_INTERFACE_PREFIXES=$prefixes CHECK_INTERFACE_WHOLE=$whole \
    awk -v anywhere="$anywhere" -v bare="$bare" -v calls="$calls" -v flags="$flags" \
    "$(awk_program)" "$declared" "$@"
}

out=$(scan "$@") || die "awk could not read the documents"
claims=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "C" { print $2 }')
findings=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "F" { print "check-interface: " $2 }' | sort)
if [[ -n "$findings" ]]; then
  printf '%s\n' "$findings"
  exit 1
fi
((claims > 0)) ||
  die "the documents make no claim this could check: a notation that stopped matching is not agreement"
# A planted document is judged by the same scan, and must not plant documents of its own
[[ -z "${CHECK_INTERFACE_PLANTED:-}" ]] || exit 0

# On planted documents, built from the same declared list and read with the same flags,
# this script must go red for the planted defect's own reason, and stay green on the
# faithful ones. The names are made up so no declared name can collide with them
work=$(mktemp -d "${TMPDIR:-/tmp}/check-interface.XXXXXX")
trap 'rm -rf "$work"' EXIT

has_pair() { # has_pair NAME ARG -> whether the list declares it, directly or through *
  awk -v n="$1" -v a="$2" 'NF >= 2 && ($1 == n || $1 == "*") && $2 == a { found = 1 } END { exit !found }' "$declared"
}
# A name with a plain argument and no positional one, so a planted flag is read as a flag
pick=$(awk '
  NF >= 2 && $1 != "*" && $2 ~ /^</ { positional[$1] = 1 }
  NF >= 2 && $1 != "*" && $2 ~ /^[a-z][A-Za-z0-9_]*$/ && !($1 in first) { first[$1] = $2; order[++n] = $1 }
  END { for (i = 1; i <= n; i++) if (!(order[i] in positional)) { print order[i], first[order[i]]; exit }
        if (n) print order[1], first[order[1]] }' "$declared")
name=${pick%% *}
arg=${pick#* }
if [[ -z "$pick" ]]; then
  name=$(awk 'NF && $1 != "*" && $1 !~ /^#/ { print $1; exit }' "$declared")
  arg=""
fi
ghost=${name}zq
while awk -v n="$ghost" '$1 == n { f = 1 } END { exit !f }' "$declared"; do ghost=${ghost}q; done
wrong=zqarg
while has_pair "$name" "$wrong"; do wrong=${wrong}q; done
# The name with its first lowercase segment turned into a placeholder, which fits it
placeholder=$(printf '%s\n' "$name" | sed 's/[a-z0-9][a-z0-9]*/<x>/')
call_arg=${arg:+ $arg=v}

# A faithful line in every notation this run reads, so each planted case is one defect
# among claims that hold rather than a document with nothing else in it
faithful=()
if [[ -n "$first_prefix" ]]; then faithful+=("\`$first_prefix$name$call_arg\`"); fi
if ((calls)); then faithful+=("\`$name($arg)\`"); fi
if ((bare)); then faithful+=("\`$name$call_arg\`"); fi
if [[ -n "$whole" ]]; then
  whole_name=$(CHECK_INTERFACE_WHOLE=$whole awk 'NF && $1 != "*" && $1 ~ ("^(" ENVIRON["CHECK_INTERFACE_WHOLE"] ")$") { print $1; exit }' "$declared")
  [[ -n "$whole_name" ]] || die "no declared name matches -s $whole, so the notation can find nothing"
  whole_ghost=${whole_name}zq
  printf '%s\n' "$whole_ghost" | grep -qxE -- "$whole" ||
    die "-s $whole accepts $whole_name but not $whole_ghost, so no made-up name can be planted in it"
  faithful+=("\`$whole_name\`")
fi

planted=0
plant() { # plant EXPECT WHAT LINE... — a document of these lines must exit EXPECT, and name WHAT
  local expect=$1 what=$2 got=0 said
  shift 2
  printf '%s\n' "${faithful[@]}" "$@" >"$work/planted.md"
  said=$(CHECK_INTERFACE_PLANTED=1 "$BASH" "$self" -d "$declared" ${opts[@]+"${opts[@]}"} "$work/planted.md" 2>&1) || got=$?
  ((got == expect)) ||
    fail "a planted document exited $got where $expect was due ($what):"$'\n'"$(cat "$work/planted.md")"$'\n'"$said"
  if ((expect == 1)) && ! grep -qF -- "$what" <<<"$said"; then
    fail "a planted document went red, but not for $what:"$'\n'"$said"
  fi
  planted=$((planted + 1))
}

plant 0 "the faithful claims hold"
# Nothing to read must be refused, not passed: the faithful lines are left out for this one
saved=("${faithful[@]}")
faithful=("a line that makes no claim")
plant 2 "no claim"
faithful=("${saved[@]}")
if [[ -n "$first_prefix" ]]; then
  plant 1 "$ghost is not a declared name" "\`$first_prefix$ghost\`"
  plant 1 "$name takes no $wrong" "\`$first_prefix$name $wrong=v\`"
  plant 1 "$name takes no $wrong" "\`$first_prefix$name $wrong VALUE\`"
  plant 1 "$name takes no $wrong" '```' "\$ $first_prefix$name $wrong=v" '```'
  plant 1 "$name takes no $wrong" "\`$first_prefix$placeholder $wrong=v\`"
  plant 0 "an allowed line is not read" "\`$first_prefix$ghost\` <!-- check-interface: allow -->"
  if ((! flags)); then
    plant 0 "a word before a quoted value is prose, not an argument" "\`$first_prefix$name and not \"$wrong\"\`"
  fi
  if ((anywhere)); then
    plant 1 "$ghost is not a declared name" "a sentence that calls $first_prefix$ghost in passing"
  else
    plant 0 "a prefix in prose is not a claim without -a" "a sentence that calls $first_prefix$ghost in passing"
  fi
fi
if ((calls)); then
  plant 1 "$ghost is not a declared name" "\`$ghost($arg)\`"
  plant 1 "$name takes no $wrong" "\`$name(…, $wrong)\`"
  plant 1 "$name takes no $wrong" "\`$placeholder($wrong)\`"
fi
if ((bare)); then
  plant 1 "$name takes no $wrong" "\`$name $wrong=v\`"
  plant 0 "an undeclared first word is prose under -b" "\`$ghost $wrong=v\`"
  plant 0 "a bare word in an unprefixed span is not a flag" "\`$name $wrong\`"
fi
if [[ -n "$whole" ]]; then
  plant 1 "$whole_ghost is not a declared name" "\`$whole_ghost\`"
fi
if ((flags)); then
  plant 1 "$name takes no $wrong" "\`$first_prefix$name $wrong\`"
fi

echo "check-interface: $claims claims in $# documents hold against $nnames declared names, $planted planted cases behave"
