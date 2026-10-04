# Billzo — Local Backup & Restore Specification

**Document Version:** 1.0.0  
**Feature Status:** Core Non-Negotiable Module  
**Integrity Standard:** Cryptographic SHA-256 Manifest + Pre-Restore Safe Snapshots  

---

## 1. Backup Strategy Overview

For Indian small businesses, data loss due to hardware crashes, OS re-installations, or malware is catastrophic. Billzo treats backup and restore not as an afterthought, but as an essential core utility.

```
┌─────────────────────────────────────────────────────────┐
│                 Billzo Backup Package                   │
│                    (*.billzobak)                        │
├─────────────────────────────────────────────────────────┤
│ ├── manifest.json        (Metadata, SHA-256, Versions)  │
│ ├── database.sqlite      (Consistent snapshot via WAL)  │
│ └── media/               (Business logos, signatures)   │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Backup File Specification (`.billzobak`)

The backup archive is a standard Zip container with a custom extension `.billzobak` to provide instant file-association on Windows.

### 2.1 Manifest Schema (`manifest.json`)
```json
{
  "format_version": 1,
  "app_version": "1.0.0",
  "app_build_number": 1,
  "schema_version": 1,
  "created_at": "2026-10-01T09:00:00Z",
  "business_id": "e6b4ca16-5c9f-44ea-ba72-a1f050b50679",
  "business_name": "ABC Enterprises",
  "database_sha256": "4a5e...9b1c",
  "total_invoices": 1420,
  "total_customers": 350,
  "total_products": 890,
  "backup_type": "MANUAL"
}
```

---

## 3. Safe Backup Creation Workflow

1. **Consistent Snapshotting:**
   - To avoid backing up a half-written transaction in SQLite WAL mode, the application issues:
   ```sql
   VACUUM INTO 'temporary_backup_path/database.sqlite';
   ```
   - This produces an exact, defragmented, consistent snapshot of the active database while concurrent reads continue uninterrupted.
2. **Media Collection:** Copies any business logos or signatures registered in `businesses.logo_path`.
3. **Manifest & Cryptographic Hash:** Computes the SHA-256 hash of `database.sqlite` and packages it into `manifest.json`.
4. **Compression & Packaging:** Compresses artifacts into the destination `.billzobak` file.
5. **Cataloging:** Inserts an entry into `backup_records` table with size, checksum, and file path.

---

## 4. Bulletproof Restore Protocol

Restoring a database must never risk corrupting or wiping out the user's existing data if the provided backup file is corrupted, invalid, or tampered with.

```
[ Merchant Selects Backup File ]
               │
               ▼
   [ 1. Validate Archive Integrity ]
     - Manifest exists & readable?
     - SHA-256 matches database.sqlite?
               │ YES
               ▼
   [ 2. Verify Schema Compatibility ]
     - Backup schema <= Current schema?
               │ YES
               ▼
   [ 3. Create Pre-Restore Safety Snapshot ] ◄── MUST NEVER BE SKIPPED
     - Copy current billzo.db to safety snapshot
               │
               ▼
   [ 4. Run PRAGMA integrity_check ]
     - Test candidate DB in temp memory
               │ PASSED
               ▼
   [ 5. Atomic Hot Swap ]
     - Close active SQLite connection pool
     - Replace active DB files with backup
     - Reopen connection & run pending migrations
               │
     ┌─────────┴─────────┐
  SUCCESS             FAILURE
     │                   │
     ▼                   ▼
[ Notify User & ]   [ Rollback to Safety Snapshot ]
[ Restart App   ]   [ Display Exact Error Details ]
```

### 4.1 Step 3: Mandatory Pre-Restore Safety Snapshot
Before overwriting the active database, Billzo automatically copies:
`%APPDATA%\Billzo\data\billzo.db` $\to$ `%APPDATA%\Billzo\backups\pre_restore_safety_backup_<TIMESTAMP>.db`
If anything fails during the restore process, this safety snapshot is automatically restored. The user can never lose their existing data through a failed restore.
