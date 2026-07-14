#!/usr/bin/env bash
# check-template-pins.sh — fail-closed parity check between the SKILL.md embedded
# workflow template and helmet's own live .github/workflows.
#
# WHY: skills/helmet/SKILL.md embeds a *copy* of the CI workflows as the template
# helmet installs into consumer repos. Dependabot + pinact bump the live workflows'
# action SHAs, but nothing updates the hand-maintained SKILL.md copy — so the template
# silently drifts behind (the 2026-07-10 audit found harden-runner, checkout, setup-node,
# and pinact all lagging, pinact by a full major). This turns that drift loud: every
# action pinned in BOTH must carry the same SHA + version comment.
#
# CONTRACT:
#   - DRIFT (fails, exit 1): an action pinned in both SKILL.md and a live workflow at a
#     different `<sha> # vX.Y.Z`. Catches SHA lag AND mislabeled version comments.
#   - template-only actions (setup-go/python, codecov, sbom, rust-cache, …): consumer-
#     language variants with no helmet-live counterpart — reported as info, never fail.
#   - live-only actions (in a live workflow, absent from the template): WARN, never fail
#     (may be helmet-repo-specific; failing would create false positives).
#     # ponytail: parity is enforced only on the intersection; widen to require template
#     # completeness if a real "template forgot an action" bug ever ships.
#
# USAGE:  scripts/check-template-pins.sh [--self-test]
# EXIT:   0 = parity; 1 = drift; 2 = setup/extraction error (fail-closed).
# REQUIRES: bash, grep, sed, sort, join, awk (no network, no gh).
set -euo pipefail

# Pin one collation for the whole pipeline: sort(1) and join(1) MUST agree on order,
# or join silently finds no matches and every pin looks unpaired (false parity).
export LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Extract `owner/repo@<40-hex> # vX.Y.Z` pins → `action|sha|version`, sorted-unique.
# Sort on field 1 (the action) as the PRIMARY key so ordering matches what join(1)
# expects. A whole-line `sort -u` would diverge from field-1 order when one action
# name is a prefix of another (`foo/bar` vs `foo/bar-baz`: `-` 0x2D < `|` 0x7C), which
# makes join silently miss the pair and report false parity (fail-open). `-k2` keeps
# the sha+version as a secondary key so `-u` still dedupes whole lines and distinct
# pins for the same action survive (the conflict check below relies on that).
# A FULLY well-formed pinned-action line, anchored from the `uses:` KEY so validation
# targets the parsed VALUE, not "anywhere on the line". This is the SINGLE contract used
# by BOTH extract() (parity capture) and malformed() (fail-closed), so they can never
# disagree on what "valid" means. It defeats a fake pin planted in a trailing comment
# (`@main # actions/x@<40-hex> # v1.0.0` can't launder an unpinned ref), accepts a quoted
# value (`uses: "a/b@<40-hex>" # v1.2.3`) and flexible whitespace, and rejects 4-part
# `# v1.2.3.4` / pre-release `# v1.2.3-beta` via the trailing ws/EOL boundary.
# SCOPE: block-mapping `[- ]uses:` lines — the ONLY form helmet's workflows and the
# SKILL.md template use, matching .github/scripts/check-pinned-uses.sh (the repo's
# canonical SHA-pin gate). Flow-style `{ uses: … }` is out of scope for both.
# The value is `<action>@<40-hex>`, either double-quoted, single-quoted, or unquoted —
# each a BALANCED alternative so an unbalanced trailing quote (`@<40-hex>'`, a mutable
# ref) cannot pass. Followed by a ` # vX.Y.Z` comment ending at whitespace/EOL.
WELLFORMED_RE="^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*(\"[^\"@[:space:]]+@[0-9a-f]{40}\"|'[^'@[:space:]]+@[0-9a-f]{40}'|[^\"'@[:space:]]+@[0-9a-f]{40})[[:space:]]+#[[:space:]]+v[0-9]+\.[0-9]+\.[0-9]+([[:space:]]|$)"

extract() {
  grep -hE "$WELLFORMED_RE" "$@" \
    | sed -nE "s/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[\"']?([^\"'@[:space:]]+)@([0-9a-f]{40})[\"']?[[:space:]]+#[[:space:]]+v([0-9]+\.[0-9]+\.[0-9]+).*/\2|\3|\4/p" \
    | LC_ALL=C sort -t'|' -k1,1 -k2 -u
}

