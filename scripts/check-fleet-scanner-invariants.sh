#!/usr/bin/env bash
# check-fleet-scanner-invariants.sh — assert that each fleet mirror's live
# security.yml still holds helmet's security-critical scanner INVARIANTS, and
# fail loud on any mirror that has *weakened* one.
#
# WHY: helmet vendors its security.yml into each fleet repo, then each mirror
# evolves independently (repo-specific paths, extra jobs, older-but-valid pins,
# reworded comments). A whole-document hash would flag every mirror as massively
# "drifted" (72–152 benign lines each) — the wrong instrument. This check asserts
# a fixed set of SEMANTIC invariants instead: it fires ONLY when a mirror is *less
# strict* than the contract, never on benign customization or version drift. The
# real risk #76 names — "a mirror-local edit weakens a scanner and goes undetected"
# — is exactly what this catches.
#
# SCOPE (honest limits): this catches a mirror edited to weaken a scanner's GATE,
# hardening, presence, or suppression. It does NOT verify the `changes` detector's
# shell logic. A detector rewritten to always emit `security=false` while succeeding
# would skip every scanner, and invariant 2's `always() + result != 'success'`
# backstop only catches a *failed/cancelled* detector, not a *lying-but-successful*
# one. Deep-parsing the detector's fail-closed shell is the adversarial-YAML/shell
# hole #66 deliberately closed by NOT parsing; re-opening it here is out of scope.
# The ultimate control is CI actually running the scanners on every PR/push — this
# is drift-detection over the gating *shape*, not a sandbox for a hostile maintainer.
#
# INVARIANTS asserted per mirror (each fires only when the mirror is *weaker*):
#   1. Four BLOCKING scanner steps present: trivy (action or CLI), semgrep
#      (`semgrep scan … --error`), checkov (`checkov -d`), zizmor (`zizmor …
#      .github/workflows`). Install-only / echo / comment steps do not count.
#   2. Each scanner job is fail-CLOSED gated: either no `needs:`+no job `if:`
#      (truly unconditional), OR the exact canonical shape
#      `always() && (needs.D.outputs.security == 'true' || needs.D.result != 'success')`
#      (D = the detector job the `if:` references). Anything else is UNVERIFIABLE → FAIL.
#   3. trivy hardening intact ON THE TRIVY STEP: scanners⊇vuln, severity⊇{HIGH,CRITICAL},
#      exit-code==1, scan-type fs (action) / a real scan target (CLI).
#   4. No scanner neutered: step/job `continue-on-error: true`, trailing `|| true`/`|| :`/
#      `|| exit 0`, `set +e`, a constant-false step `if:`, checkov `--soft-fail`.
#   5. Reachability: `on.pull_request` present with NO `paths:`/`paths-ignore:` filter
#      (a PR path filter can make a required scanner check never register).
#
# USAGE:
#   scripts/check-fleet-scanner-invariants.sh <owner/repo> [<owner/repo> ...]
#   scripts/check-fleet-scanner-invariants.sh --fleet        # read .helmet-fleet
#   scripts/check-fleet-scanner-invariants.sh --self-test    # hermetic fixtures, no network
#
# EXIT: 0 = all invariants hold on all reachable mirrors;
#       1 = ≥1 mirror weakened OR unreadable/unparseable (cannot certify → not a silent pass);
#       2 = setup/usage error (missing python3 or PyYAML, bad args).
# REQUIRES: gh (authenticated), python3 + PyYAML (`pip install pyyaml`). PyYAML is
#           NOT otherwise a repo/runner dependency — asserted up front, fail-closed.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
WORKFLOW_PATH=".github/workflows/security.yml"
FLEET_FILE="$REPO_ROOT/.helmet-fleet"

# --- the parser + invariant asserter (Python; reads one workflow YAML on stdin) ------
# Exit: 0 = all invariants hold; 1 = weakened OR unparseable; 2 = PyYAML missing.
# The bool-resolver strip is load-bearing: YAML 1.1 coerces the unquoted GitHub key
# `on` to boolean True, so a naive parser never finds the triggers (breaks invariant 5
# on EVERY valid workflow). Dropping the bool resolver keeps `on`/`true`/`false` strings.
read -r -d '' PYSRC <<'PYEOF' || true
import os, re, sys

# Test seam: exercise the fail-closed "PyYAML absent" path hermetically (self-test).
if os.environ.get("_FLEET_FORCE_NO_YAML") == "1":
    sys.stderr.write("ERROR: python3 + PyYAML required (pip install pyyaml)\n")
    sys.exit(2)
