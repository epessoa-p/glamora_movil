import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Reportes: los mismos de la web (indicadores y tablas) por período.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTimeRange _range = _preset('month');
  String _preset_ = 'month';
  String? _type;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;

  static const _presets = {'today': 'Hoy', 'week': '7 días', 'month': 'Este mes', 'last': 'Mes anterior'};

  static DateTimeRange _preset(String key) {
    final t = dateOnly(DateTime.now());
    return switch (key) {
      'today' => DateTimeRange(start: t, end: t),
      'week' => DateTimeRange(start: t.subtract(const Duration(days: 6)), end: t),
      'last' => DateTimeRange(start: DateTime(t.year, t.month - 1, 1), end: DateTime(t.year, t.month, 0)),
      _ => DateTimeRange(start: DateTime(t.year, t.month, 1), end: t),
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final d = await context.read<Session>().api.get('/reports', {
        'type': ?_type,
        'from': ymd(_range.start),
        'to': ymd(_range.end),
      });
      if (mounted) {
        setState(() {
          _data = d as Map<String, dynamic>;
          _type = '${_data!['type']}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: dateOnly(DateTime.now()),
      initialDateRange: _range,
      helpText: 'Elige el período',
      saveText: 'Aplicar',
    );
    if (picked == null) return;
    setState(() {
      _range = picked;
      _preset_ = 'custom';
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final available = ((d?['available'] as List?) ?? const []).cast<Map<String, dynamic>>();

    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: Column(children: [
        // Período
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final e in _presets.entries)
              Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: _preset_ == e.key,
                  onSelected: (_) {
                    setState(() {
                      _preset_ = e.key;
                      _range = _preset(e.key);
                    });
                    _load();
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: ChoiceChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(_preset_ == 'custom' ? '${shortDay(_range.start)} – ${shortDay(_range.end)}' : 'Elegir'),
                selected: _preset_ == 'custom',
                onSelected: (_) => _pickRange(),
              ),
            ),
          ]),
        ),
        // Tipo de reporte
        if (available.length > 1)
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final t in available)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ChoiceChip(
                    label: Text('${t['label']}'),
                    selected: _type == t['key'],
                    onSelected: (_) {
                      setState(() => _type = '${t['key']}');
                      _load();
                    },
                  ),
                ),
            ]),
          ),
        if (_loading && d != null) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : d == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(onRefresh: _load, child: _report(d)),
        ),
      ]),
    );
  }

  Widget _report(Map<String, dynamic> d) {
    final report = (d['report'] as Map?)?.cast<String, dynamic>() ?? const {};
    final kpis = ((report['kpis'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final tables = ((report['tables'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      Text('${shortDay(DateTime.parse(d['from'] as String))} al ${shortDay(DateTime.parse(d['to'] as String))} · montos en ${d['currency']}', style: TextStyle(color: muted, fontSize: 13)),
      const SizedBox(height: 10),
      // Indicadores en dos columnas
      LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final k in kpis)
            SizedBox(
              width: w,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: hexColor(k['color'] as String?), shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Expanded(child: Text('${k['label']}', style: TextStyle(color: muted, fontSize: 12), maxLines: 2)),
                    ]),
                    const SizedBox(height: 6),
                    Text('${k['value']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
        ]);
      }),
      for (final t in tables) ...[
        const SizedBox(height: 16),
        Text('${t['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        _table(t, muted),
      ],
    ]);
  }

  /// Tabla del reporte: primera columna flexible, el resto a la derecha.
  /// Con muchas columnas se desplaza de costado.
  Widget _table(Map<String, dynamic> t, Color muted) {
    final head = ((t['head'] as List?) ?? const []).map((e) => '$e').toList();
    final rows = ((t['rows'] as List?) ?? const []).map((r) => (r as List).map((e) => '${e ?? ''}').toList()).toList();
    if (rows.isEmpty) {
      return Card(child: Padding(padding: const EdgeInsets.all(14), child: Text('Sin datos en el período.', style: TextStyle(color: muted))));
    }

    Widget cell(String text, int i, {bool header = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            text,
            textAlign: i == 0 ? TextAlign.left : TextAlign.right,
            style: TextStyle(fontSize: header ? 12 : 13, fontWeight: header ? FontWeight.w700 : (i == head.length - 1 ? FontWeight.w700 : FontWeight.w400), color: header ? muted : null),
          ),
        );

    final table = Table(
      columnWidths: {0: head.length > 3 ? const IntrinsicColumnWidth() : const FlexColumnWidth(2), for (var i = 1; i < head.length; i++) i: const IntrinsicColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .06)), children: [for (final (i, h) in head.indexed) cell(h, i, header: true)]),
        for (final r in rows)
          TableRow(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .4)))),
            children: [for (var i = 0; i < head.length; i++) cell(i < r.length ? r[i] : '', i)],
          ),
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: head.length > 3 ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: table) : table,
    );
  }
}
