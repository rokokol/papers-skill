#!/usr/bin/env bash
# Decide the machine-checkable half of a changelog. Takes ANY changelog, so it is worth
# more than a review comment: drop it into a repository's own gate and the rules stop
# depending on somebody remembering them. Another repository takes it through the ci
# skill's vendoring cascade (references/bump-cascade.md in https://github.com/rokokol/ci-skill)
# and never edits its copy in place: a fix belongs in rokokol/versioning-skill.
#
#   check-changelog.sh [-v VERSION-FILE | -n] [CHANGELOG]
#
#   -v FILE   the repository's version file (default: VERSION beside the changelog)
#   -n        assert this repository has no version, whatever files are lying around
#
# Options may come before or after the changelog, and there is one changelog per run.
#
# A repository HAS a version when someone can install a particular one and report a bug
# against it. Then its headings are `## [x.y.z]` and an `## Unreleased` section is where
# work waits for the next release. A repository that is only ever read at whatever revision
# is checked out has no version to be wrong about: its headings are dates, and `Unreleased`
# is a state it can never be in, so the section would never close.
#
# Exit: 0 clean, 1 findings printed, 2 a usage error.
# Nothing here reaches the network. Needs bash 3.2 and POSIX tools only.
set -uo pipefail

# The help is the header comment above, whole: it ends where the first non-comment line
# starts, so the text can grow without a line count here going stale
usage() { awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; }

die() {
  printf 'check-changelog: %s\n' "$1" >&2
  exit 2
}

version_file=""
no_version=""
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
    ((10#$x < 10#$y)) && return 0
    ((10#$x > 10#$y)) && return 1
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
      ((10#$x < 10#$y)) && return 0
      ((10#$x > 10#$y)) && return 1
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

findings=0
report() { # report LINE MESSAGE
  printf '%s:%s: %s\n' "$changelog" "$1" "$2"
  findings=$((findings + 1))
}

# Headings, with their line numbers, in the order the file states them. A read loop rather
# than `mapfile`, which is bash 4.0+ — this checker is meant to be dropped into other
# repositories' gates, and macOS ships bash 3.2.
headings=()
while IFS= read -r heading_line; do
  headings+=("$heading_line")
done < <(grep -n '^## ' "$changelog")
# An extractor that finds nothing must say so rather than read as "all clear": a file with
# no headings at all is not a clean changelog, it is an unparsed one
((${#headings[@]} > 0)) || {
  report 1 "no '## ' headings at all — nothing here records anything"
  exit 1
}

seen_dated=""
seen_release=""
prev_date=""
prev_version=""
found_current=""

for entry in "${headings[@]}"; do
  line="${entry%%:*}"
  text="${entry#*:}"
  text="${text#\#\# }"
  text="${text%"${text##*[![:space:]]}"}"

  case "$text" in
    Unreleased | '[Unreleased]')
      if [[ -z "$version" ]]; then
        report "$line" "an Unreleased section in a repository with no version — it holds work that has landed but not shipped, which cannot happen here, so it never closes"
      elif [[ -n "$seen_release" ]]; then
        report "$line" "an Unreleased section below a release — work waiting for the next release goes on top, above everything that has shipped"
      fi
      ;;

    '['*']'*)
      # `## [x.y.z]`, optionally followed by a date
      v="${text#\[}"
      v="${v%%]*}"
      if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
        report "$line" "'$text' is not a version heading — expected ## [x.y.z]"
        continue
      fi
      [[ "$v" == "$version" ]] && found_current=1
      seen_release=1
      if [[ -n "$seen_dated" ]]; then
        report "$line" "a numbered heading above a dated one — dated entries belong on top, where a repository that stopped shipping versions keeps its newer work"
      fi
      if [[ "$v" == "$prev_version" ]]; then
        report "$line" "[$v] appears twice — one heading per release, and the second one's entries belong under the first"
      elif [[ -n "$prev_version" ]]; then
        version_lt "$v" "$prev_version" ||
          report "$line" "[$v] is not older than the [$prev_version] above it — newest first"
      fi
      prev_version="$v"
      ;;

    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      seen_dated=1
      seen_release=1
      if ! real_day "$text"; then
        report "$line" "$text is not a date — the heading has the shape of one, but no such day exists"
        continue
      fi
      if [[ -n "$version" ]]; then
        report "$line" "a dated heading in a repository that ships version $version — a shipped artifact's changelog is numbered, so a reader can match an entry to what they installed"
      fi
      if [[ "$text" == "$prev_date" ]]; then
        report "$line" "$text appears twice — one heading per day, and the second one's entries belong under the first"
      elif [[ -n "$prev_date" && ! "$text" < "$prev_date" ]]; then
        report "$line" "$text is not older than the $prev_date above it — newest first"
      fi
      prev_date="$text"
      ;;

    *) report "$line" "'$text' is neither a version, a date, nor Unreleased" ;;
  esac
done

if [[ -n "$version" && -z "$found_current" ]]; then
  report 1 "VERSION says $version but no '## [$version]' heading records what is in it"
fi

((findings == 0)) || exit 1