try:
    import yaml
except Exception:
    sys.stderr.write("ERROR: python3 + PyYAML required (pip install pyyaml)\n")
    sys.exit(2)

# SAFE: a SafeLoader subclass — no `!!python/...` type constructors are added, so this
# is safe_load-equivalent on untrusted remote YAML. We ONLY remove the bool implicit
# resolver (below) so GitHub's `on` key stays a string (YAML 1.1 coerces it to True).
class WFLoader(yaml.SafeLoader):
    pass
for _ch in list(WFLoader.yaml_implicit_resolvers):
    _keep = [(t, r) for (t, r) in WFLoader.yaml_implicit_resolvers[_ch]
             if t != "tag:yaml.org,2002:bool"]
    if _keep:
        WFLoader.yaml_implicit_resolvers[_ch] = _keep
    else:
        del WFLoader.yaml_implicit_resolvers[_ch]

def norm_expr(s):
    """Normalize a GitHub `if:`/scalar expr: strip one ${{ }} wrap, unify quotes, collapse ws."""
    if s is None:
        return None
    s = str(s).strip()
    m = re.match(r"^\$\{\{\s*(.*?)\s*\}\}$", s, re.S)
    if m:
        s = m.group(1).strip()
    s = s.replace('"', "'")
    s = re.sub(r"\s+", " ", s)
    return s

def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]

def truthy(v):
    return norm_expr(v) in ("true", "yes", "on")

def steps_of(job):
    return job.get("steps", []) if isinstance(job, dict) else []

def step_run(step):
    return str(step.get("run", "")) if isinstance(step, dict) else ""

def step_uses(step):
    return str(step.get("uses", "")) if isinstance(step, dict) else ""

def step_with(step):
    w = step.get("with", {}) if isinstance(step, dict) else {}
    return w if isinstance(w, dict) else {}

# --- scanner step matchers (bound to the REAL invocation, not a bare token) ----------
def is_trivy_action(step):
    return re.match(r"^aquasecurity/trivy-action@", step_uses(step)) is not None

def is_trivy_cli(step):
    r = step_run(step)
    return re.search(r"\btrivy\b.*\b(fs|filesystem|rootfs|image|config)\b", r) is not None

def is_semgrep_scan(step):
    return re.search(r"\bsemgrep\s+scan\b", step_run(step)) is not None

def is_checkov(step):
    return re.search(r"\bcheckov\b.*(-d\b|--directory\b)", step_run(step)) is not None

def is_zizmor(step):
    r = step_run(step)
    return re.search(r"\bzizmor\b", r) is not None and re.search(r"\.github/workflows|\s\.(\s|$)", r) is not None

# --- invariant 4: is this scanner step neutered? -------------------------------------
def run_neutered(run):
    if re.search(r"\|\|\s*(true|:)(\s|$|;|&)", run):
        return True
    if re.search(r"\|\|\s*exit\s+0\b", run):
        return True
    if re.search(r"(^|\n|;|\s)set\s+\+e\b", run):
        return True
    return False

def step_neutered(job, step):
    if truthy(job.get("continue-on-error")):
        return True
    if truthy(step.get("continue-on-error")):
        return True
    sif = norm_expr(step.get("if"))
    if sif is not None and (sif == "false" or sif.startswith("false &&")):
        return True
    if run_neutered(step_run(step)):
        return True
    return False

# --- invariant 2: is the scanner-owning JOB fail-closed gated? -----------------------
def gate_ok(job):
    nif = norm_expr(job.get("if"))
    needs = [str(n) for n in as_list(job.get("needs"))]
    # Which detector job does the `if:` reference (needs.D.outputs.security / needs.D.result)?
    refs = set(re.findall(r"needs\.([A-Za-z0-9_-]+)\.(?:outputs\.security|result)", nif or ""))
    if refs:
        if len(refs) != 1:
            return False  # ambiguous / multiple detectors → cannot certify
        D = next(iter(refs))
        if D not in needs:
            return False  # references a job it doesn't depend on → cannot certify
        d = re.escape(D)
        pos = r"needs\.%s\.outputs\.security == 'true'" % d
        neg = r"needs\.%s\.result != 'success'" % d
        for a, b in ((pos, neg), (neg, pos)):
            if re.match(r"^always\(\) && \(%s \|\| %s\)$" % (a, b), nif):
                return True
        return False  # gated but not the canonical fail-closed shape → UNVERIFIABLE → FAIL
    # No detector referenced: certify ONLY a truly unconditional job — no needs at all,
    # and no job-level `if:` (or an always-true one). Any non-detector `needs` could skip
    # the job via implicit success(); any other `if:` we cannot certify.
    if needs:
        return False
    return nif is None or nif in ("always()", "true", "success()")

