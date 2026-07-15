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
# Also OUT of scope: job SCHEDULABILITY (valid `runs-on`, well-formed reusable-workflow
# `uses:`, non-cyclic/existent `needs:` graph). A job that can't be scheduled is a
# workflow GitHub REJECTS or never starts — a LOUD CI failure (every run red/pending),
# not a silent scanner weakening. Fully validating it means reimplementing GitHub's
# workflow schema; the shell/YAML masking checks here target only what fails *quietly*.
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
    # Own a PRIVATE copy of the implicit-resolver map — the parent dict is shared across
    # PyYAML's Loader/SafeLoader/FullLoader, so stripping it in place would disable bool
    # coercion process-wide for every `yaml.safe_load` (harmless in our one-shot subprocess,
    # but the copy-on-write idiom PyYAML's own add_implicit_resolver() uses is correct).
    yaml_implicit_resolvers = {
        ch: list(resolvers) for ch, resolvers in yaml.SafeLoader.yaml_implicit_resolvers.items()
    }
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

# --- shell command extraction: ignore comments and non-command (echo/printf) text ----
def strip_comments(run):
    """Join shell line-continuations (`\\`<newline>) so a command split across lines is one
    logical line, then drop `#`-to-EOL comments — QUOTE-AWARE so a `#` inside single/double
    quotes (`--config 'p/foo #bar'`) is NOT treated as a comment (else a trailing `|| echo`
    masking operator after it would be wrongly stripped, hiding the mask). A `#` is a comment
    only at line start or after whitespace, outside quotes. Backslash-escaped quotes (`\\"`)
    are honored so they don't fake-close a string. LIMIT (accepted, #66-style): quote/escape
    state is tracked PER LINE, so a single/double quote that spans a newline is not carried
    across — a rare construct in a scanner step, and unhandled exotica (multiline quotes,
    heredocs, `$'…'` ANSI-C) read as STRICTER (more likely to flag), the safe direction. Full
    fidelity here means a real shell lexer; the ultimate control is CI actually running."""
    run = re.sub(r"\\\n[ \t]*", " ", run)  # bash line-continuation → single logical line
    out = []
    for line in run.splitlines():
        res = []
        quote = None
        prev_ws = True
        esc = False
        for c in line:
            if esc:  # previous char was a backslash → this char is literal
                res.append(c)
                esc = False
                prev_ws = False
            elif c == "\\" and quote != "'":
                # backslash escapes the next char outside quotes and inside double quotes
                # (but NOT inside single quotes, where it is literal). Handles `\"` / `\#`.
                res.append(c)
                esc = True
                prev_ws = False
            elif quote:
                res.append(c)
                if c == quote:
                    quote = None
                prev_ws = False
            elif c in ("'", '"'):
                quote = c
                res.append(c)
                prev_ws = False
            elif c == "#" and prev_ws:
                break  # unquoted comment → to end of line
            else:
                res.append(c)
                prev_ws = c.isspace()
        out.append("".join(res))
    return "\n".join(out)

# Non-command builtins whose ARGUMENTS must not count as an invocation
# (`echo 'semgrep scan --error .'` is output, not a scanner).
_NONCMD = {"echo", "printf", "print", ":", "true", "false", "cat", "test", "["}

def command_segments(run):
    """Yield (leading_tool, segment_text, negated) for each shell command segment — split
    on shell separators, skipping env-assignment / sudo / env / command / `!` prefixes,
    dropping comments and echo-style output. A tool matched here sits at a real COMMAND
    position; `negated` is True if a shell `!` prefixes it (inverting its exit). This is the
    SINGLE source of truth for prefix stripping — the negation check reuses it rather than a
    parallel regex, so `! FOO=bar semgrep` and `! command semgrep` are handled identically.
    ponytail: does NOT unwrap `bash -c '…'`; canonical uses direct invocation, and an
    unwrapped wrapper simply reads as 'scanner missing' (fail-closed), the safe side."""
    stripped = strip_comments(run)
    # Split on shell separators found OUTSIDE quotes: locate them in a quote-blanked copy,
    # then slice the ORIGINAL so a `|`/`;` inside `--config 'a|b;c.yml'` doesn't split the
    # command (which would hide the `--error` flag after it). Returned text is the real text.
    blanked = _blank_quotes(stripped)
    parts, last = [], 0
    for m in re.finditer(r"\n|;|&&|\|\||\||&", blanked):
        parts.append(stripped[last:m.start()])
        last = m.end()
    parts.append(stripped[last:])
    segs = []
    for part in parts:
        toks = part.split()
        i = 0
        negated = False
        while i < len(toks) and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[i])
                                 or toks[i] in ("env", "sudo", "command", "!", "time", "nohup", "exec")):
            if toks[i] == "!":
                negated = not negated  # `! ! cmd` cancels
            i += 1
        if i >= len(toks) or toks[i] in _NONCMD:
            continue
        segs.append((toks[i], " ".join(toks[i:]), negated))
    return segs

