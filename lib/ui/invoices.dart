import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../data/app_store.dart';
import '../domain/billing.dart';
import '../services/invoice_pdf.dart';
import 'common.dart';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key, required this.store});
  final AppStore store;
  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  int viewIndex = 0;
  String search = '', filter = 'All invoices', customerSearch = '';
  DateTimeRange? range;
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final items =
        store.invoices.where((i) {
          final due = store.dueFor(i['id']);
          final date = DateTime.parse(i['createdAt']);
          return '${i['number']} ${(i['customer'] as Map)['name'] ?? ''}'
                  .toLowerCase()
                  .contains(search.toLowerCase()) &&
              (filter == 'All invoices' ||
                  filter == 'Unpaid' && due > 0 ||
                  filter == 'Paid' && due == 0 && i['cancelled'] != true ||
                  filter == 'Cancelled' && i['cancelled'] == true) &&
              (range == null ||
                  (!date.isBefore(range!.start) &&
                      date.isBefore(range!.end.add(const Duration(days: 1)))));
        }).toList()..sort(
          (a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'),
        );
    final dues = store.invoices.fold<double>(
      0,
      (sum, i) => sum + store.dueFor(i['id']),
    );
    final customersWithDues = store.customerBalances
        .where(
          (c) =>
              '${c['name']} ${c['phone']}'.toLowerCase().contains(
                customerSearch.toLowerCase(),
              ),
        )
        .toList();

    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isCompact ? 14 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            'Invoices & customer dues',
            'Every sale, customer balance, and payment record.',
            action: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Pill('Outstanding ${money(dues)}', color: accent),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => recordPaymentDialog(context, store),
                    icon: const Icon(Icons.payments_outlined, size: 17),
                    label: const Text('Record payment'),
                  ),
                ],
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('Invoices (${store.invoices.length})'),
                  selected: viewIndex == 0,
                  onSelected: (_) => setState(() => viewIndex = 0),
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: Text(
                    'Customer Balances (${store.customerBalances.where((c) => (c['due'] as double) > 0).length} with dues)',
                  ),
                  selected: viewIndex == 1,
                  onSelected: (_) => setState(() => viewIndex = 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (viewIndex == 0)
            Panel(
              child: Column(
                children: [
                  TextField(
                    onChanged: (v) => setState(() => search = v),
                    decoration: const InputDecoration(
                      hintText: 'Search invoice number or customer…',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in [
                          'All invoices',
                          'Unpaid',
                          'Paid',
                          'Cancelled',
                        ]) ...[
                          ChoiceChip(
                            label: Text(f),
                            selected: filter == f,
                            onSelected: (_) => setState(() => filter = f),
                          ),
                          const SizedBox(width: 8),
                        ],
                        OutlinedButton.icon(
                          onPressed: () async {
                            final r = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 1)),
                            );
                            if (r != null) setState(() => range = r);
                          },
                          icon: const Icon(Icons.date_range, size: 17),
                          label: Text(
                            range == null
                                ? 'Date range'
                                : '${dateLabel(range!.start)} – ${dateLabel(range!.end)}',
                          ),
                        ),
                        if (range != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () => setState(() => range = null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (items.isEmpty)
                    const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No invoices here yet',
                      message:
                          'Completed sales will appear here. Use Point of sale to create your first bill.',
                    ),
                  for (final i in items)
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: lineColor)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: canvas,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              i['cancelled'] == true
                                  ? Icons.cancel_outlined
                                  : Icons.receipt_long_outlined,
                              color: i['cancelled'] == true ? muted : green,
                            ),
                          ),
                          title: Text(
                            '${(i['customer'] as Map)['name'] ?? ''}'.isEmpty
                                ? 'Walk-in customer'
                                : '${(i['customer'] as Map)['name']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${i['number']}\n${dateLabel(i['createdAt'])}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: muted,
                                height: 1.6,
                              ),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    money(i['total']),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 5),
                                  Pill(
                                    i['cancelled'] == true
                                        ? 'Cancelled'
                                        : store.dueFor(i['id']) > 0
                                            ? 'Due ${money(store.dueFor(i['id']))}'
                                            : 'Paid',
                                    color: i['cancelled'] == true
                                        ? muted
                                        : store.dueFor(i['id']) > 0
                                            ? accent
                                            : green,
                                  ),
                                ],
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 19, color: muted),
                                tooltip: 'Delete invoice',
                                onPressed: () =>
                                    deleteInvoiceDialog(context, store, i),
                              ),
                            ],
                          ),
                          onTap: () => showInvoice(context, store, i),
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    onChanged: (v) => setState(() => customerSearch = v),
                    decoration: const InputDecoration(
                      hintText: 'Search customer by name or phone…',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (customersWithDues.isEmpty)
                    const EmptyState(
                      icon: Icons.people_outline,
                      title: 'No customer balances found',
                      message:
                          'Customers with credit or invoice history will appear here with full balances.',
                    ),
                  for (final c in customersWithDues)
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: lineColor)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: canvas,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.person_outline,
                              color: ink,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${c['name']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${c['phone'] ?? 'No phone'} · ${c['invoiceCount']} invoice(s)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                (c['due'] as double) > 0
                                    ? 'Due: ${money(c['due'])}'
                                    : 'Clear',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: (c['due'] as double) > 0
                                      ? accent
                                      : green,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Billed: ${money(c['totalInvoiced'])} · Paid: ${money(c['totalPaid'])}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          if ((c['due'] as double) > 0)
                            OutlinedButton(
                              onPressed: () =>
                                  recordPaymentDialog(context, store),
                              child: const Text('Record payment'),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showInvoice(
  BuildContext context,
  AppStore store,
  Json initial,
) async {
  String paper = store.settings['paper'] ?? 'A4';
  await showDialog(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, set) => AnimatedBuilder(
        animation: store,
        builder: (dialog, _) {
          final invoice = store.invoices.firstWhere(
            (i) => i['id'] == initial['id'],
            orElse: () => initial,
          );
          final due = store.dueFor(invoice['id']);
          return Dialog(
            insetPadding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 15, 10, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_long_outlined, color: accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${invoice['number']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialog),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${(invoice['shop'] as Map)['name']}',
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${(invoice['shop'] as Map)['address'] ?? ''}',
                            style: const TextStyle(color: muted),
                          ),
                          const SizedBox(height: 15),
                          Wrap(
                            spacing: 18,
                            runSpacing: 8,
                            children: [
                              Text(
                                'Customer: ${(invoice['customer'] as Map)['name'] ?? 'Walk-in'}',
                              ),
                              Text(dateLabel(invoice['createdAt'])),
                              Pill(
                                invoice['cancelled'] == true
                                    ? 'Cancelled'
                                    : due > 0
                                    ? 'Payment pending'
                                    : due < 0
                                    ? 'Excess paid'
                                    : 'Paid',
                                color: due > 0
                                    ? accent
                                    : due < 0
                                    ? const Color(0xFF8E5A2A)
                                    : green,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Text(
                                'Items (${(invoice['lines'] as List).length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: muted,
                                ),
                              ),
                              const Spacer(),
                              if (invoice['cancelled'] != true)
                                TextButton.icon(
                                  onPressed: () => editInvoiceItemsDialog(
                                    dialog,
                                    store,
                                    invoice,
                                  ),
                                  icon: const Icon(
                                    Icons.edit_note_rounded,
                                    size: 16,
                                    color: accent,
                                  ),
                                  label: const Text(
                                    'Edit / Add items',
                                    style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          for (final line in invoice['lines'] as List)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _invoiceLineThumbnail(line, store),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${line['name']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              '${quantity(line['quantity'])} ${line['unit']} × ${money(line['price'])}',
                                              style: const TextStyle(
                                                color: muted,
                                                fontSize: 11,
                                              ),
                                            ),
                                            if (number((line['discount'] as Map?)?['value']) > 0) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                '(${(line['discount'] as Map)['type'] == 'percent' ? '${(line['discount'] as Map)['value']}% off' : '-${money((line['discount'] as Map)['value'])}'})',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: green,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    money(line['total']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Divider(color: lineColor),
                          _invoiceTotal('Gross Subtotal', invoice['subtotal']),
                          if (number(invoice['itemDiscountTotal']) > 0)
                            _invoiceTotal(
                              'Item discounts',
                              -number(invoice['itemDiscountTotal']),
                            ),
                          if (number(invoice['overallDiscountTotal']) > 0)
                            _invoiceTotal(
                              'Bill discount',
                              -number(invoice['overallDiscountTotal']),
                            ),
                          if (number(invoice['itemDiscountTotal']) <= 0 &&
                              number(invoice['overallDiscountTotal']) <= 0 &&
                              number(invoice['discountTotal']) > 0)
                            _invoiceTotal(
                              'Discount',
                              -number(invoice['discountTotal']),
                            ),
                          _invoiceTotal('GST', invoice['taxTotal']),
                          _invoiceTotal(
                            'Total',
                            invoice['total'],
                            strong: true,
                          ),
                          _invoiceTotal(
                            'Paid / net received',
                            store.paidFor(invoice['id']),
                          ),
                          if (due < 0)
                            _invoiceTotal('Excess paid / Refund due', -due)
                          else
                            _invoiceTotal('Balance due', due),
                          const SizedBox(height: 18),
                          if (store.payments.any(
                            (p) => p['invoiceId'] == invoice['id'],
                          )) ...[
                            const Text(
                              'Payment history',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            for (final p in store.payments.where(
                              (p) => p['invoiceId'] == invoice['id'],
                            ))
                              Material(
                                color: Colors.transparent,
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('${p['method']}'),
                                  subtitle: Text(dateLabel(p['createdAt'])),
                                  trailing: Text(money(p['amount'])),
                                ),
                              ),
                          ],
                          if (invoice['cancelled'] == true)
                            Text(
                              'Cancellation: ${invoice['cancellationReason']}',
                              style: const TextStyle(color: accent),
                            ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<String>(
                          value: paper,
                          items: [
                            for (final p in ['A4', 'A5', '58mm', '80mm'])
                              DropdownMenuItem(value: p, child: Text(p)),
                          ],
                          onChanged: (v) => set(() => paper = v!),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => showDialog(
                            context: dialog,
                            builder: (preview) => Dialog(
                              child: SizedBox(
                                width: 850,
                                height: 700,
                                child: Column(
                                  children: [
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: IconButton(
                                        onPressed: () => Navigator.pop(preview),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                    Expanded(
                                      child: PdfPreview(
                                        build: (_) => InvoicePdf.generate(
                                          {
                                            ...invoice,
                                            'paid': store.paidFor(invoice['id']),
                                            'balance': store.dueFor(invoice['id']),
                                          },
                                          paper: paper,
                                        ),
                                        canChangePageFormat: false,
                                        canChangeOrientation: false,
                                        allowPrinting: false,
                                        allowSharing: false,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 17),
                          label: const Text('Preview'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => perform(
                            dialog,
                            () => InvoicePdf.shareInvoice(
                              {
                                ...invoice,
                                'paid': store.paidFor(invoice['id']),
                                'balance': store.dueFor(invoice['id']),
                              },
                              paper: paper,
                            ),
                          ),
                          icon: const Icon(Icons.download_outlined, size: 17),
                          label: const Text('Save PDF'),
                        ),
                        FilledButton.icon(
                          onPressed: () => perform(
                            dialog,
                            () => InvoicePdf.printInvoice(
                              {
                                ...invoice,
                                'paid': store.paidFor(invoice['id']),
                                'balance': store.dueFor(invoice['id']),
                              },
                              paper: paper,
                            ),
                          ),
                          icon: const Icon(Icons.print_outlined, size: 17),
                          label: const Text('Print invoice'),
                        ),
                        if (invoice['cancelled'] != true)
                          OutlinedButton.icon(
                            onPressed: () => editInvoiceItemsDialog(
                              dialog,
                              store,
                              invoice,
                            ),
                            icon: const Icon(
                              Icons.edit_note_rounded,
                              size: 17,
                              color: accent,
                            ),
                            label: const Text(
                              'Edit items',
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (due > 0)
                          OutlinedButton(
                            onPressed: () =>
                                recordInvoicePayment(dialog, store, invoice),
                            child: const Text('Record payment'),
                          ),
                        if (invoice['cancelled'] == true)
                          OutlinedButton.icon(
                            onPressed: () async {
                              final lines = (invoice['lines'] as List? ?? [])
                                  .map((l) => Map<String, dynamic>.from(l as Map))
                                  .toList();
                              await store.saveDraft({
                                'lines': lines,
                                'customer': invoice['customer'] ?? {},
                                'discount': invoice['discount'] ?? {
                                  'type': 'amount',
                                  'value': 0,
                                },
                                'gstEnabled': invoice['gstEnabled'] ?? false,
                                'taxInclusive':
                                    invoice['taxInclusive'] ?? false,
                                'interstate': invoice['interstate'] ?? false,
                              });
                              if (dialog.mounted) Navigator.pop(dialog);
                              if (context.mounted) {
                                context.go('/pos');
                                toast(
                                  context,
                                  'Loaded invoice lines into cart to create replacement bill.',
                                );
                              }
                            },
                            icon: const Icon(Icons.replay_rounded, size: 16),
                            label: const Text('Reissue bill'),
                          ),
                        if (invoice['cancelled'] != true)
                          TextButton(
                            onPressed: () => cancelSale(dialog, store, invoice),
                            child: const Text(
                              'Cancel invoice',
                              style: TextStyle(color: muted),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: () => deleteInvoiceDialog(
                            context,
                            store,
                            invoice,
                            parentDialog: dialog,
                          ),
                          icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade700),
                          label: Text(
                            'Delete invoice',
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

Widget _invoiceTotal(String label, dynamic amount, {bool strong = false}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: strong ? ink : muted,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            money(amount),
            style: TextStyle(
              fontSize: strong ? 23 : 13,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );

Future<void> recordInvoicePayment(
  BuildContext context,
  AppStore store,
  Json invoice,
) async {
  final amount = TextEditingController(
    text: store.dueFor(invoice['id']).toStringAsFixed(2),
  );
  String method = 'Cash';
  await showDialog(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Record payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          field('Amount received (₹)', amount, numeric: true),
          DropdownButtonFormField<String>(
            initialValue: method,
            items: [
              for (final m in ['Cash', 'UPI', 'Card'])
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) => method = v!,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.maybeOf(dialog);
            try {
              final val = double.parse(amount.text);
              await store.recordPayment(invoice['id'], val, method);
              if (dialog.mounted) Navigator.pop(dialog);
              if (messenger != null) {
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Payment recorded'),
                    backgroundColor: ink,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } catch (error) {
              if (dialog.mounted) {
                toast(
                  dialog,
                  error.toString().replaceFirst('Exception: ', ''),
                  error: true,
                );
              }
            }
          },
          child: const Text('Save payment'),
        ),
      ],
    ),
  );
  amount.dispose();
}

Future<void> recordPaymentDialog(
  BuildContext context,
  AppStore store, {
  String? preselectedInvoiceId,
}) async {
  final unpaid = store.invoices
      .where((i) => i['cancelled'] != true && store.dueFor(i['id']) > 0)
      .toList();
  if (unpaid.isEmpty) {
    await showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('No pending dues'),
        content: const Text(
          'All completed bills are fully paid. There are no unpaid customer invoices at this time.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }

  var selectedId = preselectedInvoiceId ?? unpaid.first['id'] as String;
  if (!unpaid.any((i) => i['id'] == selectedId)) {
    selectedId = unpaid.first['id'] as String;
  }
  final amount = TextEditingController(
    text: store.dueFor(selectedId).toStringAsFixed(2),
  );
  String method = 'Cash';

  await showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        title: const Text('Record customer payment'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select unpaid invoice',
                  ),
                  items: [
                    for (final inv in unpaid)
                      DropdownMenuItem(
                        value: inv['id'] as String,
                        child: Text(
                          '${inv['number']} · ${(inv['customer'] as Map?)?['name'] ?? 'Walk-in'} (Due: ${money(store.dueFor(inv['id']))})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    if (id == null) return;
                    set(() {
                      selectedId = id;
                      amount.text = store.dueFor(id).toStringAsFixed(2);
                    });
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: canvas,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Current balance due:',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                      Text(
                        money(store.dueFor(selectedId)),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                field('Amount received (₹)', amount, numeric: true),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                  ),
                  items: [
                    for (final m in ['Cash', 'UPI', 'Card'])
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) => method = v!,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.maybeOf(dialogContext);
              try {
                final val = double.parse(amount.text);
                await store.recordPayment(selectedId, val, method);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (messenger != null) {
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Payment recorded'),
                      backgroundColor: ink,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  toast(
                    dialogContext,
                    error.toString().replaceFirst('Exception: ', ''),
                    error: true,
                  );
                }
              }
            },
            child: const Text('Save payment'),
          ),
        ],
      ),
    ),
  );
  amount.dispose();
}

Future<void> cancelSale(
  BuildContext context,
  AppStore store,
  Json invoice,
) async {
  final reason = TextEditingController();
  await showDialog(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Cancel this invoice?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Stock will be returned and ${money(store.paidFor(invoice['id']))} will be recorded as refunded. Confirm only after returning any payment to the customer. The original invoice stays in your records.',
            style: const TextStyle(height: 1.6),
          ),
          const SizedBox(height: 18),
          field('Cancellation reason', reason),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Keep invoice'),
        ),
        FilledButton(
          onPressed: () => perform(dialog, () async {
            await store.cancelInvoice(invoice['id'], reason.text);
            if (dialog.mounted) Navigator.pop(dialog);
          }),
          child: const Text('Confirm cancellation'),
        ),
      ],
    ),
  );
}

Future<void> deleteInvoiceDialog(
  BuildContext context,
  AppStore store,
  Json invoice, {
  BuildContext? parentDialog,
}) async {
  await showDialog(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Delete this invoice?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Are you sure you want to permanently delete invoice ${invoice['number']}?',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            invoice['cancelled'] == true
                ? 'This cancelled invoice and all its associated records will be permanently removed.'
                : 'Inventory stock deducted for this bill will be automatically restored, and payments will be cleared. This action cannot be undone.',
            style: const TextStyle(height: 1.5, color: muted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => perform(dialog, () async {
            await store.deleteInvoice(invoice['id'] as String);
            if (dialog.mounted) Navigator.pop(dialog);
            if (parentDialog != null && parentDialog.mounted) {
              Navigator.pop(parentDialog);
            }
            if (context.mounted) {
              toast(context, 'Invoice ${invoice['number']} deleted.');
            }
          }),
          child: const Text('Delete permanently'),
        ),
      ],
    ),
  );
}

Widget _invoiceLineThumbnail(dynamic line, AppStore store) {
  final l = line as Map;
  final product = store.products.cast<Map<String, dynamic>?>().firstWhere(
    (p) => p?['id'] == l['productId'],
    orElse: () => null,
  );
  final rawImage = (l['image'] ?? product?['image']) as String?;
  if (rawImage != null && rawImage.trim().isNotEmpty) {
    try {
      final clean = rawImage.contains(',')
          ? rawImage.split(',').last.trim()
          : rawImage.trim();
      final bytes = base64Decode(clean);
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: lineColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Image.memory(
            bytes,
            width: 38,
            height: 38,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                _defaultInvoiceLineIcon(product?['category'] ?? ''),
          ),
        ),
      );
    } catch (_) {
      // Fallback
    }
  }
  return _defaultInvoiceLineIcon(product?['category'] ?? '');
}

Widget _defaultInvoiceLineIcon(String cat) {
  return Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: const Color(0xFFF0EDE5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Center(
      child: Icon(
        categoryIcon(cat),
        color: const Color(0xFF938363),
        size: 18,
      ),
    ),
  );
}

Future<void> editInvoiceItemsDialog(
  BuildContext context,
  AppStore store,
  Json invoice,
) async {
  final linesList = (invoice['lines'] as List? ?? [])
      .map((l) => Map<String, dynamic>.from(l as Map))
      .toList();

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (editDialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        Map<String, dynamic>? previewBill;
        String? calculationError;
        try {
          if (linesList.isNotEmpty) {
            previewBill = calculateBill(
              lines: linesList,
              discount: (invoice['discount'] as Map?)?.cast<String, dynamic>() ??
                  {'type': 'amount', 'value': 0},
              gstEnabled: invoice['gstEnabled'] == true,
              taxInclusive: invoice['taxInclusive'] == true,
              interstate: invoice['interstate'] == true,
            );
          }
        } catch (e) {
          calculationError = e
              .toString()
              .replaceFirst('Exception: ', '')
              .replaceFirst('ArgumentError: ', '');
        }

        final originalTotal = number(invoice['total']);
        final currentTotal =
            previewBill != null ? number(previewBill['total']) : 0.0;
        final totalDiff = currentTotal - originalTotal;

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit_note_rounded,
                        color: accent,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit items · ${invoice['number']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const Text(
                              'Add, remove, or adjust quantities of items on this invoice.',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(editDialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: lineColor),

                // Toolbar: Add Product & Custom Item
                Container(
                  color: const Color(0xFFFBF9F4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final selected =
                              await _pickProductDialog(context, store);
                          if (selected != null) {
                            setDialogState(() {
                              final existingIndex = linesList.indexWhere(
                                (l) => l['productId'] == selected['id'],
                              );
                              if (existingIndex >= 0) {
                                final currentQty =
                                    (linesList[existingIndex]['quantity']
                                            as num)
                                        .toDouble();
                                linesList[existingIndex]['quantity'] =
                                    currentQty + 1;
                              } else {
                                linesList.add({
                                  'productId': selected['id'],
                                  'name': selected['name'],
                                  'price':
                                      (selected['sellingPrice'] as num).toDouble(),
                                  'quantity': 1.0,
                                  'unit': selected['unit'] ?? 'pcs',
                                  'gst':
                                      (selected['gstRate'] as num?)?.toDouble() ??
                                          0.0,
                                  'discount': {'type': 'amount', 'value': 0},
                                  'image': selected['image'],
                                });
                              }
                            });
                          }
                        },
                        icon: const Icon(
                          Icons.add_shopping_cart_rounded,
                          size: 16,
                        ),
                        label: const Text('Add Product'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final custom = await _addCustomItemDialog(context);
                          if (custom != null) {
                            setDialogState(() {
                              linesList.add(custom);
                            });
                          }
                        },
                        icon: const Icon(Icons.playlist_add_rounded, size: 16),
                        label: const Text('Custom Item'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await store.saveDraft({
                            'lines': linesList,
                            'customer': invoice['customer'] ?? {},
                            'discount': invoice['discount'] ?? {
                              'type': 'amount',
                              'value': 0,
                            },
                            'gstEnabled': invoice['gstEnabled'] ?? false,
                            'taxInclusive': invoice['taxInclusive'] ?? false,
                            'interstate': invoice['interstate'] ?? false,
                          });
                          if (editDialogContext.mounted) {
                            Navigator.pop(editDialogContext);
                          }
                          if (context.mounted) Navigator.pop(context);
                          if (context.mounted) {
                            context.go('/pos');
                            toast(
                              context,
                              'Loaded invoice into POS cart to edit in register.',
                            );
                          }
                        },
                        icon: const Icon(Icons.point_of_sale_rounded, size: 16),
                        label: const Text('Edit in POS cart'),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${linesList.length} ${linesList.length == 1 ? 'item' : 'items'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: lineColor),

                // Items list
                Flexible(
                  child: linesList.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.remove_shopping_cart_outlined,
                                  size: 48,
                                  color: muted,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'No items in this invoice',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: muted,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Use "Add Product" or "Custom Item" above to add items.',
                                  style: TextStyle(fontSize: 12, color: muted),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: linesList.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 12, color: lineColor),
                          itemBuilder: (context, index) {
                            final item = linesList[index];
                            final qty =
                                (item['quantity'] as num?)?.toDouble() ?? 1.0;
                            final price =
                                (item['price'] as num?)?.toDouble() ?? 0.0;
                            final lineTotal = qty * price;
                            return Row(
                              children: [
                                _invoiceLineThumbnail(item, store),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${item['name']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${money(price)} / ${item['unit'] ?? 'pcs'}'
                                        '${(item['gst'] as num?) != null && (item['gst'] as num) > 0 ? ' · GST ${(item['gst'] as num)}%' : ''}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Stepper
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: lineColor),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 30,
                                          minHeight: 30,
                                        ),
                                        icon: const Icon(Icons.remove, size: 15),
                                        onPressed: () {
                                          setDialogState(() {
                                            if (qty > 1) {
                                              item['quantity'] = qty - 1;
                                            } else {
                                              linesList.removeAt(index);
                                            }
                                          });
                                        },
                                      ),
                                      InkWell(
                                        onTap: () async {
                                          final newQty =
                                              await _editQuantityDialog(
                                            context,
                                            qty,
                                            item['unit'] ?? 'pcs',
                                          );
                                          if (newQty != null && newQty > 0) {
                                            setDialogState(() {
                                              item['quantity'] = newQty;
                                            });
                                          }
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          child: Text(
                                            quantity(qty),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 30,
                                          minHeight: 30,
                                        ),
                                        icon: const Icon(Icons.add, size: 15),
                                        onPressed: () {
                                          setDialogState(() {
                                            item['quantity'] = qty + 1;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 75,
                                  child: Text(
                                    money(lineTotal),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Color(0xFFAF4137),
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    setDialogState(() {
                                      linesList.removeAt(index);
                                    });
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                ),

                const Divider(height: 1, color: lineColor),

                // Calculation breakdown summary bar
                if (previewBill != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    color: const Color(0xFFF9F7F2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Original: ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: muted,
                                  ),
                                ),
                                Text(
                                  money(originalTotal),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (totalDiff != 0)
                                  Pill(
                                    totalDiff > 0
                                        ? '+${money(totalDiff)}'
                                        : '-${money(-totalDiff)}',
                                    color: totalDiff > 0 ? accent : green,
                                  ),
                              ],
                            ),
                            if (invoice['gstEnabled'] == true) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Subtotal: ${money(previewBill['subtotal'])} · GST: ${money(previewBill['taxTotal'])}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Updated Total',
                              style: TextStyle(
                                fontSize: 11,
                                color: muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              money(currentTotal),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: ink,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                if (calculationError != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    color: const Color(0xFFFFECEC),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFAF4137),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            calculationError,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFAF4137),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Action buttons
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(editDialogContext),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: linesList.isEmpty || calculationError != null
                            ? null
                            : () async {
                                final messenger =
                                    ScaffoldMessenger.maybeOf(context);
                                try {
                                  await store.updateInvoiceLines(
                                    invoice['id'],
                                    linesList,
                                  );
                                  if (editDialogContext.mounted) {
                                    Navigator.pop(editDialogContext);
                                  }
                                  if (messenger != null) {
                                    messenger.hideCurrentSnackBar();
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Invoice items updated successfully',
                                        ),
                                        backgroundColor: ink,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (editDialogContext.mounted) {
                                    toast(editDialogContext, '$e', error: true);
                                  }
                                }
                              },
                        icon: const Icon(Icons.check_rounded, size: 17),
                        label: const Text('Save changes'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<Map<String, dynamic>?> _pickProductDialog(
  BuildContext context,
  AppStore store,
) async {
  String search = '';
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (pickerContext) => StatefulBuilder(
      builder: (context, setPickerState) {
        final q = search.trim().toLowerCase();
        final filtered = store.products.where((p) {
          if (p['archived'] == true) return false;
          if (q.isEmpty) return true;
          final name = (p['name'] ?? '').toString().toLowerCase();
          final code = (p['code'] ?? '').toString().toLowerCase();
          final cat = (p['category'] ?? '').toString().toLowerCase();
          return name.contains(q) || code.contains(q) || cat.contains(q);
        }).toList();

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        color: accent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Select product to add',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(pickerContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search product by name, code or category…',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (val) => setPickerState(() => search = val),
                  ),
                ),
                const Divider(height: 12, color: lineColor),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No products found',
                            style: TextStyle(color: muted),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1, color: lineColor),
                          itemBuilder: (context, i) {
                            final p = filtered[i];
                            final stock = store.stockFor(p['id']);
                            return ListTile(
                              leading: _invoiceLineThumbnail(
                                {'productId': p['id'], 'image': p['image']},
                                store,
                              ),
                              title: Text(
                                '${p['name']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                '${p['category'] ?? 'General'} · Stock: ${quantity(stock)} ${p['unit'] ?? 'pcs'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: stock <= (p['minStock'] ?? 0)
                                      ? Colors.red.shade700
                                      : muted,
                                ),
                              ),
                              trailing: Text(
                                money(p['sellingPrice'] ?? 0),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              onTap: () => Navigator.pop(pickerContext, p),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<Map<String, dynamic>?> _addCustomItemDialog(BuildContext context) async {
  final nameCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  String unit = 'pcs';
  double gstRate = 0.0;

  final res = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setCustomState) => AlertDialog(
        title: const Text(
          'Add custom item',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Item name *'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Price (₹) *'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Quantity *'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: const [
                        DropdownMenuItem(value: 'pcs', child: Text('pcs')),
                        DropdownMenuItem(value: 'kg', child: Text('kg')),
                        DropdownMenuItem(value: 'bag', child: Text('bag')),
                        DropdownMenuItem(value: 'm', child: Text('m')),
                        DropdownMenuItem(value: 'ft', child: Text('ft')),
                        DropdownMenuItem(value: 'box', child: Text('box')),
                        DropdownMenuItem(value: 'ltr', child: Text('ltr')),
                      ],
                      onChanged: (v) => setCustomState(() => unit = v ?? 'pcs'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<double>(
                initialValue: gstRate,
                decoration: const InputDecoration(labelText: 'GST Rate'),
                items: const [
                  DropdownMenuItem(value: 0.0, child: Text('0% (Exempt / None)')),
                  DropdownMenuItem(value: 5.0, child: Text('5%')),
                  DropdownMenuItem(value: 12.0, child: Text('12%')),
                  DropdownMenuItem(value: 18.0, child: Text('18%')),
                  DropdownMenuItem(value: 28.0, child: Text('28%')),
                ],
                onChanged: (v) => setCustomState(() => gstRate = v ?? 0.0),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text.trim());
              final qty = double.tryParse(qtyCtrl.text.trim());
              if (name.isEmpty ||
                  price == null ||
                  price < 0 ||
                  qty == null ||
                  qty <= 0) {
                return;
              }
              Navigator.pop(dialogContext, {
                'name': name,
                'price': price,
                'quantity': qty,
                'unit': unit,
                'gst': gstRate,
                'discount': {'type': 'amount', 'value': 0},
              });
            },
            child: const Text('Add item'),
          ),
        ],
      ),
    ),
  );
  nameCtrl.dispose();
  priceCtrl.dispose();
  qtyCtrl.dispose();
  return res;
}

Future<double?> _editQuantityDialog(
  BuildContext context,
  double current,
  String unit,
) async {
  final ctrl = TextEditingController(
    text: current.toStringAsFixed(current == current.roundToDouble() ? 0 : 2),
  );
  final res = await showDialog<double>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        'Edit quantity ($unit)',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 220,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: unit,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final val = double.tryParse(ctrl.text.trim());
            if (val != null && val > 0) {
              Navigator.pop(dialogContext, val);
            }
          },
          child: const Text('Apply'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return res;
}


