#!/usr/bin/env bash
# Needs bash 3.2 and POSIX tools only, so it runs on a macOS runner unchanged. It has no
# repo-specific part: another repository takes it through the vendoring cascade
# (references/bump-cascade.md in https://github.com/rokokol/ci-skill), never edits its
# copy in place, and calls it from its own gate
set -euo pipefail

usage() {
  cat <<'EOF'
Hold a skill's documents to the interface a foreign tool declares about itself: the
commands of a CLI as its own help lists them, the tools and arguments an MCP server
advertises, the fields an API accepts. When the tool renames one, a document that still
teaches the old name teaches an agent to call something that does not exist, and nothing
in the repository notices. Then it proves each of its checks able to fail, on planted
documents built from the same declared list, every time it runs

  check-interface.sh -d FILE [-r FILE] [-x FILE] [-p PREFIX]... [-a] [-b] [-c] [-s ERE] [-f] DOC...

  -d FILE    what the tool declares: one name per line, or a name and one argument it
             takes per line. A name `*` gives its arguments to every name, and an
             argument written <like-this> is a positional value, so bare words after
             that name are values rather than flags. How the list is made is the calling
             gate's own line: an MCP handshake, `tool help | awk …`, a recorded snapshot
  -p PREFIX  a claim opens with PREFIX at the start of a code span, or of a line in a
             fenced block after an optional `$ `: `PREFIX NAME key=… flag`; repeatable
  -a         PREFIX opens a claim anywhere in a line, prose included — for a prefix no
             sentence uses in passing, such as the full name of an MCP tool
  -b         a code span that opens with a declared name is a claim too; an undeclared
             first word there is taken for prose, and so are its bare words, which may
             be quoted output or a shell line as easily as flags, so only its `key=`
             arguments are held
  -c         a code span in call notation, `NAME(arg, arg=…, …)`, is a claim
  -s ERE     a code span that is wholly a name matching ERE is a claim to that name
  -f         a bare lowercase word after a prefixed name is an argument, as a CLI's
             flags are
  -r FILE    names the tool declared before, in the format of -d. One that is there and
             not in -d was renamed or removed, and a claim opening with it is a finding in
             every notation — under -b too, where an undeclared first word is otherwise
             prose, so a renamed command in a bare span is caught the day the declaration
             drops it. The calling gate makes the file, from the declarations it recorded
  -x FILE    excuses for the wrong calls a document shows on purpose, kept in a file no
             agent loads, so an excuse costs no request its tokens; a consumer keeps it
             beside the checker as check-interface.allow. One entry per line,
             `ID PATH [TEXT]`, excuses the findings of ID in PATH, spelt as the finding
             spells it, or only those on lines that contain TEXT when it is given; `#`
             opens a comment. An entry that excuses nothing is itself a finding

An argument is read as `key=value`, as `key VALUE` where VALUE is an upper-case or
<angled> placeholder, and with -f as a bare word after a prefix. A claim ends at a shell
operator, at the end of its span or line, or after a word ending in `.` or `;`. A name
may hold a placeholder, <source> or SOURCE, which stands for every declared name it
fits, and each of those must take the argument

The findings, by the id each one carries:
  undeclared-name  a claim opens with a name the tool does not declare, or with a
                   placeholder no declared name fits
  undeclared-arg   a declared name is given an argument it does not take
  retired-name     a claim opens with a name -r holds and -d no longer does
  stale-allow      an entry in the -x file that excuses nothing, one naming a document
                   this run does not read included, so the file stays true

Nothing here reaches the network.
Exit 0 when every claim holds, 1 with one `check-interface: FILE:LINE: ID: what` line
per finding, 2 on a usage error, an unreadable file, an -x entry that is not
`ID PATH [TEXT]` or names an id no excusable finding carries, a declared list that names
nothing, or documents that make no claim at all, so a notation that stopped matching is
not read as agreement
EOF
}

die() {
  printf 'check-interface: %s\n' "$1" >&2
  exit 2
}

fail() {
  printf 'check-interface: %s\n' "$1"
  exit 1
}

