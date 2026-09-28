#!/usr/bin/env bash
# Taken from rokokol/versioning-skill through the ci skill's vendoring cascade
# (references/bump-cascade.md in https://github.com/rokokol/ci-skill): a copy is never
# edited in place, a fix belongs there. Needs bash 3.2 and POSIX tools only
# No -e: every finding is printed and counted, and a non-zero grep is data, not a failure
set -uo pipefail

usage() {
  cat <<'EOF'
Decide the machine-checkable half of a changelog. Takes ANY changelog, so it is worth
more than a review comment: drop it into a repository's own gate and the rules stop
depending on somebody remembering them

  check-changelog.sh [-v VERSION-FILE | -n] [-t TEMPLATE] [CHANGELOG]

  -v FILE       the repository's version file (default: VERSION beside the changelog)
  -n            assert this repository has no version, whatever files are lying around
  -t TEMPLATE   the heading template this changelog follows, level included, instead of
                the first release heading choosing one from the table below

Options may come before or after the changelog, and there is one changelog per run

A repository HAS a version when someone can install a particular one and report a bug
against it. A VERSION file says so, and so does a numbered release heading unless -n
says otherwise, the version then living in a manifest this checker does not read. Such a
changelog may keep an `Unreleased` section on top for work waiting on the next release. A
repository that is only ever read at whatever revision is checked out has no version to
be wrong about: its headings are dates, and `Unreleased` is a state it can never be in,
so the section would never close

Every release heading in one changelog follows one template. Without -t, the first
release heading picks it from the table; the flag gives it whole, level included, as in
-t '## [{version}] - {date}'. {version} is x.y.z or x.y with an optional -prerelease and
+build; {date} is YYYY-MM-DD and {long-date} a date in words, "July 20th, 2026" or
"Jan 26, 2026", and either must name a day that exists; {url} is a link target. HTML
tags and Keep a Changelog's ` [YANKED]` are read past

Templates, and who writes them:

  [{version}] - {date}           Keep a Changelog, Common Changelog
  [{version}]({url}) ({date})    release-please, conventional-changelog
  {version} - {date}             Common Changelog without the link
  {version} ({date})             angular, grafana, helix, typescript-eslint
  v{version} ({date})            babel, pydantic
  {version} ({long-date})        react, tokio
  v{version} — {long-date}       axios
  {version}                      jest, ruff, uv, esbuild, rollup, svelte
  v{version}                     bat, fd
  Version {version}              black
  {date}                         a repository with no version

A release may sit at any level, since conventional-changelog writes a major at #, a minor
at ## and a patch at ###. The highest level a release sits at is the release level: there
a heading that follows no template is a finding, one deeper is a section, and a level-one
heading that opens the file is its title. `Unreleased`, in any case and bracketed or not,
sits at the release level. Headings are read in both Markdown forms, hashed and
underlined, and never inside a code fence

Newest first: a release is out of place when it is newer than the one above it by version
and, where the template carries a day, by day as well. So a changelog keeping several
release lines passes whether it interleaves them by day, as angular's does, or keeps them
in blocks by version, as grafana's does

Dated and numbered headings meet at most once, in either order: dated above numbered where
a repository stopped shipping versions, numbered above dated where it started, its dated
history kept rather than rewritten. A VERSION file puts the numbered ones on top, and -n
the dated ones

Nothing here reaches the network
Exit: 0 clean, 1 findings printed, 2 a usage error
EOF
}

die() {
  printf 'check-changelog: %s\n' "$1" >&2
  exit 2
}

