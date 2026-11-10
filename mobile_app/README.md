# Court Case Manager — Android Offline App

This folder is the new Flutter Android application. The existing Streamlit app at the repository root is intentionally preserved during migration.

## Direction

- Android-first Flutter application.
- SQLite database stored in Android app-private storage.
- No Google Sheets, Google Drive, or internet dependency for normal case work.
- Export/import and backup will be implemented as explicit user actions.
- Existing registers and V2 modules will be migrated incrementally.

## Phase 1 progress

- Dashboard with live counts for cases, Dak, Remand, documents, and contacts.
- Session Court: initial add, edit, search, and soft-archive workflow.
- Dak Register: add, edit, and search.
- Remand Register: add, edit, and search.
- Address Book: add, edit, and search.
- Local SQLite CRUD helpers and audit entries for register changes.
- GitHub Actions workflow added for Flutter dependency resolution and static analysis.

## Phase 2 progress

- Initial summons draft generator linked to a selected Session Court case.
- Initial action-report draft generator using case details and user-entered proceedings.
- Generated drafts are stored in the local SQLite database and logged in the audit log.
- Draft preview is selectable and can be copied for review/editing.

## Phase 3 progress

- Case Timeline: date-wise case events can be recorded and reviewed.
- Action Checklist: tasks can be added, assigned, given a due date, and marked complete/reopened.
- Case Document Library: files are copied into app-private storage and linked to a selected case.
- Document Version History: adding a revised file records a version entry and updates the current document pointer.
- Audit Log viewer: recent recorded app actions can be reviewed in read-only form.

## Phase 4 progress

- Mandatory 6–8 digit app PIN setup; PIN hash is derived with PBKDF2-HMAC-SHA256 and stored using Android secure storage.
- App returns to the lock screen when the app becomes inactive/backgrounded.
- Password-protected backup format uses PBKDF2-HMAC-SHA256 (310,000 iterations) and AES-256-GCM authenticated encryption.
- Backup includes the SQLite database and app-managed case document files.
- Restore checks the backup format, authenticates/decrypts it, validates the encrypted SQLCipher database and `PRAGMA integrity_check` in a temporary database before replacing current data.

## Phase 4 security implementation

- Live SQLite storage now uses SQLCipher; a random 256-bit database key is stored in Android secure storage.
- Existing plaintext SQLite files are migrated through `sqlcipher_export` to a temporary encrypted database, integrity-checked, and only then swapped into place. The original file is retained if migration fails.
- PIN failures are throttled: after five failures, the wait grows from 30 seconds up to 15 minutes. PIN changes require the current PIN.
- Encrypted backups include the SQLCipher database key only inside the AES-256-GCM encrypted archive, allowing restore on another device.
- Restore authenticates/decrypts the archive, validates the encrypted database using SQLCipher, stages document files, and keeps rollback copies while swapping data.
- For Android release builds with code shrinking, add `-keep class net.sqlcipher.** { *; }` to `android/app/proguard-rules.pro` after generating the Android platform project.

## Phase 5 progress

- CI now runs dependency resolution, Flutter analysis, automated tests, and generates an Android debug APK on GitHub Actions.
- Added automated validation tests for 6–8 digit PIN rules and the minimum backup-password length.
- Updated deprecated Flutter form-field initial-value arguments and removed an unused import.
- Backup creation and restore now request a WAL truncate checkpoint and refuse to continue when SQLite reports a busy checkpoint.
- CI adds SQLCipher ProGuard keep rules to its generated Android build and publishes the debug APK as a short-lived build artifact when all checks pass.

## Phase 6 — Dynamic Fields and Register Import/Export

- Added an additive SQLCipher schema migration for dynamic field definitions, dropdown options, per-role field metadata, custom values, import profiles and import history. Existing register rows and fixed columns are preserved.
- Dynamic custom fields can be created per module, marked required, configured as text/number/date/dropdown/multiline/boolean metadata, and rendered in Session Court, Dak, Remand and Address Book entry forms. Custom values are saved in the same transaction as the register change and audit event.
- Added Excel (.xlsx) import and Excel export from the module screens. Column headers are auto-matched with Hindi/English aliases and can be manually mapped.
- Added row-level preview, duplicate/required-field checks and selection before import. Imports are additive; existing records are not overwritten. Import result and source are recorded in the local audit/import history.
- Export includes the selected register data and configured custom-field values.
- Google Sheets direct API sync is intentionally not enabled; download the sheet as .xlsx and import locally to preserve offline-first operation and avoid silently connecting court records to a cloud account.

## Still pending

- Full field-by-field parity with the existing Streamlit registers.
- Document version history browsing/rollback and stronger file integrity checks.
- Audit log tamper resistance/export and user/device attribution (currently local app log only).
- Role enforcement against individual authenticated staff accounts (role metadata is currently configurable but the app does not yet have multi-user sign-in).
- Automated tests and actual Android-device testing.
- Android platform project generation and release APK build.
- Officially formatted PDF/print output (Hindi font embedding is required before reliable PDF generation).
- Dak attachments/photos.
- Android-device verification of SQLCipher migration, key storage, lockout behavior, backup portability and restore rollback.
- PIN recovery is intentionally not bypassable: use a verified encrypted backup on a clean installation/device and set a new local PIN. The backup password and backup file must both be available.
- Backup compatibility tests across future app/schema versions and file completeness checks.
- Legacy data import and row-count reconciliation against all original registers.

## Build

Install Flutter SDK and Android SDK, then from this directory:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The release APK is generated at `build/app/outputs/flutter-apk/app-release.apk` after Android platform files are generated.

## Data safety

The live SQLite database uses SQLCipher and its key is stored in Android secure storage. These changes have not yet passed Android-device security testing. Keep at least two verified encrypted backups in separate safe locations. PIN reset is not bypassable; on a new device restore a verified backup and set a new PIN. If the database key is lost and no valid backup exists, local data may be unrecoverable. Do not use this build for real police/court records until the migration, key lifecycle, lockout, backup/restore, app lifecycle and attachment integrity have been tested on a physical Android device.

## Migration policy

The original Streamlit app and its source files remain untouched. Legacy Google Sheets data will only be imported after an explicit export/selection and a row-count/reconciliation check. No existing source records will be deleted.


## Phase 8 — Download and install a test APK

The `phase8-data-migration` branch now has an Android Debug APK workflow. It generates the Android platform scaffold in the CI runner, applies the Android backup hardening and SQLCipher keep rule, runs Flutter tests/analyzer, and builds a debug APK.

1. Open the repository's **Actions** tab.
2. Select **Android Debug APK** and open the latest successful run for `phase8-data-migration`.
3. Under **Artifacts**, download `court-case-manager-debug-apk`.
4. Extract the ZIP; it contains `app-debug.apk`.
5. Transfer the APK to the Android phone and install it. If Android asks, allow installation from that file manager/browser for this one install.
6. Open the app and test with dummy records first. Do not import live court/police records until the SQLCipher, backup/restore and reconciliation gates are approved.

This is a debug/test APK, not a signed production release. Android platform files are generated in CI and are not committed into the source branch. The APK artifact is retained for 14 days per workflow settings.
