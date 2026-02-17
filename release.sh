#!/bin/bash
set -e

PKGNAME=$(basename "$PWD")
VERSION=$(git cliff --bumped-version | cut -dv -f2)

echo "Creating release for $PKGNAME v$VERSION..."

# Update version in shard.yml
sed "s/^version:.*$/version: $VERSION/g" -i shard.yml

# Run lint check FIRST (fast operation)
echo "Running lint check..."
if ameba --fix src/ 2>&1 | grep -q "^E"; then
  echo "❌ Lint errors found. Please fix them before releasing."
  exit 1
fi

echo "✓ Lint checks passed (warnings are ok)"

# Build static binaries (slow operation, done after lint)
echo "Building static binaries..."
./build_static.sh

# Create commit
git add shard.yml
git commit -m "bump: Release v$VERSION" || echo "No version changes to commit"

# Create tag
git tag "v$VERSION"

# Push tag
git push --tags

# Create GitHub release
gh release create "v$VERSION" \
  "dist/$PKGNAME-linux-amd64" \
  "dist/$PKGNAME-linux-arm64" \
  --title "Release v$VERSION" \
  --notes "$(git cliff -l -s all)"

echo "✓ Released v$VERSION"
