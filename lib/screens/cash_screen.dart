import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// 200 → «200», 0.5 → «0.50».
String _denom(dynamic v) {
  final d = _n(v);
  return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
}

/// Cierre contando billetes y monedas: cantidad por denominación, con el total
/// y la diferencia en vivo. El servidor vuelve a calcular el total.
class _CashCountScreen extends StatefulWidget {
  const _CashCountScreen({required this.denominations, required this.expected, required this.currency, required this.submit});

  final List<Map<String, dynamic>> denominations;
  final double expected;
  final String currency;
  final Future<Map<String, dynamic>> Function(List<Map<String, dynamic>> count) submit;

  @override
  State<_CashCountScreen> createState() => _CashCountScreenState();
}

class _CashCountScreenState extends State<_CashCountScreen> {
  late final _qty = [for (final _ in widget.denominations) TextEditingController()];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _qty) {
      c.dispose();
    }
    super.dispose();
  }

  int _q(int i) => int.tryParse(_qty[i].text.trim()) ?? 0;

  /// En centavos, para que 3 × 0.10 dé 0.30 exacto.
  int get _cents {
    var total = 0;
    for (var i = 0; i < widget.denominations.length; i++) {
      total += (_n(widget.denominations[i]['value']) * 100).round() * _q(i);
    }
    return total;
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final count = [
        for (var i = 0; i < widget.denominations.length; i++)
          if (_q(i) > 0) {'value': widget.denominations[i]['value'], 'qty': _q(i)},
      ];
      final res = await widget.submit(count);
      if (mounted) Navigator.pop(context, res);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final total = _cents / 100;
    final diffCents = _cents - (widget.expected * 100).round();
    final diff = diffCents / 100;
    final exact = diffCents == 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Contar efectivo')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        Text('Efectivo esperado: ${money(widget.expected, widget.currency)}', style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('Cuenta solo el efectivo: las demás formas de pago no se cuentan.', style: TextStyle(color: muted, fontSize: 12.5)),
        const SizedBox(height: 8),
        for (final (i, d) in widget.denominations.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(d['kind'] == 'billete' ? Icons.payments_outlined : Icons.toll_outlined, color: muted, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('${d['kind'] == 'billete' ? 'Billete' : 'Moneda'} de ${_denom(d['value'])}')),
              SizedBox(
                width: 90,
                child: TextField(
                  key: ValueKey('qty-${d['value']}'),
                  controller: _qty[i],
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.end,
                  decoration: const InputDecoration(hintText: '0', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
          ),
        const Divider(height: 24),
        Row(children: [
          const Expanded(child: Text('Total contado', style: TextStyle(fontWeight: FontWeight.w700))),
          Text(money(total, widget.currency), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const Expanded(child: Text('Diferencia')),
          Text(
            exact ? 'Exacto' : '${diff > 0 ? 'Sobrante' : 'Faltante'} ${money(diff.abs(), widget.currency)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: exact ? Brand.success : Brand.danger),
          ),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: const Icon(Icons.lock_outline),
          label: const Text('Cerrar caja'),
        ),
      ]),
    );
  }
}

/// Abre la caja: con un solo turno abierto va directo a él; si no, al listado
/// (para abrir una o elegir entre varias). Al volver actualiza el distintivo.
Future<void> openCashFlow(BuildContext context) async {
  final session = context.read<Session>();
  final open = session.openCash;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => open.length == 1 ? CashSessionScreen(sessionId: open.first.id) : const CashScreen()),
  );
  await session.refreshCash();
}

/// Cajas del salón: cuáles están abiertas y con cuánto.
class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  ApiClient get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await _api.get('/cash');
      if (mounted) setState(() => _data = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _open(Map<String, dynamic> register) async {
    final cur = '${_data!['currency']}';
    final session = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AmountDialog(
        title: 'Abrir ${register['name']}',
        label: 'Dinero inicial (fondo de caja)',
        currency: cur,
        action: 'Abrir caja',
        submit: (amount, _) async => (await _api.post('/cash/open', {'cash_register_id': register['id'], 'opening_amount': amount}) as Map<String, dynamic>)['session'],
      ),
    );
    if (session == null || !mounted) return;
    showMessage(context, 'Caja abierta.');
    context.read<Session>().refreshCash();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CashSessionScreen(sessionId: session['id'] as int)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Caja')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _load, child: _list(d)),
    );
  }

  Widget _list(Map<String, dynamic> d) {
    final cur = '${d['currency']}';
    final registers = (d['registers'] as List).cast<Map<String, dynamic>>();
    final can = (d['can'] as Map).cast<String, dynamic>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    if (registers.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        EmptyView(text: 'No hay cajas configuradas. Créalas en la web, en Caja y finanzas › Cajas.', icon: Icons.point_of_sale),
      ]);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final r in registers) ...[
        Card(
          child: Builder(builder: (context) {
            final s = r['session'] as Map<String, dynamic>?;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: CircleAvatar(
                backgroundColor: (s != null ? Brand.success : muted).withValues(alpha: .15),
                child: Icon(Icons.point_of_sale, color: s != null ? Brand.success : muted),
              ),
              title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(s != null ? 'Abierta desde las ${hm(wallTime(s['opened_at'] as String))} · esperado ${money(_n(s['expected']), cur)}' : 'Cerrada'),
              trailing: s != null
                  ? const Icon(Icons.chevron_right)
                  : (can['open'] == true ? FilledButton.tonal(onPressed: () => _open(r), child: const Text('Abrir')) : null),
              onTap: s == null
                  ? null
                  : () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => CashSessionScreen(sessionId: s['id'] as int)));
                      _load();
                    },
            );
          }),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

