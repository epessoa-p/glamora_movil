import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'branches_screen.dart';
import 'payment_methods_screen.dart';
import 'staff_schedules_screen.dart';

/// Configuración: un cuadro por sección. Cada cuadro aparece solo con su
/// permiso (los mismos de la web, guardados en la base de datos).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static List<({String title, String detail, IconData icon, Color color, Widget screen})> sectionsFor(Me me) => [
        if (me.can('company_view'))
          (title: 'Mi empresa', detail: 'Nombre, contacto, logo y colores', icon: Icons.storefront_outlined, color: const Color(0xFFA85585), screen: const CompanySettingsScreen()),
        if (me.can('branches_view'))
          (title: 'Sucursales', detail: 'Locales y su almacén', icon: Icons.account_tree_outlined, color: const Color(0xFF6366F1), screen: const BranchesScreen()),
        if (me.can('schedules_view'))
          (title: 'Horarios', detail: 'Turnos semanales del personal', icon: Icons.schedule_outlined, color: const Color(0xFF0EA5E9), screen: const StaffSchedulesScreen()),
        if (me.can('payment_methods_view'))
          (title: 'Formas de pago', detail: 'Cómo cobras y cómo se cuenta al cerrar caja', icon: Icons.credit_card_outlined, color: const Color(0xFF10B981), screen: const PaymentMethodsScreen()),
      ];

  /// El menú muestra «Configuración» solo si hay al menos un cuadro.
  static bool visibleFor(Me me) => sectionsFor(me).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me;
    if (me == null) return const Scaffold();
    final sections = sectionsFor(me);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: sections.isEmpty
          ? const EmptyView(text: 'No tienes permisos de configuración.', icon: Icons.settings_outlined)
          : GridView(
              padding: const EdgeInsets.all(16),
              // Dos por fila en el teléfono; más en pantallas anchas, sin agrandarse.
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisExtent: 176, mainAxisSpacing: 12, crossAxisSpacing: 12),
              children: [
                for (final s in sections)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => s.screen)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(color: s.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                            child: Icon(s.icon, color: s.color),
                          ),
                          const Spacer(),
                          Text(s.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(s.detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 12.5)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Mi empresa: datos del salón, logo y colores.
class CompanySettingsScreen extends StatefulWidget {
  const CompanySettingsScreen({super.key});

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

/// Colores sugeridos (el primero es el predeterminado de Glamora).
const _palette = ['#A85585', '#D6336C', '#9C36B5', '#6741D9', '#1C7ED6', '#0CA678', '#E8590C', '#495057'];

Color? _hex(String? v) {
  final s = (v ?? '').trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
  return Color(int.parse('FF$s', radix: 16));
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  final _name = TextEditingController();
  final _ruc = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _description = TextEditingController();
  final _primary = TextEditingController();
  final _secondary = TextEditingController();
  Map<String, dynamic>? _data;
  String? _loadError;
  String? _error;
  Map<String, String> _fieldErrors = const {};
  bool _saving = false;
  bool _uploading = false;

  ApiClient get _api => context.read<Session>().api;
  bool get _canEdit => (_data?['can'] as Map?)?['edit'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _ruc, _phone, _email, _address, _description, _primary, _secondary]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final d = await _api.get('/company') as Map<String, dynamic>;
      if (!mounted) return;
      _fill(d);
      setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _loadError = errorText(e));
    }
  }

  void _fill(Map<String, dynamic> d) {
    _name.text = '${d['name'] ?? ''}';
    _ruc.text = '${d['ruc'] ?? ''}';
    _phone.text = '${d['phone'] ?? ''}';
    _email.text = '${d['email'] ?? ''}';
    _address.text = '${d['address'] ?? ''}';
    _description.text = '${d['description'] ?? ''}';
    _primary.text = '${d['primary_color'] ?? ''}';
    _secondary.text = '${d['secondary_color'] ?? ''}';
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final res = await _api.put('/company', {
        'name': _name.text.trim(),
        'ruc': _opt(_ruc),
        'phone': _opt(_phone),
        'email': _opt(_email),
        'address': _opt(_address),
        'description': _opt(_description),
        'primary_color': _opt(_primary)?.toUpperCase(),
        'secondary_color': _opt(_secondary)?.toUpperCase(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _data = {..._data!, ...res});
      showMessage(context, '${res['message']}');
      // El menú lateral muestra el nombre y el logo del salón.
      context.read<Session>().refresh();
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

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final res = await _api.upload('/company/logo', field: 'logo', bytes: await file.readAsBytes(), filename: file.name) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _data = {..._data!, 'logo_url': res['logo_url']});
      showMessage(context, '${res['message']}');
      context.read<Session>().refresh();
    } catch (e) {
      if (mounted) showMessage(context, e is ApiException ? (e.fieldErrors['logo']?.first ?? e.message) : errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _field(TextEditingController c, String label, String key, {TextInputType? type, int maxLines = 1, TextCapitalization caps = TextCapitalization.none}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          enabled: _canEdit && !_saving,
          keyboardType: type,
          maxLines: maxLines,
          textCapitalization: caps,
          decoration: InputDecoration(labelText: label, errorText: _fieldErrors[key]),
        ),
      );

  Widget _color(TextEditingController c, String label, String key) {
    final enabled = _canEdit && !_saving;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: c,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          hintText: '#A85585',
          errorText: _fieldErrors[key],
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: CircleAvatar(radius: 10, backgroundColor: _hex(c.text) ?? Colors.transparent, child: _hex(c.text) == null ? const Icon(Icons.block, size: 16) : null),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in _palette)
          InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? () => setState(() => c.text = p) : null,
            child: CircleAvatar(
              radius: 14,
              backgroundColor: _hex(p),
              child: c.text.toUpperCase() == p ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
            ),
          ),
      ]),
      const SizedBox(height: 16),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi empresa')),
      body: _loadError != null
          ? ErrorView(message: _loadError!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Center(
                    child: Column(children: [
                      CompanyLogo(name: '${d['name']}', url: d['logo_url'] as String?, radius: 44),
                      if (_canEdit)
                        TextButton.icon(
                          onPressed: _uploading ? null : _pickLogo,
                          icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_camera_outlined),
                          label: Text(_uploading ? 'Subiendo…' : 'Cambiar logo'),
                        ),
                    ]),
                  ),
                  if (!_canEdit)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('Solo lectura: no tienes permiso para editar los datos de la empresa.', textAlign: TextAlign.center),
                    ),
                  const SizedBox(height: 8),
                  _field(_name, 'Nombre del salón', 'name', caps: TextCapitalization.words),
                  _field(_ruc, 'RUC / NIT', 'ruc'),
                  _field(_phone, 'Teléfono', 'phone', type: TextInputType.phone),
                  _field(_email, 'Correo', 'email', type: TextInputType.emailAddress),
                  _field(_address, 'Dirección', 'address', caps: TextCapitalization.sentences),
                  _field(_description, 'Descripción', 'description', maxLines: 3, caps: TextCapitalization.sentences),
                  const SizedBox(height: 4),
                  Text('Colores de la marca', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  _color(_primary, 'Color principal', 'primary_color'),
                  _color(_secondary, 'Color secundario', 'secondary_color'),
                  if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
                  if (_canEdit)
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.check),
                      label: const Text('Guardar cambios'),
                    ),
                ]),
    );
  }
}
