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
- **Push to `main`** is handled by a second webhook to a `runservice`
  token (`/trigger/webhook`), which makes OBS re-pull git and rebuild
  `home:hierynomus/claude-desktop`. `.obs/workflows.yml` is *not* consulted
  for pushes, so the workflow webhook alone does nothing on a push.
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

### 3. Two OBS tokens

They do different jobs and **you need both**:

```
# a) syncs the scmsync package + rebuilds on push to main
osc token --create --operation runservice home:hierynomus claude-desktop

# b) runs .obs/workflows.yml (the PR builds); feed it the GitHub PAT
osc token --create --operation workflow --scm-token <GITHUB_PAT>
```

Each prints an **id** and a **secret string**.

Why two: `/trigger/workflow` only executes `.obs/workflows.yml` steps. A
push to `main` matches no workflow there (the file only has a
`pull_request` workflow), so it would do nothing — the scmsync package
would never re-sync. The `runservice` token on `/trigger/webhook` is what
re-pulls git and rebuilds. (`osc service remoterun home:hierynomus
claude-desktop` is the manual equivalent — handy to force a sync.)

### 4. Two GitHub webhooks

Repo **Settings → Webhooks → Add webhook**, twice:

| # | Payload URL | Secret | Events |
|---|---|---|---|
| 1 | `https://build.opensuse.org/trigger/webhook?id=<RUNSERVICE_TOKEN_ID>` | runservice token string | **Pushes** |
| 2 | `https://build.opensuse.org/trigger/workflow?id=<WORKFLOW_TOKEN_ID>` | workflow token string | **Pull requests** |

Both: content type `application/json`, SSL verification on.

### 5. Verify

- Push a trivial commit to `main` → `osc results home:hierynomus claude-desktop`
  shows a rebuild; `osc api /source/home:hierynomus/claude-desktop/_scmsync.obsinfo`
  shows the new commit sha.
- Open a throwaway PR → an OBS check appears on it, building in
  `home:hierynomus:ci`.
- Stuck? `osc service remoterun home:hierynomus claude-desktop` forces a sync.

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
