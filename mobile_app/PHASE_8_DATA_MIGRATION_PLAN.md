# Phase 8 — Legacy Data Migration & Reconciliation

**Branch:** `phase8-data-migration`
**Baseline:** Phase 7 audit branch, commit `0c032f7ea953ec0dd462f98fc6cd9c674c950085`
**Status:** Source-schema and import-path audit. No live Google Sheet was accessed and no records were imported.

## User constraints carried forward

- The Android app is local-first and Android-only. Google account / continuous internet is not required for daily use.
- Existing Google Sheets / Streamlit records must be preserved.
- Import the old records once into the local database; keep the old registers unchanged until reconciliation is signed off.
- Support Excel import and export, with automatic Hindi/English column matching and manual correction.
- The four source registers are Session Court, Dak Register, Rimand Register, and Address Book.

## Legacy source sheets and columns found in `gsheet.py`

### Session Court — sheet `सेशन कोर्ट`

`ST NO`, `मु0अ0स0`, `धारा`, `बनाम`, `न्यायालय`, `तलब साक्षी`, `पिछली पेशी`, `अगली तारीख पेशी`, `Status`, `सम्मन की स्थिति`, `Type Of Moni`, `कृत कार्यवाही`, `कुल गवाह`, `Fir दिनांक`, `आरोप पत्र प्रेषित`, `प्रसंज्ञान दिनांक`, `चार्ज फ्रेम`, `थाने पर देने का दिनाँक`.

### Dak Register — sheet `Dak REGISTER`

`STN`, `बनाम`, `status`, `Type`, `नाम पता`, `संबंधित थाना`, `कोर्ट का नाम`, `थाने पर लाने का दिनांक`, `तारीख़ पेशी`, `रिमार्क`, `लिंक`.

### Rimand Register — sheet `RIMAND REGISTER`

`रिमांड Date`, `मु0अ0स0`, `धारा`, `कोर्ट`, `IO`, `First रिमांड डेट`, `नाम पता अभियुक्त`.

### Address Book — sheet `Address Book`

`नाम`, `पता`, `मोबाइल`, `विभाग`.

## Existing Android target schema

The current Android database has tables `cases`, `dak_register`, `remand_register`, and `address_book`. The current import screen supports XLSX only. It has automatic alias matching, manual column mapping, preview, duplicate/invalid row filtering, selected-row import, and export.

## Mapping gaps identified in current import aliases

These are source headers present in the old Streamlit schema that are not explicitly represented in the current alias list, and therefore need explicit mapping or a custom-field preservation decision:

| Source register | Legacy header | Intended target | Finding |
|---|---|---|---|
| Session Court | `बनाम` | `accused_name` | Add exact alias |
| Session Court | `अगली तारीख पेशी` | `next_hearing` | Add exact alias |
| Dak | `STN` | `st_no` | Add exact alias |
| Dak | `बनाम` | `accused_name` | Add exact alias |
| Dak | `कोर्ट का नाम` | `court_name` | Add exact alias |
| Dak | `थाने पर लाने का दिनांक` | `station_received_date` | Add exact alias |
| Dak | `तारीख़ पेशी` | `hearing_date` | Add exact alias including nukta variant |
| Dak | `रिमार्क` | `remarks` | Add exact alias |
| Dak | `लिंक` | Preserve original URL | No dedicated legacy-link target found; preserve in a custom field or a new source-link field, do not discard |
| Rimand | `रिमांड Date` | `remand_date` | Add exact mixed-script alias |
| Rimand | `कोर्ट` | `court_name` | Add exact alias |
| Rimand | `IO` | `investigating_officer` | Add exact alias |
| Rimand | `First रिमांड डेट` | `first_remand_date` | Add exact alias |
| Rimand | `नाम पता अभियुक्त` | `accused_details` | Add exact alias |
| Address Book | `पता` | `address` | Ensure exact alias is present |

**Important:** The current auto-match implementation normalizes headers and compares them with the alias list. Normalization does not make semantically different words equivalent; an explicit alias is needed for the gaps above.

## Data integrity rules for the migration

1. Never write back to Google Sheets or alter the old Streamlit source during migration.
2. Take an original XLSX export of each of the four sheets and retain it unchanged as the migration source.
3. Record source file name, sheet name, export timestamp, and source row count.
4. Keep source row number in the import report so every imported / skipped / rejected row can be traced to the original workbook.
5. Do not silently discard unknown columns. Require explicit user mapping to an existing field or a custom field; retain the original source header in the mapping report.
6. Preserve original ST NO, FIR number, dates, status, summons state, court names, and source link values as text where needed. Do not convert ST NO/FIR into numeric values or strip leading zeros.
7. Normalize dates only when the source value is unambiguous. Preserve the raw source date for ambiguous or invalid date strings and report for review.
8. Do not overwrite an existing Android record. Duplicate matches must be shown for manual review; do not auto-merge based only on a name.
9. For Session Court, the primary duplicate key is ST NO. For Dak, use STN + Type, but also report possible same-STN rows with differing Type. For Rimand, use FIR number + remand date; blank key fields must not be treated as proof of uniqueness. For Address Book, mobile number is a candidate key only; blank or shared numbers need review.
10. After import, compare source row totals with imported + duplicate/skipped + invalid/error counts for each sheet. Then compare key-field samples and totals before approving migration.
11. Keep the old Sheets/Streamlit register available read-only until the user confirms reconciliation. No destructive cleanup is part of this phase.

