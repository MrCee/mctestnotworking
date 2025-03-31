#!/bin/bash
set -e

######################################
# Auto-detect Host UID and GID
######################################
PUID=$(id -u)
PGID=$(id -g)
echo "🔍 Auto-detected PUID: $PUID"
echo "🔍 Auto-detected PGID: $PGID"

######################################
# Set Default Values for MariaDB UID/GID
######################################
MYSQL_UID=${MYSQL_UID:-999}
MYSQL_GID=${MYSQL_GID:-999}
echo "⚙️ Using MYSQL_UID: $MYSQL_UID"
echo "⚙️ Using MYSQL_GID: $MYSQL_GID"

######################################
# Detect Host Operating System
######################################
HOST_OS_VAR=$(uname)
HOST_OS="linux"
if [ "$HOST_OS_VAR" = "Darwin" ]; then
    HOST_OS="macos"
fi
echo "🖥️ Detected HOST_OS: $HOST_OS"

######################################
# Update .env File with Detected Values
######################################
ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
    echo
    echo "❌ ERROR: .env file not found in the project root."
    echo "💡 To fix this:"
    echo "   1. Copy the example file: cp .env.example .env"
    echo "   2. Fill in values like IP_URL, MYSQL_HOST, etc."
    echo "   3. Re-run ./kickstart.sh"
    echo
    exit 1
fi

echo "🔄 Updating environment variables in $ENV_FILE"
awk -v PUID="$PUID" -v PGID="$PGID" -v HOST_OS="$HOST_OS" -v MYSQL_UID="$MYSQL_UID" -v MYSQL_GID="$MYSQL_GID" '
  BEGIN {FS=OFS="="}
  $1=="PUID" {$2=PUID}
  $1=="PGID" {$2=PGID}
  $1=="HOST_OS" {$2=HOST_OS}
  $1=="MYSQL_UID" {$2=MYSQL_UID}
  $1=="MYSQL_GID" {$2=MYSQL_GID}
  {print}
' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
echo "✅ .env updated"

#######################################
## INSTALL_MODE: init / rerun / repair
#######################################
#MODE=$(grep -E "^INSTALL_MODE=" "$ENV_FILE" | cut -d= -f2)
#
#if [ "$MODE" = "init" ]; then
#    echo "🆕 INSTALL_MODE=init → First-time setup"
#    INSTALL_MODE_NEXT="rerun"
#elif [ "$MODE" = "repair" ]; then
#    echo "🧰 INSTALL_MODE=repair → Running repair logic"
#    INSTALL_MODE_NEXT="repair"
#else
#    echo "🔁 INSTALL_MODE=$MODE → Assuming rerun"
#    INSTALL_MODE_NEXT="$MODE"
#fi
#
#if [ "$INSTALL_MODE_NEXT" != "$MODE" ]; then
#    echo "🔄 Updating INSTALL_MODE in $ENV_FILE → $INSTALL_MODE_NEXT"
#    awk -v mode="$INSTALL_MODE_NEXT" 'BEGIN {FS=OFS="="}
#      $1=="INSTALL_MODE" {$2=mode}
#      {print}
#    ' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
#    echo "✅ INSTALL_MODE updated to $INSTALL_MODE_NEXT"
#fi

######################################
# Create Required Directories
######################################
DIRS=("invoiceplane_uploads" "invoiceplane_css" "invoiceplane_views" "invoiceplane_language" "mariadb")
echo "📁 Creating required directories..."
for dir in "${DIRS[@]}"; do
    mkdir -p "./$dir"
    echo "✅ Created: $dir"
done

######################################
# Set Ownership and Permissions
######################################
set_permissions() {
    local dir=$1
    local owner="$PUID:$PGID"
    local perms="775"

    if [ "$HOST_OS" = "macos" ]; then
        perms="777"
    fi

    if [[ "$dir" == "./mariadb" ]]; then
        owner="$MYSQL_UID:$MYSQL_GID"
    fi

    echo "🔄 Setting permissions on: $dir ($owner with $perms)"

    if command -v sudo >/dev/null 2>&1; then
        sudo chown -R "$owner" "$dir" 2>/dev/null || echo "⚠️ Skipping chown errors for $dir"
        sudo chmod -R "$perms" "$dir"
    else
        chown -R "$owner" "$dir" 2>/dev/null || echo "⚠️ Skipping chown errors for $dir"
        chmod -R "$perms" "$dir"
    fi

    echo "✅ Permissions applied to: $dir"
}

###########################################
# 🚀 Enforce Modern Docker Compose (v2)
###########################################
if ! command -v docker compose >/dev/null 2>&1; then
  echo "❌ docker compose (v2) not found. Please upgrade Docker CLI."
  exit 1
fi

DOCKER_COMPOSE="docker compose"
echo "🚀 Using modern Docker Compose: $DOCKER_COMPOSE"

######################################
# Start Containers
######################################
echo "▶️ Starting containers..."
$DOCKER_COMPOSE up -d
sleep 5

###########################################
# 🔄 Sync SETUP_COMPLETED Between Container & .env
###########################################
CONTAINER_NAME="${IP_CONTAINER_NAME:-invoiceplane_app}"
ENV_FILE=".env"
IPCONFIG="/var/www/html/ipconfig.php"

echo "🔍 Checking setup completion state..."

if docker exec "$CONTAINER_NAME" test -f "$IPCONFIG" >/dev/null 2>&1; then
    CONTAINER_VALUE=$(docker exec "$CONTAINER_NAME" sh -c "grep '^SETUP_COMPLETED=' $IPCONFIG | cut -d= -f2 | tr -d '\r\n'")
    ENV_VALUE=$(grep -E "^SETUP_COMPLETED=" "$ENV_FILE" | cut -d= -f2 | tr -d '\r\n')

    echo "🌐 Container: SETUP_COMPLETED=$CONTAINER_VALUE"
    echo "🧾 .env:      SETUP_COMPLETED=$ENV_VALUE"

    if [[ "$CONTAINER_VALUE" != "$ENV_VALUE" ]]; then
        echo "⚠️  Mismatch detected — syncing .env to match container state..."

        if [[ "$CONTAINER_VALUE" == "true" ]]; then
            sed -i.bak 's/^SETUP_COMPLETED=.*/SETUP_COMPLETED=true/' "$ENV_FILE"
            echo "✅ .env updated: SETUP_COMPLETED=true"
        else
            sed -i.bak 's/^SETUP_COMPLETED=.*/SETUP_COMPLETED=false/' "$ENV_FILE"
            echo "🔁 .env updated: SETUP_COMPLETED=false"
        fi

        echo "🔁 Restarting container to reflect updated .env..."
        docker compose down
        docker compose up -d

        echo "✅ Container restarted and now in sync."
    else
        echo "🔄 SETUP_COMPLETED already in sync. No action needed."
    fi
else
    echo "⚠️  ipconfig.php not found in container — skipping setup sync."
fi

