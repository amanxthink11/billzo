# Billzo — Financial & Accounting Integrity Rules

**Document Version:** 1.0.0  
**Standard:** Indian Accounting Standards (Ind AS) & GST Statutory Rules  
**Monetary Representation:** Integer Minor Units (1 INR = 100 Paise)  

---

## 1. Monetary Mathematics & Floating-Point Prohibition

### 1.1 The Floating-Point Failure Mode
Under IEEE 754 floating-point arithmetic (`double`), decimal numbers like `0.1` and `0.2` cannot be represented with exact precision in binary:
```dart
0.1 + 0.2 == 0.30000000000000004 // TRUE
```
Across large ledgers and multi-item invoices, minor discrepancies accumulate, producing reconciliation failures, audit non-compliance, and mismatch between invoice totals and tax filings.

### 1.2 Integer Minor Units (Paise) Rule
**Rule 1.1:** All monetary fields in Billzo (rates, prices, discounts, sub-totals, taxes, totals, payments, receivables, payables) MUST be represented as 64-bit integers (`int`) denominated in Indian Paise:
$$\text{Amount (Paise)} = \text{Amount (INR)} \times 100$$
- ₹1,000.00 is stored as `100000`.
- ₹49.99 is stored as `4999`.
- Dart `int` natively supports up to $9,223,372,036,854,775,807$ paise (over ₹92 quadrillion), preventing integer overflow.

### 1.3 Quantity Scaling
To support fractional units of measurement (e.g. `1.250 Kg` or `4.5 Meters`), quantities are stored as integers scaled by $1,000$ (3 decimal precision):
$$\text{Stored Quantity} = \text{Decimal Quantity} \times 1000$$
- `1.250` units stored as `1250`.
- `5` units stored as `5000`.

---

## 2. Tax Calculation Mechanics (GST Engine)

### 2.1 Tax Slabs & Basis Points
Tax rates are represented in basis points ($1\% = 100 \text{ bps}$, $18\% = 1800 \text{ bps}$) to avoid floating-point percentages:

| Tax Slab | Total Basis Points | CGST Bps | SGST / UTGST Bps | IGST Bps |
|---|---|---|---|---|
| **Exempt / Nil** | 0 | 0 | 0 | 0 |
| **0.25%** | 25 | 12.5* | 12.5* | 25 |
| **3%** | 300 | 150 | 150 | 300 |
| **5%** | 500 | 250 | 250 | 500 |
| **12%** | 1200 | 600 | 600 | 1200 |
| **18%** | 1800 | 900 | 900 | 1800 |
| **28%** | 2800 | 1400 | 1400 | 2800 |

*\*For 0.25%, basis points can be scaled to tenths of bps (250 / 125 / 125) using standard divisor.*

### 2.2 Intra-State vs. Inter-State Supply Rule
Let $S_{merchant}$ be the Merchant's 2-digit State Code and $S_{supply}$ be the Place of Supply State Code:
- **Intra-State Supply ($S_{merchant} == S_{supply}$):**
  - $\text{CGST} = \text{TaxableAmount} \times \frac{\text{CGST\_bps}}{10000}$
  - $\text{SGST} = \text{TaxableAmount} \times \frac{\text{SGST\_bps}}{10000}$
  - $\text{IGST} = 0$
- **Inter-State Supply ($S_{merchant} \neq S_{supply}$):**
  - $\text{CGST} = 0$
  - $\text{SGST} = 0$
  - $\text{IGST} = \text{TaxableAmount} \times \frac{\text{IGST\_bps}}{10000}$

### 2.3 Tax-Exclusive Pricing Formula
When prices are entered exclusive of tax:
1. $\text{GrossLineTotal} = \frac{\text{RatePaise} \times \text{QuantityScaled}}{1000}$
2. $\text{TaxableAmount} = \text{GrossLineTotal} - \text{LineDiscountPaise}$
3. $\text{CGST} = \left\lfloor \frac{\text{TaxableAmount} \times \text{CGST\_bps} + 5000}{10000} \right\rfloor$ *(Half-Up rounding to nearest Paisa)*
4. $\text{SGST} = \left\lfloor \frac{\text{TaxableAmount} \times \text{SGST\_bps} + 5000}{10000} \right\rfloor$
5. $\text{LineTotal} = \text{TaxableAmount} + \text{CGST} + \text{SGST} + \text{IGST} + \text{Cess}$

