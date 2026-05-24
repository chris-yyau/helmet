---
name: helmet
description: >
  Full repo onboarding — bootstraps test infrastructure (Phase A), wires the CI/CD pipeline (Phase B),
  generates a project CLAUDE.md (Phase C), and builds a local CodeGraph index (Phase D).
  Use when onboarding a new repo, setting up tests + CI from scratch, adding Codecov/pinact/SBOM/security scanning,
  auditing pipeline completeness, fixing CI failures, generating/refreshing a project CLAUDE.md,
  wiring tree-sitter code intelligence, or deploying pipeline changes across multiple repos.
---

Load and follow the helmet skill to onboard this repository.

Analyze the user's request to determine which phase(s) to run:
- If the user asks about tests, test setup, or coverage: run **Phase A** (Test Infrastructure)
- If the user asks about CI, pipelines, Codecov, security scanning: run **Phase B** (CI/CD Pipeline)
- If the user asks to generate, refresh, or update CLAUDE.md: run **Phase C** (CLAUDE.md Generation)
- If the user asks about codegraph, code graph, structural search, or code intelligence: run **Phase D** (CodeGraph Index)
- If the user says "onboard" or "setup" without specifics: run all four phases in order (A → B → C → D)

Phase D auto-runs after Phase C completes when the codegraph CLI is on PATH and a supported language was detected. If codegraph is missing, Phase D prints an install hint and skips cleanly — the rest of the helmet run is unaffected.

Follow the skill instructions precisely, executing each step in sequence.
