---
name: helmet
description: >
  Full repo onboarding — bootstraps test infrastructure (Phase A), wires the CI/CD pipeline (Phase B),
  generates a project CLAUDE.md (Phase C), and builds a per-repo CodeGraph index (Phase D).
  Use when onboarding a new repo, setting up tests + CI from scratch, adding Codecov/pinact/SBOM/security scanning,
  auditing pipeline completeness, fixing CI failures, deploying pipeline changes across multiple repos,
  generating/refreshing a repo's CLAUDE.md, or building a tree-sitter code intelligence index.
  Replaces ci-pipeline-setup and test-setup.
---

# Repo Pipeline Setup

Four-phase repo onboarding: **Phase A** bootstraps test infrastructure (language detection, framework detection, test runner + coverage, smoke tests, gold-standard templates). **Phase B** wires the CI/CD pipeline (Codecov, SHA pinning, SBOM, vulnerability scanning, security backstop, Dependabot, commit signing, OpenSSF Scorecard, CodeScene, GitGuardian). **Phase C** generates a project CLAUDE.md by analyzing the repo's tech stack, structure, commands, conventions, and CI configuration — so every new Claude Code session starts with full project context. **Phase D** builds a tree-sitter code knowledge graph via [CodeGraph](https://github.com/colbymchenry/codegraph) — so any agent wired to codegraph answers structural questions (where is X defined, what calls Y, what would break) from the index instead of fanning out grep/Read subagents. Wiring agents is a one-time setup, not part of every run.

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

**Phase C (CLAUDE.md):**
- Onboarding a new repo — auto-runs after Phase B completes
- Repo has no `.claude/CLAUDE.md` or it contains only boilerplate
- User asks to generate or refresh a project's CLAUDE.md
- Significant infrastructure changes (new test framework, CI additions) made CLAUDE.md stale

**Phase D (CodeGraph Index):**
- Onboarding a new repo with code in a codegraph-supported language — auto-runs after Phase C completes when the `codegraph` CLI is on PATH
- Refreshing the index after a large refactor (codegraph also incrementally re-indexes on file save, so manual refresh is rarely needed)
- Adding code intelligence to a repo that already has tests + CI + CLAUDE.md but no `.codegraph/` index
- User asks to build a code graph or enable structural code search (Phase D only builds the index — to *wire* codegraph into agents, surface the D0 one-time prerequisite instead)

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
| `typer` | Typer (CLI) | CliRunner, exit codes, output assertions |
| `click` | Click (CLI) | CliRunner, exit codes, output assertions |
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

Generate up to three test files per detected language:

1. **Smoke test** (always) — proves the app can be imported.
2. **Gold-standard template test** (always) — heavily commented pattern for example-based tests.
3. **Property test template** (opt-in) — ask the user first: *"Does this repo have parsers, validators, serializers, crypto, state machines, or financial logic?"* If yes, generate; if no, skip and don't install the framework.

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
  it.todo('returns expected result for valid input')
  // it('returns expected result for valid input', () => {
  //   const result = yourFunction('valid')
  //   expect(result).toBe(expected)
  // })

  // Error case
  it.todo('throws on invalid input')
  // it('throws on invalid input', () => {
  //   expect(() => yourFunction(null)).toThrow()
  // })
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
    pass  # Replace with real test
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
    pass  # Replace with real test


# Error case: verify error handling
def test_error_case():
    # with pytest.raises(ValueError):
    #     your_function(None)
    pass  # Replace with real test
```

</details>

<details><summary>Python -- Typer CLI example</summary>

```python
"""
TEMPLATE TEST -- Copy this file as a starting point for new test files.

Pattern: pytest + Typer's CliRunner for CLI command testing.
Run: pytest
Coverage: pytest --cov

For full TDD workflow, use `busdriver:tdd`.
For more patterns, see `busdriver:python-testing`.
"""
from typer.testing import CliRunner
from app.main import app  # Adjust to your Typer app import

runner = CliRunner()


# Happy path: verify command runs and produces expected output
def test_command_succeeds():
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "Usage" in result.output


# Error case: verify proper error exit on bad input
def test_command_bad_input():
    result = runner.invoke(app, ["nonexistent-command"])
    assert result.exit_code != 0


# Framework pattern: test a subcommand with arguments
def test_subcommand_with_args(tmp_path):
    """Use tmp_path for any file I/O to keep tests isolated."""
    # result = runner.invoke(app, ["process", "--input", str(tmp_path / "data.csv")])
    # assert result.exit_code == 0
    # assert "Processed" in result.output
    pass  # Replace with real test
```

</details>

<details><summary>Python -- Click CLI example</summary>

```python
"""
TEMPLATE TEST -- Copy this file as a starting point for new test files.

Pattern: pytest + Click's CliRunner for CLI command testing.
Run: pytest
Coverage: pytest --cov

For full TDD workflow, use `busdriver:tdd`.
For more patterns, see `busdriver:python-testing`.
"""
from click.testing import CliRunner
from app.main import cli  # Adjust to your Click group/command import

runner = CliRunner()


# Happy path: verify command runs and produces expected output
def test_command_succeeds():
    result = runner.invoke(cli, ["--help"])
    assert result.exit_code == 0
    assert "Usage" in result.output


# Error case: verify proper error exit on bad input
def test_command_missing_required():
    result = runner.invoke(cli, ["process"])  # Missing required arg
    assert result.exit_code != 0
    assert "Error" in result.output or "Missing" in result.output


# Framework pattern: test with isolated filesystem
def test_command_with_files(tmp_path):
    """Use tmp_path for file I/O; use runner.isolated_filesystem() for CWD isolation."""
    # with runner.isolated_filesystem(temp_dir=tmp_path):
    #     result = runner.invoke(cli, ["init"])
    #     assert result.exit_code == 0
    pass  # Replace with real test
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
    func testHappyPath() throws {
        // let result = yourFunction("valid")
        // XCTAssertEqual(result, expected)
        throw XCTSkip("Template — replace with real test")
    }

    // Error case: verify error handling
    func testErrorCase() throws {
        // XCTAssertThrowsError(try yourFunction(nil))
        throw XCTSkip("Template — replace with real test")
    }
}
```

</details>

Adapt all import paths and function names to match the actual codebase. The template is a starting point -- the tests should compile and pass as-is, so the developer can immediately see the pattern and replace with real tests.

**Placeholder tests:** Avoid always-passing no-op assertions (`assert True`, `expect(true).toBe(true)`, `XCTAssertTrue(true)`) in template tests -- they inflate pass counts and trigger automated reviewer warnings. Instead:
- **Python:** Use `pass` for placeholder bodies
- **TypeScript/JS:** Use `it.todo('description')` (vitest/jest mark them as pending, not passing)
- **Swift:** Use `throw XCTSkip("Template — replace with real test")`
- **Go:** `t.Log(...)` is fine (informational, not a false assertion)
- **Rust:** Commented-out assertions are fine (no placeholder needed)

For tests that demonstrate a real pattern (e.g., importing the app, hitting a real endpoint), use actual assertions -- only use placeholders for commented-out examples the developer hasn't wired up yet.

### C. Property-Based Test Template (Optional)

Property-based testing complements example-based testing by generating random inputs and checking that **invariants** hold across all of them. It catches edge cases that example tests miss (empty strings, unicode boundaries, integer overflow, concurrent-operation orderings).

**When to use property tests:**

| Good fit | Poor fit |
|----------|----------|
| **Parsers / serializers** — round-trip invariants (`parse(serialize(x)) == x`) | CRUD endpoints / HTTP glue |
| **Validators** — rejected inputs stay rejected after canonicalization | UI rendering logic |
| **Crypto / hashing** — output length, determinism, collision properties | Database migrations |
| **State machines** — sequences of operations preserve invariants | Configuration loaders |
| **Financial calculators** — commutative / associative / zero-sum properties | Pure plumbing / pass-throughs |
| **Sort / search / data structures** — algorithmic invariants | Pure presentation-layer code |

If a repo has no modules matching "good fit," skip this template — adding property tests to CRUD handlers is noise, not signal.

**Three gold-standard property patterns** each template demonstrates:

1. **Invariant** — a property that always holds (`reverse(reverse(x)) == x`, `parse(serialize(x)) == x`)
2. **Oracle** — compare new implementation against a simple reference (`my_sort(xs) == sorted(xs)`)
3. **Model/state-machine** — a sequence of operations preserves a higher-level invariant (`push then pop on stack returns same element`)

**File placement:**

| Language | Property test file | Framework | Install |
|----------|-------------------|-----------|---------|
| Python | `tests/test_properties_template.py` | [Hypothesis](https://hypothesis.readthedocs.io) | `pip install hypothesis` |
| TypeScript/JS | `__tests__/properties.test.ts` | [fast-check](https://fast-check.dev) | `npm install -D fast-check` |
| Go | `properties_test.go` | [rapid](https://github.com/flyingmutant/rapid) (preferred — has shrinking) or `testing/quick` (stdlib, no shrinking) | `go get -t pgregory.net/rapid` |
| Rust | `tests/properties.rs` | [proptest](https://docs.rs/proptest) | `cargo add --dev proptest` |
| Swift | `Tests/AppTests/PropertyTests.swift` | Pragmatic mix — see Swift template notes | See notes |

**Opt-in flow:** During Phase A, after detecting language + modules, ask the user:
> *"Does this repo have parsers, validators, serializers, crypto, state machines, or financial logic? (y/n)"*
>
> If yes → generate property test template.
> If no → skip; add no framework dependency.

Default is **no** — don't install framework dependencies speculatively.

<details><summary>Python -- Hypothesis</summary>

```python
"""
PROPERTY TEST TEMPLATE -- Copy this file as a starting point.

When to use: parsers, serializers, validators, crypto, state machines,
financial calculators. NOT for CRUD, HTTP glue, or pure plumbing.

Pattern: Hypothesis generates random inputs; you assert invariants.
Run: pytest tests/test_properties_template.py
Install: pip install hypothesis

For more patterns, see https://hypothesis.readthedocs.io/en/latest/quickstart.html
"""
import pytest
from hypothesis import given, strategies as st

# from your_module import serialize, deserialize, validate, canonicalize


# 1. INVARIANT -- round-trip property: parse(serialize(x)) == x
@given(st.dictionaries(st.text(), st.integers()))
def test_serialize_roundtrip_is_identity(data):
    """Serializing then parsing should always return the original."""
    pytest.skip("Template — replace body with real serialize/deserialize round-trip")
    # assert deserialize(serialize(data)) == data


# 2. ORACLE -- compare implementation to a known-correct reference
@given(st.lists(st.integers()))
def test_custom_sort_matches_python_sorted(xs):
    """Your sort should match Python's built-in sorted()."""
    pytest.skip("Template — replace body with real my_sort vs sorted() comparison")
    # assert my_sort(list(xs)) == sorted(xs)


# 3. MODEL/STATE-MACHINE -- sequences of ops preserve an invariant
@given(st.lists(st.integers()))
def test_push_then_pop_returns_same_element(items):
    """Stack push/pop is a two-way mapping for each element."""
    pytest.skip("Template — replace body with real stack LIFO check")
    # stack = Stack()
    # for item in items:
    #     stack.push(item)
    #     assert stack.pop() == item


# Shrinking example -- Hypothesis will minimize a failing input.
# Uncomment to see: the test will "fail" with a minimal counterexample.
# @given(st.lists(st.integers()))
# def test_intentionally_fails_to_show_shrinking(xs):
#     assert sum(xs) < 1_000_000  # Shrinker finds [1_000_000] as minimal fail
```

</details>

<details><summary>TypeScript/JavaScript -- fast-check</summary>

```typescript
/**
 * PROPERTY TEST TEMPLATE -- Copy this file as a starting point.
 *
 * When to use: parsers, serializers, validators, crypto, state machines,
 * financial calculators. NOT for CRUD, HTTP glue, or pure plumbing.
 *
 * Pattern: fast-check generates random inputs; you assert invariants.
 * Run: npm test -- properties
 * Install: npm install -D fast-check
 *
 * For more patterns, see https://fast-check.dev/docs/tutorials/quick-start/
 */
import { describe, it } from 'vitest'
// import fc from 'fast-check'
// import { serialize, deserialize, mySort, Stack } from '../src/module'

describe('property tests', () => {
  // 1. INVARIANT -- round-trip property
  it.todo('serialize + deserialize is identity')
  // it('serialize + deserialize is identity', () => {
  //   fc.assert(
  //     fc.property(fc.dictionary(fc.string(), fc.integer()), (data) => {
  //       expect(deserialize(serialize(data))).toEqual(data)
  //     })
  //   )
  // })

  // 2. ORACLE -- compare to a reference implementation
  it.todo('custom sort matches Array.prototype.sort')
  // it('custom sort matches Array.prototype.sort', () => {
  //   fc.assert(
  //     fc.property(fc.array(fc.integer()), (xs) => {
  //       const mine = mySort([...xs])
  //       const reference = [...xs].sort((a, b) => a - b)
  //       expect(mine).toEqual(reference)
  //     })
  //   )
  // })

  // 3. MODEL/STATE-MACHINE -- sequence of ops preserves invariant
  it.todo('stack push/pop preserves last-in-first-out')
  // it('stack push/pop preserves last-in-first-out', () => {
  //   fc.assert(
  //     fc.property(fc.array(fc.integer()), (items) => {
  //       const stack = new Stack<number>()
  //       for (const item of items) {
  //         stack.push(item)
  //         expect(stack.pop()).toBe(item)
  //       }
  //     })
  //   )
  // })

  // Shrinking example -- fast-check minimizes a failing input.
  // Uncomment to see: failure report will show the minimal counterexample.
  // it('intentionally fails to demonstrate shrinking', () => {
  //   fc.assert(
  //     fc.property(fc.array(fc.integer()), (xs) => {
  //       expect(xs.reduce((a, b) => a + b, 0)).toBeLessThan(1_000_000)
  //     })
  //   )
  // })
})
```

</details>

<details><summary>Go -- rapid (preferred) or testing/quick (stdlib fallback)</summary>

**Recommended: `pgregory.net/rapid`.** It provides shrinking (automatic minimization of failing inputs), stateful testing, and rich generators. `testing/quick` works but lacks shrinking — debugging failures on nested structs becomes painful.

```go
// Package myapp_test contains property-based tests using pgregory.net/rapid.
//
// When to use: parsers, serializers, validators, crypto, state machines,
// financial calculators. NOT for CRUD, HTTP glue, or pure plumbing.
//
// Pattern: rapid generates random inputs and SHRINKS failures to minimal cases.
// Run: go test -run TestProperty ./...
// Install: go get -t pgregory.net/rapid
//
// For more patterns, see https://pkg.go.dev/pgregory.net/rapid
// Fallback (stdlib, no shrinking): use testing/quick — see commented section below.
package myapp_test

import (
	"testing"
	// Uncomment when you replace t.Skip() bodies with real property checks:
	// "sort"
	// "pgregory.net/rapid"
)

// 1. INVARIANT -- round-trip property
func TestPropertySerializeRoundtrip(t *testing.T) {
	t.Skip("template — replace body with real serialize/deserialize round-trip check")
	// rapid.Check(t, func(t *rapid.T) {
	//     data := rapid.MapOf(rapid.String(), rapid.Int()).Draw(t, "data")
	//     encoded := serialize(data)
	//     decoded := deserialize(encoded)
	//     if !reflect.DeepEqual(decoded, data) {
	//         t.Fatalf("roundtrip mismatch: got %v, want %v", decoded, data)
	//     }
	// })
}

// 2. ORACLE -- compare custom impl against sort.Ints
func TestPropertyCustomSortMatchesStdlib(t *testing.T) {
	t.Skip("template — replace body with real mySort vs sort.Ints comparison")
	// rapid.Check(t, func(t *rapid.T) {
	//     xs := rapid.SliceOf(rapid.Int()).Draw(t, "xs")
	//     mine := mySort(append([]int{}, xs...))
	//     reference := append([]int{}, xs...)
	//     sort.Ints(reference)
	//     if !slices.Equal(mine, reference) {
	//         t.Fatalf("sort mismatch: got %v, want %v", mine, reference)
	//     }
	// })
}

// 3. MODEL/STATE-MACHINE -- stack push/pop invariant
func TestPropertyStackPushPopLIFO(t *testing.T) {
	t.Skip("template — replace body with real stack LIFO invariant check")
	// rapid.Check(t, func(t *rapid.T) {
	//     items := rapid.SliceOf(rapid.Int()).Draw(t, "items")
	//     stack := NewStack[int]()
	//     for _, item := range items {
	//         stack.Push(item)
	//         if got := stack.Pop(); got != item {
	//             t.Fatalf("LIFO violated: push %d then pop %d", item, got)
	//         }
	//     }
	// })
}

// ── Stdlib fallback (no shrinking) ───────────────────────────────────────────
// If you cannot add rapid as a dependency, testing/quick from the stdlib works.
// Failure reports show raw generated inputs (no minimization), so debugging is
// harder — especially for maps and nested structs.
//
// import "testing/quick"
//
// func TestPropertyQuickSerializeRoundtrip(t *testing.T) {
//     f := func(data map[string]int) bool {
//         return reflect.DeepEqual(deserialize(serialize(data)), data)
//     }
//     if err := quick.Check(f, nil); err != nil {
//         t.Error(err)
//     }
// }
```

</details>

<details><summary>Rust -- proptest</summary>

```rust
//! PROPERTY TEST TEMPLATE -- Copy this file as a starting point.
//!
//! When to use: parsers, serializers, validators, crypto, state machines,
//! financial calculators. NOT for CRUD, HTTP glue, or pure plumbing.
//!
//! Pattern: proptest generates random inputs; you assert invariants.
//! Run: cargo test --test properties
//! Install: cargo add --dev proptest
//!
//! For more patterns, see https://proptest-rs.github.io/proptest/

use proptest::prelude::*;

// use std::collections::HashMap;  // uncomment when you wire up the serialize test
// use my_crate::{serialize, deserialize, my_sort};

proptest! {
    // 1. INVARIANT -- round-trip property
    // Remove #[ignore] once you wire up real serialize/deserialize.
    #[test]
    #[ignore = "template — replace body with real round-trip check"]
    fn serialize_roundtrip_is_identity(_data in prop::collection::hash_map(".*", any::<i64>(), 0..10)) {
        // let encoded = serialize(&_data);
        // let decoded: HashMap<String, i64> = deserialize(&encoded).unwrap();
        // prop_assert_eq!(decoded, _data);
    }

    // 2. ORACLE -- compare custom impl against stdlib sort
    #[test]
    #[ignore = "template — replace body with real my_sort vs stdlib comparison"]
    fn custom_sort_matches_stdlib(_xs in prop::collection::vec(any::<i32>(), 0..100)) {
        // let mut mine = _xs.clone();
        // my_sort(&mut mine);
        // let mut reference = _xs.clone();
        // reference.sort();
        // prop_assert_eq!(mine, reference);
    }

    // 3. MODEL/STATE-MACHINE -- stack LIFO invariant
    #[test]
    #[ignore = "template — replace body with real stack LIFO check"]
    fn stack_push_pop_is_lifo(_items in prop::collection::vec(any::<i32>(), 0..50)) {
        // let mut stack: Vec<i32> = Vec::new();
        // for &item in &_items {
        //     stack.push(item);
        //     prop_assert_eq!(stack.pop(), Some(item));
        // }
    }
}
```

</details>

<details><summary>Swift -- pragmatic mix (parameterized tests + custom generators)</summary>

**Swift's property-testing story is weaker than other languages.** The classic choice, SwiftCheck (`typelift/SwiftCheck`), has had no releases since 2019 and has open build failures on Swift 5.9+/6.0. Options:

| Option | Status | Tradeoff |
|--------|--------|----------|
| **Parameterized tests** (XCTest / swift-testing) + hand-rolled generators | Stable, works with toolchain | No shrinking; manual generator code |
| **[swift-gen](https://github.com/pointfreeco/swift-gen)** (Point-Free) | Actively maintained | Data generation only — you write the test loop yourself |
| **SwiftCheck** | Unmaintained since 2019 | Full property API but likely fails to compile on modern Swift |

The template below uses option 1 (parameterized tests + custom generators) because it works without external dependencies. Upgrade to swift-gen if you need richer combinators.

```swift
// PROPERTY TEST TEMPLATE -- Copy this file as a starting point.
//
// When to use: parsers, serializers, validators, crypto, state machines,
// financial calculators. NOT for CRUD, UI glue, or pure plumbing.
//
// Pattern: XCTest with hand-rolled random generators. No external dependency.
// Run: swift test
//
// For richer combinators (without full property framework):
//   .package(url: "https://github.com/pointfreeco/swift-gen", from: "0.4.0")
// For stateful testing and advanced patterns, consider swift-testing's
// `@Test(arguments:)` parameterized tests (Swift 5.10+).