## Reconciliation report required

For each source sheet, produce:
- Source row count (excluding header), blank rows, imported rows, exact duplicates, possible duplicates, invalid rows, and rows needing manual mapping.
- Counts of blank ST NO / FIR / mobile fields where applicable.
- Date parse exceptions and status/summons values not in the known dropdown lists.
- A row-level CSV/XLSX exception report with original row number, original values, suggested target mapping, and reason.
- A post-import comparison of source and local database counts, plus a sample comparison using ST NO / FIR number / mobile.

## Execution boundary and next action

The actual Google Sheet contents and an exported XLSX workbook are not available to this repository inspection. Therefore no real record import, count comparison, or data-loss certification can honestly be reported yet.

Next implementation steps:
1. Complete Phase 7's synthetic migration/backup/restore safety tests before any real-record import.
2. Add the missing exact header aliases and a required unknown-column/custom-field decision to the Android import flow.
3. Extend import reporting to include source row numbers and per-row failure reasons.
4. Test using a synthetic workbook containing Hindi/English headers, leading-zero ST NO/FIR values, blank keys, repeated records, mixed date formats, and Dak links.
5. Only after those tests pass, use fresh read-only XLSX exports of all four legacy sheets for the real migration and reconciliation. Keep the source untouched.

## Implementation progress — 2026-11-10

### Completed on `phase8-data-migration`

- Added explicit Hindi/English aliases for the known legacy headers in the Android importer.
- Added Excel worksheet selection when a workbook contains multiple sheets; the user can select the intended sheet instead of the importer silently reading only the first one.
- Added original worksheet row numbers to the import preview. Blank rows are filtered from preview without renumbering the remaining source rows.
- Unknown non-empty headers now block import until the user maps them to an existing field / configured custom field, or explicitly chooses **जानबूझकर छोड़ें**. This prevents accidental silent loss of unknown columns.
- A legacy Dak `लिंक` column should be mapped to a configured custom field if its URL needs to be retained. It must not be mapped to `attachment_path`.

### Verification status

- GitHub source inspection confirms the changes are committed on this branch.
- No GitHub Actions workflow run was returned for the latest commit.
- Flutter analyzer, automated tests, APK build, and Android device testing have **not** been run in this environment. Do not treat source edits as runtime validation.
- No actual Google Sheet was accessed and no real records were imported.

### Remaining before real migration

1. Pass original worksheet row numbers into the import service and persist row-level rejection reasons in an import exception report.
2. Fix the mismatch between the duplicated dynamic-field schema creators before relying on custom-field import on upgraded databases.
3. Add synthetic XLSX fixtures for all four registers, including multiple worksheets, blank rows, duplicate keys, leading-zero identifiers, mixed date values, and Dak source links.
4. Verify duplicate rules and null-key handling in the database import service; a blank identity must never be treated as proof of uniqueness.
5. Run Flutter tests/analyzer/build and Android device recovery tests after Phase 7 safety gates.
6. Import fresh read-only exports only after the above checks, then reconcile source totals and key-field samples. Keep the source Sheets unchanged.

## Implementation progress — import exception and identity-key hardening

### Implemented on `phase8-data-migration`

- Database schema version raised from 4 to 5 with additive repair for the overlapping v4 metadata creators.
- Missing `field_definitions.is_system`, `allowed_roles`, and `is_dropdown` columns are added without dropping existing definitions.
- `import_history` is repaired to contain both legacy column-name sets (`file_name/imported_at` and `source_name/created_at`) so the existing history writer and reader can operate together.
- Added `import_row_errors` to preserve each skipped, duplicate, manual-review, or failed row with original Excel row number, outcome, reason, source filename/sheet, and original mapped row values.
- Existing `field_values` rows are copied with `INSERT OR IGNORE` into the app's active `custom_field_values` table; the old table is retained.
- Import now receives the original Excel row numbers from the preview and shows the row-level exception report. The report can also be exported to XLSX.
- Automatic import requires a complete identity key:
  - Session Court: ST NO
  - Dak: STN + Type; same STN with a different Type is flagged for manual review
  - Rimand: FIR number + remand date
  - Address Book: mobile number; same mobile with a different name is flagged for manual review
- Incomplete identity keys are not silently treated as unique and are sent to manual review rather than auto-imported.

### Validation performed

- Reviewed the committed source changes on GitHub.
- Ran a local SQLite schema simulation for the combined `import_history` column set and `import_row_errors` insert path; the simulation succeeded.
- This SQLite simulation is **not** a Flutter/SQLCipher device test.
- Flutter analyzer, Flutter unit tests, APK build, and Android device testing remain unrun because the Flutter/Dart SDK and Android device are not available in this execution environment.
- No live Google Sheet was read or changed; no real records were imported.

### Next gate

Create and run synthetic XLSX tests for all four registers, then run Flutter analyzer/tests/build and Android device verification before any real migration. Review all `needs_review` and `error` rows before approving an import.

