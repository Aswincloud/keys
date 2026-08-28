#!/bin/sh
# Refuses to build if keys.txt is not something sshd could load.
#
# Wired as wrangler's `build.command`, so it runs on `wrangler deploy`, on
# `npm run deploy` and inside Workers Builds — every path that can reach
# production. A non-zero exit here aborts the deploy.
#
# This exists because the failure it prevents is silent and delayed: a truncated
# paste or an editor-wrapped line bundles and deploys without complaint, and only
# surfaces later when sshd on a brand-new machine rejects authorized_keys — which
# is exactly the moment you have no other way in.
set -eu
cd "$(dirname "$0")/.."
F=keys.txt
fail=0
n=0

[ -f "$F" ] || { echo "validate: $F is missing"; exit 1; }

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ""|\#*) continue ;; esac
  n=$((n + 1))

  # Parses as a key at all?
  if ! printf '%s\n' "$line" | ssh-keygen -lf - >/dev/null 2>&1; then
    echo "validate: line $n does not parse as an SSH public key:"
    echo "    $(printf '%s' "$line" | cut -c1-72)..."
    fail=1
    continue
  fi

  # Has a comment? The README leans on comments for retiring a key later, so an
  # uncommented line is a key you cannot confidently remove.
  fields=$(printf '%s' "$line" | awk '{print NF}')
  if [ "$fields" -lt 3 ]; then
    echo "validate: line $n has no comment — add one so it can be identified later"
    fail=1
    continue
  fi

  # Is the comment an email address? This repo and the endpoint are both public,
  # so a comment is published verbatim. A work address was committed here once and
  # took a history rewrite and a repo re-create to remove; this is the guard that
  # stops it happening twice.
  #
  # A bare host with no dot (AswinPC, ubuntu, truenas-host) is a machine name and
  # fine. A dotted host is only fine if it is a non-routable local suffix, which
  # is what a Mac's Bonjour name looks like (Aswins-MacBook-Air.local).
  comment=$(printf '%s' "$line" | awk '{print $3}')
  case "$comment" in
    *@*)
      host=${comment#*@}
      case "$host" in
        *.local|*.lan|*.internal|*.home|*.arpa) : ;;
        *.*)
          echo "validate: line $n comment '$comment' looks like an email address."
          echo "           Comments are published verbatim — use a machine name."
          fail=1
          ;;
      esac
      ;;
  esac
done < "$F"

[ "$n" -gt 0 ] || { echo "validate: $F has no keys"; exit 1; }

# Duplicate blobs. Two lines with the same key and different comments are one way
# in listed twice, and /install would silently keep only the first.
dupes=$(grep -v '^#' "$F" | grep . | awk '{print $2}' | sort | uniq -d)
if [ -n "$dupes" ]; then
  echo "validate: duplicate key material:"
  printf '%s\n' "$dupes" | sed 's/^/    /'
  fail=1
fi

if [ "$fail" != 0 ]; then
  echo
  echo "validate: FAILED — not deploying."
  exit 1
fi

echo "validate: $n keys OK"
ssh-keygen -lf "$F" 2>/dev/null | sed 's/^/    /' || true
