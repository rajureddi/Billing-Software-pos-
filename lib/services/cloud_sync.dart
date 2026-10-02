import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_store.dart';
import '../data/app_config.dart';

typedef SyncRecords = List<Map<String, dynamic>> Function();
typedef AcceptRecords = Future<void> Function(
  List<Map<String, dynamic>> records,
);
typedef SyncRpc = Future<dynamic> Function(
  String name,
  Map<String, dynamic> params,
);
typedef SaveConfigCallback = Future<void> Function(
  String url,
  String key,
  String token,
);
final Map<AppStore, CloudSync> _cloudServices = {};
CloudSync cloudFor(AppStore store) => _cloudServices.putIfAbsent(store, () {
  final settings = store.settings;
  final service = CloudSync(
    deviceId: store.deviceId,
    pendingRecords: store.exportSyncRecords,
    acknowledge: store.acknowledgeSync,
    applyRemote: store.applyRemoteRecords,
    isInitialSyncDone: () => store.isInitialSyncDone,
    markInitialSyncDone: store.markInitialSyncDone,
    getCursor: () => store.syncCursor,
    setCursor: store.setSyncCursor,
    resetCursor: store.resetSyncCursor,
    saveConfig: (url, key, token) => store.saveSettings({
      'supabaseUrl': url,
      'supabaseAnonKey': key,
      'supabaseShopToken': token,
    }),
    initialUrl: ((settings['supabaseUrl'] as String?)?.trim().isNotEmpty ?? false)
        ? (settings['supabaseUrl'] as String).trim()
        : AppConfig.supabaseUrl,
    initialAnonKey: ((settings['supabaseAnonKey'] as String?)?.trim().isNotEmpty ?? false)
        ? (settings['supabaseAnonKey'] as String).trim()
        : AppConfig.supabaseAnonKey,
    initialShopToken: (settings['supabaseShopToken'] as String?) ?? '',
  );
  store.syncChanges.addListener(service.triggerSync);
  store.syncStatus.addListener(service.refreshStatus);
  service.onDispose = () {
    store.syncChanges.removeListener(service.triggerSync);
    store.syncStatus.removeListener(service.refreshStatus);
    _cloudServices.remove(store);
  };
  unawaited(service.initialize());
  return service;
});

/// One serialized sync path. Reconnect, local writes and periodic catch-up all
/// enter this queue; no realtime callback writes to the database independently.
class CloudSync extends ChangeNotifier with WidgetsBindingObserver {
  String _url, _anonKey, _shopToken;
  final String deviceId;
  final SyncRecords pendingRecords;
  final AcceptRecords acknowledge, applyRemote;
  final Future<void> Function()? markAllForSync,
      markInitialSyncDone,
      resetCursor;
  final Future<void> Function(String)? bindOwner;
  final bool Function()? isInitialSyncDone;
  final int Function()? getCursor;
  final Future<void> Function(int)? setCursor;
  final SaveConfigCallback? saveConfig;
  final SyncRpc? rpcOverride;
  final Duration retryBase, catchUpInterval;
  SupabaseClient? _client;
  Timer? _debounce, _retry, _catchUp;
  Future<void>? _running;
  bool _syncQueued = false,
      _forceQueued = false,
      _disposed = false,
      _healthy = false;
  int _cursor = 0, _failures = 0;
  String? error;
  String status = 'Local mode';
  DateTime? lastSynced;
  VoidCallback? onDispose;
  CloudSync({
    required this.deviceId,
    required this.pendingRecords,
    required this.acknowledge,
    required this.applyRemote,
    this.markAllForSync,
    this.bindOwner,
    this.isInitialSyncDone,
    this.markInitialSyncDone,
    this.getCursor,
    this.setCursor,
    this.resetCursor,
    this.saveConfig,
    this.rpcOverride,
    this.retryBase = const Duration(seconds: 2),
    this.catchUpInterval = const Duration(seconds: 15),
    String initialUrl = '',
    String initialAnonKey = '',
    String initialShopToken = '',
  }) : _url = initialUrl.trim(),
       _anonKey = initialAnonKey.trim(),
       _shopToken = initialShopToken.trim();
  String get url => _url;
  String get anonKey => _anonKey;
  String get shopToken => _shopToken;
  bool get configured => _url.isNotEmpty && _anonKey.isNotEmpty;
  bool get signedIn => configured;
  String? get email => null;
  bool get isOnline => configured && _healthy && error == null;
  bool get busy => _running != null;
  int get pending => pendingRecords().length;
  void refreshStatus() {
    if (!_disposed) notifyListeners();
  }

