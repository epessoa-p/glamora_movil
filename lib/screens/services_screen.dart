import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// Catálogo de servicios: buscar, crear y editar.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  Map<String, dynamic>? _data;
  String? _error;

  ApiClient get _api => context.read<Session>().api;

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
      final d = await _api.get('/services', {'q': _search.text.trim()});
      if (mounted) setState(() => _data = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _open([Map<String, dynamic>? service]) async {
    final d = _data!;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceFormScreen(
          service: service,
          categories: (d['categories'] as List).cast<Map<String, dynamic>>(),
          canCreateCategory: (d['can'] as Map)['create_category'] == true,
        ),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final can = (d?['can'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cur = context.read<Session>().me?.company.currencySymbol ?? 'Bs';
    final services = ((d?['services'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Servicios')),
      floatingActionButton: can['create'] == true
          ? FloatingActionButton.extended(heroTag: null, onPressed: () => _open(), icon: const Icon(Icons.add), label: const Text('Nuevo'))
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(hintText: 'Buscar servicio', prefixIcon: Icon(Icons.search), isDense: true),
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
                      child: services.isEmpty
                          ? ListView(children: const [SizedBox(height: 80), EmptyView(text: 'No hay servicios. Crea el primero con «Nuevo».', icon: Icons.content_cut)])
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
                              itemCount: services.length,
                              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                              itemBuilder: (_, i) {
                                final s = services[i];
                                final active = s['active'] == true;
                                final sub = [
                                  if (s['category'] != null) '${(s['category'] as Map)['name']}',
                                  if (s['duration'] != null) '${s['duration']} min',
                                  if (!active) 'Inactivo',
                                ].join(' · ');
                                return ListTile(
                                  enabled: true,
                                  title: Text('${s['name']}', style: TextStyle(fontWeight: FontWeight.w600, color: active ? null : muted)),
                                  subtitle: sub.isEmpty ? null : Text(sub, style: TextStyle(color: active ? null : muted)),
                                  trailing: Text(money(_n(s['price']), cur), style: TextStyle(fontWeight: FontWeight.w800, color: active ? null : muted)),
                                  onTap: can['edit'] == true ? () => _open(s) : null,
                                );
                              },
                            ),
                    ),
        ),
      ]),
    );
  }
}

/// Crear o editar un servicio.
class ServiceFormScreen extends StatefulWidget {
  const ServiceFormScreen({super.key, this.service, required this.categories, this.canCreateCategory = false});

  final Map<String, dynamic>? service;
  final List<Map<String, dynamic>> categories;
  final bool canCreateCategory;

  @override
  State<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
  late final _name = TextEditingController(text: widget.service?['name'] as String? ?? '');
  late final _price = TextEditingController(text: widget.service == null ? '' : _n(widget.service!['price']).toStringAsFixed(2));
  late final _duration = TextEditingController(text: '${widget.service?['duration'] ?? ''}');
  late final _description = TextEditingController(text: widget.service?['description'] as String? ?? '');
  late final List<Map<String, dynamic>> _categories = [...widget.categories];
  late int? _categoryId = (widget.service?['category'] as Map?)?['id'] as int?;
  late bool _active = widget.service?['active'] != false;
  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  bool get _editing => widget.service != null;
  ApiClient get _api => context.read<Session>().api;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _duration.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _newCategory() async {
    final ctrl = TextEditingController();
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        String? error;
        var saving = false;
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Nueva categoría'),
            content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: 'Nombre', errorText: error)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setLocal(() => saving = true);
                        try {
                          final c = await _api.post('/service-categories', {'name': ctrl.text.trim()});
                          if (context.mounted) Navigator.pop(context, c as Map<String, dynamic>);
                        } catch (e) {
                          setLocal(() {
                            saving = false;
                            error = e is ApiException ? (e.fieldErrors['name']?.first ?? e.message) : errorText(e);
                          });
                        }
                      },
                child: const Text('Crear'),
              ),
            ],
          ),
        );
      },
    );
    // Sin dispose: el diálogo sigue dibujándose durante su animación de salida.
    if (created != null && mounted) {
      setState(() {
        _categories.add(created);
        _categoryId = created['id'] as int;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    final body = {
      'name': _name.text.trim(),
      'price': double.tryParse(_price.text.replaceAll(',', '.')),
      'duration_minutes': int.tryParse(_duration.text.trim()),
      'service_category_id': _categoryId,
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'active': _active,
    };
    try {
      final res = _editing ? await _api.put('/services/${widget.service!['id']}', body) : await _api.post('/services', body);
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
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar servicio' : 'Nuevo servicio')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _name,
          enabled: !_saving,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: 'Nombre', errorText: _fieldErrors['name']),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: DropdownButtonFormField<int?>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Categoría', errorText: _fieldErrors['service_category_id']),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin categoría')),
                for (final c in _categories) DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}')),
              ],
              onChanged: _saving ? null : (v) => setState(() => _categoryId = v),
            ),
          ),
          if (widget.canCreateCategory)
            IconButton(tooltip: 'Nueva categoría', onPressed: _saving ? null : _newCategory, icon: const Icon(Icons.add_circle_outline)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _price,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Precio', prefixText: '$cur ', errorText: _fieldErrors['price']),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _duration,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Duración', suffixText: 'min', errorText: _fieldErrors['duration_minutes']),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // Duraciones frecuentes con un toque.
        Wrap(spacing: 6, children: [
          for (final m in const [20, 30, 45, 60, 90, 120])
            ChoiceChip(
              label: Text(m < 60 ? '$m min' : '${m ~/ 60} h${m % 60 > 0 ? ' ${m % 60}' : ''}'),
              selected: _duration.text.trim() == '$m',
              onSelected: _saving ? null : (_) => setState(() => _duration.text = '$m'),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          enabled: !_saving,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
        ),
        if (_editing)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            title: const Text('Activo'),
            subtitle: const Text('Los inactivos no aparecen para agendar ni cobrar'),
            onChanged: _saving ? null : (v) => setState(() => _active = v),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.check),
          label: Text(_editing ? 'Guardar cambios' : 'Crear servicio'),
        ),
      ]),
    );
  }
}
