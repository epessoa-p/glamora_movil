import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../util/contact.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Cumpleaños de clientes con saludo por WhatsApp (y cupón de regalo opcional).
class BirthdaysScreen extends StatefulWidget {
  const BirthdaysScreen({super.key});

  @override
  State<BirthdaysScreen> createState() => _BirthdaysScreenState();
}

class _BirthdaysScreenState extends State<BirthdaysScreen> {
  String _range = 'today';
  List<BirthdayInfo> _items = [];
  List<TemplateOption> _templates = [];
  List<({int id, String code, String value})> _coupons = [];
  int? _templateId;
  int? _couponId;
  bool _loading = true;
  String? _error;
  final Set<int> _greeted = {};

  ApiClient get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.get('/birthdays', {'range': _range}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _items = (data['clients'] as List).whereType<Map<String, dynamic>>().map(BirthdayInfo.fromJson).toList();
        _templates = (data['templates'] as List).whereType<Map<String, dynamic>>().map(TemplateOption.fromJson).toList();
        _coupons = (data['coupons'] as List).whereType<Map<String, dynamic>>()
            .map((c) => (id: c['id'] as int, code: '${c['code']}', value: '${c['value']}')).toList();
        _templateId ??= _templates.isEmpty ? null : _templates.first.id;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _greet(BirthdayInfo b) async {
    final ok = await sendWhatsapp(context, _api, {
      'client_id': b.client.id,
      'type': 'birthday',
      'template_id': _templateId,
      'coupon_id': _couponId,
    });
    if (ok && mounted) setState(() => _greeted.add(b.client.id));
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Cumpleaños')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'today', label: Text('Hoy')),
                  ButtonSegment(value: 'week', label: Text('7 días')),
                  ButtonSegment(value: 'month', label: Text('Este mes')),
                ],
                selected: {_range},
                onSelectionChanged: (s) {
                  setState(() => _range = s.first);
                  _load();
                },
              ),
            ),
          ),
          if (_coupons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: DropdownButtonFormField<int?>(
                initialValue: _couponId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cupón de regalo', isDense: true, prefixIcon: Icon(Icons.card_giftcard)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Sin cupón')),
                  for (final c in _coupons) DropdownMenuItem(value: c.id, child: Text('${c.code} · ${c.value}')),
                ],
                onChanged: (v) => setState(() => _couponId = v),
              ),
            ),
          if (_templates.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: DropdownButtonFormField<int>(
                initialValue: _templateId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Plantilla', isDense: true),
                items: [for (final t in _templates) DropdownMenuItem(value: t.id, child: Text(t.name))],
                onChanged: (v) => setState(() => _templateId = v),
              ),
            ),
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _items.isEmpty
                            ? const EmptyView(text: 'Nadie cumple años en este periodo.', icon: Icons.cake_outlined)
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                itemCount: _items.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final b = _items[i];
                                  final greeted = b.greetedAt != null || _greeted.contains(b.client.id);
                                  return Card(
                                    key: ValueKey('birthday-${b.client.id}'),
                                    color: b.isToday ? Brand.soft.withValues(alpha: .5) : null,
                                    child: ListTile(
                                      leading: Avatar(name: b.client.name),
                                      title: Text(b.client.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      subtitle: Text(
                                        '${b.isToday ? '¡Hoy! 🎂' : longDay(b.birthday)}${b.age != null ? ' · cumple ${b.age}' : ''}'
                                        '${greeted ? '\nYa saludado' : ''}',
                                        style: TextStyle(color: greeted ? Brand.success : muted),
                                      ),
                                      isThreeLine: greeted,
                                      trailing: b.client.phone == null
                                          ? const Text('Sin teléfono', style: TextStyle(fontSize: 12))
                                          : FilledButton(
                                              style: FilledButton.styleFrom(minimumSize: const Size(0, 38), backgroundColor: const Color(0xFF25D366)),
                                              onPressed: () => _greet(b),
                                              child: Text(greeted ? 'Reenviar' : 'Saludar'),
                                            ),
                                    ),
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
