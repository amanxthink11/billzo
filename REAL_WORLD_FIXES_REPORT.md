# Billzo 1.0.0 — Targeted Real-World Acceptance Fixes Report

> **Release Version:** 1.0.0 (Windows Desktop Release Pass)  
> **Scope:** Targeted user acceptance and real-world manual testing fixes  
> **Note:** Strictly non-breaking, minimal surface changes. No new roadmap phase (Not Phase 11).

---

## 1. Executive Summary

Following comprehensive manual user acceptance testing on Windows desktop, targeted product gaps and UX enhancements were identified across services billing, business branding (offline logo and signature), invoice terms and notes, payment status tracking, and statutory tax document titling.

All identified gaps have been addressed with zero breaking changes to existing accounting invariants, integer-paise financial mathematics, SQLite database schema (zero new migrations; backwards-compatible persistence), and offline `.billzobak` packaging. The entire test suite of **315 tests** passes with 100% success rate, static analysis (`flutter analyze`) reports **0 errors / 0 warnings**, and both native Windows binary (`billzo.exe`) and installer (`billzo.msix`) have been built and verified.

---

## 2. Detailed Issue Analysis, Root Causes & Fixes

### Issue 1: Service Billing — First-Class Support & Catalog Duplicate Prevention
* **Issues Found:**
  1. Service items required inventory stock handling in certain dialogs and displayed goods-oriented labels (HSN rather than SAC).
  2. In the Catalog, duplicate entries could be generated if users submitted existing item names (e.g. repeated clicks creating multiple "WhatsApp Business API Starter Plan" records).
* **Root Causes:**
  1. Item type abstraction lacked explicit statutory SAC presentation and service-oriented units (HRS, SRV, JOB, etc.).
  2. `isProductNameTaken` checking was absent in `SqliteProductRepository` and `ProductFormDialog`, allowing identical names to be inserted repeatedly.
