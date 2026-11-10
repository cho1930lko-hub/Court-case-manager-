# Phase 7 — Data Safety Implementation Tracker

**Working branch:** `phase7-hardening`
**Parent:** `phase8-data-migration` (preserves the Phase 8 planning and import-alias work)
**Safety boundary:** Synthetic data only. Do not import production register records until every P0 test and the Android recovery test matrix passes.

## Scope and execution order

### P0 — Recovery and data integrity (blocking)
- [ ] Add automated tests for SQLCipher database migration from plaintext SQLite; prove original file remains intact on failed migration.
- [ ] Add encrypted backup/restore round-trip test containing a database, SQLCipher key, case document and evidence attachment.
- [ ] Add negative restore tests: wrong password, malformed envelope, missing DB/key, invalid key, duplicate archive names, traversal paths, oversized archive and corrupt encrypted database.
- [ ] Add restore failure-injection tests at each replacement boundary; prove database, key and both managed attachment roots roll back together.
- [ ] Execute the migration and backup/restore matrix on a real Android device (including app restart after restore). Source inspection alone is not acceptance.
- [ ] Decide and implement reliable local operator attribution for audit events, or explicitly document the limitations of a shared local PIN.

### P1 — Safe operation
- [ ] Consolidate duplicate dynamic-field schema creation using versioned migrations; preserve existing schema-v4 data.
- [ ] Return row-level import errors and make partial-success behavior explicit.
- [ ] Add archive browse and audited restore workflow.
- [ ] Add Change PIN entry under Security settings; verify current PIN before change.
- [ ] Verify every visible mutation uses audited transactional APIs.

### P2 — Hardening
- [ ] Remove/deprecate unused non-audited mutation APIs after call-site search.
- [ ] Remove or harden direct document-version update bypass.
- [ ] Clarify that local PIN is a device gate, not per-staff identity or role enforcement.

## Acceptance gates
1. All automated Flutter tests pass on the exact commit.
2. Existing schema-v4 database upgrade test preserves row counts and key values.
3. Backup restore reproduces database rows and attachment bytes exactly.
4. Every injected restore failure leaves the pre-restore database, key and attachment files usable.
5. Real-device test evidence is recorded before real legacy records are imported.

## Current verified baseline
- Existing test file: `test/security_validation_test.dart`.
- Existing tests cover PIN format, managed-path validation, too-short backup password, malformed/unsupported backup envelope, missing database entry and wrong backup password.
- The current backup service uses PBKDF2-HMAC-SHA256 (310,000 iterations) and AES-256-GCM, and validates the encrypted DB before replacing live data.
- Full backup/restore round-trip, attachment byte comparison, SQLCipher migration rollback and restore failure-injection tests are not present in the inspected test file.
- Flutter SDK/device execution is not available through the GitHub source inspection used for this tracker; no test is claimed as passing.

## Change log
- 2026-11-10: Created this implementation tracker on `phase7-hardening`, branched from `phase8-data-migration` so Phase 8 work is retained without merging anything into `main`.
