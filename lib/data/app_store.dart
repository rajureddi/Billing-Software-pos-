import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/billing.dart';
import 'app_config.dart';

class _Database extends GeneratedDatabase {
  _Database(super.executor);
  @override
  int get schemaVersion => 3;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE records (id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL, revision INTEGER NOT NULL, dirty INTEGER NOT NULL DEFAULT 1, base_revision INTEGER NOT NULL DEFAULT 0, group_id TEXT)',
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 3)
        await customStatement('ALTER TABLE records ADD COLUMN group_id TEXT');
      if (from < 2) {
        await customStatement(
          'ALTER TABLE records ADD COLUMN base_revision INTEGER NOT NULL DEFAULT 0',
        );
      }
    },
  );
}

class AppStore extends ChangeNotifier {
  AppStore._(this._db);
  _Database _db;
  static const _uuid = Uuid();
  List<Map<String, dynamic>> _records = [];
  final Map<String, Map<String, dynamic>> _byId = {};
  final Map<String, List<Map<String, dynamic>>> _byKind = {};
  Map<String, Map<String, dynamic>>? _invoiceIndex;
  Future<void> _writeQueue = Future.value();
  String? _groupId;
  final ChangeNotifier syncChanges = ChangeNotifier();
  final ChangeNotifier syncStatus = ChangeNotifier();
  static dynamic _copy(dynamic value) {
    if (value is Map)
      return value.map((k, v) => MapEntry(k.toString(), _copy(v)));
    if (value is List) return value.map(_copy).toList();
    return value;
  }

  List<Map<String, dynamic>> _raw(String kind) => _byKind[kind] ?? const [];
  void _index() {
    _byId.clear();
    _byKind.clear();
    _invoiceIndex = null;
    for (final r in _records) {
      _byId[r['id']] = r;
      _byKind.putIfAbsent(r['kind'], () => []).add(r['payload']);
    }
  }

