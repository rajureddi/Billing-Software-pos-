import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_store.dart';
import '../services/cloud_sync.dart';
import '../services/image_optimizer.dart';
import 'common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});
  final AppStore store;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Map<String, TextEditingController> cs;
  final shopTokenController = TextEditingController();
  late bool gst, taxInclusive;
  late String paper;
  String logo = '';
  bool saving = false;
  late final TextEditingController supabaseUrlController;
  late final TextEditingController supabaseKeyController;
  bool showCloudSetup = false;
  bool testingConnection = false;
  String? connectionFeedback;
  bool? connectionSuccess;

  @override
  void initState() {
    super.initState();
    final s = widget.store.settings;
    cs = {
      for (final k in [
        'name',
        'owner',
        'tagline',
        'category',
        'address',
        'phone',
        'email',
        'gstin',
        'state',
        'footer',
        'upi',
        'bank',
      ])
        k: TextEditingController(text: '${s[k] ?? ''}'),
    };
    gst = s['gstEnabled'] == true;
    taxInclusive = s['taxInclusive'] == true;
    paper = s['paper'] ?? 'A4';
    logo = s['logoBase64'] ?? '';
    final cloud = cloudFor(widget.store);
    final initialUrl = ((s['supabaseUrl'] as String?) ?? '').trim();
    final initialKey = ((s['supabaseAnonKey'] as String?) ?? '').trim();
    supabaseUrlController = TextEditingController(
      text: initialUrl.isNotEmpty ? initialUrl : cloud.url,
    );
    supabaseKeyController = TextEditingController(
      text: initialKey.isNotEmpty ? initialKey : cloud.anonKey,
    );
    shopTokenController.text = cloud.shopToken;
    showCloudSetup = !cloud.configured;
    widget.store.syncChanges.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (!mounted || saving) return;
    final s = widget.store.settings;
    for (final entry in cs.entries) {
      final val = '${s[entry.key] ?? ''}';
      if (entry.value.text != val) {
        entry.value.text = val;
      }
    }
    setState(() {
      gst = s['gstEnabled'] == true;
      taxInclusive = s['taxInclusive'] == true;
      paper = s['paper'] ?? 'A4';
      logo = s['logoBase64'] ?? '';
    });
  }

  @override
  void dispose() {
    widget.store.syncChanges.removeListener(_onStoreChanged);
    shopTokenController.dispose();
    for (final c in cs.values) {
      c.dispose();
    }
    supabaseUrlController.dispose();
    supabaseKeyController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    await perform(context, () async {
      if (cs['name']!.text.trim().isEmpty) {
        throw ArgumentError('Shop name is required.');
      }
      if (gst &&
          (cs['gstin']!.text.trim().length != 15 ||
              cs['state']!.text.trim().isEmpty)) {
        throw ArgumentError(
          'For GST billing, enter a 15-character GSTIN and shop state.',
        );
      }
      final url = supabaseUrlController.text.trim();
      final key = supabaseKeyController.text.trim();
      await widget.store.saveSettings({
        for (final k in cs.keys) k: cs[k]!.text.trim(),
        'gstEnabled': gst,
        'taxInclusive': taxInclusive,
        'paper': paper,
        'logoBase64': logo,
        'supabaseUrl': url,
        'supabaseAnonKey': key,
        'supabaseShopToken': shopTokenController.text.trim(),
      });
      final cloud = cloudFor(widget.store);
      if (url != cloud.url ||
          key != cloud.anonKey ||
          shopTokenController.text.trim() != cloud.shopToken) {
        await cloud.configure(
          url: url,
          anonKey: key,
          shopToken: shopTokenController.text,
        );
      }
    }, success: 'Shop settings saved');
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final cloud = cloudFor(widget.store);
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isCompact ? 14 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            'Make it your shop.',
            'Your identity, your preferences. Printed on every invoice.',
            action: FilledButton.icon(
              onPressed: saving ? null : save,
              icon: const Icon(Icons.check, size: 18),
              label: Text(saving ? 'Saving…' : 'Save changes'),
            ),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final identity = Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Business details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'These details appear at the top of your invoices.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: canvas,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: logo.isEmpty
                              ? const Icon(
                                  Icons.storefront_outlined,
                                  color: green,
                                  size: 29,
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(13),
                                  child: Image.memory(
                                    base64Decode(logo),
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton(
                          onPressed: () => perform(context, () async {
                            final result = await FilePicker.pickFile(
                              type: FileType.custom,
                              allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
                            );
                            if (result == null) return;
                            final bytes = await result.readAsBytes();
                            final opt = await ImageOptimizer.optimize(
                              bytes,
                              maxDimension: 400,
                            );
                            setState(() => logo = opt.base64);
                          }),
                          child: const Text('Upload logo'),
                        ),
                        if (logo.isNotEmpty)
                          IconButton(
                            onPressed: () => setState(() => logo = ''),
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    field('Shop name', cs['name']!),
                    field('Owner / Proprietor name', cs['owner']!),
                    field('Tagline', cs['tagline']!),
                    field(
                      'Business category',
                      cs['category']!,
                      hint: 'Hardware & building materials',
                    ),
                    field('Shop address', cs['address']!, lines: 3),
                    field('Phone number', cs['phone']!),
                    field('Email address', cs['email']!),
                    field('Shop state / state code', cs['state']!),
                    field('GSTIN', cs['gstin']!),
                  ],
                ),
              );
              final prefs = Column(
                children: [
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Billing preferences',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'GST billing',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Default for new bills',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                          value: gst,
                          onChanged: (v) => setState(() => gst = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Prices include GST',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          value: taxInclusive,
                          onChanged: (v) => setState(() => taxInclusive = v),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: paper,
                          decoration: const InputDecoration(
                            labelText: 'Default invoice size',
                          ),
                          items: [
                            for (final p in ['A4', 'A5', '58mm', '80mm'])
                              DropdownMenuItem(value: p, child: Text(p)),
                          ],
                          onChanged: (v) => setState(() => paper = v!),
                        ),
                        const SizedBox(height: 16),
                        field(
                          'Invoice footer / terms',
                          cs['footer']!,
                          lines: 3,
                        ),
                        field('UPI ID', cs['upi']!),
                        field('Bank details', cs['bank']!, lines: 2),
                        const Text(
                          'Invoice numbers use a unique device series. Printer selection is available in your system print dialog.',
                          style: TextStyle(
                            color: muted,
                            fontSize: 11,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Panel(
                    color: const Color(0xFFEDF2EA),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.print_outlined,
                          color: green,
                          size: 28,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Made for your counter.',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'A4 and A5 for detailed invoices. 58 mm and 80 mm for compact receipts. Print from your laptop through the installed Epson or receipt-printer driver.',
                          style: TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              return c.maxWidth > 850
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: identity),
                        const SizedBox(width: 24),
                        Expanded(flex: 2, child: prefs),
                      ],
                    )
                  : Column(
                      children: [identity, const SizedBox(height: 20), prefs],
                    );
            },
          ),
          const SizedBox(height: 24),
          Panel(
            child: AnimatedBuilder(
              animation: cloud,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud_outlined, color: green),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Cloud & multi-device sync',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Pill(
                        cloud.busy
                            ? 'Syncing…'
                            : !cloud.configured
                            ? 'Local mode'
                            : cloud.error != null
                            ? 'Offline · Retrying'
                            : 'Direct sync active',
                        color: !cloud.configured
                            ? muted
                            : cloud.error != null
                            ? accent
                            : green,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'All your inventory, product photos, stock movements, and invoices sync in real-time across iOS, Android, Windows, and Web. If internet disconnects, local billing and printing continue smoothly.',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.7),
                  ),
                  const SizedBox(height: 16),

                  // Connection Config Box (collapsible or shown if unconfigured)
                  if (!cloud.configured || showCloudSetup) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: canvas,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: lineColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.hub_outlined,
                                color: green,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Supabase Cloud Connection',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (cloud.configured)
                                TextButton(
                                  onPressed: () =>
                                      setState(() => showCloudSetup = false),
                                  child: const Text('Hide settings'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Enter your Supabase project credentials. All devices connect to the same project database.',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Supabase URL and Anon Key are securely loaded from your .env file.',
                            style: TextStyle(fontSize: 12, color: green, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 14),
                          field(
                            'Private Shop Token (Optional)',
                            shopTokenController,
                          ),
                          if (connectionFeedback != null) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  Icon(
                                    connectionSuccess == true
                                        ? Icons.check_circle_outline
                                        : Icons.error_outline,
                                    size: 16,
                                    color: connectionSuccess == true
                                        ? green
                                        : const Color(0xFFC74343),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      connectionFeedback!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: connectionSuccess == true
                                            ? green
                                            : const Color(0xFFC74343),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: cloud.busy
                                    ? null
                                    : () => perform(
                                        context,
                                        () async {
                                          final url = supabaseUrlController.text
                                              .trim();
                                          final key = supabaseKeyController.text
                                              .trim();
                                          if (url.isEmpty || key.isEmpty) {
                                            throw ArgumentError(
                                              'Enter the project URL and publishable key.',
                                            );
                                          }
                                          await cloud.configure(
                                            url: url,
                                            anonKey: key,
                                            shopToken: shopTokenController.text,
                                          );
                                          await widget.store.saveSettings({
                                            'supabaseUrl': url,
                                            'supabaseAnonKey': key,
                                            'supabaseShopToken':
                                                shopTokenController.text.trim(),
                                          });
                                          setState(
                                            () => showCloudSetup = false,
                                          );
                                        },
                                        success:
                                            'Connected to Supabase project!',
                                      ),
                                icon: const Icon(Icons.link, size: 16),
                                label: const Text('Save & Connect'),
                              ),
                              OutlinedButton.icon(
                                onPressed: testingConnection
                                    ? null
                                    : () async {
                                        setState(() {
                                          testingConnection = true;
                                          connectionFeedback = null;
                                        });
                                        final ok =
                                            await CloudSync.testConnection(
                                              supabaseUrlController.text,
                                              supabaseKeyController.text,
                                              shopToken:
                                                  shopTokenController.text,
                                            );
                                        if (mounted) {
                                          setState(() {
                                            testingConnection = false;
                                            connectionSuccess = ok;
                                            connectionFeedback = ok
                                                ? 'Connection successful! Cloud backend is reachable.'
                                                : 'Could not connect. Check the URL and Publishable Key.';
                                          });
                                        }
                                      },
                                icon: testingConnection
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.network_check_rounded,
                                        size: 16,
                                      ),
                                label: Text(
                                  testingConnection
                                      ? 'Testing…'
                                      : 'Test Connection',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _showImportPairingDialog(context, cloud),
                                icon: const Icon(
                                  Icons.qr_code_scanner,
                                  size: 16,
                                ),
                                label: const Text('Import Pairing Code'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // Direct Sync Active Card and Actions
                  if (cloud.configured) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F8F1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC7E2C3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: green.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(
                              Icons.cloud_done_rounded,
                              color: green,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Direct Sync Active',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: green,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Device: ${widget.store.deviceId.substring(0, 8)} · '
                                  '${cloud.pending == 0 ? "All changes synced" : "${cloud.pending} pending"} · '
                                  '${cloud.lastSynced != null ? "Synced ${cloud.lastSynced!.hour.toString().padLeft(2, '0')}:${cloud.lastSynced!.minute.toString().padLeft(2, '0')}" : "Instant real-time sync"}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: cloud.busy
                              ? null
                              : () => perform(context, () async {
                                  await cloud.sync();
                                }, success: 'Synchronized with cloud!'),
                          icon: const Icon(Icons.sync_rounded, size: 16),
                          label: Text(cloud.busy ? 'Syncing…' : 'Sync now'),
                        ),
                      ],
                    ),
                  ],

                  if (cloud.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        cloud.error!,
                        style: const TextStyle(
                          color: Color(0xFFC74343),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (widget.store.conflicts.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7F2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFFD8C2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: accent,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${widget.store.conflicts.length} sync conflict${widget.store.conflicts.length == 1 ? '' : 's'} need review',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: accent,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'The same product or settings were edited on this device and also on another device. Select which version to keep.',
                            style: TextStyle(fontSize: 12, color: ink),
                          ),
                          const SizedBox(height: 16),
                          for (final c in widget.store.conflicts) ...[
                            _buildConflictCard(context, widget.store, c),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Backup & restore',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Keep a copy of your shop data. Restoring merges missing records without duplicating existing invoices.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => perform(context, () async {
                        final data = await widget.store.exportBackup();
                        await FilePicker.saveFile(
                          dialogTitle: 'Export shop backup',
                          fileName:
                              'counterday-backup-${DateTime.now().millisecondsSinceEpoch}.json',
                          bytes: Uint8List.fromList(utf8.encode(data)),
                        );
                      }, success: 'Backup export ready'),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Export backup'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => perform(context, () async {
                        final result = await FilePicker.pickFile(
                          type: FileType.custom,
                          allowedExtensions: ['json'],
                        );
                        if (result == null) return;
                        final bytes = await result.readAsBytes();
                        if (!context.mounted) return;
                        if (await confirm(
                          context,
                          'Restore this backup?',
                          'Missing products, invoices, payments, and stock movements will be added to this device. Existing records are kept.',
                        )) {
                          await widget.store.importBackup(utf8.decode(bytes));
                        }
                      }, success: 'Backup checked'),
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text('Restore backup'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                try {
                  await Supabase.instance.client.auth.signOut();
                } catch (_) {}
                await widget.store.switchShop('');
                if (context.mounted) {
                  context.go('/login');
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC42B2B),
                side: const BorderSide(color: Color(0xFFC42B2B)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Log Out of Workspace'),
            ),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildConflictCard(
    BuildContext context,
    AppStore store,
    Map<String, dynamic> c,
  ) {
    final local = Map<String, dynamic>.from(c['local'] as Map? ?? {});
    final remote = Map<String, dynamic>.from(
      ((c['remote'] as Map?)?['payload'] as Map?) ?? {},
    );
    final kind = ((c['remote'] as Map?)?['kind'] as String?) ?? 'record';
    final name = local['name'] ?? remote['name'] ?? c['recordId'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill(kind.toUpperCase(), color: muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$name',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: canvas,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LOCAL DEVICE VERSION',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Price: ${money(local['price'])}  ·  Unit: ${local['unit'] ?? '-'}\nCategory: ${local['category'] ?? '-'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F6F3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CLOUD / REMOTE VERSION',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: green,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Price: ${money(remote['price'])}  ·  Unit: ${remote['unit'] ?? '-'}\nCategory: ${remote['category'] ?? '-'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => perform(
                  context,
                  () => store.resolveConflict(c['id'], useRemote: false),
                  success: 'Kept local version',
                ),
                child: const Text('Keep local version'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => perform(
                  context,
                  () => store.resolveConflict(c['id'], useRemote: true),
                  success: 'Accepted cloud version',
                ),
                child: const Text('Accept cloud version'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showImportPairingDialog(BuildContext context, CloudSync cloud) {
    final input = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setModal) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.qr_code_scanner, color: green, size: 24),
              SizedBox(width: 10),
              Text('Import Pairing Code'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paste the pairing code copied from your other device to connect automatically.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: input,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Pairing code',
                    hintText: 'Paste code here…',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final parsed = CloudSync.parsePairingCode(input.text);
                if (parsed == null) {
                  toast(dialogCtx, 'Invalid pairing code format.', error: true);
                  return;
                }
                Navigator.pop(dialogCtx);
                setState(() {
                  supabaseUrlController.text = parsed['url']!;
                  supabaseKeyController.text = parsed['key']!;
                  shopTokenController.text = parsed['token'] ?? '';
                  showCloudSetup = false;
                });
                await cloud.configure(
                  url: parsed['url']!,
                  anonKey: parsed['key']!,
                  shopToken: parsed['token'] ?? '',
                );
                await widget.store.saveSettings({
                  'supabaseUrl': parsed['url']!,
                  'supabaseAnonKey': parsed['key']!,
                  'supabaseShopToken': parsed['token'] ?? '',
                });
                if (context.mounted) {
                  toast(context, 'Direct sync connected successfully!');
                }
              },
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
