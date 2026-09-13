import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../data/app_store.dart';
import '../domain/billing.dart';
import 'common.dart';
import 'invoices.dart';
import 'inventory.dart';

class PosPage extends StatefulWidget {
  const PosPage({super.key, required this.store});
  final AppStore store;
  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  List<Json> lines = [];
  Json customer = {}, discount = {'type': 'amount', 'value': 0};
  String search = '', category = 'All items';
  bool mobileCart = false,
      gstEnabled = false,
      taxInclusive = false,
      interstate = false,
      busy = false;
  Timer? saveTimer;
  @override
  void initState() {
    super.initState();
    final draft = widget.store.draft;
    lines = (draft['lines'] as List? ?? []).map((e) => Json.from(e)).toList();
    customer = Json.from(draft['customer'] ?? {});
    discount = Json.from(draft['discount'] ?? discount);
    gstEnabled =
        draft['gstEnabled'] ?? widget.store.settings['gstEnabled'] ?? false;
    taxInclusive =
        draft['taxInclusive'] ?? widget.store.settings['taxInclusive'] ?? false;
    interstate = draft['interstate'] ?? false;
  }

  Json get draft => {
    'lines': lines,
    'customer': customer,
    'discount': discount,
    'gstEnabled': gstEnabled,
    'taxInclusive': taxInclusive,
    'interstate': interstate,
  };
  void changed() {
    setState(() {});
    saveTimer?.cancel();
    saveTimer = Timer(
      const Duration(milliseconds: 300),
      () => widget.store.saveDraft(draft).catchError((Object error) {
        if (mounted) {
          toast(context, 'Draft could not be saved: $error', error: true);
        }
      }),
    );
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    super.dispose();
  }

  Json get bill => calculateBill(
    lines: lines,
    discount: discount,
    gstEnabled: gstEnabled,
    taxInclusive: taxInclusive,
    interstate: interstate,
  );
  void addProduct(Json p) {
    final index = lines.indexWhere((l) => l['productId'] == p['id']);
    if (index < 0) {
      lines.add({
        'productId': p['id'],
        'name': p['name'],
        'unit': p['unit'],
        'price': p['price'],
        'quantity': 1,
        'gst': p['gst'] ?? 0,
        'hsn': p['hsn'] ?? '',
        'discount': {'type': 'amount', 'value': 0},
      });
    } else {
      lines[index]['quantity'] = number(lines[index]['quantity']) + 1;
    }
    changed();
  }

