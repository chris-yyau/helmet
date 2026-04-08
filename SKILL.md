---
name: helmet
description: >
  Full repo onboarding — bootstraps test infrastructure (Phase A) and wires the CI/CD pipeline (Phase B).
  Use when onboarding a new repo, setting up tests + CI from scratch, adding Codecov/pinact/SBOM/security scanning,
  auditing pipeline completeness, fixing CI failures, or deploying pipeline changes across multiple repos.
  Replaces ci-pipeline-setup and test-setup.
---

# Repo Pipeline Setup

Two-phase repo onboarding: **Phase A** bootstraps test infrastructure (language detection, framework detection, test runner + coverage, smoke tests, gold-standard templates). **Phase B** wires the CI/CD pipeline (Codecov, SHA pinning, SBOM, vulnerability scanning, security backstop, Dependabot, commit signing, OpenSSF Scorecard, CodeScene, GitGuardian).

## When to Use

**Phase A (Test Infrastructure):**
- Onboarding an existing repo that has application code but no test suite
- Starting a new project and want test infrastructure from the start
- CI audit found missing test infrastructure (e.g., Codecov marked N/A)

**Phase B (CI/CD Pipeline):**
- Onboarding a new repo into the CI pipeline
- Adding or fixing Codecov, pinact, or GitGuardian for existing repos
- Deploying pipeline changes across multiple repos at once
- Fixing cross-platform CI failures (lightningcss, npm ci, vitest coverage, Swift iOS-only)
- Auditing CI pipeline completeness across the portfolio
- Adding SBOM generation or build provenance attestations
- Setting up SSH commit signing or troubleshooting signature issues
- Configuring Dependabot security alerts or version updates
- Deploying OpenSSF Scorecard or SECURITY.md
- Setting up CodeScene behavioral code analysis on PRs
- Adding security scanning CI backstop (Semgrep, Checkov, Zizmor) for defense-in-depth

---

# Phase A: Test Infrastructure


Bootstrap test infrastructure for repos with testable code but no tests. Detects language and framework, installs the test runner + coverage provider, creates config, and generates a smoke test + gold-standard template test.

## When to Use

- Onboarding an existing repo that has application code but no test suite
- Starting a new project and want test infrastructure from the start
- CI audit found missing test infrastructure (e.g., Codecov marked N/A)

## A0. Precondition Check

Before running detection, verify the repo has testable application code.

**A repo is "testable" when BOTH conditions are met:**
1. At least one language config file exists: `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `setup.py`, `requirements.txt`, `Package.swift`, or a `*.xcodeproj` directory
2. At least one non-test source file exists in that language (`.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.go`, `.rs`, `.swift`)

**Exclude from source file count:** `node_modules/`, `vendor/`, `.git/`, `dist/`, `build/`, generated files.

**If NEITHER condition is met** (no config file AND no source files), stop and report:
> "This repo has no testable application code. Test infrastructure is not applicable. Consider shellcheck for shell scripts or JSON schema validation for config files."

## A1. Detection

### A1a. Language Detection

Detect languages in order of confidence. Check config files first (highest signal), then fall back to file extension counts.

**Primary signal — config files:**

| Config File | Language |
|-------------|----------|
| `package.json` | TypeScript/JavaScript |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pyproject.toml`, `setup.py`, `requirements.txt` | Python |
| `Package.swift`, `*.xcodeproj` (directory, not file) | Swift |

**Fallback — file extension count** (when no config file found for a language):

| Extensions | Language |
|------------|----------|
| `.ts`, `.tsx`, `.js`, `.jsx` | TypeScript/JavaScript |
| `.go` | Go |
| `.rs` | Rust |
| `.py` | Python |
| `.swift` | Swift |

**Mixed repos:** Detect ALL languages present. Scope each language's setup to its root directory:
- Find the nearest config file (`package.json`, `go.mod`, etc.) and treat that directory as the language root.
- Example: `package.json` at repo root + `go.mod` in `services/api/` -> run TS setup at root, Go setup scoped to `services/api/`.
- Each language gets independent detection, installation, and output. They do not share test directories or configs.

### A1b. Framework Detection

After detecting the language, inspect dependency declarations for framework-specific packages. The detected framework determines which test patterns the template test will demonstrate.

**TypeScript/JavaScript** (check `dependencies` + `devDependencies` in `package.json`):

| Dependency | Framework | Template test approach |
|------------|-----------|----------------------|
| `express` | Express | supertest route tests |
| `next` | Next.js | Route handler tests, API route tests |
| `hono` | Hono | Hono test client |
| `fastify` | Fastify | `app.inject()` tests |
| None matched | Generic | Export/function-level unit tests |

**Python** (check `pyproject.toml` `[project.dependencies]` or `requirements.txt`):

| Dependency | Framework | Template test approach |
|------------|-----------|----------------------|
| `fastapi` | FastAPI | TestClient, dependency overrides |
| `django` | Django | TestCase, Client, model tests |
| `flask` | Flask | Test client, route tests |
| None matched | Generic | Module/function-level tests |

**Go** (check `require` block in `go.mod`):

