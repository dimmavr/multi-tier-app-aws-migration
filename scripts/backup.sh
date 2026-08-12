#!/bin/bash

set -euo pipefail

DB_HOST="10.0.20.10"
DB_USER="admin"
DB_NAME="appdb"
BACKUP_DIR="/home/admin/backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
RETENTION_DAYS=7
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql"
VERIFY_DB="appdb_verify"
LOG_FILE="/home/admin/backups/backup.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Backup run: $(date) ==="


mkdir -p "$BACKUP_DIR"
pg_dump -h $DB_HOST -U $DB_USER $DB_NAME > $BACKUP_FILE

if [ ! -s "$BACKUP_FILE" ]; then
   echo "error"
   exit 1
fi

echo "Backup created: $BACKUP_FILE"
ls -lh $BACKUP_FILE


# count από την πηγή (ζωντανή βάση, υπάρχει ήδη)
EXPECTED_COUNT=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -tAc 'SELECT COUNT(*) FROM users')

# σπρώξε το dump στη db
scp "$BACKUP_FILE" "${DB_USER}@${DB_HOST}:/tmp/verify.sql"

# createdb + restore ΠΑΝΩ ΣΤΗ DB, και πιάσε το restored count
RESTORED_COUNT=$(ssh "${DB_USER}@${DB_HOST}" "
    sudo -u postgres dropdb --if-exists $VERIFY_DB &&
    sudo -u postgres createdb $VERIFY_DB &&
    sudo -u postgres psql -d $VERIFY_DB -f /tmp/verify.sql >/dev/null 2>&1 &&
    sudo -u postgres psql -d $VERIFY_DB -tAc 'SELECT COUNT(*) FROM users' &&
    sudo -u postgres dropdb $VERIFY_DB &&
    rm -f /tmp/verify.sql
")

# σύγκρινε
if [ "$RESTORED_COUNT" = "$EXPECTED_COUNT" ]; then
    echo "Verify PASS: $RESTORED_COUNT rows match source"
else
    echo "Verify FAIL: source=$EXPECTED_COUNT restored=$RESTORED_COUNT"
    exit 1
fi

# --- Στάδιο 5: Retention (κράτα τα τελευταία N) ---
RETENTION_COUNT=2
# ls -t: sort by time, νεότερα πρώτα
# tail -n +N: πάρε από τη γραμμή N και μετά (τα "πέρα από το όριο")
ls -t "${BACKUP_DIR}/${DB_NAME}"_*.sql | tail -n +$((RETENTION_COUNT + 1)) | while read old; do
    rm -f "$old"
done
