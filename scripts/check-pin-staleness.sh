#!/usr/bin/env bash
# check-pin-staleness.sh — flag run-line tool pins that have fallen behind the
# registry's latest release (issue #67).
#
# WHY: Dependabot covers only the github-actions ecosystem. The scanner pins
# (semgrep/checkov/zizmor) live inside `pip install 'NAME==VER'` run-lines in
# security.yml, and the semantic-release set lives inside `npx -p NAME@VER` in
# release.yml — neither is a requirements/package file Dependabot can see, so
# they drift silently. This turns that drift loud: query PyPI / npm for latest
# and report any pin that is behind. The pins are the single source of truth —
# extracted from the live workflows, never a hand-kept manifest that could itself
# drift.
#
# CONTRACT (exit codes):
#   0 = every tracked pin equals the registry's latest release.
#   1 = one or more pins are behind (a markdown table is printed to STDOUT).
#   2 = setup/network error (unreadable file, 0 pins extracted, or a `latest`
#       lookup that returned no parseable version). Fail-closed: an unresolved
#       lookup is an error, NEVER a silent "fresh" — a bad fetch must never let
#       the workflow close the tracking issue while blind to a package.
#
# STDOUT = the stale-pin table (issue-body material). STDERR = per-pin log.
#
# USAGE:  scripts/check-pin-staleness.sh [--self-test]
# REQUIRES: bash, grep, sed, sort, jq, curl (network for the live run;
#           --self-test is hermetic — no network).
#
# ponytail: string inequality flags "pinned != latest", not "strictly behind".
# A pin AHEAD of the registry's latest stable (a yanked release, a prerelease
# pin) is reported too — correct for a review nudge; upgrade to semver ordering
# only if that ever produces real noise.
#
# shellcheck disable=SC2310,SC2312,SC2329
# SC2310/SC2312 (litmus's curated shellcheck-extra): classify(), latest_pip/latest_npm,
# and extract_*() return their result via STDOUT and tolerate failure by design (`|| true`,
# internal guards), so "set -e disabled in ||" and "command substitution masks the return
# value" are intended patterns here, not latent bugs. SC2329: latest_pip/latest_npm are
# invoked indirectly through "$lookup" in check(), which the linter cannot see.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# --- extraction (pure, hermetic-testable) --------------------------------------------
# Two layers keep a pin that ISN'T an executing command from being read as live:
#   1. The anchoring regex requires the line to be a real invocation — `run:` (block-mapping
#      or `- run:` list item) whose command IS `pip install …` / `npx …`. This alone excludes
#      a comment-only line (`# run: …`), a `;#`-commented command (`run: true;# pip install …`),
#      an unrelated command (`docker run -p host@ver`), and a pin quoted inside an echo
#      (`run: echo "npx -p pkg@1"`): in every case the command right after `run:` is not pip/npx.
#   2. strip_comments then removes any trailing inline comment (a `#` opening a shell comment:
#      preceded by whitespace OR a control operator `; & | ( )`, so both `foo # c` and `foo;# c`)
#      so an obsolete pin quoted AFTER the real command on the same line isn't picked up. A `#`
#      mid-word (inside `'a#b'`) is left alone — pin names/versions never contain `#`.
# If the workflow ever switches to a `run: |` block (pin on a continuation line) the anchor
# matches nothing and main fails closed (exit 2) rather than certifying a false "fresh".
strip_comments() { sed -E 's/[[:space:];&|()]#.*$//'; }

PIP_RUN_RE='^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]+pip[[:space:]]+install([[:space:]]|$)'
NPX_RUN_RE='^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]+npx([[:space:]]|$)'

# Single-quoted 'NAME==VER' on a live `pip install` line → `name|version`. VER must start
# with a digit so a name-only install can't masquerade as a pin.
extract_pip_pins() {
  # `|| true`: a no-match at any grep stage is the normal "no pins here" case, not an
  # error — without it pipefail would make the whole function exit non-zero and abort a
  # `set -e` caller. A genuinely broken regex yields empty too, which main treats as
  # fail-closed (exit 2). Robust at the source so no caller must remember `|| true`.
  { grep -hE "$PIP_RUN_RE" "$@" \
    | strip_comments \
    | grep -oE "'[A-Za-z0-9][A-Za-z0-9._-]*==[0-9][^']*'" \
    | sed -E "s/^'([^=]+)==(.*)'$/\1|\2/" \
    | LC_ALL=C sort -u; } || true
}

