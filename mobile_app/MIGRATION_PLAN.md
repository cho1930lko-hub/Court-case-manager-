# Safe migration plan

## Phase 0 — Foundation
- Keep the current Streamlit application intact.
- Create the Flutter Android app in this isolated folder.
- Establish the local SQLite schema and build pipeline.

## Phase 1 — Core registers
- Session Court: list, search, filters, add, edit, archive.
- Dak Register: add/edit/status and local photo attachments.
- Remand Register: add/edit/search.
- Address Book: add/edit/search.
- Preserve the existing Hindi field labels and date conventions.

## Phase 2 — Daily workflow
- Dashboard, next-hearing reminders, witness tracking.
- Summons and printable action reports.
- Case sharing and local document generation.

## Phase 3 — V2 case workspace
- Private local document library and version history.
- Case timeline and action checklist.
- OCR with on-device processing where practical; manual verification required.
- Drafting workspace with explicit human review.
- Append-only audit events within the app (not represented as tamper-proof).

## Phase 4 — Data portability and security
- Encrypted database and encrypted backup.
- Backup/restore with integrity checks and pre-restore snapshot.
- Excel/CSV export and validated import.
- App lock and optional biometric unlock.
- Device-to-device transfer through user-controlled backup.

## Acceptance gates
- Existing Streamlit source remains unchanged until mobile parity is verified.
- Test add/edit/search/export/restore with synthetic records first.
- Compare imported counts and key fields before accepting migration.
- Never delete source Sheets or old app data as part of migration.
- Do not enter production police/court records until encryption and restore tests pass.
