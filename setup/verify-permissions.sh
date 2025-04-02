#!/bin/sh

echo "🔍 Verifying Docker UID/GID permissions..."

# Expected bind-mount path
MOUNT_PATH="/var/www/html"
TEST_FILE="$MOUNT_PATH/_permtest.txt"

# Expected host-based PUID/PGID passed into container
PUID=${PUID:-501}
PGID=${PGID:-20}

# Users to verify
USERS="abc www-data nginx"

echo "📂 Checking test directory: $MOUNT_PATH"
if [ ! -d "$MOUNT_PATH" ]; then
  echo "❌ ERROR: Directory $MOUNT_PATH does not exist inside container."
  exit 1
fi

echo "🧪 Checking if users exist and are in PGID $PGID..."

for user in $USERS; do
  if id "$user" >/dev/null 2>&1; then
    echo "👤 $user exists ✅"

    GROUPS=$(id -G "$user")
    echo "   🔎 Groups for $user: $GROUPS"

    echo "$GROUPS" | grep -qw "$PGID"
    if [ $? -eq 0 ]; then
      echo "   ✅ $user is a member of PGID $PGID"
    else
      echo "   ❌ $user is NOT in PGID $PGID"
    fi
  else
    echo "⚠️ User $user not found"
  fi
done

echo "📝 Testing write access as www-data..."
if su -s /bin/sh -c "touch $TEST_FILE && rm -f $TEST_FILE" www-data; then
  echo "✅ www-data can write to $MOUNT_PATH"
else
  echo "❌ www-data CANNOT write to $MOUNT_PATH"
fi

echo "📝 Testing write access as nginx..."
if su -s /bin/sh -c "touch $TEST_FILE && rm -f $TEST_FILE" nginx; then
  echo "✅ nginx can write to $MOUNT_PATH"
else
  echo "❌ nginx CANNOT write to $MOUNT_PATH"
fi

echo "✅ Verification complete."