  Future<dynamic> _rpc(String name, Map<String, dynamic> params) {
    final request = {
      ...params,
      if (_shopToken.isNotEmpty) 'p_shop_token': _shopToken,
    };
    return (rpcOverride != null
            ? rpcOverride!(name, request)
            : _client!.rpc(name, params: request))
        .timeout(const Duration(seconds: 25));
  }

  Future<void> configure({
    required String url,
    required String anonKey,
    String? shopToken,
  }) async {
    _debounce?.cancel();
    _retry?.cancel();
    _catchUp?.cancel();
    if (_running != null) await _running;
    final changed =
        url.trim() != _url ||
        anonKey.trim() != _anonKey ||
        (shopToken ?? _shopToken).trim() != _shopToken;
    // A different project must use a separate local database. Never upload an
    // existing shop to an accidentally pasted destination.
    if (_url.isNotEmpty && url.trim() != _url)
      throw StateError(
        'Use a separate local workspace to connect a different Supabase project.',
      );
    _url = url.trim();
    _anonKey = anonKey.trim();
    _shopToken = (shopToken ?? _shopToken).trim();
    _healthy = false;
    error = null;
    if (changed) {
      _cursor = 0;
      await resetCursor?.call();
    }
    await saveConfig?.call(_url, _anonKey, _shopToken);
    await initialize();
  }

  Future<void> initialize() async {
    if (_disposed) return;
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
    _catchUp?.cancel();
    _retry?.cancel();
    _debounce?.cancel();
    try {
      if (_client != null && _client != Supabase.instance.client) {
        await _client?.dispose();
      }
    } catch (_) {}
    _client = null;
    if (!configured) {
      status = _url.isNotEmpty ? 'Enter the publishable key' : 'Local mode';
      refreshStatus();
      return;
    }
    if (rpcOverride == null) {
      try {
        _client = Supabase.instance.client;
      } catch (_) {
        _client = SupabaseClient(_url, _anonKey);
      }
    }
    _catchUp = Timer.periodic(catchUpInterval, (_) {
      if (_retry == null) triggerSync();
    });
    await sync();
  }

