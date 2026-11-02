import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Sucursales del salón: ver, crear (según el cupo del plan) y editar.
class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
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
      final d = await _api.get('/branches');
      if (mounted) setState(() => _data = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _open([Map<String, dynamic>? branch]) async {
    final can = (_data!['can'] as Map).cast<String, dynamic>();
    if (branch == null && can['plan_room'] != true) {
      showMessage(context, 'Alcanzaste el límite de sucursales de tu plan.', error: true);
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => BranchFormScreen(branch: branch, warehouses: (_data!['warehouses'] as List).cast<Map<String, dynamic>>())),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final can = (d?['can'] as Map?)?.cast<String, dynamic>() ?? const {};
    final branches = ((d?['branches'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Sucursales')),
      floatingActionButton: can['create'] == true
          ? FloatingActionButton.extended(heroTag: null, onPressed: () => _open(), icon: const Icon(Icons.add), label: const Text('Nueva'))
          : null,
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: branches.isEmpty
                      ? ListView(children: const [SizedBox(height: 80), EmptyView(text: 'Aún no hay sucursales.', icon: Icons.account_tree_outlined)])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                          itemCount: branches.length,
                          itemBuilder: (_, i) {
                            final b = branches[i];
                            final active = b['active'] == true;
                            final lines = [
                              if ((b['address'] ?? '').toString().isNotEmpty) b['address'],
                              if ((b['phone'] ?? '').toString().isNotEmpty) 'Tel. ${b['phone']}',
                              if (b['warehouse'] != null) 'Almacén: ${(b['warehouse'] as Map)['name']}',
                            ].join('\n');
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: (active ? Brand.primary : muted).withValues(alpha: .12),
                                  child: Icon(Icons.storefront_outlined, color: active ? Brand.primary : muted),
                                ),
                                title: Row(children: [
                                  Expanded(child: Text('${b['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: active ? null : muted))),
                                  if (!active) const StatusPill(label: 'Inactiva', color: Brand.danger),
                                ]),
                                subtitle: lines.isEmpty ? null : Text(lines),
                                isThreeLine: lines.contains('\n'),
                                onTap: can['edit'] == true ? () => _open(b) : null,
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

/// Crear o editar una sucursal. Sin almacén elegido se crea uno para ella.
class BranchFormScreen extends StatefulWidget {
  const BranchFormScreen({super.key, this.branch, required this.warehouses});

  final Map<String, dynamic>? branch;
  final List<Map<String, dynamic>> warehouses;

  @override
  State<BranchFormScreen> createState() => _BranchFormScreenState();
}

class _BranchFormScreenState extends State<BranchFormScreen> {
  late final _name = TextEditingController(text: '${widget.branch?['name'] ?? ''}');
  late final _code = TextEditingController(text: '${widget.branch?['code'] ?? ''}');
  late final _phone = TextEditingController(text: '${widget.branch?['phone'] ?? ''}');
  late final _email = TextEditingController(text: '${widget.branch?['email'] ?? ''}');
  late final _address = TextEditingController(text: '${widget.branch?['address'] ?? ''}');
  late final _manager = TextEditingController(text: '${widget.branch?['manager_name'] ?? ''}');
  late int? _warehouseId = (widget.branch?['warehouse'] as Map?)?['id'] as int?;
  late bool _active = widget.branch?['active'] != false;
  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  bool get _editing => widget.branch != null;

  @override
  void dispose() {
    for (final c in [_name, _code, _phone, _email, _address, _manager]) {
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
      'code': _opt(_code),
      'phone': _opt(_phone),
      'email': _opt(_email),
      'address': _opt(_address),
      'manager_name': _opt(_manager),
      'warehouse_id': _warehouseId,
      'active': _active,
    };
    try {
      final res = _editing ? await api.put('/branches/${widget.branch!['id']}', body) : await api.post('/branches', body);
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

  Widget _field(TextEditingController c, String label, String key, {TextInputType? type, TextCapitalization caps = TextCapitalization.none}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          enabled: !_saving,
          keyboardType: type,
          textCapitalization: caps,
          decoration: InputDecoration(labelText: label, errorText: _fieldErrors[key]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar sucursal' : 'Nueva sucursal')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _field(_name, 'Nombre', 'name', caps: TextCapitalization.words),
        _field(_code, 'Código (opcional)', 'code'),
        _field(_address, 'Dirección', 'address', caps: TextCapitalization.sentences),
        _field(_phone, 'Teléfono', 'phone', type: TextInputType.phone),
        _field(_email, 'Correo', 'email', type: TextInputType.emailAddress),
        _field(_manager, 'Encargado', 'manager_name', caps: TextCapitalization.words),
        DropdownButtonFormField<int?>(
          initialValue: _warehouseId,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Almacén', errorText: _fieldErrors['warehouse_id']),
          items: [
            const DropdownMenuItem(value: null, child: Text('Crear uno nuevo para la sucursal')),
            for (final w in widget.warehouses) DropdownMenuItem(value: w['id'] as int, child: Text('${w['name']}')),
          ],
          onChanged: _saving ? null : (v) => setState(() => _warehouseId = v),
        ),
        if (_editing)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            title: const Text('Activa'),
            onChanged: _saving ? null : (v) => setState(() => _active = v),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.check),
          label: Text(_editing ? 'Guardar cambios' : 'Crear sucursal'),
        ),
      ]),
    );
  }
}
