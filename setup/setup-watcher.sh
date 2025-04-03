#!/bin/sh

CONFIG="/var/www/html/ipconfig.php"
TOUCH_FLAG="/var/www/html/.postsetup_complete"

echo "👀 Watching for SETUP_COMPLETED=true in: $CONFIG"

# Only run the watcher loop if setup is incomplete
if grep -q "^SETUP_COMPLETED=false" "$CONFIG"; then
    echo "⏳ Setup is still in progress — entering watch loop..."

    while true; do
        if grep -q "^SETUP_COMPLETED=true" "$CONFIG"; then
            echo "✅ Setup completed!"

            echo "📌 Touching post-setup flag: $TOUCH_FLAG"
            touch "$TOUCH_FLAG"

            echo "🔁 Restarting container in 5 seconds..."
            sleep 5

            echo "⛔ Exiting to allow Docker to restart (requires restart: always)"
            kill -s TERM 1

            break
        fi

        sleep 1
    done
else
    echo "✅ SETUP_COMPLETED already true — skipping watcher loop"
fi


