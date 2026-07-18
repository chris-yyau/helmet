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

# ── T5: empty required array → (c) skips cleanly; (e) drifts ──────────────
# (c)'s contract is unchanged: an empty `.required` gives it nothing to verify
# and it must say so rather than error. The EXIT CODE changed with surface (e):
# an empty lock is precisely the zero-gate fail-open (e) exists to catch, so a
# run now drifts on (e) while (c) still skips cleanly. Asserting BOTH keeps
# (c)'s intent under test and records the interaction, instead of softening the
# expectation until it stops describing the behavior.
make_lock 0; reset_mock
printf 'sha_head\n' > "$MOCK/commit_shas.txt"
RUN_ARGS=(--owner o --repo r)
check "T5a empty required → (c) skips cleanly, (e) drifts, exit 1" 1 \
  +"nothing to verify" +"neither .required nor .advisory" -"using commit:"
RUN_ARGS=(--owner o --repo r --strict-remote)
check "T5b empty required under --strict-remote → same, exit 1" 1 \
  +"nothing to verify" +"neither .required nor .advisory"

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

# ── T9: surface (e) — a test-running job that no lock entry requires ─────
# The zero-tests-required fail-OPEN: surfaces (a)-(d) all pass (names are
# consistent, unique, and server-matched) while the merge gate enforces no
# test at all. Runs --local-only: (e) needs no API, and this keeps the case
# independent of the (c) commit-walk fixtures above.
add_job() { # job_key run_command — appends a job to ci.yml
  cat >> "$ROOT/.github/workflows/ci.yml" <<YAML
  $1:
    runs-on: ubuntu-latest
    steps: [{ run: "$2" }]
YAML
}
restore_ci() { git -C "$ROOT" checkout -- . 2>/dev/null || true; }

cp "$ROOT/.github/workflows/ci.yml" "$ROOT/ci.yml.bak"

make_lock 6
add_job "unit" "npm test"
RUN_ARGS=(--local-only)
check "T9a PR job absent from the lock -> (e) DRIFT, exit 1" 1 \
  +"[e]" +"'unit'" +"neither .required nor .advisory" \
  +"A test job left out here merges without ever running"

# Same job, now a required lock entry -> clean. (e) keys on lock membership.
jq '.required += [{"name":"unit","workflow":".github/workflows/ci.yml","job":"unit","source_app":"github-actions"}]' \
  "$ROOT/.github/required-checks.lock" > "$ROOT/l.tmp" && cat "$ROOT/l.tmp" > "$ROOT/.github/required-checks.lock"
check "T9b same job, recorded in .required -> (e) ok, exit 0" 0 \
  +"every PR-triggered job is recorded in the lock" -"neither .required nor .advisory"

# .advisory is the recorded-decision escape hatch the DRIFT message names.
# Without this case that instruction would be untested prose.
jq '.required |= map(select(.name != "unit")) | .advisory += [{"name":"unit","workflow":".github/workflows/ci.yml","job":"unit","source_app":"github-actions"}]' \
  "$ROOT/.github/required-checks.lock" > "$ROOT/l.tmp" && cat "$ROOT/l.tmp" > "$ROOT/.github/required-checks.lock"
check "T9c job moved to .advisory -> (e) accepts the recorded decision" 0 \
  +"every PR-triggered job is recorded in the lock" -"neither .required nor .advisory"

# T9d: THE POINT OF THE INVERSION. A job whose test command is spelled in a way
# no heuristic anticipates is still caught, because (e) never inspects what the
# job runs. The predecessor regex missed every one of these across 7 review
# rounds; here they are all the same case.
for probe in "mvn verify" "./gradlew check" "npm t" "deno test" \
             "yarn workspaces foreach -A run test" "bazel coverage //..." \
             "./scripts/weird-suite --mode ci"; do
  cat "$ROOT/ci.yml.bak" > "$ROOT/.github/workflows/ci.yml"
  make_lock 6
  add_job "probe" "$probe"
  check "T9d unrecorded job caught regardless of runner: $probe" 1 \
    +"'probe'" +"neither .required nor .advisory"
done

# T9e: a job in a workflow that CANNOT gate a PR (no pull_request trigger) is
# out of scope — requiring scheduled/release jobs would be noise, not safety.
cat > "$ROOT/.github/workflows/nightly.yml" <<'YAML'
name: Nightly
on:
  schedule:
    - cron: "0 3 * * *"
jobs:
  nightly-suite:
    runs-on: ubuntu-latest
    steps: [{ run: "npm test" }]
YAML
cat "$ROOT/ci.yml.bak" > "$ROOT/.github/workflows/ci.yml"
make_lock 6
check "T9e schedule-only workflow is out of scope for (e)" 0 \
  +"every PR-triggered job is recorded in the lock" -"nightly-suite"
rm -f "$ROOT/.github/workflows/nightly.yml"

# T9f: quoted YAML keys, matrix jobs, and reusable-workflow calls all reduce to
# the same membership question — no per-shape handling needed.
cat "$ROOT/ci.yml.bak" > "$ROOT/.github/workflows/ci.yml"
make_lock 6
cat >> "$ROOT/.github/workflows/ci.yml" <<'YAML'
  delegated:
    uses: org/shared/.github/workflows/tests.yml@abc123
YAML
check "T9f reusable-workflow call is a job like any other" 1 \
  +"'delegated'" +"neither .required nor .advisory"

