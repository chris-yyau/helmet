---
name: helmet
description: >
  Full repo onboarding — bootstraps test infrastructure (Phase A), wires the CI/CD pipeline (Phase B),
  generates a project CLAUDE.md (Phase C), and builds a per-repo CodeGraph index (Phase D).
  Use when onboarding a new repo, setting up tests + CI from scratch, adding Codecov/pinact/SBOM/security scanning,
  auditing pipeline completeness, fixing CI failures, generating/refreshing a project CLAUDE.md,
  building a tree-sitter code intelligence index, or deploying pipeline changes across multiple repos.
---

Load and follow the helmet skill to onboard this repository.

Analyze the user's request to determine which phase(s) to run:
- If the user asks about tests, test setup, or coverage: run **Phase A** (Test Infrastructure)
- If the user asks about CI, pipelines, Codecov, security scanning: run **Phase B** (CI/CD Pipeline)
- If the user asks to generate, refresh, or update CLAUDE.md: run **Phase C** (CLAUDE.md Generation)
- If the user asks about codegraph, code graph, structural search, or code intelligence: run **Phase D** (CodeGraph Index)
- If the user says "onboard" or "setup" without specifics: run all four phases in order (A → B → C → D)
  - **Phase D auto-runs** after Phase C if the `codegraph` CLI is on PATH and the repo contains a codegraph-supported language (Phase D's D0 check runs its own detection — does not require Phase A to have run in the same invocation); if codegraph is missing, Phase D prints an install hint and skips cleanly (Phases A/B/C are unaffected)

If Phase B will run, settle the **pipeline mode** before it touches anything (see the skill's "Shipping Mode" section):
- **Shipping mode** if the user said so (e.g. "onboard with shipping"), OR the default branch already carries `.cursor/skills/verify-*/`. Detection wins even when the user didn't mention it; to leave Shipping mode, the verify skill has to come off the default branch first.
- Otherwise ask once: "Will this repo land PRs through Cursor Cloud Shipping?" — no means **standard mode**.
- State the chosen mode in the first progress message.

Follow the skill instructions precisely, executing each step in sequence.
