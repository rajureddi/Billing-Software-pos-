# Counterday — implementation plan

Build the approved Flutter billing app for one hardware/retail shop owner on Android, iOS, Windows and web. Use Material 3, Riverpod, Drift/SQLite local persistence and Supabase cloud synchronization. Five primary sections: dashboard, POS, inventory, invoices/customer dues, settings.

## Implementation sequence
1. Scaffold Flutter platforms and shared models, exact decimal billing calculations, local atomic storage and stock/payment ledger.
2. Build responsive desktop/mobile screens, product/category catalog, custom items, discounts, credit payments, historical invoices, settings and stock adjustments.
3. Add PDF paper layouts and platform print integration; Supabase authentication, migration and retry-safe sync; backup export/import.
4. Analyze and test calculations, persistence and core screens; build web and available native targets; document hardware/cloud/signing setup that needs external inputs.

## Design
Counterday is a professional retail workspace: warm off-white canvas, ink typography, restrained orange accent, generous but useful spacing, slim desktop navigation, searchable category tiles and a fixed cart. Responsive mobile navigation, accessible controls, no decorative gradients or fake business metrics. A clearly labeled sample catalog may be loaded optionally; business records start empty.

## Decisions
- One stock unit per product with fractional quantities; custom non-stock lines.
- Item discount then proportional invoice discount; fixed-point arithmetic and paise rounding.
- Offline sales preserve every bill and permit flagged negative stock.
- Device-specific sequential invoice series, immutable invoice snapshots and reversal events.
- INR, configurable GST/non-GST and inclusive/exclusive tax. No GST filing or supplier purchasing.
- A4/A5/58mm/80mm PDF and system printing; direct printer protocols deferred until hardware identified.
- Cloud first login/configuration needs an owner Supabase project; local mode works without credentials.
- iOS requires macOS/signing; physical printing requires identified hardware.

## Acceptance
Verify calculations, stock movement, partial payments, persistent restart, idempotent sync, multi-device identity, conflict visibility, backup deduplication, responsive pages and printable invoice pagination. Clearly document unverified external infrastructure rather than claiming deployment.
