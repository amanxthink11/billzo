# Billzo — Product Requirements Document (PRD)

**Document Version:** 1.0.0  
**Target Release:** 1.0 (Windows Desktop), 2.0 (Android)  
**Status:** Approved Architecture Draft  
**Author:** Lead Software Architect & Senior Flutter Engineer  
**Product Tagline:** *Billing. Business. Simple.*  

---

## 1. Executive Summary & Vision

### 1.1 Product Overview
**Billzo** is a fast, offline-first invoicing, inventory, accounting, and business-management application built primarily for Indian Small and Medium Businesses (SMBs), retailers, wholesalers, service providers, and distributors. 

While competing in the category of business billing applications like MyBillBook and Vyapar, Billzo establishes its own distinct, modern product identity, adhering to clean visual hierarchy, zero cloud dependency for core workflows, deterministic Indian GST compliance, automated offline recurring billing, and reliable local data preservation.

### 1.2 Target Audience & Personas
1. **Retailers & Store Owners (e.g., Kirana, Electronics, Apparel):** Need instant, friction-free counter billing, barcode scanning, thermal printing (58mm/80mm), stock deduction, and end-of-day cash reconciliation.
2. **Wholesalers & Distributors:** Require multi-item tax invoices, credit management, customer/supplier ledgers, payment tracking, bulk discounts, and transport/place-of-supply details.
3. **Service Providers & Freelancers:** Require professional A4 PDF invoices, recurring billing templates for retainer clients, quotation/estimate conversion, and receivables aging reports.

### 1.3 Key Differentiators
- **100% Offline-First:** Zero reliance on remote APIs or third-party servers for creating invoices, calculating GST, updating inventory, generating reports, or managing recurring schedules.
- **Uncompromised Data Safety:** Full local SQLite database with Write-Ahead Logging (WAL), foreign key constraints, atomic transactions, automatic local backups, and checksum verification.
- **Deterministic Financial & Tax Precision:** Minor units (integer paise) arithmetic across all calculations to eliminate floating-point rounding discrepancies.
- **First-Class Offline Recurring Billing:** Automated missed-schedule reconciliation when the system boots up after being powered off.
- **Unified Cross-Platform Core:** Windows desktop release first, architected with a decoupled domain and repository layer ready for Android without code rewrites.

---

## 2. Core Functional Requirements

### 2.1 Sales & Invoicing Module
- **Tax Invoice & Bill of Supply:** Generation of standard GST Tax Invoices (B2B, B2C) and Bills of Supply (for composition dealers or exempted goods).
- **Invoice Lifecycle:** Distinct lifecycle states:
  - `Draft`: Work in progress; does not impact stock or financial ledgers.
  - `Finalized`: Official invoice; generates immutable ledger entries and updates stock movements.
  - `Partially Paid`: Linked to partial payment receipts with tracked outstanding balance.
  - `Paid`: Fully settled invoice.
  - `Cancelled`: Retained for auditability; creates reversing accounting and stock entries; cannot be silently deleted.
- **Estimates & Quotations:** Generation of sales quotes with one-click conversion into finalized invoices.
- **Sales Returns (Credit Notes):** Linked or standalone credit notes that credit customer accounts and adjust inventory back into stock.
- **Delivery Challans & Proforma Invoices:** Pre-sales documentation workflows.

### 2.2 Recurring Invoices Engine
- **Template Configuration:** Custom templates with customer details, item lines, payment terms, and frequency intervals:
  - Frequencies: Daily, Weekly, Bi-weekly, Monthly, Quarterly, Half-Yearly, Yearly, Custom Day Interval.
- **Execution Modes:**
  - `Auto-Generate`: Creates and finalizes invoices automatically when due.
  - `Require Review`: Alerts the merchant on due dates and queues draft invoices for verification.
- **Offline Catch-Up & Missed Schedule Handler:**
  - When the application boots after being offline (e.g., computer turned off during due date), detects all missed runs.
  - Offers merchant choices: *Generate All Missed Invoices*, *Generate Only Latest*, *Review Individually*, or *Skip*.
  - Strictly idempotent: Guaranteed zero duplicate invoices for the same scheduled cycle.

### 2.3 Purchases & Vendor Management Module
- **Purchase Bills:** Recording of vendor purchases with HSN/SAC, purchase rates, input GST tax credits, and payment status.
- **Purchase Orders:** Purchase requisitions converted to vendor bills upon stock receipt.
- **Purchase Returns (Debit Notes):** Returning defective or excess inventory, updating accounts payable and vendor ledgers.
- **Vendor Balance Tracking:** Net payable balances with aging reports.