# `-p NAME@VER` tokens on a live `npx` line → `name|version`. NAME may be scoped
# (@scope/name); VER must start with a digit, which anchors the split at the version
# `@` and never the scope `@` (so `@semantic-release/changelog@6.0.3` splits correctly
# and a `@latest`-style moving tag is ignored).
extract_npm_pins() {
  # `|| true` for the same reason as extract_pip_pins: no-match is normal, not an error.
  { grep -hE "$NPX_RUN_RE" "$@" \
    | strip_comments \
    | grep -oE '\-p @?[A-Za-z0-9._/-]+@[0-9][A-Za-z0-9._-]*' \
    | sed -E 's/^-p (@?[A-Za-z0-9._/-]+)@([0-9][A-Za-z0-9._-]*)$/\1|\2/' \
    | LC_ALL=C sort -u; } || true
}

# --- classification (pure) -----------------------------------------------------------
# classify PINNED LATEST → prints stale | fresh | error. A LATEST that is not a
# major.minor version (empty, "null", "Not Found") is an error, never "fresh".
classify() {
  local pinned="$1" latest="$2"
  if [[ ! "$latest" =~ ^[0-9]+\.[0-9]+ ]]; then echo error; return; fi
  if [[ "$pinned" == "$latest" ]]; then echo fresh; else echo stale; fi
}

# require_present LABEL PINS NAME... → returns 1 (and logs) if any NAME is missing from
# the extracted `name|version` set. Fail-closed guard so a single tracked line changing
# syntax can't silently drop a package while the others keep the set non-empty.
require_present() {
  local label="$1" pins="$2"; shift 2
  local n
  for n in "$@"; do
    # `name|` — the `|` delimiter anchors the match so `git` can't match `github|`.
    grep -qF -- "$n|" <<< "$pins" || {
      echo "ERROR: expected $label pin '$n' not extracted from its workflow (line syntax changed?) — fail-closed" >&2
      return 1
    }
  done
}

# --- registry lookups (network) ------------------------------------------------------
# Both tolerate failure to empty (|| true) so a dead network becomes an `error`
# classification (exit 2), not an aborted script or a false "fresh".
latest_pip() {
  curl -fsS --max-time 20 "https://pypi.org/pypi/$1/json" 2>/dev/null \
    | jq -r '.info.version // empty' 2>/dev/null || true
}
latest_npm() {
  # Scoped names keep their literal slash — registry.npmjs.org resolves
  # /@scope/name/latest directly.
  curl -fsS --max-time 20 "https://registry.npmjs.org/$1/latest" 2>/dev/null \
    | jq -r '.version // empty' 2>/dev/null || true
}

# --- self-test: fixtures prove extraction + classification, no network ---------------
if [[ "${1:-}" == "--self-test" ]]; then
  tdir=$(mktemp -d); trap 'rm -rf "$tdir"' EXIT
  fail=0

  # Fixtures include adversarial lines that MUST NOT be read as live pins: a commented-out
  # pin (indented and column-0), an obsolete pin quoted in a trailing comment, and — for
  # npm — a non-npx line carrying a `-p host@1.2.3`-style token.
  cat > "$tdir/security.yml" <<'EOF'
      - name: Install semgrep
        run: pip install --quiet 'semgrep==1.170.0'  # was 'semgrep==1.100.0'; lockstep: issue #67
      - name: Install checkov
        run: pip install --quiet 'checkov==3.3.8'  # lockstep: see issue #67
      # old: run: pip install --quiet 'zizmor==0.0.1'
      - name: Install zizmor
        run: pip install --quiet 'zizmor==1.26.1'  # lockstep: see issue #67
#     run: pip install --quiet 'semgrep==9.9.9'
      - name: comment after a shell operator, no space
        run: true;# pip install 'semgrep==8.8.8'
      - name: a pin quoted inside an echo is not an install
        run: echo "pip install 'semgrep==7.7.7'"
      - name: not a pin
        run: pip install --upgrade pip
EOF
  cat > "$tdir/release.yml" <<'EOF'
        run: npx -y -p semantic-release@25.0.6 -p @semantic-release/changelog@6.0.3 -p @semantic-release/exec@7.1.0 -p @semantic-release/git@10.0.1 -p @semantic-release/github@12.0.9 semantic-release
        run: npx -y -p tool@latest do-thing
        # old: run: npx -y -p semantic-release@1.0.0 semantic-release
        run: true;# npx -y -p semantic-release@2.0.0 semantic-release
        run: echo "npx -y -p semantic-release@3.0.0"
        run: docker run -p 9000@1.2.3 someimage
