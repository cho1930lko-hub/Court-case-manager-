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
- Restore checks the backup format, authenticates/decrypts it, validates the SQLite header and `PRAGMA integrity_check` in a temporary database before replacing current data.

## Still pending

- Full field-by-field parity with the existing Streamlit registers.
- Document version history browsing/rollback and stronger file integrity checks.
- Audit log tamper resistance/export and user/device attribution (currently local app log only).
- Review and validation of date fields, duplicate rules, and required fields.
- Automated tests and actual Android-device testing.
- Android platform project generation and release APK build.
- Officially formatted PDF/print output (Hindi font embedding is required before reliable PDF generation).
- Dak attachments/photos, Excel import/export, and backup/restore.
- Live SQLite database encryption at rest (current database file remains unencrypted).
- PIN attempt throttling, recovery flow, security review, and full restore rollback testing.
- Backup compatibility tests across app/schema versions and verification of document file completeness.
- Legacy data import and row-count reconciliation.

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

The live SQLite database is still not encrypted at rest. The app PIN and encrypted backup are initial implementations and have not yet passed Android-device security testing. Restore replaces current local data after a confirmation; make a separate backup first. Do not use this build for real police/court records until database encryption, lockout/recovery, backup/restore and attachment integrity have been independently tested.

## Migration policy

The original Streamlit app and its source files remain untouched. Legacy Google Sheets data will only be imported after an explicit export/selection and a row-count/reconciliation check. No existing source records will be deleted.