# `uses:` lines pinning a ref (`uses: <token>@<token>`) that is NOT a well-formed
# `<40-hex> # vX.Y.Z` pin — a tag/branch ref (`@v6`, `@main`) OR a malformed/absent
# version comment (`# stable`). extract() silently drops all of these. The `<token>@<token>`
# selector mirrors check-pinned-uses.sh, so quoted (`uses: "a/b@x"`) and subpath
# (`a/b/c@x`) refs are covered; local `uses: ./…` and `docker://…` (no `@`) are not.
malformed() {
  # selector allows an optional YAML `&anchor` before the value so an anchored ref
  # (`uses: &x actions/checkout@v6`) is still SELECTED — and, since WELLFORMED_RE has no
  # anchor branch, always flagged (fail-closed). docker:// digest refs are exempt.
  grep -hE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*(&[^[:space:]]+[[:space:]]+)?[^[:space:]]+@[^[:space:]]*' "$@" \
    | grep -vE "^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*(&[^[:space:]]+[[:space:]]+)?[\"']?docker://" \
    | grep -vE "$WELLFORMED_RE" || true
}

# Live actions whose SKILL.md `uses:` occurrence is NOT a well-formed `<40-hex> # vX.Y.Z`
# pin — a malformed/absent version comment OR a regression to a tag/branch ref (`@v6`).
# Args: LIVE_PINS_FILE SKILL_FILE. Prints offending action names; empty = all good.
bad_shared_pins() {
  local live_f="$1" skill_f="$2" skill_bad
  # Action names of SKILL.md `uses:` lines that are NOT well-formed pins (reuses
  # malformed(), so all its YAML robustness applies). Intersect with live action names
  # via grep -F (fixed strings — no ERE interpolation of the action, so a name with
  # regex metacharacters can't dodge the match). Template-only actions fall out of the
  # intersection, so their legitimately-non-semver refs don't false-fail.
  skill_bad=$(malformed "$skill_f" \
    | sed -nE "s/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*(&[^[:space:]]+[[:space:]]+)?[\"']?([^\"'@[:space:]]+)@.*/\3/p" \
    | LC_ALL=C sort -u)
  [[ -z "$skill_bad" ]] && return 0
  printf '%s\n' "$skill_bad" | grep -Fxf <(cut -d'|' -f1 "$live_f") || true
}

# report LIVE_PINS SKILL_PINS  → prints findings; returns 0 parity / 1 drift / 2 error.
report() {
  local live_f="$1" skill_f="$2"

  # Fail-closed: if either side yielded no pins, the regex/format broke — do not
  # certify parity off two empty sets.
  if [[ ! -s "$live_f" || ! -s "$skill_f" ]]; then
    echo "ERROR: extracted 0 pins from one side (regex/format broke?) — refusing to certify parity" >&2
    return 2
  fi

  # Fail-closed: a single action pinned at 2+ SHAs within one source makes parity
  # undecidable (each file is sort -u, so a repeated action key = conflicting pin).
  local dup_live dup_skill
  dup_live=$(cut -d'|' -f1 "$live_f" | uniq -d)
  dup_skill=$(cut -d'|' -f1 "$skill_f" | uniq -d)
  if [[ -n "$dup_live" || -n "$dup_skill" ]]; then
    echo "ERROR: an action is pinned at conflicting SHAs within one source (parity undecidable):" >&2
    if [[ -n "$dup_live"  ]]; then echo "  live:     $dup_live" >&2; fi
    if [[ -n "$dup_skill" ]]; then echo "  SKILL.md: $dup_skill" >&2; fi
    return 2
  fi

  local drift tmpl_only live_only
  drift=$(join -t'|' -j 1 "$live_f" "$skill_f" \
    | awk -F'|' '$2"|"$3 != $4"|"$5 {
        printf "DRIFT    %-32s live v%s (%s…)  vs  SKILL.md v%s (%s…)\n", $1, $3, substr($2,1,7), $5, substr($4,1,7) }')
  live_only=$(join -t'|' -j 1 -v 1 "$live_f" "$skill_f" | awk -F'|' '{printf "  %-32s v%s\n",$1,$3}')
  tmpl_only=$(join -t'|' -j 1 -v 2 "$live_f" "$skill_f" | awk -F'|' '{printf "  %-32s v%s\n",$1,$3}')

  local rc=0
  if [[ -n "$drift" ]]; then
    echo "$drift"
    rc=1
  else
    echo "PARITY   all shared action pins match between SKILL.md and live workflows."
  fi
  if [[ -n "$live_only" ]]; then
    echo
    echo "WARN: live workflow actions absent from the SKILL.md template (not failed):"
    echo "$live_only"
  fi
  if [[ -n "$tmpl_only" ]]; then
    echo
    echo "info: template-only actions (consumer-language variants, no live counterpart):"
    echo "$tmpl_only"
  fi
  return "$rc"
}