# --- scanner step matchers → the matched command SEGMENT ("" if absent) --------------
def is_trivy_action(step):
    return re.match(r"^aquasecurity/trivy-action@", step_uses(step)) is not None

def trivy_cli_seg(step):
    for lead, seg, _ in command_segments(step_run(step)):
        if lead == "trivy" and re.match(r"^trivy\s+(fs|filesystem|rootfs|image|config)\b", seg):
            return seg
    return ""

def semgrep_seg(step):
    for lead, seg, _ in command_segments(step_run(step)):
        if lead == "semgrep" and re.match(r"^semgrep\s+scan\b", seg):
            return seg
    return ""

def checkov_seg(step):
    for lead, seg, _ in command_segments(step_run(step)):
        if lead == "checkov" and re.search(r"(^|\s)(-d\b|--directory\b)", seg):
            return seg
    return ""

def zizmor_seg(step):
    for lead, seg, _ in command_segments(step_run(step)):
        if lead == "zizmor" and re.search(r"\.github/workflows|\s\.(\s|$)", seg):
            return seg
    return ""

# --- invariant 4: is this scanner step neutered? -------------------------------------
def _blank_quotes(s):
    """Replace the CONTENTS of quoted spans with 'Q' (preserving the quote marks and length)
    so shell OPERATORS inside quotes (`--config 'rules|a;b.yml'`) aren't mistaken for real
    pipes/semicolons. Honors `\\`-escapes outside single quotes. Used for operator/masking
    detection where quoted text is literal DATA — NOT for trap handlers, whose quoted body is
    semantically active."""
    out = []
    quote = None
    esc = False
    for c in s:
        if esc:
            out.append("Q" if quote else c)
            esc = False
        elif c == "\\" and quote != "'":
            out.append(c)
            esc = True
        elif quote:
            if c == quote:
                out.append(c)
                quote = None
            else:
                out.append("Q")
        elif c in ("'", '"'):
            quote = c
            out.append(c)
        else:
            out.append(c)
    return "".join(out)

def run_neutered(run):
    # Operator masks are only real OUTSIDE quotes — blank quoted spans first so a quoted
    # `|| true` in a config value can't false-positive.
    blanked = _blank_quotes(run)
    if re.search(r"\|\|\s*(true|:)(\s|$|;|&)", blanked):
        return True
    if re.search(r"\|\|\s*exit\s+0\b", blanked):
        return True
    if re.search(r"(^|\n|;|\s)set\s+\+e\b", blanked):
        return True
    # a trap that FORCES exit 0 on step/error exit — `trap 'exit 0' EXIT|ERR|0` (signal `0`
    # is the EXIT alias; signal names are case-insensitive in bash) — swallows the scanner's
    # failure. Checked on the RAW run because the handler body is semantic even though quoted.
    # `trap 'exit 1' ERR` / `trap 'rm -f x' EXIT` do NOT force a zero exit and are NOT matched.
    # ponytail: a handler split across newlines is the accepted single-line-parse limit below.
    if re.search(r"\btrap\b[^\n]*\bexit\s+0\b[^\n]*\b(?i:EXIT|ERR|0)\b", run):
        return True
    return False

def _pipefail(shell):
    """Does the effective GitHub `shell` run with `-o pipefail` (so a pipe PROPAGATES a
    failure)? `shell: bash` → yes (`-eo pipefail`); the DEFAULT (`bash -e`) and `shell: sh`
    → no; a custom template → yes only when `-o pipefail` is a real option before `{0}`.
    ACCEPTED LIMITS (rare/adversarial — documented, not chased): a later `+o pipefail`
    that toggles it back off, and non-bash runners (Windows PowerShell has no pipefail
    concept). The common GitHub shells are covered; a mirror crafting the exotic forms is
    adversarial, same posture as the #66 shell-parse boundary."""
    if not shell:
        return False
    s = str(shell)
    if s == "bash":
        return True
    head = s.split("{0}", 1)[0].split()  # options precede the {0} script placeholder
    for i, t in enumerate(head):
        if re.match(r"^-[a-z]*o[a-z]*$", t) and i + 1 < len(head) and head[i + 1] == "pipefail":
            return True
    return False

