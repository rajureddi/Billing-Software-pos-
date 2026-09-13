import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_store.dart';
import 'common.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.store});
  final AppStore store;
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  int viewIndex = 0;
  String search = '', category = 'All products', movementSearch = '';
  bool lowOnly = false, shortageOnly = false;
  @override
  Widget build(BuildContext context) {
    final all = widget.store.products
        .where((p) => p['archived'] != true)
        .toList();
    final existingCats = widget.store.categories
        .where((c) => all.any((p) => '${p['category']}'.toLowerCase() == c.toLowerCase()))
        .toList();
    final cats = [
      'All products',
      ...existingCats,
    ];
    final items = all
        .where(
          (p) =>
              '${p['name']} ${p['code']}'.toLowerCase().contains(
                search.toLowerCase(),
              ) &&
              (category == 'All products' ||
                  '${p['category']}'.toLowerCase() == category.toLowerCase()) &&
              (!lowOnly ||
                  widget.store.stockFor(p['id']) <= number(p['lowStock'])) &&
              (!shortageOnly || widget.store.stockFor(p['id']) < 0),
        )
        .toList();
    final movements = widget.store.allMovementsWithProducts
        .where(
          (m) =>
              '${m['productName']} ${m['productCode']} ${m['reason']}'
                  .toLowerCase()
                  .contains(movementSearch.toLowerCase()),
        )
        .toList();
    final shortageCount =
        all.where((p) => widget.store.stockFor(p['id']) < 0).length;

    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isCompact ? 14 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            'Inventory & stock ledger',
            'Track units, record adjustments, and audit movement history.',
            action: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => receiveStockDialog(context, widget.store),
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 17),
                    label: const Text('Add / Receive stock'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => editProduct(context, widget.store),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add product'),
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
                  label: Text('Products (${all.length})'),
                  selected: viewIndex == 0,
                  onSelected: (_) => setState(() => viewIndex = 0),
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: Text(
                    'Movement Ledger (${widget.store.movements.length})',
                  ),
                  selected: viewIndex == 1,
                  onSelected: (_) => setState(() => viewIndex = 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (viewIndex == 0) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Pill('${all.length} active products'),
                  const SizedBox(width: 8),
                  Pill('${cats.length - 1} categories', color: muted),
                  if (shortageCount > 0) ...[
                    const SizedBox(width: 8),
                    Pill(
                      '$shortageCount shortage(s)',
                      color: const Color(0xFFC74343),
                    ),
                  ],
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Low stock only'),
                    selected: lowOnly,
                    onSelected: (v) => setState(() => lowOnly = v),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Shortages / Negative stock only'),
                    selected: shortageOnly,
                    onSelected: (v) => setState(() => shortageOnly = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Panel(
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => search = v),
                  decoration: const InputDecoration(
                    hintText: 'Search products by name or code',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final c in cats)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c),
                            selected: category == c,
                            onSelected: (_) => setState(() => category = c),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (items.isEmpty)
                  EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: all.isEmpty
                        ? 'Build your catalog'
                        : 'No matching products',
                    message: all.isEmpty
                        ? 'Add cement, plumbing supplies, steel, tools and everything your shop sells.'
                        : 'Try a different search or category.',
                    action: all.isEmpty
                        ? TextButton(
                            onPressed: () => perform(
                              context,
                              () => widget.store.seedCatalog(),
                              success: 'Sample catalog added',
                            ),
                            child: const Text('Load sample catalog'),
                          )
                        : null,
                  ),
                if (items.isNotEmpty)
                    LayoutBuilder(
                      builder: (context, c) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: c.maxWidth),
                          child: DataTable(
                            headingRowColor: const WidgetStatePropertyAll(canvas),
                            horizontalMargin: 14,
                            columnSpacing: 24,
                            columns: const [
                              DataColumn(label: Text('PRODUCT')),
                              DataColumn(label: Text('CATEGORY')),
                              DataColumn(label: Text('PRICE')),
                              DataColumn(label: Text('STOCK')),
                              DataColumn(label: Text('ACTIONS')),
                            ],
                            rows: [
                              for (final p in items)
                                DataRow(
                                  cells: [
                                    DataCell(
                                      Row(
                                        children: [
                                          Icon(
                                            categoryIcon('${p['category']}'),
                                            color: green,
                                            size: 21,
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${p['name']}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              Text(
                                                '${p['code']}',
                                                style: const TextStyle(
                                                  color: muted,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      onTap: () => editProduct(
                                        context,
                                        widget.store,
                                        product: p,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${p['category']}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${money(p['price'])} / ${p['unit']}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    DataCell(
                                      Builder(
                                        builder: (context) {
                                          final stock =
                                              widget.store.stockFor(p['id']);
                                          final isNegative = stock < 0;
                                          final isLow =
                                              stock <= number(p['lowStock']);
                                          return Pill(
                                            isNegative
                                                ? 'Shortage ${quantity(stock)} ${p['unit']}'
                                                : '${quantity(stock)} ${p['unit']}',
                                            color: isNegative
                                                ? const Color(0xFFC74343)
                                                : isLow
                                                    ? accent
                                                    : green,
                                          );
                                        },
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        children: [
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              textStyle: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            onPressed: () => receiveStockDialog(
                                              context,
                                              widget.store,
                                              product: p,
                                            ),
                                            icon: const Icon(Icons.add, size: 13),
                                            label: const Text('Stock'),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            tooltip: 'Edit product',
                                            onPressed: () => editProduct(
                                              context,
                                              widget.store,
                                              product: p,
                                            ),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 18,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Archive product',
                                            onPressed: () async {
                                              if (await confirm(
                                                context,
                                                'Archive ${p['name']}?',
                                                'This hides the product from your catalog. Existing invoices remain unchanged.',
                                              )) {
                                                if (context.mounted) {
                                                  await perform(
                                                    context,
                                                    () =>
                                                        widget.store.saveProduct({
                                                          ...p,
                                                          'archived': true,
                                                        }),
                                                  );
                                                }
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.archive_outlined,
                                              size: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ] else
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    onChanged: (v) => setState(() => movementSearch = v),
                    decoration: const InputDecoration(
                      hintText:
                          'Search movement by product name, code, or reason…',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (movements.isEmpty)
                    const EmptyState(
                      icon: Icons.history_rounded,
                      title: 'No stock movements recorded',
                      message:
                          'Stock movements from sales, opening inventory, adjustments, and cancellations will appear here.',
                    ),
                  if (movements.isNotEmpty)
                    LayoutBuilder(
                      builder: (context, c) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: c.maxWidth),
                          child: DataTable(
                            headingRowColor:
                                const WidgetStatePropertyAll(canvas),
                            horizontalMargin: 14,
                            columnSpacing: 20,
                            columns: const [
                              DataColumn(label: Text('DATE & TIME')),
                              DataColumn(label: Text('PRODUCT')),
                              DataColumn(label: Text('CHANGE')),
                              DataColumn(label: Text('REASON / INVOICE')),
                            ],
                            rows: [
                              for (final m in movements)
                                DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        dateLabel(m['createdAt']),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${m['productName']}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                          if ('${m['productCode']}'.isNotEmpty)
                                            Text(
                                              '${m['productCode']}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: muted,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Pill(
                                        '${(m['quantity'] as num) > 0 ? '+' : ''}${quantity(m['quantity'])} ${m['productUnit']}',
                                        color: (m['quantity'] as num) > 0
                                            ? green
                                            : (m['quantity'] as num) < 0
                                                ? accent
                                                : muted,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${m['reason']}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
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

Future<void> editProduct(
  BuildContext context,
  AppStore store, {
  Json? product,
}) async {
  final p = product ?? {};
  final controllers = {
    for (final key in [
      'name',
      'code',
      'category',
      'unit',
      'price',
      'gst',
      'hsn',
      'lowStock',
      'openingStock',
    ])
      key: TextEditingController(
        text:
            '${p[key] ?? switch (key) {
                  'category' => 'General',
                  'unit' => 'pcs',
                  'price' => '0',
                  'gst' => '0',
                  'lowStock' => '5',
                  'openingStock' => '0',
                  _ => '',
                }}',
      ),
  };
  final existingCats = store.categories;
  String? selectedDropdownCat = existingCats.firstWhere(
    (c) =>
        c.toLowerCase() == controllers['category']!.text.trim().toLowerCase(),
    orElse: () => '',
  );
  if (selectedDropdownCat.isEmpty) selectedDropdownCat = null;
  String? imageBase64 = p['image'] as String?;
  var saving = false;
  await showDialog(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, set) => AlertDialog(
        title: Text(product == null ? 'Add product' : 'Edit product'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                field('Product name', controllers['name']!),
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: canvas,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: lineColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: lineColor),
                        ),
                        child: imageBase64 != null &&
                                imageBase64!.trim().isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Image.memory(
                                  base64Decode(
                                    imageBase64!.contains(',')
                                        ? imageBase64!.split(',').last.trim()
                                        : imageBase64!.trim(),
                                  ),
                                  fit: BoxFit.cover,
                                  width: 88,
                                  height: 88,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.broken_image_outlined,
                                    color: muted,
                                    size: 32,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.image_outlined,
                                color: muted,
                                size: 36,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Product image (POS only)',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Take photo with camera or upload file',
                              style: TextStyle(fontSize: 10, color: muted),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                  ),
                                  onPressed: () async {
                                    try {
                                      final picker = ImagePicker();
                                      final picked = await picker.pickImage(
                                        source: ImageSource.camera,
                                        maxWidth: 1024,
                                        maxHeight: 1024,
                                        imageQuality: 85,
                                      );
                                      if (picked != null) {
                                        final bytes =
                                            await picked.readAsBytes();
                                        set(() {
                                          imageBase64 = base64Encode(bytes);
                                        });
                                      }
                                    } catch (_) {
                                      final result = await FilePicker.pickFile(
                                        type: FileType.custom,
                                        allowedExtensions: [
                                          'png',
                                          'jpg',
                                          'jpeg',
                                          'webp',
                                        ],
                                      );
                                      if (result != null) {
                                        final bytes =
                                            await result.readAsBytes();
                                        set(() {
                                          imageBase64 = base64Encode(bytes);
                                        });
                                      }
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.photo_camera_outlined,
                                    size: 14,
                                  ),
                                  label: const Text(
                                    'Take photo',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                  ),
                                  onPressed: () async {
                                    try {
                                      final picker = ImagePicker();
                                      final picked = await picker.pickImage(
                                        source: ImageSource.gallery,
                                        maxWidth: 1024,
                                        maxHeight: 1024,
                                        imageQuality: 85,
                                      );
                                      if (picked != null) {
                                        final bytes =
                                            await picked.readAsBytes();
                                        set(() {
                                          imageBase64 = base64Encode(bytes);
                                        });
                                      }
                                    } catch (_) {
                                      final result = await FilePicker.pickFile(
                                        type: FileType.custom,
                                        allowedExtensions: [
                                          'png',
                                          'jpg',
                                          'jpeg',
                                          'webp',
                                        ],
                                      );
                                      if (result != null) {
                                        final bytes =
                                            await result.readAsBytes();
                                        set(() {
                                          imageBase64 = base64Encode(bytes);
                                        });
                                      }
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.folder_open_outlined,
                                    size: 14,
                                  ),
                                  label: const Text(
                                    'Upload file',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                if (imageBase64 != null &&
                                    imageBase64!.trim().isNotEmpty)
                                  IconButton(
                                    tooltip: 'Remove image',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Color(0xFFC74343),
                                    ),
                                    onPressed: () =>
                                        set(() => imageBase64 = null),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                field('Product code (optional)', controllers['code']!),
                UnitSelector(
                  controller: controllers['unit']!,
                  extraUnits: [
                    for (final prod in store.products)
                      if (prod['unit'] != null) '${prod['unit']}',
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: canvas,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: lineColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.category_outlined,
                            size: 15,
                            color: accent,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Category',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          if (selectedDropdownCat != null)
                            Pill(
                              'Selected: $selectedDropdownCat',
                              color: green,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Select category',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedDropdownCat,
                                  isExpanded: true,
                                  hint: const Text(
                                    'Choose…',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  items: [
                                    for (final c in existingCats)
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
                                      set(() {
                                        selectedDropdownCat = v;
                                        controllers['category']!.text = v;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: controllers['category'],
                              decoration: const InputDecoration(
                                labelText: 'Or enter name',
                                hintText: 'e.g. Cement, Paints…',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                              onChanged: (v) {
                                final match = existingCats.firstWhere(
                                  (c) =>
                                      c.toLowerCase() ==
                                      v.trim().toLowerCase(),
                                  orElse: () => '',
                                );
                                set(() {
                                  selectedDropdownCat =
                                      match.isNotEmpty ? match : null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      if (existingCats.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final c in existingCats.take(7))
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    controllers['category']!
                                            .text
                                            .trim()
                                            .toLowerCase() ==
                                        c.toLowerCase()
                                        ? accent.withValues(alpha: 0.15)
                                        : Colors.white,
                                side: BorderSide(
                                  color:
                                      controllers['category']!
                                              .text
                                              .trim()
                                              .toLowerCase() ==
                                          c.toLowerCase()
                                          ? accent
                                          : lineColor,
                                ),
                                label: Text(
                                  c,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight:
                                        controllers['category']!
                                                .text
                                                .trim()
                                                .toLowerCase() ==
                                            c.toLowerCase()
                                            ? FontWeight.w700
                                            : FontWeight.normal,
                                    color:
                                        controllers['category']!
                                                .text
                                                .trim()
                                                .toLowerCase() ==
                                            c.toLowerCase()
                                            ? accent
                                            : ink,
                                  ),
                                ),
                                onPressed: () {
                                  set(() {
                                    selectedDropdownCat = c;
                                    controllers['category']!.text = c;
                                  });
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: field(
                        'Selling price (₹)',
                        controllers['price']!,
                        numeric: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: field(
                        'GST rate (%)',
                        controllers['gst']!,
                        numeric: true,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: field('HSN code', controllers['hsn']!)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: field(
                        'Low-stock threshold',
                        controllers['lowStock']!,
                        numeric: true,
                      ),
                    ),
                  ],
                ),
                if (product == null) ...[
                  field(
                    'Opening stock',
                    controllers['openingStock']!,
                    numeric: true,
                  ),
                ],
                const Text(
                  'Supports packaged and loose items (kg, m, ltr, ton, etc.) with up to 3 decimal places.',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    set(() => saving = true);
                    try {
                      final rawCat = controllers['category']!.text.trim();
                      if (rawCat.isEmpty) {
                        throw ArgumentError('Category name is required.');
                      }
                      final data = <String, dynamic>{
                        ...p,
                        for (final key in controllers.keys)
                          if (key != 'openingStock')
                            key: controllers[key]!.text.trim(),
                        'category': store.normalizeCategory(rawCat),
                        'image': (imageBase64 != null &&
                                imageBase64!.trim().isNotEmpty)
                            ? imageBase64
                            : null,
                      };
                      for (final key in ['price', 'gst', 'lowStock']) {
                        data[key] = double.parse(controllers[key]!.text);
                      }
                      if (data['unit'] == '') {
                        throw ArgumentError('Unit is required.');
                      }
                      await store.saveProduct(
                        data,
                        openingStock: double.parse(
                          controllers['openingStock']!.text,
                        ),
                      );
                      if (dialog.mounted) Navigator.pop(dialog);
                    } catch (e) {
                      if (dialog.mounted) {
                        toast(dialog, '$e', error: true);
                        set(() => saving = false);
                      }
                    }
                  },
            child: Text(saving ? 'Saving…' : 'Save product'),
          ),
        ],
      ),
    ),
  );
}

Future<void> adjustProductStock(
  BuildContext context,
  AppStore store,
  Json p,
) => receiveStockDialog(context, store, product: p);

Future<void> receiveStockDialog(
  BuildContext context,
  AppStore store, {
  Json? product,
}) async {
  final activeProducts = store.products
      .where((p) => p['archived'] != true)
      .toList();
  if (activeProducts.isEmpty) {
    toast(context, 'Add a product first before receiving stock.', error: true);
    return;
  }

  String selectedId =
      product?['id'] as String? ?? activeProducts.first['id'] as String;
  final amountController = TextEditingController();
  final reasonController = TextEditingController(
    text: 'Stock received / Purchase',
  );
  bool isAdding = true;

  await showDialog(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, set) {
        final currentProd = store.products.firstWhere(
          (p) => p['id'] == selectedId,
          orElse: () => activeProducts.first,
        );
        final currentStock = store.stockFor(selectedId);
        final entered = double.tryParse(amountController.text) ?? 0;
        final finalStock = isAdding
            ? (currentStock + entered)
            : (currentStock - entered);

        return AlertDialog(
          title: Row(
            children: [
              const Icon(
                Icons.add_shopping_cart_rounded,
                size: 21,
                color: green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  product != null
                      ? 'Add stock · ${currentProd['name']}'
                      : 'Add / Receive stock',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product == null) ...[
                    DropdownButtonFormField<String>(
                      initialValue: selectedId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Select product to receive stock for',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      items: [
                        for (final p in activeProducts)
                          DropdownMenuItem(
                            value: p['id'] as String,
                            child: Text(
                              '${p['name']} (Stock: ${quantity(store.stockFor(p['id']))} ${p['unit']})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          set(() => selectedId = v);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: canvas,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: lineColor),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Current on-hand stock:',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                            Text(
                              '${quantity(currentStock)} ${currentProd['unit']}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (entered > 0) ...[
                          const Divider(height: 14, color: lineColor),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isAdding
                                    ? 'New stock after addition:'
                                    : 'New stock after reduction:',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                              Text(
                                '${quantity(finalStock)} ${currentProd['unit']}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: finalStock < 0
                                      ? const Color(0xFFC74343)
                                      : green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: true,
                              icon: Icon(Icons.add, size: 16),
                              label: Text('Receive / Add (+)', style: TextStyle(fontSize: 12)),
                            ),
                            ButtonSegment(
                              value: false,
                              icon: Icon(Icons.remove, size: 16),
                              label: Text('Reduce / Damage (−)', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                          selected: {isAdding},
                          onSelectionChanged: (s) => set(() {
                            isAdding = s.first;
                            if (isAdding &&
                                reasonController.text ==
                                    'Damaged / Wastage') {
                              reasonController.text =
                                  'Stock received / Purchase';
                            } else if (!isAdding &&
                                reasonController.text ==
                                    'Stock received / Purchase') {
                              reasonController.text = 'Damaged / Wastage';
                            }
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  field(
                    isAdding ? 'Quantity to add (+)' : 'Quantity to remove (−)',
                    amountController,
                    numeric: true,
                    onChanged: (_) => set(() {}),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final q in [5, 10, 25, 50, 100])
                        ActionChip(
                          label: Text('+$q'),
                          onPressed: () => set(
                            () => amountController.text = '$q',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  field('Reason or Supplier reference', reasonController),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final r in isAdding
                          ? [
                              'Stock received / Purchase',
                              'Supplier delivery',
                              'Customer return',
                              'Count adjustment',
                            ]
                          : [
                              'Damaged / Wastage',
                              'Internal use',
                              'Returned to vendor',
                              'Count correction',
                            ])
                        ActionChip(
                          label: Text(r, style: const TextStyle(fontSize: 10)),
                          onPressed: () =>
                              set(() => reasonController.text = r),
                        ),
                    ],
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
              onPressed: () async {
                try {
                  final qty = double.parse(amountController.text);
                  if (!qty.isFinite || qty <= 0) {
                    throw ArgumentError('Enter a positive quantity.');
                  }
                  final delta = isAdding ? qty : -qty;
                  await store.adjustStock(
                    selectedId,
                    delta,
                    reasonController.text.trim().isEmpty
                        ? (isAdding ? 'Stock inward' : 'Stock reduction')
                        : reasonController.text.trim(),
                  );
                  if (dialog.mounted) Navigator.pop(dialog);
                  if (context.mounted) {
                    toast(
                      context,
                      '${isAdding ? 'Added' : 'Removed'} ${quantity(qty)} ${currentProd['unit']} for ${currentProd['name']}. (New stock: ${quantity(finalStock)} ${currentProd['unit']})',
                    );
                  }
                } catch (e) {
                  if (dialog.mounted) {
                    toast(dialog, '$e', error: true);
                  }
                }
              },
              child: Text(isAdding ? 'Add stock' : 'Reduce stock'),
            ),
          ],
        );
      },
    ),
  );
}
