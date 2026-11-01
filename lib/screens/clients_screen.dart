import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../session.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';
import 'birthdays_screen.dart';
import 'client_detail_screen.dart';

/// Búsqueda de clientes y alta rápida. Con [pickMode] devuelve el cliente
/// elegido (lo usa el formulario de cita).
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key, this.pickMode = false});

  final bool pickMode;

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  List<ClientInfo> _items = [];

  /// Para descartar respuestas de búsquedas anteriores que lleguen tarde.
  int _request = 0;

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

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
    setState(() {}); // botón de limpiar
  }

  Future<void> _load() async {
    final id = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.get('/clients', {'q': _search.text.trim()});
      if (!mounted || id != _request) return;
      setState(() {
        _items = (data as List).whereType<Map<String, dynamic>>().map(ClientInfo.fromJson).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _request) return;
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final client = await showModalBottomSheet<ClientInfo>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => NewClientSheet(api: _api, initialName: _search.text.trim()),
    );
    if (client == null || !mounted) return;
    if (widget.pickMode) {
      Navigator.pop(context, client);
      return;
    }
    showMessage(context, 'Cliente ${client.name} registrado.');
    setState(() => _items = [client, ..._items]);
  }

  void _tap(ClientInfo c) {
    if (widget.pickMode) {
      Navigator.pop(context, c);
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => ClientDetailScreen(client: c)));
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<Session>().me!.can('clients_create');

    return Scaffold(
      appBar: AppBar(
        leading: shellLeading(context),
        title: Text(widget.pickMode ? 'Elegir cliente' : 'Clientes'),
        actions: [
          if (!widget.pickMode && (context.read<Session>().me?.can('birthdays') ?? false))
            IconButton(
              tooltip: 'Cumpleaños',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BirthdaysScreen())),
              icon: const Icon(Icons.cake_outlined),
            ),
          const CashButton(),
          const ProfileButton(),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(heroTag: null, onPressed: _create, icon: const Icon(Icons.person_add_alt), label: const Text('Nuevo'))
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              autofocus: widget.pickMode,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, teléfono o CI',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
          Expanded(child: _body(canCreate)),
        ],
      ),
    );
  }

  Widget _body(bool canCreate) {
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if (_items.isEmpty && !_loading) {
      return EmptyView(
        text: _search.text.isEmpty ? 'Aún no hay clientes.' : 'No se encontró "${_search.text.trim()}".',
        icon: Icons.person_search_outlined,
        action: canCreate ? FilledButton.tonalIcon(onPressed: _create, icon: const Icon(Icons.person_add_alt), label: const Text('Registrar cliente')) : null,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (_, i) {
          final c = _items[i];
          return ListTile(
            leading: Avatar(name: c.name),
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([c.phone, c.document].whereType<String>().join(' · ').isEmpty ? 'Sin teléfono' : [c.phone, c.document].whereType<String>().join(' · ')),
            trailing: widget.pickMode ? const Icon(Icons.chevron_right) : null,
            onTap: () => _tap(c),
          );
        },
      ),
    );
  }
}

/// Alta rápida: nombre y teléfono. Devuelve el cliente creado.
class NewClientSheet extends StatefulWidget {
  const NewClientSheet({super.key, required this.api, this.initialName = ''});

  final ApiClient api;
  final String initialName;

  @override
  State<NewClientSheet> createState() => _NewClientSheetState();
}

class _NewClientSheetState extends State<NewClientSheet> {
  late final _name = TextEditingController(text: widget.initialName);
  final _phone = TextEditingController();
  bool _saving = false;
  Map<String, String> _errors = {};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _errors = {'full_name': 'Escribe el nombre del cliente.'});
      return;
    }
    setState(() {
      _saving = true;
      _errors = {};
      _error = null;
    });
    try {
      final data = await widget.api.post('/clients', {
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      });
      if (mounted) Navigator.pop(context, ClientInfo.fromJson(data as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errors = {for (final x in e.fieldErrors.entries) x.key: x.value.first};
          _error = e.fieldErrors.isEmpty ? e.message : null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Nuevo cliente', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            enabled: !_saving,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: 'Nombre completo', prefixIcon: const Icon(Icons.person_outline), errorText: _errors['full_name']),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            enabled: !_saving,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(labelText: 'Teléfono (opcional)', prefixIcon: const Icon(Icons.phone_outlined), errorText: _errors['phone']),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Guardar cliente'),
          ),
        ],
      ),
    );
  }
}
