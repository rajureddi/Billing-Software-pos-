import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_store.dart';

typedef SyncRecords = List<Map<String, dynamic>> Function();
typedef AcceptRecords = Future<void> Function(
  List<Map<String, dynamic>> records,
);

final Map<AppStore, CloudSync> _cloudServices = {};
CloudSync cloudFor(AppStore store) => _cloudServices.putIfAbsent(store, () {
  final service = CloudSync(
    deviceId: store.deviceId,
    pendingRecords: store.exportSyncRecords,
    acknowledge: store.acknowledgeSync,
    applyRemote: store.applyRemoteRecords,
    bindOwner: store.bindOwner,
  );
  service.initialize();
  return service;
});

/// Local billing never depends on this service being configured or reachable.
class CloudSync extends ChangeNotifier with WidgetsBindingObserver {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final String deviceId;
  final SyncRecords pendingRecords;
  final AcceptRecords acknowledge;
  final AcceptRecords applyRemote;
  final Future<void> Function(String owner) bindOwner;
  SupabaseClient? _client;
  Timer? _timer;
  StreamSubscription<AuthState>? _auth;
  bool _busy = false;
  bool _disposed = false;
  int _cursor = 0;
  String? _owner;
  String? error;
  String status = 'Local mode';
  DateTime? lastSynced;
  CloudSync({
    required this.deviceId,
    required this.pendingRecords,
    required this.acknowledge,
    required this.applyRemote,
    required this.bindOwner,
  });
  bool get configured => url.isNotEmpty && anonKey.isNotEmpty;
  bool get signedIn => _client?.auth.currentUser != null;
  String? get email => _client?.auth.currentUser?.email;
  bool get busy => _busy;
  int get pending => pendingRecords().length;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    if (!configured) return;
    try {
      await Supabase.initialize(url: url, publishableKey: anonKey);
      _client = Supabase.instance.client;
      _auth = _client!.auth.onAuthStateChange.listen((_) {
        status = signedIn ? 'Ready to sync' : 'Sign in to sync';
        _notify();
        if (signedIn) unawaited(sync());
      });
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(sync()),
      );
      status = signedIn ? 'Ready to sync' : 'Sign in to sync';
      await sync();
    } catch (e) {
      error = '$e';
      status = 'Cloud unavailable';
    }
    _notify();
  }

  Future<void> signIn(String email, String password) async {
    if (_client == null) {
      throw StateError('Configure Supabase before signing in.');
    }
    await _client!.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await sync();
  }

  Future<String> signUp(String email, String password) async {
    if (_client == null) {
      throw StateError('Configure Supabase before creating an account.');
    }
    final result = await _client!.auth.signUp(
      email: email.trim(),
      password: password,
    );
    if (result.session == null) {
      return 'Check your email to confirm your account, then sign in.';
    }
    await sync();
    return 'Account created.';
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
    status = 'Sign in to sync';
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  Future<void> sync() async {
    if (_busy || !signedIn || _disposed) return;
    final client = _client!;
    final owner = client.auth.currentUser!.id;
    // Keep a local database attached to one account during its lifetime.
    if (_owner != null && _owner != owner) {
      error =
          'This local shop belongs to another account. Use its owner account.';
      status = 'Account mismatch';
      _notify();
      return;
    }
    _owner = owner;
    _busy = true;
    error = null;
    status = 'Syncing';
    _notify();
    try {
      await bindOwner(owner);
      await client.rpc(
        'register_billing_device',
        params: {'p_device_id': deviceId},
      );
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
      while (true) {
        final raw = await client.rpc(
          'pull_billing_records',
          params: {'p_after': _cursor, 'p_limit': 250},
        );
        final records = (raw as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (records.isEmpty) break;
        await applyRemote(records);
        _cursor = (records.last['cursor'] as num).toInt();
        if (records.length < 250) break;
      }
      lastSynced = DateTime.now();
      status = pending == 0 ? 'Up to date' : 'Resolve sync conflicts';
    } catch (e) {
      error = '$e';
      status = 'Offline · retrying';
    } finally {
      _busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _auth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
