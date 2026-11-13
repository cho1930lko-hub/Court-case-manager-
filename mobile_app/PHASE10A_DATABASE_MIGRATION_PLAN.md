# Phase 10A — Database Migration Compatibility Plan

This document records the verified migration collision between the ZIP source and the Phase 8 GitHub baseline. It is deliberately a plan, not an executable migration.

## Verified version difference

- GitHub working branch: `mobile_app/lib/data/local_database.dart` opens database version **5**.
- ZIP source: same logical file opens database version **9**.
- ZIP upgrade dispatcher adds:
  - v5 → v6: rebuilds/normalizes the separate `field_defs` table and adds `extras` to selected register tables.
  - v6 → v7: creates `sync_state`.
  - v7 → v8: creates eCourts import/audit tables.
  - v8 → v9: creates hearing/worklist tables.
- GitHub Phase 8 baseline has a distinct Dynamic Field Manager schema:
  - `field_definitions`, `field_options`, `field_values`, `field_permissions`, `import_history`, `import_row_errors`.
  - It also has Phase 8 compatibility repairs for the overlapping v4 field-table creators.

## Critical incompatibility

The ZIP v5→v6 migration operates on `field_defs` (a separate sheet-mapping/field-definition system). The GitHub Phase 8 code shown in this branch uses `field_definitions` and related tables for the Dynamic Field Manager. These are not interchangeable tables.

Therefore, do **not** copy the ZIP's `_migrateV5ToV6` wholesale into the GitHub migration dispatcher, and do not rename/drop GitHub's `field_definitions`, `field_values`, or related tables to match the ZIP. Doing so risks breaking the Field Manager and losing user-defined metadata.

## Safe integration design

1. Preserve GitHub v1–v5 migration code and the complete `ensurePhase8MigrationSchema` repair.
2. Add a new version 6 migration specifically for the GitHub schema. It must be written as idempotent additive DDL, guarded by `PRAGMA table_info` and `sqlite_master` checks.
3. Before adding ZIP's `extras` columns, inspect each target table and add only missing columns. Preserve every existing row and value.
4. Create `sync_state`, eCourts tables, and worklist tables with `CREATE TABLE IF NOT EXISTS`; verify indexes and uniqueness constraints separately.
5. Do not import the ZIP's `field_defs` table migration unless the complete ZIP feature set that reads/writes `field_defs` is also being ported. If required, keep it as a distinct namespace and test it independently.
6. Do not alter SQLCipher key handling, database path, encryption, or plaintext migration as part of this feature port.

## Required pre-merge test matrix

- Fresh install: create latest schema and verify all expected tables/indexes.
- Existing v5 Phase 8 database: migrate a byte-for-byte copy to latest schema.
- Re-run migration helper against an already-latest schema to prove idempotence.
- Verify row counts and primary-key sets for `cases`, `dak_register`, `remand_register`, `address_book`, `case_documents`, `case_timeline`, `case_checklist`, `evidence_items`, `field_definitions`, `field_options`, `field_values`, `field_permissions`, `import_history`, and `import_row_errors`.
- Run `PRAGMA integrity_check` and `PRAGMA foreign_key_check`.
- Verify custom fields and import error history remain readable and writable.
- Verify rollback behavior: deliberately fail a migration on a disposable DB copy and confirm the source copy remains unchanged.
- Only after these pass, port the Worklist data-access layer and UI.

## Current decision

No executable schema migration is committed yet. The exact v5→v6 DDL must be authored against the complete Phase 8 schema and ZIP v6–v9 table definitions, then validated on disposable database fixtures. No live device database or production data was opened or modified.