| Dependency | Framework | Template test approach |
|------------|-----------|----------------------|
| `github.com/gin-gonic/gin` | Gin | httptest + gin test context |
| `github.com/go-chi/chi` | Chi | httptest + chi router |
| `net/http` imports in `.go` source files (not in `go.mod` — stdlib packages don't appear there) | Stdlib | httptest handler tests |
| None matched | Generic | Table-driven function tests |

**Rust** (check `[dependencies]` in `Cargo.toml`):

| Dependency | Framework | Template test approach |
|------------|-----------|----------------------|
| `actix-web` | Actix | `actix_web::test`, `TestRequest` |
| `axum` | Axum | Tower service tests |
| None matched | Generic | `#[cfg(test)]` module tests |

**Swift** (check `Package.swift` dependencies or project structure):

| Signal | Framework | Template test approach |
|--------|-----------|----------------------|
| `import Testing` in source files (Xcode 16+ / Swift 6) | Swift Testing | `@Test` functions, `#expect` assertions (note: Phase 2/3 templates use XCTest as fallback until Swift Testing templates are added) |
| SwiftUI imports + `*.xcodeproj` dir | SwiftUI app | ViewInspector, `@Observable` state tests |
| `Package.swift` (library) | Swift package | XCTest module tests |
| Vapor in dependencies | Vapor | `XCTVapor` request tests |

### A1c. Existing Test Detection

Before installing, check if test infrastructure already exists for each detected language. Skip or fill gaps as needed.

**Signals to check:**

| Signal | Means |
|--------|-------|
| Test directories (`__tests__/`, `tests/`, `test/`, `*_test.go` files) | Tests may exist |
| Test config files (`vitest.config.*`, `jest.config.*`, `pytest.ini`, `pyproject.toml` with `[tool.pytest]`) | Test framework configured |
| Test scripts in `package.json` (`"test"`, `"test:coverage"`) or Makefile (`test:` target) | Test runner registered |
| Coverage config (`.coveragerc`, `.nycrc`, `codecov.yml`) | Coverage already set up |

**Decision rules:**

| Config exists | Test dir exists | Test script exists | Action |
|:---:|:---:|:---:|---|
| Yes | Yes | Yes | **Skip** -- fully set up |
| Yes | No | -- | **Create directory only**, keep existing config |
| No | Yes | -- | **Create config only**, keep existing directory |
| -- | -- | No (but config + dir exist) | **Add script only** |
| No | No | No | **Full setup** |

Proceed automatically in all cases (no user prompt). Report what was created vs. what was skipped.

## A2. Installation

Install the test framework and coverage provider for each detected language. If installation fails (network, permissions, version conflict), stop and report the error -- do not proceed to Phase 3.

### Package Manager Detection (TypeScript/JavaScript)

Detect the package manager from the lock file. Fall back to npm.

| Lock File | Package Manager | Install Command |
|-----------|----------------|-----------------|
| `bun.lockb` or `bun.lock` | bun | `bun add -D vitest @vitest/coverage-v8` |
| `pnpm-lock.yaml` | pnpm | `pnpm add -D vitest @vitest/coverage-v8` |
| `yarn.lock` | yarn | `yarn add -D vitest @vitest/coverage-v8` |
| `package-lock.json` or none | npm | `npm install -D vitest @vitest/coverage-v8` |

### Per-Language Installation

#### TypeScript/JavaScript

1. Install vitest + coverage provider via detected package manager
2. Install framework-specific test helpers based on detected framework:

| Framework | Additional dev dependency |
|-----------|-------------------------|
| Express | `supertest` |
| Hono | (built-in test client, no extra dep) |
| Fastify | (built-in `app.inject()`, no extra dep) |
| Next.js | (no extra dep for route handler tests) |
| Generic | (no extra dep) |

3. Create `vitest.config.ts`:

```typescript
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],  // lcov for Codecov compatibility
      exclude: ['node_modules/', 'dist/', '**/*.config.*'],
    },
  },
})
```

4. Add to `package.json` scripts:
   - `"test": "vitest run"`
   - `"test:coverage": "vitest run --coverage"`
5. Create `__tests__/` directory

#### Python

1. Determine installation method:
   - `uv.lock` present -> add `pytest` and `pytest-cov` to dev dependencies, run `uv sync --dev` or `uv pip install -e ".[dev]"`
   - `pyproject.toml` with PEP 621 `[project]` section -> add `pytest` and `pytest-cov` to `[project.optional-dependencies]` dev group, run `pip install -e ".[dev]"`
   - `pyproject.toml` with Poetry (`[tool.poetry]`), PDM, or other non-PEP-621 format -> fall back to `requirements-dev.txt` approach
   - No `pyproject.toml` -> create `requirements-dev.txt` with `pytest` and `pytest-cov`, run `pip install -r requirements-dev.txt`
2. If `$VIRTUAL_ENV` is unset and no `uv.lock`, warn: "No virtual environment detected. Consider `python -m venv .venv` first." Proceed anyway.
3. Add pytest config to `pyproject.toml` (create or append):

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "--cov=<package> --cov-report=xml --cov-report=term"  # Replace <package> with actual package name (e.g., src, app)
```

4. Create `tests/` directory with `__init__.py` and `conftest.py`

#### Go

1. No installation needed (testing is built-in)
2. If `Makefile` exists, add targets:

```makefile
test:
	go test ./...

test-coverage:
	go test -coverprofile=coverage.out ./... && go tool cover -html=coverage.out -o coverage.html
```

3. No separate test directory -- Go test files go alongside source files (`*_test.go`)

#### Rust

1. No test framework installation needed (built-in `#[test]`)
2. Attempt coverage tool install:
   ```bash
   cargo install cargo-llvm-cov
   ```
   If install fails, warn: "cargo-llvm-cov not installed. Tests will work but coverage reports require it. Install manually or use CI-only coverage." Continue with setup.
3. Create `tests/` directory for integration tests

#### Swift

1. XCTest is built-in -- no installation needed
2. For `Package.swift` projects: add test target if missing:
   ```swift
   .testTarget(name: "AppTests", dependencies: ["App"])
   ```
3. For Xcode projects: verify test target exists, warn if missing (cannot auto-create Xcode test targets reliably)
4. Create `Tests/AppTests/` directory structure

## A3. Output Files

### A. Smoke Test

Generate one real, runnable test that proves the app can be imported without crashing.

**Scope:** Import-only. Does NOT start servers, connect to databases, or trigger side effects. If the app performs side effects on import (e.g., `mongoose.connect()` at module level), the smoke test will fail -- report this with the suggestion: "Your app performs side effects on import. Consider wrapping startup logic in a function."

**File placement:**

| Language | Smoke test file |
|----------|----------------|
| TypeScript/JS | `__tests__/smoke.test.ts` |
| Python | `tests/test_smoke.py` |
| Go | `smoke_test.go` (in root package) |
| Rust | `tests/smoke.rs` |
| Swift | `Tests/AppTests/SmokeTests.swift` |

**Templates:**

<details><summary>TypeScript/JavaScript</summary>

```typescript
import { describe, it, expect } from 'vitest'

describe('smoke', () => {
  it('main module imports without error', async () => {
    const mod = await import('../src/index')
    expect(mod).toBeDefined()
  })
})
```

Adjust the import path (`../src/index`) to match the actual entry point found in `package.json` `"main"` or `"exports"` field.

</details>

<details><summary>Python</summary>

```python
def test_smoke():
    """Verify the main package can be imported."""
    import app  # noqa: F401
```

Adjust `import app` to match the actual package name (the top-level directory containing `__init__.py`, or the module name from `pyproject.toml`).

</details>

<details><summary>Go</summary>

```go
package main

import "testing"

func TestSmoke(t *testing.T) {
    // Verify the package compiles and main symbols are accessible.
    // If this test fails, the package has a build error.
    t.Log("smoke test: package compiles successfully")
}
```

Place in the root package directory. Adjust `package main` to match the actual package name if different.

</details>

<details><summary>Rust</summary>

```rust
#[test]
fn smoke() {
    // Verify the crate compiles and can be used as a dependency.
    // If this fails, there is a build error in the main crate.
    assert!(true, "crate compiles successfully");
}
```

Place as `tests/smoke.rs` (integration test). The crate name is auto-resolved from `Cargo.toml`.

</details>

<details><summary>Swift</summary>

```swift
import XCTest
@testable import App

final class SmokeTests: XCTestCase {
    func testSmoke() {
        // Verify the module can be imported without error.
        XCTAssertTrue(true, "Module imports successfully")
    }
}
```

Adjust `@testable import App` to match the actual module/target name from `Package.swift` or the Xcode project.

</details>

### B. Gold-Standard Template Test

Generate one heavily commented test file showing the right patterns for the detected language+framework. Contains 2-3 real implemented tests (not TODOs) demonstrating:

1. **Happy path** -- basic operation with expected input
2. **Error case** -- how to test error handling
3. **Framework pattern** -- one idiomatic framework-specific test (e.g., authenticated route, middleware)

Comments explain: import conventions, test structure, mocking approach, and where to find more patterns.

**File placement:**

| Language | Template test file | Naming rationale |
|----------|-------------------|------------------|
| TypeScript/JS | `__tests__/_template.test.ts` | Underscore sorts first |
| Python | `tests/test_template.py` | Follows pytest `test_` convention |
| Go | `template_test.go` (root package) | Matches template naming in other languages (`example_test.go` is reserved for godoc examples) |
| Rust | `tests/template.rs` | Integration test in `tests/` |
| Swift | `Tests/AppTests/TemplateTests.swift` | XCTest naming convention |

**Generate the template based on the detected framework.** Use the framework detection from Phase 1b to select the right test patterns. The template must use the actual framework's test helpers (e.g., supertest for Express, TestClient for FastAPI, httptest for Go stdlib).

**References to include in template comments:**
- `busdriver:tdd` -- for generating tests for specific modules
- Language-specific testing skill -- `busdriver:golang-testing`, `busdriver:python-testing`, `busdriver:rust-testing`, etc.

<details><summary>TypeScript/JavaScript -- Express example</summary>

```typescript
/**
 * TEMPLATE TEST -- Copy this file as a starting point for new test files.
 *
 * Pattern: supertest + vitest for Express route testing.
 * Run: npm test
 * Coverage: npm run test:coverage
 *
 * For full TDD workflow, use `busdriver:tdd` to generate tests for specific modules.
 * For more patterns, see `busdriver:tdd`.
 */
import { describe, it, expect } from 'vitest'
import request from 'supertest'
import { app } from '../src/app'

describe('GET /health', () => {
  // Happy path: verify the endpoint returns expected shape
  it('returns 200 with status ok', async () => {
    const res = await request(app).get('/health')
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ status: 'ok' })
  })

  // Error case: verify proper error response format
  it('returns 404 for unknown routes', async () => {
    const res = await request(app).get('/nonexistent')
    expect(res.status).toBe(404)
  })

  // Framework pattern: testing with auth header
  it('authenticated route returns 401 without token', async () => {
    const res = await request(app).get('/api/protected')
    expect(res.status).toBe(401)
  })
})
```

</details>

<details><summary>TypeScript/JavaScript -- Generic (no framework)</summary>

```typescript
/**
 * TEMPLATE TEST -- Copy this file as a starting point for new test files.
 *
 * Pattern: vitest for unit testing exported functions.
 * Run: npm test
 * Coverage: npm run test:coverage
 *
 * For full TDD workflow, use `busdriver:tdd`.
 */
import { describe, it, expect } from 'vitest'
// import { yourFunction } from '../src/utils'

describe('yourFunction', () => {
  // Happy path
  it('returns expected result for valid input', () => {
    // const result = yourFunction('valid')
    // expect(result).toBe(expected)
    expect(true).toBe(true) // Replace with real test
  })

  // Error case
  it('throws on invalid input', () => {
    // expect(() => yourFunction(null)).toThrow()
    expect(true).toBe(true) // Replace with real test
  })
})
```

</details>

<details><summary>Python -- FastAPI example</summary>

```python
"""
TEMPLATE TEST -- Copy this file as a starting point for new test files.

Pattern: pytest + TestClient for FastAPI endpoint testing.
Run: pytest
Coverage: pytest --cov

For full TDD workflow, use `busdriver:tdd`.
For more patterns, see `busdriver:python-testing`.
"""
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


# Happy path: verify endpoint returns expected shape
def test_health_returns_ok():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


# Error case: verify proper error response
def test_unknown_route_returns_404():
    response = client.get("/nonexistent")
    assert response.status_code == 404


# Framework pattern: dependency override for testing
def test_with_dependency_override():
    """Example of overriding a FastAPI dependency for testing."""
    # from app.dependencies import get_db
    # def mock_db():
    #     return FakeDB()
    # app.dependency_overrides[get_db] = mock_db
    # response = client.get("/items")
    # app.dependency_overrides.clear()
    assert True  # Replace with real test
```

</details>

<details><summary>Python -- Generic (no framework)</summary>

```python
"""
TEMPLATE TEST -- Copy this file as a starting point for new test files.

Pattern: pytest for unit testing functions and classes.
Run: pytest
Coverage: pytest --cov

For full TDD workflow, use `busdriver:tdd`.
For more patterns, see `busdriver:python-testing`.
"""
# from your_module import your_function


# Happy path: verify function returns expected result
def test_happy_path():
    # result = your_function("valid input")
    # assert result == expected
    assert True  # Replace with real test


# Error case: verify error handling
def test_error_case():
    # with pytest.raises(ValueError):
    #     your_function(None)
    assert True  # Replace with real test
```

</details>

<details><summary>Go -- net/http example</summary>

```go
// Template test -- copy this file as a starting point for new test files.
//
// Pattern: table-driven tests with httptest for HTTP handler testing.
// Run: make test (or go test ./...)
// Coverage: make test-coverage
//
// For full TDD workflow, use `busdriver:tdd`.
// For more patterns, see `busdriver:golang-testing`.

package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// Happy path: verify handler returns expected status.
func TestHealthHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()
	healthHandler(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

// Error case: table-driven test pattern for multiple inputs.
func TestHealthHandler_EdgeCases(t *testing.T) {
	tests := []struct {
		name   string
		method string
		want   int
	}{
		{"GET returns 200", http.MethodGet, http.StatusOK},
		{"POST returns 405", http.MethodPost, http.StatusMethodNotAllowed},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(tt.method, "/health", nil)
			w := httptest.NewRecorder()
			healthHandler(w, req)
			if w.Code != tt.want {
				t.Errorf("expected %d, got %d", tt.want, w.Code)
			}
		})
	}
}
```

</details>

<details><summary>Go -- Generic (no framework)</summary>

```go
// Template test -- copy this file as a starting point for new test files.
//
// Pattern: table-driven tests for pure functions.
// Run: go test ./...
// Coverage: go test -coverprofile=coverage.out ./...
//
// For full TDD workflow, use `busdriver:tdd`.
// For more patterns, see `busdriver:golang-testing`.

package main

import "testing"

// Happy path: verify function returns expected result.
func TestYourFunction(t *testing.T) {
	// result := YourFunction("valid input")
	// if result != expected {
	//     t.Errorf("expected %v, got %v", expected, result)
	// }
	t.Log("Replace with real test")
}

// Error case: table-driven test pattern.
func TestYourFunction_EdgeCases(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{"valid input", "hello", false},
		{"empty input", "", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// _, err := YourFunction(tt.input)
			// if (err != nil) != tt.wantErr {
			//     t.Errorf("wantErr=%v, got err=%v", tt.wantErr, err)
			// }
			t.Log("Replace with real test")
		})
	}
}
```

</details>

<details><summary>Rust -- Generic example</summary>

```rust
//! TEMPLATE TEST -- Copy this file as a starting point for new integration tests.
//!
//! Pattern: integration test in tests/ directory.
//! Run: cargo test
//! Coverage: cargo llvm-cov
//!
//! For full TDD workflow, use `busdriver:tdd`.
//! For more patterns, see `busdriver:rust-testing`.

// use your_crate::your_function;

// Happy path: verify function returns expected result
#[test]
fn test_happy_path() {
    // let result = your_function("valid input");
    // assert_eq!(result, expected);
}

// Error case: verify error handling
#[test]
fn test_error_case() {
    // let result = your_function("");
    // assert!(result.is_err());
}
```

</details>

<details><summary>Swift -- XCTest example</summary>

```swift
/// TEMPLATE TEST -- Copy this file as a starting point for new test files.
///
/// Pattern: XCTest for unit testing.
/// Run: swift test (SPM) or xcodebuild test (Xcode)
///
/// For full TDD workflow, use `busdriver:tdd`.
import XCTest
@testable import App

final class TemplateTests: XCTestCase {

    // Happy path: verify function returns expected result
    func testHappyPath() {
        // let result = yourFunction("valid")
        // XCTAssertEqual(result, expected)
        XCTAssertTrue(true, "Replace with real test")
    }

    // Error case: verify error handling
    func testErrorCase() {
        // XCTAssertThrowsError(try yourFunction(nil))
        XCTAssertTrue(true, "Replace with real test")
    }
}
```

</details>

Adapt all import paths and function names to match the actual codebase. The template is a starting point -- the tests should compile and pass as-is (with placeholder assertions), so the developer can immediately see the pattern and replace with real tests.

## A4. Post-Setup

After generating all files, verify the setup works end-to-end.

### A4a. Run the Tests

Execute the test command for the detected language:

| Language | Command |
|----------|---------|
| TypeScript/JS | `npm test` (or `yarn test` / `pnpm test` / `bun test` per detected package manager) |
| Python | `pytest tests/` |
| Go | `go test ./...` |
| Rust | `cargo test` |
| Swift | `swift test` (SPM) or `xcodebuild test` (Xcode) |

### A4b. Handle Results

| Result | Action |
|--------|--------|
| **All tests pass** | Report success, show coverage baseline, proceed to 4c |
| **Smoke test fails -- import side effects** | Report: "Your app performs side effects on import (e.g., DB connections, env vars). Consider wrapping startup logic in a function. The smoke test verifies import-only." |
| **Smoke test fails -- missing dependencies** | Report: "Install missing dependencies first, then re-run Phase A." |
| **Template test fails** | Report as informational (not an error): "The template test references example endpoints/functions. Adapt it to your actual code." |
| **Installation failed** | Report the error (network, permissions, version conflict). Do not generate output files. |

### A4c. Report Summary

Show a summary of everything that happened:

```
## Phase A Complete: Test Infrastructure

**Language:** TypeScript (Express)
**Package manager:** npm

**Created:**
- vitest.config.ts (coverage: v8, reporter: lcov)
- package.json scripts: test, test:coverage
- __tests__/smoke.test.ts (1 test, passing)
- __tests__/_template.test.ts (3 tests, passing)

**Skipped:** (nothing -- full setup)

**Test results:** 4 tests passing
**Coverage baseline:** 12.3%

**Next steps:**
-- Proceed to Phase B to wire CI/CD pipeline
- Use `busdriver:tdd` when ready to write tests for specific modules
```

---

# Phase B: CI/CD Pipeline


Set up the full CI pipeline for new or existing repos: tests + coverage, action pinning, SBOM generation, build provenance attestations, security scanning backstop (Semgrep, Checkov, Zizmor), Dependabot, SSH commit signing, OpenSSF Scorecard, CodeScene behavioral analysis, and GitGuardian secrets detection.

## When to Use

- Onboarding a new repo into the CI pipeline
- Adding or fixing Codecov, pinact, or GitGuardian for existing repos
- Deploying pipeline changes across multiple repos at once
- Fixing cross-platform CI failures (lightningcss, npm ci, vitest coverage, Swift iOS-only)
- Auditing CI pipeline completeness across the portfolio
- Adding SBOM generation or build provenance attestations
- Setting up SSH commit signing or troubleshooting signature issues
- Configuring Dependabot security alerts or version updates
- Deploying OpenSSF Scorecard or SECURITY.md
- Setting up CodeScene behavioral code analysis on PRs
- Adding security scanning CI backstop (Semgrep, Checkov, Zizmor) for defense-in-depth

## Pipeline Components

| Component | What It Does | Config Files |
|-----------|-------------|--------------|
| **Codecov** | Diff-coverage on PRs (80% target for new code) | `codecov.yml` + `.github/workflows/tests.yml` |
| **Pinact** | Auto-pin GitHub Actions to full SHA + precise version comments | `.github/workflows/pinact.yml` |
| **GitGuardian** | Secrets detection on push/PR (catches Gitleaks misses, different engine) | GitHub App (ggshield) |
| **Syft SBOM** | Generate Software Bill of Materials (dependency list) | `compliance` job in `tests.yml` |
| **SBOM Attestation** | Cryptographic SBOM provenance (GitHub Sigstore) | `compliance` job in `tests.yml` |
| **Release Attestation** | Attest source archives on GitHub Release (Sigstore) | `attest` job in `release.yml` |
| **Trivy Vuln** | Dependency vulnerability scanning (CRITICAL+HIGH) | `compliance` job in `tests.yml` |
| **Trivy License** | Dependency license compliance (CRITICAL only) | `compliance` job in `tests.yml` |
| **LICENSE** | Proprietary repo license (all rights reserved) | `LICENSE` file at repo root |
| **Cosign** | Keyless binary signing (forge release only) | `.github/workflows/release.yml` |
| **Harden-Runner** | Monitor network egress + detect code overwrite in Actions (Ubuntu only) | First step in every ubuntu job |
| **Commitlint** | Enforce Conventional Commits format (open-source repos only) | `commitlint.config.js` + `commitlint` job in `tests.yml` |
| **semantic-release** | Auto version bump + changelog + GitHub Release (open-source repos only) | `.releaserc.json` + `.github/workflows/release.yml` |
| **OpenSSF Scorecard** | Security health score (18 checks, weekly cron + push) | `.github/workflows/scorecard.yml` |
| **SECURITY.md** | Vulnerability disclosure policy | `SECURITY.md` at repo root |
| **Dependabot** | Security alerts + automated version update PRs (GitHub-native) | `.github/dependabot.yml` |
| **Commit Signing (SSH)** | Verified commits with SSH key signatures | `~/.gitconfig` (global) + GitHub signing key |
| **checkov (local)** | IaC misconfiguration scan — **BLOCK** on commit | `~/.claude/hooks/pre-commit-iac-scan.sh` |
| **zizmor (local)** | GitHub Actions workflow security — WARN on commit | `~/.claude/hooks/pre-commit-iac-scan.sh` |
| **trivy (local)** | Dependency vuln scan — WARN on commit (CI trivy is the real gate) | `~/.claude/hooks/pre-commit-iac-scan.sh` |
| **Semgrep CI** | Code security scanning backstop — SQLi, XSS, cmd injection (push+PR) | `semgrep` job in `security.yml` |
| **Checkov CI** | IaC misconfiguration CI backstop — Dockerfile, Terraform, k8s, workflows (push+PR) | `checkov` job in `security.yml` |
| **Zizmor CI** | GitHub Actions workflow security CI backstop (push+PR) | `zizmor` job in `security.yml` |
| **CodeScene** | Behavioral code analysis — code health, hotspots, complexity on PRs (student account) | GitHub App + `.codescene/custom-quality-gates.json` |

## Default Behavior: Audit Current Repo

When this skill is invoked without a specific task (e.g., user runs `/ci-pipeline-setup` or says "audit CI"), run a full checklist against the current repo. Check every component below using the exact commands shown. Present results as a table with pass/fail/N-A status.

### Repo Settings (via API)
```bash
OWNER=$(gh repo view --json owner -q '.owner.login')
REPO=$(gh repo view --json name -q '.name')

# Repo settings
gh api "repos/$OWNER/$REPO" --jq '{
  allow_merge_commit, allow_squash_merge, allow_rebase_merge,
  allow_update_branch, delete_branch_on_merge, allow_auto_merge,
  visibility, default_branch
}'

# Actions permissions (also check selected_actions_url for allowlist if allowed_actions is "selected")
gh api "repos/$OWNER/$REPO/actions/permissions" --jq '{allowed_actions, sha_pinning_required}'

# Branch protection (use detected default branch, not hardcoded "main")
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name')
gh api "repos/$OWNER/$REPO/branches/$DEFAULT_BRANCH/protection/required_status_checks" --jq '{strict, contexts}' 2>&1
```

### File Checks
| Check | Command | Pass condition |
|-------|---------|---------------|
| Tests workflow | `[ -f .github/workflows/tests.yml ]` | File exists |
| Security backstop | `[ -f .github/workflows/security.yml ]` | File exists |
| Pinact workflow | `[ -f .github/workflows/pinact.yml ]` | File exists |
| Scorecard workflow | `[ -f .github/workflows/scorecard.yml ]` | File exists |
| Release workflow | `[ -f .github/workflows/release.yml ]` | File exists (N/A for non-release repos) |
| SHA pin script | `[ -f .github/scripts/check-pinned-uses.sh ]` | File exists |
| Dependabot | `[ -f .github/dependabot.yml ]` | File exists |
| Codecov config | See Codecov detection logic below | Three-way check |
| LICENSE | `[ -f LICENSE ]` | File exists |
| SECURITY.md | `[ -f SECURITY.md ]` | File exists |
| Release config | `[ -f .releaserc.json ]` | File exists (N/A for non-release repos) |
| Commitlint config | `[ -f commitlint.config.js ]` | File exists (N/A for non-release repos) |

**Codecov detection logic:**
1. Has test script (`"test"` in package.json / Makefile `test:` target / `go test` / `cargo test`) AND coverage config (`codecov.yml`, `.coveragerc`, vitest coverage config) -> **wire Codecov**
2. Has source files (`.ts`/`.tsx`/`.js`/`.jsx`/`.py`/`.go`/`.rs`/`.swift`) but no test infrastructure -> **`Codecov | ❌ — set up test infrastructure first`**
3. No source files (markdown, JSON, shell only) -> **`Codecov | N/A`**

### Workflow Hardening (check each workflow file)
For each `.github/workflows/*.yml`, verify:
| Check | How to verify |
|-------|--------------|
| `timeout-minutes` on every job | For each workflow, verify every job has `timeout-minutes` set |
| `permissions` declared | `grep -L 'permissions' .github/workflows/*.yml` — should return nothing |
| `defaults.run.shell` | Check `defaults.run.shell: bash` is declared (not just any `shell:` key in step-level overrides) |
| Concurrency group | Check push/PR workflows only (not cron-only workflows like scorecard) |
| Harden-Runner | For each ubuntu job (not macOS), verify `harden-runner` step exists. Check per-job, not per-file |
| SHA-pinned actions | `bash .github/scripts/check-pinned-uses.sh` — exit 0 = pass |
| No `paths` + `paths-ignore` on same trigger | Verify no workflow uses both `paths` and `paths-ignore` on the same trigger event (GitHub ignores `paths-ignore` when `paths` is present) |
| `persist-credentials: false` | Check all checkout steps except release/pinact (which need push access) |

### Content Checks (grep inside files)
| Check | Command | Pass condition |
|-------|---------|---------------|
| Compliance job (SBOM+license+vuln) | `grep -q 'sbom-action' .github/workflows/tests.yml` | Found (N/A for no-dep repos) |
| Trivy in compliance | `grep -q 'trivy-action\|scanners.*vuln' .github/workflows/tests.yml` | Found (N/A for no-dep repos) |
| Commitlint job | `grep -q 'commitlint' .github/workflows/tests.yml` | Found (N/A for non-release repos) |
| Semgrep in security.yml | `grep -q 'semgrep' .github/workflows/security.yml` | Found |
| Checkov in security.yml | `grep -q 'checkov' .github/workflows/security.yml` | Found |
| Zizmor in security.yml | `grep -q 'zizmor' .github/workflows/security.yml` | Found |
| Trivy vuln scan | `grep -q 'trivy-action' .github/workflows/tests.yml` OR `grep -q 'trivy' .github/workflows/security.yml` | Found in either (Trivy runs in compliance job in tests.yml; security.yml auto-skips if compliance exists) |
| Reports summary job | `grep -q 'GITHUB_STEP_SUMMARY' .github/workflows/security.yml` | Found |
| Artifact retention set | `grep -q 'retention-days' .github/workflows/scorecard.yml` | Found where upload-artifact is used |

### Present Results
Show a summary table:
```
| Component | Status | Notes |
|-----------|--------|-------|
| Repo: squash-only merge | ✅/❌ | |
| Repo: auto-merge | ✅/❌ | |
| Repo: branch protection | ✅/❌ | contexts: [...] |
| Repo: Actions selected | ✅/❌ | |
| Repo: SHA pinning required | ✅/❌ | |
| Tests workflow | ✅/❌ | |
| Security backstop | ✅/❌ | semgrep+checkov+zizmor+trivy+reports |
| Pinact | ✅/❌ | |
| Scorecard | ✅/❌ | |
| Release | ✅/❌/N-A | |
| Dependabot | ✅/❌ | ecosystems: [...] |
| Codecov | ✅/❌/N-A | |
| Compliance (SBOM+vuln+license) | ✅/❌/N-A | |
| Commitlint | ✅/❌/N-A | |
| LICENSE | ✅/❌ | |
| SECURITY.md | ✅/❌ | |
| SHA pin script | ✅/❌ | |
| Harden-Runner (all ubuntu jobs) | ✅/❌ | |
| Workflow hardening | ✅/❌ | timeouts, permissions, shell, concurrency |
| Commit signing | ✅/❌ | SSH or GPG |
```

After showing results, suggest fixes for any ❌ items referencing the specific section in this skill.

---

## B1. Process

### B1a. Detect Stack

```bash
cd /path/to/repo  # <- Replace with the actual repository path
ls package.json pyproject.toml go.mod Cargo.toml Package.swift build.gradle.kts pom.xml 2>/dev/null
```

### B1b. Configure Repo Settings (before deploying workflows)

Configure repo settings via API BEFORE deploying workflows. Without this, `allowed_actions: "local_only"` causes silent `startup_failure` on all workflows using external actions.

**Important:** If the org controls Actions permissions, repo-level API calls return 409 Conflict. Check org-level first: `gh api orgs/ORG/actions/permissions/selected-actions`. If org-level is set, modify it there instead of per-repo.

```bash
OWNER="owner"
REPO="repo"

# ── Repo settings (merge, auto-merge, branch cleanup) ──
gh api "repos/$OWNER/$REPO" -X PATCH \
  -F allow_merge_commit=false \
  -F allow_squash_merge=true \
  -F allow_rebase_merge=false \
  -F allow_update_branch=true \
  -F delete_branch_on_merge=true \
  -F allow_auto_merge=true \
  --silent

# ── Actions permissions ──
# Set to "selected" — allows github-owned + specific third-party
gh api "repos/$OWNER/$REPO/actions/permissions" -X PUT \
  -f allowed_actions=selected -F enabled=true -F sha_pinning_required=true

# Allowlist: github-owned always + specific third-party patterns
gh api "repos/$OWNER/$REPO/actions/permissions/selected-actions" -X PUT \
  --input - <<'EOF'
{
  "github_owned_allowed": true,
  "verified_creator_allowed": false,
  "patterns_allowed": [
    "step-security/harden-runner@*",
    "ossf/scorecard-action@*",
    "suzuki-shunsuke/pinact-action@*"
  ]
}
EOF

# ── Branch protection (required for safe auto-merge) ──
# Without this, auto-merge merges PRs immediately without waiting for CI.
# Adapt "contexts" to match actual job names from the repo's tests.yml.
gh api "repos/$OWNER/$REPO/branches/$DEFAULT_BRANCH/protection" -X PUT \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["test (ubuntu-latest)", "test (macos-latest)"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF

# ── Verify ──
gh api "repos/$OWNER/$REPO" --jq '{allow_merge_commit, allow_squash_merge, allow_rebase_merge, allow_update_branch, delete_branch_on_merge, allow_auto_merge}'
gh api "repos/$OWNER/$REPO/actions/permissions" --jq '{allowed_actions, sha_pinning_required}'
gh api "repos/$OWNER/$REPO/branches/$DEFAULT_BRANCH/protection/required_status_checks" --jq '{strict, contexts}'
```

Add patterns for any additional third-party actions the repo uses (e.g., `anchore/sbom-action@*`, `aquasecurity/trivy-action@*`, `codecov/codecov-action@*`).

**Branch protection notes:**
- `strict: true` requires the PR branch to be up-to-date with main before merging (works with `allow_update_branch`)
- `contexts` must match exact job names from CI workflows — run `gh run view <run-id>` to see job names
- `enforce_admins: false` lets repo owner bypass (solo dev escape hatch). Set `true` for team repos
- `required_pull_request_reviews: null` skips review requirement — solo dev doesn't need self-approval
- Without branch protection, `allow_auto_merge` merges immediately with no checks — always pair them

### B2. Workflow Hardening (apply to ALL workflows)

Every workflow MUST include these patterns. Apply before deploying any component.

**Mandatory in every workflow file:**

```yaml
# 1. Path filtering — skip CI for docs-only changes
on:
  push:
    branches: [main]
    # WARNING: If you later add `paths:` to this trigger, remove `paths-ignore` —
    # do not combine both. See audit checks for details.
    paths-ignore:
      - '**/*.md'
      - 'docs/**'
      - 'LICENSE'
  pull_request:
    # WARNING: If you later add `paths:` to this trigger, remove `paths-ignore` —
    # do not combine both.
    paths-ignore:
      - '**/*.md'
      - 'docs/**'
      - 'LICENSE'

# 2. Concurrency — cancel stale runs on same PR
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

# 3. Top-level least-privilege permissions
permissions:
  contents: read

# 4. Explicit shell
defaults:
  run:
    shell: bash
```

**Mandatory on every job:**
```yaml
jobs:
  example:
    runs-on: ubuntu-latest
    timeout-minutes: 10  # Always set — no runaway jobs
```

**Security workflow uses `paths` (not `paths-ignore`)** — only triggers when security-relevant files change:
```yaml
on:
  pull_request:
    paths:
      - '.github/**'
      - '**/*.sh'
      - '**/*.js'
      - '**/*.py'
      - '**/*.yml'
      - 'package.json'
      - '**/package-lock.json'
      - '**/pnpm-lock.yaml'
      - '**/yarn.lock'
      - '**/go.sum'
      - '**/requirements*.txt'
      - '**/Dockerfile'
      - '**/*.tf'
      # ⚠️ Do NOT add paths-ignore here — combining paths + paths-ignore
      # on the same trigger is undefined behavior in GitHub Actions.
```

**SHA pin verification script** (`.github/scripts/check-pinned-uses.sh`):

Extract the inline grep to a reusable script. Handles quoted `uses:` values, local action refs, and docker:// refs:

```bash
#!/usr/bin/env bash
set -euo pipefail
status=0
while IFS= read -r -d '' file; do
  while IFS= read -r raw; do
    line_no="${raw%%:*}"
    line="${raw#*:}"
    ref="$(printf '%s' "$line" \
      | sed -E "s/^[[:space:]]*uses:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]].*$//; s/^['\"]//; s/['\"]$//")"
    case "$ref" in
      ./*|docker://*) continue ;;  # Local refs + docker:// exempt
    esac
    if [[ ! "$ref" =~ @[0-9a-f]{40}$ ]]; then
      echo "::error file=$file,line=$line_no::Unpinned or invalid action/workflow ref: $ref"
      status=1
    fi
  done < <(grep -nE '^[[:space:]]*uses:[[:space:]]*[^[:space:]]+@[^[:space:]]+' "$file" || true)
done < <(find .github/workflows .github/actions -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 2>/dev/null)
exit $status
```

**Reports summary job** — add to security.yml for PR summary:
```yaml
  reports:
    if: always()
    needs: [trivy, semgrep, checkov, zizmor]
    runs-on: ubuntu-latest
    timeout-minutes: 2
    steps:
      - name: Write summary
        env:
          TRIVY: ${{ needs.trivy.result }}
          SEMGREP: ${{ needs.semgrep.result }}
          CHECKOV: ${{ needs.checkov.result }}
          ZIZMOR: ${{ needs.zizmor.result }}
        run: |
          {
            echo "## Security Backstop"
            echo "| Scanner | Result |"
            echo "|---------|--------|"
            echo "| trivy | $TRIVY |"
            echo "| semgrep | $SEMGREP |"
            echo "| checkov | $CHECKOV |"
            echo "| zizmor | $ZIZMOR |"
          } >> "$GITHUB_STEP_SUMMARY"
```

**`pull_request` over `pull_request_target`** — never use `pull_request_target` with untrusted code. All workflows use `pull_request`.

### B3. Deploy Components

Deploy in this order — each is independent:

#### A. Tests + Coverage (Codecov)

**Workflow** — use tailored workflow per repo, NOT the universal template:

<details><summary>TypeScript/JavaScript (vitest)</summary>

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
    with:
      persist-credentials: false
  - uses: actions/setup-node@53b83947a5a98c8d113130e565377fae1a50d02f # v6.3.0
    with:
      node-version: 20
      cache: npm
  - run: npm install @vitest/coverage-v8
  - run: npx vitest run --coverage
  - uses: codecov/codecov-action@1af58845a975a7985b0beb0cbe6fbbb71a41dbad # v5.5.3
    with:
      token: ${{ secrets.CODECOV_TOKEN }}
```
</details>

<details><summary>Python (pytest)</summary>

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
    with:
      persist-credentials: false
  - uses: actions/setup-python@a309ff8b426b58ec0e2a45f0f869d46889d02405 # v6.2.0
    with:
      python-version: "3.12"
      cache: pip
  - run: pip install ".[dev]" pytest-cov
  - run: pytest --cov --cov-report=xml
  - uses: codecov/codecov-action@1af58845a975a7985b0beb0cbe6fbbb71a41dbad # v5.5.3
    with:
      token: ${{ secrets.CODECOV_TOKEN }}
```
</details>

<details><summary>Rust (cargo-llvm-cov)</summary>

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
    with:
      persist-credentials: false
  - uses: dtolnay/rust-toolchain@efa25f7f19611383d5b0ccf2d1c8914531636bf9 # stable
    with:
      toolchain: stable
      components: llvm-tools-preview
  - uses: Swatinem/rust-cache@82a92a6e8fbeee089604da2575dc567ae9ddeaaf # v2.7.5
  - uses: taiki-e/install-action@0c48e7d0d41c6c13ecc8a3a78cda3882cb2e9464 # v2.52.4
  - run: cargo llvm-cov --lcov --output-path lcov.info
  - uses: codecov/codecov-action@1af58845a975a7985b0beb0cbe6fbbb71a41dbad # v5.5.3
    with:
      token: ${{ secrets.CODECOV_TOKEN }}
      files: lcov.info
```

**Key Rust optimizations:**
- `Swatinem/rust-cache` caches `~/.cargo` and `target/` — turns 5+ min rebuilds into ~30s
- `taiki-e/install-action@cargo-llvm-cov` downloads pre-built binary (vs `cargo install` compiling from source, saving 2-3 min)
- `components: llvm-tools-preview` on toolchain is required by cargo-llvm-cov
</details>

<details><summary>Swift (iOS — xcodebuild)</summary>

```yaml
runs-on: macos-latest  # ⚠️ 10x cost multiplier vs ubuntu-latest
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
    with:
      persist-credentials: false
  - run: |
      xcodebuild test \
        -scheme TestTargetName \
        -destination 'platform=iOS Simulator,name=iPhone 16' \
        -enableCodeCoverage YES
  - uses: codecov/codecov-action@1af58845a975a7985b0beb0cbe6fbbb71a41dbad # v5.5.3
    with:
      token: ${{ secrets.CODECOV_TOKEN }}
```
</details>

<details><summary>Go</summary>

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
    with:
      persist-credentials: false
  - uses: actions/setup-go@d35c59abb061a4a6fb18e82ac0862c26744d6ab5 # v5.5.0
    with:
      go-version-file: go.mod  # reads 'go' directive; fallback: go-version: "stable"
      cache: true
  - run: go test -coverprofile=coverage.out ./...
  - uses: codecov/codecov-action@1af58845a975a7985b0beb0cbe6fbbb71a41dbad # v5.5.3
    with:
      token: ${{ secrets.CODECOV_TOKEN }}
```
</details>

**Codecov config** (`codecov.yml` at repo root):

```yaml
coverage:
  status:
    project: off          # No global coverage vanity metrics
    patch:
      default:
        target: 80%       # New code must have 80% coverage
        threshold: 5%
comment:
  layout: "condensed_header, diff, flags, components"
  behavior: default
  require_changes: true
```

**Secret:** Set `CODECOV_TOKEN` as org-level secret (one token for all org repos).

#### B. Action Pinning (Pinact)

**Workflow** (`.github/workflows/pinact.yml`):

```yaml
name: Auto-pin GitHub Actions
on:
  push:
    branches: [main]  # Change to match repo default branch
    paths:
      - '.github/workflows/**'

permissions: {}

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

defaults:
  run:
    shell: bash

jobs:
  pin:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: suzuki-shunsuke/pinact-action@cf51507d80d4d6522a07348e3d58790290eaf0b6 # v2.0.0
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

**Local pre-push:** Run `pinact run --fix .github/workflows/*.yml` before pushing to avoid CI failures from imprecise version comments.

**Key gotchas:**
- `branches:` must match repo's actual default branch (`main` vs `master`)
- Do NOT use `persist-credentials: false` on checkout — pinact needs push access for auto-fix commits
- Version comments must be precise (`# v4.2.2` not `# v4`) — pinact enforces this

#### C. Compliance (SBOM + License + Vulnerability — combined single job)

Combine SBOM generation, license compliance, and vulnerability scanning into a single `compliance` job. This saves 2 billable minutes per push (3 jobs → 1), since each GitHub Actions job is billed minimum 1 minute even if it runs in 15 seconds.

```yaml
  compliance:
    if: github.event_name == 'push'
    needs: test  # or 'build' if the first job is named 'build'
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@fa2e9d605c4eeb9fcad4c99c224cee0c6c7f3594 # v2.16.0
        with:
          egress-policy: audit
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          persist-credentials: false
      - name: Generate SBOM
        uses: anchore/sbom-action@e22c389904149dbc22b58101806040fa8d37a610 # v0.24.0
        with:
          format: spdx-json
          output-file: sbom.spdx.json
      - name: Trivy license scan
        uses: aquasecurity/trivy-action@57a97c7e7821a5776cebc9bb87c984fa69cba8f1 # v0.35.0
        with:
          scan-type: fs
          scanners: license
          severity: CRITICAL
          exit-code: 1
      - name: Trivy vulnerability scan
        uses: aquasecurity/trivy-action@57a97c7e7821a5776cebc9bb87c984fa69cba8f1 # v0.35.0
        with:
          scan-type: fs
          scanners: vuln
          severity: CRITICAL,HIGH
          ignore-unfixed: true
          exit-code: 1
```

**Key points:**
- `needs:` must match the first job name (`test` or `build`)
- All three scans run sequentially in one runner (saves 2 billable minutes vs 3 parallel jobs)
- If license scan fails, vuln scan still won't run — acceptable tradeoff for the cost savings
- SBOM scans lockfiles (`package-lock.json`, `Cargo.lock`, `requirements.txt`, `Package.resolved`, etc.)
- Syft auto-detects the package manager from the repo contents
- Trivy vuln: `exit-code: 1` makes CRITICAL/HIGH a hard gate; `ignore-unfixed: true` skips unfixable CVEs
- Trivy license: CRITICAL only (GPL-3.0, AGPL-3.0); HIGH (LGPL) doesn't block

<details><summary>Adding Build Attestations (requires GitHub Team or public repos)</summary>

`actions/attest-build-provenance` creates a signed provenance statement ("this SBOM was built by this workflow, from this commit"). However, it requires **GitHub Team plan ($4/user/month) or a public repository**. Private repos on the free plan get:

```
Error: Feature not available for the <org> organization.
To enable this feature, please upgrade the billing plan, or make this repository public.
```

To add attestations when eligible, add these permissions and step to the `sbom` job:

```yaml
    permissions:
      contents: read
      id-token: write        # Sigstore OIDC for keyless attestation
      attestations: write    # GitHub Artifact Attestations API
    steps:
      # ... after SBOM generation ...
      - name: Attest SBOM provenance
        uses: actions/attest-build-provenance@a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32 # v4.1.0
        with:
          subject-path: sbom.spdx.json
```

Verify locally: `gh attestation verify sbom.spdx.json --repo owner/repo`

</details>

#### D. Release Archive Attestation (non-binary repos)

For repos that distribute via GitHub Releases as source archives (shell projects, config repos, tools installed via `curl | sh`), attest the GitHub-generated source archives (tarball + zip) on each release. This proves the release was created by the CI workflow, not uploaded manually or tampered with. Skip for packages distributed exclusively via registries (npm, PyPI, crates.io) where the registry is the trust boundary.

**Requires:** Public repository (any plan) or GitHub Enterprise Cloud for private repos. Private repos on GitHub Free/Team get `Feature not available`.

**Architecture:** Split into a separate `attest` job with isolated permissions — the release job keeps only `contents/issues/pull-requests: write`, while the attest job gets the minimal `id-token: write` + `attestations: write` scope. This prevents the `id-token: write` permission (used for Sigstore OIDC) from being available to the job that runs `npx` with third-party packages.

**Add to `release.yml`** — the `release` job must expose outputs for the attest job:

```yaml
  release:
    # ... existing release job ...
    outputs:
      new_release: ${{ steps.release.outputs.new_release }}
      tag: ${{ steps.release.outputs.tag }}
    steps:
      # ... existing steps ...
      - name: Release
        id: release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          BEFORE_TAG=$(gh release view --json tagName -q '.tagName' 2>/dev/null || echo "")
          npx -y -p semantic-release -p @semantic-release/changelog -p @semantic-release/git -p @semantic-release/github semantic-release
          AFTER_TAG=$(gh release view --json tagName -q '.tagName' 2>/dev/null || echo "")
          if [ -n "$AFTER_TAG" ] && [ "$BEFORE_TAG" != "$AFTER_TAG" ]; then
            echo "new_release=true" >> "$GITHUB_OUTPUT"
            echo "tag=$AFTER_TAG" >> "$GITHUB_OUTPUT"
          elif [ -n "$AFTER_TAG" ]; then
            # Rerun recovery: if latest tag points to this commit, allow attestation retry
            TAG_SHA=$(git rev-list -n 1 "$AFTER_TAG" 2>/dev/null || echo "")
            if [ "$TAG_SHA" = "$(git rev-parse HEAD)" ]; then
              echo "new_release=true" >> "$GITHUB_OUTPUT"
              echo "tag=$AFTER_TAG" >> "$GITHUB_OUTPUT"
            fi
          fi

  attest:
    needs: release
    if: needs.release.outputs.new_release == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
      id-token: write
      attestations: write
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@fa2e9d605c4eeb9fcad4c99c224cee0c6c7f3594 # v2.16.0
        with:
          egress-policy: audit
      - name: Download source archives
        env:
          TAG: ${{ needs.release.outputs.tag }}
          REPO: ${{ github.repository }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "::error::Unexpected tag format: $TAG"; exit 1; }
          mkdir -p dist
          REPO_NAME="${REPO##*/}"
          gh api "repos/${REPO}/tarball/${TAG}" > "dist/${REPO_NAME}-${TAG}.tar.gz"
          gh api "repos/${REPO}/zipball/${TAG}" > "dist/${REPO_NAME}-${TAG}.zip"
          tar tzf "dist/${REPO_NAME}-${TAG}.tar.gz" > /dev/null
          unzip -t "dist/${REPO_NAME}-${TAG}.zip" > /dev/null
      - name: Attest source archives
        uses: actions/attest-build-provenance@a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32 # v4.1.0
        with:
          subject-path: 'dist/*'
