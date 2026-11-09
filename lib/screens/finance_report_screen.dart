import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

List<Map<String, dynamic>> _list(dynamic v) => ((v as List?) ?? const []).cast<Map<String, dynamic>>();

String _dmy(String ymd) => DateFormat('dd/MM/yyyy').format(DateTime.parse(ymd));

/// Reporte de finanzas: el dinero que entró y salió, en tres pestañas que
/// comparten el período.
class FinanceReportScreen extends StatefulWidget {
  const FinanceReportScreen({super.key});

  @override
  State<FinanceReportScreen> createState() => _FinanceReportScreenState();
}

class _FinanceReportScreenState extends State<FinanceReportScreen> {
  static const _presets = [
    ('hoy', 'Hoy'),
    ('semana', 'Esta semana'),
    ('semana_ant', 'Semana ant.'),
    ('mes', 'Este mes'),
    ('mes_ant', 'Mes ant.'),
    ('todo', 'Todo'),
  ];

  String _preset = 'mes';
  DateTimeRange? _custom;
  String? _range;

  Map<String, String> get _period => {
        if (_custom == null) 'preset': _preset,
        if (_custom != null) 'from': ymd(_custom!.start),
        if (_custom != null) 'to': ymd(_custom!.end),
      };

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(context: context, initialDateRange: _custom, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (picked != null && mounted) setState(() => _custom = picked);
  }

  /// «Desde el inicio — hoy», «Desde 25/08/2026 — hoy».
  void _onData(Map<String, dynamic> d) {
    final from = '${d['from']}', to = '${d['to']}';
    final isToday = to == ymd(DateTime.now());
    final end = isToday ? 'hoy' : _dmy(to);
    final text = d['all_time'] == true
        ? 'Desde el inicio — $end'
        : from == to
            ? _dmy(from)
            : 'Desde ${_dmy(from)} — $end';
    if (text != _range) setState(() => _range = text);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Finanzas'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.assignment_outlined), text: 'Resultados'),
            Tab(icon: Icon(Icons.swap_vert), text: 'Movimientos'),
            Tab(icon: Icon(Icons.lock_outline), text: 'Cierres'),
          ]),
        ),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final (key, label) in _presets)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _custom == null && _preset == key,
                    onSelected: (_) => setState(() {
                      _preset = key;
                      _custom = null;
                    }),
                  ),
                ),
              ChoiceChip(label: const Text('Rango'), selected: _custom != null, onSelected: (_) => _pickRange()),
            ]),
          ),
          if (_range != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(children: [
                Icon(Icons.calendar_today_outlined, size: 14, color: muted),
                const SizedBox(width: 6),
                Expanded(child: Text(_range!, style: TextStyle(color: muted, fontSize: 12.5))),
              ]),
            ),
          Expanded(
            child: TabBarView(children: [
              _ResultsTab(period: _period, onData: _onData),
              _MovementsTab(period: _period, onData: _onData),
              _ClosingsTab(period: _period, onData: _onData),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Carga de una pestaña: consulta otra vez cuando cambia el período o sus filtros,
/// y conserva lo cargado al pasar a otra pestaña.
abstract class _TabState<T extends _ReportTab> extends State<T> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? data;
  String? error;
  int _request = 0;

  String get tab;
  Map<String, String> get filters => const {};
  List<Widget> content(Map<String, dynamic> d, Color muted);

  String get cur => context.read<Session>().me?.company.currencySymbol ?? 'Bs';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant T old) {
    super.didUpdateWidget(old);
    if ('${old.period}' != '${widget.period}') load();
  }

  Future<void> load() async {
    final request = ++_request;
    setState(() => error = null);
    try {
      final d = await context.read<Session>().api.get('/reports/finance', {'tab': tab, ...widget.period, ...filters}) as Map<String, dynamic>;
      // Si ya se pidió otro período, esta respuesta llegó tarde: no se muestra.
      if (!mounted || request != _request) return;
      setState(() => data = d);
      widget.onData(d);
    } catch (e) {
      if (mounted && request == _request) setState(() => error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = data;
    if (error != null) return ErrorView(message: error!, onRetry: load);
    if (d == null) return const Center(child: CircularProgressIndicator());
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 2, 14, 24), children: content(d, muted)),
    );
  }
}

abstract class _ReportTab extends StatefulWidget {
  const _ReportTab({required this.period, required this.onData});

  final Map<String, String> period;
  final ValueChanged<Map<String, dynamic>> onData;
}

Widget _row(String label, String value, {Color? color, bool bold = false}) {
  final style = TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w500);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400))),
      const SizedBox(width: 10),
      Text(value, style: style),
    ]),
  );
}

// ------------------------------------------------------------------ Resultados

class _ResultsTab extends _ReportTab {
  const _ResultsTab({required super.period, required super.onData});

