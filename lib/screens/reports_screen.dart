import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Reportes: una tarjeta por reporte. Cada una abre su vista.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

/// Tarjetas del menú: título, descripción, icono, color y tipos del servidor.
const _cards = [
  (
    title: 'Resumen por área',
    detail: 'Ventas, servicios, clientes, inventario, compras y caja del período.',
    icon: Icons.dashboard_customize_outlined,
    color: Color(0xFF6366F1),
    types: ['ventas', 'servicios', 'clientes', 'inventario', 'compras', 'caja'],
  ),
  (
    title: 'Análisis',
    detail: 'Comparación con el período anterior, días y horas con más ventas y ventas por profesional.',
    icon: Icons.query_stats,
    color: Color(0xFFEC4899),
    types: ['analisis'],
  ),
  (
    title: 'Ganancias',
    detail: 'Ventas netas, costo de lo vendido, comisiones, gastos y ganancia neta con su margen.',
    icon: Icons.savings_outlined,
    color: Color(0xFF10B981),
    types: ['ganancias'],
  ),
];

class _ReportsScreenState extends State<ReportsScreen> {
  Set<String>? _available;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await context.read<Session>().api.get('/reports', {'meta': '1'}) as Map<String, dynamic>;
      if (mounted) setState(() => _available = {for (final t in (d['available'] as List).cast<Map<String, dynamic>>()) '${t['key']}'});
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _available;
    final cards = available == null ? const [] : _cards.where((c) => c.types.any(available.contains)).toList();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : available == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (cards.isEmpty) const EmptyView(text: 'No tienes reportes disponibles.', icon: Icons.insights_outlined),
                    for (final c in cards) ...[
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ReportViewScreen(title: c.title, types: c.types.where(available.contains).toList())),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(color: c.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                                child: Icon(c.icon, color: c.color),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(c.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text(c.detail, style: TextStyle(color: muted, fontSize: 13)),
                                ]),
                              ),
                              const Icon(Icons.chevron_right),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ]),
                ),
    );
  }
}
/// Vista de un reporte (o un grupo de ellos, como pestañas): indicadores y
/// tablas por período, los mismos de la web.
class ReportViewScreen extends StatefulWidget {
  const ReportViewScreen({super.key, required this.title, required this.types});

  final String title;

  /// Tipos del servidor que muestra esta vista (el primero es el inicial).
  final List<String> types;

  @override
  State<ReportViewScreen> createState() => _ReportViewScreenState();
}

class _ReportViewScreenState extends State<ReportViewScreen> {
  late DateTimeRange _range = _preset('month');
  String _preset_ = 'month';
  late String? _type = widget.types.first;
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
    // Solo los tipos de esta vista (el servidor devuelve todos los disponibles).
    final available = ((d?['available'] as List?) ?? const []).cast<Map<String, dynamic>>().where((t) => widget.types.contains(t['key'])).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
      if (report['note'] != null) ...[
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 16, color: muted),
          const SizedBox(width: 6),
          Expanded(child: Text('${report['note']}', style: TextStyle(color: muted, fontSize: 12))),
        ]),
      ],
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