def exit_masked(run, tool_re, pipefail):
    """True if the scanner's non-zero exit can't fail the step. Walks the scanner's AND-OR
    list and flags: `! scanner` negation; a `||` fallback that can succeed (list exits 0);
    a background `&` (step never waits); and a pipe `|` when pipefail is OFF (the pipeline's
    exit is the last stage's). `&&` continues the list; under pipefail a pipe propagates, so
    the walk continues. `;`/newline ENDS the statement — a trailing command's masking is
    errexit-dependent and, along with `&&`-errexit-exemption, is the accepted out-of-scope
    limit (GitHub's errexit varies by shell; a mirror crafting it is adversarial). The
    explicit invariant-4 neuters (`|| true`/`set +e`/`trap 'exit 0'`/`continue-on-error`/
    `if:` guards/`--soft-fail`) are also caught unconditionally by run/step_neutered."""
    run = _blank_quotes(strip_comments(run))  # operators inside quotes are literal data
    for _lead, seg, negated in command_segments(run):
        if negated and re.search(tool_re, seg):
            return True
    for m in re.finditer(tool_re, run):
        rest = run[m.end():]
        seen_list_op = False  # have we passed a `&&`/`||` (left the scanner's own pipeline)?
        while True:
            mm = re.search(r"\|\||&&|\|(?!\|)|(?<![>&])&(?![&>])|;|\n", rest)
            if not mm:
                break
            op = mm.group()
            if op == "||":
                return True   # fallback for the AND-OR list so far → list can exit 0
            if op == "&":
                return True   # the whole preceding list is backgrounded → step never waits
            if op == "&&":
                seen_list_op = True
                rest = rest[mm.end():].lstrip()  # continue the list (lstrip = skip continuation nl)
                continue
            if op == "|":
                # A pipe in the SCANNER'S OWN pipeline (before any `&&`/`||`) masks its exit
                # unless pipefail. A pipe AFTER `&&`/`||` belongs to a later command that runs
                # only conditionally — not the scanner's failure — so it never masks.
                if not seen_list_op and not pipefail:
                    return True
                rest = rest[mm.end():].lstrip()
                continue
            break  # ';' or newline — end of this statement
    return False

# SCOPE — job SCHEDULABILITY (does the scanner job have a valid `runs-on`, a well-formed
# reusable-workflow `uses:`, a non-cyclic/existent `needs:` graph) is deliberately OUT of
# scope. A job that can't be scheduled is a workflow GitHub REJECTS or never starts — a LOUD
# CI failure (every run red/pending), not a *silent* scanner weakening, so it falls outside
# this drift-detector's threat model. Validating it fully means reimplementing GitHub's
# workflow schema; the ultimate control is CI actually running. (Removed after review showed
# it inviting unbounded schema-validation with no threat-model payoff — see the PR discussion.)

def step_neutered(job, step):
    # continue-on-error is safe ONLY if absent or literal `false`. Literal `true` OR any
    # ${{ }} expression (which could evaluate true at runtime) → cannot certify the scan
    # blocks → FAIL. `truthy()` alone would miss the expression form (a fail-open hole).
    for coe in (job.get("continue-on-error"), step.get("continue-on-error")):
        if coe is not None and norm_expr(coe) != "false":
            return True
    # A step-level `if:` must keep the scan UNCONDITIONAL: absent / always() / success() /
    # true only. An event guard (`github.event_name == 'push'` skips PRs), a constant-false,
    # or any other ${{ }} expression could skip the scan on the very events it must cover.
    sif = norm_expr(step.get("if"))
    if sif is not None and sif not in ("always()", "true", "success()"):
        return True
    if run_neutered(strip_comments(step_run(step))):
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

def _defaults_shell(d):
    run = (d.get("defaults") or {}).get("run") if isinstance(d, dict) else None
    return run.get("shell") if isinstance(run, dict) else None

wf_shell = _defaults_shell(doc)

fail = []

