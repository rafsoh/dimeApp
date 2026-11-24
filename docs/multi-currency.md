# Multiple currencies

How Dime stores, converts and syncs amounts in more than one currency, and what has to stay true as the
app grows. The top priority is that no data is ever lost.

## Data model

`MainModel 3` adds one attribute to one entity:

| Entity | Attribute | Type | Optional | Default |
| --- | --- | --- | --- | --- |
| `Transaction` | `currencyCode` | String (ISO 4217, upper case) | yes | none |

Nothing else changed: amounts are still `Double`, and `Budget`, `MainBudget`, `TemplateTransaction` and
`Category` are exactly as in `MainModel 2`. The attribute is optional with no default, which is what
CloudKit requires and lets Core Data migrate existing stores lightweight. Before migrating,
`StoreSnapshot` keeps a SQLite copy of the untouched store in `PreMigrationSnapshots`.

`Transaction.currencyCode` is the currency of that transaction's `amount`, and it is authoritative.
Nothing else decides what currency a stored amount is in.

## What a missing currency means

`currencyCode == nil` means "the user's main currency": the `currency` value in the app group defaults
(`group.com.rafaelsoh.dime`), which is synced between devices through `NSUbiquitousKeyValueStore`. That is
exactly what every transaction meant before currencies were stored, so migration writes nothing.

`nil` is a legacy value only:

- No automatic process rewrites existing transactions. The only bulk writes are the two choices offered
  when the user changes their main currency (below).
- Every transaction created by this version names its currency: the app, CSV import, the New Transaction
  shortcut, templates and recurring occurrences (which copy their parent's currency, including a legacy
  `nil`). Backups restore whatever the backup holds.
- **Before transactions ever move into a store shared with other people, every `nil` row must be stamped
  with an explicit code**, through the same path as the "Convert" choice: user initiated, backed up first,
  only once the store is current with iCloud, in resumable batches that change nothing but
  `currencyCode`. Participants can have different main currencies, so `nil` would mean different things to
  each of them.

## The one place a new transaction's currency is chosen

`CurrencyPreferences.defaultCurrency(mainCurrency:multipleCurrenciesEnabled:recent:)`, called through
`DataController.currencyForNewTransaction()`. It returns the last currency used while the Multiple
Currencies Feature Lab option is on, and the main currency otherwise. When accounts arrive, an account's
default currency goes here, between the last used currency and the main currency. Templates have no
currency and always create transactions in the main currency.

## Conversion

- Conversion happens when amounts are read, always into the *viewer's* main currency. Converted amounts and
  rates are never written to Core Data or CloudKit, and nothing per viewer is synced.
- Every total goes through `CurrencyConverter`. Amounts with no currency or in the main currency are added
  exactly as before, in the same order, so the totals are bit-for-bit what they were
  (`MoneySummingEquivalenceTests`).
- An amount whose rate isn't known is never treated as 1:1. It is left out of the total and counted in the
  total's `ConversionReport`, and the UI says so: "≈ $1,240 · 2 excluded".
- Budgets stay in the main currency. Spending against a budget is the converted sum of its transactions.
- Nothing in the conversion, totals, backups, CSV or currency picker code assumes a transaction has a
  category.

## Exchange rates

`ExchangeRateStore` keeps daily rates as JSON in the app group container
(`ExchangeRates/rates.json`), so the widgets and intents can read them. Only the app fetches.

- One pivot: every rate is "units per US dollar", and a cross rate is `r[B] / r[A]`.
- Each transaction converts at the rate on its own date. Lookup order: that date, then the nearest earlier
  cached date that has the currency, then the latest rates. Otherwise the amount is unconvertible.
- Providers, free and keyless:
  - [fawazahmed0/exchange-api](https://github.com/fawazahmed0/exchange-api): `latest` or a date tag without
    zero padding (`2025.3.1`) on jsDelivr, with the `currency-api.pages.dev` mirror as a fallback. Over 200
    currencies, history from 2 March 2024.
  - [Frankfurter](https://frankfurter.dev) (European Central Bank): about 30 currencies back to 1999, used
    for dates before March 2024 (a year per request) and when exchange-api fails.
- Historical days are cached forever; the latest rates are refreshed at most once a day, or from Settings ›
  Exchange Rates. Only days that have foreign-currency transactions are fetched, up to 40 requests per
  refresh with a short pause between them. Without foreign transactions nothing is fetched at all.
- A cache file that can't be read is deleted and rebuilt. It never crashes the app.

## Changing the main currency

Settings › Currency asks, while Multiple Currencies is on:

- **My transactions were actually in X** (relabel): transactions labelled with the old main currency are
  relabelled X, and those without a currency follow the main currency. This is what changing the currency
  always did, and it's what happens without asking while the feature is off.
- **Convert to X**: transactions without a currency are labelled with the old main currency, then the main
  currency becomes X, so they're converted from then on.

Both refuse to start until `DataController.isDataCurrentWithICloud` is true, take a JSON backup through
`BackupManager.backUpNow` and stop if it fails, store the plan in the app group defaults, then change only
`currencyCode` on a background context in batches of 500 with predicate-scoped fetches. Changed rows stop
matching the predicate, so an interrupted change resumes on the next launch (or when the store is current
with iCloud) and changes nothing once it's done. The main currency only switches after every batch is
saved. When no transaction needs changing, the currency switches straight away, as before.

## Sync and older versions

- The new attribute syncs as `CD_currencyCode`. **Before releasing, run a Debug build with the
  `-initializeCloudKitSchema` launch argument against the development environment, then deploy the schema
  to production in the CloudKit Dashboard.** A release whose schema isn't deployed fails to export
  transactions that have a currency.
- Older app versions ignore the attribute. They show a foreign amount as if it were in the main currency
  (¥1,200 reads as $1,200 in their totals), but the stored amount and currency are untouched. Their own
  model has no `currencyCode`, so they never write one; NSPersistentCloudKitContainer is expected to leave
  the field alone when such a device edits another attribute of the record. That expectation hasn't been
  verified yet and is part of the manual test plan (edit a foreign transaction on the App Store build, then
  check the currency on the new build).
- Older versions restoring a backup written by this version ignore the currencies in it. This version
  refuses backups from a newer format than it knows rather than dropping their fields.
- The main currency is synced through iCloud key-value storage. If another device has a different main
  currency it adopts this one on launch; transactions stamped or relabelled here reach it through
  CloudKit.

## Backups and CSV

- Backup format version 2 adds `currencyCode` to each transaction. Version 1 files still restore (every
  currency `nil`). Restoring never changes existing objects, and id-less rows from old versions still match
  by date, amount, note and type, without the currency.
- CSV export appends a `Currency` column at the end, so earlier columns keep their positions. Rows without a
  currency are exported with the main currency, and three-digit currencies keep three decimals.
- CSV import accepts an optional column of ISO codes. Empty cells use the main currency; codes Dime doesn't
  know are skipped and reported, never read as the main currency.

## Future work to keep in mind

- **Accounts** will each have a default currency, used only as the default for new transactions (see
  above). `Transaction.currencyCode` stays authoritative.
- **Transactions without categories**: the currency code paths already allow `category == nil`.
- **Sharing** accounts, transactions and budgets through CloudKit sharing: stamp legacy `nil` rows first
  (above). Each participant converts to their own main currency when reading; rates and converted amounts
  stay local. A shared budget's currency would need its own field then, which is a schema change for later.
