#!/bin/bash

set -euo pipefail

APP_HOST="10.0.10.10"
APP_USER="admin"
APP_DIR="/home/admin/app"
TARGET_VERSION="$1"

if [ -z "$TARGET_VERSION" ]; then
   echo "Usage: $0 <version>"
   exit 1
fi


if ! ssh "$APP_USER@$APP_HOST" "[ -d $APP_DIR/releases/$TARGET_VERSION ]"; then
    echo "Release $TARGET_VERSION not found"
    exit 1
fi

CURRENT=$(ssh "$APP_USER"@"$APP_HOST" "basename \$(readlink $APP_DIR/current)")
echo "Current: $CURRENT → Target: $TARGET_VERSION"

ssh "$APP_USER"@"$APP_HOST" "ln -sfn $APP_DIR/releases/$TARGET_VERSION $APP_DIR/current && sudo systemctl restart flaskapp"
echo "Deployed $TARGET_VERSION"

# --- Health check με retries (readiness wait, λόγω restart downtime) ---
HEALTH_URL="http://${APP_HOST}/"
MAX_RETRIES=5
HEALTHY=false

for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf --max-time 3 "$HEALTH_URL" >/dev/null 2>&1; then
        HEALTHY=true
        break
    fi
    echo "Health check attempt $i/$MAX_RETRIES failed, retrying..."
    sleep 2
done

# --- Απόφαση: PASS ή ROLLBACK ---
if [ "$HEALTHY" = true ]; then
    echo "Deploy successful: $TARGET_VERSION is healthy"
else
    echo "Health check FAILED after $MAX_RETRIES attempts — rolling back to $CURRENT"
    ssh "$APP_USER@$APP_HOST" "ln -sfn $APP_DIR/releases/$CURRENT $APP_DIR/current && sudo systemctl restart flaskapp"
    echo "Rolled back to $CURRENT"
    exit 1
fi
