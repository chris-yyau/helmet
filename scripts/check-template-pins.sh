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
# The single strict pin contract, shared by extract() and malformed(): a 40-hex SHA
# followed by exactly ` # vX.Y.Z` (three-part semver) that ENDS at whitespace or EOL.
# The trailing boundary rejects 4-part `# v1.2.3.4` and pre-release `# v1.2.3-beta`
# so extract() and malformed() never disagree on what "valid" means. (A legit trailing
# ` # zizmor: …` comment still ends the semver with a space, so it stays valid.)
PIN_RE='@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+([[:space:]]|$)'

extract() {
  grep -hoE "[A-Za-z0-9._/-]+$PIN_RE" "$@" \
    | sed -E 's/@([0-9a-f]{40}) # v([0-9]+\.[0-9]+\.[0-9]+).*/|\1|\2/' \
    | LC_ALL=C sort -t'|' -k1,1 -k2 -u
}

# `uses:` lines carrying an `owner/repo@<40-hex>` SHA pin whose suffix is NOT a
# well-formed ` # vX.Y.Z` comment (e.g. `# stable`, or none). extract() silently
# drops these; scoped to `uses:` lines so the SHA-verification doc table (arrow
# `→ v` rows) is not matched. Mirrors extract()'s ` # v[0-9]` discriminator.
malformed() {
  grep -hE 'uses:.*@[0-9a-f]{40}' "$@" | grep -vE "$PIN_RE" || true
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

  rm -f "$lf" "$sf"
  if [[ "$fail" -eq 0 ]]; then echo "self-test: PASS"; exit 0; else echo "self-test: FAIL"; exit 1; fi
fi

# --- main ----------------------------------------------------------------------------
SKILL="$REPO_ROOT/skills/helmet/SKILL.md"
WF_DIR="$REPO_ROOT/.github/workflows"
if [[ ! -f "$SKILL" ]]; then echo "ERROR: not found: $SKILL" >&2; exit 2; fi
if [[ ! -d "$WF_DIR" ]]; then echo "ERROR: not found: $WF_DIR" >&2; exit 2; fi

live_f=$(mktemp); skill_f=$(mktemp)
trap 'rm -f "$live_f" "$skill_f"' EXIT
extract "$WF_DIR"/*.yml > "$live_f" || true
extract "$SKILL"        > "$skill_f" || true

# Fail closed on any malformed pin in the live workflows: extract() drops it from the
# live set, so a malformed shared live action would otherwise go uncompared. Live is
# helmet's own CI — every `uses:` pin must be well-formed, so flag any that isn't.
bad_live=$(malformed "$WF_DIR"/*.yml)
if [[ -n "$bad_live" ]]; then
  echo "ERROR: live workflow action(s) SHA-pinned without a well-formed '# vX.Y.Z' comment (fail-closed):" >&2
  printf '%s\n' "$bad_live" | sed 's/^/  /' >&2
  exit 2
fi

# Fail closed (Codex P2): a LIVE action SHA-pinned in SKILL.md on a `uses:` line but
# with a malformed/absent `# vX.Y.Z` comment is invisible to extract(), so it would
# surface as a non-failing live-only WARN instead of being compared. Scope to live
# actions so template-only labels (e.g. rust-toolchain `# stable`) don't false-fail.
if [[ -s "$live_f" ]]; then
  bad=$(malformed "$SKILL" | grep -oE '[A-Za-z0-9._/-]+@[0-9a-f]{40}' | sed 's/@.*//' \
        | LC_ALL=C sort -u | grep -Fxf <(cut -d'|' -f1 "$live_f") || true)
  if [[ -n "$bad" ]]; then
    echo "ERROR: live action(s) SHA-pinned in SKILL.md with a malformed/absent '# vX.Y.Z' comment (fail-closed):" >&2
    printf '%s\n' "$bad" | sed 's/^/  /' >&2
    exit 2
  fi
fi

printf 'Template↔live pin parity (SKILL.md vs .github/workflows)\n\n'
rc=0
report "$live_f" "$skill_f" || rc=$?
exit "$rc"
