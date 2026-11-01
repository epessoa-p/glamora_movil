import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../util/contact.dart';
import '../util/format.dart';
import '../widgets/common.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// Cartera: clientes que deben, el más atrasado primero.
class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key});

  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await context.read<Session>().api.get('/receivables', {'q': _search.text.trim()});
      if (mounted) setState(() => _data = data as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final cur = '${d?['currency'] ?? 'Bs'}';
    final rows = (d?['clients'] as List? ?? const []).cast<Map<String, dynamic>>();

    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas por cobrar')),
      body: Column(
        children: [
          if (d != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(child: Text('Por cobrar ${money(_n(d['total']), cur)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                Text('Vencido ${money(_n(d['overdue']), cur)}', style: TextStyle(color: _n(d['overdue']) > 0 ? Brand.danger : null, fontWeight: FontWeight.w600)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(hintText: 'Buscar cliente o teléfono', prefixIcon: Icon(Icons.search), isDense: true),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _load);
              },
            ),
          ),
          Expanded(
            child: _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : d == null
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: rows.isEmpty
                            ? const EmptyView(text: 'Nadie debe nada. 🎉', icon: Icons.receipt_long_outlined)
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                                itemCount: rows.length,
                                separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                                itemBuilder: (_, i) {
                                  final r = rows[i];
                                  final client = ClientInfo.fromJson(r['client'] as Map<String, dynamic>);
                                  final overdue = r['overdue'] == true;
                                  return ListTile(
                                    leading: Avatar(name: client.name),
                                    title: Text(client.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text('${r['accounts']} cuenta(s) · ${overdue ? 'vencida desde' : 'vence'} ${shortDay(DateTime.parse(r['oldest_due'] as String))}',
                                        style: TextStyle(color: overdue ? Brand.danger : null)),
                                    trailing: Text(money(_n(r['debt']), cur), style: const TextStyle(fontWeight: FontWeight.w800)),
                                    onTap: () async {
                                      await Navigator.push(context, MaterialPageRoute(builder: (_) => ReceivableClientScreen(client: client)));
                                      _load();
                                    },
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// Estado de cuenta de un cliente con el formulario de cobro.
class ReceivableClientScreen extends StatefulWidget {
  const ReceivableClientScreen({super.key, required this.client});

  final ClientInfo client;

  @override
  State<ReceivableClientScreen> createState() => _ReceivableClientScreenState();
}

class _ReceivableClientScreenState extends State<ReceivableClientScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  final _amount = TextEditingController();
  String? _method;
  int? _sessionId;
  int? _target;
  bool _saving = false;
  String? _formError;

  ApiClient get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await _api.get('/receivables/${widget.client.id}') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _data = d;
        final debt = _n((d['summary'] as Map)['debt']);
        _amount.text = debt > 0 ? debt.toStringAsFixed(2) : '';
        final methods = (d['payment_methods'] as List).cast<Map<String, dynamic>>();
        _method ??= methods.isEmpty ? null : '${methods.first['code']}';
        final sessions = (d['cash_sessions'] as List).cast<Map<String, dynamic>>();
        if (sessions.length == 1) _sessionId ??= sessions.first['id'] as int;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _collect() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0;
    if (amount <= 0) {
      setState(() => _formError = 'Indica el monto a cobrar.');
      return;
    }
    final ok = await confirm(context, title: 'Registrar cobro', message: '¿Cobrar ${money(amount, '${_data!['currency']}')} a ${widget.client.name}?', ok: 'Cobrar');
    if (!ok || !mounted) return;

    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final res = await _api.post('/receivables/${widget.client.id}/collect', {
        'amount': amount,
        'payment_method': _method,
        'cash_session_id': _sessionId,
        'receivable_id': _target,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      showMessage(context, '${res['message']} Queda debiendo ${money(_n(res['debt']), '${_data!['currency']}')}.');
      _target = null;
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final me = context.watch<Session>().me;
    if (me == null) return const Scaffold(); // sesión cerrada: la pantalla se está yendo

    return Scaffold(
      appBar: AppBar(title: const Text('Estado de cuenta')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: _content(d, me))),
    );
  }

  List<Widget> _content(Map<String, dynamic> d, Me me) {
    final cur = '${d['currency']}';
    final s = d['summary'] as Map<String, dynamic>;
    final accounts = (d['accounts'] as List).cast<Map<String, dynamic>>();
    final receipts = (d['receipts'] as List).cast<Map<String, dynamic>>();
    final methods = (d['payment_methods'] as List).cast<Map<String, dynamic>>();
    final sessions = (d['cash_sessions'] as List).cast<Map<String, dynamic>>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final canCollect = me.can('receivables_collect') && accounts.isNotEmpty;

    return [
      Text(widget.client.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('Debe ${money(_n(s['debt']), cur)}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: s['overdue'] == true ? Brand.danger : null)),
      if (s['enabled'] == true) Text('Límite ${money(_n(s['limit']), cur)} · disponible ${money(_n(s['available']), cur)}', style: TextStyle(color: muted)),
      if (widget.client.phone != null) ...[
        const SizedBox(height: 10),
        ContactButtons(phone: widget.client.phone!, message: 'Hola ${widget.client.name.split(' ').first}, te recordamos que tienes un saldo pendiente de ${money(_n(s['debt']), cur)}.'),
      ],
      const SizedBox(height: 16),
      const Text('Cuentas pendientes', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      if (accounts.isEmpty)
        Text('No debe nada.', style: TextStyle(color: muted))
      else
        Card(
          child: Column(children: [
            for (final (i, a) in accounts.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                dense: true,
                title: Text('Venta ${a['sale'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${a['overdue'] == true ? 'Vencida' : 'Vence'} el ${shortDay(DateTime.parse(a['due_date'] as String))} · de ${money(_n(a['amount']), cur)}',
                    style: TextStyle(color: a['overdue'] == true ? Brand.danger : null)),
                trailing: Text(money(_n(a['balance']), cur), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ]),
        ),
      if (canCollect) ...[
        const SizedBox(height: 16),
        const Text('Registrar cobro', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _amount,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Monto', prefixText: '$cur ', errorText: _formError),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _method,
          decoration: const InputDecoration(labelText: 'Forma de pago', isDense: true),
          items: [for (final m in methods) DropdownMenuItem(value: '${m['code']}', child: Text('${m['name']}'))],
          onChanged: _saving ? null : (v) => setState(() => _method = v),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int?>(
          initialValue: _sessionId,
          decoration: const InputDecoration(labelText: 'Caja', isDense: true),
          items: [
            if (d['require_cash'] != true) const DropdownMenuItem(value: null, child: Text('No registrar en caja')),
            for (final c in sessions) DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}')),
          ],
          onChanged: _saving ? null : (v) => setState(() => _sessionId = v),
        ),
        if (accounts.length > 1) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<int?>(
            initialValue: _target,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Aplicar a', isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('Las más antiguas primero')),
              for (final a in accounts) DropdownMenuItem(value: a['id'] as int, child: Text('Venta ${a['sale']} · saldo ${money(_n(a['balance']), cur)}')),
            ],
            onChanged: _saving ? null : (v) => setState(() => _target = v),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _saving ? null : _collect,
          icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.payments_outlined),
          label: const Text('Cobrar y emitir recibo'),
        ),
      ],
      if (receipts.isNotEmpty) ...[
        const SizedBox(height: 20),
        const Text('Últimos cobros', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Card(
          child: Column(children: [
            for (final r in receipts)
              ListTile(
                dense: true,
                title: Text('${r['number']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${shortDay(wallTime(r['paid_at'] as String))} · ${r['method']}'),
                trailing: Text(money(_n(r['amount']), cur)),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 24),
    ];
  }
}
