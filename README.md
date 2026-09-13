# SRS AGENCIES • Retail & Hardware POS Billing Software

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Platform](https://img.shields.io/badge/Platforms-Android%20%7C%20Windows%20%7C%20Web%20%7C%20iOS-brightgreen?style=for-the-badge)
![Offline First](https://img.shields.io/badge/Offline--First-100%25%20Local%20Storage-orange?style=for-the-badge)
![License](https://img.shields.io/badge/License-Proprietary-red?style=for-the-badge)

A high-speed, modern, **offline-first Point of Sale (POS) and inventory management application** tailored specifically for hardware stores, building materials suppliers (Cement, Iron & Steel, Plumbing, Paints, Electricals), and retail shops.

Engineered to operate seamlessly without an active internet connection, while providing optional multi-device cloud synchronization via Supabase for shop owners managing billing across tablets, mobile phones, and Windows desktop counters.

---

## 🚀 Key Highlights

- **100% Offline-Ready**: Every bill, payment, customer ledger entry, and inventory movement is saved immediately to local storage on the device.
- **High-Speed Checkout**: Keyboard shortcuts (`F1` for custom/loose items, `F2` for instant checkout, `Esc` to clear), instant product search, and barcode scanner integration.
- **Loose Item & Fractional Billing**: Native support for loose items sold by weight (`kg`, `g`, `ton`), length (`m`, `ft`), or volume (`ltr`), accurate to 3 decimal places (e.g. `2.500 kg nails`, `12.500 m wire`).
- **Flexible Dual Discounts**: Apply line-item discounts directly on individual product rows, and apply overall bill discounts strictly at the gross payment level.
- **Customer Ledgers & Dues**: Complete customer balance tracking, credit sales, payment collections, and outstanding dues management.
- **Smart Category & Unit Normalization**: Dual-selector dropdowns with custom input options and case-insensitive matching (e.g., auto-merging `cement` and `Cement`).
- **Multi-Format Receipt & Invoice PDF Engine**:
  - **Thermal Roll (58mm & 80mm)** for fast receipt printers.
  - **Standard A4 & A5** format for full-page tax/commercial bills.
- **Dedicated SRS Branding**:
  - Custom launcher icons across all Android display densities (`mdpi` through `xxxhdpi`).
  - Native launch screen & animated in-app splash screen.
  - Interactive Company Overview / Landing page accessible via logo tap.

---

## 📱 Modules & Features

### 1. Dashboard
- **Financial Pulse**: Real-time summary of today's sales, payments collected, unpaid customer balances, invoice count, and low-stock alerts.
- **Quick Action Bar**: 1-click access to **New Bill**, **Add Product**, **Add Stock**, and **Record Payment**.
- **Adaptive Layout**: Responsive portrait and landscape orientation support for phones, tablets, and wide PC monitors.
- **Clean Connectivity Status**: Reassuring offline-ready banner with cloud sync indicators.

### 2. Point of Sale (POS)
- **Product Catalog Search**: Real-time search by item name or product code, with category filter chips.
- **Custom / Loose Item Billing (`F1`)**: Instant entry modal for open items, custom charges, or unlisted goods with custom unit dropdowns.
- **Split Payments**: Collect payments across **Cash**, **UPI**, and **Customer Credit** within the same invoice.
- **Auto-Saved Drafts**: Persistent local draft recovery protects against accidental tab closure or power loss.

### 3. Inventory & Stock Management
- **Product Directory**: Comprehensive product table with real-time stock status pills, selling price, GST rates, and HSN codes.
- **Unit of Measurement Dropdown**: Pre-loaded with standard hardware units (`pcs`, `kg`, `bag`, `ton`, `m`, `ft`, `ltr`, `box`, `pkt`, `sq.ft`, etc.) with custom unit input and quick-touch chips.
- **Inward Stock Receiving Modal**: Fast purchase stock addition with quick quantity presets (`+10`, `+25`, `+50`, `+100`).
- **Immutable Movement Ledger**: Full audit trail of stock adjustments, customer sales, and invoice deletion reversals.

### 4. Invoices & Customer Ledger
- **Invoice Register**: Filter by status (*All*, *Paid*, *Partial*, *Unpaid*, *Cancelled*).
- **Invoice Deletion with Stock Restoration**: Safe invoice deletion that restores inventory stock back to catalog items and updates payment balances.
- **Customer Dues Tracking**: Directory of customers with positive outstanding balances, with 1-tap payment recording dialog.
- **Print & Share**: Built-in multi-platform PDF viewer, printer integration, and file sharing.

### 5. Settings & Cloud Sync
- **Shop Profile**: Business name, category, phone number, physical address, and GSTIN.
- **Printer Configuration**: Select thermal roll width (58mm / 80mm) or sheet sizes (A4 / A5).
- **Cloud Account**: Secure Supabase integration for multi-device data replication across devices.

---

## 🛠️ Tech Stack & Architecture

| Layer | Technology |
|---|---|
| **Framework** | [Flutter](https://flutter.dev/) (Channel stable, Material 3) |
| **Language** | [Dart](https://dart.dev/) |
| **State Management** | [Riverpod](https://riverpod.dev/) + `ChangeNotifier` |
| **Routing** | [GoRouter](https://pub.dev/packages/go_router) |
| **Local Storage** | Shared Preferences + Structured JSON & SQLite-compatible local storage |
| **PDF Generation** | [pdf](https://pub.dev/packages/pdf) & [printing](https://pub.dev/packages/printing) |
| **Cloud Sync** | [Supabase Flutter](https://pub.dev/packages/supabase_flutter) |
| **Date & Currency** | [intl](https://pub.dev/packages/intl) (Indian Rupee `₹` & `en_IN` formatting) |

---

## 🏁 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (version 3.24+ recommended)
- Android Studio / Android SDK (for Android builds)
- Visual Studio with C++ tools (for Windows builds)
- Google Chrome (for Web testing)

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/rajureddi/Billing-Software-pos-.git
   cd Billing-Software-pos-
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Verify the installation**:
   ```bash
   flutter analyze
   flutter test
   ```

---

## 💻 Running the Application

### Android (Phone / Tablet)
Connect an Android device with USB debugging enabled, or start an emulator:
```bash
flutter run -d android
```

To build a standalone production release APK:
```bash
flutter build apk --release
# Output APK: build/app/outputs/flutter-apk/app-release.apk
```

### Windows Desktop
```bash
flutter run -d windows
```

To build the standalone Windows executable:
```bash
flutter build windows --release
# Output folder: build/windows/x64/runner/Release/
```

### Web Browser
```bash
flutter run -d chrome
```

To build the static web deployment bundle:
```bash
flutter build web --release
# Output directory: build/web/
```

---

## 🧪 Testing & Verification

The project includes an automated test suite covering billing calculations, GST logic, discounts, storage reversals, and PDF generation:

```bash
flutter test
```

### Test Coverage Highlights:
- Fractional quantity pricing & loose item discount calculations.
- Tax-inclusive vs. tax-exclusive GST extraction.
- Single-item discount isolated from overall gross payment discount.
- Proportional paise allocation on mixed GST rates.
- Multi-line A4, A5, 58mm, and 80mm PDF receipt rendering.
- Offline stock movements and invoice deletion reversals.
- Case-insensitive category normalization.

---

## 📁 Directory Structure

```text
billing_software/
├── android/               # Android native configuration & icons
├── assets/images/         # Branding assets (SRS logo, app icons)
├── lib/
│   ├── data/              # Local storage, schema, AppStore state
│   ├── domain/            # Billing math, GST calculations, discount logic
│   ├── services/          # Cloud sync (Supabase), PDF invoice generator
│   ├── ui/                # User interface screens & widgets
│   │   ├── app.dart           # App shell, theme, navigation & top bar
│   │   ├── branding.dart      # Official logo widget & brand tokens
│   │   ├── common.dart        # Reusable UI widgets & UnitSelector
│   │   ├── dashboard.dart     # Sales metrics, quick actions & alerts
│   │   ├── inventory.dart     # Product catalog, stock receiving modal
│   │   ├── invoices.dart      # Invoices history, customer balances ledger
│   │   ├── landing_page.dart  # Company overview & module portal
│   │   ├── pos.dart           # Point of sale checkout & custom item modal
│   │   ├── settings.dart      # Shop profile, printer settings, cloud sync
│   │   └── splash_screen.dart # Animated branded launch screen
│   └── main.dart          # Application entry point
├── test/                  # Automated unit and integration test suite
├── web/                   # Web host configuration & favicons
├── windows/               # Windows desktop runner & resources
└── pubspec.yaml           # Dependencies and asset registrations
```

---

## 👥 Author & Maintenance

- **Shop**: SRS AGENCIES
- **Repository**: [https://github.com/rajureddi/Billing-Software-pos-.git](https://github.com/rajureddi/Billing-Software-pos-.git)
- **Primary Use**: Retail Billing & Wholesale Supply Management (Cement, Plumbing, Steel & Hardware)