### 2.4 Tax-Inclusive Pricing Formula
When prices are entered as MRP (inclusive of GST):
1. $\text{GrossInclusive} = \frac{\text{MrpPaise} \times \text{QuantityScaled}}{1000} - \text{LineDiscountPaise}$
2. $\text{TaxableAmount} = \left\lfloor \frac{\text{GrossInclusive} \times 10000 + \frac{10000 + \text{TotalTax\_bps}}{2}}{10000 + \text{TotalTax\_bps}} \right\rfloor$
3. $\text{TotalTaxAmount} = \text{GrossInclusive} - \text{TaxableAmount}$
4. Split `TotalTaxAmount` equally between CGST and SGST for intra-state supplies. Any odd 1-paisa remainder is assigned to CGST deterministically.

### 2.5 Invoice Round-Off
Under Indian commercial standards, the grand invoice total can be rounded to the nearest whole Rupee ($\pm 50 \text{ paise}$):
$$\text{Remainder} = \text{TotalAmountBeforeRoundOff} \pmod{100}$$
- If $\text{Remainder} \ge 50$, $\text{RoundOffPaise} = 100 - \text{Remainder}$ (Added)
- If $\text{Remainder} < 50$, $\text{RoundOffPaise} = -\text{Remainder}$ (Subtracted)
$$\text{FinalPayablePaise} = \text{TotalAmountBeforeRoundOff} + \text{RoundOffPaise}$$

---

## 3. Double-Entry General Ledger Framework

Every finalized financial transaction generates balanced debit and credit entries in `ledger_entries`.

### 3.1 Standard Chart of Accounts

| Account Code | Account Name | Type | Normal Balance |
|---|---|---|---|
| `1010` | Cash on Hand | Asset | Debit |
| `1020` | Bank Account | Asset | Debit |
| `1100` | Accounts Receivable (Debtors) | Asset | Debit |
| `1200` | Inventory Stock Value | Asset | Debit |
| `2100` | Accounts Payable (Creditors) | Liability | Credit |
| `2210` | Output CGST Payable | Liability | Credit |
| `2220` | Output SGST Payable | Liability | Credit |
| `2230` | Output IGST Payable | Liability | Credit |
| `2310` | Input CGST Credit | Asset | Debit |
| `2320` | Input SGST Credit | Asset | Debit |
| `2330` | Input IGST Credit | Asset | Debit |
| `3000` | Owner's Capital / Equity | Equity | Credit |
| `4000` | Sales Revenue | Income | Credit |
| `5000` | Cost of Goods Sold (COGS) | Expense | Debit |
| `5100` | Operating Expenses | Expense | Debit |
| `5200` | Round-Off Account | Expense/Income | Balanced |

### 3.2 Transaction Posting Rules

#### A. Finalizing a Tax Invoice (Credit Sale)
- **Debit:** Accounts Receivable (`1100`) [Total Invoice Amount]
- **Credit:** Sales Revenue (`4000`) [Taxable Amount]
- **Credit:** Output CGST (`2210`) [CGST Amount]
- **Credit:** Output SGST (`2220`) [SGST Amount]
- **Credit/Debit:** Round-Off Account (`5200`) [Round-off Adjustment]
- **Verification Invariant:** $\sum \text{Debits} == \sum \text{Credits}$

#### B. Receiving Customer Payment
- **Debit:** Cash on Hand (`1010`) or Bank Account (`1020`) [Amount Received]
- **Credit:** Accounts Receivable (`1100`) [Amount Received]

#### C. Purchasing Stock from Supplier (Credit Purchase)
- **Debit:** Inventory (`1200`) [Taxable Amount]
- **Debit:** Input CGST Credit (`2310`) [CGST Amount]
- **Debit:** Input SGST Credit (`2320`) [SGST Amount]
- **Credit:** Accounts Payable (`2100`) [Total Bill Amount]

---

## 4. Invoice Immutability & Lifecycle Rules

```
 ┌────────┐       Finalize       ┌───────────┐      Payment       ┌────────┐
 │ DRAFT  ├─────────────────────►│ FINALIZED ├───────────────────►│  PAID  │
 └───┬────┘                      └─────┬─────┘                    └────────┘
     │                                 │
     │ Delete                          │ Cancel (with Reason)
     ▼                                 ▼
[ Purged ]                       ┌───────────┐
                                 │ CANCELLED │ (Retains history & reverses entries)
                                 └───────────┘
```

1. **Draft Invoices:** Modifiable and deletable. No ledger postings, no stock reservations.
2. **Finalized Invoices:** Immutable.
   - Invoice number, dates, line items, and totals cannot be modified via SQL UPDATE.
   - Any modification requires generating a formal **Credit Note / Sales Return** or issuing a **Cancellation**.
3. **Cancellation Rule:**
   - Marks invoice status as `CANCELLED`.
   - Records `cancelled_at` and `cancellation_reason`.
   - Generates reversing balancing entries in `ledger_entries`.
   - Restores deducted inventory quantities via compensating `stock_movements` records with reference `SALE_RETURN` / `CANCELLATION`.
   - Preserves historical invoice record permanently for tax and audit compliance.
