#!/usr/bin/env bash
#
# Re-extract gcc.c-torture from an upstream GCC tag into this repository.
#
#   ./sync-upstream.sh releases/gcc-16.2.0
#
# Uses a blobless (--filter=blob:none), shallow, sparse clone so only the
# ~2.4 MB of testsuite sources are downloaded rather than GCC's ~4 GB history.
# Rewrites the mirrored paths and PROVENANCE, then leaves the result in the
# working tree for review -- it never commits or pushes.

set -euo pipefail

UPSTREAM_REPO=https://github.com/gcc-mirror/gcc.git
UPSTREAM_SUBDIR=gcc/testsuite/gcc.c-torture

# Top-level paths owned by the mirror; everything else at the root is replaced
# wholesale on each sync.  Keep in sync with PROVENANCE's `mirror-owned`.
MIRROR_OWNED=(.gitattributes .gitignore LICENSE PROVENANCE README.md sync-upstream.sh)

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

TAG="${1:-}"
[ -n "$TAG" ] || die "usage: $0 <gcc-tag>   (e.g. releases/gcc-16.2.0)"

cd "$(dirname "$0")"
[ -d .git ] || die "must be run from the root of the mirror repository"
[ -f PROVENANCE ] || die "PROVENANCE missing -- refusing to run in an unexpected directory"

command -v git >/dev/null || die "git not found"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> cloning $UPSTREAM_REPO at $TAG (blobless, shallow, sparse)"
git -c advice.detachedHead=false clone --quiet --filter=blob:none --sparse \
    --depth 1 --branch "$TAG" "$UPSTREAM_REPO" "$TMP/gcc"
git -C "$TMP/gcc" sparse-checkout set "$UPSTREAM_SUBDIR" >/dev/null

SRC="$TMP/gcc/$UPSTREAM_SUBDIR"
[ -d "$SRC" ] || die "$UPSTREAM_SUBDIR not present at $TAG"
[ -f "$TMP/gcc/COPYING3" ] || die "COPYING3 not present at $TAG"

COMMIT="$(git -C "$TMP/gcc" rev-parse HEAD)"

echo "==> replacing mirrored paths"
# Remove every root entry that is not mirror-owned.  The glob skips dotfiles,
# so .git and .gitattributes are never at risk; dotfiles that ARE mirror-owned
# are listed above and skipped explicitly for clarity.
shopt -s nullglob
for path in *; do
    for owned in "${MIRROR_OWNED[@]}"; do
        [ "$path" = "$owned" ] && continue 2
    done
    rm -rf -- "$path"
done
shopt -u nullglob

cp -a "$SRC/." .
# GCC ships GPLv3 as COPYING3; store it as LICENSE so GitHub detects it.
cp -a "$TMP/gcc/COPYING3" LICENSE

echo "==> regenerating PROVENANCE"
MIRRORED_PATHS=()
for path in "$SRC"/*; do MIRRORED_PATHS+=("$(basename "$path")"); done

files=$(find "${MIRRORED_PATHS[@]}" -type f | wc -l)
bytes=$(find "${MIRRORED_PATHS[@]}" -type f -exec cat {} + | wc -c)
sha=$(find "${MIRRORED_PATHS[@]}" -type f -print0 \
      | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)

# Directories get a trailing slash in the human-readable listing.
listing=""
for path in "${MIRRORED_PATHS[@]}"; do
    if [ -d "$path" ]; then listing+="$path/ "; else listing+="$path "; fi
done
listing="${listing% }"

# Only advertise mirror-owned files that actually exist, so PROVENANCE never
# names a file the repository does not have.
OWNED_PRESENT=()
for owned in "${MIRROR_OWNED[@]}"; do
    [ -e "$owned" ] && OWNED_PRESENT+=("$owned")
done

cat > PROVENANCE <<EOF
# Provenance of the mirrored content
#
# Everything in this repository except the files listed under "mirror-owned"
# below is copied verbatim, without modification, from the GNU Compiler
# Collection source tree.  Regenerate with ./sync-upstream.sh <gcc-tag>.

upstream-project:  GNU Compiler Collection (GCC)
upstream-repo:     $UPSTREAM_REPO
upstream-tag:      $TAG
upstream-commit:   $COMMIT
upstream-subdir:   $UPSTREAM_SUBDIR
extracted-on:      $(date -u +%Y-%m-%d)

# Mirrored paths (repository root == contents of upstream-subdir)
mirrored-paths:    $listing
mirrored-files:    $files
mirrored-bytes:    $bytes

# LICENSE is GCC's top-level COPYING3 (GNU GPL v3), copied unmodified from the
# same upstream commit and renamed so GitHub's license detection picks it up.
license-file:      LICENSE

# Files added by this mirror and not present upstream.
mirror-owned:      ${OWNED_PRESENT[*]}

# sha256 over the mirrored paths, computed as:
#   find ${MIRRORED_PATHS[*]} -type f -print0 \\
#     | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum
mirrored-sha256:   $sha
EOF

echo
echo "==> done: $TAG ($COMMIT)"
echo "    $files files, $bytes bytes, sha256 $sha"
echo
git status --short --untracked-files=no | head -20
echo "    (review with 'git status' / 'git diff', then commit)"
