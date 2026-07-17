# Helmet Plugin

Full repo onboarding — bootstraps test infrastructure, CI/CD pipelines, and security scanning for Claude Code projects.

## Tech Stack

- **Type:** Claude Code plugin (no application source code)
- **Content:** Markdown skills, YAML workflows, JSON configs, shell scripts
- **Package manager:** npm (CI-only — semantic-release and commitlint)
- **Version:** see `package.json` (managed by semantic-release)
- **License:** MIT

## Project Structure

```text
.claude-plugin/   Plugin manifests (plugin.json, marketplace.json)
.github/          Workflows (7) and scripts (1)
commands/         Slash command definitions (1: /helmet)
scripts/          Build scripts (bump-version.sh, check-pipeline-drift.sh, check-required-checks.sh, check-template-pins.sh)
skills/           Skill definitions (1: helmet — large four-phase onboarding skill)
```

## Commands

| Command | What it does |
|---------|-------------|
| `./scripts/bump-version.sh <ver>` | Sync version across all 3 manifests |
| `./scripts/bump-version.sh --check` | Verify manifests are in sync (used in CI) |
| `.github/scripts/check-pinned-uses.sh` | Verify all Actions use full SHA pins |
| `./scripts/check-template-pins.sh` | Verify SKILL.md template action pins match live workflow pins (runs in the `version-drift` CI job) |
| `./scripts/check-fleet-scanner-invariants.sh --fleet` | Assert each fleet mirror's live `security.yml` still holds the security-critical scanner invariants (fail-closed gates, trivy/semgrep/checkov/zizmor blocking, PR reachability); tolerates benign customization. Needs `gh` + PyYAML |
| `./scripts/check-fleet-scanner-invariants.sh --self-test` | Hermetic fixtures proving the invariant asserter fails closed (runs in the `version-drift` CI job) |
| `./scripts/check-pin-staleness.sh` | Compare the run-line tool pins (semgrep/checkov/zizmor in `security.yml`, semantic-release set in `release.yml`) against PyPI/npm latest; exit 1 + a markdown table on drift, exit 2 on lookup failure (fail-closed). Powers `pin-staleness.yml`. Needs `curl` + `jq` |
| `./scripts/check-pin-staleness.sh --self-test` | Hermetic fixtures proving extraction + stale/fresh/error classification (runs in the `version-drift` CI job) |

## CI Workflows

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `tests.yml` | PR | Version drift detection + template pin parity + commitlint |
| `security.yml` | Push (path-filtered) + PR (all, job-level skip) | Semgrep, Checkov, Zizmor, Trivy scanners |
| `pinact.yml` | Push to main (`.github/workflows/**` paths only) | Auto-pin GitHub Actions to SHA |
| `scorecard.yml` | Weekly (scheduled) | OpenSSF security health score |
| `pin-staleness.yml` | Monthly (scheduled) + dispatch | Compare run-line tool pins vs PyPI/npm latest; opens/updates/closes a rolling `pinned-tool-stale` tracking issue on drift (issue #67). Dependabot can't see these pins |
| `release.yml` | Push to main | semantic-release: changelog, version bump, GitHub Release |
| `bypass-audit.yml` | Push to main | Detect direct-push bypass of required checks → creates `admin-bypass` issue |
| `dependabot-auto-merge.yml` | PR (gated on `dependabot[bot]` author) | On opt-in repos (`vars.DEPENDABOT_AUTO_APPROVE="true"` + `can_approve_pull_request_reviews:true` on workflow permissions): approves AND `gh pr merge --auto --squash` for patch (any) + safe minor (dev/indirect/github_actions). On opt-out repos (default, including enterprise orgs that disable GitHub Actions PR approval): annotate-only — comment fires for both safe-and-manual and unsafe (major / production-direct minor) bumps; safe bumps are merged by hand. Helmet repo itself is opted in |

## Conventions

- **Commits:** Conventional Commits enforced by commitlint (`feat:`, `fix:`, `chore:`, etc.)
- **Merge strategy:** Squash-only (merge commits and rebase disabled)
- **Actions security:** All actions SHA-pinned with version comments; harden-runner on every ubuntu job
- **Permissions:** Permissions explicitly scoped per workflow; `permissions: {}` where possible, minimum required scopes granted per-job
- **Dependabot:** Configured for `github-actions` ecosystem
- **Required checks:** `version-drift`, `commitlint`, `Actions security` (zizmor), `Code security` (semgrep), `Dependency CVEs` (trivy), `IaC misconfig` (checkov) — the six entries in `.github/required-checks.lock`, enforced via branch protection (`strict: true`, `enforce_admins: false`)
- **Security workflow pattern:** PR trigger has no path filter (workflow always starts); a `changes` job detects security-relevant files; scanner jobs gate on `if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')` — they run when security-relevant files changed OR when the `changes` job itself fails/cancels (fail-closed: a broken detector cannot silently bypass required checks). GitHub treats skipped jobs as passing for required checks, so irrelevant PRs cleanly skip. Push trigger retains path filters

## Version Sync

Version numbers are managed across three manifests (declared in `.version-bump.json`):

- `package.json` — `version` field
- `.claude-plugin/plugin.json` — `version` field
- `.claude-plugin/marketplace.json` — `version` field (inside `plugins[0]`)

**Automated (preferred):** semantic-release bumps all manifests via `@semantic-release/exec` → `bump-version.sh` on every merge to main. No manual version management needed.

**Drift detection:** `./scripts/bump-version.sh --check` runs in CI on PRs to catch version desync.