### 2.4 Inventory & Stock Control Module
- **Item Master:** SKU, item code/barcode, item name, category, unit of measurement (Pcs, Box, Kg, Ltr, etc.), HSN/SAC code, purchase price, selling price, wholesale price, and tax rate.
- **Stock Tracking:** Real-time stock counts updated strictly through immutable `StockMovement` records (Sales, Purchases, Returns, Adjustments, Scrap, Opening Balance).
- **Low Stock Alerts:** Configurable reorder points and low-stock dashboard notifications.
- **Stock Adjustments:** Explicit reconciliation records with audit notes for shrinkage, damage, or audit variance.

### 2.5 Accounting, Ledgers & Day Book
- **Double-Entry Local Ledger:** Every finalized sale, purchase, payment, and expense posts balanced debit and credit entries to dedicated ledger accounts.
- **Accounts Receivable & Payable:** Customer-wise and vendor-wise aging analysis (0-30 days, 31-60 days, 61-90 days, 90+ days).
- **Payment Collection & Allocation:** Multi-mode payments (Cash, UPI, Bank Transfer, Cheque) allocated across specific invoices or credited as advance on account.
- **Day Book:** Chronological ledger of all daily inflows and outflows.
- **Expense Tracker:** Business operational expenses categorized under chart of accounts.

### 2.6 Goods and Services Tax (GST) Engine
- **Tax Components:** Automated split calculation for intra-state (CGST + SGST or UTGST) and inter-state (IGST) transactions based on Business Place of Supply and Customer Place of Supply.
- **Tax Modes:** Line-item level support for both GST-exclusive (base rate + tax) and GST-inclusive (reverse-calculated base rate from MRP).
- **Rate Master:** Pre-configured Indian GST rates (0%, 0.25%, 3%, 5%, 12%, 18%, 28%) with custom cess support.
- **Statutory Reporting:** Generation of GSTR-1 (Sales), GSTR-2 (Purchases), and GSTR-3B summary-ready data tables.

### 2.7 Reporting & Analytics Engine
- **Financial Performance:** Profit & Loss statement, Gross Margin by product and category.
- **Sales Analytics:** Daily, weekly, monthly, and yearly sales trends, top-selling items, highest-margin customers.
- **Tax Reports:** HSN-wise sales summary, tax slab distribution, outward/inward tax credit summaries.
- **Stock Reports:** Stock valuation (FIFO and Weighted Average), stock movement ledger, slow-moving items.
- **Audit Logs:** Tamper-evident chronological logs of critical actions (invoice finalization, cancellation, price updates, manual backups).

### 2.8 Printing, PDF & Export Engine
- **Multi-Format Templates:**
  - A4 Standard Tax Invoice (Professional modern layout).
  - 80mm POS Thermal Receipt (Counter sales, quick checkout).
  - 58mm POS Thermal Receipt (Compact mobile/desktop thermal printers).
- **Customization Options:** Merchant logo integration, custom header/footer notes, bank account & UPI QR code display, terms & conditions, authorized signatory box.
- **File Exports:** Export to PDF, CSV, and Excel (XLSX).

### 2.9 Local Backup, Restore & Data Protection
- **Backup Types:** On-demand manual backups and automatic daily/weekly scheduled local backups.
- **Target Destinations:** Local drives, removable USB drives, or user-selected folders.
- **Security & Integrity:** SQLite database backup encapsulated in compressed archive with SHA-256 integrity checksum and schema version metadata.
- **Safe Restore:** Automatic pre-restore snapshot of the active database before restoring any archive to prevent accidental data corruption or loss.

---

## 3. Non-Functional Requirements (NFRs)

| Category | Requirement Specification |
|---|---|
| **Platform Compatibility** | Phase 1: Windows 10/11 (x64). Phase 2: Android 8.0+ (API Level 26+). |
| **Offline Independence** | 100% operational offline. Zero blocking network calls. No mandatory online sign-in. |
| **Performance Target** | Application launch < 1.5 seconds. Invoice generation & save < 200 ms. Search across 50,000 items < 50 ms. |
| **Monetary Precision** | 100% integer arithmetic (paise) internally; 2-decimal presentation. Zero IEEE 754 rounding errors. |
| **Data Integrity** | Foreign key constraints ON, WAL journaling mode, synchronous = NORMAL/FULL, ACID transactions. |
| **Memory Footprint** | Idle RAM < 120 MB on Windows; active billing < 250 MB. |
| **UI Aesthetics** | Modern, high-trust, responsive UI based on the official Billzo Brand Identity Kit (Inter font, Primary Blue `#2563EB`, Success Green `#10B981`, Accent Orange `#F59E0B`, Dark Slate `#0F172A`). |

---

## 4. Competitive Scope Boundaries

To deliver an exceptional and legally compliant business tool while avoiding intellectual property conflicts:
- Billzo will **NOT** mirror proprietary UI workflows, icons, or visual themes of Vyapar or MyBillBook.
- Billzo will introduce a distinct, high-efficiency keyboard-first desktop invoice interface tailored for high-speed counter operations.
- All domain rules, schemas, accounting workflows, and export engines are built from first principles.