# T9g: `pull_request` mentioned OUTSIDE the `on:` block (a jq filter, a script
# body) must not make a schedule-only workflow in-scope. A whole-file grep got
# this wrong against helmet's own pin-staleness.yml, demanding a lock entry for
# a job that can never gate a PR.
cat "$ROOT/ci.yml.bak" > "$ROOT/.github/workflows/ci.yml"
make_lock 6
cat > "$ROOT/.github/workflows/sweep.yml" <<'YAML'
name: Sweep
on:
  schedule:
    - cron: "0 8 1 * *"
jobs:
  sweep:
    runs-on: ubuntu-latest
    steps:
      - run: gh api issues --jq '.[] | select(.pull_request == null) | .number'
YAML
check "T9g pull_request outside the on: block does not pull a job in-scope" 0 \
  +"every PR-triggered job is recorded in the lock" -"'sweep'"
rm -f "$ROOT/.github/workflows/sweep.yml"

# T9h: quoted job keys. The parser is shared with (a) and (d), so an
# unquoted-only key regex drops the job from EVERY surface — it never reaches
# (e), and an unrecorded PR test job reads as covered.
for key in '"unit"' "'unit'" 'unit '; do
  cat "$ROOT/ci.yml.bak" > "$ROOT/.github/workflows/ci.yml"
  make_lock 6
  printf '  %s:\n    runs-on: ubuntu-latest\n    steps: [{ run: "npm test" }]\n' "$key" \
    >> "$ROOT/.github/workflows/ci.yml"
  check "T9h quoted/spaced job key [$key] still reaches (e)" 1 \
    +"'unit'" +"neither .required nor .advisory"
done

# T9i: single-quoted and space-padded `on:` keys. Repos write `"on":` / `'on':`
# to dodge the YAML 1.1 on/true coercion; missing those exempts every job in
# the file from registry completeness.
for onkey in '"on"' "'on'" 'on '; do
  cat "$ROOT/ci.yml.bak" > "$ROOT/.github/workflows/ci.yml"
  make_lock 6
  { printf 'name: Quoted\n%s:\n  pull_request:\njobs:\n' "$onkey"
    printf '  quoted-trigger:\n    runs-on: ubuntu-latest\n    steps: [{ run: "npm test" }]\n'
  } > "$ROOT/.github/workflows/quoted.yml"
  check "T9i on-key spelling [$onkey] is recognized as PR-triggered" 1 \
    +"'quoted-trigger'" +"neither .required nor .advisory"
  rm -f "$ROOT/.github/workflows/quoted.yml"
done

# T9j: YAML permits any consistent indent. A 4-space-indented job, and a job
# whose value is an inline flow mapping, are both valid — and a parser anchored
# to two spaces plus end-of-line drops them from (a), (d) AND (e).
cat "$ROOT/ci.yml.bak" > "$ROOT/.github/workflows/ci.yml"
make_lock 6
cat > "$ROOT/.github/workflows/layout.yml" <<'YAML'
name: Layout
on:
  pull_request:
jobs:
    deep-indent:
        runs-on: ubuntu-latest
        steps: [{ run: "npm test" }]
    inline-map: { uses: org/repo/.github/workflows/tests.yml@abc123 }
YAML
check "T9j 4-space indent and inline flow-mapping jobs reach (e)" 1 \
  +"'deep-indent'" +"'inline-map'" +"neither .required nor .advisory"
rm -f "$ROOT/.github/workflows/layout.yml"

# T9k: the job display `name:` must still win over the key, and a STEP name
# must not be mistaken for it — the indent-aware parser pins job-level keys to
# the first child indent, and this is what proves that pin holds.
cat "$ROOT/ci.yml.bak" > "$ROOT/.github/workflows/ci.yml"
make_lock 6
cat > "$ROOT/.github/workflows/named.yml" <<'YAML'
name: Named
on:
  pull_request:
jobs:
  jobkey:
    name: Job Display Name
    runs-on: ubuntu-latest
    steps:
      - name: a step name
        run: npm test
YAML
check "T9k job name: wins; a step name: is not mistaken for it" 1 \
  +"'Job Display Name'" -"'a step name'"
rm -f "$ROOT/.github/workflows/named.yml"

# T9l: surface (a) shares the (d)/(e) hardened collector's indent/quote
# tolerance. A lock entry for a quoted, 4-space-indented job key with a
# quoted `"name":` display value must resolve cleanly — before this fix (a)
# used a separate, unhardened parser (exactly-two-space unquoted job keys,
# four-space unquoted `name:` only) and reported "job key not found" even
# though (d)/(e) already recognized the same job (Greptile PR #89 P1).
cat "$ROOT/ci.yml.bak" > "$ROOT/.github/workflows/ci.yml"
make_lock 6
jq '.required += [{"name":"Unit Tests Quoted","workflow":".github/workflows/quoted-a.yml","job":"unit-quoted","source_app":"github-actions"}]' \
  "$ROOT/.github/required-checks.lock" > "$ROOT/l.tmp" && cat "$ROOT/l.tmp" > "$ROOT/.github/required-checks.lock"
cat > "$ROOT/.github/workflows/quoted-a.yml" <<'YAML'
name: Quoted A
on:
  pull_request:
jobs:
    "unit-quoted":
        "name": Unit Tests Quoted
        runs-on: ubuntu-latest
        steps: [{ run: "npm test" }]
YAML
check "T9l quoted job key + 4-space indent + quoted name: resolves on (a)" 0 \
  +"ok: every lock entry maps to a workflow job" -"job key not found"
rm -f "$ROOT/.github/workflows/quoted-a.yml"

restore_ci

# ── report ───────────────────────────────────────────────────────────────
echo ""
echo "===================================="
echo "check-required-checks (c): $pass passed, $fail failed"
echo "===================================="
[[ "$fail" -eq 0 ]]