  Future<void> _exclusive(Future<void> Function() action) {
    final operation = _writeQueue.then((_) => action());
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  Map<String, double>? _cachedStockMap;
  Map<String, double>? _cachedPaidMap;
  List<Map<String, dynamic>>? _cachedCustomerBalances;
  List<Map<String, dynamic>>? _cachedMovementsWithProducts;
  List<String>? _cachedCategories;
  String get deviceId =>
      (_kind('local').firstWhere(
                (r) => r['id'] == 'device',
                orElse: () => {},
              )['value'] ??
              '')
          as String;
  List<Map<String, dynamic>> _kind(String kind) =>
      _raw(kind).map((p) => Map<String, dynamic>.from(_copy(p))).toList();
  List<Map<String, dynamic>> get products => _kind('product');
  Map<String, Map<String, dynamic>> get _invoicesById {
    if (_invoiceIndex != null) return _invoiceIndex!;
    final cancellations = {
      for (final c in _raw('cancellation'))
        if (c['deleted'] != true) c['invoiceId']: c,
    };
    return _invoiceIndex = {
      for (final invoice in _raw('invoice'))
        if (invoice['deleted'] != true)
          invoice['id']: {
            ...invoice,
            if (cancellations[invoice['id']] case final c?) ...{
              'cancelled': true,
              'cancellationReason': c['reason'],
              'cancelledAt': c['createdAt'],
            },
          },
    };
  }

  List<Map<String, dynamic>> get invoices => _invoicesById.values
      .map((p) => Map<String, dynamic>.from(_copy(p)))
      .toList();
  List<Map<String, dynamic>> get payments =>
      _kind('payment').where((p) => p['deleted'] != true).toList();
  List<Map<String, dynamic>> get movements =>
      _kind('movement').where((m) => m['deleted'] != true).toList();
  List<Map<String, dynamic>> get customers =>
      _kind('customer').where((c) => c['deleted'] != true).toList();
  List<Map<String, dynamic>> get conflicts => _kind('conflict');
  Map<String, dynamic> get settings => {
    ...defaultSettings,
    ...(_kind('settings').firstOrNull ?? {}),
    ...(_raw('local').where((r) => r['id'] == 'cloud-config').firstOrNull ??
        {}),
  };
  Map<String, dynamic> get draft => _kind('draft').firstOrNull ?? {};
  int get pendingCount => _records
      .where(
        (r) =>
            r['dirty'] == 1 &&
            !['local', 'draft', 'conflict'].contains(r['kind']),
      )
      .length;
  static Map<String, dynamic> get defaultSettings => {
    'name': 'My Store',
    'owner': '',
    'tagline': 'Retail & Billing',
    'category': 'General Retail',
    'address': '',
    'phone': '',
    'email': '',
    'gstin': '',
    'state': '',
    'footer': '1. Goods once sold are covered by standard store policy. 2. Subject to local jurisdiction.',
    'upi': '',
    'bank': '',
    'gstEnabled': false,
    'taxInclusive': false,
    'paper': 'A4',
    'supabaseUrl': AppConfig.supabaseUrl,
    'supabaseAnonKey': AppConfig.supabaseAnonKey,
  };
  static Future<AppStore> open({String? shopId}) async {
    final cleanId = shopId?.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_') ?? '';
    final dbName = cleanId.isNotEmpty ? 'counterday_$cleanId' : 'counterday_guest';
    return openForTesting(
      driftDatabase(
        name: dbName,
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      ),
    );
  }
  static Future<AppStore> openForTesting(QueryExecutor executor) async {
    final store = AppStore._(_Database(executor));
    await store._reload();
    if (store.deviceId.isEmpty) {
      await store._commit(
        () => store._put('local', {
          'id': 'device',
          'value': _uuid.v4(),
        }, dirty: false),
      );
    }
    return store;
  }

  Future<void> close() async {
    await _writeQueue;
    syncChanges.dispose();
    syncStatus.dispose();
    await _db.close();
  }

  /// Clears all local records from SQLite so a new shop starts with zero old data
  Future<void> clearAllData() async {
    await _writeQueue;
    await _db.customStatement('DELETE FROM records');
    _records = [];
    _index();
    await _reload();
    syncChanges.notifyListeners();
    notifyListeners();
  }

  /// Switches the local offline SQLite database to be completely scoped to the logged-in shop/user
  Future<void> switchShop(String shopId) async {
    await _writeQueue;
    await _db.close();
    final cleanId = shopId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final dbName = cleanId.isNotEmpty ? 'counterday_$cleanId' : 'counterday_guest';
    final newExecutor = driftDatabase(
      name: dbName,
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
    _db = _Database(newExecutor);
    _records = [];
    _index();
    await _reload();
    if (deviceId.isEmpty) {
      await _commit(
        () => _put('local', {
          'id': 'device',
          'value': _uuid.v4(),
        }, dirty: false),
      );
    }
    syncChanges.notifyListeners();
    notifyListeners();
  }

  Future<void> _reload() async {
    _cachedStockMap = null;
    _cachedPaidMap = null;
    _cachedCustomerBalances = null;
    _cachedMovementsWithProducts = null;
    _cachedCategories = null;
    final rows = await _db.customSelect('SELECT * FROM records').get();
    _records = rows
        .map(
          (r) => {
            'id': r.read<String>('id'),
            'kind': r.read<String>('kind'),
            'payload': jsonDecode(r.read<String>('payload')),
            'revision': r.read<int>('revision'),
            'dirty': r.read<int>('dirty'),
            'baseRevision': r.read<int>('base_revision'),
            'groupId': r.readNullable<String>('group_id'),
          },
        )
        .toList();
    _index();
  }

  Future<void> _put(
    String kind,
    Map<String, dynamic> payload, {
    bool dirty = true,
    int? revision,
  }) async {
    final id = payload['id'] as String;
    final existing = await _db
        .customSelect(
          'SELECT revision FROM records WHERE id = ?',
          variables: [Variable<String>(id)],
        )
        .getSingleOrNull();
    final next = revision ?? ((existing?.read<int>('revision') ?? 0) + 1);
    await _db.customStatement(
      'INSERT INTO records (id,kind,payload,revision,dirty,group_id) VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,payload=excluded.payload,revision=excluded.revision,dirty=excluded.dirty,group_id=excluded.group_id',
      [
        id,
        kind,
        jsonEncode(payload),
        next,
        dirty ? 1 : 0,
        dirty ? _groupId : null,
      ],
    );
  }

  Future<void> _commit(
    Future<void> Function() action, {
    bool notify = true,
    bool localEdit = true,
  }) => _exclusive(() async {
    final changed = <String>{};

    // A temporary change journal also covers explicit updates and tombstones.
    await _db.customStatement(
      'CREATE TEMP TABLE IF NOT EXISTS changed_records (id TEXT PRIMARY KEY)',
    );
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      final row = event == 'DELETE' ? 'OLD' : 'NEW';
      await _db.customStatement(
        'CREATE TEMP TRIGGER IF NOT EXISTS audit_${event.toLowerCase()} AFTER $event ON records BEGIN INSERT OR IGNORE INTO changed_records VALUES ($row.id); END',
      );
    }
    await _db.customStatement('DELETE FROM changed_records');
    _groupId = const Uuid().v4();
    try {
      await _db.transaction(action);
    } finally {
      _groupId = null;
    }
    final ids = await _db.customSelect('SELECT id FROM changed_records').get();
    for (final id in ids) {
      changed.add(id.read<String>('id'));
    }
    if (changed.isEmpty) return;
    for (final id in changed) {
      final row = await _db
          .customSelect(
            'SELECT * FROM records WHERE id=?',
            variables: [Variable<String>(id)],
          )
          .getSingleOrNull();
      if (row == null) {
        _byId.remove(id);
        continue;
      }
      _byId[id] = {
        'id': id,
        'kind': row.read<String>('kind'),
        'payload': jsonDecode(row.read<String>('payload')),
        'revision': row.read<int>('revision'),
        'dirty': row.read<int>('dirty'),
        'baseRevision': row.read<int>('base_revision'),
        'groupId': row.readNullable<String>('group_id'),
      };
    }
    _records = _byId.values.toList();
    _index();
    if (notify) {
      _cachedStockMap = null;
      _cachedPaidMap = null;
      _cachedCustomerBalances = null;
      _cachedMovementsWithProducts = null;
      _cachedCategories = null;
      notifyListeners();
    }
    syncStatus.notifyListeners();
    if (localEdit && pendingCount > 0) syncChanges.notifyListeners();
  });

  String? get boundOwner =>
      _kind('local')
              .where((r) => r['id'] == 'cloud-owner')
              .firstOrNull?['value']
          as String?;
  Future<void> bindOwner(String owner) async {
    if (boundOwner != null && boundOwner != owner) {
      throw StateError('This device belongs to a different owner account.');
    }
    if (boundOwner == null) {
      await _commit(
        () =>
            _put('local', {'id': 'cloud-owner', 'value': owner}, dirty: false),
      );
    }
  }

  Map<String, double> get allStockMap {
    if (_cachedStockMap != null) return _cachedStockMap!;
    final map = <String, int>{};
    for (final m in movements) {
      final pid = m['productId'] as String?;
      if (pid != null) {
        map[pid] = (map[pid] ?? 0) + ((m['quantity'] as num) * 1000).round();
      }
    }
    return _cachedStockMap = map.map((k, v) => MapEntry(k, v / 1000));
  }

  double stockFor(String productId) => allStockMap[productId] ?? 0.0;

  Map<String, double> get allPaidMap {
    if (_cachedPaidMap != null) return _cachedPaidMap!;
    final map = <String, int>{};
    for (final p in payments) {
      final invId = p['invoiceId'] as String?;
      if (invId != null) {
        map[invId] = (map[invId] ?? 0) + paise(p['amount'] as num);
      }
    }
    return _cachedPaidMap = map.map((k, v) => MapEntry(k, v / 100));
  }

  double paidFor(String invoiceId) => allPaidMap[invoiceId] ?? 0.0;
  double dueFor(String invoiceId) {
    final invoice = _invoicesById[invoiceId];
    if (invoice == null) throw ArgumentError('Invoice not found.');
    if (invoice['cancelled'] == true) return 0;
    return (paise(invoice['total'] as num) - paise(paidFor(invoiceId))) / 100;
  }

  List<Map<String, dynamic>> movementsFor(String productId) =>
      movements.where((m) => m['productId'] == productId).toList()
        ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));

  List<Map<String, dynamic>> get allMovementsWithProducts {
    if (_cachedMovementsWithProducts != null)
      return _cachedMovementsWithProducts!;
    final prodMap = {for (final p in products) p['id']: p};
    return _cachedMovementsWithProducts =
        movements.map((m) {
            final p = prodMap[m['productId']];
            return {
              ...m,
              'productName': p?['name'] ?? 'Custom / Deleted item',
              'productUnit': p?['unit'] ?? 'pcs',
              'productCode': p?['code'] ?? '',
            };
          }).toList()
          ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
  }

  List<Map<String, dynamic>> get customerBalances {
    if (_cachedCustomerBalances != null) return _cachedCustomerBalances!;
    final Map<String, Map<String, dynamic>> map = {};
    for (final customer in customers) {
      final id = customer['id'] as String;
      map[id] = {
        'id': id,
        'name': customer['name'] ?? 'Unnamed customer',
        'phone': customer['phone'] ?? '',
        'address': customer['address'] ?? '',
        'gstin': customer['gstin'] ?? '',
        'totalInvoiced': 0.0,
        'totalPaid': 0.0,
        'due': 0.0,
        'invoiceCount': 0,
        'lastInvoiceAt': null,
      };
    }
    for (final inv in invoices) {
      if (inv['cancelled'] == true) continue;
      final cust = inv['customer'] as Map?;
      if (cust == null) continue;
      final custId = cust['id'] as String?;
      final custName = (cust['name'] ?? '').toString().trim();
      if (custName.isEmpty) continue;
      final key = custId ?? custName;
      if (!map.containsKey(key)) {
        map[key] = {
          'id': key,
          'name': custName,
          'phone': cust['phone'] ?? '',
          'address': cust['address'] ?? '',
          'gstin': cust['gstin'] ?? '',
          'totalInvoiced': 0.0,
          'totalPaid': 0.0,
          'due': 0.0,
          'invoiceCount': 0,
          'lastInvoiceAt': null,
        };
      }
      final invTotal = (inv['total'] as num?)?.toDouble() ?? 0.0;
      final invPaid = paidFor(inv['id']);
      final invDue = dueFor(inv['id']);
      final entry = map[key]!;
      entry['totalInvoiced'] = (entry['totalInvoiced'] as double) + invTotal;
      entry['totalPaid'] = (entry['totalPaid'] as double) + invPaid;
      entry['due'] = (entry['due'] as double) + invDue;
      entry['invoiceCount'] = (entry['invoiceCount'] as int) + 1;
      final invDate = inv['createdAt'] as String?;
      if (invDate != null) {
        if (entry['lastInvoiceAt'] == null ||
            invDate.compareTo(entry['lastInvoiceAt'] as String) > 0) {
          entry['lastInvoiceAt'] = invDate;
        }
      }
    }
    return _cachedCustomerBalances = map.values.toList()
      ..sort((a, b) => (b['due'] as double).compareTo(a['due'] as double));
  }

  List<String> get categories {
    if (_cachedCategories != null) return _cachedCategories!;
    final map = <String, String>{};
    for (final p in products) {
      if (p['archived'] == true) continue;
      final cat = (p['category'] ?? '').toString().trim();
      if (cat.isEmpty) continue;
      final lower = cat.toLowerCase();
      if (!map.containsKey(lower) ||
          (cat[0].toUpperCase() == cat[0] &&
              map[lower]![0].toLowerCase() == map[lower]![0])) {
        map[lower] = cat;
      }
    }
    const defaults = [
      'Cement',
      'Plumbing',
      'Steel & Iron',
      'Fasteners',
      'Paints & Chemicals',
      'Electrical',
      'Tools & Hardware',
      'General',
    ];
    for (final d in defaults) {
      final lower = d.toLowerCase();
      if (!map.containsKey(lower)) {
        map[lower] = d;
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return _cachedCategories = list;
  }

  String normalizeCategory(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'General';
    for (final c in categories) {
      if (c.toLowerCase() == trimmed.toLowerCase()) {
        return c;
      }
    }
    return trimmed
        .split(RegExp(r'\s+'))
        .map(
          (w) => w.isEmpty
              ? ''
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Future<void> saveSettings(Map<String, dynamic> value) => _commit(() async {
    final merged = {...settings, ...value};
    final connection = <String, dynamic>{'id': 'cloud-config'};
    for (final key in ['supabaseUrl', 'supabaseAnonKey', 'supabaseShopToken']) {
      if (merged.containsKey(key)) connection[key] = merged.remove(key);
    }
    if (connection.length > 1) await _put('local', connection, dirty: false);
    await _put('settings', {...merged, 'id': 'shop-settings'});
  });
  Map<String, dynamic> get invoiceShop =>
      {...settings}..removeWhere((k, v) => k.startsWith('supabase'));
  Future<void> saveProduct(
    Map<String, dynamic> product, {
    num openingStock = 0,
  }) async {
    if ((product['name'] ?? '').toString().trim().isEmpty ||
        (product['price'] as num? ?? -1) < 0) {
      throw ArgumentError('Enter a product name and valid price.');
    }
    if (!openingStock.isFinite) throw ArgumentError('Invalid opening stock.');
    final id = (product['id'] as String?) ?? _uuid.v4();
    final exists = products.any((p) => p['id'] == id);
    final rawCat = (product['category'] ?? '').toString().trim();
    final cleanCat = normalizeCategory(rawCat);
    await _commit(() async {
      await _put('product', {
        'code': '',
        'unit': 'pcs',
        'gst': 0,
        'hsn': '',
        'lowStock': 5,
        'archived': false,
        ...product,
        'category': cleanCat,
        'id': id,
      });
      if (!exists && openingStock != 0) {
        await _movement(id, openingStock, 'Opening stock');
      }
    });
  }

  Future<void> _movement(
    String id,
    num quantity,
    String reason, {
    String? invoiceId,
  }) => _put('movement', {
    'id': _uuid.v4(),
    'productId': id,
    'quantity': quantity,
    'reason': reason,
    'invoiceId': invoiceId,
    'createdAt': DateTime.now().toIso8601String(),
  });
  Future<void> adjustStock(
    String productId,
    num quantity,
    String reason,
  ) async {
    if (!quantity.isFinite ||
        quantity == 0 ||
        reason.trim().isEmpty ||
        !products.any((p) => p['id'] == productId)) {
      throw ArgumentError('Enter a valid stock adjustment and reason.');
    }
    await _commit(() => _movement(productId, quantity, reason));
  }

  Future<void> saveDraft(Map<String, dynamic> value) => _commit(
    () => _put('draft', {...value, 'id': 'cart-draft'}, dirty: false),
    notify: false,
    localEdit: false,
  );
  Future<Map<String, dynamic>> finalizeInvoice({
    required List<Map<String, dynamic>> lines,
    required Map<String, dynamic> customer,
    required Map<String, dynamic> discount,
    required List<Map<String, dynamic>> paymentEntries,
    required bool gstEnabled,
    required bool taxInclusive,
    required bool interstate,
  }) async {
    if (lines.isEmpty) throw ArgumentError('Add an item to the bill.');
    final bill = calculateBill(
      lines: lines,
      discount: discount,
      gstEnabled: gstEnabled,
      taxInclusive: taxInclusive,
      interstate: interstate,
    );
    var paid = 0;
    for (final p in paymentEntries) {
      final amount = p['amount'] as num;
      if (amount < 0 || !amount.isFinite) {
        throw ArgumentError('Invalid payment.');
      }
      paid += paise(amount);
    }
    if (paid > paise(bill['total'] as num)) {
      throw ArgumentError('Payment exceeds invoice total.');
    }
    if (paid < paise(bill['total'] as num) &&
        (customer['name'] ?? '').toString().trim().isEmpty) {
      throw ArgumentError('A customer name is required for credit.');
    }
    final now = DateTime.now();
    final fy = now.month >= 4 ? now.year : now.year - 1;
    final id = _uuid.v4();
    Map<String, dynamic> invoice = {};
    await _commit(() async {
      final counterId = 'counter-$fy';
      final row = await _db
          .customSelect(
            'SELECT payload FROM records WHERE id=?',
            variables: [Variable<String>(counterId)],
          )
          .getSingleOrNull();
      final counter = row == null
          ? 1
          : (jsonDecode(row.read<String>('payload'))['value'] as int) + 1;
      await _put('local', {'id': counterId, 'value': counter}, dirty: false);
      final savedCustomer = {...customer};
      if ((customer['name'] ?? '').toString().trim().isNotEmpty) {
        savedCustomer['id'] ??= _uuid.v4();
        await _put('customer', savedCustomer);
      }
      invoice = {
        ...bill,
        'id': id,
        'number':
            '${fy.toString().substring(2)}-${deviceId.replaceAll('-', '').substring(0, 8).toUpperCase()}-${counter.toString().padLeft(5, '0')}',
        'createdAt': now.toIso8601String(),
        'customer': savedCustomer,
        'shop': invoiceShop,
        'discount': discount,
        'gstEnabled': gstEnabled,
        'taxInclusive': taxInclusive,
        'interstate': interstate,
        'cancelled': false,
      };
      await _put('invoice', invoice);
      for (final line in lines) {
        if (line['productId'] != null) {
          await _movement(
            line['productId'] as String,
            -(line['quantity'] as num),
            'Sale',
            invoiceId: id,
          );
        }
      }
      for (final p in paymentEntries) {
        if ((p['amount'] as num) > 0) {
          await _put('payment', {
            'id': _uuid.v4(),
            ...p,
            'invoiceId': id,
            'createdAt': now.toIso8601String(),
          });
        }
      }
      await _put('draft', {'id': 'cart-draft'}, dirty: false);
    });
    return invoice;
  }

  Future<Map<String, dynamic>> updateInvoiceLines(
    String invoiceId,
    List<Map<String, dynamic>> lines, {
    Map<String, dynamic>? discount,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('Invoice must contain at least one item.');
    }
    final invoice = invoices.firstWhere(
      (i) => i['id'] == invoiceId,
      orElse: () => throw ArgumentError('Invoice not found.'),
    );
    if (invoice['cancelled'] == true) {
      throw ArgumentError('Cancelled invoices cannot be edited.');
    }

    final discountToUse =
        discount ??
        (invoice['discount'] as Map?)?.cast<String, dynamic>() ??
        {'type': 'amount', 'value': 0};

    final bill = calculateBill(
      lines: lines,
      discount: discountToUse,
      gstEnabled: invoice['gstEnabled'] == true,
      taxInclusive: invoice['taxInclusive'] == true,
      interstate: invoice['interstate'] == true,
    );

    Map<String, dynamic> updated = {};
    await _commit(() async {
      final oldMovements = movements
          .where((m) => m['invoiceId'] == invoiceId)
          .toList();
      for (final m in oldMovements) {
        await _put('movement', {
          ...m,
          'deleted': true,
          'deletedAt': DateTime.now().toIso8601String(),
        });
      }

      for (final line in lines) {
        if (line['productId'] != null) {
          await _movement(
            line['productId'] as String,
            -(line['quantity'] as num),
            'Sale (Updated bill)',
            invoiceId: invoiceId,
          );
        }
      }

      updated = {
        ...invoice,
        ...bill,
        'discount': discountToUse,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await _put('invoice', updated);
    });

    return updated;
  }

  Future<void> recordPayment(
    String invoiceId,
    num amount,
    String method,
  ) async {
    if (!amount.isFinite ||
        amount <= 0 ||
        paise(amount) > paise(dueFor(invoiceId))) {
      throw ArgumentError(
        'Payment must be positive and no more than the balance.',
      );
    }
    await _commit(
      () => _put('payment', {
        'id': _uuid.v4(),
        'invoiceId': invoiceId,
        'amount': paise(amount) / 100,
        'method': method,
        'createdAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<void> cancelInvoice(String invoiceId, String reason) async {
    final invoice = _invoicesById[invoiceId];
    if (invoice == null) throw ArgumentError('Invoice not found.');
    if (invoice['cancelled'] == true || reason.trim().isEmpty) {
      throw ArgumentError(
        'Enter a reason; cancelled invoices cannot be cancelled again.',
      );
    }
    await _commit(() async {
      await _put('cancellation', {
        'id': 'cancel-$invoiceId',
        'invoiceId': invoiceId,
        'reason': reason,
        'createdAt': DateTime.now().toIso8601String(),
      });
      for (final line in invoice['lines'] as List) {
        if (line['productId'] != null) {
          await _movement(
            line['productId'] as String,
            line['quantity'] as num,
            'Cancellation: $reason',
            invoiceId: invoiceId,
          );
        }
      }
      final paid = paidFor(invoiceId);
      if (paid > 0) {
        await _put('payment', {
          'id': _uuid.v4(),
          'invoiceId': invoiceId,
          'amount': -paid,
          'method': 'Refund',
          'reason': reason,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  Future<void> deleteInvoice(String invoiceId) async {
    final invoice = invoices.firstWhere(
      (i) => i['id'] == invoiceId,
      orElse: () => throw ArgumentError('Invoice not found.'),
    );
    await _commit(() async {
      final nowStr = DateTime.now().toIso8601String();
      final relatedMovements = movements
          .where((m) => m['invoiceId'] == invoiceId)
          .toList();
      final relatedPayments = payments
          .where((p) => p['invoiceId'] == invoiceId)
          .toList();

      if (relatedMovements.isEmpty && invoice['cancelled'] != true) {
        final lines = (invoice['lines'] as List?) ?? [];
        for (final line in lines) {
          if (line is Map && line['productId'] != null) {
            await _movement(
              line['productId'] as String,
              line['quantity'] as num,
              'Stock restored: deleted invoice ${invoice['number']}',
              invoiceId: invoiceId,
            );
          }
        }
      }

      // Mark all related movements as deleted so stock is restored and sync deletes them
      for (final m in relatedMovements) {
        await _put('movement', {
          ...m,
          'deleted': true,
          'deletedAt': nowStr,
        }, dirty: true);
      }

      // Mark all related payments as deleted so dues/balances update and sync deletes them
      for (final p in relatedPayments) {
        await _put('payment', {
          ...p,
          'deleted': true,
          'deletedAt': nowStr,
        }, dirty: true);
      }

      // Mark cancellation if present as deleted
      final cancelRecord = _kind('cancellation').firstWhere(
        (c) => c['id'] == 'cancel-$invoiceId' || c['invoiceId'] == invoiceId,
        orElse: () => {},
      );
      if (cancelRecord.isNotEmpty) {
        await _put('cancellation', {
          ...cancelRecord,
          'deleted': true,
          'deletedAt': nowStr,
        }, dirty: true);
      }

      // Mark invoice itself as deleted
      await _put('invoice', {
        ...invoice,
        'deleted': true,
        'deletedAt': nowStr,
      }, dirty: true);
    });
  }

  Future<void> markAllForSync() async {
    await _commit(() async {
      await _db.customStatement(
        "UPDATE records SET dirty = 1 WHERE kind NOT IN ('local', 'draft', 'conflict')",
      );
    });
  }

  bool get isInitialSyncDone =>
      _kind('local').any((r) => r['id'] == 'cloud-initial-sync-done');

  Future<void> markInitialSyncDone() => _commit(
    () => _put('local', {
      'id': 'cloud-initial-sync-done',
      'value': true,
    }, dirty: false),
    notify: false,
    localEdit: false,
  );
  int get syncCursor =>
      (_byId['cloud-sync-cursor']?['payload']['value'] as num?)?.toInt() ?? 0;
  Future<void> setSyncCursor(int cursor) => _commit(
    () async {
      if (cursor > syncCursor)
        await _put('local', {
          'id': 'cloud-sync-cursor',
          'value': cursor,
        }, dirty: false);
    },
    notify: false,
    localEdit: false,
  );
  Future<void> resetSyncCursor() => _commit(
    () => _db.customStatement(
      "DELETE FROM records WHERE id IN ('cloud-sync-cursor','cloud-initial-sync-done')",
    ),
    notify: false,
    localEdit: false,
  );

  List<Map<String, dynamic>> exportSyncRecords() {
    final blocked = conflicts.map((c) => c['recordId']).toSet();
    final blockedGroups = {
      for (final id in blocked)
        if (_byId[id]?['groupId'] != null) _byId[id]!['groupId'],
    };
    return _records
        .where(
          (r) =>
              r['dirty'] == 1 &&
              !['local', 'draft', 'conflict'].contains(r['kind']) &&
              !blocked.contains(r['id']) &&
              !blockedGroups.contains(r['groupId']),
        )
        .map(
          (r) => {
            'id': r['id'],
            'kind': r['kind'],
            'payload': _copy(r['payload']),
            'revision': r['revision'],
            'baseRevision': r['baseRevision'],
            'groupId': r['groupId'] ?? r['id'],
          },
        )
        .toList();
  }

  Future<void> acknowledgeSync(List records) => _commit(
    () async {
      for (final record in records.whereType<Map>()) {
        await _db.customStatement(
          'UPDATE records SET base_revision=MAX(base_revision,?), dirty=CASE WHEN revision=? THEN 0 ELSE dirty END WHERE id=? AND base_revision<=?',
          [
            record['serverRevision'] ?? record['revision'],
            record['revision'],
            record['id'],
            record['serverRevision'] ?? record['revision'],
          ],
        );
      }
    },
    notify: false,
    localEdit: false,
  );
  static bool _deepEquals(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a is num && b is num) return (a - b).abs() < 0.0001;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a.toString() == b.toString();
  }

  Future<void> applyRemoteRecords(List records) => _commit(() async {
    for (final raw in records) {
      final record = Map<String, dynamic>.from(raw as Map);
      if (![
        'product',
        'invoice',
        'payment',
        'movement',
        'customer',
        'settings',
        'cancellation',
      ].contains(record['kind']))
        continue;
      final payload = Map<String, dynamic>.from(record['payload'] as Map);
      final revision =
          (record['serverRevision'] ?? record['revision'] ?? 1) as int;
      if (payload['id'] != record['id'] || revision < 1)
        throw FormatException('Invalid sync record.');
      final local = await _db
          .customSelect(
            'SELECT * FROM records WHERE id=?',
            variables: [Variable<String>(record['id'])],
          )
          .getSingleOrNull();
      if (local != null) {
        final base = local.read<int>('base_revision');
        final current = Map<String, dynamic>.from(
          jsonDecode(local.read<String>('payload')),
        );
        if (revision < base || (revision == base && record['conflict'] != true))
          continue;
        if (_deepEquals(current, payload)) {
          if (revision > base)
            await _db.customStatement(
              'UPDATE records SET base_revision=? WHERE id=?',
              [revision, record['id']],
            );
          continue;
        }
        if (local.read<int>('dirty') == 1 ||
            (current['deleted'] == true && payload['deleted'] != true)) {
          final conflict = {
            'id': 'conflict-${record['id']}',
            'recordId': record['id'],
            'local': current,
            'remote': record,
          };
          final previous = _byId[conflict['id']]?['payload'];
          if (!_deepEquals(previous, conflict))
            await _put('conflict', conflict, dirty: false);
          continue;
        }
      }
      // Keep the client mutation counter monotonic: server revisions are separate.
      await _put(
        record['kind'],
        payload,
        dirty: false,
        revision: local?.read<int>('revision') ?? 1,
      );
      await _db.customStatement(
        'UPDATE records SET base_revision=? WHERE id=?',
        [revision, record['id']],
      );
    }
  }, localEdit: false);
  Future<void> resolveConflict(
    String conflictId, {
    required bool useRemote,
  }) async {
    final conflict = conflicts.firstWhere((c) => c['id'] == conflictId);
    final remote = Map<String, dynamic>.from(conflict['remote'] as Map);
    if (!['product', 'customer', 'settings'].contains(remote['kind'])) {
      throw StateError(
        'Financial record conflicts require review. Export a backup and contact support.',
      );
    }
    await _commit(() async {
      final payload = Map<String, dynamic>.from(
        (useRemote ? remote['payload'] : conflict['local']) as Map,
      );
      await _put(remote['kind'], payload, dirty: !useRemote);
      await _db.customStatement(
        'UPDATE records SET base_revision=? WHERE id=?',
        [remote['revision'], remote['id']],
      );
      await _db.customStatement('DELETE FROM records WHERE id=?', [conflictId]);
    });
  }

  Future<String> exportBackup() async => jsonEncode({
    'version': 1,
    'createdAt': DateTime.now().toIso8601String(),
    'records': _records,
  });
  Future<void> importBackup(String data) async {
    final decoded = jsonDecode(data);
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['records'] is! List) {
      throw FormatException('Unsupported backup.');
    }
    final rows = (decoded['records'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final r in rows) {
      if (r['id'] is! String ||
          r['kind'] is! String ||
          r['payload'] is! Map ||
          r['payload']['id'] != r['id']) {
        throw FormatException('Invalid backup record.');
      }
    }
    await _commit(() async {
      for (final r in rows) {
        if (['local', 'draft', 'conflict'].contains(r['kind'])) continue;
        final exists = await _db
            .customSelect(
              'SELECT id FROM records WHERE id=?',
              variables: [Variable<String>(r['id'] as String)],
            )
            .getSingleOrNull();
        if (exists == null) {
          await _put(
            r['kind'] as String,
            Map<String, dynamic>.from(r['payload'] as Map),
          );
        }
      }
    });
  }

  Future<void> seedCatalog() async {
    if (products.isNotEmpty) return;
    for (final p in [
      {
        'name': 'UltraTech Cement 50 kg',
        'category': 'Cement',
        'unit': 'bag',
        'price': 420,
        'code': 'CEM-001',
        'gst': 28,
      },
      {
        'name': 'TMT Steel Bar 12 mm',
        'category': 'Iron & Steel',
        'unit': 'kg',
        'price': 68,
        'code': 'STL-001',
        'gst': 18,
      },
      {
        'name': 'PVC Pipe 1 inch',
        'category': 'Plumbing',
        'unit': 'm',
        'price': 95,
        'code': 'PLM-001',
        'gst': 18,
      },
      {
        'name': 'Brass Ball Valve',
        'category': 'Plumbing',
        'unit': 'pcs',
        'price': 285,
        'code': 'PLM-002',
        'gst': 18,
      },
      {
        'name': 'Binding Wire',
        'category': 'Iron & Steel',
        'unit': 'kg',
        'price': 85,
        'code': 'STL-002',
        'gst': 18,
      },
      {
        'name': 'Wall Putty 20 kg',
        'category': 'Paint & Finish',
        'unit': 'bag',
        'price': 780,
        'code': 'PNT-001',
        'gst': 18,
      },
      {
        'name': 'Steel Nails',
        'category': 'Fasteners',
        'unit': 'kg',
        'price': 110,
        'code': 'FST-001',
        'gst': 18,
      },
      {
        'name': 'PTFE Thread Tape',
        'category': 'Plumbing',
        'unit': 'pcs',
        'price': 25,
        'code': 'PLM-003',
        'gst': 18,
      },
    ]) {
      await saveProduct(p, openingStock: 0);
    }
  }
}
