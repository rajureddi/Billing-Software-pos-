import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppConfig {
  static String? _cachedUrl;
  static String? _cachedKey;

  /// Supabase project URL loaded strictly from compile-time environment or .env file
  static String get supabaseUrl {
    if (_cachedUrl != null && _cachedUrl!.isNotEmpty) return _cachedUrl!;
    const envVal = String.fromEnvironment('SUPABASE_URL');
    if (envVal.isNotEmpty) {
      _cachedUrl = envVal;
      return envVal;
    }
    _loadFromDotEnvFile();
    return _cachedUrl ?? '';
  }

  /// Supabase anon key loaded strictly from compile-time environment or .env file
  static String get supabaseAnonKey {
    if (_cachedKey != null && _cachedKey!.isNotEmpty) return _cachedKey!;
    const envVal = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (envVal.isNotEmpty) {
      _cachedKey = envVal;
      return envVal;
    }
    _loadFromDotEnvFile();
    return _cachedKey ?? '';
  }

  /// Returns the initialized Supabase client with proper Flutter asyncStorage for auth
  static Future<SupabaseClient> getClient() async {
    try {
      return Supabase.instance.client;
    } catch (_) {
      final url = supabaseUrl;
      final key = supabaseAnonKey;
      if (url.isEmpty || key.isEmpty) {
        throw StateError('SUPABASE_URL and SUPABASE_ANON_KEY must be provided in .env');
      }
      await Supabase.initialize(
        url: url,
        anonKey: key,
      );
      return Supabase.instance.client;
    }
  }

  static void _loadFromDotEnvFile() {
    if (kIsWeb) return;
    try {
      final file = File('.env');
      if (file.existsSync()) {
        final lines = file.readAsLinesSync();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final split = trimmed.split('=');
          if (split.length >= 2) {
            final key = split[0].trim();
            final value = split.sublist(1).join('=').trim();
            if (key == 'SUPABASE_URL') _cachedUrl = value;
            if (key == 'SUPABASE_ANON_KEY') _cachedKey = value;
          }
        }
      }
    } catch (_) {
      // Ignored if file cannot be read directly
    }
  }

  /// Normalizes user input so that either a plain User ID / Username (e.g. "raju", "shop1")
  /// or a standard email address can be used seamlessly with Supabase Auth.
  static String formatAuthEmail(String input) {
    final trimmed = input.trim();
    if (trimmed.contains('@')) {
      return trimmed;
    }
    final sanitized = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    return '$sanitized@pos.local';
  }
}
