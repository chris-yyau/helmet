# Plan: Fleet scanner-invariant check (#76, reframed)

**Status:** DRAFT — in blueprint-review (iteration 2, addressing iteration-1 findings)
**Date:** 2026-07-15
**Issue:** #76 (reframed — see "Why the reframe")

## Why the reframe

#76 as filed proposed a **whole-document content hash** of each fleet mirror's
`security.yml` against helmet's canonical, with a "tiny per-repo divergence allowlist."
Measurement on the live fleet (2026-07-15) refutes that premise:

| Mirror | changed lines vs canonical | nature of divergence |
|--------|---------------------------|----------------------|
| chris-yyau/busdriver | 152 | repo-specific paths (`hooks/**`, `scripts/**`, `.seatbelt.yml`), an extra `gitleaks` job, older-but-valid pins, reworded comments |
| Dive-And-Dev/chrisyau.me | 74 | version drift + reworded comments |
| Dive-And-Dev/perch | 72 | version drift + reworded comments |

Mirrors are **independently-evolved, legitimately-customized snapshots**, not
byte-identical-modulo-one-line copies (which is what the *local* #66 template↔live
pair is). A whole-document hash would flag every mirror as massively "drifted," and a
per-repo allowlist would have to encode 72–152 lines of benign divergence per mirror —
and re-drift on every canonical edit. Unmaintainable.

The **real risk** #76 names — "a mirror-local edit weakens security and goes
undetected" — is genuine. Byte-parity is the wrong instrument. A **semantic invariant
check** is the right one: assert the security-critical properties still hold, tolerate
legitimate customization.

## Goal

A maintainer-run (on-demand / scheduled) fleet check that, for each mirror's live
`security.yml`, asserts a fixed set of **security-critical invariants** and fails loud
on any mirror that has *weakened* one — independent of benign customization or version drift.

**Non-goals:** byte-parity; version-currency (the existing stamp scan owns that);
converging the fleet's `with:` keys; per-repo allowlists; verifying the `changes`
detector's shell logic (see "Residual — scope boundary").

## Canonical reference (verified against `.github/workflows/security.yml`)

The invariants below are derived from helmet's own live `security.yml`, cited by line:
- Scanner jobs `trivy`/`semgrep`/`checkov`/`zizmor`, each gated `if: always() &&
  (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')`
  (security.yml:122,148,169,190). The `always()` is load-bearing — a job with
  `needs: [changes]` is **skipped** by GitHub's implicit `success()` when `changes`
  fails/cancels *unless* `always()` is present. Dropping `always()` is fail-OPEN.
- trivy step `with:` → `scan-type: fs`, `scanners: vuln`, `severity: HIGH,CRITICAL`,
  `exit-code: 1` (security.yml:138-143). `ignore-unfixed`/`skip-dirs` are hygiene keys
  that vary across the fleet and are NOT required (a mirror without them is *stricter*).
- semgrep runs a **blocking scan** step `semgrep scan --config ... --error` (security.yml:164),
  SEPARATE from its install step (security.yml:162). checkov: `checkov -d . ...` (185).
  zizmor: `zizmor ... .github/workflows/` (206/212). trivy uses the `aquasecurity/trivy-action`
  step (136-143).

## Invariants (the assertion set)

Parse each mirror's `security.yml` into structure (jobs → steps → `if`/`with`/`run`/`uses`),
then assert. Each invariant fires ONLY when a mirror is **less strict** than the contract;
never on benign customization or on being stricter.

1. **Four blocking scanners present.** A job must contain a **blocking execution step** for
   each of trivy, semgrep, checkov, zizmor — bound to the real invocation, NOT a mere token:
   - trivy: a step whose `uses:` is `aquasecurity/trivy-action@*` (action form) OR a `run:`
     invoking `trivy` with a scan target (CLI form).
   - semgrep: a `run:` step invoking `semgrep scan` (the scan, not `pip install semgrep`).
   - checkov: a `run:` step invoking `checkov -d`/`checkov --directory`.
   - zizmor: a `run:` step invoking `zizmor ... .github/workflows` (or a dir target).
   Reject install-only, comments, `echo`, and steps neutralized per invariant 4.
   Missing any scanner ⇒ FAIL.

