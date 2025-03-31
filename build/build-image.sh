#!/bin/bash

###########################################
# 📝 Logging Setup
###########################################
[ -f build.log ] && mv build.log build.previous.log
exec > >(tee build.log) 2>&1
set -euo pipefail

###########################################
# ⚙️ Docker BuildKit Environment
###########################################
export COMPOSE_DOCKER_CLI_BUILD=1
export DOCKER_BUILDKIT=1

###########################################
# 🚨 SAFETY WARNING: Destructive Operation
###########################################
echo "⚠️ This script will DELETE persistent volumes and bind-mounted directories."
read -rp "Type 'y' to continue: " INITIAL_CONFIRM
[[ "$INITIAL_CONFIRM" =~ ^[Yy]$ ]] || {
  echo "Aborting as per user request."
  exit 1
}

###########################################
# 🧭 Detect Docker Tools
###########################################
DOCKER_BUILDX="docker buildx"
command -v docker-buildx >/dev/null 2>&1 && DOCKER_BUILDX="docker-buildx"

DOCKER_COMPOSE="docker compose"
command -v docker-compose >/dev/null 2>&1 && DOCKER_COMPOSE="docker-compose"

###########################################
# ♻️ Optional Cleanup Prompt
###########################################
read -rp "Do you want to clean containers, images, volumes, and local data? [y/N]: " CLEANUP_CONFIRM
CLEANUP_CONFIRM=$(echo "$CLEANUP_CONFIRM" | tr '[:upper:]' '[:lower:]')
if [[ "$CLEANUP_CONFIRM" == "y" ]]; then
  echo "🧹 Cleaning up..."

  $DOCKER_COMPOSE down -v || true
  docker ps -a --filter "name=invoiceplane_" -q | xargs -r docker rm -f
  docker image prune -af || true
  $DOCKER_BUILDX prune --force --all || true
  sudo rm -rf invoiceplane_* mariadb || true

  NO_CACHE_FLAG="--no-cache"
else
  echo "⏩ Skipping cleanup."
  NO_CACHE_FLAG=""
fi

###########################################
# 🗓️ Reproducible Build Date
###########################################
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "📆 Build date: $BUILD_DATE"

###########################################
# 📦 Load Environment Variables
###########################################
[ -f .env ] || { echo "❌ .env file not found."; exit 1; }
echo "📦 Loading environment variables..."
set -a
source .env
set +a

###########################################
# ✅ Check Required Vars
###########################################
REQUIRED_VARS=(PHP_VERSION IP_VERSION IP_IMAGE IP_LANGUAGE IP_SOURCE PUID PGID)
for VAR in "${REQUIRED_VARS[@]}"; do
  [[ -n "${!VAR:-}" ]] || { echo "❌ Missing env var: $VAR"; exit 1; }
done

###########################################
# 🧠 Detect Native Architecture
###########################################
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) PLATFORM="linux/amd64" ;;
  arm64|aarch64) PLATFORM="linux/arm64" ;;
  *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac
echo "✅ Detected architecture: $ARCH → $PLATFORM"

###########################################
# 🏷️ Choose Build Mode (Push or Load)
###########################################
read -rp "Do you want to push the image to GHCR? (y/N): " PUSH_CONFIRM
PUSH_CONFIRM=$(echo "$PUSH_CONFIRM" | tr '[:upper:]' '[:lower:]')
if [[ "$PUSH_CONFIRM" == "y" ]]; then
  BUILD_MODE="push"
  PLATFORMS="linux/amd64,linux/arm64"
  echo "📤 Will push multi-arch image to: ${IP_IMAGE}:${IP_VERSION}"
else
  BUILD_MODE="load"
  PLATFORMS="$PLATFORM"
  echo "💻 Will load native image locally: ${IP_IMAGE}:${IP_VERSION}"
fi

###########################################
# 🧩 Common Build Arguments
###########################################
BUILD_ARGS="
  --build-arg BUILD_DATE=${BUILD_DATE}
  --build-arg PHP_VERSION=${PHP_VERSION}
  --build-arg IP_LANGUAGE=${IP_LANGUAGE}
  --build-arg IP_VERSION=${IP_VERSION}
  --build-arg IP_SOURCE=${IP_SOURCE}
  --build-arg IP_IMAGE=${IP_IMAGE}
  --build-arg PUID=${PUID}
  --build-arg PGID=${PGID}
"

###########################################
# 🔨 Run Docker Buildx
###########################################
if [[ "$BUILD_MODE" == "push" ]]; then
  $DOCKER_BUILDX build $NO_CACHE_FLAG \
    --progress=plain \
    --platform "$PLATFORMS" \
    --push \
    --tag "${IP_IMAGE}:${IP_VERSION}" \
    $BUILD_ARGS \
    .
else
  $DOCKER_BUILDX build $NO_CACHE_FLAG \
    --progress=plain \
    --platform "$PLATFORMS" \
    --load \
    --tag "${IP_IMAGE}:${IP_VERSION}" \
    $BUILD_ARGS \
    .
fi

###########################################
# ✅ Done
###########################################
echo "✅ Docker image built: ${IP_IMAGE}:${IP_VERSION}"
[[ "$BUILD_MODE" == "push" ]] && echo "🌍 Image was pushed to GHCR." || echo "📦 Image loaded into local Docker."

echo "🎉 Build complete!"

