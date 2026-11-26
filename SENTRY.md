# Sentry

Dime reports crashes, app hangs, and a small set of data-integrity events to the Sentry project `dime-ios` in the org `dime-1x` (US region). The goal is to explain reports of all data disappearing after an update, without sending the contents of anyone's books.

## Setup

The app links the official [sentry-cocoa](https://github.com/getsentry/sentry-cocoa) SDK 9.35.0 (the current stable release) through Swift Package Manager. The product is the prebuilt `Sentry` binary, on the `dime` app target only.

`SentryBootstrap.start()` runs at the top of `dimeApp.init`, before `DataController` opens the store. Release builds use the environment `production` and a release name of `bundle-id@version+build`. Debug builds set the environment to `debug` and `enabled = false`, so Xcode runs do not spend the free Developer plan quota. Unit tests do not start the SDK.

Crash reporting and app hang tracking (2 second threshold) are on. Tracing is sampled at `tracesSampleRate = 0.1`. Session replay is off (`sessionSampleRate` and `onErrorSampleRate` are 0), and screenshots and view hierarchies are not attached.

### Extensions

The widget and the intent extensions compile the same store-loading code, but they do not link Sentry. The SDK is a static binary of several megabytes, and each extension would embed its own copy. Those processes instead write a short, privacy-safe record into the app-group defaults. The app forwards that queue the next time it launches. Extension crash stacks are not reported.

## What is sent

- Crash reports, watchdog terminations, and app hangs: stack traces, OS and device model, app version, and the in-memory breadcrumb trail.
- One sampled performance trace in about ten launches (app start and view-controller class names). No Core Data, file, or network spans.
- Data-integrity breadcrumbs and captured events. Values are counts, booleans, file sizes, and short tokens such as `import` or `NSCocoaErrorDomain`. See the list below.

No Sentry user is set. `sendDefaultPii` is false, and scope persistence is off. `beforeSend` removes the user, the HTTP request, the device name, and identifier-like context fields. `beforeBreadcrumb` drops automatic breadcrumbs other than app, device, and view-controller lifecycle, and it drops those too when the message is not a class or lifecycle name.

In the Sentry project settings, turn on **Prevent Storing of IP Addresses** (Security & Privacy). The Cocoa SDK has historically left IP inference to the server even when the client sends no PII.

## What is not sent

- Transaction amounts, notes, dates, or currency codes
- Category names, emoji, or colours
- Merchant or payee text, budget names, or any other text the user typed
- Account identifiers, Apple ID, device name, IDFV, or a Sentry user id
- Screenshots, view hierarchies, or session replay
- Core Data predicates, SQL, or the contents of a backup file
- The full store path (it contains the app-container id)

Error objects are reduced to a domain and code chain before they are captured. CloudKit partial failures often embed the record that failed; that record is not included. Network failures during sync are breadcrumbs only, because an offline device would otherwise create an event on every retry.

## Events that diagnose missing data

These are the captured messages, in addition to ordinary crashes:

| Situation | Message |
| --- | --- |
| Migration finishes with fewer transactions, categories, budgets, or templates than before | Store migration reduced record counts |
| The store opens with zero transactions, the file or a pre-migration snapshot is non-trivial, and the user did not use Erase Data | Store loaded with no transactions |
| After iCloud is current, the store has fewer than half the transactions of the newest backup (and at least 10 were in the backup) | Transaction count is far below the newest backup |
| A CloudKit import or export ends with that same kind of drop, and it was not a bulk delete in the same moment | CloudKit sync reduced the transaction count |
| Store load, the pre-migration snapshot, a context save, a backup, a restore, or a non-network CloudKit event fails | The caught error, domain and code only |

Breadcrumbs (not their own issues) also cover: migration start and the pre-migration snapshot from the store copy kept before migrating, store load counts, iCloud sync preference changes, the legacy iCloud setting being carried over, CloudKit event start and finish, CSV import counts, backup written or skipped, restore started and finished, erase-all, and a bulk delete (a category, or 10 or more transactions). The pre-migration count is an integer read from the old store with migration disabled.

The empty-store and below-backup issues are sent once per app version so a launch loop cannot drain the quota. Erase Data suppresses the empty-store issue.

## Uploading dSYMs

Release builds of the `dime` target run `app/scripts/upload-dsyms.sh` after the other build phases. The script does nothing unless `CONFIGURATION` is `Release` and `SENTRY_AUTH_TOKEN` is set. When both are set, a missing `sentry-cli` or a failed upload fails the build so a release cannot ship without symbols by accident. Debug builds, including CI tests, skip the upload.

Create a Sentry auth token with `project:releases` and `org:read`, then expose it as `SENTRY_AUTH_TOKEN`. Do not commit the token, and do not put it in the build phase. `.sentryclirc` is gitignored.

Install the CLI on the machine that archives:

```sh
brew install getsentry/tools/sentry
```

For a local archive, put the token in the scheme's environment or in the shell before opening Xcode. For Xcode Cloud, add `SENTRY_AUTH_TOKEN` as a secret environment variable and install the CLI in `ci_scripts/ci_post_clone.sh`:

```sh
#!/bin/sh
brew install getsentry/tools/sentry
```

The existing GitHub Actions workflow runs tests in Debug and does not archive, so it does not upload symbols. An archive job only needs the secret in the environment; the build phase picks it up.

The build phase hides environment variables in the log (`showEnvVarsInLog = 0`). The script never prints the token.

## App Store privacy

Crash data, performance data, and other diagnostic data are declared in `app/dime/PrivacyInfo.xcprivacy` as collected, not linked to identity, and not used for tracking. The App Store Connect privacy label still has to be updated by hand: Crash Data and Performance Data / Other Diagnostic Data, not linked to the user's identity, not used for tracking.
