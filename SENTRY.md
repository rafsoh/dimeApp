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

Error objects are reduced to a domain and code chain before they are captured. Crash reasons go through `DataIntegrityLog.redactedExceptionReason` in `beforeSend`: Core Data exception reasons describe the record involved (amount, currency, dates, note), so everything from `data: {` on, `x-coredata://` store ids, and quoted text are removed. CloudKit partial failures often embed the record that failed; that record is not included. Network failures during sync are breadcrumbs only, because an offline device would otherwise create an event on every retry.

## Events that diagnose missing data

These are the captured messages, in addition to ordinary crashes:

| Situation | Message |
| --- | --- |
| Migration finishes with fewer transactions, categories, budgets, or templates than before | Store migration reduced record counts |
| The store opens with zero transactions, though the previous load (in any process) had more than the person has deleted since | Store emptied unexpectedly |
| After iCloud is current, the store plus what the person deleted since the newest backup is under half that backup (and at least 10 were in the backup) | Transaction count is far below the newest backup |
| A CloudKit import or setup ends with that same kind of drop, and it was not a bulk delete in the same moment. The event names the two history authors that deleted the most transactions since the event began. | CloudKit sync reduced the transaction count |
| CloudKit setup fails and leaves the store out of the coordinator; the app opens it again without iCloud for the rest of the launch | Store reopened without iCloud after CloudKit setup removed it |
| Store load, the pre-migration snapshot, a context save, a backup, a restore, or a CloudKit event fails, other than for the network or with 134400 or 134419 | The caught error, domain and code only. Partial CloudKit failures add their per-record codes as `partialCodes`. |
| The store failed to open, then opened on the second attempt a second later | Persistent store loaded on the second attempt |

Breadcrumbs (not their own issues) also cover: migration start and the pre-migration snapshot from the store copy kept before migrating (including `pre-migration snapshot made by SQLite after Core Data refused`, when Core Data's copy failed and SQLite's online backup made it instead), store load counts, iCloud sync preference changes, the legacy iCloud setting being carried over, CloudKit event start and finish, CSV import counts, backup written or skipped, restore started and finished, erase-all, and a bulk delete (a category, or 10 or more transactions). The pre-migration count is an integer read from the old store with migration disabled.

The empty-store and below-backup issues are sent once per app version so a launch loop cannot drain the quota. Counts that can't be read are left out of these checks rather than read as 0; a failed read used to look like every row was gone.

Counting happens on a background context, and only around CloudKit imports and setup. Exports follow every save, and counting on the main thread for each one waited on the store while CloudKit held it.

## iCloud with no account

The app remembers what CloudKit last said about the iCloud account. When that was no account or a restricted one, the next launch opens the store without mirroring, and the person's sync preference stays as it was. With mirroring on and no account, CloudKit setup failed with 134405 and the transaction count read 0 right after, and CloudKit clears a mirrored store's records when the account goes away. Settings still shows the iCloud status, which asks the person to sign in. The first launch after iCloud reports an account mirrors again.

## Out of storage

Before migrating, the app copies the store only when the volume has room for the copy and for the migration after it (twice the store and its write-ahead log, plus 20 MB). Otherwise it first deletes all but the newest earlier copy, and if that still isn't enough it skips the copy and leaves a `pre-migration snapshot skipped for lack of space` breadcrumb. A copy that fails partway is deleted. When a save fails, the changes stay in the view context and the person is told: "Dime couldn't save your changes", with a storage-specific message when the device is full. The save is tried again each time the app returns to the foreground. Each kind of save failure is sent once per launch; repeats are breadcrumbs, since a full disk fails every save after it.

## When the store won't open

A store that fails to load no longer crashes the app. The app tries once more after a second, and if that fails too it shows a screen that says the data is still on the device, with Try Again and Contact Support, and the error's domain and code. Nothing is changed or deleted. If the failure is the device running out of storage (SQLite code 13, a file write out of space, or ENOSPC anywhere in the error chain), the screen says so and asks the person to free up space first. Only the app migrates the store: the widget and intents extensions open it without migration, so they can't race the app (the cause of `NSMigrationError` 134110 on the first launch after an update) or be stopped partway through by their memory limit. Until the app has migrated the file, an extension leaves it closed and its widgets show nothing; the app reloads them once the migration finishes.

