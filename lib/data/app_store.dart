import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/billing.dart';

class _Database extends GeneratedDatabase {
  _Database(super.executor);
  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE records (id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL, revision INTEGER NOT NULL, dirty INTEGER NOT NULL DEFAULT 1, base_revision INTEGER NOT NULL DEFAULT 0)',
      );
    },
    onUpgrade: (m, from, to) async {
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
  final _Database _db;
  static const _uuid = Uuid();
  List<Map<String, dynamic>> _records = [];
  String get deviceId =>
      (_kind('local').firstWhere(
                (r) => r['id'] == 'device',
                orElse: () => {},
              )['value'] ??
              '')
          as String;
  List<Map<String, dynamic>> _kind(String kind) => _records
      .where((r) => r['kind'] == kind)
      .map(
        (r) => Map<String, dynamic>.from(
          jsonDecode(jsonEncode(r['payload'])) as Map,
        ),
      )
      .toList();
  List<Map<String, dynamic>> get products => _kind('product');
  List<Map<String, dynamic>> get invoices => _kind('invoice').map((invoice) {
    final cancellation = _kind('cancellation')
        .where((c) => c['invoiceId'] == invoice['id'])
        .firstOrNull;
    return {
      ...invoice,
      if (cancellation != null) ...{
        'cancelled': true,
        'cancellationReason': cancellation['reason'],
        'cancelledAt': cancellation['createdAt'],
      },
    };
  }).toList();
  List<Map<String, dynamic>> get payments => _kind('payment');
  List<Map<String, dynamic>> get movements => _kind('movement');
  List<Map<String, dynamic>> get customers => _kind('customer');
  List<Map<String, dynamic>> get conflicts => _kind('conflict');
  Map<String, dynamic> get settings => {
    ...defaultSettings,
    ...(_kind('settings').firstOrNull ?? {}),
  };
  Map<String, dynamic> get draft => _kind('draft').firstOrNull ?? {};
  int get pendingCount => exportSyncRecords().length;
  static const defaultSettings = {
    'name': 'SRS AGENCIES',
    'tagline': 'Hardware & Building Materials',
    'category': 'Hardware, Cement & Steel',
    'address': '',
    'phone': '',
    'email': '',
    'gstin': '',
    'state': '',
    'footer':
        '1. Goods once sold are covered by standard store policy. 2. Subject to local jurisdiction.',
    'upi': '',
    'bank': '',
    'gstEnabled': false,
    'taxInclusive': false,
    'paper': 'A4',
  };
  static Future<AppStore> open() async => openForTesting(
    driftDatabase(
      name: 'counterday',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ),
  );
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

  Future<void> close() => _db.close();
  Future<void> _reload() async {
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
          },
        )
        .toList();
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
      'INSERT INTO records (id,kind,payload,revision,dirty) VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,payload=excluded.payload,revision=excluded.revision,dirty=excluded.dirty',
      [id, kind, jsonEncode(payload), next, dirty ? 1 : 0],
    );
  }

  Future<void> _commit(Future<void> Function() action) async {
    await _db.transaction(action);
    await _reload();
    notifyListeners();
  }

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

  double stockFor(String productId) =>
      movements
          .where((m) => m['productId'] == productId)
          .fold<int>(
            0,
            (sum, m) => sum + ((m['quantity'] as num) * 1000).round(),
          ) /
      1000;
  double paidFor(String invoiceId) =>
      payments
          .where((p) => p['invoiceId'] == invoiceId)
          .fold<int>(0, (sum, p) => sum + paise(p['amount'] as num)) /
      100;
  double dueFor(String invoiceId) {
    final invoice = invoices.firstWhere((i) => i['id'] == invoiceId);
    if (invoice['cancelled'] == true) return 0;
    return (paise(invoice['total'] as num) - paise(paidFor(invoiceId))) / 100;
  }

  List<Map<String, dynamic>> movementsFor(String productId) =>
      movements.where((m) => m['productId'] == productId).toList()
        ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));

  List<Map<String, dynamic>> get allMovementsWithProducts {
    final prodMap = {for (final p in products) p['id']: p};
    return movements.map((m) {
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
    return map.values.toList()
      ..sort((a, b) => (b['due'] as double).compareTo(a['due'] as double));
  }

  List<String> get categories {
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
    return list;
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
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  Future<void> saveSettings(Map<String, dynamic> value) => _commit(
    () => _put('settings', {...settings, ...value, 'id': 'shop-settings'}),
  );
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
        'shop': settings,
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
    final invoice = invoices.firstWhere((i) => i['id'] == invoiceId);
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
      final relatedMovements =
          movements.where((m) => m['invoiceId'] == invoiceId).toList();
      final relatedPayments =
          payments.where((p) => p['invoiceId'] == invoiceId).toList();

      if (relatedMovements.isEmpty && invoice['cancelled'] != true) {
        final lines = (invoice['lines'] as List?) ?? [];
        for (final line in lines) {
          if (line is Map && line['productId'] != null) {
            await _movement(
              line['productId'] as String,
              line['quantity'] as num,
              'Stock restored: deleted invoice ${invoice['number']}',
            );
          }
        }
      }

      for (final m in relatedMovements) {
        await _db.customStatement(
          'DELETE FROM records WHERE id = ?',
          [m['id']],
        );
      }
      for (final p in relatedPayments) {
        await _db.customStatement(
          'DELETE FROM records WHERE id = ?',
          [p['id']],
        );
      }
      await _db.customStatement(
        'DELETE FROM records WHERE id = ?',
        ['cancel-$invoiceId'],
      );
      await _db.customStatement(
        'DELETE FROM records WHERE id = ?',
        [invoiceId],
      );
    });
  }

  List<Map<String, dynamic>> exportSyncRecords() => _records
      .where(
        (r) =>
            r['dirty'] == 1 &&
            !['local', 'draft', 'conflict'].contains(r['kind']),
      )
      .map(
        (r) => {
          'id': r['id'],
          'kind': r['kind'],
          'payload': r['payload'],
          'revision': r['revision'],
          'baseRevision': r['baseRevision'],
        },
      )
      .toList();
  Future<void> acknowledgeSync(List records) => _commit(() async {
    for (final record in records) {
      if (record is Map) {
        await _db.customStatement(
          'UPDATE records SET base_revision=?, dirty=CASE WHEN revision=? THEN 0 ELSE dirty END WHERE id=?',
          [
            record['serverRevision'] ?? record['revision'],
            record['revision'],
            record['id'],
          ],
        );
      }
    }
  });
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
      ].contains(record['kind'])) {
        continue;
      }
      final payload = Map<String, dynamic>.from(record['payload'] as Map);
      if (payload['id'] != record['id']) {
        throw FormatException('Invalid sync record.');
      }
      final local = await _db
          .customSelect(
            'SELECT * FROM records WHERE id=?',
            variables: [Variable<String>(record['id'] as String)],
          )
          .getSingleOrNull();
      if (local != null &&
          local.read<String>('payload') == jsonEncode(payload)) {
        continue;
      }
      if (local != null && local.read<int>('dirty') == 1) {
        await _put('conflict', {
          'id': 'conflict-${record['id']}',
          'recordId': record['id'],
          'local': jsonDecode(local.read<String>('payload')),
          'remote': record,
          'createdAt': DateTime.now().toIso8601String(),
        }, dirty: false);
        continue;
      }
      if (local != null && ['payment', 'movement'].contains(record['kind'])) {
        throw StateError('Immutable ledger conflict.');
      }
      await _put(
        record['kind'] as String,
        payload,
        dirty: false,
        revision: record['revision'] as int? ?? 1,
      );
      await _db.customStatement(
        'UPDATE records SET base_revision=? WHERE id=?',
        [record['revision'] ?? 1, record['id']],
      );
    }
  });
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