2. **Each scanner job is fail-closed gated** (the crux). For the JOB that owns each scanner
   step, its `if:` must be one of these normalized-compliant shapes (whitespace/quote-normalized,
   detector job id parameterized from the job's own `needs`):
   - **No gate dependency** — the job's `needs:` does NOT include the detector (`changes`)
     job ⇒ it is truly always scheduled ⇒ PASS. (A scanner with no `needs: [changes]` runs
     unconditionally, which is fail-*closed*.)
   - **Gated but fail-closed** — the job `needs: [changes]` AND its `if:` contains BOTH a
     status-continuation function (`always()`; `!cancelled()` is NOT accepted — it still
     skips on a *failed* detector) AND a detector-failure backstop equivalent to
     `needs.changes.result != 'success'`.
   Explicitly FAIL: `needs: [changes]` with **absent** `if:` (implicit `success()` → skipped
   when detector fails → fail-OPEN); an `if:` that has the `result != 'success'` backstop but
   dropped `always()`; a dead-conjunction gate (`false && ...`). This is a small whitelist of
   accepted shapes, NOT a substring search.

3. **trivy hardening intact, scoped to the trivy step.** On the matched trivy step:
   - Action form: `with.scanners` includes `vuln`; `with.severity` includes both `HIGH` and
     `CRITICAL`; `with.exit-code` == `1` (normalize string vs int). `scan-type: fs` present.
   - CLI form: effective `--scanners vuln`, `--severity HIGH,CRITICAL`, `--exit-code 1`, a real
     scan target. (trivy defaults `--exit-code` to 0 → an omitted exit-code is fail-open ⇒ FAIL.)
   A compliant-looking key on the WRONG step, or `scanners: secret` (no CVE scanning), ⇒ FAIL.
   (Do NOT require `ignore-unfixed`/`skip-dirs` — benign hygiene, and their absence is stricter.)

4. **No scanner neutered.** The scanner's blocking step must not be suppressed:
   `continue-on-error: true` at **step OR job** level, a trailing `|| true`/`|| :` on the
   scan command, or `if: false`/a constant-false gate on the step ⇒ FAIL.

5. **Workflow reachability.** The `on:` triggers must let the workflow actually start:
   the `pull_request:` trigger must have **no `paths:`/`paths-ignore:` filter** (canonical
   security.yml:3-5 — an unfiltered PR trigger; a mirror that added a PR path filter could make
   a required scanner check never register). The `push:` trigger MAY keep its path filter
   (canonical does). Missing `pull_request:` trigger entirely ⇒ FAIL.

## Residual — scope boundary (honest limits)

This check catches a mirror edited to *weaken a scanner's gate, hardening, presence, or
suppression*. It does **NOT** verify the `changes` detector's shell logic. A detector rewritten
to always emit `security=false` while succeeding (`result == 'success'`) would skip every scanner,
and invariant 2's `always() + result != 'success'` backstop only catches a *failed/cancelled*
detector, not a *lying-but-successful* one. Deep-parsing the detector's fail-closed shell is the
adversarial-YAML/shell hole #66 deliberately closed by NOT parsing; re-opening it here is out of
scope. **The ultimate control is CI actually running the scanners on every PR/push** — this fleet
check is drift-detection over the gating *shape*, not a sandbox for a hostile maintainer. Documented
as a `SCOPE` comment in the script (mirroring #66's `normalize_doc` SCOPE note).

## Design

- **New sibling script** `scripts/check-fleet-scanner-invariants.sh` (not folding into
  `check-pipeline-drift.sh` — that script owns the version-stamp concern on `bypass-audit.yml`).
  Reuse its proven fleet plumbing: `.helmet-fleet` parsing (see fleet scope below), `gh api ...
  --raw` fetch, the same missing/no-access fail-closed handling, and the same exit-code contract
  (**0** = all invariants hold on all reachable mirrors; **1** = ≥1 mirror weakened OR unreadable/
  unparseable; **2** = setup/usage error incl. missing parser dependency).
- **Fleet scope.** Same `.helmet-fleet` list the stamp scan uses — the **stamp-bearing push-time
  repos** (`.helmet-fleet.example`: busdriver, helmet, perch, chrisyau.me, jikdak, growth-engine,
  diveanddev.com); `chris-yyau/seatbelt` is a documented scheduled-sweep exception (ADR-0001) and is
  NOT in the list. The check runs on every listed repo regardless of version stamp (a version-behind
  mirror must still hold fail-closed scanners). Wording corrected from the earlier "ALL fleet mirrors."
- **Parser.** `python3` + **PyYAML** (`yaml`). This is **NOT currently a repo/runner dependency**
  (verified: zero `import yaml` in `scripts/`/`.github/`, no requirements manifest). So:
  fail-CLOSED with exit 2 and a clear `ERROR: python3 + PyYAML required (pip install pyyaml)` if
  either is absent — never a silent skip. Rationale for a real parser over grep/awk: the invariants
  need job→step structure, `with:` maps, and `if:` expressions; grep/awk over multi-line YAML is the
  fragile path. The maintainer already needs `gh`+`jq`; PyYAML is one documented add, asserted up front.
- **Fetch/parse failure** (not found / no access / unparseable YAML) ⇒ reported + counts toward the
  nonzero exit (a mirror that can't be certified is not silently passed), mirroring `check-pipeline-drift.sh`.

## Self-test (fail-closed proof) + CI wiring

`--self-test` mode with in-script fixtures (no network), each asserting the expected verdict.
**Wired into CI** — add `check-fleet-scanner-invariants.sh --self-test` to `tests.yml`'s
`version-drift` job alongside the existing `check-template-pins.sh --self-test` (tests.yml:34-37),
so the fail-closed proof can't silently rot. (The live-fleet run stays maintainer-only — it needs
`gh`/network — but `--self-test` is hermetic.)

Fixtures (each with expected verdict):
- **compliant** baseline (canonical-shaped, action-form trivy) ⇒ PASS.
- **compliant CLI-form trivy** (`run: trivy fs --scanners vuln --severity HIGH,CRITICAL --exit-code 1`) ⇒ PASS.
- **missing scanner** (drop the trivy job) ⇒ FAIL (inv 1).
- **install-only semgrep** (keep `pip install semgrep`, delete the `semgrep scan` step) ⇒ FAIL (inv 1).
- **dropped `always()`** (`if: needs.changes.outputs.security == 'true' || needs.changes.result != 'success'`, no `always()`) ⇒ FAIL (inv 2).
- **absent `if:` with `needs: [changes]`** ⇒ FAIL (inv 2, fail-open).
- **dead-conjunction gate** (`if: false && always()`) ⇒ FAIL (inv 2).
- **no-`needs`/no-`if` scanner** (truly unconditional) ⇒ PASS (inv 2 — stricter).
- **trivy `scanners: secret`** (no vuln scanning) ⇒ FAIL (inv 3).
- **trivy severity narrowed** (`severity: CRITICAL` only) / **exit-code omitted or 0** ⇒ FAIL (inv 3).
- **compliant keys on the WRONG step** ⇒ FAIL (inv 3 — must be scoped to the trivy step).
- **step-level `continue-on-error: true`** on the scan step / **trailing `|| true`** ⇒ FAIL (inv 4).
- **PR-trigger path filter added** ⇒ FAIL (inv 5, reachability).
- **benign customization** (extra `gitleaks` job, repo-specific paths, older pins, absent
  `ignore-unfixed`, reworded comments) ⇒ PASS (the anti-false-positive proof — the whole point).
- **unparseable YAML** ⇒ FAIL (fail-closed, exit contributes to 1).
- **fleet parsing** (comment/blank-line handling in a temp `.helmet-fleet`) and **mocked `gh` failure /
  empty API body** ⇒ counts toward nonzero exit, not a silent pass.
- **missing PyYAML** path ⇒ exit 2 (distinct from exit 1) — asserted via a stubbed `python3`.

## Out of scope / follow-ups

- Wiring the **live-fleet run into a scheduled workflow** (weekly, like `scorecard.yml`) — deferred;
  overlaps #64's scheduled-scan theme. This plan delivers the script + hermetic `--self-test` + its CI
  wiring; scheduling the networked fleet sweep is a separate small PR once the check is trusted.
- Version-stamp drift — already owned by `check-pipeline-drift.sh`.
- Verifying the `changes` detector's shell logic — see "Residual — scope boundary."

## Build order

1. `scripts/check-fleet-scanner-invariants.sh` — header (WHY/USAGE/EXIT/REQUIRES incl. PyYAML) +
   fleet plumbing (reuse the `check-pipeline-drift.sh` pattern) + a `python3`/PyYAML availability
   guard (exit 2 if absent) + the per-mirror parse-and-assert (invariants 1–5) + exit-code contract.
2. `--self-test` fixtures (the cases above), run hermetically.
3. Wire `--self-test` into `tests.yml`'s `version-drift` job.
4. Run `--self-test` → PASS; run against the live fleet → triage real findings (a genuinely weakened
   mirror is a real bug to file/fix, not a script bug).
5. Docs: a row in `.claude/CLAUDE.md`'s `## Commands` table (that file IS tracked and has the table),
   plus the script header block.

<!-- design-reviewed: PASS -->
<!-- design-review-coverage: DEGRADED 2/3 reviewer_1=runtime-droid-rescue -->
