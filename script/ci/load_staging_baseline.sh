#!/bin/bash

# Every time staging is deployed, we load a baseline data set before running the new code's
# migrations. This script loads the baseline data set, after first taking a backup of the
# current database.

set -e

echo "--- Checking environment variables"
ENV_VARS='CURRENT_PATH APP DB_HOST DB_USER DB'
for var in $ENV_VARS; do
  eval value=\$$var
  echo "$var=$value"
  test -n "$value"
done

cd "$CURRENT_PATH"
source ./script/ci/includes.sh

echo "Stopping unicorn and delayed job..."
service "$APP" stop
RAILS_ENV=staging script/delayed_job -i 0 stop

echo "Backing up current data..."
mkdir -p db/backup
pg_dump -h "$DB_HOST" -U "$DB_USER" "$DB" |gzip > db/backup/staging-`date +%Y%m%d%H%M%S`.sql.gz

echo "Loading baseline data..."
drop_and_recreate_database "$DB"
gunzip -c db/backup/staging-baseline.sql.gz |psql -h "$DB_HOST" -U "$DB_USER" "$DB"

echo "Restarting unicorn..."
service "$APP" start
# Delayed job is restarted by monit

echo "Done!"
