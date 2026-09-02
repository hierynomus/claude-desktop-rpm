#!/usr/bin/env bash
# Bump packaging/ to the newest claude-desktop in Anthropic's apt index.
#
# Rewrites, in lockstep:
#   packaging/claude-desktop.spec   Version, %global deb_sha256, Release->1, %changelog
#   packaging/_service              download_url url + filename
#
# The checksum comes straight from the apt Packages index (field "SHA256:"),
# so this never downloads the 166 MB .deb. OBS fetches it at build time and
# the spec's %prep verifies it against deb_sha256.
#
# Usage:
#   scripts/bump-version.sh [VERSION]     # default: newest in the index
#   scripts/bump-version.sh --commit ...  # also `git add` + `git commit`
#
# Exit status: 0 and prints "bumped <old> -> <new>" on a change,
#              0 and prints "up to date (<version>)" when already current.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$REPO_ROOT/packaging/claude-desktop.spec"
SERVICE="$REPO_ROOT/packaging/_service"
APT_BASE="https://downloads.claude.ai/claude-desktop/apt/stable"
INDEX="$APT_BASE/dists/stable/main/binary-amd64/Packages"

commit=0
want=""
for arg in "$@"; do
  case "$arg" in
    --commit) commit=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *)  want="$arg" ;;
  esac
done

current=$(sed -n 's/^Version:[[:space:]]*//p' "$SPEC")
[ -n "$current" ] || { echo "cannot read Version from $SPEC" >&2; exit 1; }

# Parse the index into "version<TAB>sha256<TAB>filename" rows, one per stanza.
rows=$(curl -fsSL "$INDEX" | awk '
  /^Package: claude-desktop$/ { inpkg=1; v=s=f=""; next }
  inpkg && /^Version: /        { v=$2 }
  inpkg && /^SHA256: /         { s=$2 }
  inpkg && /^Filename: /       { f=$2 }
  inpkg && /^$/                { if (v) print v "\t" s "\t" f; inpkg=0 }
  END                         { if (inpkg && v) print v "\t" s "\t" f }
')
[ -n "$rows" ] || { echo "no claude-desktop entries in $INDEX" >&2; exit 1; }

if [ -n "$want" ]; then
  row=$(awk -F'\t' -v w="$want" '$1==w' <<<"$rows" | head -1)
  [ -n "$row" ] || { echo "version $want not found in the index" >&2; exit 1; }
else
  row=$(sort -V -t'	' -k1,1 <<<"$rows" | tail -1)
fi

new=$(cut -f1 <<<"$row")
sha=$(cut -f2 <<<"$row")
fname=$(basename "$(cut -f3 <<<"$row")")
url="$APT_BASE/pool/main/c/claude-desktop/$fname"

if [ "$new" = "$current" ]; then
  echo "up to date ($current)"
  exit 0
fi

# Guard against an accidental downgrade (e.g. a bad --version arg).
if [ "$(printf '%s\n%s\n' "$current" "$new" | sort -V | tail -1)" != "$new" ]; then
  echo "refusing to move $current -> $new (not newer)" >&2
  exit 1
fi

echo "bumping $current -> $new"
echo "  sha256   $sha"
echo "  filename $fname"

# --- rewrite the spec ------------------------------------------------------
tmp=$(mktemp)
awk -v new="$new" -v sha="$sha" '
  /^%global deb_sha256 / { print "%global deb_sha256 " sha; next }
  /^Version:[[:space:]]/  { print "Version:        " new; next }
  /^Release:[[:space:]]/  { print "Release:        1"; next }
  { print }
' "$SPEC" > "$tmp"

entry="* $(LC_ALL=C date '+%a %b %d %Y') jeroen <ajvanerp@gmail.com> - ${new}-1
- Update to upstream ${new}"
awk -v e="$entry" '
  { print }
  /^%changelog$/ && !done { print e; print ""; done=1 }
' "$tmp" > "$SPEC"
rm -f "$tmp"

# --- rewrite _service ----------------------------------------------------
sed -i \
  -e "s#<param name=\"url\">.*</param>#<param name=\"url\">${url}</param>#" \
  -e "s#<param name=\"filename\">.*</param>#<param name=\"filename\">${fname}</param>#" \
  "$SERVICE"

echo "bumped $current -> $new"

if [ "$commit" -eq 1 ]; then
  cd "$REPO_ROOT"
  git add packaging/claude-desktop.spec packaging/_service
  git commit -m "claude-desktop ${new}: update to upstream release

Automated bump from Anthropic's apt index.
SHA256 ${sha} (verified in %prep at build time)."
  echo "committed"
fi
