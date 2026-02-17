#!/bin/bash
set -e

echo "Building static binaries for Crybot..."

# Setup QEMU for multi-arch builds
docker run --rm --privileged \
  multiarch/qemu-user-static \
  --reset -p yes

# Build for AMD64
echo ""
echo "Building for AMD64..."
docker build . -f Dockerfile.static -t crybot-builder-amd64 \
  --platform linux/amd64

docker run -ti --rm \
  -v "$PWD":/app \
  --user="$(id -u):$(id -g)" \
  crybot-builder-amd64 \
  /bin/sh -c "cd /app && shards build --without-development --release --static"

# Copy and rename the AMD64 binary
mkdir -p dist
cp bin/crybot dist/crybot-linux-amd64
echo "✓ Built: dist/crybot-linux-amd64"

# Build for ARM64
echo ""
echo "Building for ARM64..."
docker build . -f Dockerfile.static -t crybot-builder-arm64 \
  --platform linux/arm64

docker run -ti --rm \
  -v "$PWD":/app \
  --user="$(id -u):$(id -g)" \
  crybot-builder-arm64 \
  /bin/sh -c "cd /app && shards build --without-development --release --static"

# Copy and rename the ARM64 binary
cp bin/crybot dist/crybot-linux-arm64
echo "✓ Built: dist/crybot-linux-arm64"

# Show file sizes
echo ""
echo "Binary sizes:"
ls -lh dist/

echo ""
echo "Static binaries built successfully!"
echo "You can now ship these binaries - they have no external dependencies."
