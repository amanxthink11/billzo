# Billzo — Testing Strategy & Quality Verification

**Document Version:** 1.0.0  
**Test Coverage Target:** 100% Core Business Logic & Accounting Math  
**Framework:** `package:test`, `package:flutter_test`  

---

## 1. Automated Testing Pyramid

Financial applications cannot rely on superficial visual testing. Billzo enforces a strict test-first verification methodology:

```
          / \
         /   \       E2E / Integration Tests (15%)
        /     \      - Full Transaction Pipelines, Migrations, Restores
       /───────\
      /         \    Component / Widget Tests (25%)
     /           \   - Responsive Layouts, Keyboard Shortcuts, Modals
    /─────────────\
   /               \ Unit Tests (60%)
  /                 \- Deterministic Paise Math, GST Engine, Schedulers
 /───────────────────\
```

---

## 2. Mandatory Unit Test Matrix

### 2.1 GST & Tax Engine Tests (`test/unit/tax/`)
- [ ] **Intra-State 18% Exclusive:** Base rate ₹1,000.00 (`100000` paise). Verified CGST = ₹90.00 (`9000`), SGST = ₹90.00 (`9000`), Total = ₹1,180.00 (`118000`).
- [ ] **Inter-State 18% Exclusive:** Base rate ₹1,000.00 (`100000` paise). Verified IGST = ₹180.00 (`18000`), CGST = 0, SGST = 0, Total = ₹1,180.00 (`118000`).
- [ ] **Tax-Inclusive MRP Reverse Calculation:** Item with MRP ₹1,180.00 (`118000` paise) at 18% GST. Verified Taxable = ₹1,000.00 (`100000`), CGST = ₹90.00, SGST = ₹90.00.
- [ ] **Odd Paise Split Integrity:** Item with Taxable Amount ₹33.33 at 18% GST. Total tax = ₹6.00 (`600` paise). Split: CGST = 300 paise, SGST = 300 paise. Ensure 0-paisa leakage.
- [ ] **Fractional Quantity Calculation:** 1.250 Kg at ₹150.00/Kg. Verified exact gross = ₹187.50 (`18750` paise) without IEEE 754 precision drift.

### 2.2 Invoicing & Ledger Tests (`test/unit/sales/`)
- [ ] **Invoice Finalization Balance Verification:** Verify $\sum \text{Debit Entries} == \sum \text{Credit Entries}$ on every generated transaction.
- [ ] **Partial Payment Allocation:** Invoice for ₹5,000.00. Payment of ₹2,000.00 applied. Verified status updates to `PARTIAL`, remaining balance = ₹3,000.00 (`300000` paise).
- [ ] **Second Payment Settling Invoice:** Subsequent payment of ₹3,000.00 applied. Verified status updates to `PAID`, remaining balance = 0.
- [ ] **Cancellation Stock & Ledger Reversal:** Finalized invoice cancelled. Verified compensating ledger entries posted and stock deducted is restored via compensating movement.

### 2.3 Recurring Invoices & Offline Catch-up Tests (`test/unit/recurring/`)
- [ ] **Month-End Scheduling:** Profile created on Jan 31. Next 3 calculated dates: Feb 28 (or 29), Mar 31, Apr 30.
- [ ] **Missed Schedule Detection:** Profile next run date = `2026-10-01`. System date = `2026-10-06`. Verified engine detects 1 missed cycle.
- [ ] **Multi-Cycle Missed Detection:** Weekly profile next run date = `2026-09-15`. System date = `2026-10-06`. Verified engine detects exactly 3 missed runs (Sep 15, Sep 22, Sep 29).
- [ ] **Idempotency Guarantee:** Attempting to execute `generateInvoiceForCycle()` twice for the same `(recurring_invoice_id, scheduled_for_date)` returns failure / aborts with zero duplicate records created.

### 2.4 Backup & Restore Integrity Tests (`test/unit/backup/`)
- [ ] **SHA-256 Generation & Validation:** Generated backup zip must contain valid SHA-256 hash. Corrupted byte in DB file must trigger checksum failure.
- [ ] **Safe Pre-Restore Rollback:** Deliberately induce SQLite exception during restore. Verify original database file is untouched and fully operational.

---

## 3. Database Migration & Concurrency Tests

1. **Migration Upgrade Path:** Test running all migrations from scratch (`v0 -> v1 -> vN`) verifying zero schema errors and foreign keys enforced.
2. **Concurrent Read/Write Stress Test:** Run 100 concurrent read operations during an active write transaction under SQLite WAL mode to verify non-blocking reads.