EOF

  pip=$(extract_pip_pins "$tdir/security.yml")
  exp_pip=$'checkov|3.3.8\nsemgrep|1.170.0\nzizmor|1.26.1'
  if [[ "$pip" != "$exp_pip" ]]; then echo "FAIL: pip extraction: got [$pip]"; fail=1; fi
  # phantom versions from comments / commented-out / `;#` / echo lines must be absent
  if grep -qE '1\.100\.0|9\.9\.9|0\.0\.1|8\.8\.8|7\.7\.7' <<< "$pip"; then echo "FAIL: comment/echo-quoted pin extracted"; fail=1; fi

  npm=$(extract_npm_pins "$tdir/release.yml")
  # LC_ALL=C order: after `git`, `github`'s `h` (0x68) sorts before `git`'s `|` (0x7C).
  exp_npm=$'@semantic-release/changelog|6.0.3\n@semantic-release/exec|7.1.0\n@semantic-release/github|12.0.9\n@semantic-release/git|10.0.1\nsemantic-release|25.0.6'
  if [[ "$npm" != "$exp_npm" ]]; then echo "FAIL: npm extraction: got [$npm]"; fail=1; fi
  # the moving `@latest` tag, commented/`;#`/echo pins, and a non-npx `-p host@ver`: absent
  if grep -q '^tool|' <<< "$npm"; then echo "FAIL: moving @latest tag extracted as a pin"; fail=1; fi
  if grep -qE 'semantic-release\|(1|2|3)\.0\.0|9000' <<< "$npm"; then echo "FAIL: comment/echo/non-npx token extracted"; fail=1; fi

  # --- property coverage: comment delimiters × command placement (parser change) -------
  # Combinatorial, not just fixed examples: for every shell-comment delimiter, a real pin
  # followed by a phantom pin in the trailing comment must yield ONLY the real pin; and a
  # pin appearing in any NON-command context (echo, comment-only, unrelated command) must
  # yield nothing. q dodges nested-single-quote hell.
  q="'"
  for delim in " #" ";#" "&&#" "|#" "  #" $'\t#'; do
    printf "        run: pip install --quiet %srealpkg==1.2.3%s%s pip install %sfoo==9.9.9%s\n" \
      "$q" "$q" "$delim" "$q" "$q" > "$tdir/prop.yml"
    got=$(extract_pip_pins "$tdir/prop.yml")
    [[ "$got" == "realpkg|1.2.3" ]] || { echo "FAIL: prop pip delim [$delim] -> [$got]"; fail=1; }
    printf "        run: npx -y -p realpkg@1.2.3%s npx -p foo@9.9.9\n" "$delim" > "$tdir/prop.yml"
    got=$(extract_npm_pins "$tdir/prop.yml")
    [[ "$got" == "realpkg|1.2.3" ]] || { echo "FAIL: prop npm delim [$delim] -> [$got]"; fail=1; }
  done
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf '%s\n' "$line" > "$tdir/prop.yml"
    p=$(extract_pip_pins "$tdir/prop.yml"); n=$(extract_npm_pins "$tdir/prop.yml")
    [[ -z "$p$n" ]] || { echo "FAIL: non-command line yielded [$p$n]: $line"; fail=1; }
  done <<PROP
        run: echo "pip install ${q}foo==9.9.9${q}"
        run: echo "npx -p foo@9.9.9"
      # run: pip install ${q}foo==9.9.9${q} -p foo@9.9.9
        run: docker run pip install ${q}foo==9.9.9${q} -p foo@9.9.9
