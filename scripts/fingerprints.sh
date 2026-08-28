#!/bin/sh
# Regenerates fingerprints.txt from keys.txt.
#
#     sh scripts/fingerprints.sh
#
# Run this after changing keys.txt and commit both files together. validate.sh
# refuses to build while the two disagree, so the fingerprint of any key that
# changed lands in the same diff as the change -- which is the point. A reviewer
# skims past a 68-character base64 blob; a changed SHA256 line is legible.
set -eu
cd "$(dirname "$0")/.."

{
  echo "# Fingerprints of every key in keys.txt. Generated -- do not hand-edit."
  echo "# Regenerate with: sh scripts/fingerprints.sh"
  echo "#"
  echo "# These exist so a corrupted key cannot deploy. ssh-keygen -l validates"
  echo "# structure, not authenticity: flip one bit in the key material and it still"
  echo "# parses, still reports 256-bit ED25519, and still passes -- only the"
  echo "# fingerprint changes. Pinning them turns 'these look like keys' into 'these"
  echo "# are exactly the keys we intend'."
  echo
  ssh-keygen -lf keys.txt | awk '{print $2"  "$3}'
} > fingerprints.txt

echo "fingerprints.sh: wrote $(grep -v '^#' fingerprints.txt | grep -c .) fingerprints"
grep -v '^#' fingerprints.txt | grep . | sed 's/^/    /'
