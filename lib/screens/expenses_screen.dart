import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/finance_widgets.dart';
import '../widgets/payment_source.dart';
import 'expense_categories_screen.dart';
import 'expense_form_screen.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// Gastos de una pestaña: general, proveedor, personal o basicos. Salen de una
/// cuenta o de la caja abierta. Se anulan, no se borran.
class ExpensesTab extends StatefulWidget {
  const ExpensesTab({super.key, required this.group});

  final String group;

  @override
  State<ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<ExpensesTab> {
  late DateTimeRange _range = DateTimeRange(start: DateTime(DateTime.now().year, DateTime.now().month), end: DateTime.now());
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _basics;
  Map<String, dynamic>? _owed;
  String? _month;
  String? _error;

  ApiClient get _api => context.read<Session>().api;
  bool _can(String ability) => context.read<Session>().me?.can(ability) ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await _api.get('/expenses', {'from': ymd(_range.start), 'to': ymd(_range.end), 'group': widget.group});
      final basics = widget.group == 'basicos' ? await _api.get('/finance/basics', {if (_month != null) 'month': _month}) : null;
      // Lo pendiente no depende del periodo elegido.
      final owed = widget.group == 'personal' && _can('commissions_view') ? await _api.get('/commissions/pending') : null;
      if (!mounted) return;
      setState(() {
        _data = d as Map<String, dynamic>;
        _basics = basics as Map<String, dynamic>?;
        _owed = owed as Map<String, dynamic>?;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(context: context, initialDateRange: _range, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    _load();
  }

  Future<void> _new({int? categoryId, double? amount}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ExpenseFormScreen(group: widget.group, categoryId: categoryId, amount: amount)),
    );
    if (saved == true) _load();
  }

  Future<void> _newService() async {
    final saved = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => const ExpenseCategorySheet(initialType: 'basicos'));
    if (saved == true) _load();
  }

  Future<void> _open(Map<String, dynamic> e, String cur) async {
    final changed = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _ExpenseSheet(expense: e, currency: cur));
    if (changed == true) _load();
  }

  Future<void> _settle(Map<String, dynamic> p, String cur) async {
    final paid = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _SettleSheet(pending: p, currency: cur));
    if (paid == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final can = (d?['can'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cur = '${d?['currency'] ?? 'Bs'}';
    final rows = ((d?['expenses'] as List?) ?? const []).cast<Map<String, dynamic>>();

    return Scaffold(
      floatingActionButton: can['create'] == true
          ? FloatingActionButton.extended(
              heroTag: null,
              backgroundColor: Brand.primary,
              foregroundColor: Colors.white,
              onPressed: () => _new(),
              icon: const Icon(Icons.add),
              label: Text(switch (widget.group) {
                'proveedor' => 'Pago a proveedor',
                'personal' => 'Pago a personal',
                'basicos' => 'Pago de servicio',
                _ => 'Nuevo gasto',
              }),
            )
          : null,
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
                    if (_owed != null) _OwedCard(owed: _owed!, currency: cur, onPay: (p) => _settle(p, cur)),
                    if (_basics != null)
                      _BasicsCard(
                        month: _basics!,
                        currency: cur,
                        canCreate: can['create'] == true,
                        onMonth: (m) {
                          setState(() => _month = m);
                          _load();
                        },
                        onPay: (s) => _new(categoryId: s['id'] as int, amount: s['last_amount'] == null ? null : _n(s['last_amount'])),
                        onAddService: _can('expense_categories_create') ? _newService : null,
                      ),
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        onTap: _pickRange,
                        leading: const Icon(Icons.date_range, color: Brand.primary),
                        title: Text('${shortDay(_range.start)} – ${shortDay(_range.end)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Toca para cambiar el periodo'),
                        trailing: Text(money(_n(d['total']), cur), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ),
                    if (rows.isEmpty) const Padding(padding: EdgeInsets.only(top: 40), child: EmptyView(text: 'Sin gastos en el periodo.', icon: Icons.receipt_long_outlined)),
                    for (final e in rows) _row(e, cur),
                  ]),
                ),
    );
  }

  Widget _row(Map<String, dynamic> e, String cur) {
    final source = e['source'] as Map?;
    final cancelled = e['cancelled'] == true;
    return FinanceTile(
      icon: source == null ? Icons.remove_circle_outline : (source['type'] == 'caja' ? Icons.point_of_sale_outlined : Icons.account_balance_outlined),
      title: '${money(_n(e['amount']), cur)} · ${e['concept']}',
      dimmed: cancelled,
      tags: [if (e['number'] != null) '${e['number']}', if (cancelled) 'Anulado'],
      subtitle: [
        if (e['date'] != null) shortDay(DateTime.parse('${e['date']}')),
        if (e['category'] != null) '${e['category']}',
        if (e['paid_to'] != null) '${e['paid_to']}',
        _sourceLabel(source),
      ].join(' · '),
      onTap: () => _open(e, cur),
    );
  }
}