/// Turno de caja: saldo esperado, movimientos, ingreso/gasto rápido y cierre.
class CashSessionScreen extends StatefulWidget {
  const CashSessionScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  State<CashSessionScreen> createState() => _CashSessionScreenState();
}

class _CashSessionScreenState extends State<CashSessionScreen> {
  Map<String, dynamic>? _s;
  String? _error;

  ApiClient get _api => context.read<Session>().api;
  String get _cur => context.read<Session>().me?.company.currencySymbol ?? 'Bs';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await _api.get('/cash/${widget.sessionId}');
      if (mounted) setState(() => _s = s as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _movement(String type) async {
    final income = type == 'ingreso';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AmountDialog(
        title: income ? 'Registrar ingreso' : 'Registrar gasto',
        label: 'Monto',
        currency: _cur,
        conceptHint: income ? 'Ej.: cambio, aporte' : 'Ej.: compra de café, taxi',
        action: 'Registrar',
        submit: (amount, concept) async => await _api.post('/cash/${widget.sessionId}/movements', {'type': type, 'amount': amount, 'concept': concept}) as Map<String, dynamic>,
      ),
    );
    if (result == null || !mounted) return;
    showMessage(context, '${result['message']}');
    setState(() => _s = result['session'] as Map<String, dynamic>);
  }