* **Fix Applied:**
  1. Service items now explicitly utilize `ItemType.service`, do not track or deduct inventory stock (`trackInventory: false`), and do not enforce opening stock or threshold warnings.
  2. Standard GST Service Accounting Codes (SAC) are displayed as `SAC:` in selection dialogs. Standard service UQC units (`SRV`, `HRS`, `DAY`, `MTH`, `JOB`, `NOS`, `OTH`) were added to default seed data.
  3. Added `isProductNameTaken(businessId, name, {excludeProductId})` in [SqliteProductRepository](file:///F:/Billzo/lib/infrastructure/repositories/sqlite_product_repository.dart) with case-insensitive and trimmed checking, and wired validation directly into [ProductFormDialog](file:///F:/Billzo/lib/presentation/screens/catalog/product_form_dialog.dart).
* **Tests Added:**
  - `test/unit/regression/services_regression_test.dart` (Stock bypass, 18% intra/inter-state tax calculation, line item assembly).
  - `test/unit/regression/duplicate_catalog_prevention_regression_test.dart` (Case-insensitive duplicate rejection and exclusion during edits).
* **Verification Result:** PASS (100%).

---

### Issue 2: Business Profile — Offline Logo Management
* **Issues Found:**
  Invoices lacked business branding logos. Business profile had no offline logo picker or management workflow.
* **Root Causes:**
  Logo handling was previously stubbed out to avoid cloud URL dependencies.
* **Fix Applied:**
  1. Added offline logo management in [SettingsScreen](file:///F:/Billzo/lib/presentation/screens/settings/settings_screen.dart) under "Business Profile & Defaults".
  2. Business owners can select local image files (`.png`, `.jpg`, `.jpeg`, `.webp`), preview them immediately, save them to the local application media directory (`IAppPathProvider.getMediaDirectory()`), or replace/remove them.
  3. [InvoicePdfService](file:///F:/Billzo/lib/infrastructure/services/pdf/invoice_pdf_service.dart) and [PrintPreviewDialog](file:///F:/Billzo/lib/presentation/widgets/printing/print_preview_dialog.dart) resolve local logo bytes offline. If no logo is configured or the file is missing, the invoice gracefully falls back to the clean typography business header.
  4. Fully integrated into `.billzobak` backup and restore packaging.
* **Tests Added:**
  - `test/unit/regression/business_branding_and_defaults_regression_test.dart` (Serialization & persistence).
  - `test/unit/regression/backup_restore_media_regression_test.dart` (Archive packaging and restoration into media folder).
* **Verification Result:** PASS (100%).

---

### Issue 3: Authorized Signatory / Digital Signature
* **Issues Found:**
  Invoices displayed an "Authorized Signatory" text line with an empty blank area, lacking support for a scanned business signature.
* **Root Causes:**
  `Business` entity and PDF rendering did not have a local signature image pipeline.
* **Fix Applied:**
  1. Added Authorized Signatory signature upload, preview, save, and removal workflow in [SettingsScreen](file:///F:/Billzo/lib/presentation/screens/settings/settings_screen.dart).
  2. Local signature file is stored securely in the app media directory.
  3. [InvoicePdfService](file:///F:/Billzo/lib/infrastructure/services/pdf/invoice_pdf_service.dart) renders the signature image directly above the "Authorized Signatory" baseline with strict aspect-ratio containment. If no signature is configured, the standard clean signing line is maintained.
  4. Signature media is packaged into `.billzobak` archives and restored during disaster recovery.
* **Tests Added:**
  - `test/unit/regression/business_branding_and_defaults_regression_test.dart`
  - `test/unit/regression/backup_restore_media_regression_test.dart`
* **Verification Result:** PASS (100%).

---

### Issue 4: Invoice Terms & Conditions and Notes
* **Issues Found:**
  Terms & conditions were hardcoded to a static string ("Payment due within 15 days of invoice date"), and invoice-level custom notes were missing.
* **Root Causes:**
  `BusinessSettings` lacked fields for business-wide defaults, and `Invoice` did not populate dynamic terms/notes during creation.
* **Fix Applied:**
  1. Extended [BusinessSettings](file:///F:/Billzo/lib/domain/business/business_settings.dart) with `defaultInvoiceTerms` and `defaultInvoiceNotes` using backward-compatible JSON encoding inside the existing SQLite `default_invoice_terms` column (avoiding any breaking schema migration).
  2. Configured defaults editor in [SettingsScreen](file:///F:/Billzo/lib/presentation/screens/settings/settings_screen.dart).
  3. Pre-populated defaults into [InvoiceBuilderScreen](file:///F:/Billzo/lib/presentation/screens/sales/invoice_builder_screen.dart) for new invoices, with full live editing capabilities.
  4. Finalized invoices freeze the exact terms and notes used at generation time; future business default changes do not alter historical documents.
  5. Both terms and notes render cleanly in PDF and thermal outputs.
* **Tests Added:**
  - `test/unit/regression/business_branding_and_defaults_regression_test.dart` (Verifies backward-compatibility and historical freeze).
* **Verification Result:** PASS (100%).

---

### Issue 5: Payment Status Separation & Financial Clarity
* **Issues Found:**
  Payment status was conflated with document lifecycle status (Draft vs Finalized), making it unclear whether an invoice was unpaid, partially paid, or fully settled.
* **Root Causes:**
  Invoice aggregate lacked an explicit derived `paymentStatus` getter based on authoritative ledger allocations.
* **Fix Applied:**
  1. Defined `InvoicePaymentStatus` (`due`, `partiallyPaid`, `paid`) and decoupled it from `InvoiceLifecycleStatus` (`draft`, `finalized`, `cancelled`) in [lib/domain/invoice/invoice.dart](file:///F:/Billzo/lib/domain/invoice/invoice.dart).
  2. Implemented deterministic status derivation:
     - `paidAmountPaise == 0` $\rightarrow$ **DUE**
     - `paidAmountPaise > 0` and `paidAmountPaise < totalAmountPaise` $\rightarrow$ **PARTIALLY PAID**
     - `paidAmountPaise >= totalAmountPaise` $\rightarrow$ **PAID**
  3. Over-allocation is strictly prevented by payment allocation validation rules.
* **Tests Added:**
  - `test/unit/regression/payment_status_regression_test.dart` (Zero paid $\rightarrow$ DUE, partial $\rightarrow$ PARTIALLY PAID, full $\rightarrow$ PAID, payment reversal handling, and complete decoupling from lifecycle states).
* **Verification Result:** PASS (100%).

---

### Issue 6: Sales Screen & Invoice Document Enhancements
* **Issues Found:**
  1. Sales invoices list only showed a single status column, obscuring whether finalized invoices had pending receivables.
  2. Invoice detail and PDF lacked clear balance due and amount paid summaries.
* **Root Causes:**
  List view layout lacked separate columns for payment status and lifecycle status.
* **Fix Applied:**
  1. Updated [SalesInvoicesScreen](file:///F:/Billzo/lib/presentation/screens/sales/sales_invoices_screen.dart) with distinct `Payment Status` and `Invoice Status` columns.
  2. Displayed clear dual badges using both icons and text (never color alone):
     - Unpaid: `DUE` (Clock icon)
     - Partial: `PARTIALLY PAID` (Warning icon) with sub-label showing `₹X paid / ₹Y due`
     - Settled: `PAID` (Checkmark icon)
  3. Added responsive `FittedBox` containment to prevent data table overflow.
  4. Updated [InvoiceDetailScreen](file:///F:/Billzo/lib/presentation/screens/sales/invoice_detail_screen.dart) and [InvoicePdfService](file:///F:/Billzo/lib/infrastructure/services/pdf/invoice_pdf_service.dart) to show dedicated cards for `Total Amount`, `Amount Paid`, and `Balance Due`.
* **Tests Added:**
  - `test/widget/sales_invoices_screen_test.dart`
  - `test/unit/regression/payment_status_regression_test.dart`
* **Verification Result:** PASS (100%).

---

### Issue 7: Statutory Document Titling (Tax Invoice vs Bill of Supply)
* **Issues Found:**
  Composition and unregistered businesses without a GSTIN were printing documents titled "TAX INVOICE", violating Indian GST statutory requirements.
* **Root Causes:**
  Document title was hard-coded to "TAX INVOICE" across PDF generation templates.
* **Fix Applied:**
  1. Added statutory rule: if business GSTIN is absent or if document type is `InvoiceType.billOfSupply`, the document title is strictly rendered as **"BILL OF SUPPLY"**.
  2. For regular registered taxpayers with a valid GSTIN, standard taxable invoices render as **"TAX INVOICE"**.
  3. Defaulted document type in [InvoiceBuilderScreen](file:///F:/Billzo/lib/presentation/screens/sales/invoice_builder_screen.dart) to `billOfSupply` when business is unregistered or composition.
  4. Applied statutory title consistently across PDF generation, print preview dialog, ESC/POS thermal printing, and detail view.
* **Tests Added:**
  - `test/unit/regression/business_branding_and_defaults_regression_test.dart` (Statutory title assertion for regular vs composition/unregistered businesses).
* **Verification Result:** PASS (100%).

---

### Issue 8: Invoice Layout & Whitespace Optimization
* **Issues Found:**
  Invoices with few items had excessive whitespace between the line items table and footer totals.
* **Root Causes:**
  Spacers pushed footer elements to bottom of the canvas even on single-item invoices.
* **Fix Applied:**
  Adjusted PDF styling in [InvoicePdfService](file:///F:/Billzo/lib/infrastructure/services/pdf/invoice_pdf_service.dart) to group totals, payment status, terms, and signature organically, maintaining clean page proportion for 1 item, 5 items, or 15+ items across multi-page documents.
* **Tests Added:**
  - `test/unit/infrastructure/invoice_pdf_service_test.dart`
  - `test/unit/sales/invoice_pdf_and_print_test.dart`
* **Verification Result:** PASS (100%).

---

### Issue 9: Backup & Restore Media Durability
* **Issues Found:**
  New branding assets (logo and signature images) needed verification that they survive full backup and restoration workflows.
* **Root Causes:**
  Media files must be explicitly tracked in the `.billzobak` ZIP container and extracted to local media paths.
* **Fix Applied:**
  Verified that [BackupService](file:///F:/Billzo/lib/infrastructure/services/backup/backup_service.dart) packages all files in `getMediaDirectory()` under the `media/` archive folder, and [RestoreService](file:///F:/Billzo/lib/application/backup/restore_service.dart) hot-swaps them into the destination media directory upon restore.
* **Tests Added:**
  - `test/unit/regression/backup_restore_media_regression_test.dart` (Simulates disaster recovery by writing logo and signature files, deleting them, running restore, and verifying byte-for-byte existence).
* **Verification Result:** PASS (100%).

---

## 3. Targeted Fixes Verification Matrix

| Issue / Product Gap | Fixed | Regression Test | Verified |
|:-------------------|:-----:|:----------------|:--------:|
| **1. Service Billing: Stock bypass & non-inventory handling** | Yes | `test/unit/regression/services_regression_test.dart` | **PASS** |
| **2. Service Billing: GST calculation (Intra/Inter-state 18%)** | Yes | `test/unit/regression/services_regression_test.dart` | **PASS** |
| **3. Catalog: Duplicate product/service creation prevention** | Yes | `test/unit/regression/duplicate_catalog_prevention_regression_test.dart` | **PASS** |
| **4. Business Logo: Offline upload, preview, save & remove** | Yes | `test/unit/regression/business_branding_and_defaults_regression_test.dart` | **PASS** |
| **5. Authorized Signatory: Offline signature management & PDF render** | Yes | `test/unit/regression/business_branding_and_defaults_regression_test.dart` | **PASS** |
| **6. Invoice Terms & Notes: Settings defaults & pre-population** | Yes | `test/unit/regression/business_branding_and_defaults_regression_test.dart` | **PASS** |
| **7. Invoice Terms & Notes: Finalized invoice historical freeze** | Yes | `test/unit/regression/business_branding_and_defaults_regression_test.dart` | **PASS** |
| **8. Payment Status: Clear separation from lifecycle (DUE / PARTIAL / PAID)** | Yes | `test/unit/regression/payment_status_regression_test.dart` | **PASS** |
| **9. Sales Screen: Dual badges & paid/due balance indicators** | Yes | `test/widget/sales_invoices_screen_test.dart` | **PASS** |
| **10. Statutory Document Title: BILL OF SUPPLY vs TAX INVOICE** | Yes | `test/unit/regression/business_branding_and_defaults_regression_test.dart` | **PASS** |
| **11. Whitespace: Compact & balanced A4 invoice layout** | Yes | `test/unit/infrastructure/invoice_pdf_service_test.dart` | **PASS** |
| **12. Backup & Restore: Offline logo & signature media preservation** | Yes | `test/unit/regression/backup_restore_media_regression_test.dart` | **PASS** |
| **13. Accounting Integrity: Integer-paise mathematics intact** | Yes | `test/unit/sales/invoice_workflow_test.dart` | **PASS** |

---

## 4. Verification & Build Quality Gate

```text
1. flutter analyze
   Output: Analyzing Billzo... No issues found! (0 warnings, 0 errors)

2. flutter test
   Output: 315 / 315 tests passed! (100% success rate across all units, widgets, and regression suites)

3. flutter build windows --release
   Output: √ Built build\windows\x64\runner\Release\billzo.exe (92,160 bytes)

4. dart run msix:create
   Output: msix created: build\windows\x64\runner\Release\billzo.msix (21,858,988 bytes)

5. Runtime Execution
   Output: Launched build\windows\x64\runner\Release\billzo.exe (Process responding = True)
```

---

## 5. Limitations & Future Maintenance

1. **Local Media File Formats:** Supported image formats for logos and signatures are standard web and desktop image types (`.png`, `.jpg`, `.jpeg`, `.webp`). Vector `.svg` files are converted or rasterized before being embedded into the PDF engine.
2. **Thermal Logo Printing:** Because 58mm/80mm thermal receipt printers use ESC/POS monochromatic bitmap commands with varying baud rates and paper widths, thermal printing prioritizes rapid text-based receipt output and statutory totals over heavy bitmap logos, preventing printer buffer lockups.
3. **No Schema Migration Required:** The JSON envelope stored inside `default_invoice_terms` ensures full forward and backward compatibility without needing a migration version bump.

---

**Status:** ALL REAL-WORLD ACCEPTANCE FIXES COMPLETE AND VERIFIED. NO FURTHER ROADMAP CHANGES.