PROP

  [[ "$(classify 1.0.0 1.1.0)" == stale ]] || { echo "FAIL: behind not stale"; fail=1; }
  [[ "$(classify 1.0.0 1.0.0)" == fresh ]] || { echo "FAIL: equal not fresh"; fail=1; }
  [[ "$(classify 1.0.0 '')" == error ]]    || { echo "FAIL: empty latest not error"; fail=1; }
  [[ "$(classify 1.0.0 'Not Found')" == error ]] || { echo "FAIL: junk latest not error"; fail=1; }
  # a pin AHEAD of latest is still flagged (review nudge, not a strict-behind check)
  [[ "$(classify 2.0.0 1.9.0)" == stale ]] || { echo "FAIL: ahead-of-latest not flagged"; fail=1; }

  # empty input → no pins (main's caller fails closed on this)
  : > "$tdir/empty.yml"
  [[ -z "$(extract_pip_pins "$tdir/empty.yml")" ]] || { echo "FAIL: empty file yielded pins"; fail=1; }

  # require_present: all-present passes; a missing package fails closed. `git` must not be
  # satisfied by `github|` (the `|` anchor). Guards the silent-drop case where one tracked
  # line changes syntax but the others keep the set non-empty.
  require_present pip "$exp_pip" semgrep checkov zizmor || { echo "FAIL: require_present false-negative"; fail=1; }
  require_present npm "$exp_npm" @semantic-release/git @semantic-release/github || { echo "FAIL: git/github prefix mismatch"; fail=1; }
  if require_present pip $'semgrep|1.0\nzizmor|1.0' semgrep checkov zizmor 2>/dev/null; then
    echo "FAIL: require_present missed a dropped package"; fail=1
  fi

  if [[ "$fail" -eq 0 ]]; then echo "self-test: PASS"; exit 0; else echo "self-test: FAIL"; exit 1; fi
fi

# --- main ----------------------------------------------------------------------------
SECURITY_YML="$REPO_ROOT/.github/workflows/security.yml"
RELEASE_YML="$REPO_ROOT/.github/workflows/release.yml"
for f in "$SECURITY_YML" "$RELEASE_YML"; do
  [[ -r "$f" ]] || { echo "ERROR: cannot read $f (fail-closed)" >&2; exit 2; }
done

pip_pins=$(extract_pip_pins "$SECURITY_YML" || true)
npm_pins=$(extract_npm_pins "$RELEASE_YML" || true)

# Fail-closed: 0 pins from either side means the run-line format changed and the regex
# no longer matches — never certify "all fresh" off an empty extraction.
if [[ -z "$pip_pins" ]]; then echo "ERROR: extracted 0 pip pins from $SECURITY_YML (format changed?)" >&2; exit 2; fi
if [[ -z "$npm_pins" ]]; then echo "ERROR: extracted 0 npm pins from $RELEASE_YML (format changed?)" >&2; exit 2; fi

# Fail-closed per-package: a non-empty extraction is not enough — if ONE tracked line
# changes syntax (e.g. checkov switches to double quotes) the others keep the set
# non-empty and that package would be silently untracked, letting the sweep report fresh
# and close the issue while blind to it. Assert every package in the issue #67 contract
# is present. Names, not versions — adding/removing a scanner means updating this list
# (a removal fails loudly here, which is the point).
require_present pip "$pip_pins" semgrep checkov zizmor || exit 2
require_present npm "$npm_pins" \
  semantic-release @semantic-release/changelog @semantic-release/exec \
  @semantic-release/git @semantic-release/github || exit 2

stale_rows=()
error=0

check() {  # ECOSYSTEM  PINS  LOOKUP_FN
  local eco="$1" pins="$2" lookup="$3" name ver latest
  while IFS='|' read -r name ver; do
    [[ -n "$name" ]] || continue
    latest=$("$lookup" "$name")
    case "$(classify "$ver" "$latest")" in
      stale) stale_rows+=("$eco|$name|$ver|$latest"); echo "STALE  $eco $name $ver -> $latest" >&2 ;;
      fresh) echo "fresh  $eco $name $ver" >&2 ;;
      error) echo "::error::could not resolve latest $eco version for '$name' (got '$latest')" >&2; error=1 ;;
    esac
  done <<< "$pins"
}

check pip "$pip_pins" latest_pip
check npm "$npm_pins" latest_npm

# A broken lookup dominates: exit 2 rather than let the workflow act on a partial
# verdict (it must not close the tracking issue while blind to a package).
if [[ "$error" -ne 0 ]]; then
  echo "ERROR: one or more registry lookups failed — not emitting a staleness verdict" >&2
  exit 2
fi

if [[ "${#stale_rows[@]}" -eq 0 ]]; then
  echo "All tracked pins are at the latest release." >&2
  exit 0
fi

{
  echo "| ecosystem | package | pinned | latest |"
  echo "|-----------|---------|--------|--------|"
  for row in "${stale_rows[@]}"; do
    IFS='|' read -r eco name ver latest <<< "$row"
    # shellcheck disable=SC2016  # literal backticks — markdown code span in the issue body
    printf '| %s | `%s` | %s | %s |\n' "$eco" "$name" "$ver" "$latest"
  done
}
exit 1
