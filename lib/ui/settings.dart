import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../services/cloud_sync.dart';
import 'common.dart';



class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});
  final AppStore store;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Map<String, TextEditingController> cs;
  late bool gst, taxInclusive;
  late String paper;
  String logo = '';
  bool saving = false;
  final email = TextEditingController(), password = TextEditingController();
  @override
  void initState() {
    super.initState();
    final s = widget.store.settings;
    cs = {
      for (final k in [
        'name',
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
    cloudFor(widget.store);
  }

  @override
  void dispose() {
    for (final c in cs.values) {
      c.dispose();
    }
    email.dispose();
    password.dispose();
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
      await widget.store.saveSettings({
        for (final k in cs.keys) k: cs[k]!.text.trim(),
        'gstEnabled': gst,
        'taxInclusive': taxInclusive,
        'paper': paper,
        'logoBase64': logo,
      });
    }, success: 'Shop settings saved');
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final cloud = cloudFor(widget.store);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
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
                              allowedExtensions: ['png', 'jpg', 'jpeg'],
                            );
                            if (result == null) return;
                            final bytes = await result.readAsBytes();
                            if (bytes.length > 1000000) {
                              throw ArgumentError(
                                'Choose an image smaller than 1 MB.',
                              );
                            }
                            setState(() => logo = base64Encode(bytes));
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
                          'Cloud & devices',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Pill(
                        cloud.status,
                        color: cloud.error == null ? green : accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your bills and inventory remain safely stored on this device without an internet connection.',
                    style: TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!cloud.configured)
                    const Text(
                      'Cloud is not connected yet. To enable it, configure a Supabase project URL and publishable/anon key when building the app, and apply the included database migration. No cloud credentials are stored in this project.',
                      style: TextStyle(fontSize: 12, height: 1.7),
                    ),
                  if (cloud.configured && !cloud.signedIn) ...[
                    field('Owner email', email),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton(
                          onPressed: cloud.busy
                              ? null
                              : () => perform(
                                  context,
                                  () => cloud.signIn(email.text, password.text),
                                ),
                          child: const Text('Sign in'),
                        ),
                        OutlinedButton(
                          onPressed: cloud.busy
                              ? null
                              : () => perform(context, () async {
                                  final result = await cloud.signUp(
                                    email.text,
                                    password.text,
                                  );
                                  if (context.mounted) toast(context, result);
                                }),
                          child: const Text('Create owner account'),
                        ),
                      ],
                    ),
                  ],
                  if (cloud.signedIn)
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(cloud.email ?? ''),
                        FilledButton(
                          onPressed: cloud.busy ? null : () => cloud.sync(),
                          child: Text(cloud.busy ? 'Syncing…' : 'Sync now'),
                        ),
                        TextButton(
                          onPressed: () => cloud.signOut(),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  if (cloud.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        cloud.error!,
                        style: const TextStyle(color: accent, fontSize: 11),
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
}
