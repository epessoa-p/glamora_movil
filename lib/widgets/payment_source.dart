import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/format.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// De dónde sale (o de dónde viene) el dinero.
class SourceChoice {
  const SourceChoice({required this.type, this.sessionId, this.accountId});

  /// 'caja', 'cuenta' o 'ninguno'.
  final String type;
  final int? sessionId;
  final int? accountId;

  bool get isComplete => type == 'ninguno' || (type == 'caja' && sessionId != null) || (type == 'cuenta' && accountId != null);

  Map<String, Object?> get body => {
        'source_type': type,
        if (type == 'caja') 'cash_session_id': sessionId,
        if (type == 'cuenta') 'financial_account_id': accountId,
      };

  /// Elección inicial: la cuenta pedida, o la primera cuenta, o la primera caja abierta.
  factory SourceChoice.initial(Map<String, dynamic> options, {int? accountId}) {
    final sessions = (options['sessions'] as List).cast<Map<String, dynamic>>();
    final accounts = (options['accounts'] as List).cast<Map<String, dynamic>>();
    if (accountId != null && accounts.any((a) => a['id'] == accountId)) return SourceChoice(type: 'cuenta', accountId: accountId);
    if (accounts.isNotEmpty) return SourceChoice(type: 'cuenta', accountId: accounts.first['id'] as int);
    if (sessions.isNotEmpty) return SourceChoice(type: 'caja', sessionId: sessions.first['id'] as int);
    return const SourceChoice(type: 'cuenta');
  }
}

/// ¿De dónde sale el dinero? Pestañas Cuenta | Caja abierta (y una opcional sin
/// origen). Es el mismo selector en gastos y liquidaciones.
class PaymentSourcePicker extends StatelessWidget {
  const PaymentSourcePicker({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label = '¿De dónde sale el dinero?',
    this.noneLabel,
    this.amount,
    this.excludeAccountId,
    this.enabled = true,
  });

  final Map<String, dynamic> options;
  final SourceChoice value;
  final ValueChanged<SourceChoice> onChanged;
  final String label;
  final String? noneLabel;

  /// Monto a pagar, para avisar si el saldo no alcanza.
  final double? amount;
  final int? excludeAccountId;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final cur = '${options['currency'] ?? 'Bs'}';
    final sessions = (options['sessions'] as List).cast<Map<String, dynamic>>();
    final accounts = (options['accounts'] as List).cast<Map<String, dynamic>>().where((a) => a['id'] != excludeAccountId).toList();
    final canUseAccounts = options['can_use_accounts'] == true;

    void select(String type) {
      onChanged(switch (type) {
        'caja' => SourceChoice(type: 'caja', sessionId: sessions.isEmpty ? null : sessions.first['id'] as int),
        'cuenta' => SourceChoice(type: 'cuenta', accountId: accounts.isEmpty ? null : accounts.first['id'] as int),
        _ => const SourceChoice(type: 'ninguno'),
      });
    }

    final selectedAccount = accounts.where((a) => a['id'] == value.accountId).firstOrNull;
    final short = value.type == 'cuenta' && selectedAccount != null && amount != null && amount! > _n(selectedAccount['balance']) + 0.001;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          if (canUseAccounts) const ButtonSegment(value: 'cuenta', label: Text('Cuenta'), icon: Icon(Icons.account_balance_outlined, size: 18)),
          const ButtonSegment(value: 'caja', label: Text('Caja abierta'), icon: Icon(Icons.point_of_sale_outlined, size: 18)),
          if (noneLabel != null) ButtonSegment(value: 'ninguno', label: Text(noneLabel!)),
        ],
        selected: {value.type},
        onSelectionChanged: enabled ? (s) => select(s.first) : null,
      ),
      const SizedBox(height: 10),
      if (value.type == 'caja')
        sessions.isEmpty
            ? Text('No hay ningún turno de caja abierto. Abre la caja para pagar desde ella.', style: TextStyle(color: muted))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DropdownButtonFormField<int>(
                  key: const ValueKey('source-session'),
                  initialValue: value.sessionId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Turno de caja'),
                  items: [
                    for (final s in sessions)
                      DropdownMenuItem(value: s['id'] as int, child: Text('${s['name']} · ${money(_n(s['expected']), cur)}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: enabled ? (id) => onChanged(SourceChoice(type: 'caja', sessionId: id)) : null,
                ),
                const SizedBox(height: 4),
                Text('Sale en efectivo del cajón: se descuenta en el arqueo del turno.', style: TextStyle(color: muted, fontSize: 12)),
              ]),
      if (value.type == 'cuenta')
        accounts.isEmpty
            ? Text('No hay cuentas activas. Créalas en Finanzas › Cuentas.', style: TextStyle(color: muted))
            : DropdownButtonFormField<int>(
                key: const ValueKey('source-account'),
                initialValue: value.accountId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cuenta'),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(value: a['id'] as int, child: Text('${a['name']} · ${money(_n(a['balance']), cur)}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: enabled ? (id) => onChanged(SourceChoice(type: 'cuenta', accountId: id)) : null,
              ),
      if (short)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('El saldo de esta cuenta no alcanza: tiene ${money(_n(selectedAccount['balance']), cur)}.', style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600)),
        ),
    ]);
  }
}