# --- invariant 3: trivy hardening, scoped to the matched trivy step ------------------
def trivy_action_hardened(step):
    w = {str(k).lower(): v for k, v in step_with(step).items()}
    scanners = str(w.get("scanners", ""))
    severity = str(w.get("severity", "")).upper()
    exitc = norm_expr(w.get("exit-code"))
    scan_type = str(w.get("scan-type", ""))
    return (
        re.search(r"\bvuln\b", scanners) is not None
        and "HIGH" in severity and "CRITICAL" in severity
        and exitc == "1"
        and scan_type == "fs"
    )

def trivy_cli_hardened(run):
    if not re.search(r"--scanners[=\s]+\S*vuln", run):
        return False
    sev = re.search(r"--severity[=\s]+(\S+)", run)
    if not sev or "HIGH" not in sev.group(1).upper() or "CRITICAL" not in sev.group(1).upper():
        return False
    if not re.search(r"--exit-code[=\s]+1\b", run):
        return False
    # a real scan target: a standalone `.` or a path-like token (contains `/`) — this
    # excludes flag VALUES like `vuln`/`HIGH,CRITICAL`/`1`, which have neither.
    # ponytail: `--skip-dirs tests/` could satisfy this without a top-level target;
    # accepted — trivy errors at runtime on a truly targetless run, so this is drift-only.
    if not re.search(r"(^|\s)(\.|\S*/\S*)(\s|$)", run):
        return False
    return True

# --- driver --------------------------------------------------------------------------
raw = sys.stdin.read()
if not raw.strip():
    sys.stderr.write("  FAIL: empty workflow document (fail-closed)\n")
    sys.exit(1)
try:
    doc = yaml.load(raw, Loader=WFLoader)
except Exception as e:
    sys.stderr.write("  FAIL: unparseable YAML (%s)\n" % e.__class__.__name__)
    sys.exit(1)
if not isinstance(doc, dict):
    sys.stderr.write("  FAIL: workflow is not a mapping\n")
    sys.exit(1)

jobs = doc.get("jobs", {})
if not isinstance(jobs, dict):
    jobs = {}

fail = []

# Invariants 1–4, per scanner: require ≥1 owning step whose job is fail-closed gated,
# is not neutered, and (trivy/semgrep/checkov) is not weakened.
SCANNERS = ("trivy", "semgrep", "checkov", "zizmor")
for scanner in SCANNERS:
    candidates, weakened = [], []
    for jn, job in jobs.items():
        if not isinstance(job, dict):
            continue
        for step in steps_of(job):
            if not isinstance(step, dict):
                continue
            if scanner == "trivy":
                is_action = is_trivy_action(step)
                if not (is_action or is_trivy_cli(step)):
                    continue
            elif scanner == "semgrep":
                if not is_semgrep_scan(step):
                    continue
            elif scanner == "checkov":
                if not is_checkov(step):
                    continue
            else:  # zizmor
                if not is_zizmor(step):
                    continue
            candidates.append((jn, step))
            reasons = []
            if not gate_ok(job):
                reasons.append("job gate not fail-closed")
            if step_neutered(job, step):
                reasons.append("step neutered (continue-on-error/|| true/set +e/if:false)")
            if scanner == "trivy":
                ok = trivy_action_hardened(step) if is_trivy_action(step) else trivy_cli_hardened(step_run(step))
                if not ok:
                    reasons.append("trivy hardening weak (scanners/severity/exit-code/scan-type)")
            elif scanner == "semgrep":
                if not re.search(r"--error\b", step_run(step)):
                    reasons.append("semgrep missing --error (exits 0 on findings → fail-open)")
            elif scanner == "checkov":
                if re.search(r"--soft-fail(-on)?\b", step_run(step)):
                    reasons.append("checkov --soft-fail (findings non-blocking)")
            if reasons:
                weakened.append("%s: %s" % (jn, "; ".join(reasons)))
    if not candidates:
        fail.append("[inv1] %s: no blocking scan step found" % scanner)
    elif len(candidates) == len(weakened):
        fail.append("[inv2-4] %s weakened: %s" % (scanner, " | ".join(weakened)))