  Future<void> clearCart() async {
    if (lines.isEmpty) return;
    if (await confirm(
      context,
      'Clear this bill?',
      'The current draft will be removed.',
    )) {
      lines = [];
      discount = {'type': 'amount', 'value': 0};
      changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            () => editLine(),
        const SingleActivator(LogicalKeyboardKey.f1): () => editLine(),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (lines.isNotEmpty && !busy) {
            try {
              calculateBill(
                lines: lines,
                discount: discount,
                gstEnabled: gstEnabled,
                taxInclusive: taxInclusive,
                interstate: interstate,
              );
              checkout();
            } catch (_) {}
          }
        },
        const SingleActivator(LogicalKeyboardKey.f2): () {
          if (lines.isNotEmpty && !busy) {
            try {
              calculateBill(
                lines: lines,
                discount: discount,
                gstEnabled: gstEnabled,
                taxInclusive: taxInclusive,
                interstate: interstate,
              );
              checkout();
            } catch (_) {}
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): clearCart,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, c) {
            final cart = cartView();
            final catalog = catalogView();
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: catalog),
                      Container(
                        width: 380,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(left: BorderSide(color: lineColor)),
                        ),
                        child: cart,
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: mobileCart ? cart : catalog),
                      if (!mobileCart)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () =>
                                  setState(() => mobileCart = true),
                              icon: const Icon(Icons.shopping_bag_outlined),
                              label: Text(
                                'View bill  ·  ${lines.length} items  ·  ${money(bill['total'])}',
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
          },
        ),
      ),
    );
  }

  Widget catalogView() {
    final all = widget.store.products
        .where((p) => p['archived'] != true)
        .toList();
    final existingCats = widget.store.categories
        .where((c) => all.any((p) => '${p['category']}'.toLowerCase() == c.toLowerCase()))
        .toList();
    final cats = ['All items', ...existingCats];
    final items = all
        .where(
          (p) =>
              (category == 'All items' ||
                  '${p['category']}'.toLowerCase() == category.toLowerCase()) &&
              '${p['name']} ${p['code']}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();

    final screenW = MediaQuery.sizeOf(context).width;
    final isCompact = screenW < 750;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 12 : 24,
        isCompact ? 10 : 20,
        isCompact ? 12 : 24,
        isCompact ? 4 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCompact) ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Point of sale',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  onPressed: () => editLine(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text(
                    'Custom item (F1)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ] else ...[
            PageHeading(
              'Point of sale',
              'Good service starts with a simple bill.',
              action: OutlinedButton.icon(
                onPressed: () => editLine(),
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Custom / Loose item (F1)'),
              ),
            ),
          ],
          TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: InputDecoration(
              isDense: isCompact,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: isCompact ? 9 : 14,
              ),
              hintText: 'Search products by name or code…',
              prefixIcon: Icon(Icons.search_rounded, size: isCompact ? 19 : 21),
            ),
          ),
          SizedBox(height: isCompact ? 8 : 16),
          SizedBox(
            height: isCompact ? 36 : 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cats.length,
              separatorBuilder: (_, _) => SizedBox(width: isCompact ? 6 : 9),
              itemBuilder: (context, index) {
                final c = cats[index];
                final isSel = category == c;
                final catCount = c == 'All items'
                    ? all.length
                    : all
                        .where(
                          (p) =>
                              '${p['category']}'.toLowerCase() ==
                              c.toLowerCase(),
                        )
                        .length;
                if (isCompact) {
                  return Material(
                    color: isSel ? ink : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() => category = c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: isSel ? ink : lineColor),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              c == 'All items'
                                  ? Icons.apps_rounded
                                  : categoryIcon(c),
                              size: 14,
                              color: isSel ? Colors.white : muted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              c,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    isSel ? FontWeight.w700 : FontWeight.w500,
                                color: isSel ? Colors.white : ink,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : canvas,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$catCount',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isSel ? Colors.white : muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return Material(
                  color: isSel ? ink : Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () => setState(() => category = c),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 84),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: isSel ? ink : lineColor),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            c == 'All items'
                                ? Icons.apps_rounded
                                : categoryIcon(c),
                            color: isSel ? Colors.white : muted,
                            size: 20,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            c,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                              color: isSel ? Colors.white : ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (!isCompact) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  category,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Pill('${items.length}', color: muted),
                const Spacer(),
                const Icon(Icons.grid_view_rounded, size: 16, color: muted),
              ],
            ),
            const SizedBox(height: 12),
          ] else ...[
            const SizedBox(height: 8),
          ],
          Expanded(
            child: items.isEmpty
                ? SingleChildScrollView(
                    child: EmptyState(
                      icon: Icons.shopping_basket_outlined,
                      title: all.isEmpty
                          ? 'Stock your digital shelves'
                          : 'No products found',
                      message: all.isEmpty
                          ? 'Add products to your catalog, or create a custom item to start billing.'
                          : 'Try another product name or category.',
                      action: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => editProduct(context, widget.store),
                            child: const Text('Add product'),
                          ),
                          if (all.isEmpty)
                            TextButton(
                              onPressed: () => perform(
                                context,
                                () => widget.store.seedCatalog(),
                                success:
                                    'Sample catalog added. Review prices before selling.',
                              ),
                              child: const Text('Try sample catalog'),
                            ),
                        ],
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, c) => GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: (c.maxWidth / 160).floor().clamp(2, 6),
                        mainAxisExtent: isCompact ? 186 : 228,
                        crossAxisSpacing: isCompact ? 8 : 12,
                        mainAxisSpacing: isCompact ? 8 : 12,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final p = items[index];
                        final stock = widget.store.stockFor(p['id']);
                        final selected = lines.any(
                          (l) => l['productId'] == p['id'],
                        );
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () => addProduct(p),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: selected ? accent : lineColor,
                                  width: selected ? 1.5 : 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _productHeaderImage(
                                    p: p,
                                    index: index,
                                    isCompact: isCompact,
                                    stock: stock,
                                    selected: selected,
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        isCompact ? 9 : 12,
                                        isCompact ? 7 : 10,
                                        isCompact ? 9 : 12,
                                        isCompact ? 7 : 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${p['name']}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: isCompact ? 11 : 13,
                                              height: 1.2,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (!isCompact) ...[
                                            Text(
                                              '${quantity(stock)} ${p['unit']} in stock',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: stock <=
                                                        number(p['lowStock'])
                                                    ? accent
                                                    : muted,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                          ],
                                          Row(
                                            children: [
                                              Expanded(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    money(p['price']),
                                                    style: TextStyle(
                                                      fontSize: isCompact
                                                          ? 14
                                                          : 16,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                width: isCompact ? 24 : 28,
                                                height: isCompact ? 24 : 28,
                                                decoration: BoxDecoration(
                                                  color: selected
                                                      ? accent
                                                      : canvas,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Icon(
                                                  Icons.add,
                                                  size: isCompact ? 15 : 18,
                                                  color: selected
                                                      ? Colors.white
                                                      : ink,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget cartView() {
    Json totals;
    String? problem;
    try {
      totals = bill;
    } catch (e) {
      totals = {'total': 0};
      problem = '$e';
    }

    final screenW = MediaQuery.sizeOf(context).width;
    final isDesktopWide = screenW >= 1000;

    if (!isDesktopWide) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => mobileCart = false),
                  icon: const Icon(Icons.arrow_back, size: 20),
                ),
                const Expanded(
                  child: Text(
                    'Current bill',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                ),
                Pill('${lines.length} items', color: muted),
                IconButton(
                  tooltip: 'Clear bill (Esc)',
                  onPressed: lines.isEmpty ? null : clearCart,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 19,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: lines.isEmpty
                ? const SingleChildScrollView(
                    child: EmptyState(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Ready for your first item',
                      message:
                          'Tap a product in the catalog to add it to this bill.',
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _customerTile(),
                      const SizedBox(height: 12),
                      for (int index = 0; index < lines.length; index++) ...[
                        if (index > 0)
                          const Divider(height: 18, color: lineColor),
                        _cartItemWidget(index),
                      ],
                      const SizedBox(height: 16),
                      _billBreakdownCard(totals, problem, isMobile: true),
                      const SizedBox(height: 16),
                    ],
                  ),
          ),
          if (lines.isNotEmpty) _stickyMobileCheckoutBar(totals, problem),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Current bill',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                  ),
                ),
              ),
              Pill('${lines.length} items', color: muted),
              IconButton(
                tooltip: 'Clear bill (Esc)',
                onPressed: lines.isEmpty ? null : clearCart,
                icon: const Icon(Icons.delete_outline, size: 19, color: muted),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: _customerTile(),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: lines.isEmpty
              ? const SingleChildScrollView(
                  child: EmptyState(
                    icon: Icons.shopping_bag_outlined,
                    title: 'Ready for your first item',
                    message:
                        'Tap a product in the catalog to add it to this bill.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: lines.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 18, color: lineColor),
                  itemBuilder: (context, index) => _cartItemWidget(index),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: lineColor)),
          ),
          child: _billBreakdownCard(totals, problem, isMobile: false),
        ),
      ],
    );
  }

  Widget _customerTile() => Material(
    color: canvas,
    borderRadius: BorderRadius.circular(10),
    child: ListTile(
      dense: true,
      onTap: editCustomer,
      leading: const Icon(
        Icons.person_add_alt_outlined,
        size: 20,
        color: muted,
      ),
      title: Text(
        '${customer['name'] ?? ''}'.isEmpty
            ? 'Walk-in customer'
            : '${customer['name']}',
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      subtitle: Text(
        '${customer['address'] ?? ''}'.isEmpty
            ? 'Add customer details for this bill'
            : '${customer['address']}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: muted, fontSize: 10),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
    ),
  );

  Widget _cartItemWidget(int index) {
    final l = lines[index];
    final q = number(l['quantity']);
    final p = number(l['price']);
    final lineGross = q * p;
    final itemDisc =
        (l['discount'] as Map?) ?? {'type': 'amount', 'value': 0};
    final discVal = number(itemDisc['value']);
    final hasDisc = discVal > 0;
    double lineDiscountAmt = 0;
    if (hasDisc) {
      lineDiscountAmt = itemDisc['type'] == 'percent'
          ? (lineGross * (discVal / 100))
          : (discVal > lineGross ? lineGross : discVal);
    }
    final lineNet = (lineGross - lineDiscountAmt).clamp(0.0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${l['name']}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Edit item details',
              visualDensity: VisualDensity.compact,
              onPressed: () => editLine(index: index),
              icon: const Icon(
                Icons.edit_outlined,
                size: 16,
                color: muted,
              ),
            ),
            IconButton(
              tooltip: 'Remove item',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                lines.removeAt(index);
                changed();
              },
              icon: const Icon(
                Icons.close,
                size: 16,
                color: muted,
              ),
            ),
          ],
        ),
        Text(
          '${money(l['price'])} / ${l['unit']}',
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: lineColor),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Decrease quantity',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      if (q <= 1) {
                        lines.removeAt(index);
                      } else {
                        l['quantity'] = q - 1;
                      }
                      changed();
                    },
                    icon: const Icon(Icons.remove, size: 14),
                  ),
                  Text(
                    quantity(l['quantity']),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Increase quantity',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      l['quantity'] = q + 1;
                      changed();
                    },
                    icon: const Icon(Icons.add, size: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => editItemDiscount(index),
              borderRadius: BorderRadius.circular(7),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: hasDisc
                      ? green.withValues(alpha: 0.12)
                      : canvas,
                  border: Border.all(
                    color: hasDisc
                        ? green.withValues(alpha: 0.35)
                        : lineColor,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasDisc
                          ? Icons.local_offer
                          : Icons.discount_outlined,
                      size: 13,
                      color: hasDisc ? green : muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasDisc
                          ? (itemDisc['type'] == 'percent'
                              ? '${itemDisc['value']}% off'
                              : '-${money(discVal)}')
                          : '+ Disc',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: hasDisc
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: hasDisc ? green : ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasDisc)
                  Text(
                    money(lineGross),
                    style: const TextStyle(
                      fontSize: 10,
                      color: muted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                Text(
                  money(lineNet),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: hasDisc ? green : ink,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (hasDisc)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Pill(
                  'Item saving: -${money(lineDiscountAmt)} (${itemDisc['type'] == 'percent' ? '${itemDisc['value']}%' : money(discVal)} off)',
                  color: green,
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    l['discount'] = {
                      'type': 'amount',
                      'value': 0,
                    };
                    changed();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 13,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (l['productId'] != null &&
            number(l['quantity']) >
                widget.store.stockFor(l['productId']))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Quantity exceeds available stock',
              style: TextStyle(color: accent, fontSize: 10),
            ),
          ),
      ],
    );
  }

  Widget _stickyMobileCheckoutBar(Json totals, String? problem) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: lineColor)),
      boxShadow: [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 6,
          offset: Offset(0, -2),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${lines.length} ${lines.length == 1 ? 'item' : 'items'}',
                style: const TextStyle(
                  fontSize: 10,
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                money(totals['total']),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: FilledButton.icon(
              onPressed: lines.isEmpty || busy || problem != null
                  ? null
                  : checkout,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                busy ? 'Saving bill…' : 'Continue to payment (F2)',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _billBreakdownCard(
    Json totals,
    String? problem, {
    required bool isMobile,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (number(discount['value']) > 0)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: green.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_outlined, size: 16, color: green),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bill discount: ${discount['type'] == 'percent' ? '${discount['value']}% off' : money(discount['value'])}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: green,
                      ),
                    ),
                    Text(
                      'Saving ${money(totals['overallDiscountTotal'] ?? totals['discountTotal'])} on total bill',
                      style: TextStyle(
                        fontSize: 10,
                        color: green.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onPressed: lines.isEmpty ? null : editDiscount,
                child: const Text('Edit', style: TextStyle(fontSize: 11)),
              ),
              IconButton(
                tooltip: 'Remove discount',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 15, color: muted),
                onPressed: () {
                  discount = {'type': 'amount', 'value': 0};
                  changed();
                },
              ),
            ],
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(double.infinity, 34),
              side: const BorderSide(color: lineColor),
            ),
            onPressed: lines.isEmpty ? null : editDiscount,
            icon: const Icon(
              Icons.percent_rounded,
              size: 14,
              color: accent,
            ),
            label: const Text(
              '+ Add overall bill discount (₹ or %)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Bill summary',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          if (number(discount['value']) <= 0)
            TextButton.icon(
              onPressed: lines.isEmpty ? null : editDiscount,
              icon: const Icon(Icons.discount_outlined, size: 14),
              label: const Text(
                'Discount',
                style: TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
      _totalRow('Gross Subtotal', totals['subtotal']),
      if (number(totals['itemDiscountTotal']) > 0)
        _totalRow(
          'Item discounts',
          -(number(totals['itemDiscountTotal'])),
          highlightGreen: true,
        ),
      if (number(totals['overallDiscountTotal']) > 0)
        _totalRow(
          'Bill discount (${discount['type'] == 'percent' ? '${discount['value']}%' : money(discount['value'])})',
          -(number(totals['overallDiscountTotal'])),
          highlightGreen: true,
        ),
      if (number(totals['itemDiscountTotal']) <= 0 &&
          number(totals['overallDiscountTotal']) <= 0 &&
          number(totals['discountTotal']) > 0)
        _totalRow(
          'Discounts',
          -(number(totals['discountTotal'])),
          highlightGreen: true,
        ),
      if (gstEnabled) ...[
        _totalRow('Taxable value', totals['taxableTotal']),
        _totalRow(
          taxInclusive ? 'GST (included in prices)' : 'GST added',
          totals['taxTotal'],
        ),
      ] else if (number(totals['taxTotal']) > 0)
        _totalRow('Tax', totals['taxTotal']),
      Row(
        children: [
          const Expanded(
            child: Text(
              'GST billing',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ),
          Switch(
            value: gstEnabled,
            onChanged: (v) {
              gstEnabled = v;
              changed();
            },
          ),
        ],
      ),
      if (gstEnabled)
        Row(
          children: [
            Expanded(
              child: Text(
                taxInclusive
                    ? 'Prices include tax'
                    : 'Tax added to prices',
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ),
            TextButton(
              onPressed: () {
                taxInclusive = !taxInclusive;
                changed();
              },
              child: const Text(
                'Change',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      if (problem != null)
        Text(
          problem,
          style: const TextStyle(color: Colors.red, fontSize: 11),
        ),
      if (!isMobile) ...[
        const Divider(color: lineColor),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text(
              'Total amount',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              money(totals['total']),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: lines.isEmpty || busy || problem != null
                ? null
                : checkout,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(
              busy ? 'Saving bill…' : 'Continue to payment (F2)',
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Shortcuts: F1 Custom / Loose item · F2 Checkout · Esc Clear',
          style: TextStyle(fontSize: 10, color: muted),
        ),
        const SizedBox(height: 3),
        const Text(
          'Draft saves automatically on this device',
          style: TextStyle(fontSize: 9, color: muted),
        ),
      ] else ...[
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'Shortcuts: F1 Custom item · F2 Checkout · Esc Clear',
            style: TextStyle(fontSize: 10, color: muted),
          ),
        ),
      ],
    ],
  );

  Widget _totalRow(
    String label,
    dynamic value, {
    bool highlightGreen = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: highlightGreen ? green : muted,
            fontSize: 12,
            fontWeight: highlightGreen ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        const Spacer(),
        Text(
          money(value),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: highlightGreen ? green : ink,
          ),
        ),
      ],
    ),
  );
  Future<void> editLine({int? index}) async {
    final item = index == null
        ? <String, dynamic>{
            'name': '',
            'unit': 'pcs',
            'price': 0,
            'quantity': 1,
            'gst': 0,
            'hsn': '',
            'discount': {'type': 'amount', 'value': 0},
          }
        : Json.from(lines[index]);
    final cs = {
      for (final k in ['name', 'unit', 'price', 'quantity', 'gst', 'hsn'])
        k: TextEditingController(text: '${item[k] ?? ''}'),
    };
    final dc = TextEditingController(
      text: '${(item['discount'] as Map?)?['value'] ?? 0}',
    );
    final catController = TextEditingController(text: 'General');
    final codeController = TextEditingController(text: '');
    bool saveToCatalog = false;
    String type = (item['discount'] as Map?)?['type'] ?? 'amount';
    await showDialog(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, set) => AlertDialog(
          title: Text(
              index == null ? 'Add custom / loose item' : 'Edit bill item'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  field('Item name', cs['name']!),
                  Row(
                    children: [
                      Expanded(
                        child: field(
                          'Unit price (₹)',
                          cs['price']!,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: field(
                          'Quantity',
                          cs['quantity']!,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  UnitSelector(
                    controller: cs['unit']!,
                    labelText: 'Unit (pcs, kg, bag, m, ton, ltr…)',
                    extraUnits: [
                      for (final prod in widget.store.products)
                        if (prod['unit'] != null) '${prod['unit']}',
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child:
                            field('GST rate (%)', cs['gst']!, numeric: true),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: field('HSN code (optional)', cs['hsn']!),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: field('Item discount', dc, numeric: true),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: type,
                        items: const [
                          DropdownMenuItem(
                            value: 'amount',
                            child: Text('₹ amount'),
                          ),
                          DropdownMenuItem(
                            value: 'percent',
                            child: Text('% percent'),
                          ),
                        ],
                        onChanged: (v) => set(() => type = v!),
                      ),
                    ],
                  ),
                  if (index == null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: canvas,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: lineColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text(
                              'Also save as catalog product',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: const Text(
                              'Makes this item permanently available in your POS catalog',
                              style: TextStyle(fontSize: 10, color: muted),
                            ),
                            value: saveToCatalog,
                            onChanged: (v) =>
                                set(() => saveToCatalog = v ?? false),
                          ),
                          if (saveToCatalog) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Select category',
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: widget.store.categories.any(
                                          (c) =>
                                              c.toLowerCase() ==
                                              catController.text.trim().toLowerCase(),
                                        )
                                            ? widget.store.categories.firstWhere(
                                                (c) =>
                                                    c.toLowerCase() ==
                                                    catController.text.trim().toLowerCase(),
                                              )
                                            : null,
                                        isExpanded: true,
                                        hint: const Text(
                                          'Choose…',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        items: [
                                          for (final c in widget.store.categories)
                                            DropdownMenuItem(
                                              value: c,
                                              child: Text(
                                                c,
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                            ),
                                        ],
                                        onChanged: (v) {
                                          if (v != null) {
                                            set(() => catController.text = v);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: field('Or enter name', catController),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            field('Product code (optional)', codeController),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Custom and loose items without catalog save are included in this bill without affecting inventory.',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
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
              onPressed: () async {
                try {
                  final l = <String, dynamic>{
                    ...item,
                    for (final k in cs.keys) k: cs[k]!.text,
                    'discount': {'type': type, 'value': double.parse(dc.text)},
                  };
                  for (final k in ['price', 'quantity', 'gst']) {
                    l[k] = double.parse(cs[k]!.text);
                  }
                  calculateBill(lines: [l]);
                  if (index == null) {
                    if (saveToCatalog) {
                      final newId = const Uuid().v4();
                      final cat = catController.text.trim().isEmpty
                          ? 'General'
                          : catController.text.trim();
                      await widget.store.saveProduct({
                        'id': newId,
                        'name': l['name'],
                        'code': codeController.text.trim(),
                        'price': l['price'],
                        'unit': l['unit'],
                        'category': cat,
                        'gst': l['gst'],
                        'hsn': l['hsn'],
                        'lowStock': 5,
                        'archived': false,
                      });
                      l['productId'] = newId;
                    }
                    lines.add(l);
                  } else {
                    lines[index] = l;
                  }
                  changed();
                  if (dialog.mounted) Navigator.pop(dialog);
                  if (index == null && saveToCatalog && mounted) {
                    toast(context, 'Added "${l['name']}" to product catalog');
                  }
                } catch (e) {
                  if (dialog.mounted) {
                    toast(dialog, '$e', error: true);
                  }
                }
              },
              child: const Text('Save item'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> editItemDiscount(int index) async {
    final item = lines[index];
    final disc = Map<String, dynamic>.from(
      item['discount'] as Map? ?? {'type': 'amount', 'value': 0},
    );
    final controller = TextEditingController(
      text: number(disc['value']) > 0 ? '${disc['value']}' : '',
    );
    String type = disc['type'] ?? 'percent';
    final qty = number(item['quantity']);
    final pr = number(item['price']);
    final gross = qty * pr;

    await showDialog(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, set) {
          final val = double.tryParse(controller.text.trim()) ?? 0.0;
          double discAmount = 0;
          if (type == 'percent') {
            discAmount = gross * (val / 100);
          } else {
            discAmount = val > gross ? gross : val;
          }
          final finalPrice = (gross - discAmount).clamp(0.0, double.infinity);

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.local_offer_outlined, color: accent, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Item discount',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${item['name']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: muted,
                          fontWeight: FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: canvas,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: lineColor),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${quantity(qty)} ${item['unit']} × ${money(pr)}',
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                          Text(
                            'Gross: ${money(gross)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('% Percentage')),
                            selected: type == 'percent',
                            onSelected: (_) => set(() => type = 'percent'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('₹ Rupee amount')),
                            selected: type == 'amount',
                            onSelected: (_) => set(() => type = 'amount'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        const Text(
                          'Presets:',
                          style: TextStyle(fontSize: 11, color: muted, height: 2),
                        ),
                        for (final p in type == 'percent'
                            ? [2, 5, 10, 15, 20, 25]
                            : [10, 20, 50, 100, 200, 500])
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              type == 'percent' ? '$p%' : '₹$p',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onPressed: () =>
                                set(() => controller.text = '$p'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: type == 'percent'
                            ? 'Discount percentage (%)'
                            : 'Discount amount (₹)',
                        prefixText: type == 'percent' ? '% ' : '₹ ',
                        hintText: 'Enter discount value',
                      ),
                      onChanged: (_) => set(() {}),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: val > 0
                            ? green.withValues(alpha: 0.1)
                            : canvas,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: val > 0
                              ? green.withValues(alpha: 0.3)
                              : lineColor,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Discount value:',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                              Text(
                                '-${money(discAmount)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: val > 0 ? green : muted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Item total after discount:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                money(finalPrice),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: val > 0 ? green : ink,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (number(disc['value']) > 0)
                TextButton(
                  onPressed: () {
                    item['discount'] = {'type': 'amount', 'value': 0};
                    changed();
                    Navigator.pop(dialog);
                  },
                  child: const Text(
                    'Remove discount',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final v = double.tryParse(controller.text.trim()) ?? 0.0;
                  item['discount'] = {'type': type, 'value': v};
                  changed();
                  Navigator.pop(dialog);
                },
                child: const Text('Apply discount'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> editDiscount() async {
    final controller = TextEditingController(
      text: number(discount['value']) > 0 ? '${discount['value']}' : '',
    );
    String type = discount['type'] ?? 'percent';
    await showDialog(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, set) {
          final billTotalBefore = bill;
          final grossSub = number(billTotalBefore['subtotal']);
          final itemDisc = number(billTotalBefore['itemDiscountTotal']);
          final netBeforeBillDisc = grossSub - itemDisc;
          final val = double.tryParse(controller.text.trim()) ?? 0.0;
          double billDiscAmount = 0;
          if (type == 'percent') {
            billDiscAmount = netBeforeBillDisc * (val / 100);
          } else {
            billDiscAmount = val > netBeforeBillDisc ? netBeforeBillDisc : val;
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.discount_outlined, color: accent, size: 22),
                SizedBox(width: 8),
                Text('Overall bill discount'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: canvas,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: lineColor),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Eligible bill subtotal:',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                          Text(
                            money(netBeforeBillDisc),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('% Percentage')),
                            selected: type == 'percent',
                            onSelected: (_) => set(() => type = 'percent'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('₹ Rupee amount')),
                            selected: type == 'amount',
                            onSelected: (_) => set(() => type = 'amount'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        const Text(
                          'Presets:',
                          style: TextStyle(fontSize: 11, color: muted, height: 2),
                        ),
                        for (final p in type == 'percent'
                            ? [2, 5, 10, 15, 20]
                            : [20, 50, 100, 200, 500])
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              type == 'percent' ? '$p%' : '₹$p',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onPressed: () =>
                                set(() => controller.text = '$p'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: type == 'percent'
                            ? 'Overall bill discount (%)'
                            : 'Overall bill discount (₹)',
                        prefixText: type == 'percent' ? '% ' : '₹ ',
                        hintText: 'Enter discount value',
                      ),
                      onChanged: (_) => set(() {}),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: val > 0
                            ? green.withValues(alpha: 0.1)
                            : canvas,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: val > 0
                              ? green.withValues(alpha: 0.3)
                              : lineColor,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Overall bill saving:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '-${money(billDiscAmount)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: val > 0 ? green : muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Applied after individual item discounts.',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (number(discount['value']) > 0)
                TextButton(
                  onPressed: () {
                    discount = {'type': 'amount', 'value': 0};
                    changed();
                    Navigator.pop(dialog);
                  },
                  child: const Text(
                    'Remove discount',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  try {
                    final v = double.tryParse(controller.text.trim()) ?? 0.0;
                    final d = {'type': type, 'value': v};
                    calculateBill(
                      lines: lines,
                      discount: d,
                      gstEnabled: gstEnabled,
                      taxInclusive: taxInclusive,
                    );
                    discount = d;
                    changed();
                    Navigator.pop(dialog);
                  } catch (e) {
                    toast(dialog, '$e', error: true);
                  }
                },
                child: const Text('Apply discount'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> editCustomer() async {
    final cs = {
      for (final k in ['name', 'phone', 'address', 'gstin', 'state'])
        k: TextEditingController(text: '${customer[k] ?? ''}'),
    };
    await showDialog(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Customer details'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.store.customers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Choose a saved customer',
                      ),
                      items: [
                        for (final c in widget.store.customers)
                          DropdownMenuItem(
                            value: '${c['id']}',
                            child: Text(
                              '${c['name']} ${c['phone'] ?? ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        final c = widget.store.customers.firstWhere(
                          (c) => c['id'] == id,
                        );
                        customer = Json.from(c);
                        for (final k in cs.keys) {
                          cs[k]!.text = '${c[k] ?? ''}';
                        }
                      },
                    ),
                  ),
                field('Customer name', cs['name']!),
                field('Phone number', cs['phone']!),
                field('Address', cs['address']!, lines: 2),
                field('GSTIN (optional)', cs['gstin']!),
                field('State / place of supply', cs['state']!),
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
            onPressed: () {
              customer = {
                ...customer,
                for (final k in cs.keys) k: cs[k]!.text.trim(),
              };
              changed();
              Navigator.pop(dialog);
            },
            child: const Text('Save customer'),
          ),
        ],
      ),
    );
  }

  Future<void> checkout() async {
    final amount = TextEditingController(
      text: number(bill['total']).toStringAsFixed(2),
    );
    String method = 'Cash';
    List<Json> entries = [];
    bool saving = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, set) {
          final total = number(bill['total']);
          final paid = entries.fold<double>(
            0,
            (sum, p) => sum + number(p['amount']),
          );
          return AlertDialog(
            title: const Text('Complete the sale'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      money(total),
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${customer['name'] ?? ''}'.isEmpty
                          ? 'Walk-in customer'
                          : '${customer['name']}',
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 18),
                    if (gstEnabled)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Interstate sale (IGST)',
                          style: TextStyle(fontSize: 12),
                        ),
                        subtitle: const Text(
                          'Otherwise CGST + SGST',
                          style: TextStyle(fontSize: 10),
                        ),
                        value: interstate,
                        onChanged: saving
                            ? null
                            : (v) {
                                interstate = v!;
                                changed();
                                set(() {});
                              },
                      ),
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
                    const SizedBox(height: 16),
                    field('Amount received now (₹)', amount, numeric: true),
                    OutlinedButton.icon(
                      onPressed: saving
                          ? null
                          : () {
                              try {
                                final value = double.parse(amount.text);
                                if (!value.isFinite ||
                                    value <= 0 ||
                                    value > total - paid + .001) {
                                  throw ArgumentError(
                                    'Enter a positive amount within the remaining balance.',
                                  );
                                }
                                set(() {
                                  entries.add({
                                    'method': method,
                                    'amount': value,
                                  });
                                  amount.text = (total - paid - value)
                                      .toStringAsFixed(2);
                                });
                              } catch (e) {
                                toast(dialog, '$e', error: true);
                              }
                            },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add split payment'),
                    ),
                    for (var i = 0; i < entries.length; i++)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${entries[i]['method']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(money(entries[i]['amount'])),
                            IconButton(
                              onPressed: saving
                                  ? null
                                  : () => set(() => entries.removeAt(i)),
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Use 0 for a fully unpaid bill. Any remaining amount becomes customer dues. A customer name is required for credit.',
                      style: TextStyle(color: muted, fontSize: 11, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialog),
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        set(() => saving = true);
                        try {
                          final remainder = double.parse(amount.text);
                          final payments = [
                            ...entries,
                            if (remainder != 0)
                              {'method': method, 'amount': remainder},
                          ];
                          saveTimer?.cancel();
                          busy = true;
                          final invoice = await widget.store.finalizeInvoice(
                            lines: lines,
                            customer: customer,
                            discount: discount,
                            paymentEntries: payments,
                            gstEnabled: gstEnabled,
                            taxInclusive: taxInclusive,
                            interstate: interstate,
                          );
                          lines = [];
                          customer = {};
                          discount = {'type': 'amount', 'value': 0};
                          busy = false;
                          if (mounted) setState(() {});
                          if (dialog.mounted) Navigator.pop(dialog);
                          if (mounted) {
                            await showInvoice(context, widget.store, invoice);
                          }
                        } catch (e) {
                          busy = false;
                          if (dialog.mounted) {
                            toast(dialog, '$e', error: true);
                            set(() => saving = false);
                          }
                        }
                      },
                child: Text(saving ? 'Saving…' : 'Save invoice'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _productHeaderImage({
    required Map<String, dynamic> p,
    required int index,
    required bool isCompact,
    required double stock,
    required bool selected,
  }) {
    final rawImage = p['image'] as String?;
    final hasImage = rawImage != null && rawImage.trim().isNotEmpty;
    final imageHeight = isCompact ? 88.0 : 118.0;

    Widget imageContent;
    if (hasImage) {
      try {
        final clean = rawImage.contains(',')
            ? rawImage.split(',').last.trim()
            : rawImage.trim();
        final bytes = base64Decode(clean);
        imageContent = Image.memory(
          bytes,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _defaultHeaderIcon(p, index, isCompact),
        );
      } catch (_) {
        imageContent = _defaultHeaderIcon(p, index, isCompact);
      }
    } else {
      imageContent = _defaultHeaderIcon(p, index, isCompact);
    }

    final lowStock = stock <= number(p['lowStock']);

    return SizedBox(
      height: imageHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            child: imageContent,
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: lowStock
                    ? accent.withValues(alpha: 0.92)
                    : Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                '${quantity(stock)} ${p['unit']}',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (selected)
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _defaultHeaderIcon(
    Map<String, dynamic> p,
    int index,
    bool isCompact,
  ) {
    return Container(
      color: [
        const Color(0xFFF0EDE5),
        const Color(0xFFEAF0E8),
        const Color(0xFFE9EDF2),
        const Color(0xFFF6EAE0),
      ][index % 4],
      child: Center(
        child: Icon(
          categoryIcon('${p['category']}'),
          color: [
            const Color(0xFF938363),
            green,
            const Color(0xFF637891),
            accent,
          ][index % 4],
          size: isCompact ? 30 : 40,
        ),
      ),
    );
  }
}

