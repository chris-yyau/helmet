#!/usr/bin/env bash
#
# check-required-checks.sh — verify required-checks.lock matches reality.
#
# Drift surfaces in three places, all of which can silently break merge:
#
#   (a) Lock vs workflow source:  a required check's `name:` (or job key
#       when no name is set) was renamed in a .yml without updating the
#       lock — branch protection still requires the old name, no check
#       posts under that name, PRs hang.
#
#   (b) Lock vs branch protection: lock was updated, branch-protection
#       contexts weren't — server still requires an old or wrong name.
#
#   (c) Lock vs reporting app: a different integration started posting a
#       same-named status, and we didn't notice. Recorded source_app
#       lets us flag spoofing or migration.
#
# Modes:
#   ./check-required-checks.sh                      # all 3 checks (default)
#   ./check-required-checks.sh --local-only         # skip API calls (a) only
#   ./check-required-checks.sh --owner OWNER --repo REPO
#                                                    # override repo (default
#                                                    # = current git remote)
#
# Exit codes:
#   0 — no drift
#   1 — drift detected
#   2 — usage / config error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCK="$REPO_ROOT/.github/required-checks.lock"

LOCAL_ONLY=0
OWNER=""
REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-only) LOCAL_ONLY=1; shift ;;
    --owner) OWNER="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    -h|--help)
      sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "error: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$LOCK" ]]; then
  echo "error: $LOCK not found" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 2
fi

