import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

String _qty(dynamic v) {
  final d = _n(v);
  return d == d.roundToDouble() ? NumberFormat('#,##0', 'en_US').format(d) : NumberFormat('#,##0.##', 'en_US').format(d);
}

List<Map<String, dynamic>> _list(dynamic v) => ((v as List?) ?? const []).cast<Map<String, dynamic>>();

/// Inventario de hoy: cuánto hay, cuánto vale y qué requiere atención.
class InventoryReportScreen extends StatefulWidget {
  const InventoryReportScreen({super.key});

  @override
  State<InventoryReportScreen> createState() => _InventoryReportScreenState();
}

class _InventoryReportScreenState extends State<InventoryReportScreen> {
  /// Cuántas filas se ven de cada lista antes de pedir «Ver todos».
  static const _preview = 5;

  int? _warehouse;
  Map<String, dynamic>? _d;
  String? _error;
  int _request = 0;
  final _expanded = <String>{};

  String get _cur => context.read<Session>().me?.company.currencySymbol ?? 'Bs';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() => _error = null);
    try {
      final d = await context.read<Session>().api.get('/reports/inventory', {if (_warehouse != null) 'warehouse_id': '$_warehouse'});
      if (mounted && request == _request) setState(() => _d = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Inventario')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 24), children: _content(d, muted)),
                ),
    );
  }

  List<Widget> _content(Map<String, dynamic> d, Color muted) {
    final s = (d['summary'] as Map).cast<String, dynamic>();
    final warehouses = _list(d['warehouses']);
    final categories = _list(d['categories']);
    final noCost = _n(d['no_cost']).toInt();
    final belowCost = (d['below_cost'] as Map).cast<String, dynamic>();

    return [
      if (warehouses.length > 1)
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: const Text('Todos'), selected: _warehouse == null, onSelected: (_) => _pick(null)),
            ),
            for (final w in warehouses)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text('${w['name']}'), selected: _warehouse == w['id'], onSelected: (_) => _pick(w['id'] as int)),
              ),
          ]),
        ),
      Row(children: [
        _kpi('PRODUCTOS', _qty(s['products']), Icons.inventory_2_outlined, muted),
        const SizedBox(width: 8),
        _kpi('UNIDADES', _qty(s['units']), Icons.layers_outlined, muted),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _kpi('VALOR A COSTO', money(_n(s['cost']), _cur), Icons.receipt_long_outlined, muted),
        const SizedBox(width: 8),
        _kpi('VALOR A VENTA', money(_n(s['sale']), _cur), Icons.sell_outlined, muted, color: Brand.success),
      ]),
      const SizedBox(height: 8),
      _profit(s),
      if (noCost > 0) _warning('$noCost producto(s) con existencias no tienen costo cargado: la ganancia potencial sale más alta de lo real.'),
      const SizedBox(height: 14),
      const _Title('Por categoría'),
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (categories.isEmpty) Text('No hay productos activos.', style: TextStyle(color: muted)),
            for (final c in categories) _category(c, muted),
          ]),
        ),
      ),
      _restock((d['restock'] as Map).cast<String, dynamic>(), muted),
      _idle((d['idle'] as Map).cast<String, dynamic>(), muted),
      if (_n(belowCost['count']) > 0) _below(belowCost, muted),
    ];
  }

  void _pick(int? id) {
    setState(() => _warehouse = id);
    _load();
  }

  Widget _kpi(String label, String value, IconData icon, Color muted, {Color? color}) => Expanded(
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 16, color: muted),
                const SizedBox(width: 6),
                Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
              ),
            ]),
          ),
        ),
      );

  Widget _profit(Map<String, dynamic> s) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Brand.primary, Brand.rose], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.trending_up, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Expanded(child: Text('GANANCIA POTENCIAL', overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(money(_n(s['profit']), _cur), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text('Margen ${_n(s['margin']).toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
      );

  Widget _warning(String text) => Card(
        margin: const EdgeInsets.only(top: 8),
        color: Brand.warning.withValues(alpha: .12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_rounded, color: Brand.warning, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
          ]),
        ),
      );

  Widget _category(Map<String, dynamic> c, Color muted) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text('${c['name']}')),
            const SizedBox(width: 10),
            Text(money(_n(c['sale']), _cur), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 2),
          Text('${_qty(c['products'])} ${_n(c['products']) == 1 ? 'producto' : 'productos'} · ${_qty(c['units'])} unid. · costo ${money(_n(c['cost']), _cur)}', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: _n(c['share']).clamp(0, 1).toDouble(), minHeight: 6, color: Brand.primary, backgroundColor: Brand.soft.withValues(alpha: .5)),
          ),
        ]),
      );

  /// Tarjeta con encabezado y lista corta que se puede abrir completa.
  Widget _section({
    required String id,
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> head,
    required List<Map<String, dynamic>> items,
    required int total,
    required String emptyText,
    required Widget Function(Map<String, dynamic>) row,
    required Color muted,
  }) {
    final open = _expanded.contains(id);
    final shown = open ? items : items.take(_preview).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          ]),
          const SizedBox(height: 6),
          ...head,
          if (items.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(emptyText, style: TextStyle(color: muted))),
          for (final item in shown) ...[const Divider(height: 14), row(item)],
          if (items.length > _preview)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => open ? _expanded.remove(id) : _expanded.add(id)),
                child: Text(open ? 'Ver menos' : 'Ver todos (${items.length})'),
              ),
            ),
          if (open && total > items.length)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Y ${total - items.length} más.', style: TextStyle(color: muted, fontSize: 12.5)),
            ),
        ]),
      ),
    );
  }

  Widget _rowText(String title, String detail, Color muted, {Color? color, Widget? trailing}) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            Text(detail, style: TextStyle(color: muted, fontSize: 12)),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing],
      ]);

  Widget _restock(Map<String, dynamic> r, Color muted) {
    final out = _n(r['out']).toInt(), low = _n(r['low']).toInt();
    return _section(
      id: 'restock',
      title: 'Para reponer',
      icon: Icons.add_shopping_cart,
      color: Brand.danger,
      muted: muted,
      head: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          StatusPill(label: '$out ${out == 1 ? 'agotado' : 'agotados'}', color: Brand.danger),
          StatusPill(label: '$low con stock bajo', color: Brand.warning),
        ]),
        const SizedBox(height: 6),
        Text('Llegar al mínimo cuesta ${money(_n(r['cost']), _cur)}.', style: TextStyle(color: muted, fontSize: 12.5)),
        if (_warehouse != null)
          Text('Se calcula con el total de todos los almacenes, porque el mínimo es por producto.', style: TextStyle(color: muted, fontSize: 12)),
      ],
      items: _list(r['items']),
      total: _n(r['count']).toInt(),
      emptyText: 'Nada por reponer.',
      row: (p) => _rowText(
        '${p['name']}',
        'Stock ${_qty(p['stock'])} · mínimo ${_qty(p['min'])}',
        muted,
        color: p['status'] == 'agotado' ? Brand.danger : null,
        trailing: _n(p['missing']) > 0
            ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Faltan ${_qty(p['missing'])}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(money(_n(p['cost']), _cur), style: TextStyle(color: muted, fontSize: 12)),
              ])
            : null,
      ),
    );
  }

  Widget _idle(Map<String, dynamic> r, Color muted) => _section(
        id: 'idle',
        title: 'Sin movimiento',
        icon: Icons.hourglass_bottom,
        color: Brand.warning,
        muted: muted,
        head: [
          Text(
            'Sin salidas en ${_qty(r['days'])} días: ${money(_n(r['value']), _cur)} detenidos en ${_qty(r['count'])} producto(s).',
            style: TextStyle(color: muted, fontSize: 12.5),
          ),
        ],
        items: _list(r['items']),
        total: _n(r['count']).toInt(),
        emptyText: 'Todo se está moviendo.',
        row: (p) => _rowText(
          '${p['name']}',
          '${_qty(p['units'])} unid. · ${p['last_exit'] == null ? 'nunca ha salido' : 'última salida ${DateFormat('dd/MM/yyyy').format(DateTime.parse('${p['last_exit']}'))}'}',
          muted,
          trailing: Text(money(_n(p['value']), _cur), style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );

  Widget _below(Map<String, dynamic> r, Color muted) => _section(
        id: 'below',
        title: 'Precio por debajo del costo',
        icon: Icons.money_off_csred_outlined,
        color: Brand.danger,
        muted: muted,
        head: [Text('${_qty(r['count'])} producto(s) se venden sin ganar nada o perdiendo.', style: TextStyle(color: muted, fontSize: 12.5))],
        items: _list(r['items']),
        total: _n(r['count']).toInt(),
        emptyText: '',
        row: (p) => _rowText(
          '${p['name']}',
          'Costo ${money(_n(p['cost']), _cur)}',
          muted,
          trailing: Text('Precio ${money(_n(p['price']), _cur)}', style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      );
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      );
}
