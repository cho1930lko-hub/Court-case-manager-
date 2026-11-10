# Phase 7 — Data Safety & Database Audit

**Scope:** Static source review of `mobile_app/` on `android-offline-v1`.
**Baseline commit:** `aeb41cd20997ec3a2f0a3511557bce0c1dc2f208`.
**Status:** Initial audit findings. No production data was accessed; no Android device test was performed.

## Confirmed protections already present

- Local database uses `sqflite_sqlcipher`; its 32-byte random key is stored through `flutter_secure_storage`.
- Plain SQLite-to-SQLCipher migration creates a temporary encrypted copy, checks `PRAGMA integrity_check`, and retains a rollback path if replacement fails.
- Backup uses PBKDF2-HMAC-SHA256 (310,000 iterations) and AES-256-GCM. The archive includes the database, database key, case documents, and evidence attachments.
- Restore validates the authenticated envelope, archive entries and paths, validates the encrypted database before replacement, and keeps rollback copies until the restored database passes an integrity check.
- PIN storage uses salted PBKDF2-HMAC-SHA256 (310,000 iterations), accepts 6–8 ASCII digits, and applies escalating lockout after repeated failures.
- Current case and register forms call `saveWithAudit`; the method performs record changes, custom-field writes, and audit insertion in a database transaction. Case archive also has a transactional audit method.

## Findings and priority

### P0 — Must resolve before production records

1. **Real-device recovery tests are not evidenced.** The Backup screen itself warns that SQLCipher migration, secure key storage, App Lock, and Backup/Restore still need testing on a real Android device. Do not treat source inspection or a successful debug build as proof of recovery safety.
2. **No full backup/restore round-trip or failure-injection test was found in the current test file.** Existing tests cover PIN format, path validation, malformed backup input, wrong password, and short-password rejection. Add tests for database + attachment round-trip, wrong-key rollback, corrupt database rejection, and restore interruption/rollback.
3. **The local audit log does not identify the operator.** `audit_log` has action/module/record/details/time but no staff/device actor identity. A shared PIN also cannot establish which staff member performed an action. This is not a tamper-proof legal audit trail.

### P1 — Fix during Phase 7

4. **Import reports counts, not row-level causes.** `importRegisterRows` catches row exceptions and increments `errors`, then commits other successful rows in the same transaction. This is partial-success behavior, despite the “atomically” comment. The UI cannot tell the user why each failed row failed. Preserve the safe no-overwrite behavior, but return row number + reason and make partial success explicit.
5. **Dynamic-field schema creation is duplicated.** `_createDynamicFieldTables` and `_createDynamicDataTables` both create overlapping tables with differing column definitions (including field definitions/options/import history) and different custom-value table names. Current call order makes some definitions win silently; consolidate into one canonical schema and versioned migrations only after tests cover existing version-4 databases.
6. **Archived cases have no visible restore workflow.** Archive is soft-delete and logged, but the case list/search filters archived cases and no archive browser/restore action was found. Add a recoverable archive view before relying on archive as a safe removal mechanism.
7. **PIN change screen is present but not reachable from main navigation.** `change_pin_screen.dart` exists, but `main.dart` does not import or link it. Add a safe route from Security settings after verifying the current PIN.

### P2 — Hardening and maintainability

8. Legacy non-audited database methods (`saveCase`, `saveRegister`, `archiveCase`, `logAction`) remain alongside the audited APIs. Current visible forms use `saveWithAudit`, but future callers could bypass audit accidentally. Deprecate/remove unused legacy mutation methods after call-site verification.
9. Document-version history exists, but the direct `updateDocumentVersion` method updates the current document row without inserting a version-history/audit entry. Review and remove or harden this alternate path.
10. The current app lock is a shared local gate, not per-staff authentication or role enforcement. Do not present field permission metadata as enforced authorization.

## Phase 7 implementation order

1. Add automated database migration, backup/restore, rollback, and import tests using synthetic records only.
2. Consolidate schema creation without changing existing data; introduce an explicit migration from current schema version 4 and test upgrades from each supported older version.
3. Improve import validation/reporting while preserving existing-record no-overwrite behavior.
4. Add archive browse + restore with transactional audit.
5. Wire Change PIN into Security settings and verify old PIN before replacement.
6. Remove/deprecate unsafe alternate mutation APIs after confirming no callers remain.
7. Build a release candidate and execute the documented test matrix on a real Android device before production data is entered.

## Safety boundary

No production records, Google Sheets, Streamlit data, main branch, or release deployment were changed by this audit. Use synthetic test records until on-device migration and restore tests pass.
