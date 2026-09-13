import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/app_store.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = await AppStore.open();
    runApp(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: const CounterdayApp(),
      ),
    );
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Could not open your local shop data. Please reopen the app.\n\n$error',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
