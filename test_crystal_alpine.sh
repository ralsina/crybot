#!/bin/bash
set -e

echo "Testing Docker build environment..."

docker run --rm alpine:3.20 sh -c "
  apk update
  apk add crystal shards
  crystal --version
  shards --version
"

echo ""
echo "✓ Crystal is available in Alpine 3.20"
