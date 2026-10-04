# Billzo — Technical Requirements Document (TRD)

**Document Version:** 1.0.0  
**Target Runtimes:** Windows Desktop (x86_64), Android (ARM64, x86_64)  
**SDK Versions:** Flutter 3.44.0+ / Dart 3.12.0+  
**Local Database:** SQLite 3 (WAL mode, Foreign Keys ON)  

---

## 1. System Architecture Overview

Billzo is designed as a standalone, multi-layered client-side application without runtime server dependencies. The architecture enforces clean dependency inversion:

```
┌────────────────────────────────────────────────────────┐
│             Presentation Layer (UI / Views)            │
│       Widgets, State Notifiers, Theme, Responsive      │
└───────────────────────────┬────────────────────────────┘
                            │ depends on
┌───────────────────────────▼────────────────────────────┐
│            Application Services / Use Cases            │
│   InvoiceService, TaxEngine, RecurringScheduler, etc.  │
└───────────────────────────┬────────────────────────────┘
                            │ depends on
┌───────────────────────────▼────────────────────────────┐
│                      Domain Layer                      │
│   Entities, Value Objects, Domain Rules, Aggregates   │
└───────────────────────────▲────────────────────────────┘
                            │ implemented by
┌───────────────────────────┴────────────────────────────┐
│                   Repositories Layer                   │
│   InvoiceRepository, CustomerRepository, LedgerRepo    │
└───────────────────────────┬────────────────────────────┘
                            │ depends on
┌───────────────────────────▼────────────────────────────┐
│               Data / Storage / Drivers                 │
│  SQLite Database (sqlite3 / FFI), Local File Storage   │
└────────────────────────────────────────────────────────┘
```

### 1.1 Architectural Invariants
1. **Domain Independence:** The `domain` package must contain zero dependencies on Flutter UI, platform channels, or storage drivers. Domain models are pure Dart.
2. **Platform Abstraction:** All platform-specific functionality (file locations, native printing, window management, hardware keyboard shortcuts) resides behind abstract service contracts in the `infrastructure/core` boundary.
3. **Immutability of Historical Ledger Records:** No update or deletion statements are permitted against finalized financial ledger entries. Corrections require compensating reversal entries.

---

## 2. Technology Stack & Framework Selection

| Layer | Component | Choice | Rationale |
|---|---|---|---|
| **Framework** | Multiplatform SDK | **Flutter 3.44.0 (Dart 3.12.0)** | High-performance compiled native binaries for Windows desktop and Android from a single codebase. |
| **State Management** | Application State | **Riverpod (StateNotifier / AsyncNotifier)** | Compile-time safe, decoupled from Flutter widget tree, easily testable in pure unit test environments without mock contexts. |
| **Local Database** | Embedded Relational Engine | **SQLite 3 via `sqlite3` & `sqflite_common_ffi`** | Industry-standard reliability, transactional ACID guarantees, zero installation overhead on Windows, identical behavior on Android. |
| **Data Types** | Monetary Values | **64-bit Integer (Dart `int`) Minor Units (Paise)** | 1 Rupee = 100 Paise. Eliminates floating-point rounding inaccuracies inherent in IEEE 754 `double`. Dart 64-bit integer supports up to ₹9.22 × 10¹⁶. |
| **ID Generation** | Record Primary Keys | **UUIDv4 (`uuid` package)** | Decentralized ID generation prevents sequence collision during future peer-to-peer or multi-device synchronization. |
| **Document Generation** | PDF & Print Service | **`pdf` and `printing` packages** | Native rendering of vector graphics, Unicode Indian Rupee symbol (₹), customizable A4, 80mm, and 58mm layouts. |
| **Serialization** | Serialization / JSON | **Manual / `freezed` / typed JSON** | Explicit schema control, migration resilience, and type safety. |
| **Window Management** | Desktop UI Constraints | **`window_manager`** | Windows desktop window sizing (minimum width 1024x700), custom title bars, maximize/restore states. |

---

## 3. Data Integrity & Storage Specification

### 3.1 SQLite Configuration Pragma
Every database connection opened by Billzo must execute the following PRAGMAs:
```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;
PRAGMA encoding = 'UTF-8';
```
- **`foreign_keys = ON`**: Enforces relational constraints (e.g., cannot delete a customer with existing finalized invoices).
- **`journal_mode = WAL`**: Enables Write-Ahead Logging for high concurrency, permitting readers while writes occur without lock contention.
- **`synchronous = NORMAL`**: Maximizes write throughput while maintaining durability against operating system crashes in WAL mode.

### 3.2 Migration Strategy
- Migrations are versioned sequentially (`001_initial_schema.sql`, `002_add_discount_matrix.sql`).
- The database maintains a `schema_migrations` table:
```sql
CREATE TABLE schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at TEXT NOT NULL,
    checksum TEXT NOT NULL
);
```
- On startup, the migration runner reads pending migration scripts, computes SHA-256 hashes, executes migrations inside atomic transactions, and records completion.

---

## 4. Platform Independence: Windows & Android

### 4.1 Storage Path Abstraction
Platform differences in local filesystem structures are unified through `IAppPathProvider`:
- **Windows Desktop:** `%APPDATA%\Billzo\data\billzo.db` (and backups in `%APPDATA%\Billzo\backups\`).
- **Android:** Direct application sandbox directory returned via `getApplicationDocumentsDirectory()`.

```dart
abstract class IAppPathProvider {
  Future<String> getDatabaseDirectory();
  Future<String> getBackupsDirectory();
  Future<String> getTemporaryExportDirectory();
}
```

### 4.2 Printing Abstraction
Desktop Windows supports direct driver printing via Windows Print Spooler as well as POS ESC/POS thermal printers via COM/USB ports. Android supports system print services and Bluetooth thermal printers.
- `IPrinterService`: Unifies generation of ESC/POS byte streams and PDF raster/vector buffers.

---

## 5. Security & Data Protection

1. **Local Encryption (Optional Tier Ready):** Support for SQLite encryption via SQLCipher without altering domain or repository interfaces.
2. **Crash Resilience:** Atomic database transactions for multi-row operations (e.g., invoice generation requires updating invoice items, stock movements, and ledger entries in a single atomic transaction).
3. **Backup Checksums:** All backup bundles contain a SHA-256 cryptographic manifest verifying payload authenticity before any restore action is permitted.
