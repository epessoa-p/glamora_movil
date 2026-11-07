import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

String _qty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Ganancias: cuánto queda de lo vendido después del costo de los productos y
/// las comisiones, de productos, servicios o ambos.
class ProfitScreen extends StatefulWidget {
  const ProfitScreen({super.key});

  @override
  State<ProfitScreen> createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  static const _presets = [('hoy', 'Hoy'), ('semana', 'Esta semana'), ('semana_ant', 'Semana ant.'), ('mes', 'Este mes'), ('mes_ant', 'Mes ant.')];

  String _preset = 'mes';
  DateTimeRange? _custom;
  String _scope = 'ambos';
  final _lowMargin = <String, bool>{};
  Map<String, dynamic>? _d;
  String? _error;

  String get _cur => context.read<Session>().me?.company.currencySymbol ?? 'Bs';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await context.read<Session>().api.get('/reports/profit', {
        'scope': _scope,
        if (_custom == null) 'preset': _preset,
        if (_custom != null) 'from': ymd(_custom!.start),
        if (_custom != null) 'to': ymd(_custom!.end),
      });
      if (mounted) setState(() => _d = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(context: context, initialDateRange: _custom, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (picked == null || !mounted) return;
    setState(() => _custom = picked);
    _load();
  }

  Color _tone(double v) => v >= 0 ? Brand.success : Brand.danger;
  String _pct(dynamic v) => '${_n(v).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Ganancias')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final (key, label) in _presets)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(label),
                  selected: _custom == null && _preset == key,
                  onSelected: (_) {
                    setState(() {
                      _preset = key;
                      _custom = null;
                    });
                    _load();
                  },
                ),
              ),
            ChoiceChip(label: const Text('Elegir'), selected: _custom != null, onSelected: (_) => _pickRange()),
          ]),
        ),
        if (d != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('${d['from']}  —  ${d['to']}', style: TextStyle(color: muted, fontSize: 12.5)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'ambos', label: Text('Ambos'), icon: Icon(Icons.join_full, size: 18)),
              ButtonSegment(value: 'productos', label: Text('Productos'), icon: Icon(Icons.shopping_cart_outlined, size: 18)),
              ButtonSegment(value: 'servicios', label: Text('Servicios'), icon: Icon(Icons.content_cut, size: 18)),
            ],
            selected: {_scope},
            onSelectionChanged: (s) {
              setState(() => _scope = s.first);
              _load();
            },
          ),
        ),
        Expanded(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : d == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 24), children: _content(d, muted))),
        ),
      ]),
    );
  }

  List<Widget> _content(Map<String, dynamic> d, Color muted) {
    final s = (d['summary'] as Map).cast<String, dynamic>();
    final profit = _n(s['profit']);
    final productRank = d['product_rank'] as Map?;
    final serviceRank = d['service_rank'] as Map?;
    final days = (d['days'] as List).cast<Map<String, dynamic>>();
    final sales = (d['sales'] as List).cast<Map<String, dynamic>>();

    return [
      Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ganancia', style: TextStyle(color: muted)),
                  const SizedBox(height: 2),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(money(profit, _cur), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _tone(profit)))),
                ]),
              ),
              StatusPill(label: 'Margen ${_pct(s['margin'])}', color: _tone(profit)),
            ]),
            const Divider(height: 24),
            Row(children: [
              Expanded(child: _figure('Ingresos', _n(s['revenue']), muted)),
              Expanded(child: _figure('Costo', _n(s['cost']), muted)),
            ]),
          ]),
        ),
      ),
      if (_scope != 'servicios') _bucket('Productos', Icons.shopping_cart_outlined, (d['products'] as Map).cast<String, dynamic>(), muted, costLabel: 'Costo de productos'),
      if (_scope != 'productos') _bucket('Servicios', Icons.content_cut, (d['services'] as Map).cast<String, dynamic>(), muted),
      if (d['net'] != null) _net((d['net'] as Map).cast<String, dynamic>(), profit, muted),
      _titled(
        'Por día',
        Icons.calendar_month_outlined,
        muted,
        children: [
          if (days.isEmpty) Text('Sin ventas en el período.', style: TextStyle(color: muted)),
          for (final x in days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(width: 92, child: Text(shortDay(DateTime.parse('${x['date']}')), style: const TextStyle(fontWeight: FontWeight.w700))),
                Expanded(child: Text('Vendido ${money(_n(x['sold']), _cur)}', overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 12.5))),
                Text(money(_n(x['profit']), _cur), style: TextStyle(fontWeight: FontWeight.w800, color: _tone(_n(x['profit'])))),
              ]),
            ),
        ],
      ),
      if (productRank != null) _rank('Productos', productRank.cast<String, dynamic>(), muted),
      if (serviceRank != null) _rank('Servicios', serviceRank.cast<String, dynamic>(), muted),
      _titled(
        'Ventas',
        Icons.receipt_long_outlined,
        muted,
        trailing: '${d['sales_count']} registros',
        children: [
          if (sales.isEmpty) Text('Sin ventas en el período.', style: TextStyle(color: muted)),
          for (final (i, r) in sales.indexed) ...[
            if (i > 0) const Divider(height: 18),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['number']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('${r['at']} · ${r['client']}', style: TextStyle(color: muted, fontSize: 12.5)),
                  Text('Vendido ${money(_n(r['sold']), _cur)} · costo ${money(_n(r['cost']), _cur)}', style: TextStyle(color: muted, fontSize: 12.5)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(_n(r['profit']), _cur), style: TextStyle(fontWeight: FontWeight.w800, color: _tone(_n(r['profit'])))),
                Text(_pct(r['margin']), style: TextStyle(color: _tone(_n(r['margin'])), fontSize: 12.5)),
              ]),
            ]),
          ],
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Text('${d['note']}', style: TextStyle(color: muted, fontSize: 12)),
      ),
    ];
  }

  Widget _figure(String label, double value, Color muted) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: muted, fontSize: 12.5)),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(money(value, _cur), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
      ]);

  Widget _titled(String title, IconData icon, Color muted, {String? trailing, required List<Widget> children}) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 20, color: Brand.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              if (trailing != null) Text(trailing, style: TextStyle(color: muted, fontSize: 12.5)),
            ]),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );

  Widget _line(String label, String value, Color? color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: color))),
          Text(value, style: TextStyle(color: color)),
        ]),
      );

  Widget _bucket(String title, IconData icon, Map<String, dynamic> b, Color muted, {String? costLabel}) {
    final profit = _n(b['profit']);
    return _titled(title, icon, muted, trailing: '${b['count']} ventas', children: [
      _line('Ingresos', money(_n(b['revenue']), _cur), null),
      if (costLabel != null) _line(costLabel, '− ${money(_n(b['cost']), _cur)}', muted),
      _line('Comisiones', '− ${money(_n(b['commissions']), _cur)}', muted),
      const Divider(height: 16),
      Row(children: [
        const Expanded(child: Text('Ganancia', style: TextStyle(fontWeight: FontWeight.w800))),
        Text(money(profit, _cur), style: TextStyle(fontWeight: FontWeight.w800, color: _tone(profit))),
        const SizedBox(width: 6),
        Text('(${_pct(b['margin'])})', style: TextStyle(color: _tone(profit), fontSize: 12.5)),
      ]),
    ]);
  }

  Widget _net(Map<String, dynamic> n, double profit, Color muted) {
    final net = _n(n['profit']);
    return _titled('Después de gastos', Icons.savings_outlined, muted, children: [
      _line('Ganancia', money(profit, _cur), null),
      _line('Gastos operativos', '− ${money(_n(n['expenses']), _cur)}', muted),
      const Divider(height: 16),
      Row(children: [
        const Expanded(child: Text('Ganancia neta', style: TextStyle(fontWeight: FontWeight.w800))),
        Text(money(net, _cur), style: TextStyle(fontWeight: FontWeight.w800, color: _tone(net))),
      ]),
    ]);
  }

  Widget _rank(String title, Map<String, dynamic> rank, Color muted) {
    final low = _lowMargin[title] ?? false;
    final rows = (rank[low ? 'low' : 'top'] as List).cast<Map<String, dynamic>>();
    return _titled(title, Icons.emoji_events_outlined, muted, children: [
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: false, label: Text('Más ganancia')), ButtonSegment(value: true, label: Text('Margen bajo'))],
          selected: {low},
          onSelectionChanged: (s) => setState(() => _lowMargin[title] = s.first),
        ),
      ),
      const SizedBox(height: 10),
      if (rows.isEmpty) Text('Sin datos en el período.', style: TextStyle(color: muted)),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${_qty(_n(r['qty']))} u. · vendido ${money(_n(r['sold']), _cur)}', style: TextStyle(color: muted, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(_n(r['profit']), _cur), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(_pct(r['margin']), style: TextStyle(color: _tone(_n(r['margin'])), fontSize: 12.5)),
            ]),
          ]),
        ),
    ]);
  }
}