```

**Key points:**
- `BEFORE_TAG`/`AFTER_TAG` comparison detects whether semantic-release created a new release — attest job is skipped on no-op pushes (docs-only, chore commits). The `elif` branch handles rerun recovery: if the latest tag already points to HEAD (release succeeded but attest failed on a prior run), attestation is re-triggered
- Tag is validated against semver regex before use in filenames/URLs — prevents path traversal if tag source is ever compromised
- `${{ github.repository }}` is passed via `REPO` env var (not inline in `run:` block) — prevents template injection
- `tar tzf` + `unzip -t` validate archive integrity before attestation — catches truncated/corrupt downloads
- Top-level `permissions: {}` on the workflow with job-level permissions on each job — least privilege
- No `actions/checkout` needed in attest job — only downloads release archives via API

**Verify locally:**
```bash
gh release download v1.0.0 --archive tar.gz --dir dist/
gh attestation verify dist/*.tar.gz --repo owner/<repo>
```

**When NOT to use:** Repos that produce compiled binaries should use Cosign signing (Section G) instead. Release archive attestation is for source-only distributions where the GitHub-generated tarball/zip IS the release artifact.

#### E–F. Vulnerability Scanning + License Compliance

**Now combined into the `compliance` job above (Section C).** Previously separate `vuln-scan` and `license-check` jobs, consolidated 2026-03-25 to save 2 billable minutes per push (each job is billed minimum 1 minute).

#### G. Release with Cosign (forge only)

For repos that produce binaries, add `.github/workflows/release.yml` triggered on `v*` tags:

```yaml
# Triggers on: git tag v0.1.0 && git push --tags
# Produces: cross-compiled binaries + SBOM + Cosign signatures
# Verify: cosign verify-blob --signature forge-linux-amd64.sig --certificate forge-linux-amd64.pem forge-linux-amd64
```

**Belt-and-suspenders for release artifacts:**
| Layer | Tool | Applies to | What it proves |
|-------|------|-----------|----------------|
| SBOM | Syft (anchore/sbom-action) | All repos with deps | What dependencies are inside |
| Release attestation | GitHub (attest-build-provenance) | Source-only repos (Section D) | Source archives built by CI, not tampered |
| Signature | Cosign (keyless via Sigstore) | Binary repos only | Binary integrity (not tampered post-build) |
| Binary attestation | GitHub (attest-build-provenance) | Binary repos only | Who built it and how |

**Requires:** GitHub Team plan or public repo for all attestation features.

#### H. _(Reserved — previously SSH Signing setup, moved to Section 3)_

#### I. Semantic Release + Commitlint (open-source repos)

For repos that need automated versioning, changelogs, and GitHub Releases. Only add when the repo has external consumers (npm, PyPI, crates.io, or GitHub Releases).

**Prerequisites:** Repo must already use conventional commits (`feat:`, `fix:`, etc.).

**Step 1: commitlint config** (`commitlint.config.js` at repo root):

```js
export default { extends: ['@commitlint/config-conventional'] };
```

**Step 2: semantic-release config** (`.releaserc.json` at repo root):

```json
{
  "branches": ["main"],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/changelog",
    ["@semantic-release/github", {
      "successComment": false,
      "failTitle": false
    }]
  ]
}
```

Add `@semantic-release/npm` plugin if publishing to npm. Add `@semantic-release/exec` for custom release scripts (e.g., `cargo publish`).

**Step 3: CI workflow** (`.github/workflows/release.yml`):

```yaml
name: Release

on:
  push:
    branches: [main]

permissions: {}

defaults:
  run:
    shell: bash

jobs:
  release:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: write
      issues: write
      pull-requests: write
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@fa2e9d605c4eeb9fcad4c99c224cee0c6c7f3594 # v2.16.0
        with:
          egress-policy: audit
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          fetch-depth: 0
      - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
        with:
          node-version: 20
      - name: Release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: npx -y -p semantic-release -p @semantic-release/changelog -p @semantic-release/github semantic-release
```

**IMPORTANT:**
- Do NOT use `persist-credentials: false` on checkout — semantic-release needs push access to create tags
- Do NOT use `npm ci` — repos may not have lockfiles. Always use the npx CI-only approach
- semantic-release bundles `@semantic-release/npm` and loads it by default. Non-Node repos need a minimal root `package.json` with `"private": true` to satisfy its `verifyConditions` check

**Step 4: Commitlint CI check** — add to `tests.yml`:

```yaml
  commitlint:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@fa2e9d605c4eeb9fcad4c99c224cee0c6c7f3594 # v2.16.0
        with:
          egress-policy: audit
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          fetch-depth: 0
          persist-credentials: false
      - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
        with:
          node-version: 20
      - run: npm install @commitlint/cli @commitlint/config-conventional
      - name: Lint commits
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
        run: npx commitlint --from "$BASE_SHA" --to "$HEAD_SHA"
```

**Step 5: Dev dependencies** — add to the repo:

```bash
npm install -D semantic-release @semantic-release/changelog @semantic-release/github @commitlint/cli @commitlint/config-conventional
```

For non-Node repos (Go, Rust, Python, Swift), create a minimal root `package.json`:

```json
{
  "private": true,
  "version": "0.0.0-development",
  "name": "repo-name",
  "description": "repo description"
}
```

`private: true` tells the bundled `@semantic-release/npm` plugin to skip npm publishing. Without this file, semantic-release fails with `ENOPKG Missing package.json file`.

**Key points:**
- `fetch-depth: 0` is required — semantic-release reads full git history for version calculation
- `successComment: false` prevents noisy bot comments on every merged PR
- `failTitle: false` prevents auto-creating issues on release failure
- Commitlint runs on PRs only (validates all commits in the PR range)
- semantic-release runs on push to main only (after merge)
- All repos use the npx CI-only approach (no dev dependencies needed)
- For **forge** (Rust binary): semantic-release creates the GitHub Release (with tag) via `release.yml`, then `release-build.yml` (triggered by `release: types: [published]`) handles cross-compilation + Cosign signing. Two workflows, clean separation.

#### J. OpenSSF Scorecard (all repos)

**Workflow** (`.github/workflows/scorecard.yml`):

```yaml
name: OpenSSF Scorecard

on:
  schedule:
    - cron: "0 6 * * 1"  # Weekly Monday 6am UTC — schedule-only (push trigger removed 2026-03-25, saves ~55 min/mo across 10 repos)

jobs:
  scorecard:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      actions: read
      issues: read
      checks: read
      pull-requests: read
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@fa2e9d605c4eeb9fcad4c99c224cee0c6c7f3594 # v2.16.0
        with:
          egress-policy: audit
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          persist-credentials: false
      - name: Run Scorecard
        uses: ossf/scorecard-action@99c09fe975337306107572b4fdf4db224cf8e2f2 # v2.4.3
        with:
          results_file: results.sarif
          results_format: sarif
          publish_results: false
          repo_token: ${{ secrets.GITHUB_TOKEN }}
      - name: Upload results as artifact
        uses: actions/upload-artifact@bbbca2ddaa5d8feaa63e36b76fdaad77386f024f # v4.6.2
        with:
          name: scorecard-results
          path: results.sarif
          retention-days: 30
```

**Key points:**
- `publish_results: false` for private repos (API rejects private repos). Flip to `true` when going public.
- `repo_token` must be explicit — Scorecard's GraphQL queries fail with "Resource not accessible by integration" without it
- Job-level permissions include `issues`, `checks`, `pull-requests` read — Scorecard checks these for its 18 scoring categories
- Do NOT use top-level `permissions: read-all` alongside job-level permissions — they conflict and the job-level overrides, dropping the top-level grants
- SARIF upload to Security tab requires GitHub Advanced Security (paid for private repos). Use `upload-artifact` instead on free plan. When going public, add `security-events: write` and the `codeql-action/upload-sarif` step.
- Results are downloadable as artifact from the Actions run for 30 days

**When going public checklist:**
1. Set `publish_results: true`
2. Add `security-events: write` to job permissions
3. Add `upload-sarif` step after `upload-artifact`
4. The OpenSSF badge will appear at `https://scorecard.dev/viewer/?uri=github.com/ORG/REPO`

#### K. Security Policy (all repos)

Add `SECURITY.md` at repo root with:
- Vulnerability disclosure email (security@diveanddev.com)
- Response timeline (48h acknowledgment, 1 week assessment)
- Scope (all code, dependencies, infrastructure)
- Recognition policy for responsible disclosure

#### L. Dependabot (all repos — GitHub-native)

Dependabot provides two layers, both now deployed:

1. **Security alerts** — flags vulnerable dependencies in the Security tab (GitHub-native, always on)
2. **Version updates** — weekly PRs for outdated deps via `.github/dependabot.yml` (deployed to all 9 repos)

**Deployed config** (`.github/dependabot.yml`):

```yaml
version: 2
updates:
  - package-ecosystem: "npm"        # or "cargo", "swift" per repo
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 3
    groups:
      all-dependencies:
        patterns:
          - "*"
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 3
    groups:
      all-actions:
        patterns:
          - "*"
```

**Key config choices (updated 2026-03-25):**
- `open-pull-requests-limit: 3` — caps noise; prevents PR fatigue for solo dev
- `groups.all-dependencies` with `patterns: ["*"]` — batches ALL updates (minor+patch+major) into one PR per ecosystem. Maximum 2-3 PRs per repo per week instead of potentially dozens
- Previous `minor-and-patch` grouping left major updates ungrouped, creating individual PRs that each triggered the full CI suite
- Per-repo ecosystem detection: npm (all), github-actions (all), swift (drift), cargo (forge)

**Ecosystem support:** `npm`, `pip`, `gomod`, `cargo`, `swift`, `github-actions`, `composer`, `maven`, `gradle`, `nuget`, `bundler`, and more.

**Relationship with other security tools:**
- **Trivy** scans in CI on every push — catches vulns at build time
- **Dependabot** monitors continuously on GitHub — catches vulns between pushes
- **OpenSSF Scorecard** checks whether Dependabot/similar is enabled — scores the practice

#### M. Commit Signing with SSH (all machines)

SSH signing (Git 2.34+) is simpler than GPG — reuses existing SSH keys, no keyring management.

**One-time setup (already applied globally):**

```bash
# 1. Identify your SSH key (use whichever key you have)
#    Common: ~/.ssh/id_ed25519.pub, ~/.ssh/id_rsa.pub, or custom path
SSH_KEY="$HOME/.ssh/id_rsa.pub"  # ← adjust to your key

# 2. Configure git to use SSH signing
git config --global gpg.format ssh
git config --global user.signingkey "$SSH_KEY"
git config --global commit.gpgsign true      # enforce on all commits
git config --global tag.gpgsign true         # enforce on all tags

# 3. Create/append to allowed_signers file (for local signature verification)
#    Uses your git email as the principal — must match commit author email
EMAIL=$(git config --global user.email)
grep -qF "$EMAIL" ~/.ssh/allowed_signers 2>/dev/null || echo "$EMAIL $(cat "$SSH_KEY")" >> ~/.ssh/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers

# 4. Load key into SSH agent
#    macOS: --apple-use-keychain persists passphrase across reboots
#    Linux: use ssh-add without the flag (or configure ssh-agent in shell profile)
ssh-add --apple-use-keychain "${SSH_KEY%.pub}"  # macOS; drop --apple-use-keychain on Linux
```

**GitHub setup (required for "Verified" badge):**

1. Go to **Settings > SSH and GPG keys**
2. Click **"New SSH key"**
3. Set **Key type** to **"Signing Key"** (not "Authentication Key")
4. Paste contents of your SSH public key file

The same key can be added as both Authentication and Signing key.

**Verification:**

```bash
# Check a commit signature locally
git log --show-signature -1

# Verify git config
git config --global --get gpg.format        # → ssh
git config --global --get commit.gpgsign    # → true
```

**New machine setup:**

```bash
# Copy SSH key pair to new machine, then:
SSH_KEY="$HOME/.ssh/id_rsa.pub"  # ← adjust to your key
ssh-add --apple-use-keychain "${SSH_KEY%.pub}"  # macOS; drop --apple-use-keychain on Linux

# Re-apply git config (not synced automatically)
git config --global gpg.format ssh
git config --global user.signingkey "$SSH_KEY"
git config --global commit.gpgsign true
git config --global tag.gpgsign true

# Set up allowed_signers
EMAIL=$(git config --global user.email)
grep -qF "$EMAIL" ~/.ssh/allowed_signers 2>/dev/null || echo "$EMAIL $(cat "$SSH_KEY")" >> ~/.ssh/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
```

**Why SSH over GPG:**
- Reuses existing SSH keys — no separate GPG keyring
- macOS Keychain handles passphrase — no gpg-agent needed
- GitHub supports SSH signatures natively since 2022
- Simpler key management for solo developer workflow

#### N. Security Scanning Backstop (all repos)

CI backstop for security checks that seatbelt (or local hooks) runs at commit time. Defense-in-depth: catches issues from commits that bypass local hooks (e.g., `SKIP_SEATBELT=1`, no seatbelt installed, direct push from another machine).

**Workflow** (`.github/workflows/security.yml`) — uses Section 2 hardening patterns (paths, concurrency, permissions, defaults, timeouts):

```yaml
name: Security

on:
  pull_request:
    paths:                          # Only run on security-relevant changes
      - '.github/**'
      - '**/*.sh'
      - '**/*.js'
      - '**/*.py'
      - '**/*.yml'
      - 'package.json'
      - '**/package-lock.json'
      - '**/pnpm-lock.yaml'
      - '**/yarn.lock'
      - '**/go.sum'
      - '**/requirements*.txt'
      - '**/Dockerfile'
      - '**/*.tf'
  push:
    branches: [main]
    paths: [...]                    # Same paths as pull_request