import XCTest

// @testable import MyApp

final class PropertyTests: XCTestCase {
    private let iterations = 100
    private var rng = SystemRandomNumberGenerator()

    // Hand-rolled generators — extend as needed
    private func randomInts(count: Int = Int.random(in: 0...50)) -> [Int] {
        (0..<count).map { _ in Int.random(in: -1000...1000) }
    }

    private func randomString(maxLen: Int = 32) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz "
        let len = Int.random(in: 0...maxLen)
        return String((0..<len).map { _ in chars.randomElement()! })
    }

    // 1. INVARIANT -- round-trip property
    func testSerializeRoundtripIsIdentity() throws {
        throw XCTSkip("Template — replace body with real serialize/deserialize round-trip")
        // for _ in 0..<iterations {
        //     let xs = randomInts()
        //     let encoded = serialize(xs)
        //     let decoded: [Int] = try deserialize(encoded)
        //     XCTAssertEqual(decoded, xs, "roundtrip failed for: \(xs)")
        // }
    }

    // 2. ORACLE -- compare custom impl against stdlib sort
    func testCustomSortMatchesStdlib() throws {
        throw XCTSkip("Template — replace body with real mySort vs sorted() comparison")
        // for _ in 0..<iterations {
        //     let xs = randomInts()
        //     let mine = mySort(xs)
        //     let reference = xs.sorted()
        //     XCTAssertEqual(mine, reference, "sort mismatch for: \(xs)")
        // }
    }

    // 3. MODEL/STATE-MACHINE -- stack LIFO invariant
    func testStackPushPopIsLIFO() throws {
        throw XCTSkip("Template — replace body with real stack LIFO invariant check")
        // for _ in 0..<iterations {
        //     let items = randomInts(count: Int.random(in: 0...20))
        //     var stack = Stack<Int>()
        //     for item in items {
        //         stack.push(item)
        //         XCTAssertEqual(stack.pop(), item, "LIFO violated after pushing \(items)")
        //     }
        // }
    }
}
```

</details>

**Key points:**

- **Opt-in, never speculative** — don't install framework deps unless the user confirms there are modules that benefit
- **Placeholders follow the existing Phase A guidance** — `pass` (Python), `it.todo(...)` (TypeScript/JS — marks as pending, not passing), `t.Skip(...)` (Go), `XCTSkip(...)` (Swift), commented-out assertions (Rust). **Avoid always-passing placeholders** like `return true` or `expect(true).toBe(true)` — they inflate pass counts
- **No dangling unused imports** — comment out imports alongside their usages. Templates must compile under strict settings (`noUnusedLocals`, `-D warnings`, etc.)
- **Three patterns per template** — invariant, oracle, state-machine — covers the high-value property categories
- **Framework docs linked** — developers will extend templates using framework-specific features (shrinking strategies, custom generators, stateful testing)
- **Discovered by normal test runners** — files matching the naming conventions (`tests/test_properties*.py`, `__tests__/properties*.test.ts`, `properties_test.go`, `tests/properties.rs`, `PropertyTests.swift`) are picked up by the default test commands. They run alongside example-based tests; no separate CI job needed
- **NOT a PR gate** — property tests are advisory signal, not required checks. Missing property tests should never block merge

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
- Proceed to Phase B to wire CI/CD pipeline
- Phase C (CLAUDE.md) will auto-run after Phase B completes
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
| **Commitlint** | Enforce Conventional Commits format (open-source repos only) | `commitlint.config.mjs` + `commitlint` job in `tests.yml` |
| **semantic-release** | Auto version bump + changelog + GitHub Release (open-source repos only) | `.releaserc.json` + `.github/workflows/release.yml` |
| **OpenSSF Scorecard** | Security health score (18 checks, weekly cron + push) | `.github/workflows/scorecard.yml` |
| **SECURITY.md** | Vulnerability disclosure policy | `SECURITY.md` at repo root |
| **Dependabot** | Security alerts + automated version update PRs (GitHub-native) | `.github/dependabot.yml` |
| **Dependabot auto-merge** | On opted-in repos (`vars.DEPENDABOT_AUTO_APPROVE=true`): approves AND enqueues auto-merge for patch (any) + safe minor (dev/indirect/github_actions). On opted-out / enterprise-restricted repos: annotate-only — posts manual-review comment for major + production-direct minor; safe bumps merged by hand | `.github/workflows/dependabot-auto-merge.yml` |
| **Commit Signing (SSH)** | Verified commits with SSH key signatures | `~/.gitconfig` (global) + GitHub signing key |
| **checkov (local)** | IaC misconfiguration scan — **BLOCK** on commit | `~/.claude/hooks/pre-commit-iac-scan.sh` |
| **zizmor (local)** | GitHub Actions workflow security — WARN on commit | `~/.claude/hooks/pre-commit-iac-scan.sh` |
| **trivy (local)** | Dependency vuln scan — WARN on commit (CI trivy is the real gate) | `~/.claude/hooks/pre-commit-iac-scan.sh` |
| **Semgrep CI** | Code security scanning backstop — SQLi, XSS, cmd injection (push+PR) | `semgrep` job in `security.yml` |
| **Checkov CI** | IaC misconfiguration CI backstop — Dockerfile, Terraform, k8s, workflows (push+PR) | `checkov` job in `security.yml` |
| **Zizmor CI** | GitHub Actions workflow security CI backstop (push+PR) | `zizmor` job in `security.yml` |
| **CodeScene** | Behavioral code analysis — code health, hotspots, complexity on PRs (student account) | GitHub App + `.codescene/custom-quality-gates.json` |
| **Admin Bypass Audit** | Detect direct-push bypass of required checks — creates `admin-bypass` issue (repos with `enforce_admins: false`) | `.github/workflows/bypass-audit.yml` |

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
| Dependabot auto-merge | `[ -f .github/workflows/dependabot-auto-merge.yml ]` | File exists (N/A if no Dependabot config) |
| Required-checks lock | `[ -f .github/required-checks.lock ]` | File exists (canonical name + source-app registry — see B1c) |
| Required-checks drift detector | `[ -f scripts/check-required-checks.sh ] && [ -x scripts/check-required-checks.sh ]` | Script exists and is executable |
| Scanners required | `gh api repos/$OWNER/$REPO/branches/$DEFAULT_BRANCH/protection/required_status_checks --jq '.contexts as $c | (["Actions security","Code security","Dependency CVEs","IaC misconfig"] - $c | length == 0)'` | Returns `true` iff all four of `Actions security`, `Code security`, `Dependency CVEs`, `IaC misconfig` are required (run B4b retrofit if not). Set-difference: empty result means every required scanner is present in `.contexts`. (GFM treats pipes inside backticks as code, not column delimiters — no escape needed) |
| Codecov config | See Codecov detection logic below | Three-way check |
| LICENSE | `[ -f LICENSE ]` | File exists |
| SECURITY.md | `[ -f SECURITY.md ]` | File exists |
| Release config | `[ -f .releaserc.json ]` | File exists (N/A for non-release repos) |
| Commitlint config | `[ -f commitlint.config.mjs ]` | File exists (N/A for non-release repos) |
| CodeScene config | `[ -f .codescene/custom-quality-gates.json ]` | File exists (N/A if CodeScene App not installed) |
| Property tests | Any of `tests/test_properties*.py`, `__tests__/properties*.test.ts`, `properties_test.go`, `tests/properties.rs`, `PropertyTests.swift` | File exists (advisory; N/A if repo has no parser/validator/crypto/state-machine modules) |

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
| `defaults.run.shell` | Check `defaults.run.shell: bash` is declared (not just any `shell:` key in step-level overrides). **EXCEPTION:** `scorecard.yml` must NOT declare top-level `defaults:` or `env:` — `ossf/scorecard-action` publish verification rejects workflows containing them with `workflow contains global env vars or defaults` (see https://github.com/ossf/scorecard-action#workflow-restrictions) |
| Concurrency group | Every push/PR-triggered workflow must declare a `concurrency:` block (cron-only workflows like scorecard.yml are exempt). Cancellable workflows (cancel-in-progress: true) must use the canonical group: `${{ github.workflow }}-${{ github.event.pull_request.number \|\| github.ref }}` so two different workflows can't accidentally share a group. Non-cancellable workflows (release.yml, bypass-audit.yml) must use `cancel-in-progress: false` AND a commit/sha/ref-keyed group that won't collapse independent runs. Quick lint: `grep -L '^concurrency:' .github/workflows/*.yml` should return only cron-only files |
| Harden-Runner | For each ubuntu job (not macOS), verify `harden-runner` step exists. Check per-job, not per-file |
| SHA-pinned actions | `bash .github/scripts/check-pinned-uses.sh` — exit 0 = pass |
| No `paths` + `paths-ignore` on same trigger | Verify no workflow uses both `paths` and `paths-ignore` on the same trigger event (GitHub ignores `paths-ignore` when `paths` is present) |
| `persist-credentials: false` | Check all checkout steps except release/pinact (which need push access) |
| Cache policy on setup-* | For each `setup-node` step verify a `cache:` input is set (`npm`/`pnpm`/`yarn`); for each `setup-python` verify `cache: pip` (or `poetry`/`pipenv`); for each `setup-go` verify `cache: true`. See B3.0 for the full canonical table and the runnable quick-lint below |
| Cache anti-pattern | Flag any `actions/cache` block whose `path:` includes `node_modules`, `.venv`, `vendor/`, or a bare `target/` — caching install dirs is almost always wrong (cache PM stores instead). Runnable quick-lint below |
| Artifact retention bounded | For each `upload-artifact` step, verify a `retention-days:` value within ~5 lines and ≤ 30. Stricter caps per class: scorecard ≤ 14, coverage ≤ 7, security ≤ 14, release-only on releases. Runnable quick-lint below |

**Quick-lint commands** (copy-paste runnable — pipes inside markdown table cells need backslash-escaping for rendering, which breaks copy-paste; these are the unescaped forms):

```bash
# Cache policy on setup-* (verify `cache:` input is declared on setup-node/python/go steps)
grep -E 'setup-(node|python|go)' .github/workflows/*.yml -A 5 | grep -B 1 'cache:'

# Cache anti-pattern (should return nothing — caching install dirs is almost always wrong)
grep -A 5 'actions/cache@' .github/workflows/*.yml | grep -E 'node_modules|\.venv|vendor/|^[[:space:]]+- target/$'

# Artifact retention bounded (inspect each retention-days value against the per-class caps)
grep -nB 0 -A 5 'upload-artifact' .github/workflows/*.yml | grep -E 'retention-days:'
```

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
| CodeScene | ✅/❌/N-A | quality gates config |
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

# Workflow permissions: try to enable "Allow GitHub Actions to create and
# approve PRs" (default is false). Required for `dependabot-auto-merge.yml`'s
# `hmarr/auto-approve-action` step to post the approving review that satisfies
# branch protection's required_pull_request_reviews. If this returns 409
# Conflict an enterprise admin has disabled GitHub Actions PR approval at the
# enterprise level — that's fine, the workflow falls back to annotate-only
# mode (the script handles this branch explicitly below; other failure modes
# like auth/network/typo errors abort the script instead of silently falling
# through).
#
# Value comparison in the workflow's `if:` is case-sensitive — the var must
# be the exact string `true` to enable approve+auto-merge.
PUT_STDERR=$(mktemp)
trap 'rm -f "$PUT_STDERR"' EXIT
if gh api "repos/$OWNER/$REPO/actions/permissions/workflow" -X PUT \
     --input - >/dev/null 2>"$PUT_STDERR" <<'EOF'
{
  "default_workflow_permissions": "read",
  "can_approve_pull_request_reviews": true
}
EOF
then
  # PUT succeeded → repo CAN have GitHub Actions approve PRs → opt in.
  gh variable set DEPENDABOT_AUTO_APPROVE --body "true" --repo "$OWNER/$REPO"
  echo "Dependabot auto-merge: OPTED IN (full hmarr + auto-merge workflow)"
elif grep -qE "409|Conflict|not allow|not permit|disabled" "$PUT_STDERR"; then
  # PUT explicitly rejected by org/enterprise policy → annotate-only mode.
  # ALSO unset any pre-existing DEPENDABOT_AUTO_APPROVE so re-running the
  # setup on a previously-opted-in repo correctly downgrades to annotate-only
  # if the policy changed (idempotent re-run). Tolerate "not found" (404)
  # but surface real errors (auth/network) so a failed delete cannot silently
  # leave stale opt-in state on a repo that's now enterprise-blocked.
  DEL_STDERR=$(mktemp)
  if gh variable delete DEPENDABOT_AUTO_APPROVE --repo "$OWNER/$REPO" 2>"$DEL_STDERR"; then
    : # deleted successfully
  elif grep -qE "404|Not Found|not found" "$DEL_STDERR"; then
    : # variable didn't exist → nothing to clear, idempotent no-op
  else
    echo "ERROR: failed to clear DEPENDABOT_AUTO_APPROVE for annotate-only mode:" >&2
    cat "$DEL_STDERR" >&2
    rm -f "$DEL_STDERR"
    exit 1
  fi
  rm -f "$DEL_STDERR"
  echo "Dependabot auto-merge: ANNOTATE-ONLY (enterprise blocks GitHub Actions PR approval; safe bumps merged manually)"
else
  # Any OTHER failure (auth, network, typo'd OWNER/REPO, unknown server error)
  # is a real error — surface it instead of silently treating as annotate-only.
  echo "ERROR: gh api PUT actions/permissions/workflow failed for unexpected reason:" >&2
  cat "$PUT_STDERR" >&2
  exit 1
fi

# Allowlist: github-owned always + specific third-party patterns
gh api "repos/$OWNER/$REPO/actions/permissions/selected-actions" -X PUT \
  --input - <<'EOF'
{
  "github_owned_allowed": true,
  "verified_creator_allowed": false,
  "patterns_allowed": [
    "step-security/harden-runner@*",
    "ossf/scorecard-action@*",
    "suzuki-shunsuke/pinact-action@*",
    "aquasecurity/trivy-action@*",
    "dependabot/fetch-metadata@*",
    "hmarr/auto-approve-action@*"
  ]
}
EOF

# ── Branch protection (required for safe auto-merge) ──
# Without this, auto-merge merges PRs immediately without waiting for CI.
# IMPORTANT: Run this AFTER deploying workflows and triggering at least one run.
# GitHub requires a check to have at least one recorded run before accepting it as required.

# Step 1: Discover actual check names from a recent workflow run.
# GitHub uses the `name:` field as the check name; falls back to the job key if no name is set.
ALL_CHECKS=$(gh api "repos/$OWNER/$REPO/commits/$(git rev-parse HEAD)/check-runs" \
  --jq '.check_runs[].name' | sort -u)
echo "Discovered checks:"
echo "$ALL_CHECKS"

# Step 2: Categorize checks.
# Default policy: test + lint + security scanners → required; external AI bots → advisory.
# Required (recommended baseline):
#   - Test/lint:   "test", "test (ubuntu-latest)", "commitlint", "version-drift"
#   - Security:    "Actions security" (zizmor), "Code security" (semgrep),
#                  "Dependency CVEs" (trivy), "IaC misconfig" (checkov)
# Advisory (recommended NOT required):
#   - External AI: "CodeRabbit", "Greptile Review", "cubic · AI code reviewer"
#                  (third-party availability — making them required causes
#                  PRs to hang when the service is slow/unavailable)
#   - "CodeScene": treated as advisory by convention (architectural signal,
#                  not a correctness gate)
#
# Why scanners are required by default (added 2026-05-07):
# Without scanners as required checks, a Dependabot bump of a vulnerable
# npm/pip dep can merge on `test` pass alone — Trivy can flag the CVE on the
# PR but it doesn't block merge unless required. Same applies to manual
# clicks of "Enable auto-merge" on a Dependabot PR with a failing scanner.
# Skipped jobs (helmet's job-level `if:` skip pattern in security.yml) still
# count as passing, so requiring these does not introduce false-positive
# blockage on PRs that don't touch security-relevant files.
#
# Present the discovered list to the user for confirmation before applying.
# User confirms which checks should be required.

# Step 3: Apply via API.
# Build the contexts JSON array from confirmed required checks using jq (handles escaping).
# Adjust the per-repo test names ("test (ubuntu-latest)", etc.) — the security
# scanner names are the same across all helmet-onboarded repos.
CONTEXTS=$(jq -nc '$ARGS.positional' --args \
  "test (ubuntu-latest)" "test (macos-latest)" "commitlint" \
  "Actions security" "Code security" "Dependency CVEs" "IaC misconfig")

jq -n --argjson ctx "$CONTEXTS" \
  '{required_status_checks:{strict:true,contexts:$ctx},enforce_admins:false,required_pull_request_reviews:null,restrictions:null}' \
  | gh api "repos/$OWNER/$REPO/branches/$DEFAULT_BRANCH/protection" -X PUT --input -

# ── Verify ──
gh api "repos/$OWNER/$REPO" --jq '{allow_merge_commit, allow_squash_merge, allow_rebase_merge, allow_update_branch, delete_branch_on_merge, allow_auto_merge}'
gh api "repos/$OWNER/$REPO/actions/permissions" --jq '{allowed_actions, sha_pinning_required}'
gh api "repos/$OWNER/$REPO/branches/$DEFAULT_BRANCH/protection/required_status_checks" --jq '{strict, contexts}'
```

Add patterns for any additional third-party actions the repo uses (e.g., `anchore/sbom-action@*`, `aquasecurity/trivy-action@*`, `codecov/codecov-action@*`).

**Branch protection notes:**
- `strict: true` requires the PR branch to be up-to-date with main before merging (works with `allow_update_branch`)
- **Job name resolution:** GitHub uses the `name:` field if present, otherwise the YAML job key. Example: a job key `zizmor` with `name: Actions security` appears as "Actions security" in status checks. Always verify with `gh api "repos/$OWNER/$REPO/commits/<sha>/check-runs" --jq '.check_runs[].name' | sort -u`
- **Required check prerequisite:** each check must have at least one recorded run on the repository for GitHub to accept it as a required check. Run workflows at least once before setting protection
- `enforce_admins: false` lets repo owner bypass (solo dev escape hatch). **Exit condition:** allowed only while the repo has a single human maintainer. When a second contributor receives write/admin access, flip this to `true` (or migrate to a ruleset with "Do not allow bypassing" enabled) — the bypass-audit workflow flags admin direct-pushes after the fact but cannot prevent them, so the escape hatch is not a team-safe policy. Document the trigger ("when N>1 maintainers, flip enforce_admins") in the project's CLAUDE.md if you anticipate the change
- `required_pull_request_reviews: null` skips review requirement — solo dev doesn't need self-approval. For repos that DO require reviews, `dependabot-auto-merge.yml` satisfies the gate by setting `can_approve_pull_request_reviews: true` on the repo's workflow permissions (configured above): the workflow's `hmarr/auto-approve-action` posts an approving review as `github-actions[bot]`. On enterprise-restricted repos where that setting is blocked at the enterprise level (PUT returns 409 Conflict), the workflow runs in **annotate-only mode** — the operator does not set `vars.DEPENDABOT_AUTO_APPROVE`, so the approve + auto-merge steps skip cleanly and only the manual-review comment fires for major / production-direct minor bumps. Safe bumps on annotate-only repos must be merged manually.
- `bypass_pull_request_allowances: { apps: ["dependabot"] }` on branch protection was previously documented as a fallback for enterprise-restricted repos, but does NOT work in practice: GitHub auto-merge evaluates branch protection from the perspective of the user that *enabled* auto-merge (`github-actions[bot]` from this workflow's `gh pr merge --auto`), not the PR author. The bypass list contains `dependabot`, not `github-actions[bot]`, so bypass never applies. Empirically confirmed on Dive-And-Dev/perch#38 (2026-05-08): all CI green, bypass set, PR sat BLOCKED indefinitely. Do not rely on this mechanism.
- Without branch protection, `allow_auto_merge` merges immediately with no checks — always pair them
- **Renaming a job's `name:` field silently breaks required check enforcement** — the old name stays in branch protection but no longer matches any check, causing PRs to hang. Always update branch protection when renaming job display names

### B1c. Required-Check Name Registry + Source-App Lock

GitHub branch protection records required checks by literal name only — no source-app pinning, no schema. Two failure modes follow:

1. **Silent rename break.** A job's `name:` (or job key, when no name is set) is renamed in a workflow .yml. The old name remains in branch protection's `contexts:` list, never matches any check on subsequent PRs, and PRs hang on a "pending" required check that never resolves. There is no error message — just a PR that never goes green.
2. **Same-name spoofing / app drift.** A different integration starts posting a status under the same name (intentional migration that wasn't reviewed, or accidental clash). Branch protection accepts the new reporter without flagging the change.

A third failure mode that doesn't depend on the lock at all but compounds with the first two:

3. **Cross-workflow check-name collision.** Two workflows post a status check under the same effective name. Branch protection identifies required checks by name only — when names collide, GitHub's API picks one reporter and silently ignores the other. Accidental copy-paste, ill-considered renames, and matrix templates that resolve identically across workflows are all common sources. The collision is invisible until the wrong reporter's status determines merge eligibility.

All three are addressed by recording each required check in `.github/required-checks.lock` alongside the workflow file and expected reporting app, and running `scripts/check-required-checks.sh` to verify drift across four surfaces:

- **(a) Lock vs workflow source** — every required entry maps to a job (by `name:` field or bare job key) in the declared workflow file. Catches mismatched renames before deploy.
- **(b) Lock vs branch protection** — `lock.required[].name` (set) equals server's `required_status_checks.contexts` (set). Catches lock-vs-server desync.
- **(c) Lock vs reporter** — the most recent check-run for each required name has `app.slug == source_app`. Catches integration migration / spoofing.
- **(d) Workflow check-name uniqueness** — every effective check name across all workflows is globally unique. Catches collisions before they get promoted into the lock; runs even when the lock is empty (early onboarding).

**Lock file** (`.github/required-checks.lock`) — JSON, declarative, no `_doc` keys are interpreted by tools (they're for humans):

```json
{
  "_doc": ["see scripts/check-required-checks.sh and SKILL.md B1c"],
  "required": [
    { "name": "version-drift",     "source_app": "github-actions", "workflow": ".github/workflows/tests.yml",    "job": "version-drift" },
    { "name": "commitlint",        "source_app": "github-actions", "workflow": ".github/workflows/tests.yml",    "job": "commitlint" },
    { "name": "Actions security",  "source_app": "github-actions", "workflow": ".github/workflows/security.yml", "job": "zizmor" },
    { "name": "Code security",     "source_app": "github-actions", "workflow": ".github/workflows/security.yml", "job": "semgrep" },
    { "name": "Dependency CVEs",   "source_app": "github-actions", "workflow": ".github/workflows/security.yml", "job": "trivy" },
    { "name": "IaC misconfig",     "source_app": "github-actions", "workflow": ".github/workflows/security.yml", "job": "checkov" }
  ],
  "advisory": []
}
```

Recognized `source_app` values: `github-actions` (in-repo workflow), `codescene`, `codecov`, `coderabbitai`, `greptile`, `cubic`, `github-copilot`, `gitguardian`. Add new ones as needed — the script treats anything other than `github-actions` as an external app and skips the workflow-file check for it.

**Matrix-derived check names** — when a workflow job uses `strategy.matrix`, GitHub renders each combination as `<base> (<label>)` where `<base>` is the explicit `name:` (or bare job key) and `<label>` is the comma-joined matrix values. Each rendered name appears as a separate context in branch protection. Express each one in the lock with an optional `matrix_value` field holding the literal label content:

```json
{
  "required": [
    { "name": "test (ubuntu-latest)", "source_app": "github-actions", "workflow": ".github/workflows/tests.yml", "job": "test", "matrix_value": "ubuntu-latest" },
    { "name": "test (macos-latest)",  "source_app": "github-actions", "workflow": ".github/workflows/tests.yml", "job": "test", "matrix_value": "macos-latest" },
    { "name": "Lint (ubuntu-latest, 18)", "source_app": "github-actions", "workflow": ".github/workflows/tests.yml", "job": "lint", "matrix_value": "ubuntu-latest, 18" }
  ]
}
```

Surface (a) compares the lock's `name` against `<base> (<matrix_value>)`; surfaces (b)/(c) use the rendered `name` directly (no special handling needed since branch protection and check-runs both report the rendered form); surface (d) reads workflow YAML directly and ignores `matrix_value` entirely. Omit `matrix_value` for non-matrix jobs — empty / absent / null all behave the same as a flat entry. Surface (a) does *not* parse the workflow's `strategy.matrix` block to verify a matrix is actually present; it only checks that `name` equals `<base> (<matrix_value>)`. Setting `matrix_value` on a non-matrix job *with* a self-consistent `name` will pass surface (a) — but the user-facing failure shows up downstream as a hung PR (branch protection ends up requiring a context name that no check posts under). The drift detector won't pinpoint that misuse, so keep `matrix_value` off non-matrix jobs.

**Drift detector** (`scripts/check-required-checks.sh`) — exit 0 = clean, exit 1 = drift, exit 2 = config error.

```bash
./scripts/check-required-checks.sh                    # full check (a)+(b)+(c)+(d)
./scripts/check-required-checks.sh --local-only       # (a)+(d) only — no API calls
./scripts/check-required-checks.sh --strict-remote    # turn (b)/(c) "couldn't verify" into drift
./scripts/check-required-checks.sh --owner X --repo Y # override repo target
```

**When to run:**
- Before any branch-protection change (PATCH on `/required_status_checks`).
- Before deploying a workflow rename or job restructure.
- Periodically as a CI lint (suggest weekly via cron or as part of helmet `--check`).

**Maintenance discipline (the rename dance):** when intentionally renaming, removing, or adding a required check, update all three sides in this order:

1. Edit `.github/required-checks.lock` (lock).
2. Edit the workflow's `name:` field or job key (source).
3. Run `gh api -X PATCH repos/OWNER/REPO/branches/main/protection/required_status_checks` with the updated contexts (server). Use PATCH not PUT — see B4b for the idempotent pattern.
4. Run `scripts/check-required-checks.sh` and confirm zero drift on all four surfaces.

Skipping any step leaves the surfaces out of sync, which is exactly what the lock is supposed to prevent.

**(c)-check limitations:** PR-only checks (e.g., `version-drift`, `commitlint` which only run on `pull_request` events) won't appear on a main-branch commit's check-runs. The script walks back through up to 10 recent commits looking for one with check-runs, but for those PR-only checks, expect "no check-run named X — skipping app check" warnings. This is conservative correct: the script never falsely flags drift on a check it didn't see, only on a check whose reporting app actually disagrees with the lock.

**(d)-check scope and limitations:** Walks every top-level workflow file in `.github/workflows/*.{yml,yaml}` and flags any duplicate effective check name regardless of whether the duplicates sit in different workflow files or in the same workflow file — two jobs with the same explicit `name:` value in one workflow are caught the same way as a cross-workflow collision. Reusable workflow callees (`uses: ./.github/workflows/foo.yml`) and composite-action checks aren't walked. Matrix templates with `${{ matrix.* }}` interpolation are stored as their literal template string, so two workflows sharing the same template across files will be flagged (their rendered names will collide for matching matrix values). Within-workflow matrix expansion to distinct values is not flagged because GitHub's runtime renders each combination uniquely.

### B2. Workflow Hardening (apply to ALL workflows)

Every workflow MUST include these patterns. Apply before deploying any component.

**Mandatory in every workflow file:**

```yaml
# 1. Path filtering — skip CI for docs-only changes (push only)
# ⚠️ Do NOT add paths-ignore to pull_request when this workflow is a required
# status check — GitHub leaves the check "Pending" on filtered-out PRs, blocking merge.
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
    # No paths-ignore here — required status checks must always run

# 2. Concurrency — cancel stale runs on same PR
#
# Canonical group: workflow name + PR number (when on a PR) or ref (when not).
# Including `${{ github.workflow }}` is what prevents two different workflows
# from sharing a group accidentally and cancelling each other (a real footgun
# if multiple workflows on the same repo end up with `group: ${{ github.ref }}`).
# Falling back to `github.ref` when `pull_request.number` is null is what
# scopes push-triggered runs per-branch.
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

# Intentional exceptions (must not cancel):
#
#   release.yml:    group: release-${{ github.ref }}, cancel-in-progress: false
#   bypass-audit.yml: group: bypass-audit-${{ github.sha }}, cancel-in-progress: false
#
# Both are non-cancellable: releases must complete or fail cleanly without
# being interrupted (cancelling mid-tag-and-push leaves orphan tags on
# remote); the bypass audit must record one event per commit, never collapse
# overlapping pushes. Every other workflow follows the canonical group.
#
# Cron-only workflows (e.g. scorecard.yml) need no concurrency block —
# the trigger is single-fired by the schedule and cannot collide with itself.

# 3. Top-level deny-all — grant per-job only
permissions: {}

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
      - '**/pyproject.toml'
      - '**/uv.lock'
      - '**/Cargo.lock'
      - '**/Package.resolved'
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
    if [[ ! "$ref" =~ ^[^@]+@[0-9a-f]{40}$ ]]; then
      echo "::error file=$file,line=$line_no::Unpinned or invalid action/workflow ref: $ref"
      status=1
    fi
  done < <(grep -nE '^[[:space:]]*uses:[[:space:]]*[^[:space:]]+@[^[:space:]]+' "$file" || true)
