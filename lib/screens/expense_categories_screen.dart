import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/finance_widgets.dart';

/// Los tipos de categoría: deciden en qué pestaña de Gastos sale y qué pide.
const _types = {
  'general': 'Gasto general',
  'basicos': 'Servicio básico',
  'proveedor': 'Pago a proveedor',
  'personal': 'Pago a personal',
};

const _groupTitles = {
  'general': 'Gastos generales',
  'basicos': 'Servicios básicos',
  'proveedor': 'Pagos a proveedores',
  'personal': 'Pagos a personal',
};

IconData _groupIcon(String? type) => switch (type) {
      'proveedor' => Icons.local_shipping_outlined,
      'personal' => Icons.badge_outlined,
      'basicos' => Icons.home_work_outlined,
      _ => Icons.label_outline,
    };

/// Finanzas › Categorías: en qué se gasta, agrupado por tipo.
class ExpenseCategoriesTab extends StatefulWidget {
  const ExpenseCategoriesTab({super.key});

  @override
  State<ExpenseCategoriesTab> createState() => _ExpenseCategoriesTabState();
}

class _ExpenseCategoriesTabState extends State<ExpenseCategoriesTab> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await context.read<Session>().api.get('/expense-categories');
      if (mounted) setState(() => _data = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _edit([Map<String, dynamic>? category]) async {
    final saved = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => ExpenseCategorySheet(category: category));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final can = (d?['can'] as Map?)?.cast<String, dynamic>() ?? const {};
    final categories = ((d?['categories'] as List?) ?? const []).cast<Map<String, dynamic>>();

    return Scaffold(
      floatingActionButton: can['create'] == true
          ? FloatingActionButton.extended(heroTag: null, backgroundColor: Brand.primary, foregroundColor: Colors.white, onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Nueva categoría'))
          : null,
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                    for (final g in _groupTitles.entries) ...[
                      if (categories.any((c) => c['type'] == g.key)) FinanceSectionTitle(g.value),
                      for (final c in categories.where((c) => c['type'] == g.key))
                        FinanceTile(
                          icon: _groupIcon(g.key),
                          title: '${c['name']}',
                          dimmed: c['active'] != true,
                          tags: [
                            if (c['frequency'] != null) c['frequency'] == 'anual' ? 'Anual' : 'Mensual',
                            if (c['active'] != true) 'Inactiva',
                          ],
                          subtitle: '${c['expenses_count']} ${c['expenses_count'] == 1 ? 'gasto' : 'gastos'}',
                          onTap: can['edit'] == true ? () => _edit(c) : null,
                        ),
                    ],
                  ]),
                ),
    );
  }
}

/// Alta o edición de una categoría en hoja inferior. Devuelve true si se guardó.
/// Desde Gastos › Servicios se abre con `initialType: 'basicos'`.
class ExpenseCategorySheet extends StatefulWidget {
  const ExpenseCategorySheet({super.key, this.category, this.initialType = 'general'});

  final Map<String, dynamic>? category;
  final String initialType;

  @override
  State<ExpenseCategorySheet> createState() => _ExpenseCategorySheetState();
}

class _ExpenseCategorySheetState extends State<ExpenseCategorySheet> {
  late final _name = TextEditingController(text: '${widget.category?['name'] ?? ''}');
  late String _type = widget.category?['type'] as String? ?? widget.initialType;
  late String _frequency = widget.category?['frequency'] as String? ?? 'mensual';
  late bool _active = widget.category?['active'] != false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.category != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = context.read<Session>().api;
    final body = {
      'name': _name.text.trim(),
      'type': _type,
      if (_type == 'basicos') 'frequency': _frequency,
      if (_editing) 'active': _active,
    };
    try {
      if (_editing) {
        await api.put('/expense-categories/${widget.category!['id']}', body);
      } else {
        await api.post('/expense-categories', body);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldErrors['name']?.first ?? e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context, title: 'Eliminar categoría', message: 'Si tiene gastos, solo se da de baja para no romper el historial.', ok: 'Eliminar');
    if (!ok || !mounted) return;
    final api = context.read<Session>().api;
    try {
      final res = await api.delete('/expense-categories/${widget.category!['id']}');
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(content: Text('${(res as Map)['message']}')));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final title = _editing ? 'Editar categoría' : (widget.initialType == 'basicos' ? 'Nuevo servicio' : 'Nueva categoría');
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            if (_editing && widget.category?['can_delete'] == true) IconButton(tooltip: 'Eliminar', onPressed: _saving ? null : _delete, icon: const Icon(Icons.delete_outline)),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: !_editing,
            enabled: !_saving,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseFormatter()],
            decoration: InputDecoration(labelText: 'Nombre', hintText: _type == 'basicos' ? 'LUZ, AGUA, INTERNET…' : null, errorText: _error),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: [for (final t in _types.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
            onChanged: _saving ? null : (v) => setState(() => _type = v ?? _type),
          ),
          if (_type == 'basicos') ...[
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'mensual', label: Text('Mensual'), icon: Icon(Icons.calendar_month, size: 18)),
                ButtonSegment(value: 'anual', label: Text('Anual'), icon: Icon(Icons.event_repeat, size: 18)),
              ],
              selected: {_frequency},
              onSelectionChanged: _saving ? null : (s) => setState(() => _frequency = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              _frequency == 'anual' ? 'Queda pagado por un año desde el último pago.' : 'Queda pagado si hubo un pago en el mes (luz, agua, internet…).',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
          if (_editing)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              title: const Text('Activa'),
              onChanged: _saving ? null : (v) => setState(() => _active = v),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
        ]),
      ),
    );
  }
}
