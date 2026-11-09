import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Iconos de la web (Bootstrap Icons) y su equivalente en la app.
const paymentIcons = <String, (String, IconData)>{
  'bi-cash-coin': ('Efectivo', Icons.payments_outlined),
  'bi-credit-card': ('Tarjeta', Icons.credit_card),
  'bi-bank': ('Banco / Transferencia', Icons.account_balance_outlined),
  'bi-qr-code': ('QR', Icons.qr_code_2),
  'bi-wallet2': ('Billetera digital', Icons.account_balance_wallet_outlined),
  'bi-phone': ('Pago por celular', Icons.smartphone),
  'bi-ticket-perforated': ('Vale / Cupón', Icons.confirmation_number_outlined),
  'bi-credit-card-2-front': ('Genérico', Icons.credit_card_outlined),
};

IconData paymentIcon(String? icon) => paymentIcons[icon]?.$2 ?? Icons.credit_card_outlined;

/// Formas de pago del salón (las que ofrece el cobro y la caja) y cómo se cuenta al cerrar caja.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
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
      final d = await _api.get('/payment-methods');
      if (mounted) setState(() => _data = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _open([Map<String, dynamic>? method]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => PaymentMethodFormScreen(method: method)));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final can = (d?['can'] as Map?)?.cast<String, dynamic>() ?? const {};
    final methods = ((d?['methods'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Formas de pago')),
      floatingActionButton: can['create'] == true
          ? FloatingActionButton.extended(heroTag: null, onPressed: () => _open(), icon: const Icon(Icons.add), label: const Text('Nuevo'))
          : null,
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: methods.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 80),
                          EmptyView(text: 'Sin formas configuradas: el cobro usa Efectivo, QR, Tarjeta, Transferencia y Billetera móvil.', icon: Icons.credit_card_outlined),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
                          itemCount: methods.length + 1,
                          separatorBuilder: (_, i) => i == methods.length - 1 ? const SizedBox(height: 8) : const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (_, i) {
                            if (i == methods.length) return _CloseSettingsCard(data: (d['close'] as Map?)?.cast<String, dynamic>(), canEdit: can['close_settings'] == true, onSaved: _load);
                            final m = methods[i];
                            final active = m['active'] == true;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: (active ? Brand.primary : muted).withValues(alpha: .12),
                                child: Icon(paymentIcon(m['icon'] as String?), color: active ? Brand.primary : muted),
                              ),
                              title: Text('${m['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: active ? null : muted)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(spacing: 6, runSpacing: 4, children: [
                                  if (m['is_system'] == true) const StatusPill(label: 'Siempre habilitado', color: Brand.success),
                                  if (m['is_default'] == true) const StatusPill(label: 'Predeterminada', color: Brand.primary),
                                  if (m['affects_cash'] == true && m['is_system'] != true) const StatusPill(label: 'Cuenta como efectivo', color: Brand.success),
                                  if (!active) const StatusPill(label: 'Inactivo', color: Brand.danger),
                                ]),
                              ),
                              onTap: can['edit'] == true ? () => _open(m) : null,
                            );
                          },
                        ),
                ),
    );
  }
}

/// Crear o editar una forma de pago.
class PaymentMethodFormScreen extends StatefulWidget {
  const PaymentMethodFormScreen({super.key, this.method});

  final Map<String, dynamic>? method;

  @override
  State<PaymentMethodFormScreen> createState() => _PaymentMethodFormScreenState();
}

class _PaymentMethodFormScreenState extends State<PaymentMethodFormScreen> {
  late final _name = TextEditingController(text: '${widget.method?['name'] ?? ''}');
  late final _order = TextEditingController(text: '${widget.method?['sort_order'] ?? 0}');
  late String _icon = widget.method?['icon'] as String? ?? 'bi-credit-card-2-front';
  late bool _affectsCash = widget.method?['affects_cash'] == true;
  late bool _isDefault = widget.method?['is_default'] == true;
  late bool _active = widget.method?['active'] != false;
  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  bool get _editing => widget.method != null;

  /// Efectivo: siempre habilitado y siempre cuenta como efectivo.
  bool get _system => widget.method?['is_system'] == true;