# --- whole-document content parity (issue #66) ---------------------------------------
# The pin check above compares ONLY `uses:` SHA pins. It is blind to drift in the GATING
# LOGIC — `if:` / `needs:` / triggers / `paths:` / run-block wording — between live
# security.yml and the SKILL.md Section N fenced template (the copy helmet installs into
# consumers). Those two are maintained BYTE-IDENTICAL except one sanctioned divergence — the
# zizmor invocation (helmet dogfoods the strict all-severity gate via `--config .zizmor.yml`;
# the template ships the consumer `--min-severity high --min-confidence high` default). That
# single line is collapsed to a sentinel and everything else is compared verbatim, so ANY
# other drift is caught — with NO YAML/shell parsing that adversarial input could fool.
ZIZMOR_SENTINEL='SENTINEL_RUN_ZIZMOR_INVOCATION'

# Extract the single ```yaml fenced block inside "#### N. Security Scanning Backstop",
# bounded by the next "**Required file:**" line OR the next "#### " heading. awk exits 3
# if the region holds anything other than EXACTLY one such block (0 or >1) — fail-closed.
extract_section_n_block() {
  awk '
    /^#### N\. Security Scanning Backstop/ { inN=1; next }
    inN && (/^\*\*Required file:\*\*/ || /^#### /) { inN=0 }
    inN && /^```yaml[[:space:]]*$/ && !fence { fence=1; nb++; next }
    inN && fence && /^```[[:space:]]*$/ { fence=0; next }
    inN && fence { print }
    # Fail-closed on 0/>1 blocks OR an UNCLOSED fence (fence left open at EOF/region end).
    END { if (nb != 1 || fence != 0) exit 3 }
  ' "$1"
}

# Normalize a workflow document for whole-document comparison (reads stdin). Live security.yml
# and the SKILL.md Section N template are kept BYTE-IDENTICAL except the sanctioned zizmor
# divergence, so the only normalization needed is to collapse that one line to a sentinel;
# everything else — comments included — already compares equal. (Command substitution at the
# call site also strips trailing newlines, so a difference of trailing blank lines alone is
# ignored — benign: blank lines carry no gating logic.)
# TWO substitutions, one per zizmor variant — NOT a `(a|b)` alternation: BSD and GNU sed
# disagree on `\|`, and a broken alternation would silently fail to collapse and read a CLEAN
# tree as drift (a false positive that blocks every PR). Each is ANCHORED to a WHOLE run-command
# line (`^<ws>(- )?run: zizmor … <ws>$`) and collapses ONLY the command text to the sentinel,
# PRESERVING the matched `<indent>(- )?run: ` prefix via a backreference. So (a) a decoy that
# merely embeds the `run: zizmor …` substring in a larger scalar, comment, or quoted string
# cannot manufacture the sentinel the count guard expects, and (b) a STRUCTURAL move of the step
# (indentation change, list-item `- run:` vs block-mapping `run:`) still differs after
# normalization and is caught as drift. Any zizmor invocation OTHER than the two sanctioned
# variants fails to match → 0 sentinels → the count guard below fails closed.
# Deliberately does NO comment/quote/heredoc/block-scalar handling. Because the two documents
# are byte-identical there is nothing to strip — which is precisely why this check needs no
# YAML/shell parser and cannot be fooled by adversarial comment constructs (multiline quoted
# strings with `#`, `|2-` block indicators, folded scalars, …). The cost: a comment edited on
# only one side reads as drift. That is intended — the installed template must stay in lockstep
# with live, comments and all; the check tells you exactly what to re-sync.
normalize_doc() {
  sed -E "s@^([[:space:]]*(-[[:space:]]+)?run: )zizmor --config \\.zizmor\\.yml \\.github/workflows/[[:space:]]*\$@\\1${ZIZMOR_SENTINEL}@" \
    | sed -E "s@^([[:space:]]*(-[[:space:]]+)?run: )zizmor --min-severity high --min-confidence high \\.github/workflows/[[:space:]]*\$@\\1${ZIZMOR_SENTINEL}@"
}

# content_hash_check LIVE_SECURITY_YML SKILL_MD
#   0 = content parity;  1 = drift;  2 = setup/format error (fail-closed).
content_hash_check() {
  local live_f="$1" skill_f="$2" blk lrc=0 live_n tmpl_n ls ts
  [[ -r "$live_f"  ]] || { echo "ERROR: cannot read $live_f (fail-closed)"  >&2; return 2; }
  [[ -r "$skill_f" ]] || { echo "ERROR: cannot read $skill_f (fail-closed)" >&2; return 2; }

  blk=$(extract_section_n_block "$skill_f") || lrc=$?
  if [[ "$lrc" -ne 0 ]]; then
    echo "ERROR: Section N must hold exactly one \`\`\`yaml block in $skill_f (found 0 or >1) — fail-closed" >&2
    return 2
  fi
  [[ -n "$blk" ]] || { echo "ERROR: extracted an empty Section N template — fail-closed" >&2; return 2; }

  # Reserved-token guard: the sentinel is a synthetic internal token that must NEVER appear
  # literally in a real workflow/template. If it did, a planted `run: <SENTINEL>` line would
  # already carry the sentinel BEFORE substitution — colluding with the real command's collapse
  # to fake the per-side count of 1 and let a broken Section N compare equal. Fail closed on any
  # literal occurrence in either raw source (grep -F: fixed string, not a regex).
  # Capture grep's exit EXPLICITLY rather than `if`-testing a pipe: under `set -o pipefail` a
  # `printf | grep -q` writer can take SIGPIPE when grep short-circuits on a match, making the
  # pipeline nonzero and reading a real hit as a MISS (fail-OPEN). A here-string has no writer to
  # signal; and treating any non-1 exit (0 = found, ≥2 = grep read error) as "present or
  # unverifiable" keeps it fail-closed. `$live_f` is pre-checked readable; `-F` has no regex.
  local live_tok=0 tmpl_tok=0
  grep -qF "$ZIZMOR_SENTINEL" "$live_f"  || live_tok=$?
  grep -qF "$ZIZMOR_SENTINEL" <<< "$blk" || tmpl_tok=$?
  if [[ "$live_tok" != 1 || "$tmpl_tok" != 1 ]]; then
    echo "ERROR: reserved sentinel token '$ZIZMOR_SENTINEL' present or unverifiable in a source document — fail-closed" >&2
    return 2
  fi

  live_n=$(normalize_doc < "$live_f")
  tmpl_n=$(printf '%s\n' "$blk" | normalize_doc)
  [[ -n "$live_n" && -n "$tmpl_n" ]] || { echo "ERROR: a normalized document is empty (normalization broke) — fail-closed" >&2; return 2; }

  # The allowlist has exactly one entry, so its sentinel MUST appear exactly once per
  # side — 0 (line changed/removed) or >1 (duplicated) makes parity undecidable → fail-closed.
  # This is a SECONDARY guard: the whole-document compare below is primary, so relocating the
  # real zizmor step (or planting a decoy `run: zizmor …` elsewhere) still changes the
  # document and drifts the compare — the sentinel count alone cannot launder that.
  # Count sentinel OCCURRENCES, not matching lines: `grep -c` counts lines, so two sentinels
  # on one line would read as 1 and slip past the ">1" guard. gsub(s,s) returns the count.
  ls=$(printf '%s\n' "$live_n" | awk -v s="$ZIZMOR_SENTINEL" '{n+=gsub(s,s)} END{print n+0}')
  ts=$(printf '%s\n' "$tmpl_n" | awk -v s="$ZIZMOR_SENTINEL" '{n+=gsub(s,s)} END{print n+0}')
  if [[ "$ls" -ne 1 || "$ts" -ne 1 ]]; then
    echo "ERROR: RUN_ZIZMOR_INVOCATION sentinel count must be exactly 1 per side (live=$ls template=$ts) — fail-closed" >&2
    return 2
  fi

  if [[ "$live_n" == "$tmpl_n" ]]; then
    echo "PARITY   live security.yml ≡ SKILL.md Section N template (whole-document, normalized)."
    return 0
  fi
  echo "DRIFT    live security.yml and the SKILL.md Section N template diverge beyond the shared allowlist:" >&2
  diff <(printf '%s\n' "$live_n") <(printf '%s\n' "$tmpl_n") | sed 's/^/  /' >&2
  return 1
}

# --- self-test: crafted fixtures prove drift is caught and parity passes -------------
if [[ "${1:-}" == "--self-test" ]]; then
  tdir=$(mktemp -d)
  trap 'rm -rf "$tdir"' EXIT
  # Includes a prefix pair (actions/setup vs actions/setup-node) to guard the field-1
  # sort: a whole-line sort would mis-order these and make join miss the match.
  cat > "$tdir/live.yml" <<'EOF'
      - uses: actions/checkout@1111111111111111111111111111111111111111 # v6.0.3
      - uses: step-security/harden-runner@2222222222222222222222222222222222222222 # v2.19.4
      - uses: actions/setup@4444444444444444444444444444444444444444 # v1.0.0
      - uses: actions/setup-node@5555555555555555555555555555555555555555 # v6.4.0
EOF
  # SKILL.md side: checkout SHA/version lags; harden-runner matches; codecov is template-only.
  cat > "$tdir/skill.md" <<'EOF'
  uses: actions/checkout@9999999999999999999999999999999999999999 # v6.0.2
  uses: step-security/harden-runner@2222222222222222222222222222222222222222 # v2.19.4
  uses: codecov/codecov-action@3333333333333333333333333333333333333333 # v5.5.3
EOF
  lf=$(mktemp); sf=$(mktemp)
  extract "$tdir/live.yml" > "$lf" || true
  extract "$tdir/skill.md" > "$sf" || true
  out=$(report "$lf" "$sf") && rc=0 || rc=$?

  fail=0
  if [[ "$rc" -ne 1 ]]; then echo "FAIL: expected drift exit 1, got $rc"; fail=1; fi
  if ! echo "$out" | grep -q 'DRIFT .*actions/checkout'; then echo "FAIL: checkout drift not reported"; fail=1; fi
  if echo "$out" | grep 'DRIFT' | grep -q 'harden-runner'; then echo "FAIL: harden-runner falsely flagged as drift"; fail=1; fi
  if ! echo "$out" | grep -q 'codecov/codecov-action'; then echo "FAIL: template-only codecov not listed"; fail=1; fi

  # parity case: identical inputs must pass clean.
  extract "$tdir/live.yml" > "$lf" || true
  extract "$tdir/live.yml" > "$sf" || true
  out2=$(report "$lf" "$sf") && rc2=0 || rc2=$?
  if [[ "$rc2" -ne 0 ]]; then echo "FAIL: expected parity exit 0, got $rc2"; fail=1; fi
  if ! echo "$out2" | grep -q 'PARITY'; then echo "FAIL: parity not reported"; fail=1; fi
  # Identical inputs (incl. the prefix pair) must pair fully — no unpaired actions.
  if echo "$out2" | grep -qE 'WARN|^info'; then echo "FAIL: prefix pair left unpaired (field-1 sort regressed)"; fail=1; fi

  # empty-input case: must fail closed (exit 2), never certify parity.
  : > "$lf"; : > "$sf"
  report "$lf" "$sf" >/dev/null 2>&1 && rc3=0 || rc3=$?
  if [[ "$rc3" -ne 2 ]]; then echo "FAIL: expected fail-closed exit 2 on empty input, got $rc3"; fail=1; fi

  # malformed-pin detection: a SHA pin without a well-formed `# vX.Y.Z` is flagged;
  # a well-formed one is not.
  printf '  uses: foo/bar@%040d # stable\n' 0 > "$tdir/bad.yml"
  printf '  uses: foo/bar@%040d # v1.2.3\n' 0 > "$tdir/good.yml"
  if [[ -z "$(malformed "$tdir/bad.yml")" ]]; then echo "FAIL: malformed pin not flagged"; fail=1; fi
  if [[ -n "$(malformed "$tdir/good.yml")" ]]; then echo "FAIL: well-formed pin wrongly flagged"; fail=1; fi

  # a live action tag/branch-regressed (or malformed) in SKILL.md is flagged; clean isn't.
  printf 'actions/checkout|df4|6.0.3\n' > "$tdir/live2"
  printf '  uses: actions/checkout@v6\n' > "$tdir/skill_tag"
  printf '  uses: actions/checkout@%040d # v6.0.3\n' 0 > "$tdir/skill_ok"
  if [[ -z "$(bad_shared_pins "$tdir/live2" "$tdir/skill_tag")" ]]; then echo "FAIL: tag-pinned live action not flagged"; fail=1; fi
  if [[ -n "$(bad_shared_pins "$tdir/live2" "$tdir/skill_ok")" ]]; then echo "FAIL: well-formed shared pin wrongly flagged"; fail=1; fi

  # --- content-hash parity fixtures (issue #66) ---------------------------------------
  # A minimal live/template pair kept BYTE-IDENTICAL except the sanctioned zizmor divergence
  # (--config vs --min-severity). Base case must PASS; each mutation of ANY other content —
  # if/needs/paths/uses/run-wording, OR a comment — must fail. No heredoc/quote/block-scalar
  # fixtures: the normalizer no longer inspects content, so those constructs are compared
  # verbatim like every other line rather than parsed.
  chd="$tdir/ch"; mkdir -p "$chd"
  cat > "$chd/live.yml" <<'EOF'
on:
  push:
    paths:
      - '**/*.py'
jobs:
  zizmor:
    needs: [changes]
    if: always()
    steps:
      - uses: actions/checkout@1111111111111111111111111111111111111111 # v1.0.0
      - run: echo "## report"
      - run: echo "a # b"
      - run: |
          echo start
          # inner comment
          echo done
      - run: zizmor --config .zizmor.yml .github/workflows/
EOF
  cat > "$chd/skill.md" <<'EOF'
#### N. Security Scanning Backstop

```yaml
on:
  push:
    paths:
      - '**/*.py'
jobs:
  zizmor:
    needs: [changes]
    if: always()
    steps:
      - uses: actions/checkout@1111111111111111111111111111111111111111 # v1.0.0
      - run: echo "## report"
      - run: echo "a # b"
      - run: |
          echo start
          # inner comment
          echo done
      - run: zizmor --min-severity high --min-confidence high .github/workflows/
```
**Required file:** x
EOF
  bl="$chd/live.yml"; bs="$chd/skill.md"
  # set -e-safe runner: capture rc without aborting on the (expected) non-zero.
  chk() { local r=0; content_hash_check "$1" "$2" >/dev/null 2>&1 || r=$?; printf '%s' "$r"; }

  # base: identical after the zizmor sentinel collapse → parity (0)
  if [[ "$(chk "$bl" "$bs")" != "0" ]]; then echo "FAIL: content base case not parity"; fail=1; fi
  # 1. if: edit → drift (1)
  sed -E 's/if: always\(\)/if: never()/' "$bs" > "$chd/m_if"
  if [[ "$(chk "$bl" "$chd/m_if")" != "1" ]]; then echo "FAIL: if: drift not caught"; fail=1; fi
  # 2. needs: edit → drift (1)
  sed -E 's/needs: \[changes\]/needs: [changes, foo]/' "$bs" > "$chd/m_needs"
  if [[ "$(chk "$bl" "$chd/m_needs")" != "1" ]]; then echo "FAIL: needs: drift not caught"; fail=1; fi
  # 3. trigger/paths edit → drift (1)
  sed -E "s@\\*\\*/\\*\\.py@**/*.js@" "$bs" > "$chd/m_paths"
  if [[ "$(chk "$bl" "$chd/m_paths")" != "1" ]]; then echo "FAIL: paths drift not caught"; fail=1; fi
  # 4. uses: SHA edit → drift (1)
  sed -E 's/checkout@1111111111111111111111111111111111111111/checkout@2222222222222222222222222222222222222222/' "$bs" > "$chd/m_uses"
  if [[ "$(chk "$bl" "$chd/m_uses")" != "1" ]]; then echo "FAIL: uses: drift not caught"; fail=1; fi
  # 5. run-block wording edit → drift (1)
  sed -E 's/echo "## report"/echo "## changed"/' "$bs" > "$chd/m_word"
  if [[ "$(chk "$bl" "$chd/m_word")" != "1" ]]; then echo "FAIL: wording drift not caught"; fail=1; fi
  # 6. duplicate sentinel line → undecidable → fail-closed (2)
  awk '1; /zizmor --min-severity/{print "      - run: zizmor --min-severity high --min-confidence high .github/workflows/"}' "$bs" > "$chd/m_dup"
  if [[ "$(chk "$bl" "$chd/m_dup")" != "2" ]]; then echo "FAIL: duplicate sentinel not fail-closed"; fail=1; fi
  # 7. missing sentinel (zizmor line changed shape) → fail-closed (2)
  sed -E 's@zizmor --min-severity high --min-confidence high .github/workflows/@zizmor --other@' "$bs" > "$chd/m_miss"
  if [[ "$(chk "$bl" "$chd/m_miss")" != "2" ]]; then echo "FAIL: missing sentinel not fail-closed"; fail=1; fi
  # 8. extra non-allowlisted line on one side → drift (1)
  awk '1; /echo "## report"/{print "      - run: echo extra"}' "$bs" > "$chd/m_extra"
  if [[ "$(chk "$bl" "$chd/m_extra")" != "1" ]]; then echo "FAIL: extra divergence not caught"; fail=1; fi
  # 9. two ```yaml blocks in Section N → fail-closed (2)
  awk 'BEGIN{d=0} {print} /^```$/ && d==0 {print ""; print "```yaml"; print "extra: block"; print "```"; d=1}' "$bs" > "$chd/m_2blk"
  if [[ "$(chk "$bl" "$chd/m_2blk")" != "2" ]]; then echo "FAIL: two fenced blocks not fail-closed"; fail=1; fi
  # 10. an EXECUTABLE line inside a `run: |` block IS compared — a change must drift (1).
  sed -E 's/echo start/echo begin/' "$bs" > "$chd/m_bsexec"
  if [[ "$(chk "$bl" "$chd/m_bsexec")" != "1" ]]; then echo "FAIL: block-scalar executable drift not caught"; fail=1; fi
  # 11. a comment edited on ONE side now drifts (1). The two documents are kept byte-identical,
  #     so comments are compared verbatim, not stripped — the intended tradeoff of the
  #     parser-free design: the installed template must track live's comments too.
  sed -E 's/# inner comment/# changed/' "$bs" > "$chd/m_cmt"
  if [[ "$(chk "$bl" "$chd/m_cmt")" != "1" ]]; then echo "FAIL: one-sided comment edit should drift"; fail=1; fi
  # 12. a STRUCTURAL move of the zizmor step (list-item `- run:` → block-mapping `run:` at a
  #     different indent) must drift (1): the sentinel substitution preserves the `<ws>(- )?run: `
  #     prefix, so only the command text collapses and a prefix change is still compared.
  sed -E 's@^      - run: zizmor --min-severity@        run: zizmor --min-severity@' "$bs" > "$chd/m_struct"
  if [[ "$(chk "$bl" "$chd/m_struct")" != "1" ]]; then echo "FAIL: structural move of zizmor step not caught"; fail=1; fi
  # 13. the reserved sentinel token planted LITERALLY in a source (here the template) → fail-closed
  #     (2): it would otherwise pre-load a sentinel and collude with the live command's collapse
  #     to fake the per-side count and launder a broken step.
  sed -E "s@- run: zizmor --min-severity high --min-confidence high .github/workflows/@- run: ${ZIZMOR_SENTINEL}@" "$bs" > "$chd/m_planted"
  if [[ "$(chk "$bl" "$chd/m_planted")" != "2" ]]; then echo "FAIL: planted literal sentinel not fail-closed"; fail=1; fi

  rm -f "$lf" "$sf"
  if [[ "$fail" -eq 0 ]]; then echo "self-test: PASS"; exit 0; else echo "self-test: FAIL"; exit 1; fi
fi

# --- main ----------------------------------------------------------------------------
SKILL="$REPO_ROOT/skills/helmet/SKILL.md"
WF_DIR="$REPO_ROOT/.github/workflows"
if [[ ! -f "$SKILL" ]]; then echo "ERROR: not found: $SKILL" >&2; exit 2; fi
if [[ ! -d "$WF_DIR" ]]; then echo "ERROR: not found: $WF_DIR" >&2; exit 2; fi

# GitHub runs BOTH .yml and .yaml workflows — cover both, or a tag/stale pin could hide
# in a .yaml file outside this check. nullglob so a missing extension doesn't leave a
# literal glob; an empty set is a setup error (fail-closed).
shopt -s nullglob
wf_files=("$WF_DIR"/*.yml "$WF_DIR"/*.yaml)
shopt -u nullglob
if [[ ${#wf_files[@]} -eq 0 ]]; then echo "ERROR: no workflow files in $WF_DIR" >&2; exit 2; fi

# Fail closed on any unreadable input BEFORE extraction: the `|| true` on the extract
# calls (needed so a benign no-match doesn't abort) would otherwise let a permission
# error silently drop a workflow and certify parity on a partial read.
for f in "${wf_files[@]}" "$SKILL"; do
  [[ -r "$f" ]] || { echo "ERROR: cannot read $f — refusing to certify parity (fail-closed)" >&2; exit 2; }
done

live_f=$(mktemp); skill_f=$(mktemp)
trap 'rm -f "$live_f" "$skill_f"' EXIT
extract "${wf_files[@]}" > "$live_f" || true
extract "$SKILL"         > "$skill_f" || true

# Every EXTERNAL action `uses:` in the live workflows must be a well-formed
# `<40-hex> # vX.Y.Z` pin — flag tags, branches, and malformed comments. Defense in
# depth with check-pinned-uses.sh, and it keeps extract()'s live set complete so the
# parity comparison can't be dodged by a pin extract() couldn't parse.
bad_live=$(malformed "${wf_files[@]}")
if [[ -n "$bad_live" ]]; then
  echo "ERROR: live workflow action(s) not pinned to a well-formed '<40-hex> # vX.Y.Z' (fail-closed):" >&2
  printf '%s\n' "$bad_live" | sed 's/^/  /' >&2
  exit 2
fi

# Fail closed on any LIVE action whose SKILL.md `uses:` occurrence is not a well-formed
# `<40-hex> # vX.Y.Z` pin — whether the version comment is malformed/absent OR the ref
# regressed to a tag/branch (e.g. `@v6`). Either lets an unpinned/uncompared action ship
# in the installed template, and check-pinned-uses.sh scans only .github/, never SKILL.md,
# so this is the sole guard for the template's shared-action pins. Scoped to live actions
# so template-only refs (e.g. rust-toolchain `@… # stable`) don't false-fail.
if [[ -s "$live_f" ]]; then
  bad=$(bad_shared_pins "$live_f" "$SKILL")
  if [[ -n "$bad" ]]; then
    echo "ERROR: live action(s) referenced in SKILL.md without a well-formed '<40-hex> # vX.Y.Z' pin" >&2
    echo "       (tag/branch ref or malformed version comment — fail-closed):" >&2
    printf '%s\n' "$bad" | sed 's/^/  /' >&2
    exit 2
  fi
fi

printf 'Template↔live pin parity (SKILL.md vs .github/workflows)\n\n'
rc=0
report "$live_f" "$skill_f" || rc=$?

# Whole-document content parity (issue #66): live security.yml vs SKILL.md Section N.
# Fail-closed: a missing security.yml or any extraction/normalization error is exit 2,
# never a silent pass. Severities combine (2 dominates 1 dominates 0), so pin OR content
# drift fails the check.
SECURITY_YML="$WF_DIR/security.yml"
printf '\nWhole-document content parity (security.yml vs SKILL.md Section N)\n\n'
crc=0
if [[ -f "$SECURITY_YML" ]]; then
  content_hash_check "$SECURITY_YML" "$SKILL" || crc=$?
else
  echo "ERROR: $SECURITY_YML not found — cannot run content parity (fail-closed)" >&2
  crc=2
fi
rc=$(( crc > rc ? crc : rc ))
exit "$rc"
