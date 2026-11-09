# Court Case Manager — Android Offline App

This folder is the new Flutter Android application. The existing Streamlit app at the repository root is intentionally preserved during migration.

## Direction

- Android-first Flutter application.
- SQLite database stored in Android app-private storage.
- No Google Sheets, Google Drive, or internet dependency for normal case work.
- Export/import and backup will be implemented as explicit user actions.
- Existing registers and V2 modules will be migrated incrementally.

## Current scaffold

- Flutter Material 3 dashboard.
- Local SQLite database initialization.
- Initial schema for Session Court, Dak, Remand, Address Book, documents, timeline, checklist, analysis, drafts, versions, audit log, and app settings.
- Dashboard counts.

This is a foundation, not a completed replacement APK. Register CRUD screens, attachments, import/export, backup/restore, database encryption, and migration verification remain to be implemented and tested.

## Build

Install Flutter SDK and Android SDK, then from this directory:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The release APK is generated at `build/app/outputs/flutter-apk/app-release.apk`.

## Data safety

The database is currently an initial SQLite scaffold. Before real police/court records are entered, database encryption, app lock, backup encryption, restore validation, and device-loss recovery must be implemented and tested. Do not use this scaffold for production records yet.

## Migration policy

The original Streamlit app and its source files remain untouched. Legacy Google Sheets data will only be imported after an explicit export/selection and a row-count/reconciliation check. No existing source records will be deleted.