version_file=""
no_version=""
pinned=""
changelog=""
while (($#)); do
  case "$1" in
    -v)
      # Not ${2:?…}: that prints bash's own message and exits 1, which a caller reads as a
      # finding, where the header promises 2 for a usage error
      (($# >= 2)) || die "-v needs a file"
      version_file="$2"
      shift 2
      ;;
    -n)
      no_version=1
      shift
      ;;
    -t)
      (($# >= 2)) || die "-t needs a template"
      pinned="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) die "unknown option: $1" ;;
    *)
      # Not the end of the options: parsing used to stop at the file, so a -v after it
      # was dropped without a word, and so was a second file
      [[ -z "$changelog" ]] || die "one changelog at a time — got $changelog and $1"
      changelog="$1"
      shift
      ;;
  esac
done

changelog="${changelog:-CHANGELOG.md}"
[[ -r "$changelog" ]] || die "cannot read $changelog"
[[ -z "$no_version" || -z "$version_file" ]] || die "-n and -v contradict each other"

if [[ -z "$no_version" && -z "$version_file" ]]; then
  default="$(dirname "$changelog")/VERSION"
  [[ -r "$default" ]] && version_file="$default"
fi

version=""
if [[ -n "$version_file" ]]; then
  [[ -r "$version_file" ]] || die "cannot read $version_file"
  version=$(tr -d '[:space:]' <"$version_file")
  [[ -n "$version" ]] || die "$version_file is empty"
fi

# Strictly-less-than by semver precedence (semver.org, section 11). Not `sort -V`, which is
# a GNU extension the BSD sort on macOS may not have — the same reason there is no
# `mapfile` here. Build metadata after `+` never counts. A prerelease sorts below the
# release it precedes, and prerelease identifiers compare dot by dot: numeric ones as
# numbers, numeric below alphanumeric, and a shorter list below a longer one it prefixes.
# A two-part x.y compares as x.y.0
#
# The suffix used to be dropped before comparing, which made `2.0.0` and `2.0.0-rc.1`
# equal and reported the correct history — a release above its own candidate — as out of
# order, in every repository that ships release candidates
version_lt() { # version_lt A B -> 0 when A < B
  local a="${1%%+*}" b="${2%%+*}"
  local pre_a="" pre_b="" i x y
  [[ "$a" == *-* ]] && pre_a="${a#*-}"
  [[ "$b" == *-* ]] && pre_b="${b#*-}"
  local -a ia ib
  IFS=. read -r -a ia <<<"${a%%-*}"
  IFS=. read -r -a ib <<<"${b%%-*}"
  for i in 0 1 2; do
    x=${ia[$i]:-0}
    y=${ib[$i]:-0}
    # The braces are what tree-sitter needs: it rejects a base prefix before a bare $name
    ((10#${x} < 10#${y})) && return 0
    ((10#${x} > 10#${y})) && return 1
  done
  # Equal cores: a release outranks every prerelease of itself. A's side is asked first —
  # asked the other way round, B being a release answered "not less" even when A was that
  # release's own candidate
  [[ -z "$pre_a" ]] && return 1
  [[ -z "$pre_b" ]] && return 0
  IFS=. read -r -a ia <<<"$pre_a"
  IFS=. read -r -a ib <<<"$pre_b"
  for ((i = 0; i < ${#ia[@]} || i < ${#ib[@]}; i++)); do
    ((i < ${#ia[@]})) || return 0
    ((i < ${#ib[@]})) || return 1
    x=${ia[$i]}
    y=${ib[$i]}
    if [[ "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]]; then
      ((10#${x} < 10#${y})) && return 0
      ((10#${x} > 10#${y})) && return 1
    elif [[ "$x" =~ ^[0-9]+$ ]]; then
      return 0
    elif [[ "$y" =~ ^[0-9]+$ ]]; then
      return 1
    else
      [[ "$x" < "$y" ]] && return 0
      [[ "$x" > "$y" ]] && return 1
    fi
  done
  return 1
}

# Whether a YYYY-MM-DD names a day that exists. By arithmetic rather than `date`, whose
# parsing flags differ between GNU and BSD, and some BSD versions roll 02-30 into March
real_day() { # real_day YYYY-MM-DD -> 0 when the day exists
  local y=$((10#${1:0:4})) m=$((10#${1:5:2})) d=$((10#${1:8:2})) last
  case $m in
    1 | 3 | 5 | 7 | 8 | 10 | 12) last=31 ;;
    4 | 6 | 9 | 11) last=30 ;;
    2) if (((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)); then last=29; else last=28; fi ;;
    *) return 1 ;;
  esac
  ((d >= 1 && d <= last))
}

months="January February March April May June July August September October November December"
# Cut to three letters, and September's four, which react and tokio write as often as not
short_months="Jan Feb Mar Apr Jun Jul Aug Sep Sept Oct Nov Dec"

# A date in words as YYYY-MM-DD in $iso, so real_day and the ordering read one shape. Into
# a variable rather than printed, since a subshell per heading is what a long changelog
# would pay for it. The month is already one of the twelve or a cut of one: the template's
# pattern lists them, and every cut shares its first three letters with the full name
long_day() { # long_day "July 20th, 2026" -> iso=2026-07-20
  local month="${1%% *}" rest="${1#* }" day year n=0 name
  day="${rest%%,*}"
  day="${day%st}" day="${day%nd}" day="${day%rd}" day="${day%th}"
  year="${rest##* }"
  for name in $months; do
    n=$((n + 1))
    [[ "${name:0:3}" == "${month:0:3}" ]] && break
  done
  printf -v iso '%04d-%02d-%02d' "$((10#${year}))" "$n" "$((10#${day}))"
}

# Each placeholder's pattern, with the number of groups it opens, since ERE has no
# non-capturing group and the version's own groups shift every later one
re_version='([0-9]+\.[0-9]+(\.[0-9]+)?([-+][0-9A-Za-z.+-]+)?)'
re_date='([0-9]{4}-[0-9]{2}-[0-9]{2})'
re_long="((${months// /|}|${short_months// /|}) [0-9]{1,2}(st|nd|rd|th)?, [0-9]{4})"
re_url='([^)[:space:]]+)'

# A template body as an anchored ERE in $re, and the groups holding the version, the ISO
# date and the date in words in $g_version $g_date $g_long, 0 where the body has none
compile() { # compile BODY
  local body="$1" out="" n=0 c
  g_version=0 g_date=0 g_long=0
  while [[ -n "$body" ]]; do
    case "$body" in
      '{version}'*)
        g_version=$((n + 1)) n=$((n + 3)) out="$out$re_version" body="${body#\{version\}}"
        ;;
      '{date}'*) g_date=$((n + 1)) n=$((n + 1)) out="$out$re_date" body="${body#\{date\}}" ;;
      '{long-date}'*)
        g_long=$((n + 1)) n=$((n + 3)) out="$out$re_long" body="${body#\{long-date\}}"
        ;;
      '{url}'*) n=$((n + 1)) out="$out$re_url" body="${body#\{url\}}" ;;
      '{'*) die "unknown placeholder ${body%%\}*}} in the template '$1'" ;;
      *)
        c="${body:0:1}"
        case "$c" in
          \\ | . | \[ | \] | \( | \) | \* | + | \? | \{ | \} | \| | ^ | \$) out="$out\\$c" ;;
          *) out="$out$c" ;;
        esac
        body="${body:1}"
        ;;
    esac
  done
  re="^$out\$"
}

# The table in the help is the one list of templates: read back from it, so the help cannot
# offer a shape the checker refuses, or the checker accept one the help never names
t_body=() t_re=() t_gv=() t_gd=() t_gl=()
while IFS= read -r body; do
  compile "$body"
  t_body+=("$body") t_re+=("$re") t_gv+=("$g_version") t_gd+=("$g_date") t_gl+=("$g_long")
  # <<< and not `usage | awk`: the program exits once the table is read, and a producer
  # whose reader stops early dies of SIGPIPE, which pipefail makes the status of a
  # pipeline that did its job
done < <(awk '
  /^Templates, and who writes them:$/ { f = 1; next }
  f && /^$/ { if (seen) exit; next }
  f { seen = 1; sub(/^  /, ""); split($0, cell, /  +/); print cell[1] }
' <<<"$(usage)")
((${#t_body[@]} > 0)) || die "no templates in the help — the table under 'Templates, and who writes them:' is gone"

# Which template of the table a heading follows, numbered rows only or dated rows only: its
# index in $hit, or -1, with the groups of the match left in BASH_REMATCH
match_table() { # match_table TEXT numbered|dated
  local i
  for ((i = 0; i < ${#t_body[@]}; i++)); do
    if [[ "$2" == numbered ]]; then ((t_gv[i])) || continue; else ((t_gv[i] == 0)) || continue; fi
    [[ "$1" =~ ${t_re[$i]} ]] && {
      hit=$i
      return 0
    }
  done
  hit=-1
  return 1
}

# The pinned template is compiled like a row of the table and takes the index past its end,
# so every lookup below reads one set of arrays
pinned_level=""
if [[ -n "$pinned" ]]; then
  pinned_shape='^(#{1,6}) (.+)$'
  [[ "$pinned" =~ $pinned_shape ]] || die "a template starts with # or ## and a space, as in '## [{version}] - {date}': '$pinned'"
  pinned_level=${#BASH_REMATCH[1]}
  compile "${BASH_REMATCH[2]}"
  ((g_version || g_date || g_long)) || die "a template needs {version} or a date, {date} or {long-date}: '$pinned'"
  p=${#t_body[@]}
  t_body+=("${BASH_REMATCH[2]}") t_re+=("$re") t_gv+=("$g_version") t_gd+=("$g_date") t_gl+=("$g_long")
fi

findings=0
report() { # report LINE MESSAGE
  printf '%s:%s: %s\n' "$changelog" "$1" "$2"
  findings=$((findings + 1))
}

# Dated and numbered headings meet once at most, where versions started or stopped; a second
# meeting is the two kinds interleaved, which no transition explains. Called at $line
last_kind=""
meeting_line=""
meet() { # meet dated|numbered
  if [[ -n "$last_kind" && "$1" != "$last_kind" ]]; then
    if [[ -z "$meeting_line" ]]; then
      meeting_line=$line
    else
      report "$line" "a $1 heading below $last_kind ones, after the kinds met at line $meeting_line — the two kinds meet once, where a repository started or stopped shipping versions, and never interleave"
    fi
  fi
  last_kind=$1
}

# Every heading as LINE:LEVEL:TEXT, in the order the file states them: hashed ones, and
# underlined ones reported on the line of their text. Not inside a code fence, where a
# shell comment is a hashed line; not a `---` after a blank line, a list item or a quote,
# where it is a thematic break. The text comes without HTML tags, a closing run of #, or a
# [YANKED] marker. POSIX awk without interval expressions, which older BSD awks lack
extract() { # extract FILE
  awk '
    function emit(n, depth, t) {
      gsub(/<[^>]*>/, "", t)
      sub(/[ \t]+#+[ \t]*$/, "", t)
      sub(/^[ \t]+/, "", t)
      sub(/[ \t]+$/, "", t)
      sub(/ \[YANKED\]$/, "", t)
      print n ":" depth ":" t
    }
    fence != "" {
      if (index($0, fence) == 1 && $0 ~ /^(```+|~~~+)[ \t]*$/) fence = ""
      next
    }
    /^```/ || /^~~~/ { fence = substr($0, 1, 3); para = ""; next }
    /^#+([ \t]|$)/ {
      match($0, /^#+/)
      if (RLENGTH <= 6) emit(NR, RLENGTH, substr($0, RLENGTH + 1))
      para = ""
      next
    }
    para != "" && /^=+[ \t]*$/ { emit(pnr, 1, para); para = ""; next }
    para != "" && /^-+[ \t]*$/ { emit(pnr, 2, para); para = ""; next }
    /^[ \t]*$/ { para = ""; next }
    /^([-*+][ \t]|[0-9]+[.)][ \t]|>|    |\t)/ { para = ""; next }
    { para = $0; pnr = NR }
  ' "$1"
}

# A read loop rather than `mapfile`, which is bash 4.0+ — this checker is meant to be
# dropped into other repositories' gates, and macOS ships bash 3.2
headings=()
while IFS= read -r heading_line; do
  headings+=("$heading_line")
done < <(extract "$changelog")

parse() { # parse ENTRY -> $line $depth $text
  line="${1%%:*}"
  text="${1#*:}"
  depth="${text%%:*}"
  text="${text#*:}"
}

unreleased_shape='^\[?[Uu][Nn][Rr][Ee][Ll][Ee][Aa][Ss][Ee][Dd]\]?$'

# A pinned dated template replaces the table's dated rows; a pinned numbered one replaces
# its numbered rows. Either way the other kind keeps the table's rows, so a repository that
# stopped shipping versions keeps its dated headings above a pinned numbered template
dated_index() { # dated_index TEXT -> 0 when TEXT is a dated heading, with $hit set
  if [[ -n "$pinned" ]] && ((t_gv[p] == 0)); then
    [[ "$1" =~ ${t_re[$p]} ]] && hit=$p && return 0
    hit=-1
    return 1
  fi
  match_table "$1" dated
}

# A numbered heading: against the changelog's template once one is set, else the table. A
# pinned dated template allows no numbered heading at all: the repository said it has no
# versions
numbered_index() { # numbered_index TEXT -> 0 when TEXT is a numbered release, with $hit set
  if ((template >= 0)); then
    [[ "$1" =~ ${t_re[$template]} ]] && hit=$template && return 0
    hit=-1
    return 1
  fi
  if [[ -n "$pinned" ]]; then
    hit=-1
    return 1
  fi
  match_table "$1" numbered
}

template=-1
template_line=""
[[ -n "$pinned" ]] && ((t_gv[p])) && template=$p

# The release level, the highest a release, a dated entry or Unreleased sits at, unless -t
# gives it; and whether any release is numbered, which makes the repository a versioned one
# when -n does not say otherwise
level=$pinned_level
has_numbered=""
for entry in "${headings[@]}"; do
  parse "$entry"
  if numbered_index "$text"; then
    has_numbered=1
  elif ! [[ "$text" =~ $unreleased_shape ]] && ! dated_index "$text"; then
    continue
  fi
  [[ -n "$pinned" ]] && continue
  if [[ -z "$level" ]] || ((depth < level)); then level=$depth; fi
done
level=${level:-2}
versioned=""
[[ -n "$version" || (-z "$no_version" && -n "$has_numbered") ]] && versioned=1

seen_numbered=""
seen_release=""
prev_date=""
prev_day=""
prev_version=""
found_current=""
releases=0

first=1
for entry in "${headings[@]}"; do
  parse "$entry"
  opens_file=$first
  first=""

  if [[ "$text" =~ $unreleased_shape ]]; then
    ((depth == level)) || continue
    if [[ -z "$versioned" ]]; then
      report "$line" "an Unreleased section in a repository with no version — it holds work that has landed but not shipped, which cannot happen here, so it never closes"
    elif [[ -n "$seen_release" ]]; then
      report "$line" "an Unreleased section below a release — work waiting for the next release goes on top, above everything that has shipped"
    fi
    continue
  fi

  if dated_index "$text"; then
    if ((depth < level)); then
      report "$line" "'$text' is a release heading at level $depth, above the level $level that -t gives"
      continue
    fi
    releases=$((releases + 1))
    seen_release=1
    meet dated
    if ((t_gd[hit])); then iso="${BASH_REMATCH[${t_gd[$hit]}]}"; else long_day "${BASH_REMATCH[${t_gl[$hit]}]}"; fi
    if ! real_day "$iso"; then
      report "$line" "$text is not a date — the heading has the shape of one, but no such day exists"
      continue
    fi
    # Which kind sits on top is the repository's own word about itself: a VERSION file says it
    # ships versions now, so its dated history goes below them; -n says it does not, so its
    # dated entries, the newer work, go above. With neither, both transitions stand
    if [[ -n "$no_version" && -n "$seen_numbered" ]]; then
      report "$line" "a numbered heading above a dated one — a repository with no version keeps its dated entries, its newer work, on top"
    fi
    if [[ -n "$version" && -z "$seen_numbered" ]]; then
      report "$line" "a dated heading in a repository that ships version $version, above every numbered one — a shipped artifact puts its releases on top, so a reader can match an entry to what they installed"
    fi
    if [[ "$iso" == "$prev_date" ]]; then
      report "$line" "$text appears twice — one heading per day, and the second one's entries belong under the first"
    elif [[ -n "$prev_date" && ! "$iso" < "$prev_date" ]]; then
      report "$line" "$text is not older than the $prev_date above it — newest first"
    fi
    prev_date="$iso"
    continue
  fi

  if numbered_index "$text"; then
    if ((template < 0)); then
      template=$hit
      template_line=$line
    fi
    if ((depth < level)); then
      report "$line" "'$text' is a release heading at level $depth, above the level $level that -t gives"
      continue
    fi
    releases=$((releases + 1))
    meet numbered
    v="${BASH_REMATCH[${t_gv[$hit]}]}"
    day="" iso=""
    if ((t_gd[hit])); then
      day="${BASH_REMATCH[${t_gd[$hit]}]}" iso=$day
    elif ((t_gl[hit])); then
      day="${BASH_REMATCH[${t_gl[$hit]}]}"
      long_day "$day"
    fi
    if [[ -n "$day" ]] && ! real_day "$iso"; then
      report "$line" "$day is not a date — the heading has the shape of one, but no such day exists"
      iso=""
    fi
    [[ "$v" == "$version" ]] && found_current=1
    seen_release=1
    seen_numbered=1
    if [[ "$v" == "$prev_version" ]]; then
      report "$line" "[$v] appears twice — one heading per release, and the second one's entries belong under the first"
    elif [[ -n "$prev_version" ]] && ! version_lt "$v" "$prev_version"; then
      # Newer by version alone is no finding where a day says otherwise: the corpus in
      # tests/real has both orders a changelog with several release lines keeps, angular's
      # interleaved by day and grafana's in blocks by version, and each breaks the other's rule
      if [[ -z "$day" ]]; then
        report "$line" "[$v] is not older than the [$prev_version] above it — newest first"
      elif [[ -n "$iso" && -n "$prev_day" && "$iso" > "$prev_day" ]]; then
        report "$line" "'$text' is newer than the [$prev_version] above it, by version and by day — newest first"
      fi
    fi
    prev_version="$v"
    [[ -n "$iso" ]] && prev_day=$iso
    continue
  fi

  # Follows no template: a finding at the release level, unless it is the file's title
  ((depth == level)) || continue
  [[ -n "$opens_file" ]] && ((depth == 1)) && continue
  if [[ -n "$pinned" ]]; then
    report "$line" "'$text' does not follow the heading template -t gives, '$pinned'"
  elif ((template >= 0)); then
    report "$line" "'$text' does not follow this changelog's heading template '${t_body[$template]}', set by line $template_line — one template per changelog"
  else
    report "$line" "'$text' matches none of the heading templates — check-changelog.sh --help lists them"
  fi
done

# An extractor that finds nothing must say so rather than read as "all clear": a file with
# no release headings at all is not a clean changelog, it is an unparsed one
((releases > 0 || findings > 0)) || report 1 "no release headings at all — nothing here records anything"

if [[ -n "$version" && -z "$found_current" ]]; then
  report 1 "VERSION says $version but no release heading records what is in it"
fi

((findings == 0)) || exit 1