concurrency:
  group: security-${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

defaults:
  run:
    shell: bash

jobs:
  trivy:
    name: Dependency CVEs
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@<SHA> # v2.16.0
        with:
          egress-policy: audit
      - uses: actions/checkout@<SHA> # v6.0.2
        with:
          persist-credentials: false
      - name: Check for compliance job
        id: check
        run: |
          if grep -ql 'trivy-action\|scanners.*vuln' .github/workflows/tests.yml 2>/dev/null; then
            echo "skip=true" >> "$GITHUB_OUTPUT"
            echo "Trivy already covered by compliance job — skipping"
          fi
      - name: Install trivy
        if: steps.check.outputs.skip != 'true'
        run: |
          # Prefer aquasecurity/trivy-action (SHA-pinned) in CI workflows.
          # This curl fallback is for standalone security.yml without trivy-action.
          curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/v0.58.2/contrib/install.sh \
            | sudo sh -s -- -b /usr/local/bin v0.58.2
          trivy --version
      - name: Scan dependencies
        if: steps.check.outputs.skip != 'true'
        run: trivy fs --scanners vuln --severity HIGH,CRITICAL --exit-code 1 --skip-dirs tests .

  semgrep:
    name: Code security
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@<SHA> # v2.16.0
        with:
          egress-policy: audit
      - uses: actions/checkout@<SHA> # v6.0.2
        with:
          persist-credentials: false
      - name: Install semgrep
        run: pip install --quiet semgrep
      - name: Scan for vulnerabilities
        run: semgrep scan --config p/security-audit --error --exclude tests .

  checkov:
    name: IaC misconfig
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@<SHA> # v2.16.0
        with:
          egress-policy: audit
      - uses: actions/checkout@<SHA> # v6.0.2
        with:
          persist-credentials: false
      - name: Install checkov
        run: pip install --quiet checkov
      - name: Scan for misconfigurations
        run: checkov -d . --skip-path tests --quiet --compact

  zizmor:
    name: Actions security
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@<SHA> # v2.16.0
        with:
          egress-policy: audit
      - uses: actions/checkout@<SHA> # v6.0.2
        with:
          persist-credentials: false
      - name: Verify SHA pinning
        run: bash .github/scripts/check-pinned-uses.sh
      - name: Install zizmor
        run: pip install --quiet zizmor
      - name: Scan GitHub Actions workflows
        run: zizmor .github/workflows/

  reports:
    if: always()
    needs: [trivy, semgrep, checkov, zizmor]
    runs-on: ubuntu-latest
    timeout-minutes: 2
    steps:
      - name: Write summary
        env:
          TRIVY: ${{ needs.trivy.result }}
          SEMGREP: ${{ needs.semgrep.result }}
          CHECKOV: ${{ needs.checkov.result }}
          ZIZMOR: ${{ needs.zizmor.result }}
        run: |
          {
            echo "## Security Backstop"
            echo "| Scanner | Result |"
            echo "|---------|--------|"
            echo "| trivy | $TRIVY |"
            echo "| semgrep | $SEMGREP |"
            echo "| checkov | $CHECKOV |"
            echo "| zizmor | $ZIZMOR |"
          } >> "$GITHUB_STEP_SUMMARY"
```

**Required file:** `.github/scripts/check-pinned-uses.sh` — see Section 2 for the script.

**Key points:**
- Separate from `compliance` job — compliance handles supply-chain (SBOM, licenses, dep vulns); security handles code/config scanning
- Runs on push AND PRs (unlike compliance which is push-only) — catches issues before merge
- `tests/` excluded from semgrep and checkov to avoid false positives on test fixtures
- `pip install` for Python tools (semgrep, checkov, zizmor) — no additional GitHub Actions to pin/maintain
- Trivy auto-skips if compliance job exists in `tests.yml` — one template for all repos, no manual toggling
- **Workflow changes are a high-risk path** — the zizmor job runs SHA pin verification BEFORE zizmor scan; both block on failure. This catches AI-generated workflows that use tags instead of SHA pins
- SHA pin verification uses grep, not pinact CLI — zero extra dependencies, catches `@v4` / `@main` / short SHAs. Local actions (`uses: ./`) and `docker://` refs are exempt
- **Inline version comment is mandatory:** `@<sha> # vX.Y.Z` on the same line. Dependabot reads this comment to track which version the SHA corresponds to and updates both SHA + comment when bumping
- Secrets scanning is NOT here — GitGuardian handles CI-level secrets detection
- Seatbelt users get the same checks locally via PreToolUse hooks; this is the CI fallback
- All four jobs run in parallel (~3 min total wall time)

**GitHub repo/org setting — Actions permissions + SHA pinning (mandatory):**

Configure Actions permissions BEFORE deploying workflows. Without this, `allowed_actions: "local_only"` (GitHub's default for some configurations) causes `startup_failure` on all workflows using external actions — no logs, no jobs, just silent failure.

**Step 1: Set allowed actions** (via API or Settings UI):

```bash
# Set to "selected" — allows github-owned + specific third-party
gh api repos/OWNER/REPO/actions/permissions -X PUT \
  -f allowed_actions=selected -F enabled=true

# Allowlist: github-owned always + specific third-party patterns
gh api repos/OWNER/REPO/actions/permissions/selected-actions -X PUT \
  --input - <<'EOF'
{
  "github_owned_allowed": true,
  "verified_creator_allowed": false,
  "patterns_allowed": [
    "step-security/harden-runner@*",
    "ossf/scorecard-action@*",
    "suzuki-shunsuke/pinact-action@*"
  ]
}
EOF
```

Or via UI: **Settings → Actions → General → Actions permissions → "Allow select actions and reusable workflows"**, then add patterns.

`github_owned_allowed: true` covers `actions/checkout`, `actions/setup-node`, `actions/upload-artifact`, etc. Third-party actions need explicit patterns.

**Step 2: Require SHA pinning:**

In the same Settings page, check **"Require actions to be pinned to a full-length commit SHA"**. This blocks workflow runs if unpinned actions are detected, even before CI jobs start.

**Verify:**
```bash
gh api repos/OWNER/REPO/actions/permissions --jq '.'
# → {"allowed_actions":"selected","enabled":true,"sha_pinning_required":true}
gh api repos/OWNER/REPO/actions/permissions/selected-actions --jq '.'
# → {"github_owned_allowed":true,"patterns_allowed":["step-security/harden-runner@*",...]}
```

This complements the CI grep check (catches at PR time) and pinact (auto-fixes on merge). Together:

| Layer | When | What | Behavior |
|-------|------|------|----------|
| **GitHub setting** | Workflow run | Rejects unpinned actions | Hard block (workflow won't start) |
| **security.yml grep** | Push + PR | Detects `@v4` / `@main` / short SHA | CI failure |
| **Zizmor** | Push + PR | Script injection, dangerous triggers, etc. | CI failure |
| **Pinact** | After merge to main | Auto-pins tags to SHA | Auto-fix |
| **Dependabot** | Weekly | PRs to bump pinned SHAs to latest release | Version freshness |
| **Seatbelt zizmor** | Local commit | Staged workflow issues | WARN |

Pin → detect → fix → **upgrade** → local catch. Without Dependabot, SHA-pinned actions never get updated and workflows slowly go stale.

Dependabot config for `github-actions` ecosystem (already in Section L):
```yaml
- package-ecosystem: "github-actions"
  directory: "/"
  schedule:
    interval: "weekly"
  open-pull-requests-limit: 3
  groups:
    all-actions:
      patterns:
        - "*"
```

Especially valuable for AI-written workflows — LLMs default to version tags (`@v4`) not SHA pins.

**Critical: Dependabot alerts do NOT cover SHA-pinned actions.** GitHub docs state that for GitHub Actions, Dependabot alerts only fire for semantic version refs — not SHA versioning. The Pin → Detect → Fix → Upgrade chain (SHA check + Zizmor + Pinact + Dependabot version updates) is not redundant — it is the **necessary maintenance mechanism** for a SHA pin strategy. Without it, pinned actions silently go stale with no alerts.

**Artifact retention:** All workflows using `upload-artifact` must set `retention-days: 5–30`. GitHub defaults to 90 days; GitHub Free orgs have only 500 MB artifact storage. Scorecard: 30 days. Coverage/reports: 5 days.

**Relationship with local scanning:**
| Scanner | Local (seatbelt/hooks) | CI (security.yml) | CI (compliance job) |
|---------|----------------------|--------------------|--------------------|
| semgrep | Staged files, `p/security-audit` | Full repo, `p/security-audit` | — |
| checkov | Staged IaC files, BLOCK | Full repo, BLOCK | — |
| zizmor | Staged workflows, WARN | All workflows, BLOCK | — |
| trivy | Staged lock files, WARN | — | Full repo, BLOCK (HIGH+CRITICAL) |
| gitleaks | Staged changes, BLOCK | — | — (GitGuardian covers CI) |

### B4. Multi-Repo Deployment

```bash
REPOS="repo1 repo2 repo3"

# Deploy pinact + codecov in one pass
for repo in $REPOS; do
  (
    cd "/Volumes/Work/Projects/$repo" || { echo "SKIP $repo: directory not found"; exit 1; }

    # Detect stack
    LANG="unknown"
    [ -f package.json ] && LANG="javascript"
    [ -f pyproject.toml ] && LANG="python"
    [ -f go.mod ] && LANG="go"
    [ -f Cargo.toml ] && LANG="rust"
    [ -f Package.swift ] && LANG="swift"

    echo "── $repo ($LANG) ──"

    # Fix version comments before committing
    pinact run --fix .github/workflows/*.yml 2>/dev/null

    git add .github/workflows/ codecov.yml
    git commit -m "ci: add full pipeline (tests+coverage, pinact)" || { echo "FAIL $repo: commit failed"; exit 1; }
    git push || { echo "FAIL $repo: push failed"; exit 1; }
  ) || echo "WARN: $repo failed, continuing..."
done
```

### B5. Audit Pipeline Completeness

```bash
# Auto-discover git repos in the projects directory
PROJECTS_DIR="/Volumes/Work/Projects"
for dir in "$PROJECTS_DIR"/*/; do
  [ -e "$dir/.git" ] || continue
  repo=$(basename "$dir")
  codecov="❌"; pinact="❌"; tests="❌"
  [ -f "$dir/codecov.yml" ] && codecov="✅"
  [ -f "$dir/.github/workflows/pinact.yml" ] && pinact="✅"
  # DeepSource removed — secrets detection handled by gitleaks/GitGuardian
  [ -f "$dir/.github/workflows/tests.yml" ] && tests="✅"
  sbom="❌"; license="❌"; vuln="❌"; lic_file="❌"
  grep -q 'sbom-action' "$dir/.github/workflows/tests.yml" 2>/dev/null && sbom="✅"
  grep -q 'scanners.*license' "$dir/.github/workflows/tests.yml" 2>/dev/null && license="✅"
  grep -q 'scanners.*vuln\|trivy-action' "$dir/.github/workflows/tests.yml" 2>/dev/null && vuln="✅"
  [ -f "$dir/LICENSE" ] && lic_file="✅"
  harden="❌"; semrel="❌"; commitlint_cfg="❌"
  grep -q 'harden-runner' "$dir/.github/workflows/tests.yml" 2>/dev/null && harden="✅"
  [ -f "$dir/.releaserc.json" ] && semrel="✅"
  [ -f "$dir/commitlint.config.js" ] && commitlint_cfg="✅"
  scorecard="❌"; security_md="❌"; dependabot="❌"
  [ -f "$dir/.github/workflows/scorecard.yml" ] && scorecard="✅"
  [ -f "$dir/SECURITY.md" ] && security_md="✅"
  [ -f "$dir/.github/dependabot.yml" ] && dependabot="✅"
  echo "$repo: tests=$tests codecov=$codecov pinact=$pinact sbom=$sbom license=$license vuln=$vuln LICENSE=$lic_file harden=$harden semrel=$semrel commitlint=$commitlint_cfg scorecard=$scorecard SECURITY=$security_md dependabot=$dependabot"
done
```

## Common CI Failures & Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `npm ci` lock file out of sync | Lock file from different OS | Use `npm install` instead of `npm ci` |
| `lightningcss.linux-x64-gnu.node` not found | macOS lock file missing Linux binaries | `rm package-lock.json && npm install` |
| `@vitest/coverage-v8` not found | Coverage provider not in deps | Add `npm install -D @vitest/coverage-v8` step |
| `@vitest/coverage-v8` peer dep conflict | Version mismatch with vitest | Match major: vitest 2.x → `@vitest/coverage-v8@^2` |
| `navigationBarTitleDisplayMode unavailable in macOS` | Swift iOS built via `swift test` | Use `xcodebuild test` with iOS Simulator |
| `pytest: command not found` | pytest in optional deps | `pip install ".[dev]" pytest-cov` |
| `File not found: dist/index.js` (pinact) | Wrong SHA for pinact-action | Use release commit SHA, not source commit |
| Empty `with:` block | Removed only child of `with:` | Remove the `with:` line too |
| `pinact run failed` with version diff | Imprecise version comment (`# v4` not `# v4.2.2`) | Run `pinact run --fix` locally before push |
| `Resource not accessible by integration` | Org repo GITHUB_TOKEN can't create trees | Run `pinact run --fix` locally — don't rely on CI auto-fix |
| Monorepo test runner not found | Tests in subdirectory | Use `defaults.run.working-directory: subdir` |
| `Feature not available for the org` (attestation) | Private repo on GitHub Free plan | Remove `attest-build-provenance` step; requires GitHub Team ($4/user/mo) or public repo |
| Trivy vuln-scan fails with HIGH CVEs | Known vulnerabilities in dependencies | Update the vulnerable package (e.g., `npm install multer@latest`), verify no breaking changes, push fix |
| `multer` 7 HIGH DoS CVEs (1.4.5-lts.2) | Outdated multer with multiple DoS vulns | `npm install multer@latest` (2.x) — API compatible, only canton-flow affected |
| `ENOPKG Missing package.json` (semantic-release) | `@semantic-release/npm` bundled by default, requires package.json | Create minimal root `package.json` with `"private": true` |
| `persist-credentials: false` breaks semantic-release | Can't push tags without credentials | Remove `persist-credentials: false` from release.yml checkout only |
| semgrep scan timeout in CI | Large codebase with many source files | Increase `timeout-minutes` or add `--timeout` flag to semgrep scan |
| checkov false positives on test fixtures | Test files contain intentional misconfigs | Ensure `--skip-path tests` is set |
| zizmor flags unpinned actions in new workflow | Newly added workflow before pinact runs | Normal — pinact auto-pins on next push to main |
| `pip install semgrep` fails with Python error | Runner Python version incompatibility | Add `actions/setup-python` step with explicit version |
| `npm ci` fails — no lockfile | semantic-release workflow used `npm ci` | Use `npx -y -p semantic-release ...` instead — no lockfile or deps needed |
| `Resource not accessible by integration` (Scorecard) | GraphQL needs broader token permissions | Add explicit `repo_token: ${{ secrets.GITHUB_TOKEN }}` + `issues/checks/pull-requests: read` |
| `Code Security must be enabled` (Scorecard SARIF) | `upload-sarif` requires GitHub Advanced Security | Use `upload-artifact` instead for private repos on free plan |
| Scorecard `publish_results: true` fails on private repos | OpenSSF API rejects private repos | Set `publish_results: false`; flip to `true` when going public |
| Top-level `permissions: read-all` conflicts with job-level | Job-level overrides drop top-level grants | Use job-level permissions only, never mix with top-level `read-all` |
| `error: Load key: incorrect passphrase` on commit | SSH key not loaded in agent | `ssh-add --apple-use-keychain <your-key>` (macOS) or `ssh-add <your-key>` (Linux) |
| Commits show "Unverified" on GitHub | SSH key not added as Signing Key | GitHub Settings > SSH keys > New SSH key > Key type: "Signing Key" |
| `Unpinned GitHub Actions detected` in CI | AI-generated workflow used tag refs (`@v4`) | Run `pinact run --fix .github/workflows/*.yml` locally, or manually replace tags with full SHAs |
| `startup_failure` on all workflows (0s, no logs) | `allowed_actions` set to `local_only` — blocks all external actions | Set `allowed_actions: selected` via API (see Section N) with `github_owned_allowed: true` + third-party patterns |
| 409 Conflict on `repos/OWNER/REPO/actions/permissions/selected-actions` | Org-level Actions permissions override repo-level — repo API rejects changes when org controls the setting | Use `orgs/ORG/actions/permissions/selected-actions` instead. Check org-level first: `gh api orgs/ORG/actions/permissions/selected-actions` |
| Attest job skipped on workflow rerun after partial failure | `BEFORE_TAG == AFTER_TAG` because semantic-release already created the tag on the first run | Add rerun recovery: check if latest tag points to HEAD via `git rev-list -n 1 "$AFTER_TAG"` (see Section D template) |
| `paths` + `paths-ignore` on same event causes workflow file error | GitHub may reject combining positive and negative path filters on the same trigger | Use `paths` only (positive matching) for security workflows — `paths-ignore` is redundant when not matching excluded extensions |
| zizmor `template-injection` on `${{ needs.*.result }}` | zizmor can't distinguish internal GitHub context from user-controlled input | Use env vars: `env: RESULT: ${{ needs.job.result }}` then `echo "$RESULT"` in the run block |
| semgrep 8+ findings on plugin/config repo | `p/security-audit` scans all files including skill markdown, YAML, and shell scripts — flags patterns that aren't app vulnerabilities | Triage findings: suppress true false positives with `# nosemgrep: <rule-id>` inline, or add `--exclude '*.md' --exclude '*.yml'` to skip non-application files. For repos with no application source code, consider `continue-on-error: true` to make semgrep advisory-only |
| checkov CKV2_GHA_1 "top-level permissions not set" | Workflows use job-level `permissions` but no top-level `permissions` — GitHub defaults GITHUB_TOKEN to write-all when top-level is absent, even if every job restricts it | Add `permissions: {}` (empty) at workflow top level to explicitly deny all defaults. Job-level permissions then grant only what each job needs. This satisfies CKV2_GHA_1 without changing job behavior |
| zizmor artipacked on release/pinact workflows | `persist-credentials: false` missing on checkout — but these workflows intentionally need push access (semantic-release tags, pinact auto-fix commits) | Add `# zizmor: ignore[artipacked]` comment on the checkout `uses:` line to suppress. Document in workflow comment why credentials are needed. Do NOT add `persist-credentials: false` — it would break the workflow |
| zizmor exit code 13 (medium findings) | zizmor uses graduated exit codes: 0=clean, 13=medium, 14=high, other=error | For medium-only findings that are suppressed/acknowledged, the workflow will still fail. Either suppress findings inline (`# zizmor: ignore[rule]`) or use `--min-severity high` to only fail on high+ |

## Key Decisions

- **Tailored workflows over universal template** — each repo has different test runners and structure
- **SHA-pinned actions** — all `uses:` entries must have full SHA + precise version comment
- **Diff-coverage only** (`project: off`, `patch.target: 80%`) — don't gate on global coverage
- **DeepSource removed** — secrets detection handled by gitleaks (local pre-commit) and GitGuardian (CI). Static analysis coverage gap accepted for solo dev
- **`npm install` over `npm ci`** for repos with stale lock files or cross-platform native deps
- **Codecov free tier** (250 uploads/month for private repos) is sufficient for solo dev
- **GitHub Education** includes free Codecov on public and private repos
- **Run pinact locally before push** — org tokens often can't auto-fix via API
- **SBOM on push only** (not PRs) — no point generating dependency lists for unmerged code
- **Separate `sbom` job** with own permissions — test job stays `contents: read` only (least-privilege)
- **Job-level permissions** over top-level — when any job needs extra permissions, move ALL permissions to job-level to avoid accidental privilege escalation
- **Attestations require GitHub Team or public repos** — `attest-build-provenance` fails on private repos with free plan ("Feature not available for the org"). Add attestations later when repos go public or plan is upgraded
- **Cosign only for binary releases** (forge) — web apps have no release artifact to sign
- **Release archive attestation for non-binary repos** — source-only repos (shell projects, config repos) attest GitHub-generated tarball/zip archives on release. Separate `attest` job with isolated `id-token: write` + `attestations: write` permissions — keeps Sigstore OIDC scope away from the `npx`-heavy release job. Tag validated against semver regex, archives integrity-checked with `tar tzf`/`unzip -t` before attestation. `github.repository` passed via env var (not inline `${{ }}`) to prevent template injection. Includes rerun recovery: `elif` branch checks if latest tag points to HEAD via `git rev-list`, so re-running the workflow after a transient attest failure re-triggers attestation. Added 2026-03-30
- **Org-level Actions permissions override repo-level** — `gh api repos/OWNER/REPO/actions/permissions/selected-actions` returns 409 Conflict when the org controls the setting. Always check org-level first: `gh api orgs/ORG/actions/permissions/selected-actions`. If org-level is set, modify it there. Added 2026-03-30
- **Trivy vuln scan on push only** — CRITICAL+HIGH fails the build; MEDIUM/LOW reported but don't block. `ignore-unfixed: true` skips CVEs with no available fix (council decision 2026-03-22: blocking on unfixable CVEs erodes pipeline credibility)
- **Trivy license scan on push only** — CRITICAL only (GPL-3.0, AGPL); HIGH (LGPL from sharp) doesn't block
- **`licensee` skipped** — proprietary licenses aren't in SPDX standard list, reports "NOASSERTION"
- **`licensed` skipped** — dependency license compliance handled by Trivy, `licensed` is overkill for solo dev
- **Proprietary LICENSE in all repos** — "All rights reserved" establishes IP ownership
- **Combined compliance job** (`sbom` + `license-check` + `vuln-scan`) runs sequentially in one runner — saves 2 billable minutes per push vs 3 parallel jobs (updated 2026-03-25). Tradeoff: if license scan fails, vuln scan doesn't run. Acceptable for solo dev
- **Vuln-scan response workflow** — when Trivy flags a dependency: check which repos use it (`grep` across lockfiles), update to fixed version, verify no breaking changes, push fix. Most npm CVEs are fixed by `npm install pkg@latest`
- **semantic-release only for open-source repos** — private web apps deploy on push, not versioned releases. Add when a repo gets external consumers
- **Commitlint is a semantic-release dependency, not standalone** — AI (codex-review gate) handles commit message quality; commitlint enforces machine-parseable format for semantic-release's `feat:`/`fix:` parsing
- **`successComment: false`** — prevents noisy bot comments on every merged PR; `failTitle: false` prevents auto-creating issues on failure
- **Harden-Runner on all ubuntu jobs** — `egress-policy: audit` (log-only) as baseline; skip macOS runners (unsupported). Switch to `block` + allowlist when ready
- **Harden-Runner in every workflow** — tests.yml, pinact.yml, release.yml, scorecard.yml all get it as first step
- **OpenSSF Scorecard weekly only** (push trigger removed 2026-03-25) — grades 18 security practices; `publish_results: false` for private repos, flip when going public. Scorecard checks repo-level posture which doesn't change per-commit
- **Scorecard uses artifact upload not SARIF** — `upload-sarif` needs GitHub Advanced Security (paid for private repos); artifact download is free
- **SECURITY.md in all repos** — establishes vulnerability disclosure policy; OpenSSF Scorecard checks for this file
- **semantic-release always uses npx** — no dev dependencies, no lockfile, no `npm ci`. Works across Node/Python/Rust/Swift repos uniformly
- **Non-Node repos get minimal root `package.json`** — `"private": true` satisfies bundled `@semantic-release/npm` without publishing to npm
- **Forge two-stage release** — `release.yml` (semantic-release) creates GitHub Release with tag → `release-build.yml` (triggered by `release: types: [published]`) builds + Cosign signs binaries
- **Dependabot over Renovate (council decision 2026-03-22)** — Dependabot with `dependabot.yml` is sufficient for a solo dev with 9 repos. Renovate's flexibility (regex managers, preset sharing) is overhead without a team. Grouped minor/patch updates reduce PR noise. 5 open PR limit prevents fatigue. Reassess Renovate only at 50+ repos or with cross-repo preset needs
- **SSH commit signing enforced globally** — `commit.gpgsign=true` and `tag.gpgsign=true` in `~/.gitconfig`. SSH format over GPG — reuses existing SSH keys, macOS Keychain handles passphrase, no gpg-agent needed. Same key serves both authentication and signing on GitHub. OpenSSF Scorecard rewards signed commits
- **checkov BLOCK, zizmor/trivy WARN (local pre-commit)** — IaC misconfigurations hitting prod have high blast radius, so checkov blocks commit via `{"decision":"block"}`. Also blocks on parse errors (unparseable IaC = unscanned = unsafe). zizmor (Actions security) and trivy (dep vulns) stay informational — CI trivy is the real vulnerability gate, and zizmor findings are low-urgency
- **Separate `security.yml` workflow for semgrep/checkov/zizmor CI backstop** — different concern from compliance (supply-chain) job. Security scanning runs on push+PR; compliance runs push-only. Parallel jobs for speed (~3 min wall time). Each scanner gets independent timeout. Added 2026-03-27
- **`pip install` over GitHub Actions for semgrep/checkov/zizmor** — avoids additional action SHAs to maintain; pip install is reliable on ubuntu runners; pinact/Dependabot only track actions, not pip packages — accepted tradeoff for simplicity
- **semgrep `p/security-audit` ruleset in CI** — matches seatbelt's default for consistency. `--error` flag fails on any finding. `--exclude tests` avoids false positives on test fixtures with intentional bad patterns
- **GitGuardian covers secrets in CI, so no gitleaks CI job** — GitGuardian GitHub App runs on every push/PR with a different engine. Two-layer secrets detection: gitleaks (local/seatbelt) + GitGuardian (CI). No need for a third layer
- **Workflow hardening patterns mandatory on all workflows (added 2026-03-27)** — `paths-ignore` (skip docs), `concurrency` (cancel stale), `permissions` (top-level least-privilege), `defaults.run.shell: bash` (explicit), `timeout-minutes` (every job). Security workflow uses `paths` (positive match) instead of `paths-ignore`
- **`pull_request` over `pull_request_target`** — never run untrusted PR code with write permissions. All workflows use `pull_request`
- **External `check-pinned-uses.sh` over inline grep** — handles quoted `uses:` values, reusable across repos, easier to test. Deploy to `.github/scripts/`. Exempt local refs (`./`) and `docker://`
- **`reports` summary job in security.yml** — `if: always()` with `needs:` on all scanners; writes markdown table to `$GITHUB_STEP_SUMMARY` for PR-visible results
- **Dependabot `commit-message.prefix` and `labels`** — `chore(actions)` prefix for conventional commits; `dependencies` + `github-actions` labels for filtering. Dependabot reads `@<sha> # vX.Y.Z` inline comments and updates both SHA + comment
- **No OIDC needed yet (no CI-based deployment)** — all deployments use git-push → platform auto-deploy (Vercel/Netlify), so CI never touches deployment credentials. Existing `id-token: write` is only for Scorecard (OpenSSF API) and Cosign (keyless signing in forge). When CI-based deployment is added, switch to OIDC with trust policy locked to specific repo + environment (no wildcards). Never use static cloud credentials (AWS keys, GCP service accounts) as GitHub secrets for deployment
- **Workflow changes are a high-risk path** — `.github/workflows/**` modifications get explicit SHA pin verification + zizmor scan in the `zizmor` job of `security.yml`. AI-generated workflows frequently use tag refs (`@v4`) instead of full SHA pins; the grep-based verify step catches this before merge. GitHub natively supports "Require actions to be pinned to a full-length commit SHA" at org/repo level — enable this in repo settings for belt-and-suspenders enforcement alongside CI. Added 2026-03-27
- **Squash-only merges** — `allow_squash_merge: true`, merge commits and rebase disabled. Clean single-commit PRs, linear history. `allow_update_branch: true` suggests keeping PRs current. `delete_branch_on_merge: true` auto-cleans merged branches
- **Auto-merge enabled + branch protection required** — lets Dependabot PRs merge automatically after CI passes without manual intervention. MUST be paired with branch protection requiring status checks — without it, auto-merge merges immediately with no CI gate. `enforce_admins: false` for solo dev escape hatch; `strict: true` requires branch to be up-to-date before merge
- **Actions permissions must be `selected` not `local_only`** — `allowed_actions: "local_only"` silently causes `startup_failure` on all workflows using external actions (no logs, no jobs, 0s duration). Configure `allowed_actions: selected` with `github_owned_allowed: true` + explicit third-party patterns BEFORE deploying workflows. Verify with `gh api repos/OWNER/REPO/actions/permissions`. Added 2026-03-27
- **Security workflow uses `paths` only, no `paths-ignore`** — combining `paths` + `paths-ignore` on the same event trigger may cause GitHub to reject the workflow with a generic "workflow file issue" error. Since positive `paths` matching already excludes unmatched extensions (like `.md`), `paths-ignore` is redundant. Added 2026-03-27
- **Reports job uses env vars for `${{ needs.*.result }}`** — zizmor flags inline `${{ needs.job.result }}` expressions as template-injection (low confidence, false positive — values are GitHub-internal). Using `env:` block satisfies the audit with zero behavioral change. Added 2026-03-27
