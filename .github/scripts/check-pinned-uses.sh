#!/usr/bin/env bash
# Verify every uses: ref in GitHub Actions workflows is SHA-pinned (40-hex).
# Exemptions: local actions (./) and docker:// refs.
# Expected format: owner/action@<40-hex-sha> # vX.Y.Z (Dependabot reads the inline comment).
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
done < <(find .github/workflows .github/actions -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 2>/dev/null)
exit $status