  @override
  State<_ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends _TabState<_ResultsTab> {
  @override
  String get tab => 'resultados';

  @override
  List<Widget> content(Map<String, dynamic> d, Color muted) {
    final profit = _n(d['profit']);
    final capital = (d['capital'] as Map).cast<String, dynamic>();
    final unregistered = (d['sales_without_cash'] as Map).cast<String, dynamic>();

    return [
      _side('Ingresos', 'Total ingresos', Icons.trending_up, Brand.success, (d['income'] as Map).cast<String, dynamic>(), muted),
      _side('Egresos', 'Total egresos', Icons.trending_down, Brand.danger, (d['expense'] as Map).cast<String, dynamic>(), muted),
      Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Resultado acumulado', style: TextStyle(color: muted, fontSize: 12.5)),
                Text(profit >= 0 ? 'Utilidad' : 'Pérdida', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(money(profit, cur), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: profit >= 0 ? Brand.success : Brand.danger)),
              ),
            ),
          ]),
        ),
      ),
      Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _row('Aportes de capital', money(_n(capital['added']), cur), bold: true),
            if (_n(capital['taken']) > 0) _row('Retiros', money(_n(capital['taken']), cur)),
            const SizedBox(height: 4),
            Text('Dinero que puso el dueño. No es ganancia: no entra en la utilidad.', style: TextStyle(color: muted, fontSize: 12.5)),
          ]),
        ),
      ),
      if (_n(unregistered['count']) > 0)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: Brand.warning.withValues(alpha: .12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, color: Brand.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_n(unregistered['count']).toInt()} venta(s) por ${money(_n(unregistered['amount']), cur)} se registraron sin caja abierta: no pasaron por caja y no están en estos ingresos.',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text('${d['note']}', style: TextStyle(color: muted, fontSize: 12)),
      ),
    ];
  }

  Widget _side(String title, String totalLabel, IconData icon, Color color, Map<String, dynamic> side, Color muted) {
    final rows = _list(side['rows']);
    final other = _n(side['otro']);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15)),
          ]),
          const SizedBox(height: 8),
          if (rows.isEmpty) Text('Sin movimientos en el período.', style: TextStyle(color: muted)),
          for (final r in rows) _row('${r['label']}', money(_n(r['amount']), cur)),
          const Divider(height: 18),
          _row(totalLabel, money(_n(side['total']), cur), color: color, bold: true),
          const SizedBox(height: 2),
          Text(
            'Caja ${money(_n(side['caja']), cur)}  ·  Tesorería ${money(_n(side['tesoreria']), cur)}${other > 0 ? '  ·  Sin origen ${money(other, cur)}' : ''}',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ]),
      ),
    );
  }
}

// ----------------------------------------------------------------- Movimientos

class _MovementsTab extends _ReportTab {
  const _MovementsTab({required super.period, required super.onData});

