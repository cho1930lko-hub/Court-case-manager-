# Phase 10 — ZIP Integration Assessment

Status: assessment only; no application feature files have been copied yet.

## Source and target

- Source artifact: `CourtCaseManager.zip` (Flutter project at archive root).
- Target: `mobile_app/` on `codex/phase10-zip-improvements`.
- Integration base: `phase8-data-migration`.
- `main` and the source branches remain untouched.

## Confirmed source additions in the ZIP

- Worklist domain and SQL: `lib/core/worklist_engine.dart`, `lib/core/worklist_sql.dart`, `lib/core/dashboard_sql.dart`.
- Worklist UI: `lib/screens/daily_worklist_screen.dart`, `lib/widgets/dashboard_work_section.dart`.
- Hearing update and history UI: `lib/screens/hearing_update_screen.dart`.
- Weekly reporting: `lib/core/weekly_report.dart`, `lib/screens/weekly_report_screen.dart`.
- Database source reports schema version 9 and adds `hearing_history`, `case_tasks`, and `case_task_history`.

## Compatibility blockers found

1. The target branch currently has a different application baseline: its database is version 5, and it does not contain the ZIP's Worklist domain/UI files.
2. The target does not contain the ZIP's `core/dates.dart`, `core/hearings.dart`, or `utils/dates.dart` at the expected paths. Copying Worklist files alone would therefore leave unresolved imports.
3. The ZIP's `local_database.dart` is a substantially different implementation from the target's database file. Replacing it wholesale could discard target-side Phase 8 migrations and methods.
4. The ZIP's database migration path includes v6–v9 steps. These must be reconciled with the target's current v5 schema and Phase 8 schema before any migration code is merged.
5. The ZIP does not provide a complete reproducible build input set: `pubspec.lock`, Gradle wrapper files, and a verified build/test result were not present in the archive review.

## Security handling

- Do not copy `android/key.properties`, any real `.jks`/keystore, signing passwords, private keys, or API secrets.
- Signing must be supplied through a secure local/CI secret mechanism, not committed to Git.
- Root `.gitignore` and `mobile_app/SECURITY.md` have already been committed on this working branch.

## Integration sequence

1. Reconcile the source and target database schemas/migrations (v5 → compatible additive migration), preserving Phase 8 tables and records.
2. Port pure domain helpers and tests after resolving their import/API differences.
3. Port the Worklist SQL and database methods with transaction and deduplication tests.
4. Port hearing update flow and its navigation/actions.
5. Port dashboard and weekly report UI.
6. Port notification scheduling only after checking Android manifest, notification plugin versions, timezone initialization, and reboot behavior.
7. Run formatter, analyzer, unit tests, Android debug build, and a migration test using a copy of a v5 database before considering a merge.

## Known functional checks required before release

- Closed/finished cases must not reappear as upcoming actionable work.
- Pending summons must not create actionable work for closed cases unless explicitly intended.
- Task ordering must account for due date as well as priority.
- Each work-item type must navigate to the correct action (not always the hearing-update screen).
- Existing records must survive migration; no destructive table rebuild or data reset.
- Reminder rescheduling and sync startup must not race database initialization.

## Current verification status

- Repository security baseline changes: committed.
- ZIP source inventory and compatibility blockers: assessed.
- Feature integration: not yet performed.
- Flutter analyze/tests/build: not yet run.
- Production database: not accessed or modified.