# Invariants 1–4, per scanner: require ≥1 owning step whose job is fail-closed gated,
# is not neutered, and (trivy/semgrep/checkov) is not weakened.
SCANNERS = ("trivy", "semgrep", "checkov", "zizmor")
for scanner in SCANNERS:
    candidates, weakened = [], []
    for jn, job in jobs.items():
        if not isinstance(job, dict):
            continue
        job_shell = _defaults_shell(job)
        for step in steps_of(job):
            if not isinstance(step, dict):
                continue
            # pipefail is per-step: step `shell:` overrides job defaults overrides workflow.
            pf = _pipefail(step.get("shell") or job_shell or wf_shell)
            seg = ""
            if scanner == "trivy":
                is_action = is_trivy_action(step)
                seg = trivy_cli_seg(step)
                if not (is_action or seg):
                    continue
            elif scanner == "semgrep":
                seg = semgrep_seg(step)
                if not seg:
                    continue
            elif scanner == "checkov":
                seg = checkov_seg(step)
                if not seg:
                    continue
            else:  # zizmor
                seg = zizmor_seg(step)
                if not seg:
                    continue
            candidates.append((jn, step))
            reasons = []
            if not gate_ok(job):
                reasons.append("job gate not fail-closed")
            if step_neutered(job, step):
                reasons.append("step neutered (continue-on-error/if-guard/|| true/set +e)")
            if scanner == "trivy":
                ok = trivy_action_hardened(step) if is_action else trivy_cli_hardened(seg)
                if not ok:
                    reasons.append("trivy hardening weak (scanners/severity/exit-code/scan-type)")
                if seg and exit_masked(step_run(step), r"\btrivy\s+(?:fs|filesystem|rootfs|image|config)\b", pf):
                    reasons.append("trivy exit masked (piped / trailing command)")
            elif scanner == "semgrep":
                if not re.search(r"--error\b", seg):
                    reasons.append("semgrep missing --error (exits 0 on findings → fail-open)")
                if exit_masked(step_run(step), r"\bsemgrep\s+scan\b", pf):
                    reasons.append("semgrep exit masked (piped / trailing command)")
            elif scanner == "checkov":
                # checkov non-blocking forms: --soft-fail / --soft-fail-on / its short `-s`
                # (incl. an argparse short-flag CLUSTER `-so json` = `-s -o json`, and a
                # quote-adjacent `'-s'`), and --hard-fail-on (narrows the default "hard-fail on
                # ALL failed checks" set, so any use lowers coverage → fail-closed reject). The
                # cluster regex `-[a-z]*s[a-z]*` is a single-dash short group (won't match long
                # `--skip-path`). ACCEPTED LIMIT: adversarial shell-escaping of the flag (`\-s`,
                # `-''s`, `$'\x2ds'`) evades the regex — the same "not a full shell lexer"
                # boundary documented above; CI actually running checkov is the backstop.
                if re.search(r"--soft-fail(-on)?\b|--hard-fail-on\b|(^|[\s'\"])-[a-z]*s[a-z]*([\s'\"]|$)", seg):
                    reasons.append("checkov non-blocking flag (--soft-fail/-s/--hard-fail-on)")
                if exit_masked(step_run(step), r"\bcheckov\b", pf):
                    reasons.append("checkov exit masked (piped / trailing command)")
            else:  # zizmor
                if exit_masked(step_run(step), r"\bzizmor\b", pf):
                    reasons.append("zizmor exit masked (piped / trailing command)")
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
    runs-on: ubuntu-latest
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
    runs-on: ubuntu-latest
    steps:
      - run: pip install semgrep
      - run: semgrep scan --config p/security-audit --error --exclude tests .
  checkov:
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    runs-on: ubuntu-latest
    steps:
      - run: checkov -d . --skip-path tests --quiet
  zizmor:
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    runs-on: ubuntu-latest
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
    runs-on: ubuntu-latest
    outputs:
      security: ${{ steps.f.outputs.security }}
    steps:
      - id: f
        run: echo security=true >> "$GITHUB_OUTPUT"
  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - run: gitleaks detect
  trivy:
    needs: [changes]
    # reworded comment here
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    runs-on: ubuntu-latest
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
    runs-on: ubuntu-latest
    steps:
      - run: semgrep scan --config p/ci --error .
  checkov:
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    runs-on: ubuntu-latest
    steps:
      - run: checkov --directory . --quiet
  zizmor:
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    runs-on: ubuntu-latest
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

  # `|| echo` fallback swallows the failure (the `||` list exits 0 regardless of shell
  # flags) ⇒ FAIL (inv 4). `|| true`/`:`/`exit 0` are also caught by run_neutered.
  expect 1 "|| echo fallback" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#(checkov -d . --skip-path tests --quiet)#\1 || echo ignored#')"

  # backgrounded scan (`&`) — the step never waits on its exit (shell-flag-independent) ⇒ FAIL
  expect 1 "backgrounded scan" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#(checkov -d . --skip-path tests --quiet)#\1 \&#')"

  # `scanner && printf ok | tee` — the pipe belongs to the &&-command (no `||` fallback,
  # no background); the AND-OR list still exits with the scanner's failure ⇒ PASS
  expect 0 "&& then piped report" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#(semgrep scan --config p/security-audit --error --exclude tests .)#\1 \&\& printf ok | tee log#')"

  # `scanner && echo ok || echo ignored` — the trailing `||` fallback makes the whole
  # AND-OR list exit 0 when the scanner fails ⇒ FAIL (shell-flag-independent mask)
  expect 1 "&& then || fallback" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#(checkov -d . --skip-path tests --quiet)#\1 \&\& echo ok || echo ignored#')"

  # same fallback split across a block-scalar newline (`&&`<nl>`echo || echo`) — the newline
  # after `&&` is a continuation, not statement end ⇒ FAIL (walker continuation fix)
  expect 1 "&& newline then || fallback" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    's#      - run: checkov -d . --skip-path tests --quiet#      - run: |\n          checkov -d . --skip-path tests --quiet \&\&\n          echo ok || echo ignored#')"

  # `scanner && report &` — background `&` terminates the list; the step never waits ⇒ FAIL
  expect 1 "&& then background" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#(checkov -d . --skip-path tests --quiet)#\1 \&\& report \&#')"

  # `scanner | tee` under the DEFAULT shell (no pipefail) — pipeline exit is tee's ⇒ FAIL
  expect 1 "piped no pipefail" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#(semgrep scan --config p/security-audit --error --exclude tests .)#\1 | tee log#')"

  # same pipe under `shell: bash` (pipefail) — the failure propagates ⇒ PASS (no false-positive)
  expect 0 "piped under pipefail" "$(printf '%s\n' "$COMPLIANT" | \
    perl -0pe 's/^jobs:/defaults:\n  run:\n    shell: bash\njobs:/m' | \
    sed -E 's#(semgrep scan --config p/security-audit --error --exclude tests .)#\1 | tee log#')"

  # a trap that forces exit 0 on ERR swallows the scanner's failure ⇒ FAIL (inv 4 — HIGH fix)
  expect 1 "trap exit-0 ERR" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    "s/      - run: checkov -d . --skip-path tests --quiet/      - run: |\n          trap 'exit 0' ERR\n          checkov -d . --skip-path tests --quiet/")"

  # `trap 'exit 0' 0` — signal 0 is the EXIT alias ⇒ FAIL (inv 4 — HIGH fix)
  expect 1 "trap exit-0 signal-0" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    "s/      - run: checkov -d . --skip-path tests --quiet/      - run: |\n          trap 'exit 0' 0\n          checkov -d . --skip-path tests --quiet/")"

  # a plain cleanup trap (no exit-forcing handler) must NOT false-positive ⇒ PASS
  expect 0 "cleanup trap ok" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    "s/      - run: checkov -d . --skip-path tests --quiet/      - run: |\n          trap 'rm -f tmp' EXIT\n          checkov -d . --skip-path tests --quiet/")"

  # `trap 'exit 1' ERR` PRESERVES the failure (not a zero exit) ⇒ PASS (no false-positive)
  expect 0 "trap exit-1 ok" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    "s/      - run: checkov -d . --skip-path tests --quiet/      - run: |\n          trap 'exit 1' ERR\n          checkov -d . --skip-path tests --quiet/")"

  # a `|` INSIDE a quoted arg (`--config 'a|b.yml'`) is DATA, not a pipe ⇒ PASS (no false-positive)
  expect 0 "quoted pipe in config" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E "s#--config p/security-audit --error#--config 'rules|strict.yml' --error#")"

  # scanner logically negated (`! scanner` inverts its exit) in a block scalar ⇒ FAIL (inv 4 — HIGH fix)
  expect 1 "negated semgrep" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    's/      - run: semgrep scan --config p\/security-audit --error --exclude tests \./      - run: |\n          ! semgrep scan --config p\/security-audit --error --exclude tests ./')"

  # negation with an intervening command prefix (`! command semgrep …`) ⇒ FAIL (inv 4 — HIGH fix)
  expect 1 "negated via command prefix" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    's/      - run: semgrep scan --config p\/security-audit --error --exclude tests \./      - run: |\n          ! command semgrep scan --config p\/security-audit --error --exclude tests ./')"

  # negation with an intervening env-assignment (`! FOO=bar semgrep …`) ⇒ FAIL (inv 4 — HIGH fix)
  expect 1 "negated via env-assignment" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    's/      - run: semgrep scan --config p\/security-audit --error --exclude tests \./      - run: |\n          ! FOO=bar semgrep scan --config p\/security-audit --error --exclude tests ./')"

  # negation split across a shell line-continuation (`! \<nl> semgrep`) ⇒ FAIL (inv 4 — HIGH fix)
  expect 1 "negated via line continuation" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    's/      - run: semgrep scan --config p\/security-audit --error --exclude tests \./      - run: |\n          ! \\\n          semgrep scan --config p\/security-audit --error --exclude tests ./')"

  # a `#` INSIDE quotes must not truncate masking detection: `… 'p/x #y' . || echo` is masked ⇒ FAIL (HIGH fix)
  expect 1 "quoted-hash then || echo" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    "s/      - run: semgrep scan --config p\/security-audit --error --exclude tests \./      - run: |\n          semgrep scan --config 'p\/sec #x' --error . || echo ignored/")"

  # an ESCAPED quote inside a double-quoted string must not fake-close it and expose a `#`
  # comment that would strip the trailing `|| echo` mask ⇒ FAIL (HIGH fix)
  expect 1 "escaped-quote then || echo" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    "s/      - run: semgrep scan --config p\/security-audit --error --exclude tests \./      - run: |\n          semgrep scan --error --config \"p\/sec \\\\\" #x\" . || echo ignored/")"

  # echo-wrapped scanner (`echo "semgrep scan --error ."`) is NOT a real invocation ⇒
  # FAIL (inv 1 — HIGH fix: comments/echo must not satisfy presence).
  expect 1 "echo-wrapped semgrep" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#      - run: semgrep scan --config p/security-audit --error --exclude tests .#      - run: echo "semgrep scan --error ."#')"

  # commented invocation (`-d` only inside a `# comment`) is stripped ⇒ FAIL (inv 1 — HIGH fix).
  expect 1 "commented checkov" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's@      - run: checkov -d . --skip-path tests --quiet@      - run: checkov --version  # checkov -d .@')"

  # expression-valued continue-on-error (could evaluate true) ⇒ FAIL (inv 4 — HIGH fix).
  expect 1 "expr continue-on-error" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    "s/(      - run: checkov -d \. --skip-path tests --quiet)/      - continue-on-error: \\\${{ github.event_name == 'pull_request' }}\n        run: checkov -d . --skip-path tests --quiet/")"

  # step-level event-guard if: (skips the scan on PRs) ⇒ FAIL (inv 4 — HIGH fix).
  expect 1 "step event-guard if" "$(printf '%s\n' "$COMPLIANT" | perl -0pe \
    "s/(      - run: checkov -d \. --skip-path tests --quiet)/      - if: github.event_name == 'push'\n        run: checkov -d . --skip-path tests --quiet/")"

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

  # checkov short `-s` (soft-fail) ⇒ FAIL
  expect 1 "checkov -s" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#checkov -d . --skip-path tests --quiet#checkov -d . -s --quiet#')"

  # checkov --hard-fail-on narrows the blocking set ⇒ FAIL
  expect 1 "checkov --hard-fail-on" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#checkov -d . --skip-path tests --quiet#checkov -d . --hard-fail-on CKV_NEVER#')"

  # checkov short-flag CLUSTER `-so json` (= `-s -o json`) soft-fails ⇒ FAIL
  expect 1 "checkov -s cluster" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E 's#checkov -d . --skip-path tests --quiet#checkov -d . -so json#')"

  # checkov QUOTED soft-fail flag (`'-s'` survives shell quoting to checkov) ⇒ FAIL
  expect 1 "checkov quoted -s" "$(printf '%s\n' "$COMPLIANT" | \
    sed -E "s#checkov -d . --skip-path tests --quiet#checkov -d . '-s' --quiet#")"

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
  # Portable read loop — NOT `mapfile`, which macOS's Bash 3.2 lacks (this script and
  # its self-test must run on a stock macOS maintainer box, not just the CI runner).
  parsed=()
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [[ -n "$line" ]] && parsed+=("$line")
  done < "$tfleet"
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