## Uploading dSYMs

Release and Archive builds upload each shipping target's dSYM. The run script phase "Upload Debug Symbols" is on `dime`, `ExpenditureWidgetExtension`, `BudgetIntent`, and `BudgetIntentUI`, and it runs `app/scripts/upload-dsyms.sh` last. Shortcuts are compiled into the app, so they are in the app dSYM. The test target does not upload.

The phase runs only when `CONFIGURATION` is `Release` or the build action is an archive (`ACTION=install`). Debug builds, including the GitHub Actions test job, skip it. Project Release already sets `DEBUG_INFORMATION_FORMAT` to `dwarf-with-dsym`, and each shipping target sets the same value on its Release configuration so an extension cannot ship without a dSYM. `ENABLE_USER_SCRIPT_SANDBOXING` is `NO` so the phase can read the dSYM directory and `~/.sentryclirc`.

A missing `sentry-cli`, a missing token, a missing dSYM, or a failed upload prints a warning and exits 0. The build is not failed. That includes Debug builds, simulator builds, and forks that do not have a token.

### Where the token lives

The token is never committed and is never passed as a command argument. The script checks, in order:

1. The `SENTRY_AUTH_TOKEN` environment variable.
2. A gitignored `.sentryclirc` at the repository root.
3. `~/.sentryclirc`.

Org `dime-1x` and project `dime-ios` are set by the script. They are not secret. The org is on the US region (`sentry.io`), which is sentry-cli's default host.

Create an organization auth token with debug-file upload permission (`project:releases`) under Sentry → Settings → Organization Tokens.

Local archives: put this in `~/.sentryclirc` (or in `.sentryclirc` at the repo root):

```ini
[auth]
token=YOUR_TOKEN
```

Or export `SENTRY_AUTH_TOKEN` in the shell before opening Xcode. Quit and reopen Xcode if it was already open, so the GUI process inherits the variable. Do not put the token in the build phase.

Install the CLI on the machine that archives. The script looks on `PATH`, then Homebrew on Apple Silicon (`/opt/homebrew/bin/sentry-cli`) and Intel (`/usr/local/bin/sentry-cli`), then a `sentry-cli` binary inside the Sentry Cocoa SPM checkout if that package ever provides one. The 9.35.0 package does not, so Homebrew is the path to use:

```sh
brew install getsentry/tools/sentry
```

### CI

This repo does not archive on CI. `.github/workflows/ios.yml` runs tests in Debug and does not upload symbols. There is no Xcode Cloud `ci_scripts` directory.

The variable name, if a release archive is added later, is `SENTRY_AUTH_TOKEN`:

- GitHub Actions: a repository secret named `SENTRY_AUTH_TOKEN`, passed to the archive step as the environment variable `SENTRY_AUTH_TOKEN`.
- Xcode Cloud: a secret environment variable named `SENTRY_AUTH_TOKEN` on the workflow. Install the CLI in `ci_scripts/ci_post_clone.sh` with `brew install getsentry/tools/sentry`, because the image may not include it. The build phase reads the same variable.

### Verifying an upload

Archive the `dime` scheme (Product → Archive) with a token and sentry-cli installed. The build log should include `Sentry: dSYM upload finished for dime` and the same line for `ExpenditureWidgetExtension`, `BudgetIntent`, and `BudgetIntentUI`.

Then list what Sentry stored:

```sh
sentry-cli debug-files list --org dime-1x --project dime-ios
```

Match a UUID from that list to the archive with `dwarfdump --uuid` on the `.dSYM` inside the `.xcarchive`. The same files are listed in the Sentry UI under dime-ios → Settings → Debug Files. A crash from a build that uploaded its dSYMs shows file, function, and line. An older event stays unsymbolicated until it is reprocessed.

## App Store privacy

Crash data, performance data, and other diagnostic data are declared in `app/dime/PrivacyInfo.xcprivacy` as collected, not linked to identity, and not used for tracking. The App Store Connect privacy label still has to be updated by hand: Crash Data and Performance Data / Other Diagnostic Data, not linked to the user's identity, not used for tracking.
