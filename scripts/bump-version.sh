#!/usr/bin/env bash
# Bump packaging/ to the newest claude-desktop in Anthropic's apt index.
#
# Rewrites, in lockstep:
#   packaging/claude-desktop.spec   Version, %global deb_sha256_<arch>, Release->0, %changelog
#   packaging/_service              download_url url + filename, per architecture
#
# The checksums come straight from the apt Packages indexes (field "SHA256:"),
# so this never downloads the 166 MB .debs. OBS fetches them at build time and
# the spec's %prep verifies the one it unpacks against deb_sha256_<arch>.
#
# Only a version that is published for every architecture in ARCHES is
# considered, so the amd64 and arm64 builds always come from the same release.
#
# Usage:
#   scripts/bump-version.sh [VERSION]     # default: newest in all indexes
#   scripts/bump-version.sh --commit ...  # also `git add` + `git commit`
#
# Exit status: 0 and prints "bumped <old> -> <new>" on a change,
#              0 and prints "up to date (<version>)" when already current.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$REPO_ROOT/packaging/claude-desktop.spec"
SERVICE="$REPO_ROOT/packaging/_service"
APT_BASE="https://downloads.claude.ai/claude-desktop/apt/stable"
ARCHES=(amd64 arm64)

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

# Parse each index into "version<TAB>sha256<TAB>filename" rows, one per stanza.
declare -A rows
for arch in "${ARCHES[@]}"; do
  index="$APT_BASE/dists/stable/main/binary-$arch/Packages"
  rows[$arch]=$(curl -fsSL "$index" | awk '
    /^Package: claude-desktop$/ { inpkg=1; v=s=f=""; next }
    inpkg && /^Version: /        { v=$2 }
    inpkg && /^SHA256: /         { s=$2 }
    inpkg && /^Filename: /       { f=$2 }
    inpkg && /^$/                { if (v) print v "\t" s "\t" f; inpkg=0 }
    END                         { if (inpkg && v) print v "\t" s "\t" f }
  ')
  [ -n "${rows[$arch]}" ] || { echo "no claude-desktop entries in $index" >&2; exit 1; }
done

# Versions published for every architecture.
common=$(cut -f1 <<<"${rows[${ARCHES[0]}]}" | sort -u)
for arch in "${ARCHES[@]:1}"; do
  common=$(comm -12 <(echo "$common") <(cut -f1 <<<"${rows[$arch]}" | sort -u))
done
[ -n "$common" ] || { echo "no version is published for all of: ${ARCHES[*]}" >&2; exit 1; }

if [ -n "$want" ]; then
  grep -qxF "$want" <<<"$common" \
    || { echo "version $want not found in the index of every architecture" >&2; exit 1; }
  new="$want"
else
  new=$(sort -V <<<"$common" | tail -1)
fi

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
declare -A sha fname
for arch in "${ARCHES[@]}"; do
  row=$(awk -F'\t' -v w="$new" '$1==w' <<<"${rows[$arch]}" | head -1)
  sha[$arch]=$(cut -f2 <<<"$row")
  fname[$arch]=$(basename "$(cut -f3 <<<"$row")")
  echo "  $arch sha256   ${sha[$arch]}"
  echo "  $arch filename ${fname[$arch]}"
done

# --- rewrite the spec ------------------------------------------------------
tmp=$(mktemp)
cp "$SPEC" "$tmp"
for arch in "${ARCHES[@]}"; do
  sed -i "s/^%global deb_sha256_${arch} .*/%global deb_sha256_${arch} ${sha[$arch]}/" "$tmp"
done
awk -v new="$new" '
  /^Version:[[:space:]]/  { print "Version:        " new; next }
  /^Release:[[:space:]]/  { print "Release:        0"; next }
  { print }
' "$tmp" > "$tmp.v"

entry="* $(LC_ALL=C date '+%a %b %d %Y') jeroen <jeroen@hierynomus.com> - ${new}-0
- Update to upstream ${new}"
awk -v e="$entry" '
  { print }
  /^%changelog$/ && !done { print e; print ""; done=1 }
' "$tmp.v" > "$SPEC"
rm -f "$tmp" "$tmp.v"

# --- rewrite _service ----------------------------------------------------
for arch in "${ARCHES[@]}"; do
  url="$APT_BASE/pool/main/c/claude-desktop/${fname[$arch]}"
  sed -i \
    -e "s#<param name=\"url\">.*_${arch}\.deb</param>#<param name=\"url\">${url}</param>#" \
    -e "s#<param name=\"filename\">.*_${arch}\.deb</param>#<param name=\"filename\">${fname[$arch]}</param>#" \
    "$SERVICE"
done

echo "bumped $current -> $new"

if [ "$commit" -eq 1 ]; then
  cd "$REPO_ROOT"
  git add packaging/claude-desktop.spec packaging/_service
  msg="claude-desktop ${new}: update to upstream release

Automated bump from Anthropic's apt index.
SHA256 (verified in %prep at build time):"
  for arch in "${ARCHES[@]}"; do
    msg+="
  ${arch} ${sha[$arch]}"
  done
  git commit -m "$msg"
  echo "committed"
fi
