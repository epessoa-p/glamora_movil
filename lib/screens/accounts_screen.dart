import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/finance_widgets.dart';
import '../widgets/payment_source.dart';
import 'expense_form_screen.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

IconData accountIcon(String? type) => switch (type) {
      'capital' => Icons.savings_outlined,
      'banco' => Icons.account_balance_outlined,
      'billetera' => Icons.smartphone,
      'caja_chica' => Icons.account_balance_wallet_outlined,
      _ => Icons.payments_outlined,
    };

/// Finanzas › Cuentas: el saldo total y una tarjeta por cuenta.
class AccountsTab extends StatefulWidget {
  const AccountsTab({super.key});

  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
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
      final d = await _api.get('/accounts');
      if (mounted) setState(() => _data = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  List<Map<String, dynamic>> get _types => ((_data?['types'] as List?) ?? const []).cast<Map<String, dynamic>>();

  Future<void> _create() async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AccountFormScreen(types: _types)));
    if (saved == true) _load();
  }

  Future<void> _open(Map<String, dynamic> a) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetailScreen(accountId: a['id'] as int, types: _types)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final can = (d?['can'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cur = '${d?['currency'] ?? 'Bs'}';
    final accounts = ((d?['accounts'] as List?) ?? const []).cast<Map<String, dynamic>>();

    return Scaffold(
      floatingActionButton: can['create'] == true
          ? FloatingActionButton.extended(heroTag: null, backgroundColor: Brand.primary, foregroundColor: Colors.white, onPressed: _create, icon: const Icon(Icons.add), label: const Text('Nueva cuenta'))
          : null,
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 96), children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Brand.primary, Brand.rose], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('SALDO DE LAS CUENTAS', style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(money(_n(d['total']), cur), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    if (accounts.isEmpty)
                      const Padding(padding: EdgeInsets.only(top: 40), child: EmptyView(text: 'Sin cuentas. Crea la caja chica, el capital o tu cuenta de banco.', icon: Icons.account_balance_outlined)),
                    for (final a in accounts)
                      FinanceTile(
                        icon: accountIcon(a['type'] as String?),
                        title: '${a['name']}',
                        tags: ['${a['type_label']}', if (a['active'] != true) 'Inactiva'],
                        dimmed: a['active'] != true,
                        subtitle: [money(_n(a['balance']), cur), if (a['bank_name'] != null) '${a['bank_name']}'].join(' · '),
                        onTap: () => _open(a),
                      ),
                  ]),
                ),
    );
  }
}

/// Saldo actual, acciones y extracto de una cuenta, como el de un banco.
class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId, required this.types});

  final int accountId;
  final List<Map<String, dynamic>> types;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  Map<String, dynamic>? _a;
  String? _error;

  ApiClient get _api => context.read<Session>().api;
  String get _path => '/accounts/${widget.accountId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await _api.get(_path);
      if (mounted) setState(() => _a = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AccountFormScreen(account: _a, types: widget.types)));
    if (saved == true && mounted) _load();
  }

  Future<void> _expense() async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ExpenseFormScreen(group: 'general', accountId: widget.accountId)));
    if (saved == true && mounted) _load();
  }

  Future<void> _move() async {
    final saved = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => AccountMoveSheet(account: _a!));
    if (saved == true && mounted) _load();
  }

  Future<void> _void(Map<String, dynamic> m) async {
    final ok = await confirm(context, title: 'Anular movimiento', message: '¿Anular «${m['concept']}»? Dejará de contar en el saldo.', ok: 'Anular');
    if (!ok || !mounted) return;
    try {
      final res = await _api.post('$_path/movements/${m['id']}/void');
      if (!mounted) return;
      showMessage(context, '${(res as Map)['message']}');
      _load();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context, title: 'Eliminar cuenta', message: '¿Eliminar «${_a!['name']}»?', ok: 'Eliminar');
    if (!ok || !mounted) return;
    try {
      final res = await _api.delete(_path);
      if (!mounted) return;
      showMessage(context, '${(res as Map)['message']}');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final can = (a?['can'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cur = context.read<Session>().me?.company.currencySymbol ?? 'Bs';
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final movements = ((a?['movements'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final active = a?['active'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(a == null ? 'Cuenta' : '${a['name']}'),
        actions: [
          if (can['edit'] == true) IconButton(tooltip: 'Editar', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
          if (can['delete'] == true && a?['has_movements'] == false) IconButton(tooltip: 'Eliminar', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : a == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text([a['type_label'], if (a['bank_name'] != null) a['bank_name'], if (a['account_number'] != null) a['account_number'], if (!active) 'Inactiva'].join(' · '), style: TextStyle(color: muted)),
                          const SizedBox(height: 6),
                          Text(money(_n(a['balance']), cur), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                          if (active && (can['move'] == true || can['expense'] == true)) ...[
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              if (can['move'] == true)
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                                  onPressed: _move,
                                  icon: const Icon(Icons.swap_vert, size: 18),
                                  label: const Text('Movimiento'),
                                ),
                              if (can['expense'] == true)
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                                  onPressed: _expense,
                                  icon: const Icon(Icons.remove, size: 18),
                                  label: const Text('Gasto'),
                                ),
                            ]),
                          ],
                        ]),
                      ),
                    ),
                    const FinanceSectionTitle('Extracto'),
                    if (movements.isEmpty) const Padding(padding: EdgeInsets.only(top: 32), child: EmptyView(text: 'Sin movimientos todavía.', icon: Icons.receipt_long_outlined)),
                    for (final m in movements) _movement(m, cur, muted, can),
                  ]),
                ),
    );
  }

  Widget _movement(Map<String, dynamic> m, String cur, Color muted, Map<String, dynamic> can) {
    final voided = m['voided'] == true;
    final amount = _n(m['amount']);
    final color = voided ? muted : (amount >= 0 ? Brand.success : Brand.danger);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m['concept']}', style: TextStyle(fontWeight: FontWeight.w700, color: voided ? muted : null, decoration: voided ? TextDecoration.lineThrough : null)),
              const SizedBox(height: 2),
              Text([shortDay(DateTime.parse('${m['date']}')), m['origin'], if (voided) 'Anulado'].join(' · '), style: TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${amount >= 0 ? '+' : '−'}${money(amount.abs(), cur)}', style: TextStyle(fontWeight: FontWeight.w800, color: color, decoration: voided ? TextDecoration.lineThrough : null)),
            if (m['balance_after'] != null) Text('Saldo ${money(_n(m['balance_after']), cur)}', style: TextStyle(color: muted, fontSize: 11.5)),
          ]),
          if (can['move'] == true && m['can_void'] == true)
            IconButton(tooltip: 'Anular', onPressed: () => _void(m), icon: const Icon(Icons.close, size: 20))
          else
            const SizedBox(width: 8),
        ]),
      ),
    );
  }
}

