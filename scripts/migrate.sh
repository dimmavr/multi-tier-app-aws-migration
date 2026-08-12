#!/bin/bash
set -euo pipefail

TARGET_VERSION="${1:-}"
[ -z "$TARGET_VERSION" ] && { echo "Usage: $0 <version>"; exit 1; }

APP_HOST="10.0.10.10"; APP_USER="admin"; APP_DIR="/home/admin/app"
DB_HOST="10.0.20.10"; DB_USER="admin"; DB_NAME="appdb"

MIGRATION_FILE="$APP_DIR/releases/$TARGET_VERSION/migration.sql"

# 1. Υπάρχει migration για αυτό το release;
if ! ssh "$APP_USER@$APP_HOST" "[ -f $MIGRATION_FILE ]"; then
    echo "No migration.sql for $TARGET_VERSION"
    exit 0        # όχι error — απλά δεν υπάρχει τίποτα να κάνει
fi

# 2. BACKUP πρώτα (το δίχτυ) — μη-διαπραγματεύσιμο
echo "Backup before migration..."
/home/admin/backup.sh || { echo "Backup failed, aborting"; exit 1; }

# 3. MIGRATE (idempotent, IF NOT EXISTS)
echo "Applying migration $TARGET_VERSION..."
ssh "$APP_USER@$APP_HOST" "cat $MIGRATION_FILE" | psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f -

echo "Migration $TARGET_VERSION applied"
