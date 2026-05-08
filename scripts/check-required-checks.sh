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
    parsed=$(echo "$remote_url" | sed -E 's#^.*[:/]([^/]+)/([^/]+)(\.git)?$#\1 \2#' | sed 's/\.git$//')
    OWNER="${OWNER:-$(echo "$parsed" | awk '{print $1}')}"
    REPO="${REPO:-$(echo "$parsed" | awk '{print $2}')}"
    REPO="${REPO%.git}"
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
  # the job's body; falls back to the bare job key when no `name:` is set.
  # YAML parsing in shell is brittle; this is intentionally a coarse grep
  # that catches the common cases — false negatives here just become
  # additional drift output, which is the desired conservative behavior.
  if grep -qE "^[[:space:]]+name:[[:space:]]+${name}\$" "$wf"; then
    : # explicit name match
  elif grep -qE "^[[:space:]]{2}${job_key}:[[:space:]]*\$" "$wf" \
       && ! grep -qE "^[[:space:]]+name:[[:space:]]+" "$wf"; then
    # job key match AND no `name:` field anywhere in the workflow's jobs
    # block — implies the check name = job key. Imperfect but covers
    # tests.yml's version-drift / commitlint pattern.
    :
  else
    # Stricter probe: job exists but its name (or key) doesn't match.
    if grep -qE "^[[:space:]]{2}${job_key}:" "$wf"; then
      # Try to read its name field
      actual_name=$(awk -v key="$job_key" '
        $0 ~ "^[[:space:]]{2}"key":" {in_job=1; next}
        in_job && /^[[:space:]]{2}[A-Za-z0-9_-]+:/ {in_job=0}
        in_job && /^[[:space:]]+name:[[:space:]]+/ {sub(/^[[:space:]]+name:[[:space:]]+/, ""); print; exit}
      ' "$wf")
      if [[ -n "$actual_name" && "$actual_name" != "$name" ]]; then
        echo "  DRIFT: lock says '$name' but $workflow:$job_key has name '$actual_name'"
        drift=1
      else
        echo "  DRIFT: $name expected in $workflow as job '$job_key' — name field not found and key not bare"
        drift=1
      fi
    else
      echo "  DRIFT: $name expected in $workflow as job '$job_key' — job key not found"
      drift=1
    fi
  fi
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

# Force C locale so shell `sort` matches jq's codepoint ordering. Without
# this, en_US.UTF-8 dictionary order interleaves cases ("commitlint" sorts
# before "Dependency CVEs"), while jq sort is strict codepoint ("D" < "c"),
# producing a phantom diff where every item appears on both sides.
server_contexts=$(gh api "repos/$OWNER/$REPO/branches/$default_branch/protection/required_status_checks" \
  --jq '.contexts[]' 2>/dev/null | LC_ALL=C sort || true)
if [[ -z "$server_contexts" ]]; then
  echo "  warn: could not read required_status_checks (no branch protection? insufficient scope?)"
else
  lock_contexts=$(jq -r '.required[].name' "$LOCK" | LC_ALL=C sort)

  missing_on_server=$(comm -23 <(echo "$lock_contexts") <(echo "$server_contexts") || true)
  extra_on_server=$(comm -13 <(echo "$lock_contexts") <(echo "$server_contexts") || true)

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
    echo "  ok: lock.required matches server contexts (both contain $(echo "$lock_contexts" | wc -l | tr -d ' ') items)"
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
  rj=$(gh api "repos/$OWNER/$REPO/commits/$candidate/check-runs" --jq '.check_runs' 2>/dev/null || true)
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
