import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/bar_chart.dart';
import '../widgets/common.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// 3 → «3», 2.5 → «2.5».
String _qty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

List<Map<String, dynamic>> _list(dynamic v) => ((v as List?) ?? const []).cast<Map<String, dynamic>>();

/// Análisis: una pestaña por área, con gráficos comparativos en monto o cantidad.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  List<Map<String, dynamic>>? _tabs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await context.read<Session>().api.get('/reports/analysis') as Map<String, dynamic>;
      if (mounted) setState(() => _tabs = _list(d['tabs']));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (tabs == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Análisis')),
        body: _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Análisis'),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: '${t['label']}')]),
        ),
        body: TabBarView(children: [for (final t in tabs) _AnalysisTab(tab: '${t['key']}')]),
      ),
    );
  }
}

/// Una pestaña: carga sus datos una vez y conserva el estado al cambiar de pestaña.
class _AnalysisTab extends StatefulWidget {
  const _AnalysisTab({required this.tab});

  final String tab;

  @override
  State<_AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<_AnalysisTab> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _d;
  String? _error;
  bool _byAmount = true;
  bool _byMonth = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await context.read<Session>().api.get('/reports/analysis', {'tab': widget.tab}) as Map<String, dynamic>;
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  String get _cur => '${_d?['currency'] ?? 'Bs'}';
  String get _key => _byAmount ? 'amount' : 'count';
  String get _prevKey => _byAmount ? 'prev_amount' : 'prev_count';
  String _fmt(double v) => _byAmount ? money(v, _cur) : _qty(v);

