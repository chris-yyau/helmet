#!/usr/bin/env bash
#
# test-check-required-checks.sh — hermetic, network-free tests for surface (c)
# of check-required-checks.sh (the source_app / commit-walk logic).
#
# No real GitHub: a mock `gh` on PATH replays canned check-run JSON from a
# per-case fixture dir, so every exhaustion state and the honest summary are
# exercised deterministically. Runs locally and from the `version-drift` CI
# job. Requires bash + jq (same deps as the script under test).
#
# Exit: 0 all pass, 1 any failure.

set -uo pipefail   # NOT -e: we deliberately capture non-zero exits under test.

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SELF_DIR/check-required-checks.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to run these tests" >&2
  exit 2
fi

pass=0
fail=0

# ── fixture scaffold ─────────────────────────────────────────────────────
# One reusable fake repo. The script derives REPO_ROOT from its own location
# ($SCRIPT_DIR/..), so we copy it into $ROOT/scripts and it treats $ROOT as
# the repo. Per-case inputs (lock, commit list, check-run JSON, branch
# protection) are rewritten under $ROOT/mock between runs; the mock `gh`
# reads them fresh via $GH_MOCK_DIR.
# Guard mktemp: without `set -e`, an unchecked failure would leave ROOT empty
# and every derived path would resolve under `/` (e.g. /bin/gh) — catastrophic
# under a privileged run. Fail hard instead.
ROOT="$(mktemp -d)" || { echo "error: mktemp -d failed" >&2; exit 2; }
[[ -n "$ROOT" && -d "$ROOT" ]] || { echo "error: mktemp -d produced no directory" >&2; exit 2; }
trap 'rm -rf "$ROOT"' EXIT
MOCK="$ROOT/mock"
mkdir -p "$ROOT/scripts" "$ROOT/.github/workflows" "$ROOT/bin" "$MOCK"
cp "$SCRIPT" "$ROOT/scripts/check-required-checks.sh"

# A workflow whose bare job keys are the six gate names, so surfaces (a) and
# (d) pass cleanly and every run reaches (c). Bare keys → lock `name` == key.
cat > "$ROOT/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [push, pull_request]
jobs:
  check1:
    runs-on: ubuntu-latest
    steps: [{ run: "true" }]
  check2:
    runs-on: ubuntu-latest
    steps: [{ run: "true" }]
  check3:
    runs-on: ubuntu-latest
    steps: [{ run: "true" }]
  check4:
    runs-on: ubuntu-latest
    steps: [{ run: "true" }]
  check5:
    runs-on: ubuntu-latest
    steps: [{ run: "true" }]
  check6:
    runs-on: ubuntu-latest
    steps: [{ run: "true" }]
YAML

# Mock `gh`: dispatch on the api path and emit exactly what the real
# `gh api <path> --jq <expr>` would have produced for the script's calls.
cat > "$ROOT/bin/gh" <<'MOCKGH'
#!/usr/bin/env bash
# Mock gh — canned replies from $GH_MOCK_DIR, keyed by api path substring.
args="$*"
case "$args" in
  *check-runs*)
    # script: gh api .../commits/<sha>/check-runs --paginate --jq '.check_runs[]'
    # → emit the check_run objects as NDJSON (one per line), or nothing.
    sha=$(printf '%s\n' "$args" | sed -E 's#.*/commits/([^/]+)/check-runs.*#\1#')
    # A `fail_<sha>` marker makes this fetch exit non-zero — simulates a
    # network/rate-limit/auth failure so the api_error path can be tested.
    [[ -f "$GH_MOCK_DIR/fail_$sha" ]] && exit 1
    cat "$GH_MOCK_DIR/checkruns_$sha.ndjson" 2>/dev/null || true
    ;;
  *"commits?sha="*)
    # script: gh api .../commits?sha=main&per_page=1&page=N --jq '.[0].sha'
    # → emit the Nth sha (blank when past the end).
    page=$(printf '%s\n' "$args" | sed -E 's/.*[?&]page=([0-9]+).*/\1/')
    [[ "$page" =~ ^[0-9]+$ ]] || page=1
    sed -n "${page}p" "$GH_MOCK_DIR/commit_shas.txt" 2>/dev/null || true
    ;;
  *protection*)
    # script: gh api .../required_status_checks (no --jq) → full JSON body.
    cat "$GH_MOCK_DIR/branch_protection.json" 2>/dev/null || true
    ;;
  *)
    # script: gh api repos/O/R --jq '.default_branch'
    echo "main"
    ;;
esac
exit 0
MOCKGH
chmod +x "$ROOT/bin/gh"

export GH_MOCK_DIR="$MOCK"
export PATH="$ROOT/bin:$PATH"   # mock `gh` must shadow the real one
RUNNER="$ROOT/scripts/check-required-checks.sh"

