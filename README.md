# keys.aswincloud.com

Public SSH keys, served so a fresh machine can be set up with one command.
Self-hosted equivalent of `github.com/<user>.keys`.

    curl -fsSL keys.aswincloud.com/install | sh

## Getting the keys

    curl keys.aswincloud.com                          # print them
    curl keys.aswincloud.com >> ~/.ssh/authorized_keys
    wget -O- keys.aswincloud.com                      # print them
    wget --content-disposition keys.aswincloud.com    # saves as ./authorized_keys

**Plain `wget keys.aswincloud.com` writes `index.html`.** The response does set
`Content-Disposition: filename="authorized_keys"`, but wget ignores that header
unless `--content-disposition` is passed. Use `curl`, or `wget -O-`.

`http://` works — the zone redirects to HTTPS and both clients follow it.

## Routes

| route | what it returns |
|---|---|
| `/` | the keys, `text/plain`, `authorized_keys` format |
| `/fingerprints` | SHA256 fingerprints, same format as `ssh-keygen -lf` |
| `/install` | POSIX-sh installer, idempotent |

## `/install`

Appends only keys that are not already present, matching on the base64 blob rather
than the whole line — the same key with a different comment is the same key, and
appending it again would be a second way in that you cannot see. Creates `~/.ssh`
at 700 and `authorized_keys` at 600. Re-run it after adding a laptop; it tops the
file up instead of duplicating it.

It is `#!/bin/sh`, not bash: the machines this runs on first are often minimal
images where `/bin/sh` is dash.

## Adding or removing a key

Edit `keys.txt` and deploy. That is the entire workflow — nothing else references
the list.

    vi keys.txt                     # add: ssh-ed25519 AAAA... aswin@NewLaptop
    sh scripts/fingerprints.sh      # regenerate fingerprints.txt
    npm run deploy
    npm run check                   # verifies production

Commit `keys.txt` and `fingerprints.txt` together — `validate.sh` refuses to build
while they disagree.

Or edit `keys.txt` on GitHub and let Workers Builds deploy it — useful precisely
because this endpoint exists to set up *other* machines, and you may not be at the
one holding the repo.

Removing is the same: delete the line and deploy.

Existing machines are unaffected by a deploy — their `authorized_keys` is already
written. To push a new key out to machines already set up, re-run the installer
there; it appends only what is missing:

    curl -fsSL keys.aswincloud.com/install | sh

Keep the comment on each line, and make it a **machine name, not an email**. Two
separate reasons:

- It is what makes the file auditable later: on the target machine you can
  `grep -v 'aswin@Aswin-Laptop' ~/.ssh/authorized_keys` to drop one machine. An
  email address does not tell you which laptop to retire. A key with no comment at
  all is one you cannot retire with confidence — which is why `validate.sh`
  rejects it.
- This repo and the endpoint are public. A comment is published verbatim, so an
  address put there is an address published.

The comment has no effect on authentication. An `authorized_keys` line is
`type base64-key [comment]`, and `sshd` compares only the base64 key material —
the SSH wire format inside it holds just the algorithm name and the raw public
key, with no field for a comment. Renaming one changes nothing about who can log
in; the fingerprint is identical.

### Pinned fingerprints

`fingerprints.txt` lists the SHA256 of every key in `keys.txt`, and `validate.sh`
refuses to build if the two disagree.

This exists because `ssh-keygen -l` validates *structure*, not authenticity. Flip a
single bit in a key's material and the line still parses, still reports
`256 ... (ED25519)`, and still passes every other check — only the fingerprint
moves. A key corrupted that way would deploy, land in a new machine's
`authorized_keys`, and silently not work, because no private key matches it. You
would believe you had four ways into that box and have three.

The pin also makes key changes reviewable. A reviewer skims past a 68-character
base64 blob; a changed `SHA256:` line is legible. Any change to key material has to
appear in `fingerprints.txt` in the same commit or the build fails.

    sh scripts/fingerprints.sh      # after any change to keys.txt

### A bad key cannot be deployed

`scripts/validate.sh` runs as wrangler's `build.command`, so it fires on
`wrangler deploy`, `npm run deploy` and inside Workers Builds. A non-zero exit
aborts the deploy. It rejects:

- a line that does not parse under `ssh-keygen -lf`
- a line with no comment
- duplicate key material (the same key twice under different comments — one way in,
  listed twice, and `/install` would silently keep only the first)

It is in `build.command` rather than an npm `predeploy` hook so it cannot be
sidestepped by calling wrangler directly.

This guard exists because the failure it prevents is silent and delayed. A truncated
paste or an editor-wrapped line bundles and deploys without complaint, then surfaces
when `sshd` on a brand-new machine rejects `authorized_keys` — the exact moment you
have no other way in.

## What is deliberately not here

`~/.ssh/authorized_keys` on the host holds more keys than this. These are served
(the table is checked against `keys.txt` in CI, so it cannot drift):

| type | comment |
|---|---|
| ed25519 | `aswin@AswinPC` |
| ed25519 | `aswin@Aswin-Laptop` |
| ed25519 | `aswin@Aswins-MacBook-Air.local` |
| ed25519 | `aswin@Aswin-Macbook-Pro` |
| ed25519 | `mail@ubuntu` (this server) |
| ed25519 | `aswin@truenas-host` (the TrueNAS host this server runs on) |

Excluded on purpose:

- `gh-actions-deploy`, `koyeb-tg-torrent-rename-bot` — service keys. Publishing them
  under "my keys" invites pasting a CI credential onto a personal machine.
- three unnamed `ecdsa-nistp256 @aswin` keys — unattributable, so not something to
  hand to a new machine as trusted.
- the RSA-3072 key on that same MacBook Pro — older and weaker than the ed25519 set.
- the six keys on `github.com/Aswinmcw.keys` — GitHub strips comments, so all six
  read `no comment` and none can be traced to a machine.

## Why the keys are bundled, not fetched

`keys.txt` is compiled into the Worker as a text module (the `Text` rule in
`wrangler.jsonc`). There is no KV, no D1 and no origin fetch, so the endpoint cannot
serve a stale, empty or half-written list — the three failure modes that matter when
the output is being appended to `authorized_keys` on a machine you are about to
depend on.

The `/fingerprints` route computes fingerprints from the same bundled bytes rather
than reading a second checked-in list, so the two can never disagree.

## This endpoint is a trust anchor

Whatever this returns becomes a login on every machine bootstrapped from it. That is
why the list is a committed file rather than a live proxy of an upstream account:
changing it requires a commit and a deploy, and shows up in `git log`.

Public keys are safe to publish — that is what they are for. The only real
disclosure is the comments, which name your machines and include a work email.

Verify a fetch before trusting it on a machine that matters:

    curl -s keys.aswincloud.com | ssh-keygen -lf -

and compare against `/fingerprints` or a fingerprint you already hold.

## CI

`.github/workflows/ci.yml` runs on every push and pull request. Everything in it is
offline — no secrets, no Cloudflare token — so there is nothing to gate it on.

**Checks**

- `validate.sh` — the same script the deploy runs, but now *before* merge,
  including the pinned-fingerprint comparison
- `check-readme.sh` — the README table must match `keys.txt`
- `tsc --noEmit`
- `wrangler deploy --dry-run` — config and bundling, without deploying

**E2E** — boots `wrangler dev` and runs `check.sh` against it: every line through
`ssh-keygen -lf`, `/fingerprints` against `/`, and `/install` twice in a scratch
`HOME` to prove idempotency and 600/700 modes.

`validate.sh` used to run only at deploy time, which is after merge. A malformed
`keys.txt` would land on `main` and be found in a build log. Production was never at
risk — a failed build does not deploy — but `main` was, and this file only has value
if it can be trusted.

## Checks

    npm run dev                              # wrangler dev
    sh scripts/check.sh http://localhost:8787
    sh scripts/check.sh                      # production

`check.sh` pipes the response through `ssh-keygen -lf`, confirms `/fingerprints`
agrees with `/`, and runs `/install` twice in a scratch `HOME` to prove it is
idempotent and that the file modes come out at 600/700. The `ssh-keygen` step is the
one that matters: a malformed line does not fail at fetch time, it fails later by
breaking `sshd` on the machine you just set up.