done < <(find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 2>/dev/null; \
         find .github/actions  -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 2>/dev/null || true)
exit $status
```

**Reports summary job** — add to security.yml for PR summary. Requires the `changes` detection job from Section N. Security Scanning Backstop:
```yaml
  reports:
    if: always()
    needs: [changes, trivy, semgrep, checkov, zizmor]
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
          if [[ "$TRIVY" == "failure" || "$SEMGREP" == "failure" || "$CHECKOV" == "failure" || "$ZIZMOR" == "failure" ]]; then
            echo "::error::One or more security scanners failed"
            exit 1
          fi
```

**`pull_request` over `pull_request_target`** — never use `pull_request_target` with untrusted code. All workflows use `pull_request`.

### B3. Deploy Components

Deploy in this order — each is independent:

#### B3.0. Canonical Cache Policy (apply to every language template)

Cache the package manager's *store* (immutable, hash-keyed by lockfile) — never the `node_modules` / `venv` / `target` *install directory* (writable, partial, polluted by build outputs). The setup-* actions handle this correctly when given a `cache:` input; respect their default key strategy (lockfile hash) rather than rolling a manual `actions/cache` block.

| Language | Cache action | Cache key (managed automatically) | What's cached | Anti-pattern (don't) |
|---|---|---|---|---|
| TypeScript / JavaScript | `actions/setup-node` with `cache: npm` (or `pnpm` / `yarn`) | `package-lock.json` / `pnpm-lock.yaml` / `yarn.lock` hash | npm download cache (`~/.npm`), not `node_modules` | manual `actions/cache` keyed on `node_modules/**`; cross-OS sharing of the install dir |
| Python | `actions/setup-python` with `cache: pip` | `requirements.txt` / `pyproject.toml` hash | pip wheel cache (`~/.cache/pip`), not site-packages / `.venv` | caching the venv; `pip install --target` outputs |
| Go | `actions/setup-go` with `cache: true` | `go.sum` hash | module cache (`~/go/pkg/mod`) + build cache (`~/.cache/go-build`) | manual `actions/cache` for `vendor/`; caching workspace state |
| Rust | `Swatinem/rust-cache@<sha>` (purpose-built) | `Cargo.lock` + toolchain | `~/.cargo/registry`, `~/.cargo/git`, `target/` (selectively) | `actions/cache` on `target/` directly — too coarse, picks up build artifacts |
| Swift | `cache: true` on resolved-package step | `Package.resolved` hash | `~/Library/Caches/org.swift.swiftpm` | caching `.build/` |

Why this matters cost-wise: a cache *hit* saves the install time but a *miss* must still upload the cache, so caching the wrong thing (large install dirs) costs upload time on every miss without saving anything on the hit. GitHub also bills on the upload edge.

GitHub-managed cache storage is part of the org's free tier (10 GB on most plans, larger on Enterprise) — keep entries small to avoid LRU eviction of high-value (e.g. Rust) caches. Lint check below catches the most common drift.

**Audit rules** (added to the table in B0. Audit Checks):
- For each `setup-node` step in any workflow, verify a `cache:` input is set (`npm`, `pnpm`, or `yarn`).
- For each `setup-python` step, verify `cache: pip` (or `poetry`/`pipenv` if applicable).
- For each `setup-go` step, verify `cache: true`.
- Flag any `actions/cache` block whose `path:` includes `node_modules`, `.venv`, `vendor/`, or a bare `target/` — these are install-dir anti-patterns and almost always wrong.

#### A. Tests + Coverage (Codecov)

**Workflow** — use tailored workflow per repo, NOT the universal template:

<details><summary>TypeScript/JavaScript (vitest)</summary>

```yaml
steps:
  - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
    with:
      persist-credentials: false
  - uses: actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e # v6.4.0
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
  - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
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
  - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
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
  - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
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
  - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
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

**Secret:** After wiring Codecov, auto-set the repo secret from the `CODECOV_TOKEN` environment variable:
```bash
if [ -n "${CODECOV_TOKEN:-}" ]; then
  echo "$CODECOV_TOKEN" | gh secret set CODECOV_TOKEN --repo "$OWNER/$REPO"
  echo "✅ CODECOV_TOKEN secret set from environment"
else
  echo "⚠️  CODECOV_TOKEN env var not set — set it manually: gh secret set CODECOV_TOKEN --repo $OWNER/$REPO"
fi
```

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
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
      - uses: suzuki-shunsuke/pinact-action@896d595f299e71d65b9d28349d6956abe144390a # v3.0.0
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

**Scanner cadence (cost-aware split — where each layer runs):**

| Trigger | What runs | Where it lives | Why this cadence |
|---------|-----------|----------------|------------------|
| **PR** (every push) | Trivy CVE scan, Semgrep, Checkov, Zizmor (job-level skip on path-irrelevant changes) | `security.yml` | PR-time signal; required checks block merge on CRITICAL/HIGH |
| **Push to main** | SBOM generation (Syft), Trivy license + vuln scan, Cosign keyless sign (if release artifact) | `tests.yml` `compliance` job (`if: github.event_name == 'push'`) | SBOM is a release-artifact concern, not a per-PR concern — generating it for unmerged code wastes minutes and produces unused artifacts |
| **Release** (`release: types: [published]`) | GitHub-native build provenance attestation (when eligible — see Section D) + Cosign keyless sign for binaries | separate `release.yml` / `release-build.yml` | OIDC + attestations need release context, isolated permissions |
| **Weekly** (cron) | OpenSSF Scorecard (18 security practices) | `scorecard.yml` | Repo-level posture doesn't change per-commit; weekly catches drift in the practice score |

This matches ChatGPT's "PR = lightweight, push = artifact, release = signing, weekly = posture" recommendation — the compliance and scorecard jobs are already gated to non-PR triggers; PR-time scanning is delegated to `security.yml`. Don't move SBOM generation onto PR triggers — it would burn minutes and storage on artifacts that never ship.

```yaml
  compliance:
    if: github.event_name == 'push'
    needs: test  # or 'build' if the first job is named 'build'
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: audit
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          persist-credentials: false
      - name: Generate SBOM
        uses: anchore/sbom-action@e22c389904149dbc22b58101806040fa8d37a610 # v0.24.0
        with:
          format: spdx-json
          output-file: sbom.spdx.json
      - name: Trivy license scan
        uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
        with:
          scan-type: fs
          scanners: license
          severity: CRITICAL
          exit-code: 1
      - name: Trivy vulnerability scan
        uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
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
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
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

**When NOT to use:** Repos that produce compiled binaries should use Cosign signing (Section G. Release with Cosign) instead. Release archive attestation is for source-only distributions where the GitHub-generated tarball/zip IS the release artifact.

#### E–F. Vulnerability Scanning + License Compliance

**Now combined into the `compliance` job above (Section C. Compliance).** Previously separate `vuln-scan` and `license-check` jobs, consolidated 2026-03-25 to save 2 billable minutes per push (each job is billed minimum 1 minute).

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
| Release attestation | GitHub (attest-build-provenance) | Source-only repos (Section D. Release Archive Attestation) | Source archives built by CI, not tampered |
| Signature | Cosign (keyless via Sigstore) | Binary repos only | Binary integrity (not tampered post-build) |
| Binary attestation | GitHub (attest-build-provenance) | Binary repos only | Who built it and how |

**Requires:** GitHub Team plan or public repo for all attestation features.

#### H. _(Reserved — previously SSH Signing setup, moved to Section M. Commit Signing with SSH)_

#### I. Semantic Release + Commitlint (open-source repos)

For repos that need automated versioning, changelogs, and GitHub Releases. Only add when the repo has external consumers (npm, PyPI, crates.io, or GitHub Releases).

**Prerequisites:** Repo must already use conventional commits (`feat:`, `fix:`, etc.).

**Step 1: commitlint config** (`commitlint.config.mjs` at repo root):

```js
// subject-case relaxed so Dependabot's start-case "Bump ..." titles pass (the
// PR-title lint sees only the title, which carries no dependabot trailer, so
// the `ignores` rule below cannot cover it); PascalCase/UPPER-CASE still blocked.
// body-max-line-length is off (Dependabot commit bodies run long); the `ignores`
// rule skips lint entirely for Dependabot-signed commits, so hand-written commits
// still get every rule except body length. The trailer is not cryptographically
// bound — this is a commit-message format gate, not a security control.
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'subject-case': [2, 'never', ['pascal-case', 'upper-case']],
    'body-max-line-length': [0, 'always'],
  },
  ignores: [
    (message) => message.includes('Signed-off-by: dependabot[bot]'),
  ],
};
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
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: audit
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          fetch-depth: 0
      - uses: actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e # v6.4.0
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
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: audit
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          fetch-depth: 0
          persist-credentials: false
      - uses: actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e # v6.4.0
        with:
          node-version: 20
      # CI-only, exact-pinned dev install; repo is deliberately lockfile-less
      - run: npm install --no-save --no-package-lock --no-audit --no-fund @commitlint/cli@20.5.0 @commitlint/config-conventional@20.5.0 # zizmor: ignore[adhoc-packages]
      - name: Lint PR title (squash merge message)
        env:
          PR_TITLE: ${{ github.event.pull_request.title }}
        run: echo "$PR_TITLE" | npx commitlint
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
# NOTE: scorecard-action publish verification rejects workflows containing
# any top-level `env:` or `defaults:` block. The B0 audit rule that requires
# `defaults.run.shell: bash` elsewhere explicitly exempts this file.
# https://github.com/ossf/scorecard-action#workflow-restrictions
name: OpenSSF Scorecard

on:
  schedule:
    - cron: "0 6 * * 1"  # Weekly Monday 6am UTC — schedule-only (push trigger removed 2026-03-25, saves ~55 min/mo across 10 repos)

jobs:
  scorecard:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      id-token: write
      contents: read
      actions: read
      issues: read
      checks: read
      pull-requests: read
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: audit
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          persist-credentials: false
      - name: Run Scorecard
        uses: ossf/scorecard-action@4eaacf0543bb3f2c246792bd56e8cdeffafb205a # v2.4.3
        with:
          results_file: results.sarif
          results_format: sarif
          publish_results: false  # CHANGEME: flip to `true` only on a public repo. This input publishes signed results to the public OSSF scorecard.dev / api.scorecard.dev database (distinct from the private-repo SARIF upload path, which is documented separately). Private repos should leave this `false` regardless of GHAS. See "When going public checklist" below.
          repo_token: ${{ secrets.GITHUB_TOKEN }}
      - name: Upload results as artifact
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: scorecard-results
          path: results.sarif
          retention-days: 14
```

**Key points:**
- **NEVER** add top-level `env:` or `defaults:` blocks — `scorecard-action`'s publish-verification step rejects them (`workflow contains global env vars or defaults`). Job fails even though scoring succeeds. The B0 audit's `defaults.run.shell: bash` rule explicitly exempts this file. See https://github.com/ossf/scorecard-action#workflow-restrictions
- `publish_results: false` for private repos (API rejects private repos). Flip to `true` when going public.
- `repo_token` must be explicit — Scorecard's GraphQL queries fail with "Resource not accessible by integration" without it
- Job-level permissions include `issues`, `checks`, `pull-requests` read — Scorecard checks these for its 18 scoring categories
- Do NOT use top-level `permissions: read-all` alongside job-level permissions — they conflict and the job-level overrides, dropping the top-level grants
- SARIF upload to Security tab requires GitHub Advanced Security (paid for private repos). Use `upload-artifact` instead on free plan. When going public, add `security-events: write` and the `codeql-action/upload-sarif` step.
- Results are downloadable as artifact from the Actions run for 14 days (see canonical retention table)

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

Dependabot provides three layers, all now deployed:

1. **Security alerts** — flags vulnerable dependencies in the Security tab (GitHub-native, always on)
2. **Version updates** — weekly PRs for outdated deps via `.github/dependabot.yml` (deployed across all helmet-onboarded repos)
3. **Auto-merge for safe bumps (per-repo opt-in via `vars.DEPENDABOT_AUTO_APPROVE`)** — `.github/workflows/dependabot-auto-merge.yml` runs on every Dependabot PR. On opted-in repos (`vars.DEPENDABOT_AUTO_APPROVE = "true"` AND `can_approve_pull_request_reviews: true` on workflow permissions) it approves and enqueues auto-merge for safe bumps: patch (any) + minor (dev / indirect / github_actions). On opted-out repos (var unset, or enterprise policy blocks GitHub Actions from approving PRs) it runs in **annotate-only mode**: a comment fires for every safe bump explaining manual merge is required, and the existing manual-review comment fires for major / production-direct minor. Major + production-direct minor bumps are NEVER auto-merged on any tier — they always require human eyes

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

**Auth model (explicit, since this is the part that bites):**

Dependabot-triggered workflows are *not* like normal pull_request workflows. Three rules apply:

1. **Event = `pull_request`, never `pull_request_target`.** Dependabot raises PRs from a `dependabot/*` branch within the same repo (not from a fork), so `pull_request` is the right event. `pull_request_target` would run with the *target's* secrets and a writable token against PR-controlled HEAD code — for any other event type that's a known supply-chain class. We never use it. The workflow checks out nothing PR-controlled regardless.
2. **`GITHUB_TOKEN` is read-only by default on Dependabot runs**, regardless of the workflow's `permissions:` defaults at the org/repo level. The explicit job-level `permissions: contents: write + pull-requests: write` is what restores the write scope used by `hmarr/auto-approve-action` and `gh pr merge --auto` and `gh pr comment`. Without that explicit block, every write-side step would fail with a 403. **No PAT is used and no `secrets.*` other than `GITHUB_TOKEN` are referenced** — Actions secrets are unavailable to Dependabot-triggered runs even if they exist.
3. **Approval capability is org/enterprise-gated.** `hmarr/auto-approve-action` posts a review as `github-actions[bot]`, which only counts toward `required_pull_request_reviews` when `can_approve_pull_request_reviews: true` is set on the org or repo. Helmet B1b's setup script attempts to flip this at the repo level. When an enterprise admin pins it off at the enterprise level, the PUT returns 409 Conflict — the script then falls back: `vars.DEPENDABOT_AUTO_APPROVE` is left unset (or actively cleared on idempotent re-run), the approve + auto-merge steps skip cleanly via the `vars.DEPENDABOT_AUTO_APPROVE == 'true'` `if:` guard, and the workflow runs in annotate-only mode. **Bypass via `bypass_pull_request_allowances.apps:["dependabot"]` does NOT work** as a fallback because GitHub auto-merge evaluates branch protection from the actor that *enabled* auto-merge (`github-actions[bot]` from `gh pr merge --auto`), not the PR author — verified empirically on Dive-And-Dev/perch#38 (2026-05-08). Do not reintroduce.

A repo on this design is therefore one of two states: opted in (full automation; `vars.DEPENDABOT_AUTO_APPROVE="true"` AND `can_approve_pull_request_reviews:true` server-side), or opted out (annotate-only; var unset, regardless of why). The `vars.*` value is the single source of truth in the workflow `if:` conditions; the underlying capability is a property of the org/enterprise setting that B1b probes at setup.

**Auto-merge workflow** (`.github/workflows/dependabot-auto-merge.yml`):

```yaml
name: Dependabot Auto-Merge

# Approves AND enqueues auto-merge on Dependabot PRs based on update-type,
# dependency-type, and package-ecosystem — but ONLY on repos where
# `vars.DEPENDABOT_AUTO_APPROVE == 'true'`. On other repos the workflow
# becomes annotate-only: it posts a comment for safe bumps explaining the
# repo is opted out of auto-merge (manual merge needed) AND posts the
# manual-review comment for unsafe bumps. Approve + auto-merge steps
# skip cleanly on opted-out repos — no failed step, no red X.
#
# Auto-approve + auto-merge enqueued (var=true, safe bucket):
#   - patch (any ecosystem, any dependency-type)
#   - minor (dev dependencies, indirect/transitive, OR github_actions ecosystem)
#
# Comment + manual flow (always — fires on every Dependabot PR that doesn't
# fall into the auto-approve+merge bucket above):
#   - safe bump on opted-out repo: "manual merge needed" annotation
#   - major (any): "manual review required"
#   - production direct-dependency minor (non-github_actions ecosystem): "manual review required"
#   - unknown / unrecognized update-type: "inspect bump type" annotation
#
# Why a per-repo variable: GitHub's two ways to satisfy
# `required_approving_review_count` from a workflow are tier-asymmetric:
#
#   * `can_approve_pull_request_reviews: true` lets `hmarr/auto-approve-action`
#     post an approving review as `github-actions[bot]`. Available on
#     Free/Pro/Team and most Enterprise — but enterprise admins can disable it
#     globally, in which case the action errors with "GitHub Actions is not
#     permitted to approve pull requests" and the merge step never satisfies
#     the review gate.
#
#   * `bypass_pull_request_allowances.apps: ["dependabot"]` (Enterprise-only,
#     classic branch protection) was *intended* as the fallback for
#     enterprise-blocked repos, but empirically does not apply when
#     `gh pr merge --auto` is enabled by `github-actions[bot]` — bypass
#     evaluates against the merge actor, and there is no way to make
#     `github-actions[bot]` the actor and a bypass-listed actor at the same
#     time on plans we have. Dependabot's own `@dependabot squash and merge`
#     command is silently dropped on enterprise-restricted orgs as well.
#
# So the honest design is: ON repos where (a) is permitted, fully automate.
# OFF repos where (a) is blocked, run the workflow but skip the auto-merge
# steps — fall back to manual merge for safe bumps. The unsafe-bumps comment
# still fires on both tiers.
#
# Per-repo opt-in: set `vars.DEPENDABOT_AUTO_APPROVE` to the string `"true"`
# (`gh variable set DEPENDABOT_AUTO_APPROVE --body "true" --repo OWNER/REPO`).
# Anything else (unset, "false", "0") leaves the repo in annotate-only mode.
#
# Prerequisites (helmet sets these in B1b. Configure Repo Settings):
# - allow_auto_merge: true on the repo
# - Branch protection with required status checks (strict: true)
# - On AUTO_APPROVE=true repos:
#     - `can_approve_pull_request_reviews: true` on workflow permissions
#     - `hmarr/auto-approve-action@*` in the org/repo Actions allowlist
# - `dependabot/fetch-metadata@*` in the org/repo Actions allowlist (always)
#
# Token note: Dependabot-triggered workflow runs receive a read-only
# GITHUB_TOKEN by default. The explicit `permissions:` block below restores
# write scope (including `pull-requests: write` for the approve step).
# `gh pr merge --auto` only enqueues — actual merge waits for branch-protection
# checks, so no PAT is needed.

on:
  pull_request:

# Workflow-level read baseline. An empty `permissions: {}` denies all scopes —
# including metadata — and was observed to cause `startup_failure` on every
# Dependabot-triggered run (the harden-runner setup step needs at least the
# metadata-read default to initialize). `contents: read` matches the canonical
# pattern in `security.yml`. Per-job blocks below still escalate to `contents:
# write` and `pull-requests: write` where actually required for `gh pr merge`
# and `gh pr comment`.
permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

defaults:
  run:
    shell: bash

jobs:
  auto-merge:
    name: Enqueue Dependabot auto-merge
    # Use the PR object's user.login (immutable) instead of github.actor (spoofable)
    if: github.event.pull_request.user.login == 'dependabot[bot]'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: write          # required to enable auto-merge on the branch
      pull-requests: write     # required to enqueue auto-merge + post comment

    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: audit

      - name: Fetch Dependabot metadata
        id: metadata
        uses: dependabot/fetch-metadata@25dd0e34f4fe68f24cc83900b1fe3fe149efef98 # v3.1.0
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Compute auto-merge policy
        id: policy
        # Single source of truth for "is this PR in the safe auto-merge bucket?"
        # All gating below references steps.policy.outputs.safe — keeps the
        # policy expression in one place instead of duplicating the same
        # boolean across approve/merge/comment steps.
        env:
          UPDATE_TYPE: ${{ steps.metadata.outputs.update-type }}
          DEP_TYPE: ${{ steps.metadata.outputs.dependency-type }}
          PKG_ECO: ${{ steps.metadata.outputs.package-ecosystem }}
        run: |
          safe=false
          if [ "$UPDATE_TYPE" = "version-update:semver-patch" ]; then
            safe=true
          elif [ "$UPDATE_TYPE" = "version-update:semver-minor" ]; then
            case "$DEP_TYPE" in
              direct:development|indirect) safe=true ;;
            esac
            if [ "$PKG_ECO" = "github_actions" ]; then
              safe=true
            fi
          fi
          echo "safe=$safe" >> "$GITHUB_OUTPUT"
          echo "policy: update-type=$UPDATE_TYPE dep-type=$DEP_TYPE pkg-ecosystem=$PKG_ECO safe=$safe"

      - name: Approve PR — patch + safe minor
        # Posts an approving review as github-actions[bot], satisfying branch
        # protection's required_approving_review_count so `gh pr merge --auto`
        # below can fire. Only runs when both:
        #   - policy.safe == 'true' (it's a safe bucket bump)
        #   - vars.DEPENDABOT_AUTO_APPROVE == 'true' (this repo opted in)
        # On opted-out repos this step is skipped cleanly — no failed-step red
        # X, no `!cancelled()` workaround.
        if: steps.policy.outputs.safe == 'true' && vars.DEPENDABOT_AUTO_APPROVE == 'true'
        uses: hmarr/auto-approve-action@f0939ea97e9205ef24d872e76833fa908a770363 # v4.0.0
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Enqueue auto-merge — patch + safe minor
        # `gh pr merge --auto` only enqueues — actual merge waits for branch
        # protection checks. Same gate as the approve step: only on opted-in
        # repos, only for safe bucket bumps.
        if: steps.policy.outputs.safe == 'true' && vars.DEPENDABOT_AUTO_APPROVE == 'true'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          PR_URL: ${{ github.event.pull_request.html_url }}
        run: |
          # Idempotency: Dependabot rebases re-trigger this workflow, hitting
          # "already enabled" on the second run. Tolerate ONLY that specific
          # string; surface every other failure (auth, rate limit, org setting
          # off) so misconfiguration is visible instead of silently leaving
          # PRs stuck.
          out=$(gh pr merge --auto --squash "$PR_URL" 2>&1) || rc=$?
          if [ "${rc:-0}" -ne 0 ]; then
            if [[ "$out" == *"already enabled"* ]]; then
              echo "auto-merge enqueue skipped: already enabled"
            else
              echo "$out" >&2
              exit "$rc"
            fi
          else
            echo "$out"
          fi

      - name: Comment — manual review or manual merge required
        # Two cases handled here:
        #   (1) safe bumps on opted-out repos — workflow can't auto-merge so
        #       posts a "please merge manually" annotation.
        #   (2) unsafe bumps (major / production-direct minor) on any tier —
        #       always require human review.
        # Mutually exclusive per PR (a given Dependabot PR has fixed metadata
        # so it stays in one bucket). Both cases share dedup infrastructure
        # but use distinct hidden markers so future re-classification doesn't
        # accidentally collide.
        if: |
          steps.policy.outputs.safe == 'false' ||
          (steps.policy.outputs.safe == 'true' && vars.DEPENDABOT_AUTO_APPROVE != 'true')
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          PR_URL: ${{ github.event.pull_request.html_url }}
          UPDATE_TYPE: ${{ steps.metadata.outputs.update-type }}
          DEPENDENCY_TYPE: ${{ steps.metadata.outputs.dependency-type }}
          PACKAGE_ECOSYSTEM: ${{ steps.metadata.outputs.package-ecosystem }}
          DEPENDENCY_NAMES: ${{ steps.metadata.outputs.dependency-names }}
          POLICY_SAFE: ${{ steps.policy.outputs.safe }}
        run: |
          set -eo pipefail
          # Distinct markers per case so dedup is scoped correctly.
          if [ "$POLICY_SAFE" = "true" ]; then
            MARKER="<!-- dependabot-auto-merge: annotate-only -->"
          else
            MARKER="<!-- dependabot-auto-merge: manual-review-required -->"
          fi

          # Capture existing-comments fetch OUTSIDE the if-condition. Bash
          # suspends `set -e` for commands used as `if` test conditions (per
          # `man bash`), so `if gh ... | grep -qF` would let gh failures fall
          # through to the else branch → post comment. Same set-e-suspension
          # class as the security.yml `changes` detector. Here the harm is
          # fail-noisy (duplicate comment) rather than fail-open (silent
          # scanner skip), but the canonical pattern keeps the failure mode
          # explicit instead of implicit.
          existing_comments=$(gh pr view "$PR_URL" --json comments \
              --jq '.comments[] | select(.author.login == "github-actions[bot]") | .body' 2>&1) || {
            echo "::warning::gh pr view failed — posting comment without dedup check (fail-closed)"
            echo "$existing_comments" >&2
            existing_comments=""
          }

          # Capture grep's exit status explicitly. Same class of set-e
          # suspension bug as above. Exit 0 = found, 1 = not found,
          # 2+ = grep error (regex compile, I/O); on grep error, post the
          # comment (better noisy than missed alert).
          grep_status=0
          grep -qF "$MARKER" <<< "$existing_comments" || grep_status=$?
          case "$grep_status" in
            0)
              echo "already commented on this PR — skipping"
              exit 0
              ;;
            1) ;;  # no prior marker found — fall through and post
            *)
              echo "::warning::grep failed (exit $grep_status) — posting comment (fail-closed)"
              ;;
          esac

          # Body composition by case.
          # printf so the run: | block contains no literal newlines mid-string —
          # earlier `--body "${MARKER}\n${REASON}…"` form broke Dependabot's
          # stricter YAML parser (the second line was column-1, terminating the
          # block scalar; Dependabot's update engine reported
          # "/.github/workflows/dependabot-auto-merge.yml not parseable" even
          # though GitHub Actions accepted it).
          if [ "$POLICY_SAFE" = "true" ]; then
            REASON="Safe bump (${PACKAGE_ECOSYSTEM} / ${DEPENDENCY_NAMES})"
            CTA="Auto-merge skipped — this repo runs the auto-merge workflow in annotate-only mode (vars.DEPENDABOT_AUTO_APPROVE != 'true', usually because the org or enterprise blocks GitHub Actions from approving PRs). Please merge manually once required checks pass."
          elif [ "$UPDATE_TYPE" = "version-update:semver-major" ]; then
            REASON="Major version bump detected (${PACKAGE_ECOSYSTEM} / ${DEPENDENCY_NAMES})"
            CTA="Auto-merge skipped — please review changes manually before merging."
          elif [ "$UPDATE_TYPE" = "version-update:semver-minor" ]; then
            REASON="Production direct-dependency minor bump (${PACKAGE_ECOSYSTEM} / ${DEPENDENCY_NAMES})"
            CTA="Auto-merge skipped — please review changes manually before merging."
          else
            REASON="Unsafe Dependabot bump — update-type='${UPDATE_TYPE}' dependency-type='${DEPENDENCY_TYPE}' (${PACKAGE_ECOSYSTEM} / ${DEPENDENCY_NAMES})"
            CTA="Auto-merge skipped — please inspect the bump type and merge manually if appropriate."
          fi
          BODY=$(printf '%s\n\n%s. %s\n' "$MARKER" "$REASON" "$CTA")
          gh pr comment "$PR_URL" --body "$BODY"
```

**Key points:**
- **`if: github.event.pull_request.user.login == 'dependabot[bot]'`** — workflow runs on every PR but the only job is gated; non-Dependabot PRs see the job as skipped (counts as passing for branch protection). `pull_request.user.login` is read from the immutable PR object; `github.actor` is spoofable (zizmor `bot-conditions` audit), so prefer the former
- **`fetch-metadata` reports the highest update-type** across grouped updates — if any single dep in a grouped PR is a major bump, the whole PR routes to the major branch
- **Per-repo opt-in via `vars.DEPENDABOT_AUTO_APPROVE`**: when set to `"true"` AND the repo has `can_approve_pull_request_reviews: true` on workflow permissions, the workflow approves and enqueues auto-merge for safe bumps. When unset (default) or `false` — the workflow runs in **annotate-only** mode: approve + merge steps skip cleanly, only the comment step fires. This is the right default for enterprise-restricted orgs that disable GitHub Actions PR approval; the approve step never tries (no failed-step red X) and the operator merges safe bumps by hand
- **Auto-approve via `hmarr/auto-approve-action`** (opted-in repos only) — posts an approving review as `github-actions[bot]`, satisfying `required_approving_review_count`. Runs as `GITHUB_TOKEN`; no PAT, no long-lived secret. SHA-pinned for supply-chain safety
- **Tiered gating** computed once in a `policy` step (`steps.policy.outputs.safe`), referenced by approve/merge/comment: patch (any) + minor (dev / indirect / github_actions) → safe; major (any) + production-direct minor → unsafe. Single source of truth for the policy expression instead of duplicating across three steps
- **`--auto --squash`** matches helmet's squash-only merge strategy (`allow_squash_merge: true`, others off). `gh pr merge --auto` enqueues; the merge fires only after all required status checks pass AND review requirements are met
- **No PAT, no `pull_request_target`** — explicit `permissions:` on a `pull_request` workflow is enough for Dependabot's restricted-token case; preserves helmet's "never `pull_request_target`" rule
- **Two comment markers** for distinct dedup scopes: `annotate-only` (safe bump on opted-out repo, "merge manually") and `manual-review-required` (unsafe bump on any tier). A given PR has stable Dependabot metadata so it falls into exactly one marker class — distinct markers prevent collision if a future workflow change re-classifies a PR mid-lifecycle
- **Idempotent under re-runs**: Dependabot rebases trigger workflow re-runs on the same PR. (1) `gh pr merge --auto --squash` pattern-matches its stderr — only the "already enabled" idempotency string is tolerated; all other failures (auth, rate limit, branch protection misconfig) abort the step. (2) The comment step uses the canonical fail-closed dedup pattern (capture-then-test, explicit grep status via `case`) — same shape as `security.yml`'s `changes` detector. Transient `gh pr view` failures surface as `::warning::` rather than silently re-commenting

**SHA verification:**
- `step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920` → v2.20.0
- `dependabot/fetch-metadata@25dd0e34f4fe68f24cc83900b1fe3fe149efef98` → v3.1.0
- `hmarr/auto-approve-action@f0939ea97e9205ef24d872e76833fa908a770363` → v4.0.0

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

**Workflow** (`.github/workflows/security.yml`) — uses B2. Workflow Hardening patterns (concurrency, permissions, defaults, timeouts). Path filtering is split: push trigger uses `paths:` directly; PR trigger has no workflow-level path filter — instead a `changes` detection job does job-level gating (see below).

**Required-check-compatible pattern:** If `Actions security` (zizmor) or any other scanner job from security.yml is set as a GitHub required status check, the workflow CANNOT use workflow-level `paths:` filter on the PR trigger — when path filters don't match, the workflow never starts and the required check is reported as absent, blocking merge. Instead, the workflow always starts on PRs, and a `changes` job detects security-relevant files. Scanner jobs use `if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')` — running when security-relevant files changed OR when the `changes` job itself failed/cancelled (fail-closed: a broken detector cannot silently bypass required security checks). **GitHub treats skipped jobs as passing for required checks**, so the gate cleanly skips on irrelevant PRs. Push trigger retains path filters (no waste on docs-only main-branch pushes).

```yaml
name: Security

on:
  pull_request:                     # No path filter — workflow always starts on PRs
                                    # (scanner jobs skip via if: when not needed)
  push:
    branches: [main]
    paths:                          # Push trigger keeps path filter (no required-check issue)
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
      - '**/pyproject.toml'
      - '**/uv.lock'
      - '**/Cargo.lock'
      - '**/Package.resolved'

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

