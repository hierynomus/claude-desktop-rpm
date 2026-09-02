#!/usr/bin/env bash
# One-time OBS side of the SCM/CI setup. Idempotent; safe to re-run.
#
# Does the parts that can be scripted:
#   - ensures home:hierynomus:ci exists (PR branch target) with the same
#     Leap 16.0 / x86_64 repo as home:hierynomus
#   - points home:hierynomus/claude-desktop at this git repo via <scmsync>
#
# It does NOT create the workflow token or the GitHub webhook - those need
# a GitHub PAT and the GitHub UI. See docs/obs-setup.md for those steps.
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

cat <<'NEXT'

==> Scripted part done. Remaining manual steps (docs/obs-setup.md):

  1. GitHub: create a fine-grained PAT for hierynomus/claude-desktop-rpm
     with  Contents: read-only,  Commit statuses: read/write.

  2. OBS workflow token (feed it that PAT):
       osc token --create --operation workflow --scm-token <GITHUB_PAT>
     Note the token id it prints.

  3. GitHub -> repo Settings -> Webhooks -> Add webhook:
       Payload URL:  https://build.opensuse.org/trigger/workflow?id=<TOKEN_ID>
       Content type: application/json
       Events:       Pushes, Pull requests
       (the token's own secret authenticates; SSL verification on)

  4. Watch the first sync:
       osc results home:hierynomus claude-desktop
NEXT
