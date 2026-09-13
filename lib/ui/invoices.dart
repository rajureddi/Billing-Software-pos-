import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../data/app_store.dart';
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
            action: Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Pill('Outstanding ${money(dues)}', color: accent),
                FilledButton.icon(
                  onPressed: () => recordPaymentDialog(context, store),
                  icon: const Icon(Icons.payments_outlined, size: 17),
                  label: const Text('Record payment'),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                label: Text('Invoices (${store.invoices.length})'),
                selected: viewIndex == 0,
                onSelected: (_) => setState(() => viewIndex = 0),
              ),
              ChoiceChip(
                label: Text(
                  'Customer Balances (${store.customerBalances.where((c) => (c['due'] as double) > 0).length} with dues)',
                ),
                selected: viewIndex == 1,
                onSelected: (_) => setState(() => viewIndex = 1),
              ),
            ],
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in [
                        'All invoices',
                        'Unpaid',
                        'Paid',
                        'Cancelled',
                      ])
                        ChoiceChip(
                          label: Text(f),
                          selected: filter == f,
                          onSelected: (_) => setState(() => filter = f),
                        ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final r = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 1)),
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
                      if (range != null)
                        IconButton(
                          onPressed: () => setState(() => range = null),
                          icon: const Icon(Icons.close),
                        ),
                    ],
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
                                    : 'Paid',
                                color: due > 0 ? accent : green,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          for (final line in invoice['lines'] as List)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              child: Row(
                                children: [
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
          onPressed: () => perform(dialog, () async {
            await store.recordPayment(
              invoice['id'],
              double.parse(amount.text),
              method,
            );
            if (dialog.mounted) Navigator.pop(dialog);
          }, success: 'Payment recorded'),
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
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, set) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => perform(dialog, () async {
              final val = double.parse(amount.text);
              await store.recordPayment(selectedId, val, method);
              if (dialog.mounted) Navigator.pop(dialog);
            }, success: 'Payment recorded'),
            child: const Text('Save payment'),
          ),
        ],
      ),
    ),
  );
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