String _sourceLabel(Map? source) {
  if (source == null) return 'Sin origen';
  return source['type'] == 'caja' ? 'Caja · ${source['name']}' : '${source['name']}';
}

/// Detalle de un gasto, con la opción de anularlo.
class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet({required this.expense, required this.currency});

  final Map<String, dynamic> expense;
  final String currency;

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final res = await context.read<Session>().api.post('/expenses/${widget.expense['id']}/cancel', {
        if (_reason.text.trim().isNotEmpty) 'cancel_reason': _reason.text.trim(),
      });
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text('${(res as Map)['message']}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final source = e['source'] as Map?;
    final cancelled = e['cancelled'] == true;

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 96, child: Text(label, style: TextStyle(color: muted, fontSize: 13))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13.5))),
          ]),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (e['number'] != null) Text('Gasto ${e['number']}', style: TextStyle(fontSize: 13, color: muted)),
          const SizedBox(height: 4),
          Text(money(_n(e['amount']), widget.currency), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, decoration: cancelled ? TextDecoration.lineThrough : null)),
          Text('${e['concept']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (e['date'] != null) row('Fecha', shortDay(DateTime.parse('${e['date']}'))),
          row('Categoría', '${e['category'] ?? '—'}'),
          if (e['paid_to'] != null) row('Pagado a', '${e['paid_to']}'),
          row('Salió de', _sourceLabel(source)),
          if (e['reference'] != null) row('Referencia', '${e['reference']}'),
          if (e['notes'] != null) row('Notas', '${e['notes']}'),
          if (cancelled) row('Anulado', '${e['cancel_reason'] ?? 'Sí'}'),
          if (e['can_cancel'] == true) ...[
            const SizedBox(height: 14),
            TextField(controller: _reason, enabled: !_busy, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Motivo de la anulación (opcional)')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _cancel,
              style: OutlinedButton.styleFrom(foregroundColor: Brand.danger),
              icon: const Icon(Icons.cancel_outlined),
              label: Text(source == null ? 'Anular' : (source['type'] == 'caja' ? 'Anular (vuelve a la caja)' : 'Anular (vuelve a la cuenta)')),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Servicios básicos del mes: cuáles se pagaron y cuáles faltan.
class _BasicsCard extends StatelessWidget {
  const _BasicsCard({required this.month, required this.currency, required this.canCreate, required this.onMonth, required this.onPay, this.onAddService});

  final Map<String, dynamic> month;
  final String currency;
  final bool canCreate;
  final ValueChanged<String> onMonth;
  final ValueChanged<Map<String, dynamic>> onPay;
  final VoidCallback? onAddService;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final services = (month['services'] as List).cast<Map<String, dynamic>>();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(children: [
          Row(children: [
            IconButton(tooltip: 'Mes anterior', onPressed: () => onMonth('${month['previous']}'), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Column(children: [
                Text('${month['label']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text('${month['paid_count']} ${month['paid_count'] == 1 ? 'pagado' : 'pagados'} · ${month['pending_count']} ${month['pending_count'] == 1 ? 'pendiente' : 'pendientes'} · ${money(_n(month['total_paid']), currency)}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: muted)),
              ]),
            ),
            IconButton(tooltip: 'Mes siguiente', onPressed: month['next'] == null ? null : () => onMonth('${month['next']}'), icon: const Icon(Icons.chevron_right)),
          ]),
          if (services.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Todavía no hay servicios básicos: agrega la luz, el agua, el internet… con «Nuevo servicio».', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: muted)),
            ),
          for (final s in services) _service(s),
          if (onAddService != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: onAddService, icon: const Icon(Icons.add), label: const Text('Nuevo servicio')),
            ),
        ]),
      ),
    );
  }

  Widget _service(Map<String, dynamic> s) {
    final paid = s['status'] == 'pagado';
    final annual = s['frequency'] == 'anual';
    final subtitle = paid
        ? ['Pagado ${money(_n(s['paid']), currency)}', if (s['next_due_on'] != null) 'vuelve el ${shortDay(DateTime.parse('${s['next_due_on']}'))}'].join(' · ')
        : ['Pendiente', if (s['last_amount'] != null) 'último ${money(_n(s['last_amount']), currency)}'].join(' · ');
    return ListTile(
      dense: true,
      onTap: !paid && canCreate ? () => onPay(s) : null,
      leading: Icon(paid ? Icons.check_circle : Icons.schedule, color: paid ? Brand.success : Brand.warning),
      title: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        if (annual) const FinanceTag('Anual'),
      ]),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: !paid && canCreate ? const Text('Registrar', style: TextStyle(color: Brand.primary, fontWeight: FontWeight.w700)) : null,
    );
  }
}

