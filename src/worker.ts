// Serves the SSH public keys used to log in, so a fresh machine can be set up with
// one command. Self-hosted equivalent of github.com/<user>.keys.
//
// The keys are BUNDLED, not fetched: keys.txt becomes part of the Worker at build
// time. There is no KV, no D1 and no origin, so this endpoint has no runtime
// dependency that could serve a stale, empty or half-written list — the three
// failure modes that actually matter when the output is being appended to
// authorized_keys on a machine you are about to depend on.
import KEYS_FILE from "../keys.txt";

const ORIGIN = "https://keys.aswincloud.com";

// Comments and blank lines are for humans reading keys.txt; strip them for anything
// that needs the keys themselves.
function keyLines(): string[] {
  return KEYS_FILE.split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith("#"));
}

// OpenSSH fingerprint: base64 of the SHA-256 over the raw key blob, unpadded.
// Computed here rather than baked into keys.txt so the two can never disagree —
// a fingerprint list that is generated separately is a fingerprint list that goes
// stale the first time someone edits one file and not the other.
async function fingerprint(b64: string): Promise<string> {
  const raw = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const digest = await crypto.subtle.digest("SHA-256", raw);
  const out = btoa(String.fromCharCode(...new Uint8Array(digest)));
  return "SHA256:" + out.replace(/=+$/, "");
}

function text(body: string, extra: Record<string, string> = {}, status = 200) {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "public, max-age=300",
      "x-content-type-options": "nosniff",
      ...extra,
    },
  });
}

// POSIX sh, not bash: the machines this runs on first are often minimal images
// where /bin/sh is dash. Appends only keys that are absent, so re-running after
// adding a laptop tops up the file instead of duplicating every line.
//
// The key list is delivered as a quoted heredoc rather than read from stdin,
// because under `curl … | sh` stdin is the script itself — a `while read` over
// stdin would eat the rest of the script.
function installScript(): string {
  return `#!/bin/sh
# curl -fsSL ${ORIGIN}/install | sh
set -eu

AK="$HOME/.ssh/authorized_keys"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
[ -f "$AK" ] || : > "$AK"
chmod 600 "$AK"

added=0
skipped=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in \\#*) continue ;; esac
  # Match on the base64 blob, not the whole line: the same key with a different
  # comment is the same key, and appending it again would be a duplicate login.
  blob=$(printf '%s' "$line" | awk '{print $2}')
  if grep -qF "$blob" "$AK" 2>/dev/null; then
    skipped=$((skipped + 1))
    continue
  fi
  printf '%s\\n' "$line" >> "$AK"
  added=$((added + 1))
done <<'KEYS_EOF'
${keyLines().join("\n")}
KEYS_EOF

echo "authorized_keys: $added added, $skipped already present -> $AK"
`;
}

export default {
  async fetch(request: Request): Promise<Response> {
    const { pathname } = new URL(request.url);

    if (request.method !== "GET" && request.method !== "HEAD") {
      return text("405 method not allowed\n", { allow: "GET, HEAD" }, 405);
    }

    if (pathname === "/" || pathname === "/keys") {
      // filename= is what makes `wget --content-disposition` save this as
      // authorized_keys. Plain `wget <url>` ignores the header and writes
      // index.html, which is why the README leads with curl.
      return text(keyLines().join("\n") + "\n", {
        "content-disposition": 'inline; filename="authorized_keys"',
      });
    }

    if (pathname === "/fingerprints") {
      const lines = await Promise.all(
        keyLines().map(async (l) => {
          const [type, b64, ...rest] = l.split(/\s+/);
          const bits = type === "ssh-ed25519" ? "256" : "";
          return `${bits} ${await fingerprint(b64)} ${rest.join(" ") || "(no comment)"} (${type})`.trim();
        }),
      );
      return text(lines.join("\n") + "\n");
    }

    if (pathname === "/install") {
      return text(installScript(), {
        "content-disposition": 'inline; filename="install.sh"',
        "cache-control": "public, max-age=60",
      });
    }

    return text(
      `404 not found\n\n  ${ORIGIN}/              the keys\n  ${ORIGIN}/fingerprints  SHA256 fingerprints\n  ${ORIGIN}/install       install script\n`,
      {},
      404,
    );
  },
};
