# Billzo

**Billing. Business. Simple.**

Billzo is an offline-first billing and business management application built with Flutter and SQLite.

## Official Website

https://billzo.cloud

## Brand

Billzo is a product/brand from:

**Chat Grow**

https://chatgrow.in

## Features

- 100% offline-first core
- Business profile and settings
- Customers and suppliers
- Products and services
- Categories and units
- GST / Indian tax support
- Sales invoices
- BILL OF SUPPLY support
- TAX INVOICE support
- Draft and finalized invoices
- Payment tracking
- Partial/full payments
- Purchase management
- Purchase returns
- Supplier payments
- Expenses
- Accounting
- Double-entry ledger architecture
- Trial Balance
- Profit & Loss
- Balance Sheet
- GST management/reporting
- Recurring invoices
- Offline recurring invoice execution
- AR/AP aging
- Stock management
- Stock valuation
- PDF invoices
- A4 printing
- 80mm thermal printing
- 58mm thermal printing
- UPI QR
- Business logo
- Authorized signatory/signature
- Invoice terms and notes
- Local backup and restore
- .billzobak backup format
- SQLite local database
- Windows desktop support
- Android-ready architecture

## Architecture

Billzo is built on Flutter, Dart, and SQLite, following Clean Architecture and domain-driven design principles with strict layer boundaries:

- **Framework**: Flutter & Dart
- **Database Engine**: Local SQLite (`sqflite_common_ffi` / `sqlite3_flutter_libs`)
- **State Management**: Riverpod (`flutter_riverpod`)
- **Architectural Layers**:
  - **Domain**: Pure business entities, value objects, domain validators, statutory tax calculators, and abstract repository contracts.
  - **Application**: Application services, use case orchestrators, state notifiers, and database transaction managers.
  - **Infrastructure**: Concrete SQLite repositories, database connection factory, migration engine, native PDF rendering (`pdf`, `printing`), local file storage provider, and backup packaging.
  - **Presentation**: Reactive desktop UI implemented with Material Design 3, custom responsive data grids, dialog controllers, and live thermal/A4 print previews.
- **Financial Precision (Integer Paise)**:
  Money is stored and calculated strictly using integer paise rather than floating-point currency values (e.g., ₹100.50 is stored as `10050`). This prevents floating-point rounding errors and ensures accurate accounting balances across ledgers, taxes, and reports.
- **Identifiers**: Deterministic and UUID-based entity identifiers for resilient offline creation and isolation.
- **Data Authority**: Offline-first local source of truth with zero mandatory external or cloud dependencies.

## Offline-First Design

Billzo is designed from the ground up to operate completely offline. Core billing, ledger management, and reporting do not require an active internet connection:

- **Local SQLite Database**: All records—including transactions, parties, catalog items, and ledger journals—are persisted in an encrypted/isolated local database.
- **Local Invoice Generation**: Invoicing rules, statutory GST tax splits (CGST, SGST, IGST), and sequential numbering run entirely client-side.
- **Local PDF Generation**: Complete PDF document creation occurs inside the application runtime.
- **Local Printing**: Direct output to system printers, standard A4 desktop printers, and 80mm / 58mm thermal POS receipt printers.
- **Local Backup & Restore**: Archive generation and extraction run entirely on the user's workstation.
- **Offline Recurring Invoice Processing**: Scheduled and recurring invoice generation profiles are executed locally during runtime without remote server triggers.

## Backup & Restore

Billzo features an offline-first backup and disaster recovery subsystem:

- **Format**: Billzo uses the proprietary `.billzobak` backup format.
- **Contents**: Each `.billzobak` package is a self-contained archive containing the local application database, schema version metadata, cryptographic verification checksums, and associated local media assets (such as business logos and authorized signatory images).
- **Safety & Validation**: Restore workflows perform integrity verification, database compatibility validation, and safety checks before replacing the active database to prevent accidental data corruption or loss.
- **Data Privacy**: Backup archives remain entirely on the local filesystem under the user's direct control.

## Development

### Prerequisites

- Flutter SDK `^3.44.0` (Dart SDK `^3.12.0`)
- Windows 10/11 x64 with Visual Studio 2022 C++ Build Tools (Desktop development with C++)

### Common Commands

```powershell
# Install project dependencies
flutter pub get

# Run static analysis and linting
flutter analyze

# Run the complete test suite
flutter test

# Build Windows Release executable
flutter build windows --release

# Package Windows MSIX installer
dart run msix:create
```

### Verified Current State (v1.0.1)

- **Static Analysis**: `flutter analyze` — 0 issues found (clean)
- **Automated Tests**: `flutter test` — 315 / 315 tests passing (100%)
- **Windows Release Build**: Successful (`build\windows\x64\runner\Release\billzo.exe`)
- **MSIX Package**: Successful (`build\windows\x64\runner\Release\billzo.msix`)
- **Current Application Version**: `1.0.1` (MSIX Package Version: `1.0.1.0`)

## Windows Release

Pre-built Windows release packages are distributed through [GitHub Releases](https://github.com/amanxthink11/billzo/releases).

The current Windows MSIX release package is **Billzo 1.0.1**.

> **Note on Windows Installation & Code Signing:**  
> The current Windows MSIX package is test-signed for local evaluation. Windows requires installing the accompanying public test certificate (`billzo_test_cert.cer`) into the Local Machine `Trusted People` certificate store before installing the `.msix` package. Instructions and an automated installer script are provided on the GitHub Release page.

## Brand and Trademark Notice

Billzo and Chat Grow are brand names associated with Aman Singh / Chat Grow.

The MIT License applies to the source code of this repository.

It does NOT grant permission to use the Billzo or Chat Grow names, logos, trademarks, or other branding assets to imply endorsement or affiliation.

## Contributing

Contributions to Billzo are welcome! To contribute:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes adhering to project architectural standards
4. Run `flutter analyze` to ensure zero static analysis or lint warnings
5. Run `flutter test` to ensure all tests pass
6. Submit a pull request with a descriptive summary of your changes

## License

Billzo source code is released under the MIT License.

Copyright (c) 2026 Aman Singh

See the [LICENSE](LICENSE) file for the complete license text.