# Build a lock of N github-actions entries named check1..checkN. Branch
# protection is set to the same N contexts so surface (b) always passes and
# never colors the exit code we assert on for (c).
make_lock() {
  local n="$1" i
  {
    echo '{ "required": ['
    for ((i = 1; i <= n; i++)); do
      printf '  { "name": "check%d", "workflow": ".github/workflows/ci.yml", "job": "check%d", "source_app": "github-actions" }%s\n' \
        "$i" "$i" "$([[ $i -lt $n ]] && echo , || echo '')"
    done
    echo '] }'
  } > "$ROOT/.github/required-checks.lock"
  jq -c '[.required[].name]' "$ROOT/.github/required-checks.lock" \
    | jq '{contexts: .}' > "$MOCK/branch_protection.json"
}

# One check-run JSON object (compact, single line for NDJSON).
run_obj() { # name slug started_at
  jq -cn --arg n "$1" --arg s "$2" --arg t "$3" \
    '{name: $n, app: {slug: $s}, started_at: $t}'
}

reset_mock() { rm -f "$MOCK"/commit_shas.txt "$MOCK"/checkruns_*.ndjson "$MOCK"/fail_*; }

# ── assertion helpers ────────────────────────────────────────────────────
# Each check() runs the script once, captures stdout+stderr and exit code,
# and asserts: exact exit code, required substrings present, forbidden
# substrings absent. Encodes wants as `+substr` / `-substr` trailing args.
check() {
  local desc="$1" want_exit="$2"; shift 2
  local out ec
  out="$("$RUNNER" "${RUN_ARGS[@]}" 2>&1)"; ec=$?
  local ok=1 spec
  [[ "$ec" -eq "$want_exit" ]] || { ok=0; echo "  exit: got $ec want $want_exit"; }
  for spec in "$@"; do
    case "$spec" in
      +*) grep -qF -- "${spec:1}" <<<"$out" || { ok=0; echo "  missing: '${spec:1}'"; } ;;
      -*) grep -qF -- "${spec:1}" <<<"$out" && { ok=0; echo "  unexpected: '${spec:1}'"; } ;;
    esac
  done
  if [[ "$ok" -eq 1 ]]; then
    pass=$((pass + 1)); echo "PASS: $desc"
  else
    fail=$((fail + 1)); echo "FAIL: $desc"; echo "----- output -----"; echo "$out"; echo "------------------"
  fi
}

ALL_VERIFIED() { # sha: emit all six check1..6 with matching github-actions slug
  local sha="$1" i
  for ((i = 1; i <= 6; i++)); do
    run_obj "check$i" "github-actions" "2026-01-0${i}T00:00:00Z"
  done > "$MOCK/checkruns_$sha.ndjson"
}

# ── T1: newest commit only third-party → walker keeps going ──────────────
make_lock 6; reset_mock
printf 'sha_new\nsha_old\n' > "$MOCK/commit_shas.txt"
run_obj "CodeRabbit" "coderabbitai" "2026-01-01T00:00:00Z" > "$MOCK/checkruns_sha_new.ndjson"
ALL_VERIFIED sha_old
RUN_ARGS=(--owner o --repo r)
check "T1 newest commit only third-party runs → walk advances to lock-named commit" 0 \
  +"using commit: sha_old" +"every required check is reported" -"using commit: sha_new"

# ── T2: first commit is lock-named → accepted immediately ────────────────
# Use a 7-char sha so it survives the script's `${sha:0:7}` short-SHA display
# unchanged (real 40-hex SHAs truncate to 7; the assertion mirrors that).
make_lock 6; reset_mock
printf 'abc1234\n' > "$MOCK/commit_shas.txt"
ALL_VERIFIED abc1234
RUN_ARGS=(--owner o --repo r)
check "T2 first commit has a lock-named run → accepted, 'using commit' printed" 0 \
  +"using commit: abc1234" +"every required check is reported"

# ── T3: 10 commits, runs present but never lock-named → state 2 warn-only ──
make_lock 6; reset_mock
: > "$MOCK/commit_shas.txt"
for i in $(seq 1 10); do
  echo "sha_$i" >> "$MOCK/commit_shas.txt"
  run_obj "CodeRabbit" "coderabbitai" "2026-01-01T00:00:00Z" > "$MOCK/checkruns_sha_$i.ndjson"
done
RUN_ARGS=(--owner o --repo r)
check "T3a state2 (runs, none lock-named) → warn-only default, exit 0" 0 \
  +"none lock-named in last 10 commits" -"DRIFT" -"using commit:"
RUN_ARGS=(--owner o --repo r --strict-remote)
check "T3b state2 under --strict-remote → fail-closed DRIFT, exit 1" 1 \
  +"DRIFT: check-runs found but none lock-named in last 10 commits" \
  +"cannot verify source_app (--strict-remote)"

