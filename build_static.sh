#!/bin/bash
set -e

echo "Building static binaries for Crybot..."

# Build for AMD64
echo ""
echo "Building for AMD64..."
docker build . -f Dockerfile.static -t crybot-builder-amd64 \
  --platform linux/amd64 \
  --progress=plain

docker run --rm \
  -v "$PWD":/app \
  --user="$(id -u):$(id -g)" \
  crybot-builder-amd64 \
  /bin/sh -c "cd /app && shards build --without-development --release --static --no-debug '-Dpreview_mt' '-Dexecution_context' 'crybot'"

# Copy and compress the AMD64 binary
mkdir -p dist
cp bin/crybot dist/crybot-linux-amd64
upx --best --lzma dist/crybot-linux-amd64
echo "✓ Built: dist/crybot-linux-amd64 ($(du -h dist/crybot-linux-amd64 | cut -f1))"

# Build for ARM64 with retry
echo ""
echo "Building for ARM64..."
docker build . -f Dockerfile.static -t crybot-builder-arm64 \
  --platform linux/arm64 \
  --progress=plain

# ARM64 builds sometimes fail due to QEMU, so retry once
if docker run --rm \
  -v "$PWD":/app \
  --user="$(id -u):$(id -g)" \
  crybot-builder-arm64 \
  /bin/sh -c "cd /app && shards build --without-development --release --static --no-debug '-Dpreview_mt' '-Dexecution_context' 'crybot'"; then
  echo "✓ ARM64 build succeeded on first try"
else
  echo "⚠ ARM64 build failed, retrying..."
  sleep 2
  docker run --rm \
    -v "$PWD":/app \
    --user="$(id -u):$(id -g)" \
    crybot-builder-arm64 \
    /bin/sh -c "cd /app && shards build --without-development --release --static --no-debug '-Dpreview_mt' '-Dexecution_context' 'crybot'"
fi

# Copy and compress the ARM64 binary
cp bin/crybot dist/crybot-linux-arm64
upx --best --lzma dist/crybot-linux-arm64
echo "✓ Built: dist/crybot-linux-arm64 ($(du -h dist/crybot-linux-arm64 | cut -f1))"

# Show file sizes
echo ""
echo "Binary sizes:"
ls -lh dist/

echo ""
echo "Static binaries built successfully!"
echo "You can now ship these binaries - they have no external dependencies."
