# Billzo — Offline Recurring Invoicing Engine Specification

**Document Version:** 1.0.0  
**Module:** Recurring Invoices Engine  
**Execution Environment:** Client-Side Standalone (Windows Desktop / Android)  
**Core Guarantee:** Idempotent, deterministic execution with automated missed-schedule catch-up  

---

## 1. Feature Architecture & Lifecycle

Recurring invoicing in Billzo is treated as a foundational core feature rather than a secondary add-on. Because Billzo operates without a server, scheduling logic runs locally on application startup and via periodic background heartbeat timers when the app is active.

```
┌────────────────────────────────────────────────────────┐
│             Recurring Invoice Template                 │
│  (Customer, Items, Frequency, Next Run Date, Settings) │
└───────────────────────────┬────────────────────────────┘
                            │ Generates via Snapshot
                            ▼
┌────────────────────────────────────────────────────────┐
│               Generated Invoices (Immutable)           │
│   ├── Invoice #INV-2026-0101 (Cycle: 01 Oct 2026)      │
│   ├── Invoice #INV-2026-0201 (Cycle: 01 Nov 2026)      │
│   └── Invoice #INV-2026-0301 (Cycle: 01 Dec 2026)      │
└────────────────────────────────────────────────────────┘
```

### 1.1 Snapshot Isolation Principle
When an invoice is generated from a recurring profile:
1. All line items, rates, taxes, and customer addresses are deeply cloned and frozen into the newly generated `invoices` and `invoice_items` records.
2. The generated invoice references `recurring_invoice_id`.
3. Subsequent edits to the recurring profile template (e.g., changing rates or items) will **NEVER** retroactively alter previously generated invoices.

---

## 2. Schedule Calculation Mechanics

### 2.1 Supported Frequencies

| Frequency Enum | Next Run Calculation Rule |
|---|---|
| `DAILY` | $\text{NextRunDate} = \text{CurrentRunDate} + 1 \text{ day}$ |
| `WEEKLY` | $\text{NextRunDate} = \text{CurrentRunDate} + 7 \text{ days}$ |
| `BI_WEEKLY` | $\text{NextRunDate} = \text{CurrentRunDate} + 14 \text{ days}$ |
| `MONTHLY` | $\text{NextRunDate} = \text{AddMonths}(\text{CurrentRunDate}, 1)$ with month-end pinning |
| `QUARTERLY` | $\text{NextRunDate} = \text{AddMonths}(\text{CurrentRunDate}, 3)$ |
| `HALF_YEARLY` | $\text{NextRunDate} = \text{AddMonths}(\text{CurrentRunDate}, 6)$ |
| `YEARLY` | $\text{NextRunDate} = \text{AddYears}(\text{CurrentRunDate}, 1)$ |
| `CUSTOM` | $\text{NextRunDate} = \text{CurrentRunDate} + N \text{ days}$ |

### 2.2 Month-End Edge Case Handling
If a recurring monthly profile starts on January 31:
- February run: Evaluates to February 28 (or 29 in leap years).
- March run: Returns to March 31 (preserving original anchor day `31`).

---

## 3. Offline Startup & Missed Schedule Handler

### 3.1 The "Computer Was Off" Problem
In an offline desktop environment, merchants regularly turn off their PCs over weekends, holidays, or power outages.
- **Scenario:** Invoice due on **01 October**. Computer powered off from **01 October to 05 October**. Merchant launches Billzo on **06 October**.

### 3.2 Detection Workflow
1. **Boot Hook:** Upon application initialization, the `RecurringInvoiceEngine.detectDueSchedules()` query runs:
```sql
SELECT r.* FROM recurring_invoices r
WHERE r.status = 'ACTIVE'
  AND r.next_run_date <= date('now', 'localtime')
  AND (r.end_date IS NULL OR r.next_run_date <= r.end_date);
```
2. **Cycle Evaluation:** For each due profile, the engine determines how many periods were missed by comparing `next_run_date` against current system date.
   - Example: If a weekly profile has not run for 3 weeks, 3 distinct cycle dates are detected: Oct 1, Oct 8, Oct 15.

### 3.3 Merchant Reconciliation Dialog
If missed schedules are detected, Billzo presents the **Missed Recurring Invoices Resolution Modal**:

```
┌────────────────────────────────────────────────────────┐
│ 🔔 Billzo — Missed Recurring Schedules Detected        │
│                                                        │
│ 3 recurring invoices were due while your PC was off.   │
│                                                        │
│ [x] Retainer - Tech Corp (Due: 01 Oct 2026)            │
│ [x] Rent Bill - Studio (Due: 01 Oct 2026)              │
│ [ ] Maintenance - Beta Ltd (Due: 03 Oct 2026)          │
│                                                        │
│ Select Resolution:                                     │
│ (●) Generate all missed invoices (Recommended)         │
│ ( ) Generate only the latest invoice                   │
│ ( ) Review drafts individually                         │
│ ( ) Skip missed periods and advance to next due date   │
│                                                        │
│ [ Skip All ]                     [ Execute Actions ]   │
└────────────────────────────────────────────────────────┘
```

---

## 4. Idempotency & Duplicate Prevention

### 4.1 Idempotency Key Architecture
To guarantee that under no circumstance can a duplicate invoice be created for the same billing cycle (even in case of application crash or repeated clicks):
- Every execution records a row in `recurring_invoice_executions`:
```sql
CREATE TABLE recurring_invoice_executions (
    id TEXT PRIMARY KEY NOT NULL,
    recurring_invoice_id TEXT NOT NULL REFERENCES recurring_invoices(id),
    invoice_id TEXT REFERENCES invoices(id),
    scheduled_for_date TEXT NOT NULL,  -- e.g. '2026-10-01'
    executed_at TEXT NOT NULL,
    execution_status TEXT NOT NULL,
    notes TEXT,
    created_at TEXT NOT NULL,
    UNIQUE(recurring_invoice_id, scheduled_for_date)
);
```

### 4.2 Atomic Execution Step
Before generating an invoice for cycle date `T`:
1. Check if `(recurring_invoice_id, scheduled_for_date = T)` exists in `recurring_invoice_executions`.
2. If already exists, abort invoice creation for this cycle.
3. If not, inside an atomic SQLite transaction:
   - Generate invoice with `invoice_date = T`.
   - Insert execution row with `scheduled_for_date = T`.
   - Advance `recurring_invoices.next_run_date` to next scheduled cycle.
   - Commit transaction.
