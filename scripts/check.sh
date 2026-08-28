#!/bin/sh
# Verifies a running endpoint actually serves usable keys. Point it at a local
# `wrangler dev` or at production:
#     sh scripts/check.sh http://localhost:8787
#     sh scripts/check.sh https://keys.aswincloud.com
#
# The check that matters is `ssh-keygen -lf`: a malformed line does not fail at
# fetch time, it fails later by breaking sshd on the machine you just set up.
set -eu
BASE="${1:-https://keys.aswincloud.com}"
fail=0

echo "== $BASE/ =="
body=$(curl -fsS "$BASE/")
printf '%s\n' "$body" | ssh-keygen -lf - || { echo "  FAIL: does not parse as SSH keys"; fail=1; }
n=$(printf '%s\n' "$body" | grep -c . || true)
echo "  $n keys"

echo "== headers =="
curl -fsS -D- -o /dev/null "$BASE/" | grep -iE '^(content-type|content-disposition|cache-control)' || fail=1

echo "== $BASE/fingerprints =="
curl -fsS "$BASE/fingerprints"

echo "== fingerprints agree with the served keys =="
a=$(curl -fsS "$BASE/" | ssh-keygen -lf - | awk '{print $2}' | sort)
b=$(curl -fsS "$BASE/fingerprints" | awk '{print $2}' | sort)
if [ "$a" = "$b" ]; then echo "  OK"; else echo "  FAIL: mismatch"; fail=1; fi

echo "== $BASE/install is idempotent =="
tmp=$(mktemp -d)
HOME="$tmp" sh -c "curl -fsSL '$BASE/install' | sh" >/dev/null
first=$(grep -c . "$tmp/.ssh/authorized_keys")
HOME="$tmp" sh -c "curl -fsSL '$BASE/install' | sh" >/dev/null
second=$(grep -c . "$tmp/.ssh/authorized_keys")
perm=$(stat -c '%a' "$tmp/.ssh/authorized_keys")
dperm=$(stat -c '%a' "$tmp/.ssh")
echo "  run1=$first run2=$second  authorized_keys=$perm .ssh=$dperm"
[ "$first" = "$second" ] || { echo "  FAIL: not idempotent"; fail=1; }
[ "$perm" = "600" ] || { echo "  FAIL: authorized_keys should be 600"; fail=1; }
[ "$dperm" = "700" ] || { echo "  FAIL: .ssh should be 700"; fail=1; }
rm -rf "$tmp"

echo
[ "$fail" = 0 ] && echo "ALL CHECKS PASSED" || { echo "CHECKS FAILED"; exit 1; }
