#!/bin/bash

###########################################
# 📝 Logging Setup
###########################################
[ -f build.log ] && mv build.log build.previous.log
exec > >(tee build.log) 2>&1
set -eu

###########################################
# 🧭 Detect Docker Tools
###########################################
DOCKER_BUILDX="docker buildx"
command -v docker-buildx >/dev/null 2>&1 && DOCKER_BUILDX="docker-buildx"

DOCKER_COMPOSE="docker compose"
command -v docker-compose >/dev/null 2>&1 && DOCKER_COMPOSE="docker-compose"

###########################################
# 🚨 SAFETY WARNING: Destructive Operation
###########################################
if [ -t 0 ]; then
  echo "⚠️ This will DELETE volumes and bind-mounted data. Continue?"
  printf "Type 'y' to continue: "
  read INITIAL_CONFIRM
  [ "$INITIAL_CONFIRM" = "y" ] || [ "$INITIAL_CONFIRM" = "Y" ] || {
    echo "Aborted."
    exit 1
  }
else
  echo "⚠️ Non-interactive mode detected. Skipping confirmation prompt."
fi

###########################################
# 🛠️ Tooling Checks
###########################################
command -v docker-compose >/dev/null 2>&1 || {
  echo "❌ docker-compose not found."
  exit 1
}

$DOCKER_BUILDX version >/dev/null 2>&1 || {
  echo "❌ $DOCKER_BUILDX not available."
  exit 1
}

###########################################
# 📦 Load .env Variables (Short Format)
###########################################
[ -f .env ] || { echo "❌ .env file missing."; exit 1; }
echo "📦 Loading .env"
set -a
. ./.env
set +a

###########################################
# 🧠 Auto-detected Defaults
###########################################
: "${PUID:=$(id -u)}"
: "${PGID:=$(id -g)}"
BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

echo "🔧 PUID=$PUID, PGID=$PGID, BUILD_DATE=$BUILD_DATE, IP_VERSION=$IP_VERSION"

###########################################
# 🛑 Stop and Remove Existing Containers
###########################################
echo "🛑 Stopping and removing existing containers..."
$DOCKER_COMPOSE down --remove-orphans --volumes

###########################################
# 🧹 Docker Cleanup (Optional)
###########################################
echo "🧹 Docker cleanup..."
docker container prune -f
docker image prune -af
docker volume prune -f
docker builder prune -af

###########################################
# 🧩 Common Build Arguments
###########################################
BUILD_ARGS="
  --build-arg PHP_VERSION=$PHP_VERSION
  --build-arg IP_VERSION=$IP_VERSION
  --build-arg IP_SOURCE=$IP_SOURCE
  --build-arg IP_LANGUAGE=$IP_LANGUAGE
  --build-arg IP_IMAGE=$IP_IMAGE
  --build-arg PUID=$PUID
  --build-arg PGID=$PGID
  --build-arg BUILD_DATE=$BUILD_DATE
"

###########################################
# 🐳 Build Image (Scenario Mode)
###########################################
[ -n "$IP_IMAGE" ] || { echo "❌ IP_IMAGE not set."; exit 1; }

BUILD_SCENARIO=$(echo "${BUILD_SCENARIO:-load}" | tr '[:upper:]' '[:lower:]')

echo "🐳 Building image: $IP_IMAGE:$IP_VERSION using scenario: $BUILD_SCENARIO"

if [ "$BUILD_SCENARIO" = "push" ]; then
  BUILD_FLAGS="--push"
elif [ "$BUILD_SCENARIO" = "load" ]; then
  BUILD_FLAGS="--load"
elif [ "$BUILD_SCENARIO" = "none" ]; then
  BUILD_FLAGS=""
else
  echo "❌ Invalid BUILD_SCENARIO: $BUILD_SCENARIO"
  exit 1
fi

$DOCKER_BUILDX build \
  --no-cache \
  --progress=plain \
  $BUILD_FLAGS \
  --tag "$IP_IMAGE:$IP_VERSION" \
  $BUILD_ARGS \
  .

###########################################
# ✅ Done
###########################################
echo "✅ Docker image built as: $IP_IMAGE:$IP_VERSION"