/// Alta o edición de una cuenta. El saldo inicial solo se pone al crearla.
class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({super.key, this.account, required this.types});

  final Map<String, dynamic>? account;
  final List<Map<String, dynamic>> types;

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  late final _name = TextEditingController(text: '${widget.account?['name'] ?? ''}');
  late final _bank = TextEditingController(text: '${widget.account?['bank_name'] ?? ''}');
  late final _number = TextEditingController(text: '${widget.account?['account_number'] ?? ''}');
  final _initial = TextEditingController();
  late String _type = widget.account?['type'] as String? ?? 'caja_chica';
  late bool _active = widget.account?['active'] != false;
  String? _error;
  Map<String, String> _fieldErrors = const {};
  bool _saving = false;

  bool get _editing => widget.account != null;

  @override
  void dispose() {
    for (final c in [_name, _bank, _number, _initial]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    final api = context.read<Session>().api;
    final body = {
      'name': _name.text.trim(),
      'type': _type,
      'bank_name': _opt(_bank),
      'account_number': _opt(_number),
      if (_editing) 'active': _active,
      if (!_editing) 'initial_amount': double.tryParse(_initial.text.replaceAll(',', '.')),
    };
    try {
      final res = _editing ? await api.put('/accounts/${widget.account!['id']}', body) : await api.post('/accounts', body);
      if (!mounted) return;
      showMessage(context, '${(res as Map)['message']}');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _fieldErrors = {for (final entry in e.fieldErrors.entries) entry.key: entry.value.first};
          _error = e.fieldErrors.isEmpty ? e.message : null;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = context.read<Session>().me?.company.currencySymbol ?? 'Bs';
    final usesBank = _type == 'banco' || _type == 'billetera';
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar cuenta' : 'Nueva cuenta')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _name,
          enabled: !_saving,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const [UpperCaseFormatter()],
          decoration: InputDecoration(labelText: 'Nombre', errorText: _fieldErrors['name']),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Tipo'),
          items: [for (final t in widget.types) DropdownMenuItem(value: '${t['code']}', child: Text('${t['label']}'))],
          onChanged: _saving ? null : (v) => setState(() => _type = v ?? _type),
        ),
        if (usesBank) ...[
          const SizedBox(height: 12),
          TextField(controller: _bank, enabled: !_saving, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Banco o billetera (opcional)')),
          const SizedBox(height: 12),
          TextField(controller: _number, enabled: !_saving, decoration: const InputDecoration(labelText: 'N.º de cuenta (opcional)')),
        ],
        if (!_editing) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _initial,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Saldo inicial',
              prefixText: '$cur ',
              helperText: 'Lo que hay hoy en la cuenta. Entra como primer movimiento.',
              errorText: _fieldErrors['initial_amount'],
            ),
          ),
        ],
        if (_editing)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            title: const Text('Activa'),
            subtitle: const Text('Para desactivarla, su saldo debe estar en 0'),
            onChanged: _saving ? null : (v) => setState(() => _active = v),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.save),
          label: Text(_editing ? 'Guardar cambios' : 'Crear cuenta'),
        ),
      ]),
    );
  }
}

