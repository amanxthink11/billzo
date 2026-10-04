# Billzo — Software Architecture Document

**Document Version:** 1.0.0  
**Pattern:** Clean Layered Architecture / Domain-Driven Design (DDD)  
**Target Platforms:** Windows Desktop (Primary), Android (Secondary)  

---

## 1. Architectural Philosophy & Layer Boundaries

Billzo enforces strict unidirectional dependency flow from outside to inside. Higher-level modules never depend on lower-level implementation details; both depend on abstractions.

```
       [ Presentation ]
              │
              ▼
      [ Application ]
              │
              ▼
          [ Domain ]  ◄─── Pure Dart Business Logic (Core Entity & Rules)
              ▲
              │ implements
     [ Infrastructure ] (Repositories, SQLite, PDF Engine, Native Bridge)
```

### 1.1 Layer Responsibilities

#### A. Domain Layer (`lib/domain/`)
- Contains enterprise business rules, entities, value objects, domain exceptions, and repository interfaces.
- **Rules:**
  - Zero imports of Flutter UI (`package:flutter/*`).
  - Zero imports of SQLite (`package:sqflite/*` or `package:sqlite3/*`).
  - Zero imports of file I/O or network drivers.
  - Represents monetary amounts exclusively as `Money` (integer minor units / paise).
  - All entities are immutable.

#### B. Application / Services Layer (`lib/application/`)
- Contains use case orchestrators and business workflows that coordinate domain entities and repository contracts.
- **Examples:**
  - `InvoiceCreationService`: Validates stock, calculates taxes, allocates sequences, generates ledger entries, and commits atomic transaction.
  - `TaxCalculationEngine`: Calculates CGST, SGST, IGST, UTGST, inclusive/exclusive pricing without touching UI.
  - `RecurringInvoiceScheduler`: Evaluates schedules, determines missed dates, and orchestrates invoice generation.
  - `BackupService`: Orchestrates database exports, creates zip archives with checksum manifests, and safely verifies restores.

#### C. Infrastructure Layer (`lib/infrastructure/`)
- Implements repository interfaces defined in the domain layer.
- Handles direct interaction with SQLite, filesystem, printing hardware, and OS windowing.
- Contains:
  - `sqlite/`: Database connection management, schema migrations, table definitions, SQL query builders.
  - `repositories/`: Concrete implementations of domain repositories using SQLite transactions.
  - `printing/`: Native PDF generation and ESC/POS thermal formatting.
  - `platform/`: Platform path resolvers and window management.

#### D. Presentation Layer (`lib/presentation/`)
- Contains widgets, screens, visual components, state notifiers (Riverpod), and formatters.
- **Rules:**
  - Widgets contain strictly zero calculation logic.
  - UI components read state from application providers and trigger use cases via application services.
  - All screens implement responsive layouts accommodating both desktop viewports (1024px minimum) and tablet/mobile screens.
  - Adheres strictly to the **Billzo Brand Identity Kit**.

---

## 2. Standard Codebase Folder Structure

