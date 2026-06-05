# ADR-0001: Single bypass-audit standard + pipeline drift detection

- **Status:** Accepted
- **Date:** 2026-06-05

## Context

helmet generates a `bypass-audit.yml` workflow into each repo it onboards (detects
direct pushes to `main` that bypassed required checks, opens an `admin-bypass` issue).
Because helmet **vendors** (copies) the file at onboarding, every repo froze a snapshot
of whatever helmet generation it adopted. Nothing re-synced them — dependabot bumps
action SHAs but never the workflow *logic* — so the fleet drifted badly: `chrisyau.me`
and `jikdak` sat at the **v1.12** generation (April) while a freshly-authored
`diveanddev.com` (June, via its PR #30) had a materially more secure design. The
neglected repo was *ahead* of the actively-developed ones, purely because its file was
written last.

Three design divergences had accumulated across generations: (a) dedup present/absent
and, where present, gameable; (b) commit-message-based skip (`[skip ci]`/`chore(release)`)
that a human bypasser can forge to evade; (c) silent skip vs. fail-the-run on an
indeterminate API response.

A code review (codex) also surfaced that any **dedup keyed on issue title/body is an
insider-editable suppression primitive**: GitHub issue metadata is mutable, and
`.author.login` stays `github-actions[bot]` even after a human edits the body — so an
author-filtered dedup can still be defeated by editing a bot-authored issue to pre-load
a future bypass SHA. `diveanddev.com` had independently reasoned to *no dedup* for
exactly this reason.

## Decision

1. **One standard = `diveanddev.com`'s design** for all push-time repos: push-only,
   **identity-based skip only** (no commit-message skip), **fail-the-run** on an
   indeterminate PR-lookup (never silent-skip, never false-positive), and **no dedup**
   (the org audit log is the authoritative trail; a duplicate issue on a rare manual
   re-run is harmless and far safer than a mutable-metadata suppression vector).
   helmet's own `bypass-audit.yml` is the canonical template.
2. **Distribution stays vendored (self-contained), not centralized.** Each repo keeps
   its own copy; we do **not** convert to a reusable workflow. Rationale: reusable
   workflows would couple every production app repo to helmet at runtime (and make the
   repo that *authored* the design depend on a copy of itself) — unacceptable for
   self-contained production repos.
3. **Prevent future drift with detection, not coupling.** Every generated workflow
   carries a `# helmet-pipeline: vX.Y.Z` stamp; `scripts/check-pipeline-drift.sh`
   compares each repo's stamp to the canonical version and reports repos that are
   behind. Drift becomes visible instead of silent.
4. **`seatbelt` is a documented exception.** It is a daily *sweep* (cron) design, which
   structurally requires dedup; it is not converged to the push-only standard.

## Alternatives considered

- **Reusable workflow (centralize):** eliminates drift structurally, but couples every
  repo to helmet at runtime and makes self-contained production repos non-self-contained.
  Rejected — the coupling cost outweighs the "byte-identical forever" guarantee.
- **Keep author-filtered dedup as the standard:** rejected — codex showed it remains an
  insider-editable suppression primitive; for an audit workflow, no-dedup is safer.
- **Drop seatbelt's sweep too (full uniformity):** rejected — would delete a deliberate,
  more-thorough capability; a sweep genuinely needs dedup.

## Consequences

- The six in-flight "hardened dedup" PRs are **superseded** (to be closed) — the standard is
  no-dedup.
- All push-time repos converge on one design; new onboards are born on it and stamped.
- Drift is now detectable on demand (and via a scheduled scan); re-sync is a manual
  re-onboard when the check flags a repo (acceptable for a vendored model).
- `diveanddev.com` originated this design but is no longer exempt: as of v1.21.2 it adopted the hardened canonical workflow like the rest of the fleet, so it is now a stamped, drift-scanned member (not an unstamped reference).

## Revisit trigger

- If manual re-syncs become frequent/annoying, add an auto-re-adoption PR bot.
- If a repo gains multiple `issues:write` collaborators AND a no-dedup duplicate-issue
  rate becomes a real nuisance, reconsider a non-metadata dedup (e.g. a committed ledger),
  not a metadata one.
- If GitHub ships first-class org-wide required workflows that fit, reconsider centralizing.