/// Hoja con dos pestañas: Ingreso / egreso y Transferir.
class AccountMoveSheet extends StatefulWidget {
  const AccountMoveSheet({super.key, required this.account});

  final Map<String, dynamic> account;

  @override
  State<AccountMoveSheet> createState() => _AccountMoveSheetState();
}

class _AccountMoveSheetState extends State<AccountMoveSheet> {
  final _amount = TextEditingController();
  final _concept = TextEditingController();
  final _reference = TextEditingController();
  String _tab = 'move';
  String _direction = 'in';
  String? _destination;
  DateTime _date = DateTime.now();
  SourceChoice _source = const SourceChoice(type: 'ninguno');
  Map<String, dynamic>? _options;
  String? _error;
  Map<String, String> _fieldErrors = const {};
  bool _saving = false;

  ApiClient get _api => context.read<Session>().api;
  int get _id => widget.account['id'] as int;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _concept.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _api.get('/finance/options') as Map<String, dynamic>;
      if (mounted) setState(() => _options = d);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
    final concept = _concept.text.trim().isEmpty ? null : _concept.text.trim();
    try {
      final res = _tab == 'move'
          ? await _api.post('/accounts/$_id/movements', {
              'direction': _direction,
              'amount': amount,
              'concept': concept,
              'movement_date': ymd(_date),
              'reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
              if (_direction == 'in') ..._source.body,
            })
          : await _api.post('/accounts/$_id/transfer', {'amount': amount, 'concept': concept, 'destination': _destination, 'movement_date': ymd(_date)});
      if (!mounted) return;
      final message = '${(res as Map)['message']}';
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _fieldErrors = {for (final entry in e.fieldErrors.entries) entry.key: entry.value.first};
          _error = e.fieldErrors.isEmpty ? e.message : null;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _options;
    final cur = '${o?['currency'] ?? 'Bs'}';
    final others = ((o?['accounts'] as List?) ?? const []).cast<Map<String, dynamic>>().where((a) => a['id'] != _id).toList();
    final sessions = ((o?['sessions'] as List?) ?? const []).cast<Map<String, dynamic>>();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: o == null
          ? SizedBox(height: 160, child: Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${widget.account['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 'move', label: Text('Ingreso / egreso')), ButtonSegment(value: 'transfer', label: Text('Transferir'))],
                  selected: {_tab},
                  onSelectionChanged: _saving ? null : (s) => setState(() => _tab = s.first),
                ),
                const SizedBox(height: 12),
                if (_tab == 'move') ...[
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [ButtonSegment(value: 'in', label: Text('Ingreso')), ButtonSegment(value: 'out', label: Text('Egreso'))],
                    selected: {_direction},
                    onSelectionChanged: _saving ? null : (s) => setState(() => _direction = s.first),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_tab == 'transfer') ...[
                  if (others.isEmpty && sessions.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('No hay otra cuenta ni caja abierta a la que transferir.')),
                  DropdownButtonFormField<String>(
                    initialValue: _destination,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'Hacia', errorText: _fieldErrors['destination']),
                    items: [
                      for (final a in others) DropdownMenuItem(value: 'cuenta:${a['id']}', child: Text('Cuenta: ${a['name']}')),
                      for (final s in sessions) DropdownMenuItem(value: 'caja:${s['id']}', child: Text('Caja: ${s['name']}')),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _destination = v),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Importe', prefixText: '$cur ', errorText: _fieldErrors['amount']),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
                              if (d != null && mounted) setState(() => _date = d);
                            },
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(shortDay(_date)),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _concept,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: _tab == 'move' ? 'Concepto' : 'Concepto (opcional)', errorText: _fieldErrors['concept']),
                ),
                if (_tab == 'move') ...[
                  const SizedBox(height: 12),
                  TextField(controller: _reference, enabled: !_saving, decoration: const InputDecoration(labelText: 'Referencia (opcional)')),
                  if (_direction == 'in') ...[
                    const SizedBox(height: 14),
                    PaymentSourcePicker(options: o, value: _source, label: 'Viene de', noneLabel: 'Externo', excludeAccountId: _id, enabled: !_saving, onChanged: (v) => setState(() => _source = v)),
                  ],
                ],
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.save),
                  label: Text(_tab == 'move' ? 'Guardar' : 'Transferir'),
                ),
              ]),
            ),
    );
  }
}
