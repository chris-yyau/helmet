# Audit Remediation Plan — 2026-07-10

> **Status: as-executed historical record** (committed 2026-07-11). A point-in-time
> snapshot of the remediation as planned. Some details below were superseded during
> execution — do **not** follow the code/pins here verbatim:
> - **item-6 `.github/` guard:** the `if grep` form shown below is fail-open on a grep
>   exit-2 (I/O/regex error). It was hardened to a captured-exit-status / fail-closed
>   form during the mirror cascade; the final form shipped fleet-wide (see helmet #62).
> - **Template pin targets** (harden-runner v2.19.4, checkout v6.0.3) were later advanced
>   to v2.20.0 / v7.0.0 by #56. Always re-derive live pins via
>   `./scripts/check-template-pins.sh` before any refresh — never copy these.
> - **Follow-ups:** the actionable follow-ups are GitHub issues (helmet #63, #64). The
>   `docs/reviews/…/follow-up-issues.md` path referenced later is git-ignored local
>   review scratch, not part of the repo.

Source: full-plugin audit (2 parallel agents + inline verification; every finding reproduced or primary-source-verified). 12 findings → 4 PRs.

## Dependency graph (land order)

```
PR-1 (fix) ──> PR-2 (docs) ──> PR-3 (chore/dedup)
PR-4 (cruft) — independent; may fold into PR-1
```

- **PR-2 depends on PR-1**: PR-2 item 4 syncs the SKILL.md commitlint template with PR-1's merged config.
- **PR-3 depends on PR-2**: both edit SKILL.md heavily; dedup last avoids conflicts.
- **PR-4 is independent** (gitignore + local deletions only).

## Finding → PR map

| # | Finding | PR | Plan item |
|---|---------|----|-----------|
| 1 | Duplicate conflicting commitlint configs | PR-1 | 1 |
| 2 | bump-version.sh jq injection + unanchored regex | PR-1 | 2, 3 |
| 3 | bump-version.sh bash-3.2 empty-array crash | PR-1 | 4 |
| 4 | release.yml:30 wrong version comment | PR-1 | 5 |
| 5 | security.yml change-detector regression guard | PR-1 | 6 |
| 6 | .claude/CLAUDE.md stale claims (×4) | PR-2 | 1 |
| 7 | SKILL.md template pins lag real workflows | PR-2 | 2 |
| 8 | plugin.json/marketplace.json stale descriptions | PR-2 | 5 |
| 9 | SKILL.md:2913 concurrency-prefix drift | PR-2 | 3 |
| 10 | security.yml:108 dead trivy self-skip step | PR-2 | 6 |
| 11 | SKILL.md bloat/dedup | PR-3 | — |
| 12 | Repo cruft (.DS_Store etc.) | PR-4 | — |

## PR-1 `fix:` — script + CI defects

**Branch:** `fix/audit-defects`

1. **Merge commitlint configs** (verified: cosmiconfig loads `.js` before `.mjs`, so the `.mjs` protections are dead; Dependabot long-body commit reproduced failing exit=1). Ship ONE file — `commitlint.config.mjs` — and `git rm commitlint.config.js`. Final config, exactly:

   ```js
   export default {
     extends: ['@commitlint/config-conventional'],
     rules: {
       'subject-case': [2, 'never', ['pascal-case', 'upper-case']],
       'body-max-line-length': [0, 'always'],
     },
     ignores: [
       // Scoped to Dependabot-authored commits (trailer survives squash merges —
       // verified on da51614). Hand-written chore(deps): commits stay fully linted.
       (message) => message.includes('Signed-off-by: dependabot[bot]'),
     ],
   }
   ```

2. **`scripts/bump-version.sh:40`** — fix the reproduced jq injection. Exact replacement line:

   ```bash
   jq --arg v "$value" "$jq_path = \$v" "$file" > "$tmp" && mv "$tmp" "$file"
   ```

   (`$jq_path` expands in the shell; `\$v` reaches jq as its variable.) Trust boundary: `$jq_path` is built from `$field`, which comes ONLY from `.version-bump.json` (config-trusted, not attacker-influenced). Defense-in-depth: validate `$field` against `^[A-Za-z0-9_]+([.][A-Za-z0-9_]+)*$` before building the path.

3. **`scripts/bump-version.sh:170`** — anchor the semver regex: `^[0-9]+\.[0-9]+\.[0-9]+$`, with an inline comment that only strict X.Y.Z releases are supported (semantic-release never emits pre-release tags here; relax if that changes).

4. **`scripts/bump-version.sh:80,88`** — guard the empty-array expansion (reproduced `set -u` crash on `/bin/bash` 3.2.57). The array is already declared at line 58 (`local versions=()`), so `${#versions[@]}` is safe to test; only the `"${versions[@]}"` expansion crashes. Insert before line 80:

   ```bash
   if (( ${#versions[@]} == 0 )); then
     echo "error: no declared files found" >&2
     return 1
   fi
   ```

5. **`.github/workflows/release.yml:30`** — comment `# v6.0.2` → `# v6.0.3` (same SHA `df4cb1c069e1874edd31b4311f1884172cec0e10`, 9 other pins already say v6.0.3). Keep the trailing `# zizmor: ignore[artipacked]` comment.

6. **`security.yml` change-detector regression guard** — *defense-in-depth, not a live-gap fix*: the existing grep at line 86 already matches `\.github/`, and any in-file guard is editable by the same PR it gates (skipped required checks pass; only *missing* jobs block merge — inherent to in-file gating, residual accepted for this solo/squash-only/no-fork repo). The guard protects against *accidental* narrowing of the pattern in future edits. Insert after `changed_files` is captured (line 79), before the pattern grep:

   ```bash
   # Workflow/CI changes are always security-relevant — independent of the pattern below.
   if grep -qE '(^|/)\.github/' <<< "$changed_files"; then
     echo "security=true" >> "$GITHUB_OUTPUT"
     exit 0
   fi
   ```

   (`(^|/)` anchors to a real path segment — a path like `src/my.github/x.js` won't match.)

   > **Superseded (see top banner):** testing `grep` directly in an `if` is fail-open on a
   > grep exit-2 — bash treats both exit 1 (no match) and exit 2 (error) as false. The
   > shipped form captures the status and fail-closes on error (`github_grep_status=0; grep … || github_grep_status=$?; case … *) security=true`). See helmet #62 for the final code.

**Verify (PR-1):**
- `./scripts/bump-version.sh --check` → exit 0.
- `/bin/bash scripts/bump-version.sh --check` (system bash 3.2) → exit 0.
- Anchor check: `./scripts/bump-version.sh '1.2.3" | .x = "y'` → exit 1 with the format error (this proves the regex anchor, NOT the jq fix — the anchor rejects the input before `write_json_field` runs).
- **`write_json_field` unit check** (exercises the `--arg` fix directly, since no anchored-regex-passing input can reach it maliciously): in a temp dir, `source` the helper functions, run `write_json_field test.json version '1.2.3" | .x = "y'` against `{"version":"0.0.0"}`, assert the field equals the literal string and no extra keys appeared.
- Commitlint: `npx commitlint --print-config` shows the merged rules; a Dependabot-signed long-body message passes (exit 0); a hand-written `chore(deps): Bump Foo` with a PascalCase subject still fails; only one `commitlint.config.*` file remains.
- **Change-detector unit check** (primary): extract the detector block from `security.yml`, run it with mocked `changed_files` = a `.github/workflows/x.yml` path → `security=true`; `docs/foo.md` → `security=false`; simulate grep exit 2 → `security=true` (fail-closed).
- Optional e2e: scratch PR touching `.github/workflows/security.yml` → all four scanner jobs run; scratch PR touching only `docs/` → scanners cleanly skip. (Push triggers are main-only, so PRs — not branch pushes — are the trigger.)
- `bash .github/scripts/check-pinned-uses.sh` → exit 0; zizmor clean.

## PR-2 `docs:` — doc/template drift

**Branch:** `docs/audit-drift` — **after PR-1** (item 4 depends on the merged commitlint config).

1. **`.claude/CLAUDE.md`**: `Workflows (5)` → `(7)`; drop the hard "2740-line" count (say "single large onboarding skill" — counts rot); list all 3 `scripts/` files; required-checks line → the 6 lock entries (`version-drift`, `commitlint`, `Actions security`, `Code security`, `Dependency CVEs`, `IaC misconfig`).
2. **SKILL.md template pins** — refresh embedded SHAs to match the live workflows (full SHAs, copied from tree):
   - harden-runner → `9af89fc71515a100421586dfdb3dc9c984fbf411 # v2.19.4` (replaces `ab7a9404c0f3da075243ca237b5fac12c98deaa5 # v2.19.3`, 12 occurrences; the new SHA already appears once at ~line 3495, so post-replace total = 13)
   - checkout → `df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3` (replaces `de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2`, 15 occurrences)
   - setup-node → `48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e # v6.4.0` (replaces `53b83947a5a98c8d113130e565377fae1a50d02f # v6.3.0`, 3 occurrences)
   - pinact-action → `896d595f299e71d65b9d28349d6956abe144390a # v3.0.0` (replaces `cf51507d80d4d6522a07348e3d58790290eaf0b6 # v2.0.0`, SKILL.md:2053; **major bump** — diff the template's `with:` inputs against the live `pinact.yml`, which already runs v3, while updating)

   Add one line at the top of the templates section: "Template pins are refreshed periodically; always run pinact after generating."
3. **SKILL.md:2913**: drop the `security-` prefix from the concurrency group (matches canonical rule at lines 1401/1748 and live `security.yml:24`).
4. **SKILL.md commitlint references — ALL of them, not just the template**: rename every `commitlint.config.js` reference to `commitlint.config.mjs` (4 occurrences: line 1327 doc table, 1385 audit check `[ -f commitlint.config.js ]`, 2273 template Step 1, 3742 audit script) — otherwise every newly onboarded repo reintroduces the exact drift PR-1 fixes. Bonus fix: the line-2276 template puts `export default` (ESM) in a `.js` file, which breaks in CJS repos — the `.mjs` rename resolves it. Paste PR-1's exact merged config into the template; sync the CI job with live `tests.yml` (pinned `@commitlint/cli@20.5.0` + `@commitlint/config-conventional@20.5.0`, PR-title lint step).
5. **`plugin.json` + `marketplace.json`**: description → "Full repo onboarding — bootstraps test infrastructure, wires CI/CD + security scanning, generates project CLAUDE.md, and builds a CodeGraph index" (4 phases).
6. **`security.yml:108` dead trivy self-skip step** — **decision: keep, with comment** (cascade parity beats local deletion; the step is a no-op in helmet but live in mirror repos whose tests.yml has a trivy job). Add above the step: `# template-only: no-op in helmet (tests.yml has no trivy job); kept for cascade parity. Delete when helmet's tests.yml gains a trivy job or the cascade drops trivy-in-tests mirrors.` Mirror the same comment in the SKILL.md template.

**Verify (PR-2)** — action-scoped checks (a bare SHA count can pass with a pin in the wrong block; anchoring to the action name can't):
- Old pins gone: `! grep -Eq 'harden-runner@ab7a9404|checkout@de0fac2e|setup-node@53b83947|pinact-action@cf51507d' skills/helmet/SKILL.md`
- New pins present: `grep -c 'harden-runner@9af89fc71515a100421586dfdb3dc9c984fbf411' skills/helmet/SKILL.md` = 13 (12 replaced + 1 pre-existing); `checkout@df4cb1c069e1874edd31b4311f1884172cec0e10` = 15; `setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e` = 3; `pinact-action@896d595f299e71d65b9d28349d6956abe144390a` = 1.
- Each embedded pin equals the corresponding live workflow's pin (compare against `.github/workflows/*.yml`, the source of truth).
- `grep -c 'commitlint\.config\.js' skills/helmet/SKILL.md` = 0.
- `! grep -q 'group: security-' skills/helmet/SKILL.md`
- `jq -r .description .claude-plugin/plugin.json` and marketplace.json show the 4-phase text; `./scripts/bump-version.sh --check` still exit 0 (descriptions don't touch versions).

## PR-3 `chore:` — SKILL.md dedup (finding 11)

**Branch:** `chore/skill-dedup` — **after PR-2** (both touch SKILL.md heavily).

- **PR-3.1** Collapse "skipped counts as passing" (6×) to one canonical explanation + short cross-references — but keep a one-line reminder adjacent to each workflow block that depends on it (retrieval locality matters in an agent-consumed skill).
- **PR-3.2** Collapse Dependabot `bypass_pull_request_allowances`/perch#38 rationale (4×) to one place.
- **PR-3.3** Fold the "Key Decisions" block (~lines 3814–3872) into the inline sections it duplicates. This is a content *move* (delete + non-empty merge), not pure deletion — unique wording in Key Decisions must land in the surviving inline section.
- **PR-3.4** Merge duplicated "When to Use" lists (top-level vs per-phase).
- Target: −150 to −250 lines. Constraint: no net-new policy — every surviving sentence must trace to a pre-dedup sentence.

**Verify (PR-3):** concrete fixture — create a scratch repo (`git init` + a package.json), run the helmet skill's Phase B **audit mode** against it before and after the dedup, capture the emitted audit checklist/report, and diff (normalized for whitespace): must be identical. Plus: re-read affected sections for dangling cross-references.

## PR-4 `chore:` — repo cruft (finding 12) — independent, may fold into PR-1

- **Committed scope:** add `.DS_Store` to `.gitignore` (verified: no `.DS_Store` is currently git-tracked, so no `git rm --cached` needed in helmet; mirrors should run `git rm --cached -r --ignore-unmatch '*.DS_Store'` as a no-op safety net).
- **Maintainer-local cleanup (not part of any PR; doesn't survive clones):** `rm -rf ./~` — this removes a repo-local directory literally named `~` (an artifact of an unexpanded-tilde hook write; the `./` prefix makes it unambiguous that it is NOT `$HOME`) — plus `rm .DS_Store skills/.DS_Store .pr-body-phase-d.md`.

## Cascade note

Helmet templates propagate to 6 mirror repos (busdriver, perch, chrisyau.me, jikdak, growth-engine, diveanddev.com — source of truth: `.helmet-fleet.example`). `seatbelt` is intentionally excluded: it is the ADR-0001 scheduled-sweep variant, off the push-time standard, so it is not a cascade target. Queue for the next cascade batch: PR-1 items 5–6, PR-2 template refreshes, and the PR-2 item 6 template-only comment. Helmet-local script internals (PR-1 items 2–4) cascade only to mirrors that copied `scripts/bump-version.sh`.

**Pre-cascade gate:** fill this per-repo compatibility matrix (values checked at cascade time, not assumed) before touching any mirror:

| Repo | dual commitlint? | security.yml? | pinact v3? | trivy in tests.yml? | bump-version.sh? |
|------|-----------------|---------------|-----------|--------------------:|------------------|
| busdriver / perch / chrisyau.me / jikdak / growth-engine / diveanddev.com | TBD | TBD | TBD | TBD | TBD |

## Follow-ups (recorded, not in these PRs)

- **Template/live pin-parity checker** — extend `check-pipeline-drift.sh` (or a small sibling script) to extract `uses: owner/action@sha` from `.github/workflows/*.yml` and from fenced templates in SKILL.md, failing on mismatch for the shared action set. This is the durable fix for the drift class PR-2 patches once (the plan's own wrong-SHA incident is this brittleness realized). Owner: maintainer; trigger: next time a Dependabot bump lands and SKILL.md isn't updated in the same week.
- Remaining low-priority review notes live in `docs/reviews/audit-remediation/follow-up-issues.md`.

## Out of scope (checked, fine as-is)

Version manifests in sync (1.22.1); bypass-audit.yml matches design; scorecard defaults-exception documented; harden-runner/timeout/SHA-pin coverage complete; dependabot-auto-merge permissions exception acceptable (comment imprecise but config correct).

<!-- design-reviewed: PASS -->
<!-- design-review-coverage: FULL 3/3  -->