permissions: {}

defaults:
  run:
    shell: bash

jobs:
  # Detect whether this PR/push touches security-relevant files.
  # Scanner jobs below skip via `if:` when false. GitHub treats skipped jobs as
  # passing for required status checks — so scanners can safely be required.
  changes:
    runs-on: ubuntu-latest
    timeout-minutes: 2
    permissions:
      contents: read
    outputs:
      security: ${{ steps.filter.outputs.security }}
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: audit
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          fetch-depth: 0              # Need full history to diff against base
          persist-credentials: false
      - name: Detect security-relevant changes
        id: filter
        env:
          EVENT_NAME: ${{ github.event_name }}
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
        run: |
          set -eo pipefail
          if [ "$EVENT_NAME" = "push" ]; then
            echo "security=true" >> "$GITHUB_OUTPUT"
            exit 0
          fi
          # Fail-closed: if base SHA unavailable (fork PRs, shallow checkouts),
          # run scanners rather than silently skipping.
          if ! git cat-file -e "$BASE_SHA" 2>/dev/null; then
            echo "::warning::Base SHA $BASE_SHA not available — running scanners (fail-closed)"
            echo "security=true" >> "$GITHUB_OUTPUT"
            exit 0
          fi
          # Capture diff OUTSIDE the if-condition. Bash suspends `set -e` for commands
          # used as `if` test conditions (per `man bash`), so `if git diff ... | grep` would
          # let `git diff` failures fall through to the else branch (fail-OPEN, silent
          # scanner skip). Capturing into a variable with `||` lets us force fail-closed.
          # Pattern is a superset of on: push: paths: globs above — PR scanning is intentionally
          # broader (pyproject.toml, uv.lock, Cargo.lock, Package.resolved added) for safety.
          changed_files="$(git diff --name-only "$BASE_SHA"...HEAD)" || {
            echo "::warning::git diff failed — running scanners (fail-closed)"
            echo "security=true" >> "$GITHUB_OUTPUT"
            exit 0
          }
          # Defense-in-depth: any change under .github/ (workflows, scripts, this
          # detector itself) is always security-relevant, independent of the
          # pattern below — so a future edit that accidentally narrows the pattern
          # can't stop a workflow-touching PR from being scanned. (^|/) anchors to
          # a real path segment so e.g. src/my.github/x.js does not match.
          # Capture grep's exit status explicitly rather than testing it directly
          # in an `if` — bash suspends `set -e` for `if` conditions, so a grep
          # exit-2 (I/O/regex error) would otherwise be treated as "false" and
          # fall through to the broader pattern, defeating this block's
          # independence from it. Fail-closed on error to security=true.
          github_grep_status=0
          grep -qE '(^|/)\.github/' <<< "$changed_files" || github_grep_status=$?
          case "$github_grep_status" in
            0) echo "security=true" >> "$GITHUB_OUTPUT"; exit 0 ;;
            1) ;; # no .github/ changes — continue to broader pattern check
            *) echo "::warning::grep (.github check) failed (exit $github_grep_status) — running scanners (fail-closed)"
               echo "security=true" >> "$GITHUB_OUTPUT"; exit 0 ;;
          esac
          # Capture grep's exit status explicitly. Bash suspends `set -e` for commands
          # used as `if` test conditions (per `man bash`) — same class of bug as the
          # git diff case above. A grep exit-2 (regex error, I/O fault) would otherwise
          # be treated as "false" → security=false → silent scanner skip (fail-OPEN).
          # Flagged by Greptile as residual after the prior git-diff fix.
          grep_status=0
          grep -qE '\.(sh|js|py|yml|yaml|tf)$|\.github/|package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|go\.sum|requirements.*\.txt|Dockerfile|pyproject\.toml|uv\.lock|Cargo\.lock|Package\.resolved' <<< "$changed_files" || grep_status=$?
          case "$grep_status" in
            0) echo "security=true" >> "$GITHUB_OUTPUT" ;;
            1) echo "security=false" >> "$GITHUB_OUTPUT" ;;
            *) echo "::warning::grep failed (exit $grep_status) — running scanners (fail-closed)"
               echo "security=true" >> "$GITHUB_OUTPUT" ;;
          esac

  trivy:
    name: Dependency CVEs
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: audit
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          persist-credentials: false
      - name: Scan dependencies
        uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
        with:
          scan-type: fs
          scanners: vuln
          severity: HIGH,CRITICAL
          ignore-unfixed: true
          exit-code: 1
          skip-dirs: tests

  semgrep:
    name: Code security
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: audit
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          persist-credentials: false
      - name: Install semgrep
        run: pip install --quiet 'semgrep==1.169.0'  # Pin version — unpinned is a supply chain risk; lockstep: see issue #67
      - name: Scan for vulnerabilities
        run: semgrep scan --config p/security-audit --error --exclude tests .

  checkov:
    name: IaC misconfig
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: audit
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          persist-credentials: false
      - name: Install checkov
        run: pip install --quiet 'checkov==3.3.8'  # Pin version — unpinned is a supply chain risk; lockstep: see issue #67
      - name: Scan for misconfigurations
        run: checkov -d . --skip-path tests --quiet --compact

  zizmor:
    name: Actions security
    needs: [changes]
    if: always() && (needs.changes.outputs.security == 'true' || needs.changes.result != 'success')
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: audit
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          persist-credentials: false
      - name: Verify SHA pinning
        run: bash .github/scripts/check-pinned-uses.sh
      - name: Install zizmor
        run: pip install --quiet 'zizmor==1.26.1'  # Pin version — unpinned is a supply chain risk; lockstep: see issue #67
      - name: Scan GitHub Actions workflows
        run: zizmor --min-severity high --min-confidence high .github/workflows/

  reports:
    if: always()
    needs: [changes, trivy, semgrep, checkov, zizmor]
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
          if [[ "$TRIVY" == "failure" || "$SEMGREP" == "failure" || "$CHECKOV" == "failure" || "$ZIZMOR" == "failure" ]]; then
            echo "::error::One or more security scanners failed"
            exit 1
          fi