self=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")
declared="" retired="" excuses="" prefixes="" first_prefix="" whole=""
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
    -r)
      (($# >= 2)) || die "-r needs a file"
      retired=$2
      shift 2
      ;;
    -x)
      (($# >= 2)) || die "-x needs a file"
      excuses=$2
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
# An empty -r is fine: until the tool drops a name there is nothing it once declared
[[ -z "$retired" || (-f "$retired" && -r "$retired") ]] || die "$retired is not a readable file"
[[ -z "$excuses" || (-f "$excuses" && -r "$excuses") ]] || die "$excuses is not a readable file"
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

# One pass over the declared list and the documents. Prints "E<tab>what" per -x entry it
# cannot read, "F<tab>FILE:LINE: ID: what" per finding, "X<tab>N" for the findings the -x
# file excused and "C<tab>N" for the number of claims read. POSIX awk only: no gensub and
# no arrays of arrays. A quoted heredoc in a function, not a $( ) around one, which bash
# 3.2 mis-parses when the text holds an unbalanced parenthesis, as the bracket below does
awk_program() {
  cat <<'AWK'
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
# TEXT is matched against the line as written, so a fenced line keeps its `$ `
function finding(id, what,   i, key) {
  key = FILENAME ":" FNR ": " id ": " what
  for (i = 1; i <= na; i++)
    if (aid[i] == id && apath[i] == FILENAME && (atext[i] == "" || index($0, atext[i]))) {
      used[i] = 1
      forgiven[key] = 1
      return
    }
  found[key] = 1
}
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
      finding("undeclared-arg", fit[i] " takes no " arg)
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
    if (was_declared(name)) {
      claims++
      finding("retired-name", name " is no longer declared")
    } else if (strict) {
      claims++
      if (index(pattern_of(name), "\001")) finding("undeclared-name", name " fits no declared name")
      else finding("undeclared-name", name " is not a declared name")
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
function opening(s, fenced,   i, p, w) {
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
  if (bare && match(s, /^[A-Za-z0-9_:-]+/)) {
    w = substr(s, 1, RLENGTH)
    if ((w in declared) || was_declared(w)) claim(s, 0)
  }
}
# A name the tool declared before and declares no more: renamed or removed
function was_declared(name) {
  return (name in was) && !(name in declared)
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
  if (retired_file != "") {
    while ((getline line < retired_file) > 0) {
      split(line, field, " ")
      if (field[1] != "" && field[1] !~ /^#/ && field[1] != "*") was[field[1]] = 1
    }
    close(retired_file)
  }
  # The -x file: `ID PATH [TEXT]`, TEXT the rest of the line with the space around it trimmed
  excusable = ENVIRON["CHECK_INTERFACE_IDS"]
  split(excusable, field, " ")
  for (i in field) known[field[i]] = 1
  allow_file = ENVIRON["CHECK_INTERFACE_ALLOW"]
  na = 0
  if (allow_file != "") {
    k = 0
    while ((getline line < allow_file) > 0) {
      k++
      if (line ~ /^[ \t]*(#|$)/) continue
      if (split(line, field, " ") < 2) {
        print "E\t" allow_file ":" k ": expected ID PATH [TEXT], got: " line
        continue
      }
      if (!(field[1] in known)) {
        print "E\t" allow_file ":" k ": " field[1] " is not an id an excuse can name: " excusable
        continue
      }
      text = line
      sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]*/, "", text)
      sub(/[ \t]+$/, "", text)
      na++
      aid[na] = field[1]
      apath[na] = field[2]
      atext[na] = text
      aline[na] = k
    }
    close(allow_file)
  }
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
  # An excuse that excuses nothing is a rule switched off for a line that no longer exists
  for (i = 1; i <= na; i++)
    if (!(i in used))
      found[allow_file ":" aline[i] ": stale-allow: the entry for " aid[i] " in " apath[i] " excuses nothing"] = 1
  for (k in found) print "F\t" k
  n = 0
  for (k in forgiven) n++
  print "X\t" n
  print "C\t" claims
}
AWK
}

# The ids a finding carries are read from the header, the one list of them, and the
# planted section holds the code to it; stale-allow is the one an entry cannot name
help_ids=$(usage | awk '/^The findings/ { on = 1; next } on && !NF { exit } on && /^  [a-z]/ { print $1 }')
excusable=$(printf '%s\n' "$help_ids" | grep -vx stale-allow | tr '\n' ' ')

scan() { # scan DOC... -> the E, F, X and C lines for these documents
  # The -x path through the environment, as awk -v would expand a backslash in it
  CHECK_INTERFACE_PREFIXES=$prefixes CHECK_INTERFACE_WHOLE=$whole CHECK_INTERFACE_ALLOW=$excuses \
    CHECK_INTERFACE_IDS=$excusable \
    awk -v anywhere="$anywhere" -v bare="$bare" -v calls="$calls" -v flags="$flags" \
    -v retired_file="$retired" "$(awk_program)" "$declared" "$@"
}

out=$(scan "$@") || die "awk could not read the documents"
unread=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "E" { print "check-interface: " $2 }')
if [[ -n "$unread" ]]; then
  printf '%s\n' "$unread" >&2
  exit 2
fi
claims=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "C" { print $2 }')
excused=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "X" { print $2 }')
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

# Every id the code gives a finding is in the header, and every id an entry may name there
# is one the code gives, so neither is added without the other
code_ids=$(awk_program | awk '{ while (match($0, /finding\("[a-z-]+"/)) { print substr($0, RSTART + 9, RLENGTH - 10); $0 = substr($0, RSTART + RLENGTH) } }' | sort -u)
[[ -n "$code_ids" ]] || fail "no finding(\"ID\", …) call was read from the awk program, so its ids go unchecked"
for id in $code_ids; do
  grep -qx -- "$id" <<<"$help_ids" || fail "a finding carries $id, which the header's list of ids does not name"
done
for id in $excusable; do
  grep -qx -- "$id" <<<"$code_ids" || fail "the header names $id, which no finding carries"
done

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
# Set before a plant, and spent by it: the entries of the planted -x file, and a text the
# output must not hold
entries=()
absent=""
plant() { # plant EXPECT WHAT LINE... — a document of these lines must exit EXPECT, and name WHAT
  local expect=$1 what=$2 got=0 said excuse
  shift 2
  printf '%s\n' "${faithful[@]}" "$@" >"$work/planted.md"
  excuse=()
  : >"$work/planted.allow"
  if [[ -n "${entries[*]+set}" ]]; then
    printf '%s\n' "${entries[@]}" >"$work/planted.allow"
    excuse=(-x "$work/planted.allow")
  fi
  said=$(CHECK_INTERFACE_PLANTED=1 "$BASH" "$self" -d "$declared" ${excuse[@]+"${excuse[@]}"} ${opts[@]+"${opts[@]}"} "$work/planted.md" 2>&1) || got=$?
  ((got == expect)) ||
    fail "a planted document exited $got where $expect was due ($what):"$'\n'"$(cat "$work/planted.md")"$'\n'"excused by:"$'\n'"$(cat "$work/planted.allow")"$'\n'"$said"
  if ((expect != 0)) && ! grep -qF -- "$what" <<<"$said"; then
    fail "a planted document exited $got, but not for $what:"$'\n'"$said"
  fi
  if [[ -n "$absent" ]] && grep -qF -- "$absent" <<<"$said"; then
    fail "a planted document was named for $absent, which an entry excuses:"$'\n'"$said"
  fi
  entries=()
  absent=""
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

# The excuses, on a defect this run reads in whichever notation it has: named alone, and
# not named once an entry of its id and document excuses it
doc=$work/planted.md
if [[ -n "$first_prefix" ]]; then
  defect="\`$first_prefix$ghost\`" defect_id=undeclared-name defect_what="$ghost is not a declared name"
elif ((calls)); then
  defect="\`$ghost($arg)\`" defect_id=undeclared-name defect_what="$ghost is not a declared name"
elif [[ -n "$whole" ]]; then
  defect="\`$whole_ghost\`" defect_id=undeclared-name defect_what="$whole_ghost is not a declared name"
else
  defect="\`$name $wrong=v\`" defect_id=undeclared-arg defect_what="$name takes no $wrong"
fi
if [[ "$defect_id" == undeclared-name ]]; then other_id=undeclared-arg; else other_id=undeclared-name; fi
at=$((${#faithful[@]} + 1))
plant 1 "$doc:$at: $defect_id: $defect_what" "$defect"
entries=("$defect_id $doc")
plant 0 "an entry excuses its id in its document" "$defect"
entries=("$other_id $doc")
plant 1 "$doc:$at: $defect_id: $defect_what" "$defect"
entries=("$defect_id $work/another.md")
plant 1 "$doc:$at: $defect_id: $defect_what" "$defect"
entries=("$defect_id $doc in plant one")
absent="$doc:$at:"
plant 1 "$doc:$((at + 1)): $defect_id: $defect_what" "$defect in plant one" "$defect in plant two"
# The space an editor leaves after an entry is not part of its text
entries=("$defect_id $doc in plant two" "$defect_id $doc in plant one  ")
plant 0 "each entry excuses its own line, the first not standing for the rest" "$defect in plant one" "$defect in plant two"
if [[ -n "$first_prefix" ]]; then
  entries=("undeclared-name $doc \$ $first_prefix$ghost")
  plant 0 "an entry's text is read against the fenced line as written" '```' "\$ $first_prefix$ghost" '```'
fi
entries=('# a comment and a blank line are not entries' '' "$defect_id $doc")
plant 1 "planted.allow:3: stale-allow" "a line that holds no defect"
entries=("$defect_id")
plant 2 "expected ID PATH [TEXT]" "$defect"
entries=("stale-allow $doc")
plant 2 "stale-allow is not an id an excuse can name" "$defect"
if [[ -n "$retired" ]] && ((nnames > 1)); then
  # The tool drops a name: the list without it is the declaration, the list with it the
  # earlier one, and a claim still opening with it must be named in every notation read —
  # a bare span included, where an undeclared first word is otherwise taken for prose
  awk -v n="$name" '$1 != n' "$declared" >"$work/now.txt"
  printf '%s\n' "$name" >"$work/was.txt"
  plant_retired() { # plant_retired LINE — a document of this one line must name the dropped name
    local got=0 said
    printf '%s\n' "$1" >"$work/planted.md"
    said=$(CHECK_INTERFACE_PLANTED=1 "$BASH" "$self" -d "$work/now.txt" -r "$work/was.txt" ${opts[@]+"${opts[@]}"} "$work/planted.md" 2>&1) || got=$?
    if ((got != 1)) || ! grep -qF -- "$name is no longer declared" <<<"$said"; then
      fail "a name the tool dropped passed in \`$1\` (exit $got):"$'\n'"$said"
    fi
    planted=$((planted + 1))
  }
  if [[ -n "$first_prefix" ]]; then plant_retired "\`$first_prefix$name\`"; fi
  if ((calls)); then plant_retired "\`$name($arg)\`"; fi
  if ((bare)); then plant_retired "\`$name\`"; fi
fi

echo "check-interface: $claims claims in $# documents hold against $nnames declared names, $excused findings excused, $planted planted cases behave"
