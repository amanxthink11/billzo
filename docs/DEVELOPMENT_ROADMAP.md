# Billzo — Phased Development Roadmap & Risk Matrix

**Document Version:** 1.0.0  
**Target Delivery:** Production Windows Desktop Release (Phase 0–10), Followed by Android Release (Phase 11)  

---

## 1. Phased Development Roadmap & Acceptance Criteria

```
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 0: Architecture & Foundation (Current Phase)                     │
│ └── Clean Architecture, Flutter Project Init, Money Type, Brand Assets │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 1: SQLite Engine, Migrations, Business Setup & App Settings      │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 2: Parties Master (Customers & Suppliers) & Product Catalog      │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 3: Invoicing Engine, GST Tax Calculator & Sales Lifecycle        │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 4: Recurring Invoices & Offline Missed-Schedule Catch-Up Engine  │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 5: Payments, Allocations, Double-Entry Ledgers & Day Book        │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 6: Purchases, Vendor Bills, Debit Notes & Stock Movement Ledger  │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 7: Financial & Statutory Reports (GSTR-1, P&L, Aging Analysis)   │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 8: Native PDF Engine & POS Thermal Printing (A4, 80mm, 58mm)     │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 9: Local Backup & Restore with Cryptographic Integrity Checks    │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 10: Windows Production Hardening, Keyboard UX & Packaging        │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 11: Android Platform Adaptation & Cross-Platform Release         │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Phase Breakdown & Acceptance Criteria

### Phase 0: Architecture & Foundation (Current Stage)
- [x] Complete architectural specifications (`docs/`).
- [ ] Initialize standard Flutter desktop & mobile project in `F:\Billzo`.
- [ ] Configure `pubspec.yaml` with production-grade dependencies.
- [ ] Implement core deterministic `Money` value object (integer paise arithmetic) with unit tests.
- [ ] Implement Billzo design system theme tokens (`BillzoColors`, `BillzoTypography`, `BillzoTheme`).
- [ ] Set up desktop window management (minimum size 1024x720, title: "Billzo — Billing. Business. Simple.").

### Phase 1: Database + Business Setup + Settings
- **Deliverables:** SQLite client with WAL mode and foreign keys enabled; SQL migration runner; `businesses`, `business_settings`, `invoice_sequences`, and `app_settings` tables; onboarding screen.
- **Acceptance Criteria:**
  - Database initializes in `%APPDATA%\Billzo\data\billzo.db` on Windows.
  - Initial migration applies cleanly with verification in `schema_migrations`.
  - User can complete business profile setup (Name, GSTIN, State, Bank/UPI details).
  - Business settings persist and load deterministically across application restarts.

### Phase 2: Parties & Product Catalog
- **Deliverables:** `CustomerRepository`, `SupplierRepository`, `ProductRepository`, `ProductCategoryRepository`, `UnitRepository`, `TaxRateRepository`; management UI with instant search.
- **Acceptance Criteria:**
  - Parties can be added, edited, soft-deleted, and searched by name, phone, or company.
  - Products support barcode, SKU, HSN/SAC, category, unit, tax rate, and both inclusive/exclusive pricing.
  - Soft-deleted entities retain foreign key relational integrity with historical transactions.

### Phase 3: Invoice Engine, GST & Sales
- **Deliverables:** `GstCalculationEngine`, `InvoiceCreationUseCase`, `InvoiceRepository`; Desktop fast-billing screen.
- **Acceptance Criteria:**
  - Real-time tax calculation for intra-state (CGST+SGST) and inter-state (IGST).
  - Both tax-exclusive and tax-inclusive MRP pricing handled without rounding errors.
  - Finalizing an invoice executes an atomic transaction creating the invoice, items, stock movement, and ledger entries.
  - Sequential invoice numbering generated reliably with fiscal year prefixes.

### Phase 4: Recurring Invoices & Offline Processing
- **Deliverables:** `RecurringInvoiceEngine`, `MissedScheduleDetector`, execution history log; Recurring invoice management UI.
- **Acceptance Criteria:**
  - Supports Daily, Weekly, Bi-weekly, Monthly, Quarterly, Yearly, and Custom intervals.
  - Offline startup hook detects missed schedules if the PC was turned off during the due date.
  - Merchant can choose: Generate All Missed, Generate Latest, Review, or Skip.
  - Idempotency table (`recurring_invoice_executions`) guarantees zero duplicate invoices for the same cycle.

### Phase 5: Payments, Receivables & Accounting
- **Deliverables:** Payment entry screen, multi-invoice allocation modal, customer ledger statement, Day Book, Expense tracker.
- **Acceptance Criteria:**
  - Payments can be allocated to specific invoices or credited as advance on account.
  - Invoice statuses automatically transition (`FINALIZED` $\to$ `PARTIAL` $\to$ `PAID`).
  - Customer outstanding balance updates atomically in real time.
  - Day Book accurately reflects all inflows and outflows for any chosen date.

### Phase 6: Purchases & Inventory Control
- **Deliverables:** Purchase bill entry, vendor payment tracking, purchase returns (debit notes), stock ledger, low stock alerts.
- **Acceptance Criteria:**
  - Purchases increment stock levels via `StockMovement` records.
  - Low stock dashboard widget highlights items below reorder threshold.
  - Stock adjustments require explicit reason codes and record balance adjustments.

### Phase 7: Reports & Statutory Analytics
- **Deliverables:** GSTR-1 outward supplies report, GSTR-3B tax summary, Profit & Loss statement, Stock valuation report, Receivables/Payables aging.
- **Acceptance Criteria:**
  - GSTR-1 tables match official Indian tax portal formats (B2B, B2CL, B2CS, HSN Summary).
  - P&L accurately computes Gross Profit (Revenue - COGS) and Net Profit (Gross Profit - Expenses).
  - Reports export cleanly to CSV and PDF formats.

### Phase 8: PDF & POS Thermal Printing
- **Deliverables:** Native vector PDF engine, ESC/POS thermal receipt formatter (80mm & 58mm), print preview modal.
- **Acceptance Criteria:**
  - Generates beautiful A4 tax invoice PDF with business logo, QR code, and Rupee symbol.
  - Renders 80mm and 58mm thermal receipts formatted for counter receipt printers.
  - Printing executes via Windows spooler without blocking application UI.

### Phase 9: Backup, Restore & Data Safety
- **Deliverables:** `BackupService`, `RestoreService`, automatic scheduled backups, `.billzobak` export/import.
- **Acceptance Criteria:**
  - One-click backup creates a compressed zip archive containing DB snapshot and SHA-256 manifest.
  - Restore creates a mandatory pre-restore safety snapshot before touching active database.
  - Corrupted or tampered backup files are detected and rejected with zero data loss.

### Phase 10: Windows Production Hardening
- **Deliverables:** Full keyboard shortcut coverage (F2-F10), window persistence, installer package (MSIX / Inno Setup), release binary optimization.
- **Acceptance Criteria:**
  - Complete cashier workflow achievable 100% via keyboard without mouse.
  - Startup time < 1.5 seconds on standard laptop hardware.
  - Automated tests pass with 0 warnings in `dart analyze`.

### Phase 11: Android Platform Adaptation
- **Deliverables:** Mobile responsive layout shell, camera barcode scanner, Android file sharing, Bluetooth thermal printing.
- **Acceptance Criteria:**
  - Codebase builds and runs on Android 8.0+ devices using the identical domain/database layer.
  - Camera-based barcode scanner inputs items directly into invoice cart.
  - Invoices can be shared natively via WhatsApp / Email PDF intent.

---

## 3. Technical Risk Matrix & Mitigation Strategy

| Risk Description | Probability | Impact | Mitigation Strategy |
|---|---|---|---|
| **Floating-Point Rounding Drift** | High | Critical | Enforce integer minor units (paise) across all entities and calculations; verify via extensive unit tests. |
| **Offline PC Power-Off Missing Recurring Invoices** | High | High | Implement deterministic startup boot hook that queries `next_run_date <= TODAY` and provides interactive catch-up dialog with idempotency keys. |
| **Database Corruption on Restore** | Low | Catastrophic | Mandatory pre-restore safety snapshot of the active database before any restore operation is executed. |
| **Multi-Device Sync ID Collisions** | High | High | Use UUIDv4 primary keys and partitioned document sequence prefixes (`PC1-`, `MOB-`) from day one. |
| **Windows Desktop Window Resizing Glitches** | Medium | Medium | Implement responsive `LayoutBuilder` boundaries, minimum window size enforcement (1024x720) via `window_manager`. |
| **Slow Search on Large Product Catalogs (50k+ items)** | Medium | High | Create SQLite composite indexes on `(business_id, barcode)` and `(business_id, name)`; implement debounce and query limits. |
