#!/usr/bin/env bash
# Build the RPM locally from packaging/, for testing before it hits OBS.
#
# Fetches the .deb that packaging/_service points at (the same file OBS
# would download), drops it in a throwaway rpmbuild tree, and builds the
# binary RPM. The spec's %prep verifies the SHA256, so a mismatch fails
# here exactly as it would on OBS.
#
# Usage: scripts/local-build.sh [output-dir]
#   output-dir  where to copy the finished .rpm (default: ./dist)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$REPO_ROOT/packaging/claude-desktop.spec"
SERVICE="$REPO_ROOT/packaging/_service"
OUTDIR="${1:-$REPO_ROOT/dist}"

command -v rpmbuild >/dev/null || { echo "rpmbuild not found (zypper in rpm-build)"; exit 1; }

url=$(sed -n 's#.*<param name="url">\(.*\)</param>.*#\1#p' "$SERVICE")
deb=$(basename "$url")
[ -n "$url" ] || { echo "could not read download url from $SERVICE"; exit 1; }

topdir=$(mktemp -d)
trap 'rm -rf "$topdir"' EXIT
mkdir -p "$topdir"/{SOURCES,BUILD,BUILDROOT,RPMS,SRPMS}

echo "==> fetching $deb"
curl -fSL --progress-bar "$url" -o "$topdir/SOURCES/$deb"

echo "==> rpmbuild -bb"
rpmbuild -bb --define "_topdir $topdir" "$SPEC"

mkdir -p "$OUTDIR"
find "$topdir/RPMS" -name '*.rpm' -exec cp -v {} "$OUTDIR/" \;
echo "==> done -> $OUTDIR"
