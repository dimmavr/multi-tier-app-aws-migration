#!/bin/bash
set -uo pipefail    # ΟΧΙ -e εδώ: θέλουμε να συνεχίζει ακόμα κι αν κάτι ήδη λείπει

DB_ID="migration-db"
SG_NAME="rds-migration-sg"

echo "=== AWS Teardown $(date) ==="

# --- 1. Σβήσε το RDS (re-fetch, όχι μεταβλητή από παλιό session) ---
echo "Deleting RDS instance $DB_ID..."
aws rds delete-db-instance \
  --db-instance-identifier "$DB_ID" \
  --skip-final-snapshot \
  --delete-automated-backups 2>/dev/null \
  && echo "RDS deletion started" \
  || echo "RDS already gone or not found"

# --- 2. Περίμενε να σβηστεί πλήρως (το SG δεν σβήνει όσο το κρατάει το RDS) ---
echo "Waiting for RDS to fully delete (this takes a few minutes)..."
aws rds wait db-instance-deleted --db-instance-identifier "$DB_ID" 2>/dev/null \
  && echo "RDS fully deleted" \
  || echo "RDS wait finished (already gone)"

# --- 3. Σβήσε το security group (re-fetch το ID) ---
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
    echo "Deleting security group $SG_ID..."
    aws ec2 delete-security-group --group-id "$SG_ID" \
      && echo "Security group deleted" \
      || echo "SG delete failed (maybe still in use — wait and retry)"
else
    echo "Security group not found (already deleted)"
fi

echo "=== Teardown complete ==="
echo "Verify nothing is running:"
aws rds describe-db-instances --query 'DBInstances[*].DBInstanceIdentifier' --output text