# ── T4: 10 commits, no runs at all → state 1 (warn default / drift strict) ──
make_lock 6; reset_mock
: > "$MOCK/commit_shas.txt"
for i in $(seq 1 10); do echo "sha_$i" >> "$MOCK/commit_shas.txt"; done   # no checkruns_* files
RUN_ARGS=(--owner o --repo r)
check "T4a state1 (no runs at all) → warn-only default, exit 0" 0 \
  +"no recent commit (last 10) had check-runs" -"DRIFT"
RUN_ARGS=(--owner o --repo r --strict-remote)
check "T4b state1 under --strict-remote → DRIFT, exit 1" 1 \
  +"DRIFT: no recent commit (last 10) had check-runs"

# ── T5: empty required array → clean skip, exit 0 both modes ──────────────
make_lock 0; reset_mock
printf 'sha_head\n' > "$MOCK/commit_shas.txt"
RUN_ARGS=(--owner o --repo r)
check "T5a empty required → clean skip, exit 0" 0 \
  +"nothing to verify" -"DRIFT" -"using commit:"
RUN_ARGS=(--owner o --repo r --strict-remote)
check "T5b empty required under --strict-remote → clean skip, exit 0" 0 \
  +"nothing to verify" -"DRIFT"

# ── T6: honest summary — 1 verified + 5 missing, and a mismatch drifts ────
make_lock 6; reset_mock
printf 'sha_head\n' > "$MOCK/commit_shas.txt"
# Only check1 posted a run (verified); check2..6 absent (missing, warn-only).
run_obj "check1" "github-actions" "2026-01-01T00:00:00Z" > "$MOCK/checkruns_sha_head.ndjson"
RUN_ARGS=(--owner o --repo r)
check "T6a 1 verified + 5 missing → honest tally, NOT all-clear, exit 0" 0 \
  +"verified 1 of 6 source_apps; missing 5 (warn-only); mismatch 0 (drift)" \
  -"every required check is reported"

make_lock 6; reset_mock
printf 'sha_head\n' > "$MOCK/commit_shas.txt"
# check1 posted by the WRONG app → mismatch → DRIFT; check2..6 verified.
{
  run_obj "check1" "evil-impostor" "2026-01-01T00:00:00Z"
  for i in 2 3 4 5 6; do run_obj "check$i" "github-actions" "2026-01-0${i}T00:00:00Z"; done
} > "$MOCK/checkruns_sha_head.ndjson"
RUN_ARGS=(--owner o --repo r)
check "T6b a mismatch → shown in summary AND drifts, exit 1" 1 \
  +"DRIFT: 'check1' expected source_app='github-actions' but reported by 'evil-impostor'" \
  +"mismatch 1 (drift)" -"every required check is reported"

# ── T7: partial walk (unrelated run, then a fetch FAILS) → not benign state 2 ──
# commit1 has only a third-party run (any_runs_seen=1, keeps walking); commit2's
# check-runs fetch fails (api_error=1). The walk is incomplete, so --strict-remote
# must report drift — NOT the warn-only "none lock-named" skip.
make_lock 6; reset_mock
printf 'sha_1\nsha_2\n' > "$MOCK/commit_shas.txt"
run_obj "CodeRabbit" "coderabbitai" "2026-01-01T00:00:00Z" > "$MOCK/checkruns_sha_1.ndjson"
: > "$MOCK/fail_sha_2"   # sha_2 check-runs fetch errors
RUN_ARGS=(--owner o --repo r --strict-remote)
check "T7a partial walk + fetch failure under --strict-remote → DRIFT, exit 1" 1 \
  +"check-run fetch failed during the last-10-commits walk" \
  -"none lock-named in last 10 commits"
RUN_ARGS=(--owner o --repo r)
check "T7b same partial walk in default mode → warn-only, exit 0 (lenient)" 0 \
  +"no recent commit (last 10) had check-runs" -"DRIFT"

# ── T8: newest commit fetch FAILS, older commit is lock-named → strict drifts ──
# The walk skips the newest commit (fetch error) and accepts the older, clean
# one. Under --strict-remote the unexaminable newer commit is a verification
# gap → DRIFT even though the accepted commit verifies. Default mode accepts it.
make_lock 6; reset_mock
printf 'sha_new\nsha_old\n' > "$MOCK/commit_shas.txt"
: > "$MOCK/fail_sha_new"          # newest commit's check-runs fetch errors
ALL_VERIFIED sha_old
RUN_ARGS=(--owner o --repo r --strict-remote)
check "T8a newer-commit fetch failure + accepted older commit → strict DRIFT, exit 1" 1 \
  +"using commit: sha_old" \
  +"a newer commit's check-runs could not be fetched"
RUN_ARGS=(--owner o --repo r)
check "T8b same, default mode → accepts older commit, exit 0 (lenient)" 0 \
  +"using commit: sha_old" +"every required check is reported" -"DRIFT"

# ── report ───────────────────────────────────────────────────────────────
echo ""
echo "===================================="
echo "check-required-checks (c): $pass passed, $fail failed"
echo "===================================="
[[ "$fail" -eq 0 ]]