  Future<void> _close() async {
    final expected = _n(_s!['expected']);
    // Por billetes y monedas: pantalla de conteo. Si no, un solo monto.
    final denominations = ((_s!['denominations'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final byCount = _s!['close_mode'] == 'denominaciones' && denominations.isNotEmpty;
    final result = await (byCount
        ? Navigator.push<Map<String, dynamic>>(
            context,
            MaterialPageRoute(
              builder: (_) => _CashCountScreen(
                denominations: denominations,
                expected: expected,
                currency: _cur,
                submit: (count) async => await _api.post('/cash/${widget.sessionId}/close', {'closing_count': count}) as Map<String, dynamic>,
              ),
            ),
          )
        : showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AmountDialog(
        title: 'Cerrar caja',
        label: 'Efectivo contado',
        currency: _cur,
        help: 'Efectivo esperado: ${money(expected, _cur)}. Las demás formas de pago no se cuentan.',
        difference: expected,
        action: 'Cerrar caja',
        submit: (amount, _) async => await _api.post('/cash/${widget.sessionId}/close', {'closing_amount': amount}) as Map<String, dynamic>,
      ),
    ));
    if (result == null || !mounted) return;
    showMessage(context, '${result['message']}');
    setState(() => _s = result['session'] as Map<String, dynamic>);
    context.read<Session>().refreshCash();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final me = context.watch<Session>().me;
    if (me == null) return const Scaffold(); // sesión cerrada: la pantalla se está yendo
    final open = s?['status'] == 'open';

    return Scaffold(
      appBar: AppBar(title: Text(s == null ? 'Caja' : '${s['register']}')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : s == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: _content(s))),
      bottomNavigationBar: s == null || !open || !(me.can('cash_move') || me.can('cash_close'))
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  if (me.can('cash_move')) ...[
                    Expanded(child: OutlinedButton.icon(onPressed: () => _movement('ingreso'), icon: const Icon(Icons.add), label: const Text('Ingreso'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(onPressed: () => _movement('egreso'), icon: const Icon(Icons.remove), label: const Text('Gasto'))),
                  ],
                  if (me.can('cash_move') && me.can('cash_close')) const SizedBox(width: 8),
                  if (me.can('cash_close')) Expanded(child: FilledButton.icon(onPressed: _close, icon: const Icon(Icons.lock_outline), label: const Text('Cerrar'))),
                ]),
              ),
            ),
    );
  }

  List<Widget> _content(Map<String, dynamic> s) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final open = s['status'] == 'open';
    final movements = (s['movements'] as List).cast<Map<String, dynamic>>();
    final legacy = s['legacy'] == true;
    final others = ((s['other_methods'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final count = ((s['closing_count'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final diff = s['difference'] == null ? null : _n(s['difference']);
    Widget row(String label, double value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [Expanded(child: Text(label)), Text(money(value, _cur), style: TextStyle(fontWeight: FontWeight.w600, color: color))]),
        );

    return [
      Row(children: [
        Expanded(
          child: Text(open ? 'Abierta desde las ${hm(wallTime(s['opened_at'] as String))}' : 'Cerrada a las ${hm(wallTime(s['closed_at'] as String))}', style: TextStyle(color: muted)),
        ),
        StatusPill(label: open ? 'Abierta' : 'Cerrada', color: open ? Brand.success : muted),
      ]),
      const SizedBox(height: 4),
      Text(money(_n(s['expected']), _cur), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
      Text(legacy ? 'Dinero esperado al cierre' : (open ? 'Efectivo que debería haber en caja' : 'Efectivo esperado al cierre'), style: TextStyle(color: muted)),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            row('Fondo inicial', _n(s['opening'])),
            row(legacy ? 'Ingresos (${s['sales_count']} venta(s) incluidas)' : 'Ingresos en efectivo', _n(s['income']), color: Brand.success),
            row(legacy ? 'Egresos' : 'Egresos en efectivo', -_n(s['expense']), color: Brand.danger),
            if (!open && s['counted'] != null) ...[
              const Divider(height: 18),
              row('Contado', _n(s['counted'])),
              if (count.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('Conteo: ${count.map((c) => '${c['qty']} × ${_denom(c['value'])}').join(' · ')}', style: TextStyle(color: muted, fontSize: 12.5)),
                ),
              row(diff!.abs() < 0.005 ? 'Cuadra exacto' : (diff > 0 ? 'Sobrante' : 'Faltante'), diff, color: diff.abs() < 0.005 ? Brand.success : (diff > 0 ? Brand.warning : Brand.danger)),
            ],
          ]),
        ),
      ),
      if (others.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('Otras formas de pago', style: TextStyle(fontWeight: FontWeight.w700)),
        Text('No entran en el conteo de efectivo.', style: TextStyle(color: muted, fontSize: 12.5)),
        const SizedBox(height: 6),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              for (final m in others) row('${m['method']}', _n(m['net'])),
              if (others.length > 1) ...[
                const Divider(height: 14),
                row('Total', others.fold<double>(0, (t, m) => t + _n(m['net']))),
              ],
            ]),
          ),
        ),
      ],
      const SizedBox(height: 12),
      const Text('Movimientos', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      if (movements.isEmpty)
        Text('Aún no hay movimientos.', style: TextStyle(color: muted))
      else
        Card(
          child: Column(children: [
            for (final (i, m) in movements.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                dense: true,
                leading: Icon(m['type'] == 'ingreso' ? Icons.south_west : Icons.north_east, color: m['type'] == 'ingreso' ? Brand.success : Brand.danger),
                title: Text('${m['concept']}'),
                subtitle: Text('${m['at'] != null ? hm(wallTime(m['at'] as String)) : ''} · ${m['method']}'),
                trailing: Text('${m['type'] == 'ingreso' ? '+' : '−'}${money(_n(m['amount']), _cur)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: m['type'] == 'ingreso' ? Brand.success : Brand.danger)),
              ),
            ],
          ]),
        ),
    ];
  }
}

/// Diálogo de monto (y concepto opcional) que envía al servidor y muestra
/// su error sin cerrarse. Con `difference` muestra cuánto sobra o falta.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.label,
    required this.currency,
    required this.action,
    required this.submit,
    this.conceptHint,
    this.help,
    this.difference,
  });

  final String title;
  final String label;
  final String currency;
  final String action;
  final String? conceptHint;
  final String? help;
  final double? difference;
  final Future<dynamic> Function(double amount, String concept) submit;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _amount = TextEditingController();
  final _concept = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _concept.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = _parse(_amount.text);
    if (amount == null || amount < 0) {
      setState(() => _error = 'Indica un monto válido.');
      return;
    }
    if (widget.conceptHint != null && _concept.text.trim().isEmpty) {
      setState(() => _error = 'Indica el concepto.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await widget.submit(amount, _concept.text.trim());
      if (mounted) Navigator.pop(context, res);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = _parse(_amount.text);
    final diff = widget.difference == null || amount == null ? null : amount - widget.difference!;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.help != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(widget.help!, style: const TextStyle(fontWeight: FontWeight.w600))),
        TextField(
          controller: _amount,
          autofocus: true,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: widget.label, prefixText: '${widget.currency} '),
          onChanged: (_) => setState(() {}),
        ),
        if (widget.conceptHint != null) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _concept,
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Concepto', hintText: widget.conceptHint),
          ),
        ],
        if (diff != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              diff.abs() < 0.005 ? 'Cuadra exacto' : (diff > 0 ? 'Sobran ${money(diff, widget.currency)}' : 'Faltan ${money(-diff, widget.currency)}'),
              style: TextStyle(fontWeight: FontWeight.w700, color: diff.abs() < 0.005 ? Brand.success : (diff > 0 ? Brand.warning : Brand.danger)),
            ),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _submit, child: Text(widget.action)),
      ],
    );
  }
}