  @override
  void dispose() {
    _name.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    final api = context.read<Session>().api;
    final body = {
      'name': _name.text.trim(),
      // Al editar se conserva el código: las ventas ya registradas lo usan.
      if (_editing) 'code': widget.method!['code'],
      'icon': _icon,
      'affects_cash': _affectsCash,
      'is_default': _isDefault,
      'active': _active,
      'sort_order': int.tryParse(_order.text.trim()) ?? 0,
    };
    try {
      final res = _editing ? await api.put('/payment-methods/${widget.method!['id']}', body) : await api.post('/payment-methods', body);
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
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar forma de pago' : 'Nueva forma de pago')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _name,
          enabled: !_saving,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: 'Nombre', hintText: 'Ej.: Yape, Tigo Money', errorText: _fieldErrors['name'] ?? _fieldErrors['code']),
        ),
        const SizedBox(height: 16),
        const Text('Icono', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in paymentIcons.entries)
            ChoiceChip(
              avatar: Icon(e.value.$2, size: 18),
              label: Text(e.value.$1),
              selected: _icon == e.key,
              onSelected: _saving ? null : (_) => setState(() => _icon = e.key),
            ),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _affectsCash,
          title: const Text('Cuenta como efectivo'),
          subtitle: Text(_system ? 'El efectivo está siempre habilitado y siempre se cuenta' : 'Entra al conteo del cierre de caja'),
          onChanged: _saving || _system ? null : (v) => setState(() => _affectsCash = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _isDefault,
          title: const Text('Predeterminada'),
          subtitle: const Text('Se elige solo al cobrar'),
          onChanged: _saving ? null : (v) => setState(() => _isDefault = v),
        ),
        if (_editing)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            title: const Text('Activa'),
            subtitle: Text(_system ? 'El efectivo está siempre habilitado' : 'Las inactivas no aparecen al cobrar'),
            onChanged: _saving || _system ? null : (v) => setState(() => _active = v),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _order,
          enabled: !_saving,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Orden', helperText: 'Menor número = aparece primero', errorText: _fieldErrors['sort_order']),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.check),
          label: Text(_editing ? 'Guardar cambios' : 'Crear forma de pago'),
        ),
      ]),
    );
  }
}

/// Cómo se cuenta el efectivo al cerrar caja: un solo monto o billetes y monedas.
class _CloseSettingsCard extends StatefulWidget {
  const _CloseSettingsCard({required this.data, required this.canEdit, required this.onSaved});

  final Map<String, dynamic>? data;
  final bool canEdit;
  final VoidCallback onSaved;

  @override
  State<_CloseSettingsCard> createState() => _CloseSettingsCardState();
}

class _CloseSettingsCardState extends State<_CloseSettingsCard> {
  late String _mode = '${widget.data?['mode'] ?? 'monto'}';
  late final _bills = TextEditingController(text: _join(widget.data?['bills']));
  late final _coins = TextEditingController(text: _join(widget.data?['coins']));
  bool _saving = false;
  Map<String, String> _errors = const {};

  static String _join(dynamic list) => ((list as List?) ?? const [])
      .map((v) => v is num && v == v.roundToDouble() ? v.toStringAsFixed(0) : (v is num ? v.toStringAsFixed(2) : '$v'))
      .join(', ');

  static List<String> _split(String text) => text.split(RegExp(r'[\s;,]+')).where((p) => p.isNotEmpty).toList();

  @override
  void dispose() {
    _bills.dispose();
    _coins.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      final res = await context.read<Session>().api.put('/cash-close-settings', {
        'mode': _mode,
        'bills': _split(_bills.text),
        'coins': _split(_coins.text),
      });
      if (!mounted) return;
      showMessage(context, '${(res as Map)['message']}');
      widget.onSaved();
    } on ApiException catch (e) {
      if (mounted) setState(() => _errors = {for (final entry in e.fieldErrors.entries) entry.key: entry.value.first, if (e.fieldErrors.isEmpty) 'mode': e.message});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final enabled = widget.canEdit && !_saving;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.lock_outline, size: 20, color: Brand.primary),
            SizedBox(width: 8),
            Text('Cierre de caja', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
          const SizedBox(height: 4),
          Text('Solo se cuenta el efectivo: las demás formas de pago se muestran aparte con su monto.', style: TextStyle(color: muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'monto', label: Text('Un solo monto')),
                ButtonSegment(value: 'denominaciones', label: Text('Billetes y monedas')),
              ],
              selected: {_mode},
              onSelectionChanged: enabled ? (v) => setState(() => _mode = v.first) : null,
            ),
          ),
          if (_mode == 'denominaciones') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _bills,
              enabled: enabled,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(labelText: 'Billetes', helperText: 'Separados por coma. Ej.: 200, 100, 50', errorText: _errors['bills']),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _coins,
              enabled: enabled,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(labelText: 'Monedas', helperText: 'Decimales con punto. Ej.: 5, 2, 1, 0.50', errorText: _errors['coins']),
            ),
          ],
          if (_errors['mode'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_errors['mode']!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (widget.canEdit) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: enabled ? _save : null, child: const Text('Guardar')),
            ),
          ] else
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Solo quien edita las preferencias puede cambiarlo.', style: TextStyle(color: muted, fontSize: 12))),
        ]),
      ),
    );
  }
}