```

**Required file:** `.github/scripts/check-pinned-uses.sh` — see B2. Workflow Hardening for the script.

**Key points:**
- Separate from `compliance` job — compliance handles supply-chain (SBOM, licenses, dep vulns); security handles code/config scanning
- **`changes` detection job + `if:` gating pattern** — workflow always starts on PRs (no path filter), scanner jobs skip when no security-relevant files changed. GitHub treats skipped jobs as passing for required checks, so `Actions security` (zizmor) can safely be set as a required status check via branch protection. See B1b for the `gh api` command to set required checks
- Runs on push AND PRs (unlike compliance which is push-only) — catches issues before merge
- `tests/` excluded from semgrep and checkov to avoid false positives on test fixtures
- `pip install` for Python tools (semgrep, checkov, zizmor) — no additional GitHub Actions to pin/maintain
- security.yml always runs trivy on PRs and pushes; a repo with a push-only compliance trivy job accepts one duplicate push-time scan (~1 runner-minute) — no conditional skip logic to drift or bypass
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
    "suzuki-shunsuke/pinact-action@*",
    "aquasecurity/trivy-action@*",
    "dependabot/fetch-metadata@*",
    "hmarr/auto-approve-action@*"
  ]
}
EOF
```

Or via UI: **Settings → Actions → General → Actions permissions → "Allow select actions and reusable workflows"**, then add patterns.