# Invariant 5: reachability — on.pull_request present with no paths filter.
on = doc.get("on")
if isinstance(on, str):
    triggers = {on: None}
elif isinstance(on, list):
    triggers = {str(t): None for t in on}
elif isinstance(on, dict):
    triggers = on
else:
    triggers = {}
if "pull_request" not in triggers:
    fail.append("[inv5] no pull_request trigger (workflow never starts on PRs)")
else:
    pr = triggers.get("pull_request")
    if isinstance(pr, dict) and ("paths" in pr or "paths-ignore" in pr):
        fail.append("[inv5] pull_request has a paths filter (required check may never register)")

if fail:
    for f in fail:
        sys.stderr.write("  FAIL %s\n" % f)
    sys.exit(1)
sys.exit(0)
PYEOF

# python3 must exist (PyYAML absence is detected by the checker itself → exit 2).
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required (with PyYAML: pip install pyyaml)" >&2
  exit 2
fi

# run_check: feed a workflow YAML (stdin/string) to the asserter. Returns its exit code.
run_check() { printf '%s' "$1" | python3 -c "$PYSRC"; }

# ======================================================================================
#  self-test — hermetic fixtures (no network), each asserting the expected verdict.
# ======================================================================================
if [[ "${1:-}" == "--self-test" ]]; then
  fail=0
  # expect VERDICT FIXTURE_NAME  — run the checker on $BODY, assert its exit code.
  expect() {
    local want="$1" name="$2" body="$3" got=0
    run_check "$body" >/dev/null 2>&1 || got=$?
    if [[ "$got" != "$want" ]]; then
      echo "FAIL: [$name] expected exit $want, got $got"; fail=1
    fi
  }

  # A canonical-compliant baseline (action-form trivy). Reused as a mutation base.
  COMPLIANT=$(cat <<'EOF'
on:
  pull_request:
  push:
    paths: ['.github/**']
jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      security: ${{ steps.filter.outputs.security }}
    steps:
      - id: filter
        run: echo "security=true" >> "$GITHUB_OUTPUT"
  trivy:
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    steps:
      - uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
        with:
          scan-type: fs
          scanners: vuln
          severity: HIGH,CRITICAL
          exit-code: 1
  semgrep:
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    steps:
      - run: pip install semgrep
      - run: semgrep scan --config p/security-audit --error --exclude tests .
  checkov:
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    steps:
      - run: checkov -d . --skip-path tests --quiet
  zizmor:
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    steps:
      - run: zizmor --min-severity high --min-confidence high .github/workflows/
EOF
)

  expect 0 "compliant baseline" "$COMPLIANT"

  # compliant CLI-form trivy (with a real scan target) ⇒ PASS
  expect 0 "compliant CLI trivy" "$(printf '%s\n' "$COMPLIANT" | sed -E \
    's#      - uses: aquasecurity/trivy-action@.*#      - run: trivy fs --scanners vuln --severity HIGH,CRITICAL --exit-code 1 .#; /^        with:/,/^          exit-code: 1/d')"

  # benign customization — extra gitleaks job, repo-specific paths, older pin,
  # absent ignore-unfixed, reworded comment ⇒ PASS (the anti-false-positive proof).
  expect 0 "benign customization" "$(cat <<'EOF'
on:
  pull_request:
  push:
    paths: ['hooks/**', 'scripts/**']   # repo-specific
jobs:
  changes:
    outputs:
      security: ${{ steps.f.outputs.security }}
    steps:
      - id: f
        run: echo security=true >> "$GITHUB_OUTPUT"
  gitleaks:
    steps:
      - run: gitleaks detect
  trivy:
    needs: [changes]
    # reworded comment here
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    steps:
      - uses: aquasecurity/trivy-action@0000000000000000000000000000000000000000 # v0.30.0 (older, valid)
        with:
          scan-type: fs
          scanners: vuln
          severity: CRITICAL,HIGH
          exit-code: 1
  semgrep:
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    steps:
      - run: semgrep scan --config p/ci --error .
  checkov:
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    steps:
      - run: checkov --directory . --quiet
  zizmor:
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    steps:
      - run: zizmor .github/workflows/