  @override
  State<_MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends _TabState<_MovementsTab> {
  static const _hints = {
    'caja': 'Movimientos de caja de todas las formas de pago. El cierre cuenta solo el efectivo.',
    'tesoreria': 'Solo movimientos de las cuentas, también las transferencias.',
    'todo': 'Caja y cuentas juntas, sin las transferencias entre ellas.',
  };

  String _scope = 'caja';
  String _dir = 'todos';

  @override
  String get tab => 'movimientos';

  @override
  Map<String, String> get filters => {'scope': _scope, 'dir': _dir};

  @override
  List<Widget> content(Map<String, dynamic> d, Color muted) {
    final s = (d['summary'] as Map).cast<String, dynamic>();
    final balance = _n(s['balance']);
    final categories = _list(d['categories']);
    final items = _list(d['items']);
    final count = _n(d['count']).toInt();

    final byDay = <String, List<Map<String, dynamic>>>{};
    for (final m in items) {
      byDay.putIfAbsent('${m['date']}', () => []).add(m);
    }

    return [
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'caja', label: Text('Caja')),
            ButtonSegment(value: 'tesoreria', label: Text('Tesorería')),
            ButtonSegment(value: 'todo', label: Text('Todo')),
          ],
          selected: {_scope},
          onSelectionChanged: (v) {
            setState(() => _scope = v.first);
            load();
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Text(_hints[_scope]!, style: TextStyle(color: muted, fontSize: 12.5)),
      ),
      Row(children: [
        _kpi('Ingresos', _n(s['income']), Brand.success, muted),
        const SizedBox(width: 6),
        _kpi('Egresos', _n(s['expense']), Brand.danger, muted),
        const SizedBox(width: 6),
        _kpi('Balance', balance, balance >= 0 ? Brand.success : Brand.danger, muted),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: [
        for (final (key, label) in const [('todos', 'Todos'), ('ingresos', 'Ingresos'), ('egresos', 'Egresos')])
          ChoiceChip(
            label: Text(label),
            selected: _dir == key,
            onSelected: (_) {
              setState(() => _dir = key);
              load();
            },
          ),
      ]),
      const SizedBox(height: 8),
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Por categoría', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (categories.isEmpty) Text('Sin movimientos en el período.', style: TextStyle(color: muted)),
            for (final c in categories) _category(c),
          ]),
        ),
      ),
      Text('Movimientos ($count)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      if (count > items.length)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('Se muestran los ${items.length} más recientes.', style: TextStyle(color: muted, fontSize: 12.5)),
        ),
      for (final entry in byDay.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 4),
          child: Text(longDay(DateTime.parse(entry.key)), style: TextStyle(color: muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: [for (final m in entry.value) _item(m, muted)]),
        ),
      ],
    ];
  }

  Widget _kpi(String label, double value, Color color, Color muted) => Expanded(
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(money(value, cur), style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              ),
            ]),
          ),
        ),
      );

  Widget _category(Map<String, dynamic> c) {
    final color = c['direction'] == 'in' ? Brand.success : Brand.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _row('${c['label']}', money(_n(c['amount']), cur)),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: _n(c['share']).clamp(0, 1).toDouble(), minHeight: 6, color: color, backgroundColor: color.withValues(alpha: .12)),
        ),
      ]),
    );
  }

  Widget _item(Map<String, dynamic> m, Color muted) {
    final isIn = m['direction'] == 'in';
    final cancelled = m['cancelled'] == true;
    final color = isIn ? Brand.success : Brand.danger;
    final detail = [m['category'], m['time'], m['origin'], m['method'], if (cancelled) 'Anulado'].where((v) => v != null && '$v'.isNotEmpty).join(' · ');
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: .14),
        child: Icon(isIn ? Icons.arrow_upward : Icons.arrow_downward, size: 17, color: color),
      ),
      title: Text('${m['concept']}', style: TextStyle(fontWeight: FontWeight.w600, decoration: cancelled ? TextDecoration.lineThrough : null)),
      subtitle: Text(detail, style: TextStyle(color: muted, fontSize: 12)),
      trailing: Text('${isIn ? '+' : '−'} ${money(_n(m['amount']), cur)}', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

// --------------------------------------------------------------------- Cierres

class _ClosingsTab extends _ReportTab {
  const _ClosingsTab({required super.period, required super.onData});

  @override
  State<_ClosingsTab> createState() => _ClosingsTabState();
}

class _ClosingsTabState extends _TabState<_ClosingsTab> {
  @override
  String get tab => 'cierres';

  String _at(dynamic v) => v == null ? '' : DateFormat('dd/MM HH:mm').format(DateTime.parse('$v'));

  @override
  List<Widget> content(Map<String, dynamic> d, Color muted) {
    final sessions = _list(d['sessions']);
    final count = _n(d['count']).toInt();
    if (sessions.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Center(child: Text('No hay turnos de caja en el período.', style: TextStyle(color: muted))),
        ),
      ];
    }
    return [
      if (count > sessions.length)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Se muestran los ${sessions.length} más recientes de $count.', style: TextStyle(color: muted, fontSize: 12.5)),
        ),
      for (final s in sessions) _session(s, muted),
    ];
  }

  Widget _session(Map<String, dynamic> s, Color muted) {
    final open = s['status'] == 'open';
    final others = _list(s['others']);
    final othersNet = _n(s['others_net']);
    // Cerrado antes de contar solo el efectivo: su esperado sumaba todas las formas.
    final legacy = s['legacy'] == true;
    final count = _list(s['count']);
    final name = [s['register'], s['branch']].where((v) => v != null && '$v'.isNotEmpty).join(' · ');
    final small = TextStyle(color: muted, fontSize: 12.5);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(width: 8),
            StatusPill(label: open ? 'Abierta' : 'Cerrada', color: open ? Brand.success : muted),
          ]),
          const SizedBox(height: 4),
          Text('Abrió ${s['opened_by'] ?? '—'} · ${_at(s['opened_at'])}', style: small),
          if (s['closed_at'] != null) Text('Cerró ${s['closed_by'] ?? '—'} · ${_at(s['closed_at'])}', style: small),
          const Divider(height: 18),
          _row('Apertura', money(_n(s['opening']), cur)),
          _row('Ingresos efectivo', money(_n(s['cash_in']), cur), color: Brand.success),
          _row('Egresos efectivo', money(_n(s['cash_out']), cur), color: Brand.danger),
          if (legacy && othersNet.abs() >= 0.005) _row('Otros medios', money(othersNet, cur)),
          const Divider(height: 18),
          _row(legacy ? 'Esperado en caja' : 'Esperado en efectivo', money(_n(s['expected']), cur), bold: true),
          if (s['counted'] != null) ...[
            _row('Contado', money(_n(s['counted']), cur)),
            _difference(_n(s['difference'])),
          ],
          if (count.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Conteo: ${count.map((c) => '${c['qty']} × ${_n(c['value']) == _n(c['value']).roundToDouble() ? _n(c['value']).toStringAsFixed(0) : _n(c['value']).toStringAsFixed(2)}').join(' · ')}', style: small),
          ],
          if (others.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Otros medios${legacy ? '' : ' (no se cuentan)'}: ${others.map((o) => '${o['method']} ${money(_n(o['amount']), cur)}').join(' · ')}', style: small),
          ],
        ]),
      ),
    );
  }

  Widget _difference(double diff) {
    if (diff.abs() < 0.005) return _row('Diferencia', 'Exacto', color: Brand.success, bold: true);
    return _row('Diferencia', '${diff > 0 ? 'Sobrante' : 'Faltante'} ${money(diff.abs(), cur)}', color: Brand.danger, bold: true);
  }
}
