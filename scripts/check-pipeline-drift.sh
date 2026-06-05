#!/usr/bin/env bash
# check-pipeline-drift.sh — surface repos whose helmet-generated CI boilerplate has
# silently drifted behind the current helmet pipeline version.
#
# WHY: helmet *vendors* (copies) its workflows into each repo at onboarding, so every
# repo holds a frozen snapshot. Nothing re-syncs it — dependabot bumps action SHAs but
# never the workflow logic — so a repo can sit generations behind without anyone
# noticing (e.g. a repo onboarded at v1.12 while helmet is at v1.21). Each generated
# workflow carries a `# helmet-pipeline: vX.Y.Z` stamp; this script reads that stamp
# from each repo and compares it to the canonical version, turning silent drift loud.
#
# This is the *self-contained* prevention model (repos keep their own copy; we detect
# drift) rather than reusable-workflows (central copy; repos depend on it). See
# docs/adr/0001-bypass-audit-standard-and-drift-detection.md.
#
# USAGE:
#   scripts/check-pipeline-drift.sh <owner/repo> [<owner/repo> ...]
#   scripts/check-pipeline-drift.sh --fleet          # read repos from .helmet-fleet
#
# EXIT: 0 = no drift; 1 = at least one repo behind/unstamped/ahead; 2 = usage/setup error.
# REQUIRES: gh (authenticated), jq.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
WORKFLOW_PATH=".github/workflows/bypass-audit.yml"
FLEET_FILE="$REPO_ROOT/.helmet-fleet"

# Canonical version = the `# helmet-pipeline:` stamp in helmet's OWN bypass-audit.yml
# (the template itself), NOT the plugin version. The stamp is bumped only when the
# template changes, so an unrelated plugin version bump can't manufacture false drift.
CANON_FILE="$REPO_ROOT/$WORKFLOW_PATH"
CANON=$(sed -n 's/^# helmet-pipeline: v\([0-9][0-9.]*\).*/\1/p' "$CANON_FILE" 2>/dev/null | head -1)
if [[ -z "$CANON" ]]; then
  echo "ERROR: no '# helmet-pipeline: vX.Y.Z' stamp found in $CANON_FILE (the canonical template)" >&2
  exit 2
fi

# Resolve the repo list (explicit args, or --fleet from .helmet-fleet).
repos=()
if [[ "${1:-}" == "--fleet" ]]; then
  if [[ ! -f "$FLEET_FILE" ]]; then
    echo "ERROR: --fleet given but $FLEET_FILE not found (see .helmet-fleet.example)" >&2
    exit 2
  fi
  while IFS= read -r line; do
    line="${line%%#*}"                       # strip comments
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [[ -n "$line" ]] && repos+=("$line")
  done < "$FLEET_FILE"
elif [[ "$#" -gt 0 ]]; then
  repos=("$@")
fi
if [[ "${#repos[@]}" -eq 0 ]]; then
  echo "Usage: $0 <owner/repo> [<owner/repo> ...] | --fleet" >&2
  exit 2
fi

printf 'Canonical helmet-pipeline version: v%s\n\n' "$CANON"
printf '%-34s %-12s %s\n' "REPO" "STAMP" "STATUS"

current=0; behind=0; ahead=0; missing=0
for repo in "${repos[@]}"; do
  raw=$(gh api "repos/$repo/contents/$WORKFLOW_PATH" -H "Accept: application/vnd.github.raw" 2>/dev/null || true)
  if [[ -z "$raw" ]]; then
    printf '%-34s %-12s %s\n' "$repo" "-" "not found / no access (verify)"
    missing=$((missing + 1))
    continue
  fi
  stamp=$(printf '%s\n' "$raw" | sed -n 's/^# helmet-pipeline: v\([0-9][0-9.]*\).*/\1/p' | head -1)
  if [[ -z "$stamp" ]]; then
    printf '%-34s %-12s %s\n' "$repo" "unstamped" "drift: no version stamp (pre-detection)"
    behind=$((behind + 1))
    continue
  fi
  if [[ "$stamp" == "$CANON" ]]; then
    printf '%-34s %-12s %s\n' "$repo" "v$stamp" "current"
    current=$((current + 1))
    continue
  fi
  # Not equal: decide behind vs ahead via version sort (separate command — SC2312).
  oldest=$(printf '%s\n%s\n' "$stamp" "$CANON" | sort -V | head -1)
  if [[ "$oldest" == "$stamp" ]]; then
    printf '%-34s %-12s %s\n' "$repo" "v$stamp" "BEHIND (canonical v$CANON)"
    behind=$((behind + 1))
  else
    printf '%-34s %-12s %s\n' "$repo" "v$stamp" "ahead of canonical (investigate)"
    ahead=$((ahead + 1))
  fi
done

printf '\n%d current, %d behind/unstamped, %d ahead, %d not-found.\n' \
  "$current" "$behind" "$ahead" "$missing"
if [[ "$behind" -gt 0 || "$ahead" -gt 0 ]]; then
  echo "Action needed: re-run helmet onboarding on behind/unstamped repos; investigate any 'ahead'."
  exit 1
fi
if [[ "$missing" -gt 0 ]]; then
  echo "INCOMPLETE: $missing repo(s) could not be read (not found / no access) — cannot certify them as current. Verify access and re-run."
  exit 1
fi
echo "No drift detected."
