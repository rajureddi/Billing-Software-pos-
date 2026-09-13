import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const ink = Color(0xFF202724);
const muted = Color(0xFF7B807B);
const accent = Color(0xFFE66C3B);
const canvas = Color(0xFFF6F7F3);
const lineColor = Color(0xFFE7EAE3);
const green = Color(0xFF3B775B);
typedef Json = Map<String, dynamic>;
double number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
String money(dynamic value) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
).format(number(value));
String quantity(dynamic value) => NumberFormat('0.###').format(number(value));
String dateLabel(dynamic value) =>
    DateFormat('dd MMM yyyy')
        .format(DateTime.tryParse('$value')?.toLocal() ?? DateTime.now());

IconData categoryIcon(String category) {
  final c = category.toLowerCase();
  if (c.contains('cement')) return Icons.foundation_outlined;
  if (c.contains('plumb')) return Icons.plumbing_outlined;
  if (c.contains('iron') || c.contains('steel')) {
    return Icons.view_week_outlined;
  }
  if (c.contains('paint')) return Icons.format_paint_outlined;
  if (c.contains('elect')) return Icons.electrical_services_outlined;
  if (c.contains('tool')) return Icons.handyman_outlined;
  return Icons.inventory_2_outlined;
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: lineColor),
    ),
    child: child,
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.action});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final isCompact = screenW < 700;
    return Padding(
      padding: EdgeInsets.only(bottom: isCompact ? 14 : 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxWidth < 650 || isCompact;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: isSmall ? 20 : 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: isSmall ? -0.5 : -1,
                ),
              ),
              SizedBox(height: isSmall ? 3 : 6),
              Text(
                subtitle,
                style: TextStyle(color: muted, fontSize: isSmall ? 11 : 13),
              ),
            ],
          );
          final isPortrait =
              MediaQuery.orientationOf(context) == Orientation.portrait;
          return (isPortrait || constraints.maxWidth < 850)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    text,
                    if (action != null) ...[
                      SizedBox(height: isSmall ? 10 : 14),
                      action!,
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: text),
                    ?action,
                  ],
                );
        },
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = green});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: canvas,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: green, size: 35),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, height: 1.6),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

Widget field(
  String label,
  TextEditingController controller, {
  bool numeric = false,
  int lines = 1,
  String? hint,
  ValueChanged<String>? onChanged,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: TextField(
    controller: controller,
    onChanged: onChanged,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
        : TextInputType.text,
    maxLines: lines,
    decoration: InputDecoration(labelText: label, hintText: hint),
  ),
);
Future<void> perform(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    if (success != null && messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(success),
          backgroundColor: ink,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (error) {
    final msg = error.toString().replaceFirst('Exception: ', '');
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFFAF4137),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

void toast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFAF4137) : ink,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;

const standardUnits = [
  'pcs',
  'kg',
  'bag',
  'm',
  'ft',
  'ton',
  'ltr',
  'box',
  'pkt',
  'sq.ft',
  'sq.m',
  'bundle',
  'roll',
  'set',
  'drum',
  'can',
  'pair',
  'g',
  'inch',
];

class UnitSelector extends StatefulWidget {
  const UnitSelector({
    super.key,
    required this.controller,
    this.extraUnits = const [],
    this.onChanged,
    this.showChips = true,
    this.labelText = 'Unit of measurement',
  });

  final TextEditingController controller;
  final List<String> extraUnits;
  final ValueChanged<String>? onChanged;
  final bool showChips;
  final String labelText;

  @override
  State<UnitSelector> createState() => _UnitSelectorState();
}

class _UnitSelectorState extends State<UnitSelector> {
  late List<String> _allUnits;
  String? _selectedDropdown;

  @override
  void initState() {
    super.initState();
    _initUnits();
  }

  void _initUnits() {
    final set = <String>{};
    for (final u in standardUnits) {
      set.add(u.toLowerCase());
    }
    for (final u in widget.extraUnits) {
      if (u.trim().isNotEmpty) set.add(u.trim().toLowerCase());
    }
    if (widget.controller.text.trim().isNotEmpty) {
      set.add(widget.controller.text.trim().toLowerCase());
    }
    _allUnits = set.toList();
    _updateSelected();
  }

  void _updateSelected() {
    final current = widget.controller.text.trim().toLowerCase();
    _selectedDropdown = _allUnits.contains(current) ? current : null;
  }

  @override
  void didUpdateWidget(covariant UnitSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initUnits();
  }

  @override
  Widget build(BuildContext context) {
    final currentText = widget.controller.text.trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.straighten_rounded, size: 15, color: accent),
              const SizedBox(width: 6),
              Text(
                widget.labelText,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const Spacer(),
              if (currentText.isNotEmpty)
                Pill('Unit: $currentText', color: green),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Select unit',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedDropdown,
                      isExpanded: true,
                      hint: const Text(
                        'Choose unit…',
                        style: TextStyle(fontSize: 12),
                      ),
                      items: [
                        for (final u in _allUnits)
                          DropdownMenuItem(
                            value: u,
                            child: Text(
                              u,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _selectedDropdown = v;
                            widget.controller.text = v;
                          });
                          widget.onChanged?.call(v);
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  decoration: const InputDecoration(
                    labelText: 'Or enter custom unit',
                    hintText: 'e.g. pcs, kg, m…',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (v) {
                    setState(() {
                      final match = _allUnits.firstWhere(
                        (u) => u.toLowerCase() == v.trim().toLowerCase(),
                        orElse: () => '',
                      );
                      _selectedDropdown = match.isNotEmpty ? match : null;
                    });
                    widget.onChanged?.call(v);
                  },
                ),
              ),
            ],
          ),
          if (widget.showChips) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final u in [
                  'pcs',
                  'kg',
                  'bag',
                  'm',
                  'ft',
                  'ton',
                  'ltr',
                  'box',
                  'pkt',
                  'sq.ft'
                ])
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: currentText.toLowerCase() == u.toLowerCase()
                        ? accent.withValues(alpha: 0.15)
                        : Colors.white,
                    side: BorderSide(
                      color: currentText.toLowerCase() == u.toLowerCase()
                          ? accent
                          : lineColor,
                    ),
                    label: Text(
                      u,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            currentText.toLowerCase() == u.toLowerCase()
                                ? FontWeight.w700
                                : FontWeight.normal,
                        color: currentText.toLowerCase() == u.toLowerCase()
                            ? accent
                            : ink,
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedDropdown = u;
                        widget.controller.text = u;
                      });
                      widget.onChanged?.call(u);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

