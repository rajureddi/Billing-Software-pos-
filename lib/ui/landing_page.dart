import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/app_store.dart';
import 'branding.dart';
import 'common.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final shopName = store.settings['name'] ?? 'SRS AGENCIES';
    final shopCategory = store.settings['category'] ??
        'Hardware, Cement, Plumbing, Iron & Steel Materials';
    final shopAddress = store.settings['address'] ?? '';
    final shopPhone = store.settings['phone'] ?? '';
    final shopGstin = store.settings['gstin'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBF8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: lineColor),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: ink),
          tooltip: 'Back to Dashboard',
          onPressed: () => context.go('/dashboard'),
        ),
        title: Row(
          children: [
            srsLogoWidget(size: 32, radius: 8),
            const SizedBox(width: 10),
            Text(
              shopName,
              style: const TextStyle(
                color: ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: FilledButton.icon(
              onPressed: () => context.go('/dashboard'),
              icon: const Icon(Icons.grid_view_rounded, size: 16),
              label: const Text('Go to Dashboard'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: wide ? 48 : 20,
          vertical: 32,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Hero Banner
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(wide ? 40 : 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: lineColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Glowing Emblem
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFC42B2B)
                                  .withValues(alpha: 0.22),
                              blurRadius: 30,
                              spreadRadius: 4,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: srsLogoWidget(
                            size: 110, radius: 55, showBorder: false),
                      ),
                      const SizedBox(height: 22),

                      // Pill badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF0E8),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFFC42B2B)
                                  .withValues(alpha: 0.2)),
                        ),
                        child: const Text(
                          'OFFICIAL RETAIL & BILLING SUITE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Color(0xFFC42B2B),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Main Title
                      Text(
                        shopName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: wide ? 36 : 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Subtitle / Categories
                      Text(
                        shopCategory,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: muted,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Meta (Phone, Address, GSTIN)
                      if (shopAddress.isNotEmpty ||
                          shopPhone.isNotEmpty ||
                          shopGstin.isNotEmpty) ...[
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            if (shopPhone.isNotEmpty)
                              _metaChip(Icons.phone_outlined, shopPhone),
                            if (shopAddress.isNotEmpty)
                              _metaChip(
                                  Icons.location_on_outlined, shopAddress),
                            if (shopGstin.isNotEmpty)
                              _metaChip(
                                  Icons.verified_outlined, 'GSTIN: $shopGstin'),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],

                      const Text(
                        'Complete offline-ready point of sale, inventory tracking, and payment ledger built for fast daily operations.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: ink,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 26),

                      // Quick Launch Actions
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: () => context.go('/dashboard'),
                            icon: const Icon(Icons.grid_view_rounded, size: 18),
                            label: const Text('Open Dashboard'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => context.go('/pos'),
                            icon: const Icon(Icons.point_of_sale_outlined,
                                size: 18),
                            label: const Text('Start New Bill'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.go('/inventory'),
                            icon:
                                const Icon(Icons.inventory_2_outlined, size: 18),
                            label: const Text('Manage Stock'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Workspace Modules Grid
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 14),
                    child: Text(
                      'WORKSPACE MODULES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: muted.withValues(alpha: 0.9),
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMultiCol = constraints.maxWidth >= 700;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _featureCard(
                          width: isMultiCol
                              ? (constraints.maxWidth - 16) / 2
                              : constraints.maxWidth,
                          icon: Icons.point_of_sale_outlined,
                          iconColor: const Color(0xFFC42B2B),
                          title: 'Point of Sale (Billing)',
                          desc:
                              'Instant product search, category filters, item-wise & overall bill discounts, cash/UPI/credit splits, and thermal invoice printing.',
                          buttonLabel: 'Launch POS',
                          onTap: () => context.go('/pos'),
                        ),
                        _featureCard(
                          width: isMultiCol
                              ? (constraints.maxWidth - 16) / 2
                              : constraints.maxWidth,
                          icon: Icons.inventory_2_outlined,
                          iconColor: const Color(0xFF2C6ECB),
                          title: 'Inventory & Stock Management',
                          desc:
                              'Comprehensive product catalog with normalized category matching, barcode tracking, stock receiving, and low inventory alerts.',
                          buttonLabel: 'View Inventory',
                          onTap: () => context.go('/inventory'),
                        ),
                        _featureCard(
                          width: isMultiCol
                              ? (constraints.maxWidth - 16) / 2
                              : constraints.maxWidth,
                          icon: Icons.receipt_long_outlined,
                          iconColor: const Color(0xFF248248),
                          title: 'Invoices & Customer Ledgers',
                          desc:
                              'Historical invoice log, customer payment recording, immutable stock reversal on invoice deletion, and clean PDF exports.',
                          buttonLabel: 'Browse Invoices',
                          onTap: () => context.go('/invoices'),
                        ),
                        _featureCard(
                          width: isMultiCol
                              ? (constraints.maxWidth - 16) / 2
                              : constraints.maxWidth,
                          icon: Icons.tune_rounded,
                          iconColor: const Color(0xFF7B44B8),
                          title: 'Shop Configuration & Sync',
                          desc:
                              'Manage store contact information, tax preferences, printer formatting, and optional Supabase multi-device cloud synchronization.',
                          buttonLabel: 'Open Settings',
                          onTap: () => context.go('/settings'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 36),

                // Core System Pillars
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: lineColor),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _pillar(
                          icon: Icons.offline_pin_outlined,
                          title: '100% Offline-First',
                          desc:
                              'Operates continuously without internet. All data is saved on device.',
                        ),
                      ),
                      if (wide) ...[
                        Container(
                          width: 1,
                          height: 50,
                          color: lineColor,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        Expanded(
                          child: _pillar(
                            icon: Icons.flash_on_outlined,
                            title: 'High-Speed Billing',
                            desc:
                                'Designed for quick customer checkouts and flexible discount handling.',
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 50,
                          color: lineColor,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        Expanded(
                          child: _pillar(
                            icon: Icons.sync_rounded,
                            title: 'Multi-Device Cloud',
                            desc:
                                'Sync data across Windows, Android, and Web when online.',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Footer
                Text(
                  'SRS AGENCIES · v1.0 Retail Suite',
                  style: TextStyle(
                    fontSize: 12,
                    color: muted.withValues(alpha: 0.8),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => context.go('/dashboard'),
                  icon: const Icon(Icons.arrow_back, size: 14),
                  label: const Text('Return to Dashboard'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: muted),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, color: ink),
          ),
        ],
      ),
    );
  }

  static Widget _featureCard({
    required double width,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
    required String buttonLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: lineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 12,
              color: muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: const Size(0, 36),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(buttonLabel, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _pillar({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF0E8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFFC42B2B), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 11,
                  color: muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