  void triggerSync() {
    if (!configured || _disposed) return;
    if (busy) {
      _syncQueued = true;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(sync()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) triggerSync();
  }

  Future<void> sync({bool forceAll = false}) {
    if (!configured || _disposed || (_client == null && rpcOverride == null))
      return Future.value();
    if (busy) {
      _syncQueued = true;
      _forceQueued |= forceAll;
      return _running!;
    }
    _debounce?.cancel();
    _retry?.cancel();
    _retry = null;
    final done = Completer<void>();
    _running = done.future;
    unawaited(
      _run(forceAll).whenComplete(() {
        _running = null;
        done.complete();
        refreshStatus();
      }),
    );
    return done.future;
  }

  Future<void> _pull() async {
    var cursor = getCursor?.call() ?? _cursor;
    while (!_disposed) {
      final raw = await _rpc('pull_billing_records', {
        'p_after': cursor,
        'p_limit': 250,
      });
      final rows = (raw as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      if (rows.isEmpty) break;
      final next = (rows.last['cursor'] as num).toInt();
      if (next <= cursor)
        throw StateError('Server returned a non-advancing sync cursor.');
      await applyRemote(rows);
      await setCursor?.call(next);
      _cursor = cursor = next;
      if (rows.length < 250) break;
    }
  }

  Future<void> _run(bool forceAll) async {
    status = 'Syncing…';
    refreshStatus();
    try {
      do {
        _syncQueued = false;
        if (forceAll || _forceQueued) {
          _forceQueued = false;
          forceAll = false;
          _cursor = 0;
          await resetCursor?.call();
        }
        await _rpc('register_billing_device', {'p_device_id': deviceId});
        // Pull first, preserving conflicting unsent edits for explicit review.
        // Full resync never marks stale clean records dirty.
        await _pull();
        final groups = <String, List<Map<String, dynamic>>>{};
        for (final record in pendingRecords()) {
          groups
              .putIfAbsent('${record['groupId'] ?? record['id']}', () => [])
              .add(record);
        }
        for (final group in groups.values) {
          if (_disposed) return;
          if (group.length > 1000)
            throw StateError(
              'This operation exceeds the 1000-record sync limit.',
            );
          final raw = await _rpc('push_billing_records', {
            'p_device_id': deviceId,
            'p_records': group,
          });
          final response = Map<String, dynamic>.from(raw as Map);
          final accepted = (response['accepted'] as List? ?? [])
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
          final conflicts = (response['conflicts'] as List? ?? [])
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
          if (accepted.isEmpty && conflicts.isEmpty)
            throw StateError('The server did not acknowledge the operation.');
          if (accepted.isNotEmpty) await acknowledge(accepted);
          if (conflicts.isNotEmpty) await applyRemote(conflicts);
        }
        await _pull();
        await markInitialSyncDone?.call();
        lastSynced = DateTime.now();
        _healthy = true;
        error = null;
        _failures = 0;
        status = pending == 0 ? 'Up to date' : 'Sync pending';
      } while (_syncQueued && !_disposed);
    } catch (e) {
      _healthy = false;
      error = '$e';
      status = 'Sync failed · retrying';
      _syncQueued = false;
      final factor = 1 << _failures.clamp(0, 5);
      _failures++;
      if (!_disposed)
        _retry = Timer(retryBase * factor, () {
          _retry = null;
          unawaited(sync());
        });
    }
  }

  static Future<bool> testConnection(
    String url,
    String anonKey, {
    String shopToken = '',
  }) async {
    final trimmedUrl = url.trim();
    final trimmedKey = anonKey.trim();
    if (trimmedUrl.isEmpty || trimmedKey.isEmpty) return false;
    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;

    final client = SupabaseClient(trimmedUrl, trimmedKey);
    try {
      final params = <String, dynamic>{
        'p_after': 0,
        'p_limit': 1,
        if (shopToken.trim().isNotEmpty) 'p_shop_token': shopToken.trim(),
      };
      await client
          .rpc('pull_billing_records', params: params)
          .timeout(const Duration(seconds: 15));
      return true;
    } catch (e) {
      final err = e.toString().toLowerCase();
      if (err.contains('jwt') ||
          err.contains('permission') ||
          err.contains('policy') ||
          err.contains('auth') ||
          err.contains('pgrst')) {
        return true;
      }
      return false;
    } finally {
      await client.dispose();
    }
  }

  /// Generates a compact pairing string for QR code or clipboard sharing.
  static String createPairingCode({
    required String url,
    required String anonKey,
    required String shopName,
    String? email,
    String shopToken = '',
  }) {
    final map = {
      'url': url.trim(),
      'key': anonKey.trim(),
      'shop': shopName.trim(),
      'token': shopToken.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    };
    return base64Encode(utf8.encode(jsonEncode(map)));
  }

  /// Parses a pairing code string generated from another device.
  static Map<String, String>? parsePairingCode(String code) {
    try {
      final raw = code.trim();
      final decodedJson = utf8.decode(base64Decode(raw));
      final map = Map<String, dynamic>.from(jsonDecode(decodedJson) as Map);
      if (map['url'] != null && map['key'] != null) {
        return {
          'url': map['url'].toString(),
          'key': map['key'].toString(),
          'shop': (map['shop'] ?? '').toString(),
          'token': (map['token'] ?? '').toString(),
          if (map['email'] != null) 'email': map['email'].toString(),
        };
      }
    } catch (_) {
      // Not a base64 pairing string
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _retry?.cancel();
    _catchUp?.cancel();
    unawaited(_client?.dispose() ?? Future.value());
    WidgetsBinding.instance.removeObserver(this);
    onDispose?.call();
    super.dispose();
  }
}