# Resolve owner/repo from git remote when not supplied.
if [[ -z "$OWNER" || -z "$REPO" ]]; then
  remote_url=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)
  if [[ -z "$remote_url" ]]; then
    echo "warn: no git remote 'origin' — running --local-only"
    LOCAL_ONLY=1
  else
    # Parse github.com:OWNER/REPO(.git)? or https://github.com/OWNER/REPO(.git)?
    # Normalize trailing slash + .git first so the regex doesn't have to handle
    # them as alternatives (and so the simpler regex catches both
    # `…/repo`, `…/repo/`, and `…/repo.git`).
    normalized="${remote_url%/}"           # strip one trailing slash if any
    normalized="${normalized%.git}"        # strip .git if any
    parsed=$(echo "$normalized" | sed -E 's#^.*[:/]([^/]+)/([^/]+)$#\1 \2#')
    OWNER="${OWNER:-$(echo "$parsed" | awk '{print $1}')}"
    REPO="${REPO:-$(echo "$parsed" | awk '{print $2}')}"

    # Validate parsed values. GitHub owner/repo names are restricted to
    # `[A-Za-z0-9._-]+`; anything else means the regex matched something it
    # shouldn't have (e.g., a non-github remote, a malformed URL, or a path
    # traversal attempt like `owner/../foo`). Fail-fast rather than feed
    # garbage into `gh api` URLs and get confusing 404s.
    if [[ ! "$OWNER" =~ ^[A-Za-z0-9._-]+$ || ! "$REPO" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "error: could not parse OWNER/REPO from remote '$remote_url'" >&2
      echo "       parsed: OWNER='$OWNER' REPO='$REPO'" >&2
      echo "       hint: pass --owner X --repo Y, or --local-only to skip API checks" >&2
      exit 2
    fi
  fi
fi

drift=0

# ────────────────────────────────────────────────────────────────────
# (a) Lock vs workflow source — every required entry's workflow file
#     must contain a job whose name (or key when no name) matches.
# ────────────────────────────────────────────────────────────────────
echo "[a] Checking lock entries against workflow source files…"

# Iterate required entries. Use `jq -c` so the entire object stays on one
# line — multi-line outputs would break the read loop.
while IFS= read -r entry; do
  name=$(echo "$entry" | jq -r '.name')
  workflow=$(echo "$entry" | jq -r '.workflow')
  job_key=$(echo "$entry" | jq -r '.job')
  source_app=$(echo "$entry" | jq -r '.source_app')

  wf="$REPO_ROOT/$workflow"
  if [[ ! -f "$wf" ]]; then
    if [[ "$source_app" == "github-actions" ]]; then
      echo "  DRIFT: $name → workflow file missing: $workflow"
      drift=1
    else
      # External apps don't ship in our repo; skip the file check.
      :
    fi
    continue
  fi

  # External-app entries don't correspond to a local .yml — they post via
  # the GitHub Apps integration. Skip the source check for them.
  if [[ "$source_app" != "github-actions" ]]; then
    continue
  fi

  # Find the job. The match prefers an explicit `name: <name>` line within
  # the job's body; falls back to the bare job key only when *that specific
  # job* has no `name:` field (per-job bareness — not file-wide, so mixed
  # workflows where some jobs are named and some aren't are handled
  # correctly).
  #
  # All grep ERE patterns interpolate `$name` and `$job_key` via an awk-only
  # parser instead of shell-level regex strings, so check names containing
  # ERE metacharacters (`.`, `+`, `(`, etc.) match literally rather than as
  # patterns. Job keys are restricted to `[A-Za-z0-9_-]` by GitHub Actions'
  # YAML schema, but check names are free-form and routinely contain dots
  # ("CodeScene Code Health Review (main)"), spaces, and slashes.
  #
  # Strategy: walk the file's jobs block once with awk, recording for each
  # job key its declared `name:` value (or empty if none). Then look up the
  # current entry's `job_key`:
  #   - present + name matches      → ok
  #   - present + name empty        → bare-key match against `name`
  #   - present + name differs      → DRIFT (lock vs source disagreement)
  #   - absent                      → DRIFT (job key not found)
  #
  # `actual_name` uses string equality, no regex involvement, so the lookup
  # is metacharacter-safe.
  # Use POSIX-portable awk (no gawk-only 3-arg `match()` or `gensub()`).
  # `cur` holds the most recent job key we entered.
  actual_name=$(awk -v key="$job_key" '
    # Top-level "jobs:" header. Track depth so nested keys (env:, with:, etc.)
    # in mappings under jobs.* do not get mistaken for top-level job keys.
    # Allow a trailing inline `# comment` on the header line — YAML permits it
    # and an over-strict match would silently produce false drift.
    /^jobs:[[:space:]]*(#.*)?$/ { in_jobs = 1; next }
    in_jobs && /^[^[:space:]]/ { in_jobs = 0 }   # left jobs block

    # Job key line: exactly two-space indent, identifier, then ":", optionally
    # followed by a trailing `# comment`. Capture the key with sub() since
    # BSD awk lacks 3-arg match().
    in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*(#.*)?$/ {
      cur = $0
      sub(/^  /, "", cur)
      sub(/:[[:space:]]*(#.*)?$/, "", cur)
      seen[cur] = 1
      jname[cur] = ""           # default: no explicit name
      next
    }

    # Inside the current job. The first `    name: <value>` line at the
    # four-space level wins. Use sub() to peel the prefix and the optional
    # surrounding quotes so the stored value matches the rendered check name.
    in_jobs && cur != "" && /^    name:[[:space:]]+/ {
      val = $0
      sub(/^    name:[[:space:]]+/, "", val)
      sub(/^["'\'']/, "", val)
      sub(/["'\'']$/, "", val)
      if (jname[cur] == "") jname[cur] = val
    }

    END {
      if (key in seen) {
        # Sentinel-prefix the value so we can distinguish "found, name empty"
        # (bare-key job) from "key not found at all".
        printf("FOUND:%s", jname[key])
      } else {
        printf("MISSING")
      }
    }
  ' "$wf")

  case "$actual_name" in
    MISSING)
      echo "  DRIFT: $name expected in $workflow as job '$job_key' — job key not found"
      drift=1
      ;;
    "FOUND:")
      # Job exists with no explicit name — GitHub uses the job key as the
      # check name, so the lock entry's `name` must equal the job key.
      if [[ "$name" != "$job_key" ]]; then
        echo "  DRIFT: lock says name='$name' but $workflow:$job_key has no 'name:' field (GitHub will report '$job_key')"
        drift=1
      fi
      ;;
    "FOUND:$name")
      : # explicit name match — ok
      ;;
    *)
      # Strip the FOUND: sentinel for the diagnostic message.
      observed="${actual_name#FOUND:}"
      echo "  DRIFT: lock says '$name' but $workflow:$job_key has name '$observed'"
      drift=1
      ;;
  esac
done < <(jq -c '.required[]' "$LOCK")

if [[ "$drift" -eq 0 ]]; then
  echo "  ok: every lock entry maps to a workflow job"
fi

# ────────────────────────────────────────────────────────────────────
# (b) Lock vs branch protection — names in lock.required must equal the
#     server's required_status_checks.contexts (set equality).
# ────────────────────────────────────────────────────────────────────
if [[ "$LOCAL_ONLY" -eq 1 ]]; then
  echo "[b] Skipped (--local-only)"
  exit "$drift"
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "[b] Skipped (gh CLI not installed). Re-run with gh available or pass --local-only."
  exit "$drift"
fi

echo "[b] Checking lock against $OWNER/$REPO branch protection…"

# Default branch lookup (most repos use 'main' but be explicit)
default_branch=$(gh api "repos/$OWNER/$REPO" --jq '.default_branch' 2>/dev/null || echo "main")

# Distinguish three cases that the original `--jq '.contexts[]'` form
# silently merged:
#   (i)   gh api errored / branch unprotected / 404                   → warn-skip
#   (ii)  gh api succeeded with `contexts: []`  (real-empty)          → drift if lock has entries
#   (iii) gh api succeeded with `contexts: ["a",…]`                   → set-compare
#
# Use `gh api` exit code (not response shape) to detect (i). Use `jq -e` to
# detect (ii) vs (iii) without conflating null/missing with empty array.
api_path="repos/$OWNER/$REPO/branches/$default_branch/protection/required_status_checks"
if server_response=$(gh api "$api_path" 2>/dev/null); then
  api_ok=1
else
  api_ok=0
fi

if [[ "$api_ok" -eq 0 ]]; then
  echo "  warn: could not read required_status_checks (no branch protection? insufficient scope?)"
elif ! contexts_count=$(printf '%s' "$server_response" \
       | jq -er 'if (has("contexts") and (.contexts | type == "array")) then .contexts | length else error("missing-contexts") end' 2>/dev/null); then
  # API returned 200 but the response shape is unexpected: either `.contexts`
  # is absent, or it's not an array. Treat as a warn-skip rather than silent
  # pass — the API contract changed, we're targeting the wrong endpoint, or
  # auth scope is insufficient and we got a stub response. The bare jq form
  # `.contexts | length` would have returned 0 for missing fields (since
  # `null | length` is 0), conflating "missing" with "real-empty".
  echo "  warn: required_status_checks response missing .contexts field — unexpected API shape"
else
  # Force C locale so shell `sort` matches jq's codepoint ordering. Without
  # this, en_US.UTF-8 dictionary order interleaves cases ("commitlint" sorts
  # before "Dependency CVEs"), while jq sort is strict codepoint ("D" < "c"),
  # producing a phantom diff where every item appears on both sides.
  server_contexts=$(printf '%s' "$server_response" | jq -r '.contexts[]?' | LC_ALL=C sort)
  lock_contexts=$(jq -r '.required[].name' "$LOCK" | LC_ALL=C sort)
  lock_count=$(jq -r '.required | length' "$LOCK")

  # `echo "$empty_var"` always emits a trailing newline, so an empty side
  # would feed `comm` a blank line and produce a phantom drift entry. Use
  # `printf '%s\n' | grep -v '^$'` to strip blanks so genuine empty/empty,
  # empty/non-empty, and non-empty/empty cases all report cleanly.
  missing_on_server=$(comm -23 <(printf '%s\n' "$lock_contexts" | grep -v '^$' || true) \
                                <(printf '%s\n' "$server_contexts" | grep -v '^$' || true) || true)
  extra_on_server=$(comm -13   <(printf '%s\n' "$lock_contexts" | grep -v '^$' || true) \
                                <(printf '%s\n' "$server_contexts" | grep -v '^$' || true) || true)

  if [[ -n "$missing_on_server" ]]; then
    echo "  DRIFT: in lock but not required on server:"
    echo "$missing_on_server" | sed 's/^/    - /'
    drift=1
  fi
  if [[ -n "$extra_on_server" ]]; then
    echo "  DRIFT: required on server but not in lock:"
    echo "$extra_on_server" | sed 's/^/    - /'
    drift=1
  fi
  if [[ -z "$missing_on_server" && -z "$extra_on_server" ]]; then
    if [[ "$contexts_count" -eq 0 && "$lock_count" -eq 0 ]]; then
      echo "  ok: both lock and server are empty (no required checks declared anywhere)"
    else
      echo "  ok: lock.required matches server contexts (both contain $contexts_count items)"
    fi
  fi
fi

# ────────────────────────────────────────────────────────────────────
# (c) Lock vs reporting app — for the latest commit on default branch,
#     each required check's reporting `app.slug` must equal its
#     declared source_app. Catches drift when a different integration
#     starts posting a same-named status.
# ────────────────────────────────────────────────────────────────────
echo "[c] Checking lock source_app against latest check-run reporters…"

# Walk back through recent commits to find one that actually ran CI.
# Release commits often use `[skip ci]` and have no check-runs, which is
# expected — keep stepping back until we find a real commit.
runs_json=""
sha=""
for offset in 0 1 2 3 4 5 6 7 8 9; do
  candidate=$(gh api "repos/$OWNER/$REPO/commits?sha=$default_branch&per_page=1&page=$((offset+1))" \
    --jq '.[0].sha' 2>/dev/null || true)
  [[ -z "$candidate" || "$candidate" == "null" ]] && continue
  # The check-runs endpoint paginates at 100 results per page. Repos with many
  # integrations or repeated CI re-runs on the same commit can exceed that, so
  # without --paginate the script emits "warn: no check-run named X" for items
  # past page 1 instead of detecting real drift. --paginate streams items,
  # which `jq -sc '.'` then collapses back into a single JSON array.
  rj=$(gh api "repos/$OWNER/$REPO/commits/$candidate/check-runs" --paginate \
         --jq '.check_runs[]' 2>/dev/null \
       | jq -sc '.' || true)
  count=$(echo "$rj" | jq 'length' 2>/dev/null || echo 0)
  if [[ "${count:-0}" -gt 0 ]]; then
    runs_json="$rj"
    sha="$candidate"
    break
  fi
done

if [[ -z "$runs_json" ]]; then
  echo "  warn: no recent commit (last 10) had check-runs — skipping app check"
  exit "$drift"
fi
echo "  using commit: ${sha:0:7}"

while IFS= read -r entry; do
  name=$(echo "$entry" | jq -r '.name')
  expected_app=$(echo "$entry" | jq -r '.source_app')
  # Pick the most recent check-run for this name (highest started_at).
  actual=$(echo "$runs_json" | jq -r --arg n "$name" '
    [.[] | select(.name == $n)] | sort_by(.started_at) | last
  ')
  if [[ "$actual" == "null" || -z "$actual" ]]; then
    echo "  warn: no check-run named '$name' on HEAD — skipping app check"
    continue
  fi
  actual_slug=$(echo "$actual" | jq -r '.app.slug // "unknown"')
  if [[ "$actual_slug" != "$expected_app" ]]; then
    echo "  DRIFT: '$name' expected source_app='$expected_app' but reported by '$actual_slug'"
    drift=1
  fi
done < <(jq -c '.required[]' "$LOCK")

if [[ "$drift" -eq 0 ]]; then
  echo "  ok: every required check is reported by its expected source app"
fi

exit "$drift"
