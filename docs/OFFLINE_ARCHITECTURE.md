# Billzo — Offline-First Architecture & Future Synchronization Protocol

**Document Version:** 1.0.0  
**Design Principle:** Local Authority (Zero Cloud Dependency)  
**Future Sync Model:** Peer-to-Peer LAN & Optional Asymmetric Cloud Relay  

---

## 1. Offline-First Non-Negotiable Tenets

1. **Zero Runtime Network Requirement:** Billzo must install, configure, invoice, calculate taxes, manage inventory, execute recurring schedules, and export reports with network cables disconnected or Wi-Fi turned off.
2. **Local Source of Truth:** All canonical data resides on the client's local disk in SQLite. There is no remote authoritative server that can deny writes, invalidate sessions, or block billing.
3. **No External Authentication Gate:** Application access is governed by local PIN/passcode or OS credentials without cloud authentication dependencies (Firebase Auth, Cognito, Supabase Auth).
4. **Instantaneous Local Response:** UI never displays network spinners or loading shimmers for standard database reads and writes. Query times are targeted at under 10 ms for local SQLite lookups.

---

## 2. Local Storage Architecture

```
                    ┌─────────────────────────┐
                    │  Billzo Application UI  │
                    └────────────┬────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │ SQLite Database Manager │
                    │ - WAL Mode              │
                    │ - Memory Cache (64MB)   │
                    │ - ACID Transactions     │
                    └────────────┬────────────┘
                                 │
     ┌───────────────────────────┼───────────────────────────┐
     │                           │                           │
┌────▼─────────────┐    ┌────────▼──────────┐    ┌───────────▼────────────┐
│ billzo.db        │    │ Local Assets      │    │ Encrypted Backups      │
│ Relational Data  │    │ Logos, Signatures │    │ *.billzo-bak (Zip/AES) │
└──────────────────┘    └───────────────────┘    └────────────────────────┘
```

### 2.1 File System Topology
- **Windows Desktop:**
  - Database: `%APPDATA%\Billzo\data\billzo.db`
  - Write-Ahead Log: `%APPDATA%\Billzo\data\billzo.db-wal`
  - Media & Attachments: `%APPDATA%\Billzo\media\`
  - Automatic Backups: `%APPDATA%\Billzo\backups\`
- **Android:**
  - Sandboxed Documents Directory: `/data/user/0/com.billzo.app/app_flutter/`

---

## 3. Future Synchronization Architecture

While Billzo v1.0 is strictly local-only, the database schema and domain models are engineered from day one to support seamless multi-device synchronization (e.g. Windows counter PC syncs with Android mobile scanner in the warehouse) without requiring schema rewrites.

### 3.1 Foundations for Multi-Device Sync

#### A. Decentralized Primary Keys (UUIDv4)
Autoincrement integers (`1, 2, 3...`) guarantee primary key collisions when two devices generate invoices offline. Billzo uses RFC 4122 UUIDv4 for all primary and foreign keys:
```dart
String id = const Uuid().v4(); // e.g. "e6b4ca16-5c9f-44ea-ba72-a1f050b50679"
```

#### B. Tombstones (Soft Deletion)
Physical `DELETE` statements destroy data lineage. When a record is deleted offline on Device A, Device B must know that the record was deleted rather than assuming Device A is missing it.
- `deleted_at TEXT`: Records UTC deletion timestamp. Synchronizer propagates deletions as tombstones.

#### C. Version Vectors & Change Tracking
Every table includes:
- `sync_version INTEGER`: Incremented monotonically on every local modification.
- `sync_status TEXT`: `'synced'`, `'pending_push'`, or `'conflict'`.

---

## 4. Local Area Network (LAN) Peer-to-Peer Sync (V2 Architecture)

For small Indian businesses, syncing between a counter PC and a mobile device over the local Wi-Fi router (without internet connectivity) is the ultimate operational setup.

```
┌────────────────────────┐                    ┌────────────────────────┐
│  Billzo Windows (PC)   │   Local Wi-Fi LAN  │  Billzo Android Phone  │
│  - SQLite Master Store │◄──────────────────►│  - SQLite Local Store  │
│  - mDNS Beacon (P2P)   │    Encrypted TLS   │  - Camera Barcode Scan │
└────────────────────────┘                    └────────────────────────┘
```

### 4.1 Sync Protocol Workflow
1. **Discovery:** Windows desktop advertises service via local mDNS (`_billzo-sync._tcp`).
2. **Pairing:** Android device scans QR code displayed on Windows desktop containing one-time pairing token and local IP address.
3. **Changeset Exchange:** Devices exchange change sets:
   - "Send all records where `updated_at > LastSyncTimestamp`".
4. **Deterministic Conflict Resolution (Last-Write-Wins with Financial Append Rule):**
   - **Master Data (Customers, Products):** Resolved via higher timestamp (`updated_at`).
   - **Financial Documents (Invoices, Payments):** Immutable append-only. Because invoices have unique UUIDs and invoice numbers are prefix-partitioned per device (e.g. `PC1-INV-` vs `MOB-INV-`), no invoice overwrites another.
