# Billzo — UI / UX & Design System Guidelines

**Document Version:** 1.0.0  
**Source of Truth:** `F:\Billzo\assist\Billzo Brand Identity Asset Kit.png`  
**Brand Personality:** Modern, Trustworthy, Professional, Clean, Fast, SMB-Focused  

---

## 1. Brand Identity & Color System

The Billzo visual identity is anchored directly on the official brand kit asset:

```
┌────────────────────────────────────────────────────────┐
│  Primary Blue    Secondary Blue   Success Green        │
│    #2563EB           #3B82F6         #10B981           │
│  Trust/Stability Modern/Friendly Growth/Positive       │
├────────────────────────────────────────────────────────┤
│  Accent Orange   Dark Slate       Light Background     │
│    #F59E0B           #0F172A         #F1F5F9           │
│  Action/Energy   Headings, Text   Canvas & App Shell   │
└────────────────────────────────────────────────────────┘
```

### 1.1 Color Tokens & Hex Codes

| Token Name | Hex Code | HSL / RGB | Usage |
|---|---|---|---|
| `billzoPrimaryBlue` | `#2563EB` | `rgb(37, 99, 235)` | Primary brand color, main CTA buttons, active sidebar state, links. |
| `billzoSecondaryBlue`| `#3B82F6` | `rgb(59, 130, 246)` | Secondary accents, hover highlights, interactive borders. |
| `billzoSuccessGreen` | `#10B981` | `rgb(16, 185, 129)` | "Paid" status badges, positive cash flow, inventory in-stock. |
| `billzoAccentOrange` | `#F59E0B` | `rgb(245, 158, 11)` | "Partial" status, pending actions, attention notifications. |
| `billzoDangerRed`    | `#EF4444` | `rgb(239, 68, 68)` | "Unpaid / Overdue" badges, stock alerts, destructive actions. |
| `billzoDarkSlate`    | `#0F172A` | `rgb(15, 23, 42)` | High-contrast headings, primary text, dark mode surfaces. |
| `billzoNeutralText`  | `#64748B` | `rgb(100, 116, 139)`| Secondary labels, captions, metadata, table headers. |
| `billzoBorder`       | `#E2E8F0` | `rgb(226, 232, 240)`| Card borders, divider lines, table grid lines. |
| `billzoCardSurface`  | `#FFFFFF` | `rgb(255, 255, 255)`| Content cards, data tables, modals, input backgrounds. |
| `billzoCanvasLight`  | `#F1F5F9` | `rgb(241, 245, 249)`| App background, drawer backdrop, page scaffolding. |

### 1.2 Module Accent Identity

| Module | Accent Hex | Visual Icon Theme |
|---|---|---|
| **Invoices / Sales** | `#2563EB` (Primary Blue) | Receipt with jagged bottom edge |
| **Inventory / Stock** | `#10B981` (Success Green) | 3D Box / Package |
| **GST / Tax** | `#8B5CF6` (Vibrant Purple) | Percentage (%) Badge |
| **Payments / Cash** | `#F59E0B` (Accent Amber) | Wallet / Cash Card |
| **Recurring Invoices**| `#0284C7` (Sky Blue) | Calendar with repeat arrows |
| **Reports & P&L** | `#F43F5E` (Crimson Rose) | Bar Chart Analytics |

---

## 2. Typography Specification

The font family for all Billzo desktop and mobile interfaces is **Inter**.

```
Aa  Inter — Modern, clean and highly readable across desktop and mobile.
```

### 2.1 Type Hierarchy

| Style | Size | Weight | Line Height | Application |
|---|---|---|---|---|
| **Display 1** | 28px | Bold (700) | 36px | Dashboard KPI totals, major dialog headers |
| **Headline 1**| 22px | SemiBold (600) | 28px | Page titles, invoice totals |
| **Headline 2**| 18px | SemiBold (600) | 24px | Section headers, card titles |
| **Body Large** | 15px | Medium (500) | 22px | Navigation items, prominent table cells |
| **Body Base** | 13px | Regular (400) | 18px | Standard inputs, table data, descriptions |
| **Caption**   | 11px | Medium (500) | 14px | Table column headers, status tags, badges |
| **Monetary**  | 14px | SemiBold (600) | 18px | Tabular numbers (right-aligned currency) |

*Note: All currency amounts use tabular numerals (`FontFeature.tabularFigures()`) to ensure perfect vertical alignment in financial columns.*

---

## 3. Desktop UI Layout & Wireframe Standards

### 3.1 Three-Zone Desktop Architecture
1. **Sidebar Navigation (Left):**
   - Width: 240px (expanded) / 64px (collapsed).
   - Brand Header: Billzo logo glyph + wordmark ("Billzo") + Tagline ("Billing. Business. Simple.").
   - Nav Items: Dashboard, Sales, Purchases, Inventory, Customers, Suppliers, Recurring, Reports, Settings.
   - Active Indicator: Rounded pill with `#2563EB` background and white text.
2. **Top Application Bar (Top):**
   - Height: 64px.
   - Global Quick Search (Ctrl+K): Search invoices, customers, and products instantly.
   - Business Selector: Displays active business trade name and GSTIN.
   - Primary CTA: `+ New Invoice` button (`#2563EB`) with shortcut badge `[F2]`.
   - Backup indicator & system notifications bell.
3. **Main Content Canvas (Center):**
   - Responsive multi-column grid (`LayoutBuilder`).
   - Summary stat cards at the top (Today's Sales, Today's Collection, Receivables, Payables).
   - High-density data tables with sticky headers, sortable columns, and row hover states.

### 3.2 Keyboard-First Desktop Ergonomics
Speed is critical for Indian counter billing. The UI supports full keyboard navigation without requiring mouse interactions:
- `F2`: Instant New Invoice modal/screen.
- `F3`: Focus Product Search / Barcode scanner input.
- `F4`: Select / Switch Customer.
- `F10`: Finalize & Print Invoice.
- `Escape`: Cancel / Close active drawer or modal.
- `Enter` on table rows: Open detail view or select row.
