import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/finance_widgets.dart';
import '../widgets/payment_source.dart';

/// Alta de un gasto. Los campos cambian según la pestaña de la que se viene.
class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, required this.group, this.accountId, this.categoryId, this.amount});

  /// general, proveedor, personal o basicos.
  final String group;

  /// Cuenta preseleccionada al entrar desde su detalle.
  final int? accountId;

  /// Servicio y último importe, al registrar un servicio pendiente.
  final int? categoryId;
  final double? amount;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  late final _amount = TextEditingController(text: widget.amount == null ? '' : widget.amount!.toStringAsFixed(2));
  final _concept = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  int? _categoryId;
  int? _supplierId;
  int? _personalId;
  int? _branchId;
  SourceChoice? _source;
  Map<String, dynamic>? _options;
  String? _loadError;
  String? _error;
  Map<String, String> _fieldErrors = const {};
  bool _saving = false;

  ApiClient get _api => context.read<Session>().api;
  double? get _amountValue => double.tryParse(_amount.text.replaceAll(',', '.'));

  String get _title => switch (widget.group) {
        'proveedor' => 'Pago a proveedor',
        'personal' => 'Pago a personal',
        'basicos' => 'Pago de servicio',
        _ => 'Nuevo gasto',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_amount, _concept, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final d = await _api.get('/finance/options', {'group': widget.group}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _options = d;
        _categoryId = widget.categoryId ?? d['default_category_id'] as int?;
        _source = SourceChoice.initial(d, accountId: widget.accountId);
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = errorText(e));
    }
  }

  Future<void> _newSupplier() async {
    final created = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _SupplierDialog(api: _api));
    if (created == null || !mounted) return;
    setState(() {
      (_options!['suppliers'] as List).add(created);
      _supplierId = created['id'] as int;
    });
  }

  Future<void> _save() async {
    if (!_source!.isComplete) {
      setState(() => _error = 'Elige de dónde sale el dinero: una cuenta o una caja abierta.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      final res = await _api.post('/expenses', {
        'group': widget.group,
        'expense_category_id': _categoryId,
        'amount': _amountValue,
        'concept': opt(_concept),
        'movement_date': ymd(_date),
        'reference': opt(_reference),
        'notes': opt(_notes),
        'supplier_id': _supplierId,
        'personal_id': _personalId,
        'branch_id': _branchId,
        ..._source!.body,
      });
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
    final o = _options;
    final group = widget.group;
    final categories = ((o?['categories'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final branches = ((o?['branches'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final suppliers = ((o?['suppliers'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final people = ((o?['people'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final paysSomeone = group == 'proveedor' || group == 'personal';
    // En proveedor y personal va la habitual; solo se elige si el grupo tiene varias.
    final showCategory = !paysSomeone || categories.length > 1;
    final categoryLabel = group == 'basicos' ? 'Servicio' : (paysSomeone ? 'Concepto' : 'Categoría');
    final conceptHint = switch (group) {
      'proveedor' || 'personal' => 'Pago a … (se completa solo)',
      'basicos' => 'Servicio · mes (se completa solo)',
      _ => 'Ej.: pasajes, almuerzo',
    };

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _loadError != null
          ? ErrorView(message: _loadError!, onRetry: _load)
          : o == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (group == 'proveedor') ...[
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('supplier-$_supplierId'),
                          initialValue: _supplierId,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: 'Proveedor', errorText: _fieldErrors['supplier_id']),
                          items: [for (final s in suppliers) DropdownMenuItem(value: s['id'] as int, child: Text('${s['name']}', overflow: TextOverflow.ellipsis))],
                          onChanged: _saving ? null : (v) => setState(() => _supplierId = v),
                        ),
                      ),
                      if (o['can_create_supplier'] == true) IconButton(tooltip: 'Nuevo proveedor', onPressed: _saving ? null : _newSupplier, icon: const Icon(Icons.add_circle_outline)),
                    ]),
                    const SizedBox(height: 12),
                  ],
                  if (group == 'personal') ...[
                    DropdownButtonFormField<int>(
                      initialValue: _personalId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: 'Personal', errorText: _fieldErrors['personal_id']),
                      items: [for (final p in people) DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']}', overflow: TextOverflow.ellipsis))],
                      onChanged: _saving ? null : (v) => setState(() => _personalId = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showCategory) ...[
                    DropdownButtonFormField<int>(
                      initialValue: categories.any((c) => c['id'] == _categoryId) ? _categoryId : null,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: categoryLabel, errorText: _fieldErrors['expense_category_id']),
                      items: [
                        for (final c in categories)
                          DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}${c['frequency'] == 'anual' ? ' (anual)' : ''}', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _categoryId = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _concept,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: group == 'general' ? 'Descripción' : 'Descripción (opcional)', hintText: conceptHint, errorText: _fieldErrors['concept']),
                  ),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: TextField(
                        controller: _amount,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'Importe', prefixText: '${o['currency']} ', errorText: _fieldErrors['amount']),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
                                if (d != null && mounted) setState(() => _date = d);
                              },
                        icon: const Icon(Icons.event),
                        label: Text(shortDay(_date)),
                      ),
                    ),
                  ]),
                  if (_fieldErrors['movement_date'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_fieldErrors['movement_date']!, style: const TextStyle(color: Brand.danger))),
                  if (branches.length > 1) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      initialValue: _branchId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Sucursal'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Según la caja o el usuario')),
                        for (final b in branches) DropdownMenuItem(value: b['id'] as int, child: Text('${b['name']}')),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _branchId = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: _reference, enabled: !_saving, decoration: const InputDecoration(labelText: 'Referencia (n.º de factura)')),
                  const SizedBox(height: 12),
                  TextField(controller: _notes, enabled: !_saving, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
                  const SizedBox(height: 16),
                  PaymentSourcePicker(options: o, value: _source!, amount: _amountValue, enabled: !_saving, onChanged: (v) => setState(() => _source = v)),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.save),
                    label: const Text('Registrar'),
                  ),
                ]),
    );
  }
}

class _SupplierDialog extends StatefulWidget {
  const _SupplierDialog({required this.api});

  final ApiClient api;

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  // Sin dispose inmediato: el diálogo se sigue dibujando en su animación de salida.
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final created = await widget.api.post('/suppliers', {'name': _name.text.trim()});
      if (mounted) Navigator.pop(context, created as Map<String, dynamic>);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is ApiException ? (e.fieldErrors['name']?.first ?? e.message) : errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nuevo proveedor'),
        content: TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const [UpperCaseFormatter()],
          decoration: InputDecoration(labelText: 'Nombre', errorText: _error),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: _saving ? null : _save, child: const Text('Crear')),
        ],
      );
}
