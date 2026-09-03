# OBS setup (one-time)

Wires `home:hierynomus/claude-desktop` on build.opensuse.org to this repo.
Done once; after that a push to `main` rebuilds and PRs get test-built.

## Model

- **Package source is this git repo**, via `<scmsync>` in the package meta
  (`obs-scm-bridge`) — no `osc ci`. The `<scmsync>` URL carries
  `?subdir=packaging#main`, so only `packaging/` is packaged; a push that
  doesn't touch `packaging/` regenerates an identical tree and correctly
  does not rebuild.
- **The 166 MB `.deb` is never in git.** `packaging/_service` runs
  `download_url` at build time; `%prep` verifies its SHA256 against the
  value in Anthropic's apt `Packages` index.
- **`.obs/workflows.yml`** (repo root) drives **PR builds**: each PR is
  branched into `home:hierynomus:ci:hierynomus:claude-desktop-rpm:PR-<n>`,
  built with publishing disabled, and the result is posted back to the PR
  as status checks. The branch project auto-deletes when the PR closes.
- **`.github/workflows/upstream-bump.yml`** opens a bump PR when Anthropic
  ships a newer build. Needs no OBS credentials.

```
Anthropic apt index ─(daily cron)→ bump PR ─→ OBS PR build (status checks)
                                      │
                                    merge ─→ push webhook ─→ rebuild ─→
                                      download.opensuse.org/repositories/home:hierynomus/
```

## Steps

### 1. OBS side (scriptable)

```
scripts/obs-bootstrap.sh
```

Idempotent. Creates `home:hierynomus:ci` (the PR branch target) and sets

```xml
<scmsync>https://github.com/hierynomus/claude-desktop-rpm?subdir=packaging#main</scmsync>
```

on `home:hierynomus/claude-desktop`. It also creates the `runservice`
token (step 3a). By hand: `osc meta pkg home:hierynomus claude-desktop -e`.

### 2. GitHub PAT for OBS

Fine-grained token on `hierynomus/claude-desktop-rpm`:

- **Contents:** read-only
- **Commit statuses:** read/write  (so OBS can report PR build results)

### 3. Two OBS tokens

```
# a) push to main -> re-pull git + rebuild
osc token --create --operation runservice home:hierynomus claude-desktop

# b) PR events -> run .obs/workflows.yml  (feed it the PAT from step 2)
osc token --create --operation workflow --scm-token <GITHUB_PAT>
```

Each prints an **id** and a **secret string**. Two are needed because the
two `/trigger/*` endpoints do different things: `/trigger/webhook`
(runservice) re-pulls the scmsync source and rebuilds; `/trigger/workflow`
only executes `.obs/workflows.yml` steps, which are PR-only.

### 4. Two GitHub webhooks

Repo **Settings → Webhooks → Add webhook**, twice. Content type
`application/json`, SSL verification on, the token **string** in *Secret*:

| Payload URL | Events |
|---|---|
| `https://build.opensuse.org/trigger/webhook?id=<RUNSERVICE_TOKEN_ID>` | Pushes |
| `https://build.opensuse.org/trigger/workflow?id=<WORKFLOW_TOKEN_ID>` | Pull requests |

### 5. GitHub repo setting

**Settings → Actions → General → Workflow permissions:** enable *Allow
GitHub Actions to create and approve pull requests* (for `upstream-bump`).

## Verify

- Push a commit that changes `packaging/` → `_scmsync.obsinfo` advances and
  a build starts:
  `osc api /source/home:hierynomus/claude-desktop/_scmsync.obsinfo`
- Open a throwaway PR → an "OBS" status check appears and goes green.
- Force a sync by hand if ever needed:
  `osc service remoterun home:hierynomus claude-desktop`

## Install on a desktop

```
sudo zypper ar https://download.opensuse.org/repositories/home:hierynomus/openSUSE_Leap_16.0/home:hierynomus.repo
sudo zypper refresh
sudo zypper install claude-desktop
```
