import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../util/format.dart';

/// Editar los datos de contacto del cliente. Devuelve true si se guardó.
class ClientEditScreen extends StatefulWidget {
  const ClientEditScreen({super.key, required this.clientId, required this.name, this.phone, this.document, this.email, this.birthdate, this.notes});

  final int clientId;
  final String name;
  final String? phone;
  final String? document;
  final String? email;
  final DateTime? birthdate;
  final String? notes;

  @override
  State<ClientEditScreen> createState() => _ClientEditScreenState();
}

class _ClientEditScreenState extends State<ClientEditScreen> {
  late final _name = TextEditingController(text: widget.name);
  late final _phone = TextEditingController(text: widget.phone ?? '');
  late final _document = TextEditingController(text: widget.document ?? '');
  late final _email = TextEditingController(text: widget.email ?? '');
  late final _notes = TextEditingController(text: widget.notes ?? '');
  late DateTime? _birthdate = widget.birthdate;
  bool _saving = false;
  Map<String, String> _errors = {};
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _document, _email, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthdate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? DateTime(DateTime.now().year - 30),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().subtract(const Duration(days: 1)),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) setState(() => _birthdate = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors = {};
      _error = null;
    });
    String? orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await context.read<Session>().api.put('/clients/${widget.clientId}', {
        'full_name': _name.text.trim(),
        'phone': orNull(_phone),
        'id_number': orNull(_document),
        'email': orNull(_email),
        'birthdate': _birthdate == null ? null : ymd(_birthdate!),
        'notes': orNull(_notes),
      });
      if (mounted) Navigator.pop(context, true);
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
    InputDecoration deco(String label, IconData icon, String field) => InputDecoration(labelText: label, prefixIcon: Icon(icon), errorText: _errors[field]);

    return Scaffold(
      appBar: AppBar(title: const Text('Editar cliente')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          TextField(controller: _name, enabled: !_saving, textCapitalization: TextCapitalization.characters, decoration: deco('Nombre completo', Icons.person_outline, 'full_name')),
          const SizedBox(height: 12),
          TextField(controller: _phone, enabled: !_saving, keyboardType: TextInputType.phone, decoration: deco('Teléfono', Icons.phone_outlined, 'phone')),
          const SizedBox(height: 12),
          TextField(controller: _document, enabled: !_saving, decoration: deco('Documento (CI)', Icons.badge_outlined, 'id_number')),
          const SizedBox(height: 12),
          TextField(controller: _email, enabled: !_saving, keyboardType: TextInputType.emailAddress, decoration: deco('Correo', Icons.mail_outline, 'email')),
          const SizedBox(height: 12),
          InkWell(
            onTap: _saving ? null : _pickBirthdate,
            child: InputDecorator(
              decoration: deco('Fecha de nacimiento', Icons.cake_outlined, 'birthdate').copyWith(
                suffixIcon: _birthdate == null ? null : IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close), onPressed: () => setState(() => _birthdate = null)),
              ),
              child: Text(_birthdate == null ? 'Sin fecha' : '${longDay(_birthdate!).replaceFirst(RegExp(r'^\S+ '), '')} de ${_birthdate!.year}'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            enabled: !_saving,
            maxLines: 4,
            maxLength: 2000,
            decoration: deco('Notas (alergias, preferencias…)', Icons.notes, 'notes'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.check),
            label: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
          ),
        ),
      ),
    );
  }
}