EOF
)"

  # no-needs / no-if scanner (truly unconditional) ⇒ PASS (inv 2 — stricter)
  expect 0 "unconditional scanner" "$(printf '%s\n' "$COMPLIANT" | \
    perl -0pe 's/  trivy:\n    needs: \[changes\]\n    if: [^\n]*\n/  trivy:\n/')"

  # --- FAIL fixtures ---
  # missing scanner (drop the trivy job) ⇒ FAIL (inv 1)
  expect 1 "missing trivy job" "$(printf '%s\n' "$COMPLIANT" | perl -0pe 's/  trivy:.*?\n  semgrep:/  semgrep:/s')"

  # install-only semgrep (drop the scan step) ⇒ FAIL (inv 1)
  expect 1 "install-only semgrep" "$(printf '%s\n' "$COMPLIANT" | \
    perl -0pe 's/      - run: semgrep scan[^\n]*\n//')"

  # semgrep without --error ⇒ FAIL (inv 1/fail-open — HIGH fix)
  expect 1 "semgrep no --error" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#semgrep scan --config p/security-audit --error --exclude tests .#semgrep scan --config p/security-audit --exclude tests .#')"

  # dropped always() ⇒ FAIL (inv 2)
  expect 1 "dropped always()" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E "s#if: always\(\) && \(#if: (#")"

  # absent if: with needs:[changes] ⇒ FAIL (inv 2 fail-open)
  expect 1 "absent if with needs" "$(printf '%s\n' "$COMPLIANT" | \
    perl -0pe 's/(  trivy:\n    needs: \[changes\]\n)    if: [^\n]*\n/$1/')"

  # positive-branch dropped (always() && result != success only) ⇒ FAIL (inv 2 — HIGH fix)
  expect 1 "positive branch dropped" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E "s#if: always\(\) && \(needs.changes.outputs.security == 'true' \|\| needs.changes.result != 'success'\)#if: always() \&\& needs.changes.result != 'success'#")"

  # dead-conjunction gate ⇒ FAIL (inv 2)
  expect 1 "dead conjunction gate" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E "s#if: always\(\) && \(#if: false \&\& always() \&\& (#")"

  # job-level if: false neuters scanner while needs omits detector ⇒ FAIL (inv 4/2 — MEDIUM fix)
  expect 1 "job-level if:false" "$(printf '%s\n' "$COMPLIANT" | \
    perl -0pe 's/  trivy:\n    needs: \[changes\]\n    if: [^\n]*\n/  trivy:\n    if: false\n/')"

  # trivy scanners: secret (no CVE scanning) ⇒ FAIL (inv 3)
  expect 1 "trivy scanners secret" "$(printf '%s\n' "$COMPLIANT" | sed -E 's#scanners: vuln#scanners: secret#')"

  # trivy severity narrowed to CRITICAL only ⇒ FAIL (inv 3)
  expect 1 "trivy severity narrowed" "$(printf '%s\n' "$COMPLIANT" | sed -E 's#severity: HIGH,CRITICAL#severity: CRITICAL#')"

  # trivy exit-code 0 ⇒ FAIL (inv 3)
  expect 1 "trivy exit-code 0" "$(printf '%s\n' "$COMPLIANT" | sed -E 's#exit-code: 1#exit-code: 0#')"

  # CLI-form trivy with NO scan target ⇒ FAIL (inv 3 — MEDIUM fix)
  expect 1 "CLI trivy no target" "$(printf '%s\n' "$COMPLIANT" | sed -E \
    's#      - uses: aquasecurity/trivy-action@.*#      - run: trivy fs --scanners vuln --severity HIGH,CRITICAL --exit-code 1#; /^        with:/,/^          exit-code: 1/d')"

  # step-level continue-on-error on the scan step ⇒ FAIL (inv 4)
  expect 1 "step continue-on-error" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    's/(      - run: semgrep scan[^\n]*\n)/      - continue-on-error: true\n        run: semgrep scan --config p\/security-audit --error --exclude tests .\n/')"

  # trailing || true on the scan command ⇒ FAIL (inv 4)
  expect 1 "trailing || true" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#(checkov -d . --skip-path tests --quiet)#\1 || true#')"

  # checkov --soft-fail ⇒ FAIL (inv 4 — MEDIUM fix)
  expect 1 "checkov soft-fail" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#checkov -d . --skip-path tests --quiet#checkov -d . --soft-fail --quiet#')"

  # PR-trigger path filter added ⇒ FAIL (inv 5 reachability)
  expect 1 "PR path filter" "$(printf '%s\n' "$COMPLIANT" | \
    perl -0pe "s/^on:\n  pull_request:\n/on:\n  pull_request:\n    paths: ['src\/**']\n/m")"

  # unparseable YAML ⇒ FAIL (fail-closed)
  expect 1 "unparseable yaml" $'jobs:\n  x: [unbalanced\n'

  # empty document ⇒ FAIL (fail-closed)
  expect 1 "empty document" ""

  # the `on:` boolean-coercion regression: a valid workflow must still see its
  # pull_request trigger (would FAIL inv5 under a naive loader) ⇒ PASS proven by baseline.
  # missing-PyYAML path ⇒ exit 2 (distinct from 1), via the test seam.
  got=0; _FLEET_FORCE_NO_YAML=1 run_check "$COMPLIANT" >/dev/null 2>&1 || got=$?
  if [[ "$got" != 2 ]]; then echo "FAIL: [missing PyYAML] expected exit 2, got $got"; fail=1; fi

  # fleet-list parsing: comments/blank lines stripped (mirrors check-pipeline-drift).
  tfleet=$(mktemp)
  printf '# comment\n\nchris-yyau/busdriver  \n  # another\nDive-And-Dev/perch\n' > "$tfleet"
  mapfile -t parsed < <(
    while IFS= read -r line; do
      line="${line%%#*}"; line="$(printf '%s' "$line" | tr -d '[:space:]')"
      [[ -n "$line" ]] && printf '%s\n' "$line"
    done < "$tfleet")
  rm -f "$tfleet"
  if [[ "${#parsed[@]}" -ne 2 || "${parsed[0]}" != "chris-yyau/busdriver" || "${parsed[1]}" != "Dive-And-Dev/perch" ]]; then
    echo "FAIL: [fleet parse] expected 2 clean repos, got ${parsed[*]-none}"; fail=1
  fi

  if [[ "$fail" -eq 0 ]]; then echo "self-test: PASS"; exit 0; else echo "self-test: FAIL"; exit 1; fi
