import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/app_store.dart';
import '../services/cloud_sync.dart';
import 'common.dart';
import 'inventory.dart';
import 'invoices.dart';
import 'branding.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.store});
  final AppStore store;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int days = 1;
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
    final bills = store.invoices
        .where(
          (i) =>
              i['cancelled'] != true &&
              DateTime.parse(i['createdAt']).isAfter(start),
        )
        .toList();
    final sales = bills.fold<double>(0, (sum, i) => sum + number(i['total']));
    final received = store.payments
        .where((p) => DateTime.parse(p['createdAt']).isAfter(start))
        .fold<double>(0, (sum, p) => sum + number(p['amount']));
    final due = store.invoices.fold<double>(
      0,
      (sum, i) => sum + store.dueFor(i['id']),
    );
    final products = store.products
        .where((p) => p['archived'] != true)
        .toList();
    final low = products
        .where((p) => store.stockFor(p['id']) <= number(p['lowStock']))
        .toList();
    final shortages = products
        .where((p) => store.stockFor(p['id']) < 0)
        .toList();
    final recent = [...store.invoices]
      ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isCompact ? 14 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tappable SRS AGENCIES Logo badge that opens Landing Page
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: InkWell(
              onTap: () => context.go('/landing'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: lineColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    srsLogoWidget(size: 30, radius: 7),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'SRS AGENCIES',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: -0.3,
                                  color: ink,
                                ),
                              ),
                              SizedBox(width: 5),
                              Icon(Icons.open_in_new_rounded,
                                  size: 11, color: muted),
                            ],
                          ),
                          Text(
                            'Tap logo for Shop Overview',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PageHeading(
            'A good day to do business.',
            'Here’s what’s happening at your shop.',
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/pos'),
                  icon: const Icon(Icons.point_of_sale_outlined, size: 17),
                  label: const Text('New bill'),
                ),
                OutlinedButton.icon(
                  onPressed: () => editProduct(context, store),
                  icon: const Icon(Icons.add_box_outlined, size: 17),
                  label: const Text('Add product'),
                ),
                OutlinedButton.icon(
                  onPressed: () => receiveStockDialog(context, store),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 17),
                  label: const Text('Add stock'),
                ),
                OutlinedButton.icon(
                  onPressed: () => recordPaymentDialog(context, store),
                  icon: const Icon(Icons.payments_outlined, size: 17),
                  label: const Text('Record payment'),
                ),
              ],
            ),
          ),
          _syncStatusBanner(context, store),
          if (shortages.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD5CE)),
              ),
              child: isCompact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFC74343),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Stock shortage in ${shortages.length} product${shortages.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: Color(0xFFC74343),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Units sold during offline operation exceeded recorded physical stock.',
                          style: TextStyle(fontSize: 11, color: ink),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => context.go('/inventory'),
                            child: const Text('Review stock →'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFC74343),
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stock shortage in ${shortages.length} product${shortages.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: Color(0xFFC74343),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Units sold during offline operation exceeded recorded physical stock. Review inventory to balance quantities.',
                                style: TextStyle(fontSize: 11, color: ink),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.go('/inventory'),
                          child: const Text('Review stock →'),
                        ),
                      ],
                    ),
            ),
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 15, color: muted),
              const SizedBox(width: 8),
              Text(
                dateLabel(now.toIso8601String()),
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const Spacer(),
              DropdownButton<int>(
                value: days,
                underline: const SizedBox(),
                style: const TextStyle(color: ink, fontSize: 12),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Today')),
                  DropdownMenuItem(value: 7, child: Text('Last 7 days')),
                  DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                ],
                onChanged: (v) => setState(() => days = v!),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final width = c.maxWidth > 850
                  ? (c.maxWidth - 48) / 4
                  : (c.maxWidth > 420 ? (c.maxWidth - 16) / 2 : c.maxWidth);
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _stat(
                    width,
                    'Total sales',
                    money(sales),
                    Icons.trending_up_rounded,
                    '${bills.length} invoices this period',
                    accent,
                  ),
                  _stat(
                    width,
                    'Payments received',
                    money(received),
                    Icons.account_balance_wallet_outlined,
                    'Cash, UPI & card',
                    green,
                  ),
                  _stat(
                    width,
                    'Customer dues',
                    money(due),
                    Icons.schedule_outlined,
                    'Across all unpaid invoices',
                    const Color(0xFFB08A35),
                  ),
                  _stat(
                    width,
                    'Products in catalog',
                    '${products.length}',
                    Icons.inventory_2_outlined,
                    '${low.length} need a stock check',
                    const Color(0xFF5C7196),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          if (products.isEmpty) ...[
            Panel(
              color: const Color(0xFFEDF2EA),
              child: LayoutBuilder(
                builder: (context, c) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Pill('LET’S GET YOU STARTED'),
                    const SizedBox(height: 16),
                    const Text(
                      'Your shop. A fresh start.',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add your products and shop details. Your first bill is just a few clicks away.',
                      style: TextStyle(color: muted, height: 1.6),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () => editProduct(context, store),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add your first product'),
                        ),
                        OutlinedButton(
                          onPressed: () => context.go('/settings'),
                          child: const Text('Set up shop details'),
                        ),
                        TextButton(
                          onPressed: () => perform(
                            context,
                            () => store.seedCatalog(),
                            success: 'Sample catalog added. Adjust prices and stock before using it.',
                          ),
                          child: const Text('Try a sample catalog'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          LayoutBuilder(
            builder: (context, c) {
              final recentPanel = Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Recent invoices',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.go('/invoices'),
                          child: const Text('View all →'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (recent.isEmpty)
                      const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'The first of many.',
                        message: 'Completed bills will appear here, with payment status and customer details.',
                      ),
                    for (final i in recent.take(5))
                      Material(
                        color: Colors.transparent,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: canvas,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(
                              Icons.receipt_outlined,
                              color: muted,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            '${(i['customer'] as Map)['name'] ?? 'Walk-in customer'}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${i['number']} · ${dateLabel(i['createdAt'])}',
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                          trailing: Text(
                            money(i['total']),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onTap: () => showInvoice(context, store, i),
                        ),
                      ),
                  ],
                ),
              );
              final stockPanel = Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Stock watch',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Pill('${low.length}', color: accent),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (low.isEmpty)
                      const EmptyState(
                        icon: Icons.check_circle_outline,
                        title: 'All clear here',
                        message: 'Products running low will appear here.',
                      ),
                    for (final p in low.take(5))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            Icon(
                              categoryIcon('${p['category']}'),
                              color: muted,
                              size: 21,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${p['name']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Pill(
                              '${quantity(store.stockFor(p['id']))} ${p['unit']}',
                              color: accent,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => context.go('/inventory'),
                      child: const Text('Manage inventory →'),
                    ),
                  ],
                ),
              );
              return c.maxWidth > 850
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: recentPanel),
                        const SizedBox(width: 24),
                        Expanded(flex: 2, child: stockPanel),
                      ],
                    )
                  : Column(
                      children: [
                        recentPanel,
                        const SizedBox(height: 20),
                        stockPanel,
                      ],
                    );
            },
          ),
          const SizedBox(height: 22),
          const Row(
            children: [
              Icon(Icons.lock_outline, size: 13, color: muted),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Saved locally. Connect your cloud account in Settings to sync between devices.',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(
    double width,
    String label,
    String value,
    IconData icon,
    String caption,
    Color color,
  ) => SizedBox(
    width: width,
    child: Panel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 19),
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                letterSpacing: -.6,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(caption, style: const TextStyle(color: muted, fontSize: 10)),
        ],
      ),
    ),
  );

  Widget _syncStatusBanner(BuildContext context, AppStore store) {
    final cloud = cloudFor(store);
    return AnimatedBuilder(
      animation: cloud,
      builder: (context, _) {
        final isOnline =
            cloud.configured && cloud.signedIn && cloud.error == null;
        final isSyncing = cloud.busy;
        final hasError = cloud.error != null;
        final pending = store.pendingCount;

        final Color statusColor = isSyncing
            ? accent
            : hasError
                ? const Color(0xFFC74343)
                : isOnline
                    ? green
                    : const Color(0xFF5C7196);

        final String statusTitle = isSyncing
            ? 'Syncing with cloud…'
            : hasError
                ? 'Offline mode · Saved locally'
                : isOnline
                    ? 'Cloud synchronized'
                    : 'SRS AGENCIES · Offline Ready';

        final String statusSubtitle = isSyncing
            ? 'Uploading transactions securely.'
            : hasError
                ? 'Working offline. All bills and stock are safely recorded on this device.'
                : isOnline
                    ? (cloud.lastSynced != null
                        ? 'Last synchronized ${DateFormat('hh:mm a, dd MMM').format(cloud.lastSynced!)} · Multi-device sync active'
                        : 'Connected and ready to synchronize.')
                    : 'Operating 100% offline. All bills and inventory are safely stored on this device.';

        final isCompact = MediaQuery.sizeOf(context).width < 650;
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: EdgeInsets.all(isCompact ? 12 : 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: lineColor),
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isSyncing
                                ? Icons.sync_rounded
                                : isOnline
                                    ? Icons.cloud_done_outlined
                                    : Icons.cloud_off_outlined,
                            color: statusColor,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            statusTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: statusColor,
                            ),
                          ),
                        ),
                        if (pending > 0) Pill('$pending queued', color: accent),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statusSubtitle,
                      style: const TextStyle(fontSize: 10, color: muted),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: isOnline
                          ? OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: isSyncing ? null : () => cloud.sync(),
                              icon: const Icon(Icons.refresh_rounded, size: 15),
                              label: const Text(
                                'Sync now',
                                style: TextStyle(fontSize: 11),
                              ),
                            )
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => context.go('/settings'),
                              child: const Text(
                                'Cloud settings',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isSyncing
                            ? Icons.sync_rounded
                            : isOnline
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                        color: statusColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                statusTitle,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: statusColor,
                                ),
                              ),
                              if (pending > 0) ...[
                                const SizedBox(width: 8),
                                Pill('$pending queued', color: accent),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            statusSubtitle,
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (isOnline)
                      OutlinedButton.icon(
                        onPressed: isSyncing ? null : () => cloud.sync(),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Sync now'),
                      )
                    else
                      OutlinedButton(
                        onPressed: () => context.go('/settings'),
                        child: const Text('Cloud settings'),
                      ),
                  ],
                ),
        );
      },
    );
  }
}