```
F:\Billzo\
├── assets/
│   ├── brand/               # Official logos, glyphs, receipt graphics from assist
│   ├── icons/               # Module SVG/PNG icons (Invoice, Inventory, GST, etc.)
│   └── fonts/               # Inter font family (Bold, SemiBold, Medium, Regular)
├── docs/                    # Architectural and engineering specifications
├── lib/
│   ├── core/                # Shared utilities, constants, themes, money type
│   │   ├── constants/       # App constants, tax rates, frequencies
│   │   ├── errors/          # Base failure and domain exception classes
│   │   ├── money/           # Deterministic Money & Currency value objects (Paise)
│   │   ├── theme/           # Billzo ColorScheme, Typography, CardStyles
│   │   └── utils/           # Date formatters, number to words (Indian currency)
│   ├── domain/              # Pure Domain models and repository interfaces
│   │   ├── accounting/      # LedgerAccount, LedgerEntry, DayBook
│   │   ├── auth/            # Local security, PIN/passcode lock, user profiles
│   │   ├── business/        # Business, BusinessSettings, InvoiceSequence
│   │   ├── inventory/       # Product, Category, Unit, StockMovement
│   │   ├── parties/         # Customer, Supplier, PartyBalance
│   │   ├── recurring/       # RecurringInvoice, RecurringFrequency, SchedulePeriod
│   │   ├── sales/           # Invoice, InvoiceItem, Estimate, Payment, TaxBreakup
│   │   └── tax/             # TaxRate, HsnSacCode, GstType, PlaceOfSupply
│   ├── application/         # Use cases and application services
│   │   ├── accounting/      # LedgerService, DayBookService
│   │   ├── backup/          # BackupService, RestoreService, ChecksumValidator
│   │   ├── inventory/       # StockTrackingService, LowStockService
│   │   ├── recurring/       # RecurringInvoiceEngine, MissedScheduleDetector
│   │   ├── reports/         # ReportGenerationService (Sales, Tax, P&L)
│   │   ├── sales/           # InvoiceCreationUseCase, PaymentAllocationUseCase
│   │   └── tax/             # GstCalculationEngine, InvoiceTaxEvaluator
│   ├── infrastructure/      # Database, hardware, external file systems
│   │   ├── backup/          # ZipArchiveManager, FileHasher
│   │   ├── platform/        # WindowsPathProvider, AndroidPathProvider
│   │   ├── printing/        # PdfInvoiceBuilder, ThermalReceiptBuilder
│   │   ├── repositories/    # SQLite implementations of domain repositories
│   │   └── sqlite/          # SQLite database connection, Migrator, Queries
│   ├── presentation/        # Flutter UI, Screens, Widgets, Providers
│   │   ├── common/          # Reusable UI components (BillzoButton, BillzoCard, etc.)
│   │   ├── navigation/      # Sidebar, Desktop App Bar, Breadcrumbs, TabNav
│   │   ├── providers/       # Riverpod state providers
│   │   └── screens/         # Module screens (Dashboard, Invoices, Recurring, etc.)
│   └── main.dart            # Application entrypoint
└── test/                    # Unit, integration, and golden tests
```

---

## 3. Data Flow Specification

### 3.1 Invoice Creation Flow
1. **User Interaction:** Cashier enters customer name, selects items via keyboard/barcode in `InvoiceCreateScreen`.
2. **Real-time Tax Preview:** `InvoiceCreationNotifier` calls `GstCalculationEngine.calculateLineItemTaxes()` whenever items or quantities change.
3. **Save Action:** Cashier presses `F10` or clicks `Finalize & Print`.
4. **Use Case Execution:** `InvoiceService.finalizeInvoice()` is invoked:
   - Validates business constraints (e.g. valid customer, active items, correct date).
   - Generates sequential invoice number using `SequenceService.getNextSequence(businessId, 'INV')`.
   - Executes atomic SQLite transaction:
     - Inserts record into `invoices` table.
     - Inserts line items into `invoice_items` table.
     - Inserts balancing debit/credit entries into `ledger_entries` (Accounts Receivable debited, Sales Revenue credited, GST Payable credited).
     - Inserts deduction records into `stock_movements` table.
     - Updates invoice sequence counter.
   - Commits transaction.
5. **Output Generation:** Passes finalized immutable invoice aggregate to `PdfInvoiceBuilder` or thermal print driver.
6. **State Refresh:** Riverpod invalidates relevant dashboard and inventory providers; UI displays confirmation toast and previews invoice.

---

## 4. Cross-Platform Abstraction Strategy (Windows & Android)

```
                       ┌──────────────────────┐
                       │  IPlatformService    │
                       └──────────▲───────────┘
                                  │
                 ┌────────────────┴────────────────┐
                 │                                 │
     ┌───────────────────────┐         ┌───────────────────────┐
     │ WindowsPlatformService│         │ AndroidPlatformService│
     │ - AppData directories │         │ - External docs paths │
     │ - Window sizing / F11 │         │ - Share intent / PDF  │
     │ - Direct Spooler Print│         │ - Bluetooth thermal   │
     └───────────────────────┘         └───────────────────────┘
```

1. **Dependency Injection:** Service implementations are injected at application startup based on `Platform.isWindows` or `Platform.isAndroid`.
2. **Responsive Shell:** Desktop presents collapsible navigation drawer, command search bar, and multi-column tables. Android automatically adapts to bottom navigation and list cards while utilizing the exact same application providers and domain logic.
