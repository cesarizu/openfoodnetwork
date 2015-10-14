#!/bin/bash

set -e
source ./script/ci/includes.sh

OFN_COMMIT=$(get_ofn_commit)
if [ "$OFN_COMMIT" = 'OFN_COMMIT_NOT_FOUND' ]; then
  OFN_COMMIT=$BUILDKITE_COMMIT
fi
REMOTE="${REMOTE:-$SSH_HOST:$CURRENT_PATH}"

echo "--- Checking environment variables"
ENV_VARS='OFN_COMMIT SSH_HOST CURRENT_PATH REMOTE APP DB_HOST DB_USER DB'
for var in $ENV_VARS; do
  eval value=\$$var
  echo "$var=$value"
  test -n "$value"
done

echo "--- Verifying branch is based on current master"
exit_unless_master_merged

echo "--- Loading baseline data"
VARS="CURRENT_PATH='$CURRENT_PATH' APP='$APP' DB_HOST='$DB_HOST' DB_USER='$DB_USER' DB='$DB'"
ssh "$SSH_HOST" "$VARS $CURRENT_PATH/script/ci/load_staging_baseline.sh"

echo "--- Pushing to staging"
exec 5>&1
OUTPUT=$(git push "$REMOTE" "$OFN_COMMIT":master --force 2>&1 |tee /dev/fd/5)
[[ $OUTPUT =~ "Done" ]]
