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

## Still pending

- Full field-by-field parity with the existing Streamlit registers.
- Review and validation of date fields, duplicate rules, and required fields.
- Automated tests and actual Android-device testing.
- Android platform project generation and release APK build.
- Officially formatted PDF/print output (Hindi font embedding is required before reliable PDF generation).
- Dak attachments/photos, Excel import/export, and backup/restore.
- Database encryption, app lock, backup encryption, restore validation, and device-loss recovery.
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

The database is currently an initial SQLite implementation and is not encrypted. Before real police/court records are entered, database encryption, app lock, backup encryption, restore validation, and device-loss recovery must be implemented and tested. Do not use this build for production records yet.

## Migration policy

The original Streamlit app and its source files remain untouched. Legacy Google Sheets data will only be imported after an explicit export/selection and a row-count/reconciliation check. No existing source records will be deleted.
