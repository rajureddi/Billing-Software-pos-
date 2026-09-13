import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_store.dart';
import '../services/cloud_sync.dart';
import 'common.dart';
import 'dashboard.dart';
import 'pos.dart';
import 'inventory.dart';
import 'invoices.dart';
import 'settings.dart';
import 'branding.dart';
import 'splash_screen.dart';
import 'landing_page.dart';

final storeProvider = Provider<AppStore>(
  (ref) => throw StateError('Store not initialized'),
);
final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => Consumer(
        builder: (context, ref, _) =>
            SplashScreen(store: ref.watch(storeProvider)),
      ),
    ),
    GoRoute(path: '/', redirect: (_, _) => '/splash'),
    GoRoute(
      path: '/landing',
      builder: (context, state) => Consumer(
        builder: (context, ref, _) =>
            LandingPage(store: ref.watch(storeProvider)),
      ),
    ),
    for (final page in [
      'dashboard',
      'pos',
      'inventory',
      'invoices',
      'settings',
    ])
      GoRoute(
        path: '/$page',
        builder: (_, _) => ShopShell(page: page),
      ),
  ],
);

class CounterdayApp extends StatelessWidget {
  const CounterdayApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'SRS AGENCIES • Retail & Hardware Billing',
    debugShowCheckedModeBanner: false,
    routerConfig: appRouter,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSans',
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        primary: accent,
        surface: Colors.white,
        onSurface: ink,
      ),
      dividerColor: lineColor,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 13, color: ink),
        bodyLarge: TextStyle(fontSize: 14, color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAFBF8),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: muted, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: lineColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: lineColor),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          side: const BorderSide(color: lineColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    ),
  );
}

class ShopShell extends ConsumerWidget {
  const ShopShell({super.key, required this.page});
  final String page;
  static const pages = [
    'dashboard',
    'pos',
    'inventory',
    'invoices',
    'settings',
  ];
  static const labels = [
    'Dashboard',
    'Point of sale',
    'Inventory',
    'Invoices',
    'Settings',
  ];
  static const icons = [
    Icons.grid_view_rounded,
    Icons.point_of_sale_outlined,
    Icons.inventory_2_outlined,
    Icons.receipt_long_outlined,
    Icons.tune_rounded,
  ];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 1000;
        final content = switch (page) {
          'pos' => PosPage(store: store),
          'inventory' => InventoryPage(store: store),
          'invoices' => InvoicesPage(store: store),
          'settings' => SettingsPage(store: store),
          _ => DashboardPage(store: store),
        };
        return Scaffold(
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: pages.indexOf(page),
                  onDestinationSelected: (index) =>
                      context.go('/${pages[index]}'),
                  destinations: [
                    for (var i = 0; i < pages.length; i++)
                      NavigationDestination(
                        icon: Icon(icons[i]),
                        label: i == 1 ? 'POS' : labels[i],
                      ),
                  ],
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (wide)
                  Container(
                    width: 222,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(right: BorderSide(color: lineColor)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                          child: InkWell(
                            onTap: () => context.go('/landing'),
                            borderRadius: BorderRadius.circular(12),
                            child: Row(
                              children: [
                                srsLogoWidget(size: 38, radius: 10),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'SRS AGENCIES',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.6,
                                          height: 1.1,
                                        ),
                                      ),
                                      Text(
                                        'Retail & POS Suite',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 28, bottom: 14),
                          child: Text(
                            'WORKSPACE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: muted,
                              letterSpacing: 1.7,
                            ),
                          ),
                        ),
                        for (var i = 0; i < pages.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 3,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                selected: page == pages[i],
                                selectedTileColor: const Color(0xFFFEF0E8),
                                selectedColor: accent,
                                leading: Icon(icons[i], size: 20),
                                title: Text(
                                  labels[i],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onTap: () => context.go('/${pages[i]}'),
                              ),
                            ),
                          ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: canvas,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.offline_bolt_outlined,
                                  color: green,
                                  size: 23,
                                ),
                                SizedBox(height: 9),
                                Text(
                                  'Ready, even offline.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(height: 5),
                                Text(
                                  'Your bills are saved\non this device.',
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 11,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(28, 0, 20, 23),
                          child: Text(
                            'SRS AGENCIES  /  v1.0',
                            style: TextStyle(
                              color: muted,
                              fontSize: 9,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: wide ? 64 : 52,
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 28 : 14,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(bottom: BorderSide(color: lineColor)),
                        ),
                        child: Row(
                          children: [
                            if (!wide) ...[
                              InkWell(
                                onTap: () => context.go('/landing'),
                                child: srsLogoWidget(size: 28, radius: 7),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: InkWell(
                                onTap: () => context.go('/landing'),
                                borderRadius: BorderRadius.circular(8),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${store.settings['name'] ?? 'SRS AGENCIES'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: wide ? 14 : 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${store.settings['category'] ?? ''}'
                                              .isEmpty
                                          ? 'Your everyday retail workspace'
                                          : '${store.settings['category']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (wide)
                              AnimatedBuilder(
                                animation: cloudFor(store),
                                builder: (context, _) {
                                  final cloud = cloudFor(store);
                                  final Color dotColor = cloud.busy
                                      ? accent
                                      : !cloud.configured || !cloud.signedIn
                                          ? muted
                                          : cloud.error != null
                                              ? const Color(0xFFC74343)
                                              : store.pendingCount > 0
                                                  ? const Color(0xFFB08A35)
                                                  : green;
                                  final String label = cloud.busy
                                      ? 'Syncing…'
                                      : !cloud.configured || !cloud.signedIn
                                          ? 'Local mode'
                                          : store.pendingCount > 0
                                              ? 'Sync pending'
                                              : 'Cloud synced';
                                  return TextButton.icon(
                                    onPressed: () {
                                      if (cloud.configured && cloud.signedIn) {
                                        cloud.sync();
                                      } else {
                                        context.go('/settings');
                                      }
                                    },
                                    icon: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: dotColor,
                                      ),
                                    ),
                                    label: Text(
                                      label,
                                      style: const TextStyle(
                                        color: ink,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            SizedBox(width: wide ? 16 : 8),
                            Container(
                              width: wide ? 35 : 30,
                              height: wide ? 35 : 30,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8EEE5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.person_outline_rounded,
                                color: green,
                                size: wide ? 20 : 17,
                              ),
                            ),
                            if (wide)
                              const Padding(
                                padding: EdgeInsets.only(left: 9),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Shop owner',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      'Personal workspace',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(child: content),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
