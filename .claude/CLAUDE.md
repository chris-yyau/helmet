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
.github/          Workflows (5) and scripts (1)
commands/         Slash command definitions (1: /helmet)
scripts/          Build scripts (bump-version.sh)
skills/           Skill definitions (1: helmet — 2740-line onboarding skill)
```

## Commands

| Command | What it does |
|---------|-------------|
| `./scripts/bump-version.sh <ver>` | Sync version across all 3 manifests |
| `./scripts/bump-version.sh --check` | Verify manifests are in sync (used in CI) |
| `.github/scripts/check-pinned-uses.sh` | Verify all Actions use full SHA pins |

## CI Workflows

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `tests.yml` | PR | Version drift detection + commitlint |
| `security.yml` | Push + PR | Semgrep, Checkov, Zizmor, Trivy scanners |
| `pinact.yml` | Push to main (`.github/workflows/**` paths only) | Auto-pin GitHub Actions to SHA |
| `scorecard.yml` | Weekly (scheduled) | OpenSSF security health score |
| `release.yml` | Push to main | semantic-release: changelog, version bump, GitHub Release |

## Conventions

- **Commits:** Conventional Commits enforced by commitlint (`feat:`, `fix:`, `chore:`, etc.)
- **Merge strategy:** Squash-only (merge commits and rebase disabled)
- **Actions security:** All actions SHA-pinned with version comments; harden-runner on every ubuntu job
- **Permissions:** Permissions explicitly scoped per workflow; `permissions: {}` where possible, minimum required scopes granted per-job
- **Dependabot:** Configured for `github-actions` ecosystem

## Version Sync

Version numbers are managed across three manifests (declared in `.version-bump.json`):

- `package.json` — `version` field
- `.claude-plugin/plugin.json` — `version` field
- `.claude-plugin/marketplace.json` — `version` field (inside `plugins[0]`)

**Automated (preferred):** semantic-release bumps all manifests via `@semantic-release/exec` → `bump-version.sh` on every merge to main. No manual version management needed.

**Drift detection:** `./scripts/bump-version.sh --check` runs in CI on PRs to catch version desync.
