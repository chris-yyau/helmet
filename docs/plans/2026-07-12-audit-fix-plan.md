# Audit Fix Plan — 2026-07-12

Source: full-plugin audit (inline, every finding primary-source-verified; fleet gap
confirmed by reading perch/busdriver/chrisyau.me workflows via `gh api`).
12 findings → 5 PR streams (PR-4 is one PR per affected mirror) + 3 follow-up issues
(filed as a prerequisite step, see below).

## Design decision: DELETE the trivy skip-step, don't harden it

The fail-open (finding 1) lives in the "Check for compliance job" step: a marker grep
over tests.yml that can never prove what it needs to prove (an *enabled, push-triggered,
blocking* compliance job — vs. a comment, an `if: false` job, a PR-only job, or an
advisory `exit-code: 0` scan). Review iterations 1–4 kept finding new holes in the
guard (event-guard, anchored grep, parameterized test harness, ambiguous preflight);
each patch added machinery to defend an optimization whose entire value is ~1 billable
runner-minute per push on repos that have a compliance job.

**Decision: remove the step outright — canon is "security.yml always scans".** The
scan step loses its `if:` and the check step is deleted, in helmet live, the SKILL.md
template, and all six mirrors. Cost: on mirrors with a compliance trivy job, a push to
main runs trivy twice (compliance + security.yml), ~1 duplicate minute per push.
Benefit: the required check "Dependency CVEs" always means "a scan ran", with zero
conditional logic to drift, test, or bypass — the whole guard-test/marker-grep/
preflight apparatus becomes unnecessary. (Supersedes the 2026-07-10 "keep for cascade
parity" decision: parity is now achieved by deleting the step everywhere.)

## Prerequisite: file the follow-up issues FIRST

Before PR-1a lands, file the three issues in the "Follow-up issues to file" section
(gh confirms none exist yet — only #63/#64 are open) and paste their numbers into
this plan and into the pin comments that reference them. This keeps every "see issue
#N" pointer in shipped code deterministic, never a dead prose pointer.

## Dependency graph (land order)

```text
file 3 issues ─> PR-1a (thin cascade canon: de-skip + pins) ──> PR-4 (cascade — immediately)
                                                           └──> PR-1b (live security.yml sync) ──> PR-2 (docs: SKILL.md)
PR-3 (fix: scripts) — independent in content; lands any time, but both PR-1a and PR-3
                      append steps to the same tests.yml `version-drift` job — whichever
                      lands second rebases over a trivial adjacent-line conflict.
```

- **PR-1a is deliberately thin** (skip-step removal + `with:` canon + three pip pins +
  CI-wired pip parity): it is everything PR-4 needs — a complete, self-consistent
  cascade canon — and nothing else. Finding 1 is the only HIGH — its fix must not
  queue behind the riskier permissions/paths refactor (PR-1b) or a docs PR (PR-2).
- **PR-4 immediately after PR-1a**, parallel with PR-1b/PR-2.
- **PR-2 after PR-1b**: template text must match the canon the PR-1x pair ships.
- **PR-4 is a SURGICAL PATCH, never a wholesale file copy** — see PR-4 preamble.

## Finding → PR map

| # | Finding | Severity | PR |
|---|---------|----------|----|
| 1 | PR-time trivy fail-open in perch/busdriver/chrisyau.me (skip-step suppresses the scan while compliance trivy is push-only → "Dependency CVEs" required check passes green with no scan) | HIGH | PR-4 (canon in PR-1a) |
| 2 | helmet live `security.yml` trivy skip-step lacks the push-guard the template has (no-op locally, but it is the cascade source) — resolved by deleting the step on both sides | MED | PR-1a |
| 3 | Live `security.yml` installs semgrep/checkov/zizmor unpinned (issue #63) vs pinned template | MED | PR-1a |
| 4 | `.releaserc.json` template: `@semantic-release/changelog` without `@semantic-release/git` — CHANGELOG.md generated then discarded | MED | PR-2 |
| 5 | B1b script block uses `$DEFAULT_BRANCH` never set in the block → `branches//protection` 404 on copy-paste | MED | PR-2 |
| 6 | Release template missing `concurrency:`; commitlint template missing `timeout-minutes` — violate helmet's own B2 rules | MED | PR-2 |
| 7 | zizmor invocation drift: live `--config .zizmor.yml` vs template `--min-severity high --min-confidence high` — undocumented divergence | LOW | PR-1b + PR-2 (document as intentional) |
| 8 | reports-job drift: template has fail-propagation + no harden-runner; live is the inverse | LOW | PR-1b + PR-2 |
| 9 | `check-required-checks.sh` surface (c) certifies "ok" off a commit with zero required-named check-runs | LOW | PR-3 |
| 10 | `check-required-checks.sh --help` sed range `3,42p` truncates the exit-codes section | LOW | PR-3 |
| 11 | Live `check-pinned-uses.sh` regex `@[0-9a-f]{40}$` weaker than template's anchored `^[^@]+@[0-9a-f]{40}$` | LOW | PR-3 |
| 12 | Section I contradiction: Step 5 `npm install -D semantic-release …` vs Key point "always npx, no dev deps" | LOW | PR-2 |

Review-added findings folded into the PRs below: unpinned `npx -p semantic-release …`
in a `contents: write` job (template SKILL.md:2351 AND live release.yml — the same
supply-chain class as finding 3) → PR-1b (live) + PR-2 (template); `ignore-unfixed:
true` live but absent from the Section N template despite the recorded council
decision (SKILL.md:3872) → PR-1a; workflow-level permissions form differs → PR-1b;
push `paths:` lists differ → PR-1b/PR-2; stale Key points at SKILL.md:3160 (→ PR-1a,
same-PR as the body edit it describes) and ~3897 (→ PR-2); B2 "Security workflow uses
paths" fragment (SKILL.md:1781-1805) models the `pull_request:` + `paths:` pattern
Section N forbids → PR-2.

## Shared divergence allowlist (single source of truth)

Used verbatim by the PR-1b inventory, the PR-2 re-run, and follow-up issue 1's
content-hash detector. After PR-1b + PR-2, the ONLY permitted non-comment difference
between live `security.yml` and the Section N fenced template is:

| # | Live line | Template line | Sentinel |
|---|-----------|---------------|----------|
| 1 | `run: zizmor --config .zizmor.yml .github/workflows/` | `run: zizmor --min-severity high --min-confidence high .github/workflows/` | `RUN_ZIZMOR_INVOCATION` |

Exactly one line. (The `.zizmor.yml` file itself is a separate repo file, not part of
the security.yml diff, and needs no allowlist entry.)

## PR-1a `fix:` — thin cascade canon (unblocks PR-4)

**Branch:** `fix/trivy-always-scan-and-scanner-pins`

1. **Delete the "Check for compliance job" step** from the live trivy job
   (`security.yml:129-135`) AND from the Section N template (SKILL.md:3040-3048),
   and remove `if: steps.check.outputs.skip != 'true'` from the scan step on both
   sides. Per the design decision above: security.yml always scans; the duplicate
   push-time scan on compliance-carrying repos is accepted.
2. **Trivy scan-step `with:` canon** (both sides, and what PR-4 asserts):
   `scan-type: fs`, `scanners: vuln`, `severity: HIGH,CRITICAL`,
   `ignore-unfixed: true`, `exit-code: 1`, `skip-dirs: tests`.
   Live gains `skip-dirs: tests`; the template `with:` block (SKILL.md:3052-3057)
   gains `ignore-unfixed: true` (recorded council decision, SKILL.md:3872) — in this
   PR, not PR-2, so the cascade canon is internally consistent from day one.
3. **Same-PR prose lockstep**: rewrite the Key point at SKILL.md:3160 in the same PR
   as the body edit it describes: "security.yml always runs trivy on PRs and pushes;
   repos with a push-only compliance trivy job accept one duplicate push-time scan
   (~1 runner-minute) — no conditional skip logic." (The broader B2-fragment/~3897
   prose work stays in PR-2.)
4. **Pin scanner installs** (`security.yml:161,180,201`) — closes issue #63. At
   execution time, resolve the CURRENT latest stable of each from PyPI (do **not**
   copy the template's 2026-07-10 pins blindly). Pin live AND update the three
   template pin lines (SKILL.md:3076/3097/3120) **in this same PR** (mechanical
   lockstep — no window where live and template pins disagree). Each line keeps the
   `# Pin version — unpinned is a supply chain risk` comment plus
   `# lockstep: see issue #<pip-cadence issue>` (number from the prerequisite step).
   **Record the three landed versions in the PR description** — PR-4 copies them
   verbatim (see PR-4 item 2).
5. **DESCOPED (2026-07-12) → follow-up issue 1 (#66).** A bespoke pip-pin parity
   function was implemented and reviewed, but litmus escalated it toward a full
   install-form parser (bind-to-install, `python -m pip`/`uv pip`, requirements
   files) beyond helmet's drift threat model. Decision: drop the bespoke function;
   the whole-document content-hash detector (#66) is the designated parity
   mechanism and covers these pins structurally. PR-1a ships de-skip + `with:`
   canon + live/template pins only. Original spec retained below for #66's use.
   **Pip-pin parity enforced in CI, not by discipline** — add a parity function
   (~10 lines) to `scripts/check-template-pins.sh`: extract every `NAME==VER` for
   semgrep/checkov/zizmor from live `security.yml` and from the Section N fenced
   block (awk bounded by the `#### N. Security Scanning Backstop` heading and the
   `**Required file:**` line, guarded to fail on zero or multiple fenced blocks);
   fail on missing, duplicate, or unequal. **Permanent fixtures:** extend the
   script's existing `--self-test` harness with pip cases (equal / missing /
   duplicate / unequal / malformed), and add `--self-test` as a step in the
   `version-drift` job (tests.yml currently runs the script without it — verified
   tests.yml:33) so the fixtures run in CI on every PR.

**Verify (PR-1a):**
- Structure, not just grep: extract the live trivy job and the Section N fenced block;
  `yaml.safe_load` both; assert the trivy job has exactly two steps before the scan
  (harden-runner, checkout), the scan step has NO `if:`, and its `with:` equals the
  six-key canon on both sides.
- Pinned versions exist on PyPI: `pip index versions semgrep` (etc.).
- `./scripts/check-template-pins.sh` → 0 (action + pip parity);
  `--self-test` → PASS including the new pip fixtures.
- `bash .github/scripts/check-pinned-uses.sh` → 0.
- SKILL.md:3160 Key point contains "always runs trivy".
- Push → all six required checks green; this PR touches `.github/` so the `changes`
  detector forces all scanners — confirm the trivy job log shows an actual scan.

## PR-1b `fix:` — remaining live sync (security.yml + release.yml)

**Branch:** `fix/security-release-template-sync` — after PR-1a.

1. **Permissions model** — align live to the template's stricter form: workflow-level
   `permissions: {}` (currently `contents: read`, security.yml:27-28) with explicit
   `contents: read` on each job. NOTE: today only the `changes` job has a job-level
   block — the workflow-level read is load-bearing for trivy/semgrep/checkov/zizmor,
   so each of those four MUST gain `permissions: contents: read` in the same edit;
   `reports` needs no contents scope. Template form also satisfies checkov CKV2_GHA_1.
2. **Push `paths:` union** — add the template's four lockfile globs to live
   (`**/pyproject.toml`, `**/uv.lock`, `**/Cargo.lock`, `**/Package.resolved`). Live's
   extra `**/*.yaml` is correct and stays; PR-2 adds it to the template.
3. **reports job fail-propagation** — append the template's exit-1 block
   (SKILL.md:3146-3149) to the live reports step. Harmless (scanners are individually
   required) and removes one standing logic diff.
4. **zizmor divergence marker** — above the live `zizmor --config .zizmor.yml` line, add:
   `# INTENTIONAL divergence from the SKILL.md template (--min-severity high): helmet
   dogfoods the strict all-severity gate; consumers get high-only to avoid onboarding
   friction. See the shared divergence allowlist (one line). Mirrored comment in
   SKILL.md N.` (PR-2 adds the mirror.)
5. **Pin the live release.yml npx line** — `npx -y -p semantic-release@X
   -p @semantic-release/changelog@X -p @semantic-release/exec@X
   -p @semantic-release/git@X -p @semantic-release/github@X semantic-release`
   (versions resolved at execution, recorded in the PR description). This job holds
   `contents: write` + RELEASE_TOKEN — the same unpinned-supply-chain class as
   finding 3. Folded into follow-up issue 3's refresh cadence. (PR-2 pins the
   template's Step-3 npx line to match.)
6. **Converge run-block wording** — any `run:`-block string that differs between live
   and template (e.g. `::warning::` message texts) is converged here, on whichever
   side is better-worded. After PR-1b + PR-2, the only non-comment divergence left is
   allowlist line 1.

**Verify (PR-1b):**
- **Full-file diff inventory** — extract the Section N fenced block (same guarded awk
  bounds as PR-1a item 5); strip comment lines and blank lines from both sides; diff
  against the live file. Every residual hunk must fall into one of THREE pre-declared
  buckets: (a) fixed by PR-1a/PR-1b, (b) the shared divergence allowlist (exactly
  line 1), or (c) PR-2-pending (`**/*.yaml` into template paths, reports
  harden-runner into template, divergence-mirror comment, template npx pins).
  **No wording-drift bucket** — surviving non-comment wording hunks are converged by
  item 6, not listed. Anything outside all three buckets = scope miss: fix it or
  re-bucket before merge.
- **Job-grant assertions**: top-level `permissions:` is exactly `{}`; each of
  `changes`/`trivy`/`semgrep`/`checkov`/`zizmor` has a job-level `contents: read`;
  `reports` has no contents scope. (yaml.safe_load over the parsed doc, not grep.)
- release.yml still releases: the npx pin change is exercised by the release run on
  merge to main (semantic-release exits 0, no-release-needed is a clean outcome).
- Push → all six required checks green.

## PR-2 `docs:` — SKILL.md template fixes

**Branch:** `docs/skill-template-fixes` — **after PR-1b**.

1. **Release changelog (finding 4) — Option A (recommended): remove
   `@semantic-release/changelog` from the consumer template** (`SKILL.md:2297-2310`
   `.releaserc.json` + the Step-3 npx line ~2351 + the Step-5 dep list).
   Rationale: release notes already live on GitHub Releases
   (`release-notes-generator` + `@semantic-release/github`); a committed CHANGELOG
   requires `@semantic-release/git` pushing to protected main, which needs helmet's
   `RELEASE_TOKEN || GITHUB_TOKEN` PAT pattern — extra failure modes for marginal
   value. Helmet's own repo keeps changelog+git (it has the PAT pattern and manifests
   to sync); add one sentence to the template noting "helmet's own release.yml
   additionally commits CHANGELOG.md + version manifests via @semantic-release/git —
   see it for the full pattern if you need a committed changelog (requires a push
   token that can bypass branch protection)."
   *Alternative (Option B, not recommended): copy helmet's full git-plugin pattern
   into the template — adds RELEASE_TOKEN setup + persist-credentials:true + zizmor
   ignore to every consumer for a file most repos never read.*
2. **Pin the template Step-3 npx line** (~2351) to the same versions PR-1b pinned in
   live release.yml (minus the plugins Option A removes). Same supply-chain rationale;
   same cadence issue reference.
3. **B1b `DEFAULT_BRANCH` (finding 5)** — add to the B1b block, right after
   `OWNER=`/`REPO=` (~SKILL.md:1484):
   `DEFAULT_BRANCH=$(gh api "repos/$OWNER/$REPO" --jq '.default_branch')`
4. **B2-rule compliance in templates (finding 6):**
   - Release template (~2317): add the concurrency block — **block form** (the flow
     form `{ group: … }` is invalid YAML around `${{ }}`, empirically parse-tested):

     ```yaml
     concurrency:
       group: release-${{ github.ref }}
       cancel-in-progress: false
     ```

   - Commitlint job template (~2364): add `timeout-minutes: 5`.
5. **Step 5 contradiction (finding 12)** — delete the `npm install -D …` step; replace
   with one line: "No dev dependencies required — CI installs via npx / `--no-save`."
6. **Pip pin comment mirror (finding 3)** — pins + parity check landed in PR-1a; ensure
   the template pin lines carry the same
   `# lockstep: see issue #<pip-cadence issue>` comment as live.
7. **zizmor divergence mirror (finding 7)** — in section N near the template zizmor
   step, add the counterpart comment marking live-helmet's `--config` form as an
   intentional dogfooding divergence (allowlist line 1).
8. **reports template harden-runner (finding 8) — BOTH sites**: the reports job
   template appears twice, `SKILL.md:~1836` (B2) and `SKILL.md:~3124` (Section N).
   Add the harden-runner first step to **both** fenced blocks, matching live.
9. **B2 "Security workflow uses paths" fragment (SKILL.md:1781-1805)** — it models
   `on: pull_request: paths:`, the exact pattern Section N (SKILL.md:2902-2904)
   forbids when scanner jobs are required checks (workflow never starts → required
   check reported absent → merge blocks). Replace the fragment with the push-trigger
   paths + changes-job pattern and a pointer to Section N (or delete it and reference
   Section N outright). If a paths list is kept, sync its globs with Section N
   (including `**/*.yaml`).
10. **Template push `paths:`** — add `**/*.yaml` to the Section N template push paths
    list (~2919), matching live.
11. **Stale Key point ~3897** (Key Decisions bullet restating "Security workflow uses
    `paths`") — align with the changes-job pattern: paths filtering applies to the
    push trigger only; the PR trigger is unfiltered with job-level gating. (3160 was
    fixed in PR-1a, lockstep with the body edit.)
12. **Converge remaining template-side wording** per PR-1b item 6 — after this PR, the
    live↔template diff equals exactly the shared divergence allowlist.

**Verify (PR-2):**
- **Parse, don't just grep**: extract each modified fenced YAML block with the guarded
  awk bounds and `yaml.safe_load` it, asserting the inserted keys structurally —
  release template: top-level `concurrency.group == "release-${{ github.ref }}"` and
  `cancel-in-progress == false`; commitlint job: `timeout-minutes: 5` at job level;
  both reports blocks: first step name is Harden Runner and it precedes "Write
  summary"; Section N paths list contains `**/*.yaml`. Keep grep for prose-only
  assertions.
- `./scripts/check-template-pins.sh` → 0 (action + pip parity); `--self-test` → PASS.
- `! grep -q 'npm install -D semantic-release' skills/helmet/SKILL.md`.
- B1b block defines `DEFAULT_BRANCH` before first use.
- `@semantic-release/changelog` count in the consumer template section = 0
  (helmet-own references elsewhere may remain); template Step-3 npx line carries
  `@<version>` pins.
- B2 fragment no longer contains `pull_request:` followed by `paths:`; Section N
  pointer present. Key point ~3897 no longer implies PR-trigger paths filtering.
- Re-run the PR-1b full-file diff inventory (comment-stripped): bucket (c) empty —
  the remaining diff is exactly the shared divergence allowlist (one line).

## PR-3 `fix:` — script improvements (independent in content)

**Branch:** `fix/checker-script-polish`
(Lands any time; if after PR-1a, rebase the tests.yml `version-drift` step addition
over PR-1a's — trivial adjacent-line conflict.)

**Deliverables include the test + CI wiring, not just the fixes:**
`scripts/check-required-checks.sh` changes, `scripts/test-check-required-checks.sh`
(mock-`gh` fixture suite, no network), a `version-drift` job step running it, and the
`check-pinned-uses.sh` regex fix.

1. **Surface (c) zero-evidence ok (finding 9)** (`scripts/check-required-checks.sh:628-683`)
   — two changes, with `--strict-remote` semantics preserved exactly:
   - *Commit walk*: accept a commit only when it has ≥1 check-run whose name matches a
     lock-required name: `req_hits=$(echo "$rj" | jq --argjson names "$(jq -c '[.required[].name]' "$LOCK")" '[.[] | select(.name as $n | $names | index($n))] | length')`,
     accept when `req_hits > 0`, else keep walking. (Verified compatible with
     `matrix_value` entries — lock `name` holds the full rendered name.)
     **Three distinct exhaustion states** (today's code conflates the first two):
     1. *No check-runs fetched at all in 10 commits* → unavailability: warn by
        default, **DRIFT under `--strict-remote`** (unchanged from today);
     2. *Runs exist but none lock-named in 10 commits* → a valid repo state
        (docs-only / path-filtered pushes) → **warn-only in BOTH modes**, message:
        "check-runs found but none lock-named in last 10 commits — likely docs-only
        pushes; skipping app check";
     3. *Empty `required` array* → explicit successful skip ("nothing to verify"),
        exit path unchanged.
   - *Honest summary*: define the three per-check states — **verified** (run present
     AND `app.slug` matches), **mismatch** (present AND slug differs → DRIFT, counted,
     shown), **missing** (no run for that name → warn-only, `--strict-remote`
     unchanged). Print the all-clear ONLY when `verified == lock count AND
     mismatch == 0`; otherwise print
     `"verified V of N source_apps; missing M (warn-only); mismatch X (drift)"`.
2. **`--help` truncation (finding 10)**: replace `sed -n '3,42p'` with the marker-based
   form `sed -n '/^# check-required-checks/,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'`
   — line numbers rot.
3. **check-pinned-uses.sh regex (finding 11)** (`.github/scripts/check-pinned-uses.sh:17`):
   `@[0-9a-f]{40}$` → `^[^@]+@[0-9a-f]{40}$` (template form; rejects empty-action and
   double-`@` refs). Keep template text unchanged.

**Verify (PR-3):**
- `shellcheck -S warning scripts/*.sh .github/scripts/*.sh` clean.
- `scripts/test-check-required-checks.sh` (mock `gh` on PATH injecting canned
  check-run JSON; committed and run from the `version-drift` job) covers:
  1. newest commit has only third-party runs (e.g. `CodeRabbit`) → walker keeps going;
  2. a later commit has a lock-named run → accepted, `using commit:` printed;
  3. ten commits, runs present but never lock-named → warn-only in default AND
     `--strict-remote` modes (exhaustion state 2 — no false drift);
  4. ten commits with no runs at all → warn default / DRIFT under `--strict-remote`
     (exhaustion state 1 — unchanged semantics);
  5. empty `required` array → clean skip, exit 0 in both modes;
  6. summary honesty: 1 verified + 5 missing prints `verified 1 of 6 … missing 5`,
     NOT the all-clear; a mismatch prints in the summary AND drifts.
- `./scripts/check-required-checks.sh --local-only` → 0; full live run → exit 0 with
  honest summary output.
- `--help` shows the full Exit codes section.
- `bash .github/scripts/check-pinned-uses.sh` → 0 on the live tree; negative fixture:
  a temp workflow with `uses: foo/bar@v4` → exit 1.

## PR-4 cascade `fix:` — de-skip + scanner pins to 3 mirrors

**Immediately after PR-1a** (parallel with PR-1b/PR-2). Targets (verified 2026-07-12):
`Dive-And-Dev/perch`, `chris-yyau/busdriver`, `Dive-And-Dev/chrisyau.me`.
The other three (jikdak, diveanddev.com, growth-engine) carry the *guarded* skip-step —
converge them to the de-skip canon and verify pins/`with:` in a second, lower-urgency
pass of the same shape.

**Surgical patch only — never a wholesale copy of helmet's security.yml.** Durable
helmet-only divergence: the shared allowlist (zizmor invocation line). Each mirror PR
touches exactly: delete the "Check for compliance job" step, remove the scan step's
`if:`, set the scan step's canonical `with:`, and pin the three pip install lines.

Per repo (one PR each, standard helmet cascade flow):
1. Re-verify at cascade time (do not trust this plan's snapshot): the trivy job
   contains a step named "Check for compliance job" (unambiguous presence check), and
   tests.yml's compliance job is `if: github.event_name == 'push'`.
2. **Blast-radius pre-scan** (the check has been green-without-scanning on these
   repos' PRs — the first real PR-time scan may surface pre-existing CVEs and brick
   an unrelated PR): before opening the mirror PR, run trivy locally against the
   mirror checkout with the exact canonical settings
   (`trivy fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --skip-dirs tests .`).
   Record the outcome in the cascade matrix; if findings exist, fix the deps in the
   same PR or file a tracked exception issue before merging.
3. Apply the canon: delete the check step, de-`if:` the scan step, set the six-key
   `with:` (`scan-type: fs`, `scanners: vuln`, `severity: HIGH,CRITICAL`,
   `ignore-unfixed: true`, `exit-code: 1`, `skip-dirs: tests`) — **assert all six
   post-edit** (yq/awk; paste the assertion output into the PR description). Pin the
   three pip installs to **the exact versions merged in PR-1a** (from its PR
   description) — do NOT re-resolve PyPI latest at cascade time, or the fleet
   re-drifts mid-cascade; re-resolution happens only via the cadence pass (follow-up
   issue 3). Respect each mirror's existing zizmor invocation — pin only.
4. Verify: the cascade PR itself touches `.github/` → the `changes` detector forces
   all scanners to run; confirm the trivy job log shows an actual scan and the PR's
   "Dependency CVEs" check reflects it.

**Cascade matrix — COMPLETE.** All 6 mirrors merged 2026-07-13; re-verified merged +
`with:` blocks re-fetched from each default branch 2026-07-14. Pip pins applied verbatim
(`semgrep==1.169.0`, `checkov==3.3.8`, `zizmor==1.26.1`).

| Repo | pass | skip-step pre? | pre-scan | with: keys | PR |
|------|------|---------------|----------|-----------|----|
| perch | 1st (unguarded) | Y | scan green (CI) | 4 (core only)¹ | [#65](https://github.com/Dive-And-Dev/perch/pull/65) MERGED |
| busdriver | 1st (unguarded) | Y | scan green (CI) | 5 (core+skip-dirs)¹ | [#335](https://github.com/chris-yyau/busdriver/pull/335) MERGED |
| chrisyau.me | 1st (unguarded) | Y | scan green (CI) | 5 (core+skip-dirs)¹ | [#165](https://github.com/Dive-And-Dev/chrisyau.me/pull/165) MERGED |
| growth-engine | 2nd (guarded) | Y | uv.lock 0 (local) | 5 (core+skip-dirs)¹ | [#81](https://github.com/Dive-And-Dev/growth-engine/pull/81) MERGED |
| jikdak | 2nd (guarded) | Y | pnpm-lock.yaml 0 (local) | 5 (core+skip-dirs)¹ + trivy-action@v0.36.0 SHA-pin (removed `curl\|sudo` installer) | [#255](https://github.com/Dive-And-Dev/jikdak/pull/255) MERGED |
| diveanddev.com | 2nd (guarded) | Y | package-lock.json 0 (local) | 6 (kept pre-existing `ignore-unfixed`; skip-dirs `tests,__tests__`; action still v0.35.0) | [#36](https://github.com/Dive-And-Dev/diveanddev.com/pull/36) MERGED |

**Finding 1 (HIGH) fixed everywhere:** the compliance skip-step is gone and trivy scans on
every push+PR across all 6 mirrors. The uniform gate core — `scan-type: fs / scanners: vuln /
severity: HIGH,CRITICAL / exit-code: 1` — holds on all 6 + live helmet.

¹ **`with:`-canon deviation from this plan's 6-key spec (items lines 101–106/368) — ACCEPTED
residual, not actioned.** The mirror cascade shipped 4–5 key `with:` (missing `ignore-unfixed`,
and perch also missing `skip-dirs`), vs live helmet's 6-key (security.yml:137). Litmus (Codex)
failed *adding* `ignore-unfixed` to a mirror as HIGH ("excludes known HIGH/CRITICAL from the
gate"), so it was left off; the surgical cascade did not add `skip-dirs` where a mirror lacked it.
**Every deviation is stricter than helmet** (a mirror fails on *more* than helmet, never fewer) —
no fail-open, no security regression. Full fleet uniformity of the two hygiene keys is a possible
future convergence pass (fold into #66's fleet drift detector), not a defect.

## Follow-up issues to file (prerequisite step — file before PR-1a, paste numbers here)

**Filed 2026-07-12:** issue 1 → [#66](https://github.com/chris-yyau/helmet/issues/66),
issue 2 → [#68](https://github.com/chris-yyau/helmet/issues/68),
issue 3 → [#67](https://github.com/chris-yyau/helmet/issues/67). Pin comments that
reference the pip-cadence issue use **#67**; the content-hash detector work is tracked
by **#66**.

1. **Template↔live LOGIC parity — whole-document content hash (no stamps).** Three
   independent drift instances (trivy guard, zizmor flags, reports job) prove the
   class; the action-pin parity checker is blind to it. No version-stamp mechanism is
   part of this design — `check-pipeline-drift.sh`'s `# helmet-pipeline:` stamp model
   (the only stamp that exists; bypass-audit.yml only) depends on a manually-bumped
   marker and cannot detect content drift, which is exactly the failure mode at hand.
   Spec:
   - **Local CI check (the real detector):** extend `check-template-pins.sh` (already
     in the `version-drift` required check) to compare **the complete normalized
     documents** — live `security.yml` vs the Section N fenced block: strip comments
     and blank lines, replace each shared-allowlist line with its sentinel (exactly
     one line post-PR-2), then hash and compare. Whole-document hashing (NOT selected
     `run:`/`with:` blocks) is required so `if:`/`needs:`/trigger/`paths:`/`uses:`
     drift — where the actual gating logic lives — is caught. Prerequisite:
     PR-1b/PR-2's wording convergence. Negative fixtures: an `if:` edit, a `needs:`
     edit, a trigger/paths edit, a `uses:` edit, and a wording edit on either side
     must each fail.
   - **Fleet check:** same content-hash comparison per mirror — normalize each
     mirror's fetched security.yml, apply a per-repo divergence allowlist, compare
     against the canonical hash (extended `check-pipeline-drift.sh`, alongside its
     existing bypass-audit stamp scan, which stays as-is for that file). A
     mirror-local edit can then never read "current".
   - Accepted residual: none for template↔live (machine-checked in CI); fleet check
     runs on demand/scheduled, so a mirror drifts only until the next fleet scan.
2. **SKILL.md dedup** — the 2026-07-10 plan's PR-3 (−150 to −250 lines) was silently
   dropped. File it so it's tracked or explicitly declined; the file is 4,361 lines
   of per-load context tax.
3. **Pinned-tool refresh cadence (pip + npx)** — Dependabot cannot bump pins embedded
   in workflow `run:` lines (`.github/dependabot.yml` covers `github-actions` only; a
   `pip` ecosystem entry tracks requirements files, not YAML run commands —
   SKILL.md:3894 already records this tradeoff; the npm ecosystem likewise cannot see
   npx `-p pkg@ver` args). Owner: maintainer. Cadence: monthly, or on scanner-gate /
   release failure. One pass bumps: three pip pins (helmet live + SKILL.md template —
   machine-checked in lockstep by PR-1a's parity check — + mirrors) and the
   semantic-release npx pins (live release.yml + SKILL.md Step-3 template). Optional
   later: a tiny scheduled job comparing pinned versions against PyPI/npm latest that
   opens an issue on staleness. This issue's number is referenced from the pin
   comments (PR-1a item 4 / PR-1b item 5 / PR-2 items 2+6).

## Out of scope

- Issue #64 (scheduled trivy re-scan for dormant CVEs) — already tracked, separate design.
- seatbelt repo — ADR-0001 documented exception, not a cascade target.
- The (c)-surface warn-only default for PR-only checks — documented, intentional
  (PR-3 makes the summary line honest; it does not change warn-only semantics).

<!-- design-reviewed: PASS -->
<!-- design-review-coverage: DEGRADED 1/3 reviewer_1=runtime-droid-rescue reviewer_3=runtime-failed -->