`github_owned_allowed: true` covers actions in the `actions/*` org (`actions/checkout`, `actions/setup-node`, `actions/upload-artifact`, etc.) — but **NOT** `dependabot/*` (separate org despite both being GitHub-owned). Every third-party action — and `dependabot/*` — needs an explicit pattern. Missing a pattern produces silent `startup_failure` with no jobs and no logs (the workflow can't even download the action).

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

Dependabot config for `github-actions` ecosystem (already in Section L. Dependabot):
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

**Artifact retention:** Every `upload-artifact` step must set `retention-days` explicitly — GitHub's default is 90 days, which burns through the Free org's 500 MB / Team org's 2 GB monthly budget fast and keeps potentially sensitive scanner output around longer than necessary.

| Artifact class | Retention | Rationale |
|---|---|---|
| Coverage / test reports (PR-time) | **3–7 days** | Codecov + the PR conversation already capture results; raw artifacts only useful for debugging a recent failure |
| Security scanner summaries (PR-time) | **7–14 days** | Slightly longer for triage when the same scanner re-fires across rebases, but no value beyond the PR's lifetime |
| Scorecard SARIF / JSON | **14 days** | Only needed between weekly runs — was 30 (down 2026-05-08), shorter is fine since runs are weekly. Don't go below 14 because the scheduled run can slip |
| Release artifacts (binaries, archives) | **release workflow only — not PR runs** | Built-and-attested release artifacts attach to the GitHub Release directly; do not also upload them as workflow artifacts on PRs (doubles storage, extends retention window unnecessarily) |
| SBOM (push to main) | **30 days** | SBOM is a rolling per-commit snapshot; keep enough history to investigate "which commit introduced this dep?" without paying 90 days |

**Audit rules** (added to B0. Audit Checks):
- `grep -rE 'upload-artifact' .github/workflows/` — for each match, verify a `retention-days:` value within ~5 lines (BSD/GNU grep `-A 5`). Flag missing values and any value > 30 (force a justification).
- Specifically: `scorecard.yml` `retention-days` ≤ 14, coverage upload steps ≤ 7, security uploads ≤ 14. Helmet's own `scorecard.yml` was bumped from 30 → 14 in this PR; cascading to fleet repos happens at the next per-repo helmet run.

**Relationship with local scanning:**
| Scanner | Local (seatbelt/hooks) | CI (security.yml) | CI (compliance job) |
|---------|----------------------|--------------------|--------------------|
| semgrep | Staged files, `p/security-audit` | Full repo, `p/security-audit` | — |
| checkov | Staged IaC files, BLOCK | Full repo, BLOCK | — |
| zizmor | Staged workflows, WARN | All workflows, BLOCK | — |
| trivy | Staged lock files, WARN | — | Full repo, BLOCK (HIGH+CRITICAL) |
| gitleaks | Staged changes, BLOCK | — | — (GitGuardian covers CI) |

#### O. CodeScene Behavioral Analysis (all repos with CodeScene App)

CodeScene is a GitHub App that provides behavioral code analysis — code health scoring, complexity hotspots, and change coupling on PRs. Unlike static analysis (ESLint, Semgrep), it tracks how code *changes over time*.

**Prerequisites:** Install the [CodeScene GitHub App](https://github.com/marketplace/codescene) on the org/repo.

**Config** (`.codescene/custom-quality-gates.json`):

Generate the config based on the detected language and framework. The config must be **framework-aware** — different frameworks have different test file patterns and exclusions.

<details><summary>TypeScript/JavaScript — Next.js / React</summary>

```json
{
  "quality_gates": {
    "code_health_gate": {
      "enabled": true,
      "policy": "no_deterioration",
      "description": "Block PRs that introduce code health decline"
    },
    "complexity_gate": {
      "enabled": true,
      "max_increase": 5,
      "description": "Flag PRs that increase cyclomatic complexity significantly"
    }
  },
  "analysis": {
    "exclude_patterns": [
      "node_modules/**",
      ".next/**",
      "dist/**",
      "coverage/**",
      "public/**",
      "**/*.d.ts"
    ],
    "language_specific": {
      "typescript": {
        "file_extensions": [".ts", ".tsx", ".js", ".jsx"],
        "test_patterns": ["__tests__/**", "**/*.test.ts", "**/*.test.tsx", "**/*.test.js", "**/*.test.jsx", "**/*.spec.ts", "**/*.spec.tsx", "**/*.spec.js", "**/*.spec.jsx"]
      }
    }
  }
}
```

</details>

<details><summary>TypeScript/JavaScript — Express / Hono / Fastify / Generic</summary>

```json
{
  "quality_gates": {
    "code_health_gate": {
      "enabled": true,
      "policy": "no_deterioration",
      "description": "Block PRs that introduce code health decline"
    },
    "complexity_gate": {
      "enabled": true,
      "max_increase": 5,
      "description": "Flag PRs that increase cyclomatic complexity significantly"
    }
  },
  "analysis": {
    "exclude_patterns": [
      "node_modules/**",
      "dist/**",
      "coverage/**",
      "**/*.d.ts"
    ],
    "language_specific": {
      "javascript": {
        "file_extensions": [".ts", ".js"],
        "test_patterns": ["__tests__/**", "**/*.test.ts", "**/*.test.js", "**/*.spec.ts", "**/*.spec.js"]
      }
    }
  }
}
```

</details>

<details><summary>Python</summary>

```json
{
  "quality_gates": {
    "code_health_gate": {
      "enabled": true,
      "policy": "no_deterioration"
    },
    "complexity_gate": {
      "enabled": true,
      "max_increase": 5
    }
  },
  "analysis": {
    "exclude_patterns": [
      "__pycache__/**",
      ".venv/**",
      "venv/**",
      "dist/**",
      "*.egg-info/**",
      "htmlcov/**"
    ],
    "language_specific": {
      "python": {
        "file_extensions": [".py"],
        "test_patterns": ["tests/**", "test_*.py", "*_test.py"]
      }
    }
  }
}
```

</details>

<details><summary>Go</summary>

```json
{
  "quality_gates": {
    "code_health_gate": {
      "enabled": true,
      "policy": "no_deterioration"
    },
    "complexity_gate": {
      "enabled": true,
      "max_increase": 5
    }
  },
  "analysis": {
    "exclude_patterns": [
      "vendor/**"
    ],
    "language_specific": {
      "go": {
        "file_extensions": [".go"],
        "test_patterns": ["**/*_test.go"]
      }
    }
  }
}
```

</details>

<details><summary>Rust</summary>

```json
{
  "quality_gates": {
    "code_health_gate": {
      "enabled": true,
      "policy": "no_deterioration"
    },
    "complexity_gate": {
      "enabled": true,
      "max_increase": 5
    }
  },
  "analysis": {
    "exclude_patterns": [
      "target/**"
    ],
    "language_specific": {
      "rust": {
        "file_extensions": [".rs"],
        "test_patterns": ["tests/**"]
      }
    }
  }
}
```

</details>

<details><summary>Swift</summary>

```json
{
  "quality_gates": {
    "code_health_gate": {
      "enabled": true,
      "policy": "no_deterioration"
    },
    "complexity_gate": {
      "enabled": true,
      "max_increase": 5
    }
  },
  "analysis": {
    "exclude_patterns": [
      ".build/**",
      "DerivedData/**",
      "*.xcodeproj/**"
    ],
    "language_specific": {
      "swift": {
        "file_extensions": [".swift"],
        "test_patterns": ["Tests/**", "**/*Tests.swift"]
      }
    }
  }
}
```

</details>

**Key rules for config generation:**

1. **Never exclude authored config files.** Do NOT add `**/*.config.*` to exclude patterns — config files like `next.config.ts`, `tailwind.config.ts`, and `vitest.config.ts` contain real logic that should be analyzed. Only exclude truly generated artifacts (build output, type declarations, dependencies).
2. **Match test patterns to framework.** React/Next.js projects need `.tsx` test patterns alongside `.ts`. Go uses `*_test.go` (not a separate directory). Rust integration tests go in `tests/` but unit tests are inline `#[cfg(test)]` modules.
3. **Include `public/**` for web projects** in exclude patterns — static assets (images, fonts, icons) should not be analyzed for code health.
4. **`no_deterioration` policy** means CodeScene blocks PRs that make already-problematic code worse, but allows PRs that touch healthy code. This is less disruptive than absolute thresholds.
5. **`max_increase: 5`** is the default complexity cap. Raise to 10 for repos with known complex legacy code.

**Setup steps:**
1. Install [CodeScene GitHub App](https://github.com/marketplace/codescene) on the org
2. Grant access to the target repo
3. Create `.codescene/custom-quality-gates.json` using the template above (select by detected framework)
4. CodeScene automatically reads the config and enforces gates on PRs

**N/A condition:** If the CodeScene App is not installed on the org, mark as N/A in the audit.

#### P. Admin Bypass Audit (all repos with `enforce_admins: false`)

Detects commits pushed directly to `main` without a PR — i.e., admin bypasses of the required-status-checks gate. Creates a GitHub Issue with label `admin-bypass` and emits a workflow warning annotation.

**Why this exists:** With `enforce_admins: false` (solo-dev default), GitHub branch protection does NOT apply to repo admins. Any "BLOCK" gate enforced by branch protection is advisory for admins (direct push + `gh pr merge --admin` both bypass). This workflow makes those bypasses visible and auditable after the fact, so the honest "BLOCK vs advisory" labeling can be operationalized instead of left as documentation.

**Workflow** (`.github/workflows/bypass-audit.yml`):

```yaml
name: Admin Bypass Audit

# helmet-pipeline: v<pipeline-version>   # ← COPY helmet's OWN canonical bypass-audit.yml
                                        #    VERBATIM. This excerpt is ILLUSTRATIVE — the file
                                        #    in helmet's repo is the source of truth (it is not
                                        #    drift-checked here). Bump the stamp ONLY when the
                                        #    template changes — NOT the plugin version, NOT every
                                        #    release. check-pipeline-drift.sh reads helmet's
                                        #    canonical stamp as truth; see ADR-0001.

on:
  push:
    branches: [main]

permissions: {}

concurrency:
  group: bypass-audit-${{ github.sha }}
  cancel-in-progress: false

defaults:
  run:
    shell: bash

jobs:
  audit:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read       # required by /commits/{sha}/pulls on PRIVATE repos
      issues: write        # create audit issues
      pull-requests: read  # look up PR for commit SHA
    steps:
      - name: Harden Runner
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: audit
      - name: Detect direct-push bypass
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          ACTOR: ${{ github.actor }}
          REPO: ${{ github.repository }}
          RUN_ID: ${{ github.run_id }}
          HEAD_SHA: ${{ github.sha }}
          # Do NOT pass toJSON(github.event.commits) via env — a large push (up to 2048
          # commits, each with message + file lists + URLs) can exceed the runner's
          # env/ARG_MAX limit and make the step fail to exec before any audit logic runs,
          # silently suppressing the bypass. Read from $GITHUB_EVENT_PATH (below) instead.
        run: |
          set -e   # NOT -euo pipefail; the pipes below are pipefail-safe (no early-closing head)
          # IDENTITY-based skip ONLY — automated actors. Never skip on commit-message
          # content ([skip ci]/chore(release)): attacker-controllable. Bot release commits
          # are already skipped here by actor identity.
          if [[ "$ACTOR" == *"[bot]"* ]] || [[ "$ACTOR" == "github-actions" ]]; then
            echo "Skipping audit — automated actor: $ACTOR"; exit 0
          fi
          # Audit EVERY commit added by this push, not just HEAD: a multi-commit direct push
          # whose HEAD is PR-associated would otherwise hide earlier commits. Read the commit
          # list from $GITHUB_EVENT_PATH (the event JSON on disk) with jq — never the env var.
          # FAIL-CLOSED if the payload is unreadable / not JSON / .commits is not an array
          # (INDETERMINATE) so a multi-commit bypass can't slip through a silent HEAD-only
          # fallback; a valid but EMPTY list legitimately falls back to HEAD.
          if ! COMMIT_IDS=$(jq -r 'if (.commits|type)=="array" then (.commits[].id // empty) else error("commits not an array") end' "$GITHUB_EVENT_PATH" 2>/dev/null); then
            echo "::error::Could not read a valid .commits array from \$GITHUB_EVENT_PATH — indeterminate; failing the run."; exit 1
          fi
          mapfile -t ALL_SHAS < <(printf '%s' "$COMMIT_IDS")
          [ "${#ALL_SHAS[@]}" -eq 0 ] && ALL_SHAS=("$HEAD_SHA")
          # Cap PR-lookup work at MAX_AUDIT=256; on overflow FAIL the run (durable red-X) so
          # the unaudited remainder is never silently passed. Bypassing commits accumulate
          # into ONE summary issue (no per-commit issue spam / content-creation rate-limit).
          MAX_AUDIT=256; AUDIT_FAILED=0; BYPASS_COUNT=0
          SHAS=("${ALL_SHAS[@]:0:$MAX_AUDIT}")
          if [ "${#ALL_SHAS[@]}" -gt "$MAX_AUDIT" ]; then
            echo "::error::Push has ${#ALL_SHAS[@]} commits (> $MAX_AUDIT) — audited the first $MAX_AUDIT and failing the run; review the remainder manually."
            AUDIT_FAILED=1
          fi
          for COMMIT_SHA in "${SHAS[@]}"; do
            # Distinguish "API OK, no merged-into-main PR" (bypass) from "API failed/garbled"
            # (INDETERMINATE → AUDIT_FAILED=1, keep auditing). Capture stderr SEPARATELY (not
            # 2>&1) so a benign warning can't corrupt the body into a false indeterminate.
            PRS_ERR=$(mktemp)
            if ! PRS_JSON=$(gh api "repos/$REPO/commits/$COMMIT_SHA/pulls" 2>"$PRS_ERR"); then
              echo "::error::gh api failed for $COMMIT_SHA — indeterminate"; AUDIT_FAILED=1; rm -f "$PRS_ERR"; continue
            fi
            rm -f "$PRS_ERR"
            # Count ONLY PRs actually MERGED INTO main (merged_at != null AND base.ref == "main"):
            # /commits/{sha}/pulls also returns PRs that merely CONTAIN the commit, so a commit
            # living on an unmerged/other-branch PR must not read as "no bypass".
            if ! MERGED_PRS=$(printf '%s' "$PRS_JSON" | jq -e 'if type=="array" then [.[]|select(.merged_at!=null and .base.ref=="main")] else error("not array") end' 2>/dev/null); then
              echo "::error::unexpected PR-list response for $COMMIT_SHA — indeterminate"; AUDIT_FAILED=1; continue
            fi
            [ "$(printf '%s' "$MERGED_PRS" | jq 'length')" != "0" ] && continue
            # No merged-into-main PR → direct push = bypass. Accumulate a (sanitized) table row.
            echo "::warning::Admin bypass: direct push to main by $ACTOR (commit ${COMMIT_SHA})"
            BYPASS_COUNT=$((BYPASS_COUNT+1))
            # ... (sanitize subject for the Markdown cell, build the row — see full template)
          done
          # NO dedup on purpose: issue title/body are MUTABLE (anyone with issues:write, incl.
          # via editing a bot-authored issue) → unsafe as a suppression primitive; a duplicate
          # on a rare re-run is harmless. See ADR-0001.
          # If BYPASS_COUNT>0: ensure the admin-bypass label, then file ONE labeled summary
          # issue listing every bypassing commit. If AUDIT_FAILED=1: exit 1 (durable red-X).
          # ... (label + body composition + gh issue create, see full template)
```

See `.github/workflows/bypass-audit.yml` in the helmet repo for the full template (issue body composition, Markdown-cell subject sanitization, label fallback).

**Detection logic:**
1. If actor is a bot (`[bot]` suffix or `github-actions`) → skip. **IDENTITY-based skip only** — never skip on commit-message content (`[skip ci]` / `chore(release)` are attacker-controllable; legitimate release commits are authored by a bot actor and are already skipped by this rule).
2. Read the pushed commit list from `$GITHUB_EVENT_PATH` (the event JSON on disk) with `jq` — **never** `toJSON(github.event.commits)` through an env var (a large push can exceed the runner env/ARG_MAX limit and make the step fail to exec before any audit logic runs). **Fail the run** if the payload is unreadable / not JSON / `.commits` is not an array (indeterminate); a valid-but-empty list falls back to HEAD.
3. **Audit every pushed commit, not just HEAD** (a multi-commit direct push whose HEAD is PR-associated would otherwise hide earlier commits). Capped at `MAX_AUDIT=256`; on overflow, **fail the run** so the unaudited remainder isn't silently passed. For each commit, look up `/commits/{sha}/pulls`.
4. **If `gh api` fails OR returns a non-array → indeterminate → fail the run** (durable red-X in Actions history). Capture stderr separately (not `2>&1`) so a benign warning can't manufacture a false indeterminate. Never silently skip, never coerce a garbled response into a false-positive bypass issue.
5. Count **only PRs MERGED INTO main** (`merged_at != null` AND `base.ref == "main"`) — `/commits/{sha}/pulls` also returns PRs that merely *contain* the commit, so a commit living on an unmerged/other-branch PR must not read as "no bypass".
6. Commits with no merged-into-main PR → direct-push bypass → accumulate into **ONE summary issue** (no per-commit issue spam / content-creation rate-limit). **No dedup** (mutable issue metadata is an unsafe suppression primitive — see below / ADR-0001).

**Known limitations (accepted):**
- `gh pr merge --admin` associates the merge commit with a PR, so this won't flag admin-merges — that is pr-grind's authorized path, logged to `.claude/bypass-log.jsonl`.
- A native CI-skip marker (`[skip ci]`, `[skip actions]`, …) in the head commit suppresses the whole workflow run. **Not an audit gap:** for org-owned repos the **GitHub org audit log** (`protected_branch.policy_override` events) is the authoritative, tamper-proof trail — this workflow is a convenience layer. A post-hoc "sweep" was evaluated and rejected (a workflow can't distinguish legitimate automation from a forged bypass after the fact).
- Detective, not preventive: runs after the push lands.
- **No dedup.** Issue title/body are mutable (anyone with `issues:write` can pre-create or edit a matching issue — even an author filter is defeated by editing a bot-authored issue), so a title/SHA dedup is an insider-editable suppression primitive. A duplicate issue on a rare manual re-run is the safer trade. See ADR-0001.

**Key points:**
- **Creates a permanent audit trail** — GitHub Issues are durable, searchable, and trigger notifications. Step-summary-only alerts get forgotten.
- **Label `admin-bypass`** is auto-created on first run (idempotent). Enables filtering: `gh issue list --label admin-bypass`.
- **Never interpolates `${{ github.event.* }}` into shell** (workflow injection prevention): the actor name is passed via the `env:` block and quoted; the commit list and messages are read from `$GITHUB_EVENT_PATH` with `jq` (file data, never a shell-expanded expression).
- **Honest about scope** — see Key Decisions section on what this does and doesn't catch.

**N/A condition:** If `enforce_admins: true` on the repo's branch protection, this workflow provides no value (admins can't bypass in the first place). Safe to omit.

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

### B4b. Retrofit Required Checks (existing helmet-onboarded repos)

Pure branch-protection update — no code change, no PR. Use when an existing
repo deployed helmet's `security.yml` but the scanners aren't required-checks.
Idempotent: re-adds existing required checks unchanged.

**Requires `bash`** (uses arrays — scanner names contain spaces, so POSIX
word-splitting won't work). macOS ships bash 3.2+, sufficient.

```bash
#!/usr/bin/env bash
set -u

# Edit this list per use. Slugs are "OWNER/repo".
REPOS=("OWNER/repo1" "OWNER/repo2")

# Scanner names that helmet's security.yml emits (job-level skip pattern means
# these always report a result on every PR — pass or skip-counted-as-pass).
SCANNERS=("Actions security" "Code security" "Dependency CVEs" "IaC misconfig")

for full in "${REPOS[@]}"; do
  echo "── $full ──"
  DEFAULT_BRANCH=$(gh api "repos/$full" --jq '.default_branch' 2>/dev/null) || {
    echo "  ❌ cannot read repo metadata"; continue
  }
  if [ -z "$DEFAULT_BRANCH" ]; then
    echo "  ❌ no default branch resolved"; continue
  fi

  # Single fetch — extract both fields locally. Avoids a second round-trip
  # and the TOCTOU window where strict and contexts could reflect different
  # protection states if the policy is mutated between two API calls.
  PROT_RAW=$(gh api "repos/$full/branches/$DEFAULT_BRANCH/protection/required_status_checks" 2>/dev/null)
  if [ -z "$PROT_RAW" ]; then
    echo "  ❌ no branch protection on $DEFAULT_BRANCH (set up via B1b first)"; continue
  fi
  STRICT_CUR=$(echo "$PROT_RAW" | jq -c '.strict')
  CURRENT=$(echo "$PROT_RAW" | jq -c '.contexts // []')

  # Discover scanners that have actually run on the repo recently — only add
  # ones with a recorded run, otherwise GitHub rejects them as required checks.
  RECENT_SHA=$(gh api "repos/$full/commits" --jq '.[0].sha' 2>/dev/null)
  AVAILABLE='[]'
  if [ -n "$RECENT_SHA" ]; then
    # --paginate is required: the default `/check-runs` page size is 30, so
    # a commit with many CI jobs (per-OS test matrix, multiple bots) could
    # silently drop a scanner from AVAILABLE. Aggregate all pages, dedup.
    AVAILABLE_RAW=$(gh api --paginate "repos/$full/commits/$RECENT_SHA/check-runs" \
      --jq '.check_runs[].name' 2>/dev/null \
      | jq -Rs 'split("\n") | map(select(. != "")) | unique')
    AVAILABLE=${AVAILABLE_RAW:-"[]"}
  fi

  # Merge: keep current + add scanners that exist in AVAILABLE
  MERGED=$(jq -nc --argjson current "$CURRENT" --argjson available "$AVAILABLE" \
    --argjson scanners "$(printf '%s\n' "${SCANNERS[@]}" | jq -Rcs 'split("\n") | map(select(. != ""))')" '
    ($current + ($scanners | map(select(. as $s | $available | index($s)))) ) | unique')

  echo "  strict (preserved): $STRICT_CUR"
  echo "  current contexts:   $CURRENT"
  echo "  merged contexts:    $MERGED"

  # Apply (PATCH preserves other branch-protection settings; we propagate the
  # current strict value so an intentional `strict: false` repo isn't silently
  # changed). Echo a per-repo ❌ on failure so fleet runs surface errors
  # instead of relying on stderr being noticed.
  if ! jq -nc --argjson contexts "$MERGED" --argjson strict "$STRICT_CUR" \
        '{strict: $strict, contexts: $contexts}' \
       | gh api "repos/$full/branches/$DEFAULT_BRANCH/protection/required_status_checks" \
           -X PATCH --input - --jq '{strict, contexts}'; then
    echo "  ❌ PATCH failed for $full"
  fi
done
```

**Why PATCH not PUT:** PATCH on `/required_status_checks` only updates that
sub-resource. PUT on `/protection` would require re-specifying every other
branch-protection field (enforce_admins, restrictions, etc.) — easy to miss
one and accidentally regress. The PATCH payload still must include all
sub-resource fields you want set; that's why we read and propagate `strict`
explicitly (default-overwriting it to `true` would flip a repo intentionally
configured `strict: false`).

**Verify across the fleet:**
```bash
for full in "${REPOS[@]}"; do
  printf "%-40s " "$full"
  default_b=$(gh api "repos/$full" --jq '.default_branch' 2>/dev/null)
  if [ -z "$default_b" ]; then
    echo "(cannot read repo metadata)"
    continue
  fi
  # Print both: scanners_ok boolean (the actual policy compliance signal)
  # AND the contexts list (for context). Without the boolean, a long
  # contexts string can hide a missing scanner.
  gh api "repos/$full/branches/$default_b/protection/required_status_checks" \
    --jq '"scanners_ok=" + ((["Actions security","Code security","Dependency CVEs","IaC misconfig"] - .contexts | length == 0) | tostring) + "  contexts=[" + (.contexts | join(", ")) + "]"' \
    2>/dev/null || echo "(no protection)"
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
  [ -f "$dir/commitlint.config.mjs" ] && commitlint_cfg="✅"
  scorecard="❌"; security_md="❌"; dependabot="❌"; dep_automerge="❌"; scanners_req="❌"
  [ -f "$dir/.github/workflows/scorecard.yml" ] && scorecard="✅"
  [ -f "$dir/SECURITY.md" ] && security_md="✅"
  [ -f "$dir/.github/dependabot.yml" ] && dependabot="✅"
  [ -f "$dir/.github/workflows/dependabot-auto-merge.yml" ] && dep_automerge="✅"
  # Check whether all 4 scanners are in required-status-checks (best effort —
  # remote API call; skip silently if no remote or no protection).
  if remote_full=$(git -C "$dir" remote get-url origin 2>/dev/null | sed 's|https://github.com/||;s|\.git$||') \
     && [ -n "$remote_full" ]; then
    default_b=$(gh api "repos/$remote_full" --jq '.default_branch' 2>/dev/null)
    if [ -n "$default_b" ]; then
      ctx=$(gh api "repos/$remote_full/branches/$default_b/protection/required_status_checks" \
        --jq '.contexts // []' 2>/dev/null)
      # Set-difference: empty result means every required scanner is present.
      # Same idiom as B1b's audit checklist row — kept symmetric so that the
      # round-2 buggy variant (`(index() and ...) != null`, which returned
      # true for ALL inputs) doesn't get recreated by copy-paste.
      if [ -n "$ctx" ] && echo "$ctx" | jq -e '
        ["Actions security","Code security","Dependency CVEs","IaC misconfig"] - . | length == 0
      ' >/dev/null 2>&1; then
        scanners_req="✅"
      fi
    fi
  fi
  echo "$repo: tests=$tests codecov=$codecov pinact=$pinact sbom=$sbom license=$license vuln=$vuln LICENSE=$lic_file harden=$harden semrel=$semrel commitlint=$commitlint_cfg scorecard=$scorecard SECURITY=$security_md dependabot=$dependabot dep_automerge=$dep_automerge scanners_req=$scanners_req"
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
| `startup_failure` on all workflows (0s, no logs) | `allowed_actions` set to `local_only` — blocks all external actions | Set `allowed_actions: selected` via API (see Section N. Security Scanning Backstop) with `github_owned_allowed: true` + third-party patterns |
| `startup_failure` on a SPECIFIC workflow (other workflows OK, no jobs/logs on the failing one) | A specific action `uses:` reference is not in `selected-actions.patterns_allowed`. Easy miss: `dependabot/*` is a separate org and is **NOT** covered by `github_owned_allowed: true` despite being GitHub-owned. Same for `aquasecurity/trivy-action` if Trivy is enabled in security.yml | `gh api repos/OWNER/REPO/actions/permissions/selected-actions --jq .patterns_allowed` to see current list, then PUT a new list including the missing pattern (e.g., `dependabot/fetch-metadata@*`, `aquasecurity/trivy-action@*`). Update the canonical allowlist in B1b above when adding a new third-party action to any helmet workflow |
| 409 Conflict on `repos/OWNER/REPO/actions/permissions/selected-actions` | Org-level Actions permissions override repo-level — repo API rejects changes when org controls the setting | Use `orgs/ORG/actions/permissions/selected-actions` instead. Check org-level first: `gh api orgs/ORG/actions/permissions/selected-actions` |
| Attest job skipped on workflow rerun after partial failure | `BEFORE_TAG == AFTER_TAG` because semantic-release already created the tag on the first run | Add rerun recovery: check if latest tag points to HEAD via `git rev-list -n 1 "$AFTER_TAG"` (see Section D. Release Archive Attestation template) |
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
- **Attestations require public repos OR Enterprise Cloud for private repos** — `attest-build-provenance` is available on public repos (any plan) or private/internal repos on GitHub Enterprise Cloud. Free/Pro/**Team** private repos fail with "Feature not available for the org" — use Cosign keyless signing only. Add GitHub-native attestations later if the repo goes public or plan is upgraded to Enterprise Cloud
- **Environment deployment protection rules require Team plan or higher for private repos** — `environment:` blocks in workflows can scope secrets on any plan, but required reviewers and wait timers only work on public repos (any plan) or private repos on Team/Enterprise plans. Free plan private repos cannot use them — use branch protection required checks as the merge gate instead
- **Path-filtered workflows cannot be required checks** — when a workflow's `on: pull_request: paths:` filter doesn't match, the workflow never starts and GitHub reports the required check as absent, blocking merge. Use the `changes` detection job pattern in security.yml: workflow always starts, scanner jobs skip via `if:` when no relevant files changed. GitHub treats skipped jobs as passing for required checks
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
- **Workflow hardening patterns mandatory on all workflows (added 2026-03-27)** — `paths-ignore` (skip docs), `concurrency` (cancel stale), `permissions` (top-level least-privilege), `defaults.run.shell: bash` (explicit), `timeout-minutes` (every job). Security workflow uses `paths` (positive match) instead of `paths-ignore`. **`scorecard.yml` MUST NOT declare top-level `defaults:` or `env:` blocks** — `ossf/scorecard-action`'s publish verification rejects them with `workflow contains global env vars or defaults` (HTTP 400), failing the job even though scoring succeeds. The B0 audit table's `defaults.run.shell: bash` rule explicitly carves out this file; do not "fix" the missing `defaults:` block on scorecard.yml. Ref: https://github.com/ossf/scorecard-action#workflow-restrictions
- **`pull_request` over `pull_request_target`** — never run untrusted PR code with write permissions. All workflows use `pull_request`
- **External `check-pinned-uses.sh` over inline grep** — handles quoted `uses:` values, reusable across repos, easier to test. Deploy to `.github/scripts/`. Exempt local refs (`./`) and `docker://`
- **`reports` summary job in security.yml** — `if: always()` with `needs:` on all scanners; writes markdown table to `$GITHUB_STEP_SUMMARY` for PR-visible results
- **Security scanners as required checks (added 2026-05-07)** — helmet's default branch-protection policy now requires `Actions security` (zizmor), `Code security` (semgrep), `Dependency CVEs` (trivy), and `IaC misconfig` (checkov). Previously they ran on PRs as advisory. The shift addresses two real bypass risks: (1) Dependabot bumps of vulnerable npm/pip deps could merge on `test` pass alone — Trivy flagged the CVE on the PR but didn't block merge. (2) Manual click of "Enable auto-merge" on a Dependabot PR with a failing scanner would silently merge once required checks (only `test`) passed. Helmet's job-level `if:` skip pattern in `security.yml` means scanners always report a result (pass or skip-counted-as-pass) on every PR, so requiring them does not introduce false-positive blockage on PRs that don't touch security-relevant files. The retrofit (B4b) is idempotent on `/required_status_checks` (PATCH not PUT) so re-running is safe. External AI reviewers (CodeRabbit, Greptile, cubic, CodeScene) stay advisory — their availability is third-party and required-check on them would hang PRs when the service is slow
- **Dependabot `commit-message.prefix` and `labels`** — `chore(actions)` prefix for conventional commits; `dependencies` + `github-actions` labels for filtering. Dependabot reads `@<sha> # vX.Y.Z` inline comments and updates both SHA + comment
- **Dependabot auto-merge is per-repo opt-in via `vars.DEPENDABOT_AUTO_APPROVE` (refined 2026-05-08)** — Dependabot's PR body already contains release notes + compatibility score; for patch and minor bumps, an LLM review adds little signal. The `dependabot-auto-merge.yml` workflow uses `dependabot/fetch-metadata` to gate by `update-type` and only approves + auto-merges patch/safe-minor bumps on repos that opt in (set `vars.DEPENDABOT_AUTO_APPROVE = "true"`). On opted-out repos (typical for enterprise orgs that disable GitHub Actions PR approval at the enterprise level) the workflow runs in annotate-only mode — comment fires for both safe-and-manual ("merge by hand") and unsafe ("major / production-direct minor") cases, but no failed approve step. Workflow uses `pull_request` (not `pull_request_target`) with explicit `permissions:` to override Dependabot's default read-only `GITHUB_TOKEN` — preserves helmet's "never `pull_request_target`" rule. `gh pr merge --auto` only enqueues; the actual merge waits for branch-protection checks, so no PAT is needed. **Earlier 2026-05-08 design assumed `bypass_pull_request_allowances.apps:["dependabot"]` could be a fallback for enterprise-restricted repos — empirically this does NOT work because GitHub auto-merge evaluates branch protection from the perspective of the actor that *enabled* auto-merge (`github-actions[bot]` from the workflow), not the PR author. The bypass list contains `dependabot`, never matches, and PRs sit BLOCKED indefinitely. Confirmed on Dive-And-Dev/perch#38. The `vars.DEPENDABOT_AUTO_APPROVE` opt-out is the honest replacement for that gap**
- **Idempotency on Dependabot re-runs (added 2026-05-07, post-Greptile fix)** — Dependabot rebases re-trigger the workflow on the same PR. Two paths in helmet-managed code need explicit idempotency guards: (1) `gh pr merge --auto --squash` exits non-zero with "auto merge is already enabled" once auto-merge has been enabled by a prior run — needs stderr capture and substring pattern-match: tolerate the specific idempotency string only, surface every other failure (auth, rate limit, branch protection misconfig). A naive `|| echo` mask would silently swallow real errors. (2) `gh pr comment` always creates a new comment, so the comment step needs a grep-based check against existing `github-actions[bot]` comments to avoid duplicate notifications. The comment step uses two distinct hidden markers — `<!-- dependabot-auto-merge: annotate-only -->` (safe bump on opted-out repo) and `<!-- dependabot-auto-merge: manual-review-required -->` (unsafe bump on any tier) — so dedup is correctly scoped per case. The approve step (`hmarr/auto-approve-action`) handles its own idempotency natively — the action checks for an existing approving review from the same actor on the current head SHA and skips if one exists, so no in-workflow guard needed. The original PR (#23) shipped without any of these idempotency guards — pr-grind declared clean based on Greptile's check-pass status without reading the actual review body, which contained P1 findings. The lesson is process-level: **pr-grind must read AI-reviewer comment bodies, not just check-status flips**. Greptile posts as issue comments (not inline review threads), so a `reviewThreads` GraphQL filter misses everything; use `gh pr view --comments` plus `gh api repos/.../pulls/N/reviews` to get full coverage
- **No OIDC needed yet (no CI-based deployment)** — all deployments use git-push → platform auto-deploy (Vercel/Netlify), so CI never touches deployment credentials. Existing `id-token: write` is only for Scorecard (OpenSSF API) and Cosign (keyless signing in forge). When CI-based deployment is added, switch to OIDC with trust policy locked to specific repo + environment (no wildcards). Never use static cloud credentials (AWS keys, GCP service accounts) as GitHub secrets for deployment
- **Workflow changes are a high-risk path** — `.github/workflows/**` modifications get explicit SHA pin verification + zizmor scan in the `zizmor` job of `security.yml`. AI-generated workflows frequently use tag refs (`@v4`) instead of full SHA pins; the grep-based verify step catches this before merge. GitHub natively supports "Require actions to be pinned to a full-length commit SHA" at org/repo level — enable this in repo settings for belt-and-suspenders enforcement alongside CI. Added 2026-03-27
- **Squash-only merges** — `allow_squash_merge: true`, merge commits and rebase disabled. Clean single-commit PRs, linear history. `allow_update_branch: true` suggests keeping PRs current. `delete_branch_on_merge: true` auto-cleans merged branches
- **Auto-merge enabled + branch protection required** — lets Dependabot PRs merge automatically after CI passes without manual intervention. MUST be paired with branch protection requiring status checks — without it, auto-merge merges immediately with no CI gate. `enforce_admins: false` for solo dev escape hatch; `strict: true` requires branch to be up-to-date before merge
- **Actions permissions must be `selected` not `local_only`** — `allowed_actions: "local_only"` silently causes `startup_failure` on all workflows using external actions (no logs, no jobs, 0s duration). Configure `allowed_actions: selected` with `github_owned_allowed: true` + explicit third-party patterns BEFORE deploying workflows. Verify with `gh api repos/OWNER/REPO/actions/permissions`. Added 2026-03-27
- **Security workflow uses `paths` only, no `paths-ignore`** — combining `paths` + `paths-ignore` on the same event trigger may cause GitHub to reject the workflow with a generic "workflow file issue" error. Since positive `paths` matching already excludes unmatched extensions (like `.md`), `paths-ignore` is redundant. Added 2026-03-27
- **Reports job uses env vars for `${{ needs.*.result }}`** — zizmor flags inline `${{ needs.job.result }}` expressions as template-injection (low confidence, false positive — values are GitHub-internal). Using `env:` block satisfies the audit with zero behavioral change. Added 2026-03-27

---

# Phase C: CLAUDE.md Generation


Generate a `.claude/CLAUDE.md` file so every new Claude Code session starts with full project context. Runs automatically after Phase B completes during onboarding, or standalone when refreshing a stale CLAUDE.md.

## When to Use

- After Phase A + B onboarding completes (auto-triggered)
- Repo has no `.claude/CLAUDE.md`
- Existing CLAUDE.md is boilerplate (only version sync or empty)
- User asks to refresh CLAUDE.md after significant changes

## C1. Analysis

Gather project metadata from what already exists. Do NOT ask the user — everything is derivable.

### C1a. Tech Stack

Read config files to determine languages, frameworks, and tooling:

| Source | Extract |
|--------|---------|
| `package.json` | Language (TS/JS), dependencies, scripts (`test`, `build`, `lint`, `dev`, `start`) |
| `go.mod` | Language (Go), module path |
| `Cargo.toml` | Language (Rust), crate name, dependencies |
| `pyproject.toml` / `setup.py` / `requirements.txt` | Language (Python), framework, dependencies |
| `Package.swift` / `*.xcodeproj` | Language (Swift), platform targets |
| `*.sln` / `*.csproj` | Language (C#), .NET version |
| `build.gradle.kts` / `pom.xml` | Language (Kotlin/Java), framework |
| `.claude-plugin/plugin.json` | Claude Code plugin (name, version, description) |

### C1b. Project Structure

Map the top-level directory tree. For each directory, note its purpose:

```bash
ls -1 <repo-root>
```

Count key assets where relevant (e.g., number of skills, agents, hooks, tests, workflows).

### C1c. Commands

Extract runnable commands from:
- `package.json` scripts (npm/yarn/pnpm)
- `Makefile` targets
- `Taskfile.yml` tasks
- `scripts/` directory (executable shell/JS/Python scripts)
- `go generate` directives
- `cargo` subcommands in CI

### C1d. CI Configuration

Read `.github/workflows/*.yml` to document:
- Workflow names and triggers
- What each workflow does (one line)
- Required secrets or environment variables

### C1e. Conventions

Detect from existing files:
- Commit format (commitlint config, `.releaserc.json`)
- Linting (ESLint, Prettier, ShellCheck, gofmt, rustfmt, etc.)
- Test patterns (test file location, naming, framework)
- Version management (`.version-bump.json`, semantic-release)
- Hook enforcement (hooks.json, gate scripts)

### C1f. Gotchas

Identify non-obvious patterns that would trip up a new session:
- Gate scripts that block commits/PRs (and their escape hatches)
- Files that must stay in sync (version manifests)
- Environment variables required for local dev
- Private repo constraints (no external collaborators, local tooling preference)

## C2. Generation

Write `.claude/CLAUDE.md` with this structure:

```markdown
# <Project Name>

<One-line description from package.json, plugin.json, Cargo.toml, etc.>

## Tech Stack

- **Language:** <detected languages>
- **Framework:** <if applicable>
- **Runtime:** <Node, Deno, Bun, Go, etc.>
- **Package manager:** <npm, pnpm, yarn, cargo, pip, etc.>
- **Linting:** <detected linters>
- **Commit format:** <conventional commits, etc.>

## Project Structure

\```
<directory tree with counts and purposes>
\```

## Commands

| Command | What it does |
|---------|-------------|
| `npm test` | ... |
| `npm run build` | ... |
| ... | ... |

## CI Workflows

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| ... | ... | ... |

## Conventions

- <bullet list of detected conventions>

## Version Sync (if applicable)

<version management details if .version-bump.json or similar exists>
```

### Generation Rules

- **Only include sections with content.** Skip "Commands" if there are no scripts. Skip "CI Workflows" if there are no workflow files.
- **If property tests are present** (detected as `tests/test_properties*.py`, `__tests__/properties*.test.ts`, `properties_test.go`, `tests/properties.rs`, or `PropertyTests.swift`), add a bullet to Conventions: *"Property-based tests under `<path>` — for parsers, validators, serializers, crypto, state machines. Regular example-based tests for CRUD, UI, and plumbing."*
- **Be specific, not generic.** Write "ShellCheck for `hooks/gate-scripts/*.sh`" not "linting is configured."
- **Include counts.** Write "204 skill definitions" not "many skills."
- **Document escape hatches.** If gate scripts block operations, list how to bypass them.
- **No opinions.** Document what IS, not what should be. This is a factual project map.
- **Keep it under 100 lines.** CLAUDE.md is loaded into every conversation — bloat wastes context tokens.

## C3. Verification

After writing, verify:
- [ ] `.claude/` directory exists (create if needed)
- [ ] CLAUDE.md accurately reflects current state (spot-check 3 claims against actual files)
- [ ] No secrets or credentials leaked into CLAUDE.md
- [ ] File is under 100 lines

## C4. Refresh Mode

When updating an existing CLAUDE.md (not generating from scratch):

1. Read current `.claude/CLAUDE.md`
2. Run C1 analysis
3. Diff current content against analysis results
4. Update only sections that have drifted — preserve manual additions the user may have made
5. Report what changed

**Do NOT overwrite the entire file during refresh.** Users may have added custom sections (e.g., "Things to avoid", project-specific notes). Merge, don't replace.

## Phase C Complete: CLAUDE.md

Report format:
```
✅ Phase C complete — .claude/CLAUDE.md generated

**Sections:** <list of sections written>
**Lines:** <line count>
**Refresh or new:** <new | refreshed — N sections updated>

This file is loaded automatically at the start of every Claude Code session.
To refresh later: run `/helmet` with Phase C only, or manually edit .claude/CLAUDE.md.

---

**Observability — review + bypass logs**

Busdriver's gates write per-project JSONL logs. Once the repo accumulates a few reviews, you can see pipeline health trends:

- **Raw logs** (always present once gates have fired):
  - `tail .claude/review-metrics.jsonl` — litmus review outcomes (PASS/FAIL, issue count, severity, iteration, CLI, mode, commit SHA, diff size)
  - `tail .claude/bypass-log.jsonl` — skip events (litmus + seatbelt). Event types: `skip-review-consumed`, `skip-pr-grind-consumed`, `review-skipped-none`, `narrative-fallback-triggered`, `short-circuit-pass`, `pr-fast-bypass`, `seatbelt-skip`. `seatbelt-skip` events (since seatbelt 1.8.0) carry `scanner` (e.g. `gitleaks`, `trivy`) and `reason` (the env var that tripped the skip, e.g. `SKIP_SEATBELT`, `SKIP_GITLEAKS`) — query with `jq 'select(.event=="seatbelt-skip") | {scanner,reason,head}' .claude/bypass-log.jsonl` to see which scanners are routinely bypassed
- **Dashboard script** (optional — provided by busdriver, not this repo):
  - `bash /path/to/busdriver/scripts/litmus-metrics-report.sh` — pass rate, severity distribution, iteration trends
  - Typical install path: `~/.claude/plugins/marketplaces/busdriver/scripts/litmus-metrics-report.sh` (adjust if your marketplaces directory differs). The script reads `.claude/review-metrics.jsonl` in the current working directory.

Review monthly to spot drift: scanners you keep bypassing, reviews that consistently FAIL on first iteration, or persistent short-circuit patterns.
```

## Key Decisions

- **Phase C runs after A and B but before D** — it needs Phase A (test info) and Phase B (CI info) to generate complete content. Running it earlier would miss CI workflows that Phase B just created
- **Under 100 lines** — CLAUDE.md is context tax on every conversation. Dense and factual beats comprehensive and long
- **Refresh preserves manual edits** — users add custom sections. Diff-and-merge, don't overwrite
- **No opinions, only facts** — CLAUDE.md documents what IS, not best practices or recommendations. Those belong in rules/ or skills/
- **Standalone invocable** — Phase C can run independently of A+B for repos that already have test + CI infrastructure but no CLAUDE.md

---

# Phase D: CodeGraph Index

Build a tree-sitter-parsed symbol/call graph for the repo via [CodeGraph](https://github.com/colbymchenry/codegraph). Once indexed, any agent wired to codegraph answers structural questions ("where is X defined?", "what calls Y?", "what would break if I change Z?") directly from the index instead of fanning out grep/glob/Read subagents — the upstream benchmark reports ~35% cheaper, ~57% fewer tokens, ~71% fewer tool calls on larger codebases. Phase D builds (or refreshes) this repo's index; wiring codegraph into your agents is a separate one-time setup (see D0).

## When to Use

- Onboarding any repo that contains code in a codegraph-supported language — Phase D auto-runs after Phase C when the `codegraph` CLI is on PATH
- Refreshing the index after a large refactor — codegraph's built-in file watcher (~500 ms debounce after file write) normally keeps the index current, so manual refresh is rare. Manual `codegraph sync` matters mainly when the watcher cannot run (network mounts, WSL2 `/mnt`, `CODEGRAPH_NO_WATCH=1`) or after batch operations the watcher missed
- Adding code intelligence to a repo that already has tests + CI + CLAUDE.md but no `.codegraph/` index
- Auditing or refreshing a repo's index (re-running Phase D runs `codegraph sync` on an already-indexed repo and reports current index counts)

**Supported languages** (helmet's set **bolded**; full list per upstream README, verified against `src/extraction/languages/`):
**TypeScript/JavaScript**, **Python**, **Go**, **Rust**, **Swift**, Java, Kotlin, C#, C, C++, Dart, Ruby, Scala, Vue, Svelte, Liquid, Lua, Luau, PHP, Pascal/Delphi

## D0. Precondition Check

Phase D NEVER blocks the helmet run. If any precondition fails, print a single `[d] Skipped — <reason>` line and proceed cleanly.

| Check | How | If fails |
|-------|-----|----------|
| `codegraph` CLI on PATH | `command -v codegraph >/dev/null 2>&1` | Print install hint (below), emit `[d] Skipped — codegraph CLI not installed`, exit Phase D |
| Supported language detected | Detect codegraph-supported languages directly using the same signals as [A1a Language Detection](#a1a-language-detection) (config files first, file extensions as fallback) — proceed if any of TypeScript/JavaScript, Python, Go, Rust, Swift, Java, Kotlin, C#, C, C++, Dart, Ruby, Scala, Vue, Svelte, Liquid, Lua, Luau, PHP, Pascal/Delphi is present. When Phase D is chained after Phase A in the same helmet run, reuse Phase A's detection result to avoid double work | Emit `[d] Skipped — no codegraph-supported language detected`, exit Phase D |
| Repo is a git repo OR has source files | `git rev-parse --show-toplevel` succeeds OR Phase A counted source files | Emit `[d] Skipped — no source code to index`, exit Phase D |

**Install hint (shown only when the CLI is missing):**
```
CodeGraph is not installed. Install it once globally to enable Phase D on every helmet run:

  curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh

After install completes, re-run /helmet — Phase D will pick up automatically.
Already have Node? `npm install -g @colbymchenry/codegraph` works on any version.
```

Do NOT auto-install the codegraph CLI on the user's behalf. The standalone installer drops files into `~/.codegraph/` and `~/.local/bin/`, which is a deliberate one-time decision the user should consent to.

**One-time agent wiring (prerequisite — NOT run by Phase D):** Phase D builds the index but does not register codegraph with your agents. Once per machine, wire every installed agent so each can query any repo's index:
```bash
codegraph install --target auto --location global --yes
```
`--target auto` detects and wires each installed agent (claude, cursor, codex, opencode, hermes, gemini, antigravity, kiro); `--location global` registers once for all repos. It's idempotent and machine-global — do it once, not per repo. Helmet does NOT run this automatically: it writes to your agents' global configs (`~/.claude.json`, `~/.codex/config.toml`, …), a deliberate one-time decision. If the index is built but wiring was skipped, the index exists but no agent can query it — Phase D's completion report (both first-install and re-run shapes) prints a reminder.

## D1. Capture Pre-Run Signal

Capture one pre-run signal before D2 mutates the repo: whether the per-repo index already exists. It chooses `codegraph init` (fresh build) vs `codegraph sync` (incremental refresh) for the index step, and drives the completion report's shape (first-install vs re-run).

| Signal | Detection | Means |
|--------|-----------|-------|
| Index DB | `./.codegraph/codegraph.db` exists | SQLite index already built — use `sync`, not `init` |

**Capture must happen BEFORE D2 runs AND in the same Bash invocation as the index step.** Two reasons:

1. The index step writes `.codegraph/codegraph.db`, so re-checking afterward always returns T and defeats the init-vs-sync branch.
2. Claude Code's Bash tool spawns a fresh process per call — shell variables (`SIGNAL_*`) do NOT persist across separate Bash invocations. D1, D2, D4, and the status read must therefore run as **one combined Bash call**.

See the combined snippet in D2 below — D1 lives at the top of that snippet, NOT as a separate Bash call.

**On the init-vs-sync branch:**

- Fresh repo, or an interrupted prior run (no `.codegraph/codegraph.db`): `codegraph init` builds the index from scratch.
- Existing index (signal T): `codegraph sync` refreshes incrementally, catching drift the watcher daemon may have missed (daemon down during a batch rename, network mount, `CODEGRAPH_NO_WATCH=1`).
- Both run with stdin redirected from `/dev/null` so they stay non-interactive even on a filesystem where the watch-fallback would otherwise prompt.

## D2. Build Repo Index (Unified)

Run D1's signal capture, the per-repo index build (init or sync), D4's gitignore append, and the final status read as a **single combined Bash invocation** — Claude Code's Bash tool spawns a fresh process per call, so the `SIGNAL_*` variable MUST stay in the same shell session. Phase D does NOT wire agents — that's a one-time `codegraph install` prerequisite (see D0); Phase D only builds this repo's index.

```bash
set -e  # backstops the few genuinely unguarded commands (notably the mktemp for the status tempfile — the SIGNAL_INDEX_DB assignment always exits 0 via `|| echo F`, so set -e never fires there); the index build, gitignore append, and status read are each downgraded with `|| printf ...` so a failure there still lets the completion report emit

# D1: capture the one pre-run signal (must precede the index step). Check the
# index DB file, NOT just the .codegraph/ dir — an interrupted prior run can
# leave the dir without a codegraph.db, and `sync` on a dir-without-db fails;
# requiring the db means that case correctly falls to `init` (fresh build).
SIGNAL_INDEX_DB=$([ -f .codegraph/codegraph.db ] && echo T || echo F)

# Emit the signal to stdout BEFORE D2 mutates state — the caller parses it out
# of the combined output to choose report shape (first-install vs re-run)
printf 'PHASE_D_SIGNAL SIGNAL_INDEX_DB=%s\n' "$SIGNAL_INDEX_DB"

# D2: build the per-repo index — Phase D's one job. init on a fresh repo, sync
# when .codegraph/codegraph.db already exists. stdin from /dev/null keeps both non-interactive
# even on a filesystem where the watch-fallback would otherwise prompt. Non-fatal:
# a stale watcher state or DB-lock contention from codegraph's own daemon
# shouldn't kill the rest of Phase D. The caller detects PHASE_D_SYNC_FAILED /
# PHASE_D_INDEX_FAILED in stdout and annotates the report accordingly. Agent
# wiring is NOT done here — it's a one-time `codegraph install` prerequisite (D0).
if [ "$SIGNAL_INDEX_DB" = "T" ]; then
  codegraph sync </dev/null || printf 'PHASE_D_SYNC_FAILED=1\n'
else
  codegraph init </dev/null || printf 'PHASE_D_INDEX_FAILED=1\n'
fi

# D4 (gitignore append) — non-fatal; idempotent across common variants.
# The grep covers: literal '.codegraph/', no trailing slash ('.codegraph'),
# leading slash ('/.codegraph/'), trailing whitespace, and inline comments
# (`.codegraph/  # local index`). Prevents duplicate appends on re-runs.
if ! ( [ -f .gitignore ] && grep -Eq '^[[:space:]]*/?\.codegraph/?([[:space:]]|#|$)' .gitignore ); then
  printf '\n# CodeGraph local index (regenerable from source — never commit)\n.codegraph/\n' >> .gitignore || printf 'PHASE_D_GITIGNORE_FAILED=1\n'
fi

# Status read — captured to a tempfile FIRST so a codegraph crash mid-write
# can't produce truncated JSON concatenated with the error sentinel. Only
# after a clean exit do we emit the JSON inside the BEGIN/END sentinels.
# Non-fatal: status failure (DB locked by concurrent watcher write, codegraph
# crash, etc.) shouldn't crash Phase D — the caller falls back to a "status
# unavailable" report variant via the error sentinel.
CG_STATUS_TMP=$(mktemp -t cg-status.XXXXXX)
trap 'rm -f "$CG_STATUS_TMP"' EXIT
printf 'PHASE_D_STATUS_BEGIN\n'
if codegraph status --json > "$CG_STATUS_TMP" 2>/dev/null; then
  cat "$CG_STATUS_TMP"
else
  printf '{"error":"status read failed"}'
fi
printf '\nPHASE_D_STATUS_END\n'
```

**Reading the signal + status back after the Bash call returns:** Claude parses three deterministic regions from the combined stdout:

1. `PHASE_D_SIGNAL SIGNAL_INDEX_DB=...` — the first output line, fixed prefix. Drives report-shape (first-install when F, re-run when T).
2. Between `PHASE_D_STATUS_BEGIN` and `PHASE_D_STATUS_END` sentinels — the `codegraph status --json` payload (or `{"error":...}` fallback on failure).
3. Optional fault flags: `PHASE_D_SYNC_FAILED=1` (the re-run `codegraph sync` failed; status counts reflect the pre-run index state and may be stale until the user manually re-runs `codegraph sync`); `PHASE_D_INDEX_FAILED=1` (the fresh `codegraph init` failed; no usable index was built — the failing command's stderr appears in the raw Bash output alongside the fault flag, not in a structured stdout region; surface it and tell the user to re-run `codegraph init`); `PHASE_D_GITIGNORE_FAILED=1` (gitignore append failed; user must add `.codegraph/` manually).

Shell variables themselves do not survive the Bash call's exit — the stdout-emission is the only persistence channel.

Use the combined block above as Phase D's primary action. The standalone commands shown below are for human reference and documentation only — they omit D1's signal capture, the init-vs-sync branch, and the gitignore step.

```bash
# Phase D's actual action — build this repo's index:
codegraph init </dev/null                                 # or: codegraph sync, if .codegraph/codegraph.db already exists

# One-time per machine — wire codegraph into your agents (NOT run by Phase D;
# without it the index builds but no agent can query it). See the D0 prerequisite:
codegraph install --target auto --location global --yes
```

Phase D runs only `codegraph init`/`sync`, which does the following (verified against the `codegraph` CLI v0.9.9):

1. **Builds the project index** — `codegraph init` creates `.codegraph/` at the repo root and parses every supported source file with tree-sitter, persisting the symbol/edge graph to a local SQLite database. On a re-run, `codegraph sync` refreshes it incrementally.
2. **Stays non-interactive** — `init` has no `--yes` flag and can prompt for a watch-fallback decision on filesystems where live watching can't be set up (network mount, WSL2 `/mnt`, `CODEGRAPH_NO_WATCH=1`); the `</dev/null` redirect feeds EOF so the run can't hang. `init` only *builds* the index — ongoing auto-refresh is handled by codegraph's watcher daemon (`.codegraph/daemon.pid`/`daemon.sock`), which runs alongside the MCP server (`codegraph serve --mcp`) once an agent opens the project. If no agent has the server open, the index does not refresh on its own — pick up drift with `codegraph sync`.

The one-time `codegraph install` (run separately — see the D0 prerequisite) is what makes the index *reachable*: it registers codegraph in each detected agent's global config (table below) plus Claude Code's `~/.claude/settings.json` auto-allow. That install writes nothing into the repo; Phase D's only repo writes are the `.codegraph/` index and the `.gitignore` entry (D4).

**What the one-time `codegraph install` writes** (global config per agent; `--target auto` only touches installed ones):

| Agent | File | Notes |
|-------|------|-------|
| claude | `~/.claude.json` (MCP) + `~/.claude/settings.json` (auto-allow) | `{ "mcpServers": { "codegraph": { "type": "stdio", "command": "codegraph", "args": ["serve", "--mcp"] } } }` |
| cursor | `~/.cursor/mcp.json` | args include `--path ${workspaceFolder}` so the server resolves the active project |
| codex | `~/.codex/config.toml` | `[mcp_servers.codegraph]` TOML block |
| opencode | `~/.config/opencode/opencode.jsonc` | `mcp.codegraph` entry |
| hermes | `~/.hermes/config.yaml` | `mcp_servers.codegraph` + `mcp-codegraph` toolset |
| gemini / antigravity / kiro | their respective global config paths | written only when detected |

**The only per-repo artifact:**

| Path | Purpose | Idempotent behavior |
|------|---------|---------------------|
| `./.codegraph/` | SQLite database of parsed symbols + edges (gitignored — see D4) | First-build on fresh repo via `init`; on re-run `sync` refreshes incrementally |

**First-run index timing (single-threaded, per-project):**

| Repo size | Approximate timing |
|-----------|---------------------|
| <500 source files | seconds |
| 500–3,000 | <1 min |
| 3,000–10,000 | 1–3 min |
| >10,000 | 3–10 min |

Stream the codegraph output so the user can see progress on large repos. Do NOT background the command — Phase D's completion report depends on `codegraph status --json` returning real counts.

**Why the one-time install uses `--location global --target auto`:** this machine runs multiple agents (Claude Code, Codex CLI, Gemini/Antigravity, etc.), and each reads its own config file — a per-repo `.mcp.json` only wires Claude Code, leaving every other agent blind to the index. `--target auto` detects and wires all of them; `--location global` registers once for every repo instead of re-writing config into each one. Because it's global and effectively static (it changes only when you add or remove an agent), it belongs *outside* Phase D — running it on every helmet invocation would re-touch global config for no gain. That's why Phase D builds the index only and leaves wiring as a one-time prerequisite.

**What the auto-allow covers:** the seven pre-permitted tools are codegraph's query and navigation surface — symbol search, call-graph traversal (`callers`, `callees`), impact analysis, single-node inspection, composite context, and index status. Two of them (`codegraph_node` and `codegraph_context`) can optionally return source snippets when the caller passes `includeCode=true` — in routine "where is X defined" queries this is benign, but be aware the auto-allow is not a hard read-only gate; it's "allow the normal index-query surface." The two tools that bulk-return data (`codegraph_explore`, which returns source verbatim across multiple symbols; and `codegraph_files`, which returns the project file tree) are deliberately NOT pre-allowed by codegraph's installer — they prompt the first time Claude Code calls them. Do NOT pass `--no-permissions` (would force the user to approve every search query interactively).

**On failure:** if the index step (`init`/`sync`) fails, it is downgraded to `PHASE_D_INDEX_FAILED=1` / `PHASE_D_SYNC_FAILED=1` rather than aborting, so the completion report still emits; report the stderr and tell the user to re-run `codegraph init`. Phase D does not roll back partial state — a half-built `.codegraph/` is easier to inspect and rebuild (`rm -rf .codegraph && codegraph init </dev/null`) than to undo. The most common build failures are out-of-memory on very large repos (codegraph documents a `--max-memory` flag) and individual files with unsupported syntax (codegraph logs and skips them, then continues — these are warnings, not errors).

**Index step rationale (already embedded in D2's combined block):** the `if [ "$SIGNAL_INDEX_DB" = "T" ]; then codegraph sync ...; else codegraph init ...; fi` branch builds the index fresh on the first run (`SIGNAL_INDEX_DB=F`) and refreshes it incrementally on a re-run (`T`), catching drift the file watcher may have missed (daemon down during a batch rename, network-mount filesystem, `CODEGRAPH_NO_WATCH=1`). Do NOT execute `codegraph init` or `codegraph sync` as a separate Bash call here — the branch is already in the combined block above.

## D3. Manual Override Commands

D2's unified block handles every signal state correctly. Reach for the targeted commands below only when the user explicitly requests a manual override (debug workflow, force rebuild, repair after codegraph upgrade):

| User scenario | Command | Notes |
|---------------|---------|-------|
| "Force rebuild from scratch — the index seems corrupted" | `rm -rf .codegraph && codegraph init </dev/null` | Re-creates the index from source; global agent wiring is untouched |
| "Just refresh the index, don't touch anything else" | `codegraph sync </dev/null` | Incremental refresh only; safe to run repeatedly |
| "Re-wire an agent I just installed" | `codegraph install --target auto --location global --yes` | Idempotent; picks up newly-installed agents, no-ops on already-wired ones |

**`codegraph init` builds the index by default** (the old `-i`/`--index` flag is now a deprecated no-op). It can prompt for the watch-fallback when the file watcher cannot run, so helmet always invokes it with stdin redirected from `/dev/null` to stay non-interactive — keep that redirect on any scripted `init`/`sync`.

## D4. Gitignore Append (Reference — Already Embedded in D2)

D4's gitignore append is part of D2's combined Bash block (the conditional starting with `if ! ( [ -f .gitignore ] && grep -Eq '^[[:space:]]*/?\.codegraph/?([[:space:]]|#|$)' .gitignore ); then ...` — extended regex idempotent across `.codegraph/`, `.codegraph`, `/.codegraph/`, and inline-comment variants). Do NOT execute this step as a separate Bash call — the combined block already handles it idempotently and emits `PHASE_D_GITIGNORE_FAILED=1` to stdout on failure (read-only FS, permission error).

**Rationale (why this step exists):** the `.codegraph/` directory contains a SQLite database derived deterministically from source files. Committing it would balloon the repo, churn diffs on every edit, and produce merge conflicts on every branch sync. Local-only is the only sensible mode. The combined block creates `.gitignore` if absent — some repos rely entirely on global gitignore, so a missing project `.gitignore` is normal; in that case the block writes a new one with just the codegraph entry (no boilerplate ignores, that's the user's call).

## Phase D Complete: CodeGraph Index

Read `codegraph status --json` for the report numbers. Verified fields (from `src/bin/codegraph.ts`):

| Field | Type | Use |
|-------|------|-----|
| `fileCount` | number | Indexed file count |
| `nodeCount` | number | Total symbol/node count |
| `edgeCount` | number | Total relationship count |
| `dbSizeBytes` | number | SQLite DB size on disk |
| `languages` | string[] | Languages with any indexed files |
| `pendingChanges` | `{added, modified, removed}` | Counts of files awaiting sync |
| `backend` | string | SQLite backend (e.g., `node-sqlite`) |
| `journalMode` | string | `wal` is healthy; anything else means reads can block on writes |
| `nodesByKind` | object | Breakdown of node kinds (function, class, method, etc.) |

Report format (first-install):
```text
✅ Phase D complete — CodeGraph index built

**Indexed:** <fileCount> files · <nodeCount> nodes · <edgeCount> edges
**Languages:** <languages joined with ", ">
**Index size:** <dbSizeBytes formatted as MB>
**Index location:** .codegraph/ (gitignored)

Try it: in any agent session in this repo, ask "where is <Symbol> defined?" or "what calls <Symbol>?" — it answers from the index in one MCP call instead of running grep.
→ One-time setup: if codegraph isn't wired into your agents yet, run `codegraph install --target auto --location global --yes` once — without it the index exists but no agent can query it.
```
(The first-install report always shows the one-time-setup line — Phase D builds the index but does not wire agents, and it has no cheap way to know whether wiring already happened, so it reminds rather than assumes.)

Report format (re-run — parsed `PHASE_D_SIGNAL` showed `SIGNAL_INDEX_DB=T` pre-D2):
```text
✅ Phase D re-run — CodeGraph index refreshed

**Indexed:** <fileCount> files · <nodeCount> nodes · <edgeCount> edges
**Pending sync:** <pendingChanges.added + modified + removed> files
  (append `(sync failed — counts may be stale)` if `PHASE_D_SYNC_FAILED=1` was also emitted)
→ Reachable only if codegraph is wired into your agents — one-time `codegraph install --target auto --location global --yes` if you haven't.
```
(Both reports carry the wiring reminder: Phase D builds `.codegraph/` but never wires agents and never checks, so even a re-run with an existing index can't assume wiring happened.)
The re-run shape is selected when the parsed `PHASE_D_SIGNAL` showed `SIGNAL_INDEX_DB=T`. Reminder: `SIGNAL_INDEX_DB` is parsed from stdout's `PHASE_D_SIGNAL` line — the shell variable itself did not survive the Bash call's exit.

If `journalMode != "wal"`, append a warning line: `⚠ Journal mode is "<journalMode>" — reads may block on writes; this filesystem (network mount, WSL2 /mnt) doesn't support WAL.`

If `pendingChanges.added + modified + removed > 0` after the re-run `codegraph sync`, append a hint: `→ <count> file(s) still pending — run `codegraph sync` again or check the file watcher.`

When Phase D is skipped, emit a single one-line `[d] Skipped — <reason>` and proceed to the helmet wrap-up summary.

## Key Decisions

- **Phase D runs last** — reuses Phase A's language detection when chained in the same helmet run; runs its own D0 detection when invoked standalone. Functionally decoupled from B and C: no CI involvement and no CLAUDE.md write — Phase D no longer touches CLAUDE.md
- **Phase D builds the index only; wiring is a one-time prerequisite** — agent registration (`codegraph install --target auto --location global`) is machine-global and effectively static, so it lives *outside* Phase D — run once per machine, not on every helmet invocation. Phase D's only write is the per-repo `.codegraph/` index (`init`/`sync`); D0 surfaces the one-time install command and the first-install report reminds the user if it hasn't been done. The global install, when run, wires every detected agent (Claude Code, Cursor, Codex, …) via `--target auto`, so each agent — not just Claude Code — can query the index
- **Auto-allow the query surface, not source-bulk** — Pre-permits the seven query/navigation tools (`search`, `context`, `callers`, `callees`, `impact`, `node`, `status`). Two of them (`node`, `context`) optionally surface source snippets via `includeCode=true`; not a hard read-only gate, but matches what routine "where is X" queries actually need. The two bulk tools (`explore` for verbatim source across symbols, `files` for the project file tree) are not pre-allowed and prompt on first use
- **Fail-soft** — Phase D never blocks Phase A/B/C value. If codegraph is missing, fails, or skipped, helmet still ships test infra + CI/CD + CLAUDE.md cleanly
- **No auto-install of the CLI** — `curl … install.sh | sh` is a one-time decision the user consents to. Auto-installing would surprise users with `~/.codegraph/` and `~/.local/bin/codegraph` files they didn't expect
- **`.codegraph/` is gitignored, not committed** — The index is derived deterministically from source; committing it inflates the repo and produces merge conflicts on every edit
- **Idempotent by design** — re-running Phase D on an already-indexed repo runs `codegraph sync`, a safe incremental refresh that no-ops when nothing changed and surfaces the current index status
- **Standalone invocable** — Phase D can run independently of A/B/C for repos that already have everything except a CodeGraph index
