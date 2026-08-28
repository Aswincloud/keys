#!/bin/bash
# bash, not sh: uses process substitution. CI-only, so no dash constraint —
# unlike the /install script, which must stay POSIX for minimal images.
# The README lists the served keys in a table. That table is documentation of a
# public endpoint, so it being wrong is worse than it being absent — a reader
# comparing it against what they fetched would conclude the endpoint was serving
# something it should not.
#
# It has already drifted once: a key was added to keys.txt and the table kept
# saying five. This compares the two and fails on any difference.
set -eu
cd "$(dirname "$0")/.."

keys=$(grep -v '^#' keys.txt | grep . | awk '{print $3}' | sort)
# Table rows look like:  | ed25519 | `comment` (optional note) |
table=$(grep -E '^\| *ed25519 *\|' README.md \
        | sed -e 's/.*`\([^`]*\)`.*/\1/' \
        | sort)

if [ "$keys" = "$table" ]; then
  echo "check-readme: table matches keys.txt ($(printf '%s\n' "$keys" | grep -c .) keys)"
  exit 0
fi

echo "check-readme: README table and keys.txt disagree."
echo
echo "  in keys.txt but not in the README table:"
printf '%s\n' "$(comm -23 <(printf '%s\n' "$keys") <(printf '%s\n' "$table"))" | grep . | sed 's/^/    /' || echo "    (none)"
echo "  in the README table but not in keys.txt:"
printf '%s\n' "$(comm -13 <(printf '%s\n' "$keys") <(printf '%s\n' "$table"))" | grep . | sed 's/^/    /' || echo "    (none)"
exit 1
