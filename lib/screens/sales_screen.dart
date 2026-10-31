import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'pos_screen.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

const _statusLabels = {'anulada': ('Anulada', Brand.danger), 'credito': ('A crédito', Brand.warning), 'completada': ('Cobrada', Brand.success)};

/// Ventas del día: las propias o (con permiso) las de todo el salón.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  DateTime _day = dateOnly(DateTime.now());
  bool _mine = true;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Quien ve todas las ventas arranca viendo las del salón.
    _mine = !(context.read<Session>().me?.can('sales_view') ?? false);
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await context.read<Session>().api.get('/sales', {'date': ymd(_day), if (_mine) 'mine': '1'});
      if (mounted) setState(() => _data = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  void _shift(int days) {
    setState(() {
      _day = _day.add(Duration(days: days));
      _data = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    final d = _data;
    final today = sameDay(_day, DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Ventas')),
      floatingActionButton: me.can('sales_create')
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen()));
                _load();
              },
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Cobrar'),
            )
          : null,
      body: Column(children: [
        Row(children: [
          IconButton(tooltip: 'Día anterior', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text(today ? 'Hoy' : longDay(_day), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          IconButton(tooltip: 'Día siguiente', onPressed: today ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
        ]),
        if (me.can('sales_view'))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Del salón')), ButtonSegment(value: true, label: Text('Mías'))],
              selected: {_mine},
              onSelectionChanged: (v) {
                setState(() {
                  _mine = v.first;
                  _data = null;
                });
                _load();
              },
            ),
          ),
        Expanded(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : d == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(onRefresh: _load, child: _list(d)),
        ),
      ]),
    );
  }

  Widget _list(Map<String, dynamic> d) {
    final cur = '${d['currency']}';
    final totals = d['totals'] as Map<String, dynamic>;
    final sales = (d['sales'] as List).cast<Map<String, dynamic>>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(money(_n(totals['total']), cur), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            Text('${totals['count']} venta(s)${_n(totals['tips']) > 0 ? ' · propinas ${money(_n(totals['tips']), cur)}' : ''}', style: TextStyle(color: muted)),
            for (final m in (totals['by_method'] as List).cast<Map<String, dynamic>>())
              Text('${m['method']}: ${money(_n(m['amount']), cur)}', style: const TextStyle(fontSize: 13)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (sales.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 40), child: EmptyView(text: 'No hay ventas este día.', icon: Icons.receipt_long_outlined))
      else
        Card(
          child: Column(children: [
            for (final (i, s) in sales.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                title: Text('${s['client']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${s['number']} · ${hm(wallTime(s['at'] as String))} · ${s['method']}'),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(money(_n(s['total']), cur),
                      style: TextStyle(fontWeight: FontWeight.w800, decoration: s['status'] == 'anulada' ? TextDecoration.lineThrough : null)),
                  if (s['status'] != 'completada') Text(_statusLabels[s['status']]?.$1 ?? '', style: TextStyle(fontSize: 11, color: _statusLabels[s['status']]?.$2)),
                ]),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: s['id'] as int))),
              ),
            ],
          ]),
        ),
    ]);
  }
}

/// Detalle de una venta. Tras cobrar se abre con la venta recién creada.
class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({super.key, this.sale, this.saleId, this.justCreated = false}) : assert(sale != null || saleId != null);

  final Map<String, dynamic>? sale;
  final int? saleId;
  final bool justCreated;

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  Map<String, dynamic>? _sale;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sale = widget.sale;
    if (_sale == null) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await context.read<Session>().api.get('/sales/${widget.saleId}');
      if (mounted) setState(() => _sale = s as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _sale;
    return Scaffold(
      appBar: AppBar(title: Text(s == null ? 'Venta' : 'Venta ${s['number']}')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : s == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: _content(s)),
      bottomNavigationBar: widget.justCreated
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PosScreen())),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva venta'),
                ),
              ),
            )
          : null,
    );
  }

  List<Widget> _content(Map<String, dynamic> s) {
    final cur = '${s['currency']}';
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final items = (s['items'] as List).cast<Map<String, dynamic>>();
    final status = _statusLabels[s['status']];
    Widget row(String label, double value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 18 : 14))),
            Text(money(value, cur), style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 18 : 14, color: color)),
          ]),
        );

    return [
      if (widget.justCreated)
        Card(
          color: Brand.success.withValues(alpha: .1),
          child: const ListTile(
            leading: Icon(Icons.check_circle, color: Brand.success, size: 32),
            title: Text('¡Venta cobrada!', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      if (widget.justCreated) const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text('${s['client']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        if (status != null) StatusPill(label: status.$1, color: status.$2),
      ]),
      Text('${longDay(wallTime(s['at'] as String))} · ${hm(wallTime(s['at'] as String))}', style: TextStyle(color: muted)),
      const SizedBox(height: 12),
      Card(
        child: Column(children: [
          for (final (i, it) in items.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              dense: true,
              title: Text('${it['description']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([
                '${_n(it['quantity']) % 1 == 0 ? _n(it['quantity']).toInt() : it['quantity']} × ${money(_n(it['unit_price']), cur)}',
                if (it['specialist'] != null) '${it['specialist']}',
                if (it['session'] == true) 'Sesión incluida',
              ].join(' · ')),
              trailing: Text(money(_n(it['total']), cur), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            row('Subtotal', _n(s['subtotal'])),
            if (_n(s['discounts']) > 0) row('Descuentos', -_n(s['discounts']), color: Brand.success),
            if (_n(s['tax']) > 0) row('Impuesto', _n(s['tax'])),
            row('Total', _n(s['total']), bold: true),
            if (_n(s['tip']) > 0) row('Propina', _n(s['tip'])),
            if (_n(s['credit_applied']) > 0) row('Pagado con saldo a favor', _n(s['credit_applied'])),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Column(children: [
          ListTile(dense: true, leading: const Icon(Icons.payments_outlined), title: Text('${s['method']}')),
          if (s['cash'] != null) ListTile(dense: true, leading: const Icon(Icons.point_of_sale), title: Text('${s['cash']}')),
          if (s['coupon'] != null) ListTile(dense: true, leading: const Icon(Icons.local_offer_outlined), title: Text('Cupón ${s['coupon']}')),
          if (_n(s['points_redeemed']) > 0) ListTile(dense: true, leading: const Icon(Icons.stars_outlined), title: Text('${_n(s['points_redeemed']).toInt()} puntos canjeados')),
        ]),
      ),
    ];
  }
}