fi

# ======================================================================================
#  main — resolve the fleet, fetch each mirror's security.yml, assert invariants.
# ======================================================================================
repos=()
if [[ "${1:-}" == "--fleet" ]]; then
  if [[ ! -f "$FLEET_FILE" ]]; then
    echo "ERROR: --fleet given but $FLEET_FILE not found (see .helmet-fleet.example)" >&2
    exit 2
  fi
  while IFS= read -r line; do
    line="${line%%#*}"                       # strip comments
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [[ -n "$line" ]] && repos+=("$line")
  done < "$FLEET_FILE"
elif [[ "$#" -gt 0 ]]; then
  repos=("$@")
fi
if [[ "${#repos[@]}" -eq 0 ]]; then
  echo "Usage: $0 <owner/repo> [<owner/repo> ...] | --fleet | --self-test" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh (authenticated) required for the live-fleet run" >&2
  exit 2
fi

# One up-front PyYAML probe so a missing dependency is a single clear exit 2, not a
# per-repo exit-1 masquerading as "every mirror weakened".
probe=0; printf 'on:\n  pull_request:\n' | python3 -c "$PYSRC" >/dev/null 2>&1 || probe=$?
if [[ "$probe" -eq 2 ]]; then
  echo "ERROR: python3 + PyYAML required (pip install pyyaml)" >&2
  exit 2
fi

printf '%-40s %s\n' "MIRROR" "VERDICT"
ok=0; weak=0; missing=0
for repo in "${repos[@]}"; do
  raw=$(gh api "repos/$repo/contents/$WORKFLOW_PATH" -H "Accept: application/vnd.github.raw" 2>/dev/null || true)
  if [[ -z "$raw" ]]; then
    printf '%-40s %s\n' "$repo" "not found / no access (cannot certify)"
    missing=$((missing + 1))
    continue
  fi
  rc=0; findings=$(run_check "$raw" 2>&1 1>/dev/null) || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    printf '%-40s %s\n' "$repo" "OK — invariants hold"
    ok=$((ok + 1))
  else
    printf '%-40s %s\n' "$repo" "WEAKENED / unparseable:"
    printf '%s\n' "$findings"
    weak=$((weak + 1))
  fi
done

printf '\n%d ok, %d weakened, %d not-found.\n' "$ok" "$weak" "$missing"
if [[ "$weak" -gt 0 ]]; then
  echo "Action needed: a mirror has weakened a scanner invariant — investigate/fix that repo."
  exit 1
fi
if [[ "$missing" -gt 0 ]]; then
  echo "INCOMPLETE: $missing mirror(s) unreadable (not found / no access) — cannot certify. Verify access and re-run."
  exit 1
fi
echo "All reachable mirrors hold the scanner invariants."
exit 0
