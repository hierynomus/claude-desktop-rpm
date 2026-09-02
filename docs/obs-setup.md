# OBS SCM/CI setup (one-time)

How `home:hierynomus/claude-desktop` on build.opensuse.org is wired to this
GitHub repo. You do this once. After that the flow is just: merge a PR →
OBS rebuilds the signed RPM.

## Model

- **Package source = this git repo**, via `<scmsync>` in the package meta
  (`obs-scm-bridge`). No more `osc ci`.
- **`packaging/` subdir** holds the build recipe: `claude-desktop.spec` +
  `_service`. `<scmsync>` points at `…?subdir=packaging#main`.
- **The 166 MB `.deb` is never in git.** `_service` runs `download_url` at
  build time; `%prep` verifies its SHA256 against the value Anthropic
  publishes in their apt `Packages` index.
- **`.obs/workflows.yml`** (repo root — OBS always reads it from there, not
  from `packaging/`) drives **pull-request builds**: each PR is branched
  into `home:hierynomus:ci`, built, and the result is reported back onto
  the PR as a commit status.
- **Push to `main`** needs no workflow step: OBS re-syncs the scmsync
  mirror and rebuilds `home:hierynomus/claude-desktop` on its own.
- **`.github/workflows/upstream-bump.yml`** opens a bump PR when Anthropic
  ships a new version. It needs no OBS credentials.

```
Anthropic apt index ──(daily cron)──> bump PR ──> OBS PR build (home:hierynomus:ci)
                                          │              │ status
                                          ▼              ▼
                                        merge ──> scmsync sync ──> home:hierynomus/claude-desktop
                                                                          │
                                                          download.opensuse.org/repositories/home:hierynomus/…
```

## Steps

### 1. OBS side (scriptable)

```
scripts/obs-bootstrap.sh
```

Idempotent. Creates `home:hierynomus:ci` and sets

```xml
<scmsync>https://github.com/hierynomus/claude-desktop-rpm?subdir=packaging#main</scmsync>
```

on `home:hierynomus/claude-desktop` (via `osc meta pkg … -F -`).

Or by hand: `osc meta pkg home:hierynomus claude-desktop -e` and add the
`<scmsync>` element.

### 2. GitHub PAT for OBS

Fine-grained token on `hierynomus/claude-desktop-rpm`:

- **Contents:** read-only
- **Commit statuses:** read/write  (so OBS can report PR build results)

### 3. OBS workflow token

```
osc token --create --operation workflow --scm-token <GITHUB_PAT>
```

Prints a token **id** and **secret**. The id goes in the webhook URL; the
secret is stored server-side with the token.

(Also create a personal token under OBS *Profile → Tokens* if the workflow
token flow asks for one for status reporting — recent OBS versions fold
this into the `--scm-token` above.)

### 4. GitHub webhook

Repo **Settings → Webhooks → Add webhook**:

| field | value |
|---|---|
| Payload URL | `https://build.opensuse.org/trigger/workflow?id=<TOKEN_ID>` |
| Content type | `application/json` |
| SSL verification | enabled |
| Events | *Let me select* → **Pushes** and **Pull requests** |

### 5. Verify

- Push a trivial commit to `main` → `osc results home:hierynomus claude-desktop`
  should show a rebuild.
- Open a throwaway PR → an OBS check appears on it, building in
  `home:hierynomus:ci`.

## Migrating from the old osc-committed package

The package previously had plain source revisions (`claude-desktop.spec`,
`_service`, `_servicedata.xml` committed via `osc ci`). Setting `<scmsync>`
switches it to git-backed mode; the old revisions stay in history but are
no longer the source. Nothing to delete. The old working copy under
`obs/home:hierynomus/` in git history is obsolete.

`_servicedata.xml` is gone on purpose: `download_url` does not read it
(it is a plain `wget`), so the sha512 pin it carried never did anything.
Integrity now lives in `%prep`.

## Install on a desktop

```
sudo zypper ar https://download.opensuse.org/repositories/home:hierynomus/openSUSE_Leap_16.0/home:hierynomus.repo
sudo zypper refresh
sudo zypper install claude-desktop
```
