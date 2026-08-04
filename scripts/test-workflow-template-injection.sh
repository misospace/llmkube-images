#!/usr/bin/env bash
# Regression test for issue #65: ensure the workflows listed in the issue
# do not reintroduce the suppressed template-injection pattern. The two
# workflows must:
#   1. Contain no `# zizmor: ignore[template-injection]` annotation.
#   2. Use the env-based pattern instead of direct `${{ }}` substitution
#      inside the body of a `run:` block.
#
# Exit non-zero if either workflow regresses.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Workflows fixed by issue #65.
WORKFLOWS=(
  ".github/workflows/vulnerability-scan.yaml"
  ".github/workflows/retry-release.yaml"
)

failures=0

# Strip `if:` lines before scanning so the only `${{ }}` we evaluate
# comes from `run:` block bodies. `if:` template expressions are
# expected to remain and are not the concern of this test.
for file in "${WORKFLOWS[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "FAIL: $file is missing"
    failures=$((failures + 1))
    continue
  fi

  # 1. The zizmor: ignore[template-injection] annotation must be gone.
  if grep -nF "zizmor: ignore[template-injection]" "$file" >/dev/null; then
    echo "FAIL: $file still contains '# zizmor: ignore[template-injection]'"
    grep -nF "zizmor: ignore[template-injection]" "$file" | sed 's/^/  /'
    failures=$((failures + 1))
  else
    echo "PASS: $file has no '# zizmor: ignore[template-injection]'"
  fi

  # 2. The body of every `run:` block must not contain a direct `${{ }}`
  #    template expression. We do this by extracting the lines that follow
  #    a `run:` key (preserving relative indentation) and grepping them.
  awk -v file="$file" '
    /^[ \t]*run: / {
      collecting = 1
      base_indent = -1
      next
    }
    collecting {
      # Skip blank lines; they are not part of the run block body.
      if ($0 ~ /^[ \t]*$/) { next }
      # Determine the indentation of the first non-blank line.
      if (base_indent == -1) {
        match($0, /^[ \t]*/)
        base_indent = RLENGTH
      }
      # If the line is at or past the run block base indentation, it is
      # still inside the block. Otherwise the block has ended.
      match($0, /^[ \t]*/)
      if (RLENGTH < base_indent) {
        collecting = 0
      } else {
        print file ":" NR ":" $0
      }
    }
  ' "$file" | grep -E '\${{' >/dev/null && {
    echo "FAIL: $file has a direct \${{ }} inside a run: block"
    awk -v file="$file" '
      /^[ \t]*run: / {
        collecting = 1
        base_indent = -1
        next
      }
      collecting {
        if ($0 ~ /^[ \t]*$/) { next }
        if (base_indent == -1) {
          match($0, /^[ \t]*/)
          base_indent = RLENGTH
        }
        match($0, /^[ \t]*/)
        if (RLENGTH < base_indent) {
          collecting = 0
        } else if ($0 ~ /\${{/) {
          print "  " file ":" NR ": " $0
        }
      }
    ' "$file"
    failures=$((failures + 1))
  } || echo "PASS: $file uses no direct \${{ }} inside run: blocks"
done

if (( failures > 0 )); then
  echo
  echo "Results: $failures failed"
  exit 1
fi

echo
echo "All tests passed!"