/// «Comisiones por pagar»: lo que se debe a cada persona, de cualquier fecha.
class _OwedCard extends StatelessWidget {
  const _OwedCard({required this.owed, required this.currency, required this.onPay});

  final Map<String, dynamic> owed;
  final String currency;
  final ValueChanged<Map<String, dynamic>> onPay;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final people = (owed['people'] as List).cast<Map<String, dynamic>>();
    final count = owed['count'] as int? ?? 0;
    final canPay = (owed['can'] as Map?)?['pay'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: people.isEmpty ? muted.withValues(alpha: .2) : Brand.warning.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.hourglass_top, color: Brand.warning, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Comisiones por pagar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Text(money(_n(owed['total']), currency), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 2, bottom: 6),
            child: Text(
              people.isEmpty ? 'Nada pendiente: todas las comisiones están pagadas.' : '$count ${count == 1 ? 'comisión' : 'comisiones'} sin pagar, de cualquier fecha.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          for (final p in people)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 6, 0, 6),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${p['count']} ${p['count'] == 1 ? 'comisión' : 'comisiones'} · desde el ${shortDay(DateTime.parse('${p['since']}'))}', style: TextStyle(fontSize: 12, color: muted)),
                  ]),
                ),
                Text(money(_n(p['total']), currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (canPay) ...[
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => onPay(p),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 36), visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: const Text('Pagar'),
                  ),
                ],
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Pagar la liquidación de una persona, de su comisión más antigua hasta hoy.
class _SettleSheet extends StatefulWidget {
  const _SettleSheet({required this.pending, required this.currency});

  final Map<String, dynamic> pending;
  final String currency;

  @override
  State<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends State<_SettleSheet> {
  Map<String, dynamic>? _options;
  SourceChoice? _source;
  bool _includeTips = false;
  bool _saving = false;
  String? _error;

  ApiClient get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.get('/finance/options', {'group': 'personal'}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _options = d;
        _source = SourceChoice.initial(d);
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _pay() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final p = widget.pending;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await _api.post('/commissions/${p['personal_id']}/settle', {
        'period_start': p['since'],
        'period_end': ymd(DateTime.now()),
        'include_tips': _includeTips,
        ..._source!.body,
      });
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text('${(res as Map)['message']}')));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pending;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final tips = _n(p['tips']);
    final total = _n(p['total']) + (_includeTips ? tips : 0);
    final o = _options;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Pagar a ${p['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Liquida ${p['count']} ${p['count'] == 1 ? 'comisión' : 'comisiones'} del ${shortDay(DateTime.parse('${p['since']}'))} a hoy.', style: TextStyle(fontSize: 12.5, color: muted)),
          const SizedBox(height: 12),
          if (tips > 0)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeTips,
              title: Text('Incluir propinas (${money(tips, widget.currency)})'),
              onChanged: _saving ? null : (v) => setState(() => _includeTips = v),
            ),
          Row(children: [
            const Expanded(child: Text('Total a pagar', style: TextStyle(fontWeight: FontWeight.w700))),
            Text(money(total, widget.currency), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ]),
          const SizedBox(height: 14),
          if (o == null && _error == null) const Center(child: CircularProgressIndicator()),
          if (o != null) PaymentSourcePicker(options: o, value: _source!, amount: total, enabled: !_saving, onChanged: (v) => setState(() => _source = v)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving || o == null ? null : _pay,
            icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.check),
            label: const Text('Pagar liquidación'),
          ),
        ]),
      ),
    );
  }
}
