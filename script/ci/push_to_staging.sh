#!/bin/bash

set -e
source ./script/ci/includes.sh

echo "--- Checking commit variable"
OFN_COMMIT=$(get_ofn_commit)
if [ "$OFN_COMMIT" = 'OFN_COMMIT_NOT_FOUND' ]; then
  OFN_COMMIT=$BUILDKITE_COMMIT
fi
echo "OFN_COMMIT=$OFN_COMMIT"
test -n "$OFN_COMMIT"

echo "--- Checking environment variables"
echo "STAGING_SSH_HOST=$STAGING_SSH_HOST"
test -n "$STAGING_SSH_HOST"
echo "STAGING_CURRENT_PATH=$STAGING_CURRENT_PATH"
test -n "$STAGING_CURRENT_PATH"

echo "--- Verifying branch is based on current master"
exit_unless_master_merged

echo "--- Loading baseline data"
ssh "$STAGING_SSH_HOST" "$STAGING_CURRENT_PATH/script/ci/load_staging_baseline.sh"

echo "--- Pushing to staging"
exec 5>&1
OUTPUT=$(git push "$STAGING_SSH_HOST" `get_ofn_commit`:master --force 2>&1 |tee /dev/fd/5)
[[ $OUTPUT =~ "Done" ]]
