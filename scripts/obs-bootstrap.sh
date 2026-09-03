#!/usr/bin/env bash
# One-time OBS side of the SCM/CI setup. Idempotent; safe to re-run.
#
# Does the parts that can be scripted:
#   - ensures home:hierynomus:ci exists (PR branch target) with the same
#     Leap 16.0 / x86_64 repo as home:hierynomus
#   - points home:hierynomus/claude-desktop at this git repo via <scmsync>
#   - creates the runservice token (push -> rebuild)
#
# The workflow token and the two GitHub webhooks are manual - they need a
# GitHub PAT and the GitHub UI. See docs/obs-setup.md.
#
# Prereqs: osc installed and configured for build.opensuse.org.
# Usage:   scripts/obs-bootstrap.sh [git-url]
set -euo pipefail

PROJ="home:hierynomus"
CI_PROJ="home:hierynomus:ci"
PKG="claude-desktop"
GIT_URL="${1:-https://github.com/hierynomus/claude-desktop-rpm?subdir=packaging#main}"

command -v osc >/dev/null || { echo "osc not installed / not in PATH"; exit 1; }

echo "==> Ensuring $CI_PROJ exists (PR build target)"
if osc meta prj "$CI_PROJ" >/dev/null 2>&1; then
  echo "    already exists"
else
  osc meta prj "$CI_PROJ" -F - <<XML
<project name="$CI_PROJ">
  <title>claude-desktop PR builds</title>
  <description>Throwaway branch target for pull-request builds of $PROJ/$PKG (OBS SCM/CI workflow integration).</description>
  <person userid="hierynomus" role="maintainer"/>
  <repository name="openSUSE_Leap_16.0">
    <path project="openSUSE:Leap:16.0" repository="standard"/>
    <arch>x86_64</arch>
  </repository>
</project>
XML
  echo "    created"
fi

echo "==> Pointing $PROJ/$PKG at git via <scmsync>"
echo "    $GIT_URL"
current=$(osc meta pkg "$PROJ" "$PKG" 2>/dev/null || true)
if grep -qF "$GIT_URL" <<<"$current"; then
  echo "    scmsync already set"
else
  osc meta pkg "$PROJ" "$PKG" -F - <<XML
<package name="$PKG" project="$PROJ">
  <title>Desktop application for Claude.ai (Chat, Cowork, Code)</title>
  <description>Repackage of Anthropic's official Linux .deb as a native RPM for openSUSE. Source: $GIT_URL</description>
  <scmsync>$GIT_URL</scmsync>
</package>
XML
  echo "    set"
fi

echo
echo "==> Creating the runservice token (push -> scmsync re-sync + rebuild)"
osc token --create --operation runservice "$PROJ" "$PKG" 2>&1 || true

cat <<'NEXT'

==> Scripted part done. Remaining manual steps (docs/obs-setup.md):

  1. GitHub: create a fine-grained PAT for hierynomus/claude-desktop-rpm
     with  Contents: read-only,  Commit statuses: read/write.

  2. OBS workflow token for PR builds (feed it that PAT):
       osc token --create --operation workflow --scm-token <GITHUB_PAT>

  3. GitHub -> repo Settings -> Webhooks -> Add TWO webhooks
     (content type application/json, SSL on; the token string is the Secret):

       a) Payload URL: https://build.opensuse.org/trigger/webhook?id=<RUNSERVICE_TOKEN_ID>
          Events:      Pushes
       b) Payload URL: https://build.opensuse.org/trigger/workflow?id=<WORKFLOW_TOKEN_ID>
          Events:      Pull requests

     Why two: /trigger/workflow only runs .obs/workflows.yml (PR builds).
     /trigger/webhook (runservice) re-pulls the scmsync source on push.

  4. GitHub Settings -> Actions -> General -> Workflow permissions:
     enable "Allow GitHub Actions to create and approve pull requests".

  5. Verify (after a commit that touches packaging/):
       osc results home:hierynomus claude-desktop
       osc api /source/home:hierynomus/claude-desktop/_scmsync.obsinfo
     Force a sync by hand any time with:
       osc service remoterun home:hierynomus claude-desktop
NEXT
