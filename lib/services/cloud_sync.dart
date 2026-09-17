import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_store.dart';

typedef SyncRecords = List<Map<String, dynamic>> Function();
typedef AcceptRecords = Future<void> Function(
  List<Map<String, dynamic>> records,
);
typedef SaveConfigCallback = Future<void> Function(String url, String anonKey);

final Map<AppStore, CloudSync> _cloudServices = {};

CloudSync cloudFor(AppStore store) => _cloudServices.putIfAbsent(store, () {
  final storedUrl = ((store.settings['supabaseUrl'] as String?) ?? '').trim();
  final storedKey =
      ((store.settings['supabaseAnonKey'] as String?) ?? '').trim();

  final service = CloudSync(
    deviceId: store.deviceId,
    pendingRecords: store.exportSyncRecords,
    acknowledge: store.acknowledgeSync,
    applyRemote: store.applyRemoteRecords,
    markAllForSync: store.markAllForSync,
    bindOwner: store.bindOwner,
    isInitialSyncDone: () => store.isInitialSyncDone,
    markInitialSyncDone: store.markInitialSyncDone,
    getCursor: () => store.syncCursor,
    setCursor: store.setSyncCursor,
    resetCursor: store.resetSyncCursor,
    saveConfig: (url, key) => store.saveSettings({
      'supabaseUrl': url,
      'supabaseAnonKey': key,
    }),
    initialUrl: storedUrl.isNotEmpty
        ? storedUrl
        : const String.fromEnvironment('SUPABASE_URL'),
    initialAnonKey: storedKey.isNotEmpty
        ? storedKey
        : const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  // Eager real-time push: when local store dirties any record (operation done), trigger immediate debounced sync
  store.addListener(() {
    if (store.pendingCount > 0) {
      service.triggerSync();
    }
  });

  service.initialize();
  return service;
});

/// High-performance offline-first sync engine.
/// Local billing never freezes or depends on this service being configured or reachable.
/// Direct sync mode: No logins, passwords, or authentication required.
/// Strictly event-driven: syncs on app open, on operations (inventory, pos, invoice), or on peer broadcasts. Zero random polling.
class CloudSync extends ChangeNotifier with WidgetsBindingObserver {
  static bool _supabaseInitialized = false;
  String _url;
  String _anonKey;
  final String deviceId;
  final SyncRecords pendingRecords;
  final AcceptRecords acknowledge;
  final AcceptRecords applyRemote;
  final Future<void> Function()? markAllForSync;
  final Future<void> Function(String owner)? bindOwner;
  final bool Function()? isInitialSyncDone;
  final Future<void> Function()? markInitialSyncDone;
  final int Function()? getCursor;
  final Future<void> Function(int cursor)? setCursor;
  final Future<void> Function()? resetCursor;
  final SaveConfigCallback? saveConfig;

  SupabaseClient? _client;
  RealtimeChannel? _realtimeChannel;
  Timer? _debounce;
  Timer? _pullDebounce;
  bool _busy = false;
  bool _syncQueued = false;
  bool _disposed = false;
  bool _initialFullSyncDone = false;
  int _cursor = 0;
  String? error;
  String status = 'Local mode';
  DateTime? lastSynced;

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
    String initialUrl = '',
    String initialAnonKey = '',
  })  : _url = initialUrl.trim(),
        _anonKey = initialAnonKey.trim();

  String get url => _url;
  String get anonKey => _anonKey;
  bool get configured => _url.isNotEmpty && _anonKey.isNotEmpty;
  bool get signedIn => configured; // Backwards compatibility for UI guards
  String? get email => null;
  bool get isOnline => configured && _client != null && error == null;
  bool get busy => _busy;
  int get pending => pendingRecords().length;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Dynamically update Supabase project credentials at runtime without app recompile.
  Future<void> configure({
    required String url,
    required String anonKey,
  }) async {
    final changed = url.trim() != _url || anonKey.trim() != _anonKey;
    _url = url.trim();
    _anonKey = anonKey.trim();
    error = null;
    if (changed) {
      _cursor = 0;
      await resetCursor?.call();
    }
    if (saveConfig != null) {
      await saveConfig!(_url, _anonKey);
    }
    await initialize();
  }

  Future<void> initialize() async {
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);

    _realtimeChannel?.unsubscribe();

    if (!configured) {
      status = 'Local mode';
      _notify();
      return;
    }

    try {
      if (!_supabaseInitialized) {
        try {
          await Supabase.initialize(url: _url, publishableKey: _anonKey);
          _supabaseInitialized = true;
        } catch (_) {
          // Already initialized or platform restriction
        }
      }

      // SupabaseClient works directly with anon key for RPCs and Realtime
      _client = SupabaseClient(_url, _anonKey);

      status = 'Direct sync active';
      _subscribeRealtime();

      _notify();
      // On app startup, sync once to bring store up to date and push any offline edits
      unawaited(sync());
    } catch (e) {
      error = '$e';
      status = 'Cloud unavailable';
      _notify();
    }
  }

  /// Realtime WebSocket subscription on billing_records.
  /// Broadcasts changes across all linked devices with sub-second latency.
  void _subscribeRealtime() {
    _realtimeChannel?.unsubscribe();
    if (_client == null || !configured) return;
    try {
      _realtimeChannel = _client!.channel('public:billing_records')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'billing_records',
          callback: (payload) {
            // When any peer device inserts or updates records, pull changes without pushing
            _pullRemoteUpdates();
          },
        ).subscribe();
    } catch (e) {
      debugPrint('Realtime channel error: $e');
    }
  }

  /// Incremental pull triggered when a peer device broadcasts updates over WebSocket.
  void _pullRemoteUpdates() {
    if (!configured || _disposed) return;
    _pullDebounce?.cancel();
    _pullDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_pullOnly());
    });
  }

  /// Incremental pull from cloud without pushing local records.
  Future<void> _pullOnly() async {
    if (_busy || !configured || _disposed || _client == null) return;
    final client = _client!;
    _busy = true;
    _notify();

    try {
      int cursor = getCursor?.call() ?? _cursor;
      while (true) {
        final raw = await client.rpc(
          'pull_billing_records',
          params: {'p_after': cursor, 'p_limit': 250},
        );
        final pulled = (raw as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (pulled.isEmpty) break;
        await applyRemote(pulled);
        cursor = (pulled.last['cursor'] as num).toInt();
        _cursor = cursor;
        await setCursor?.call(cursor);
        if (pulled.length < 250) break;
      }
      lastSynced = DateTime.now();
      status = pending == 0 ? 'Direct sync active' : 'Sync pending';
    } catch (e) {
      debugPrint('Incremental pull failed: $e');
    } finally {
      _busy = false;
      _notify();
      if (_syncQueued && !_disposed) {
        _syncQueued = false;
        triggerSync();
      }
    }
  }

  /// Instant local sync trigger with debounce (fires when an operation is completed).
  void triggerSync() {
    if (!configured || _disposed) return;
    if (_busy) {
      _syncQueued = true;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(sync());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (pending > 0) {
        triggerSync();
      } else {
        _pullRemoteUpdates();
      }
    }
  }

  /// Direct synchronization without login.
  Future<void> sync({bool forceAll = false}) async {
    if (!configured || _disposed || _client == null) return;
    if (_busy) {
      _syncQueued = true;
      return;
    }
    final client = _client!;

    _busy = true;
    error = null;
    status = 'Syncing…';
    _notify();

    try {
      final isFirstTime = isInitialSyncDone != null
          ? !isInitialSyncDone!()
          : !_initialFullSyncDone;

      if (forceAll) {
        _cursor = 0;
        await resetCursor?.call();
        if (markAllForSync != null) {
          await markAllForSync!();
        }
      } else if (isFirstTime) {
        _initialFullSyncDone = true;
        _cursor = 0;
        if (markAllForSync != null) {
          await markAllForSync!();
        }
      }

      // 1. Ensure device is registered
      await client.rpc(
        'register_billing_device',
        params: {'p_device_id': deviceId},
      );

      // 2. Push local dirty records in batches of 100
      final records = pendingRecords();
      for (var start = 0; start < records.length; start += 100) {
        final batch = records.skip(start).take(100).toList();
        final raw = await client.rpc(
          'push_billing_records',
          params: {'p_device_id': deviceId, 'p_records': batch},
        );
        final response = Map<String, dynamic>.from(raw as Map);
        final accepted = (response['accepted'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final conflicts = (response['conflicts'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        await acknowledge(accepted);
        if (conflicts.isNotEmpty) await applyRemote(conflicts);
      }

      // 3. Pull incremental updates from server
      int cursor = forceAll ? 0 : (getCursor?.call() ?? _cursor);
      while (true) {
        final raw = await client.rpc(
          'pull_billing_records',
          params: {'p_after': cursor, 'p_limit': 250},
        );
        final pulled = (raw as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (pulled.isEmpty) break;
        await applyRemote(pulled);
        cursor = (pulled.last['cursor'] as num).toInt();
        _cursor = cursor;
        await setCursor?.call(cursor);
        if (pulled.length < 250) break;
      }

      await markInitialSyncDone?.call();
      lastSynced = DateTime.now();
      status = pending == 0 ? 'Direct sync active' : 'Sync pending';
    } catch (e) {
      error = '$e';
      status = 'Offline · pending';
    } finally {
      _busy = false;
      _notify();
      if (_syncQueued && !_disposed) {
        _syncQueued = false;
        triggerSync();
      }
    }
  }

  /// Validate URL & Key connectivity without throwing.
  static Future<bool> testConnection(String url, String anonKey) async {
    try {
      final trimmedUrl = url.trim();
      final trimmedKey = anonKey.trim();
      if (trimmedUrl.isEmpty || trimmedKey.isEmpty) return false;
      final uri = Uri.tryParse(trimmedUrl);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;

      final tempClient = SupabaseClient(trimmedUrl, trimmedKey);
      await tempClient.from('billing_records').select().limit(1).maybeSingle();
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
    }
  }

  /// Generates a compact pairing string for QR code or clipboard sharing.
  static String createPairingCode({
    required String url,
    required String anonKey,
    required String shopName,
    String? email,
  }) {
    final map = {
      'url': url.trim(),
      'key': anonKey.trim(),
      'shop': shopName.trim(),
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
    _pullDebounce?.cancel();
    _realtimeChannel?.unsubscribe();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
