#!/bin/sh
# Uploads debug symbols for the dime Release build. See SENTRY.md.
# SENTRY_AUTH_TOKEN is read from the environment and is never written to the repo.

set -u

if [ "${CONFIGURATION:-}" != "Release" ]; then
  echo "Sentry: skipping dSYM upload for configuration ${CONFIGURATION:-unknown}"
  exit 0
fi

if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
  echo "warning: Sentry dSYM upload skipped because SENTRY_AUTH_TOKEN is not set. See SENTRY.md."
  exit 0
fi

export SENTRY_ORG="dime-1x"
export SENTRY_PROJECT="dime-ios"
# The DSN host is the US ingest region. debug-files upload uses the org slug above.

if ! command -v sentry-cli >/dev/null 2>&1; then
  if [ -x "/opt/homebrew/bin/sentry-cli" ]; then
    PATH="/opt/homebrew/bin:$PATH"
  elif [ -x "/usr/local/bin/sentry-cli" ]; then
    PATH="/usr/local/bin:$PATH"
  fi
  export PATH
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "error: sentry-cli is not installed, so dSYMs were not uploaded. Install it with: brew install getsentry/tools/sentry"
  exit 1
fi

if [ -z "${DWARF_DSYM_FOLDER_PATH:-}" ] || [ ! -d "$DWARF_DSYM_FOLDER_PATH" ]; then
  echo "error: DWARF_DSYM_FOLDER_PATH is missing, so dSYMs were not uploaded."
  exit 1
fi

echo "Sentry: uploading dSYMs from ${DWARF_DSYM_FOLDER_PATH}"
sentry-cli debug-files upload --include-sources "$DWARF_DSYM_FOLDER_PATH"
status=$?

if [ "$status" -ne 0 ]; then
  echo "error: sentry-cli debug-files upload failed with status ${status}"
  exit "$status"
fi

echo "Sentry: dSYM upload finished"
exit 0
