#!/bin/sh
# Uploads this target's dSYM to Sentry on Release and Archive builds.
# See SENTRY.md. The auth token is never written to the repo and is never printed.
#
# Token lookup, in order:
#   1. SENTRY_AUTH_TOKEN in the environment (local shell, Xcode Cloud, GitHub Actions)
#   2. .sentryclirc at the git repo root (gitignored)
#   3. ~/.sentryclirc
# Both files are the standard sentry-cli locations. A token line looks like:
#   [auth]
#   token=...
#
# Missing sentry-cli, a missing token, or a failed upload prints a warning and
# exits 0. Debug builds, simulator builds, and forks without a token must still build.

set -u

warn() {
  # "warning:" is what Xcode shows in the issue navigator. Do not print "error:":
  # Xcode can fail the phase on that prefix even when the script exits 0.
  echo "warning: $*"
}

configuration=${CONFIGURATION:-unknown}
action=${ACTION:-unknown}
target_name=${TARGET_NAME:-unknown}

should_upload=0
if [ "$configuration" = "Release" ]; then
  should_upload=1
fi
# xcodebuild archive and Xcode's Archive action set ACTION=install.
if [ "$action" = "install" ]; then
  should_upload=1
fi

if [ "$should_upload" -ne 1 ]; then
  echo "Sentry: skipping dSYM upload for ${target_name} (configuration ${configuration}, action ${action})"
  exit 0
fi

# app/scripts/upload-dsyms.sh -> repository root is two directories up.
script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

# Prints the [auth] token= value from a sentry-cli config file, or nothing.
read_auth_token() {
  config_file=$1
  if [ ! -f "$config_file" ]; then
    return 0
  fi
  awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*[#;]/) next
      if (line ~ /^[[:space:]]*\[/) {
        section = tolower(trim(line))
        next
      }
      if (section == "[auth]" && line ~ /^[[:space:]]*token[[:space:]]*=/) {
        sub(/^[[:space:]]*token[[:space:]]*=[[:space:]]*/, "", line)
        line = trim(line)
        if ((line ~ /^".*"$/) || (line ~ /^'\''.*'\''$/)) {
          line = substr(line, 2, length(line) - 2)
        }
        if (length(line) > 0) {
          print line
          exit
        }
      }
    }
  ' "$config_file"
}

token_source=""
if [ -n "${SENTRY_AUTH_TOKEN:-}" ]; then
  token_source="SENTRY_AUTH_TOKEN"
else
  repo_token=$(read_auth_token "$repo_root/.sentryclirc")
  if [ -n "$repo_token" ]; then
    SENTRY_AUTH_TOKEN=$repo_token
    token_source="repo-root .sentryclirc"
  else
    home_token=$(read_auth_token "${HOME:-}/.sentryclirc")
    if [ -n "$home_token" ]; then
      SENTRY_AUTH_TOKEN=$home_token
      token_source="~/.sentryclirc"
    fi
  fi
  unset repo_token home_token
fi

if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
  warn "Sentry dSYM upload skipped for ${target_name} because no auth token was found. Set SENTRY_AUTH_TOKEN, or add an [auth] token= line to ${repo_root}/.sentryclirc or ~/.sentryclirc. See SENTRY.md."
  exit 0
fi
export SENTRY_AUTH_TOKEN

# Org and project are not secret. US region (sentry.io) is sentry-cli's default host.
export SENTRY_ORG="dime-1x"
export SENTRY_PROJECT="dime-ios"

# Prefer a sentry-cli already on PATH, then Homebrew (Apple Silicon, then Intel),
# then a binary inside the Sentry Cocoa SPM checkout or artifact when one is there.
# sentry-cocoa 9.35.0 does not ship a CLI; the search still covers that layout.
find_sentry_cli() {
  if command -v sentry-cli >/dev/null 2>&1; then
    command -v sentry-cli
    return 0
  fi
  for candidate in /opt/homebrew/bin/sentry-cli /usr/local/bin/sentry-cli; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  if [ -n "${BUILD_DIR:-}" ]; then
    dir=$BUILD_DIR
    i=0
    while [ "$i" -lt 6 ] && [ -n "$dir" ] && [ "$dir" != "/" ]; do
      for candidate in \
        "$dir/SourcePackages/checkouts/sentry-cocoa/scripts/sentry-cli" \
        "$dir/SourcePackages/checkouts/sentry-cocoa/bin/sentry-cli" \
        "$dir/SourcePackages/artifacts/sentry-cocoa/sentry-cli/sentry-cli"
      do
        if [ -x "$candidate" ]; then
          echo "$candidate"
          return 0
        fi
      done
      dir=$(dirname "$dir")
      i=$((i + 1))
    done
  fi
  return 1
}

sentry_cli=$(find_sentry_cli) || {
  warn "Sentry dSYM upload skipped for ${target_name} because sentry-cli is not installed. Install it with: brew install getsentry/tools/sentry"
  exit 0
}

dsym_dir=${DWARF_DSYM_FOLDER_PATH:-}
dsym_name=${DWARF_DSYM_FILE_NAME:-}
if [ -z "$dsym_dir" ] || [ -z "$dsym_name" ]; then
  warn "Sentry dSYM upload skipped for ${target_name} because DWARF_DSYM_FOLDER_PATH or DWARF_DSYM_FILE_NAME is unset."
  exit 0
fi

dsym_path="$dsym_dir/$dsym_name"
if [ ! -d "$dsym_path" ]; then
  warn "Sentry dSYM upload skipped for ${target_name} because no dSYM bundle was found at ${dsym_path}. Release builds need DEBUG_INFORMATION_FORMAT = dwarf-with-dsym."
  exit 0
fi

echo "Sentry: uploading dSYM for ${target_name} from ${dsym_path} (token from ${token_source})"

# Do not pass the token as an argument. --force-foreground keeps the result in the build log.
upload_output=$("$sentry_cli" --force-foreground debug-files upload --include-sources "$dsym_path" 2>&1) || upload_status=$?
upload_status=${upload_status:-0}

if [ -n "$upload_output" ]; then
  if command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "$upload_output" | python3 -c 'import os,sys; t=os.environ.get("SENTRY_AUTH_TOKEN",""); d=sys.stdin.read(); sys.stdout.write(d.replace(t,"[redacted]") if t else d)'
  else
    echo "Sentry: sentry-cli output omitted so the auth token cannot be printed."
  fi
fi

if [ "$upload_status" -ne 0 ]; then
  warn "Sentry dSYM upload failed for ${target_name} (sentry-cli status ${upload_status}). The build will continue. See SENTRY.md."
  exit 0
fi

echo "Sentry: dSYM upload finished for ${target_name}"
exit 0