  /// Nombre de la cantidad en cada pestaña.
  String get _countLabel => switch (widget.tab) {
        'ventas' => 'N.º de ventas',
        'compras' => 'N.º de compras',
        _ => 'Cantidad',
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = _d;
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if (d == null) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 24), children: switch (widget.tab) {
        'personal' => _personal(d),
        'top' => _top(d),
        _ => _series(d),
      }),
    );
  }

  Widget _toggle() => SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: true, label: Text('Monto ($_cur)')),
          ButtonSegment(value: false, label: Text(_countLabel)),
        ],
        selected: {_byAmount},
        onSelectionChanged: (s) => setState(() => _byAmount = s.first),
      );

  Widget _kpis(Map<String, dynamic> kpis) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _KpiCard(title: 'Semana', value: _fmt(_n((kpis['week'] as Map)[_key])), current: _n((kpis['week'] as Map)[_key]), previous: _n((kpis['week'] as Map)[_prevKey]))),
          const SizedBox(width: 8),
          Expanded(child: _KpiCard(title: 'Mes', value: _fmt(_n((kpis['month'] as Map)[_key])), current: _n((kpis['month'] as Map)[_key]), previous: _n((kpis['month'] as Map)[_prevKey]))),
        ]),
      );

  List<Widget> _series(Map<String, dynamic> d) {
    final hours = d['hours'] == null ? null : _list(d['hours']);
    const prev = Brand.soft;
    const now = Brand.primary;
    final sorted = hours == null ? null : ([...hours]..sort((a, b) => _n(b[_key]).compareTo(_n(a[_key]))));

    return [
      _toggle(),
      const SizedBox(height: 10),
      _kpis((d['kpis'] as Map).cast<String, dynamic>()),
      const SizedBox(height: 8),
      BarChartCard(
        title: 'Semana anterior vs. actual (por día)',
        series: const [ChartSeries('Semana anterior', prev), ChartSeries('Semana actual', now)],
        groups: [for (final r in _list(d['by_day'])) ChartGroup('${r['label']}', [_n(r[_prevKey]), _n(r[_key])])],
        format: _fmt,
      ),
      BarChartCard(
        title: 'Comparativa semanal (últimas 8)',
        series: const [ChartSeries('', now)],
        groups: [for (final r in _list(d['weeks'])) ChartGroup('${r['label']}', [_n(r[_key])])],
        format: _fmt,
      ),
      BarChartCard(
        title: 'Comparativa mensual (últimos 6)',
        series: const [ChartSeries('', now)],
        groups: [for (final r in _list(d['months'])) ChartGroup('${r['label']}', [_n(r[_key])])],
        format: _fmt,
      ),
      if (sorted != null)
        RankingCard(
          title: 'Horas con más ventas',
          subtitle: 'Este mes',
          color: Brand.rose,
          rows: [for (final h in sorted) ('${h['label']}', _n(h[_key]), _fmt(_n(h[_key])))],
        ),
    ];
  }

  List<Widget> _personal(Map<String, dynamic> d) {
    final people = _list(d['people']);
    String first(Map<String, dynamic> p) => '${p['name']}'.split(' ').first;
    Map period(Map<String, dynamic> p, String name) => p[name] as Map;

    return [
      _toggle(),
      const SizedBox(height: 10),
      _kpis((d['kpis'] as Map).cast<String, dynamic>()),
      const SizedBox(height: 8),
      if (people.isEmpty) const Padding(padding: EdgeInsets.only(top: 32), child: EmptyView(text: 'Sin ventas del personal en este período.', icon: Icons.groups_outlined)),
      if (people.isNotEmpty) ...[
        BarChartCard(
          title: 'Semana anterior vs. actual',
          series: const [ChartSeries('Semana anterior', Brand.soft), ChartSeries('Semana actual', Brand.primary)],
          groups: [for (final p in people.take(8)) ChartGroup(first(p), [_n(period(p, 'week')[_prevKey]), _n(period(p, 'week')[_key])])],
          format: _fmt,
        ),
        BarChartCard(
          title: 'Mes anterior vs. actual',
          series: const [ChartSeries('Mes anterior', Brand.soft), ChartSeries('Mes actual', Brand.primary)],
          groups: [for (final p in people.take(8)) ChartGroup(first(p), [_n(period(p, 'month')[_prevKey]), _n(period(p, 'month')[_key])])],
          format: _fmt,
        ),
        const SizedBox(height: 4),
        const Text('Este mes', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 4),
        for (final p in people) _personCard(p),
      ],
    ];
  }

  Widget _personCard(Map<String, dynamic> p) {
    final month = p['month'] as Map;
    final current = _n(month[_key]);
    final previous = _n(month[_prevKey]);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final details = [
      '${_qty(_n(month['count']))} servicio(s)',
      if (p['commissions'] != null) 'Comisiones ${money(_n(p['commissions']), _cur)}',
    ].join(' · ');
    return Card(
      child: ListTile(
        leading: Avatar(name: '${p['name']}'),
        title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(details, style: TextStyle(color: muted)),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_fmt(current), style: const TextStyle(fontWeight: FontWeight.w800)),
          _Delta(current: current, previous: previous, short: true),
        ]),
      ),
    );
  }

  List<Widget> _top(Map<String, dynamic> d) {
    final data = (d[_byMonth ? 'month' : 'week'] as Map).cast<String, dynamic>();
    List<(String, double, String)> rows(String key) {
      final list = [..._list(data[key])]..sort((a, b) => _n(b[_key]).compareTo(_n(a[_key])));
      return [for (final r in list) ('${r['name']}', _n(r[_key]), _fmt(_n(r[_key])))];
    }

    return [
      _toggle(),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: const [ButtonSegment(value: false, label: Text('Esta semana')), ButtonSegment(value: true, label: Text('Este mes'))],
        selected: {_byMonth},
        onSelectionChanged: (s) => setState(() => _byMonth = s.first),
      ),
      const SizedBox(height: 8),
      RankingCard(title: 'Servicios más vendidos', color: Brand.primary, rows: rows('services')),
      RankingCard(title: 'Productos más vendidos', color: Brand.rose, rows: rows('products')),
      RankingCard(title: 'Mejores clientes', subtitle: _byAmount ? null : 'Por número de ventas', color: Brand.success, rows: rows('clients')),
    ];
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.title, required this.value, required this.current, required this.previous});

  final String title;
  final String value;
  final double current;
  final double previous;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Brand.primary))),
          const SizedBox(height: 4),
          _Delta(current: current, previous: previous),
        ]),
      ),
    );
  }
}

/// Variación contra el período anterior.
class _Delta extends StatelessWidget {
  const _Delta({required this.current, required this.previous, this.short = false});

  final double current;
  final double previous;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final suffix = short ? '' : ' vs anterior';
    if (previous == 0) {
      return Text(current > 0 ? 'Sin dato anterior' : 'Sin movimiento', style: TextStyle(color: muted, fontSize: 12));
    }
    final change = (current - previous) * 100 / previous.abs();
    final up = change >= 0;
    final color = up ? Brand.success : Brand.danger;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(up ? Icons.trending_up : Icons.trending_down, size: 15, color: color),
      const SizedBox(width: 3),
      Flexible(child: Text('${up ? '+' : ''}${change.toStringAsFixed(0)}%$suffix', overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 12))),
    ]);
  }
}
