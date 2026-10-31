import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../util/contact.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Recordatorios: las citas de mañana (o del día elegido) con un botón para
/// avisar por WhatsApp. Queda registrado quién avisó y cuándo.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  DateTime _day = dateOnly(DateTime.now()).add(const Duration(days: 1));
  List<TemplateOption> _templates = [];
  int? _templateId;
  List<(Appointment, DateTime?, String?)> _items = [];
  bool _loading = true;
  bool _onlyPending = false;
  String? _error;
  final Set<int> _busy = {};

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
      final data = await _api.get('/reminders', {'date': ymd(_day)}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _templates = (data['templates'] as List).whereType<Map<String, dynamic>>().map(TemplateOption.fromJson).toList();
        _templateId ??= _templates.isEmpty ? null : _templates.first.id;
        _items = (data['appointments'] as List).whereType<Map<String, dynamic>>().map((j) => (
              Appointment.fromJson(j),
              j['reminded_at'] == null ? null : wallTime(j['reminded_at'] as String),
              j['reminded_by'] as String?,
            )).toList();
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

  Future<void> _notify(Appointment a) async {
    setState(() => _busy.add(a.id));
    final ok = await sendWhatsapp(context, _api, {
      'client_id': a.client!.id,
      'type': 'reminder',
      'appointment_id': a.id,
      'template_id': _templateId,
    });
    if (!mounted) return;
    setState(() {
      _busy.remove(a.id);
      if (ok) {
        _items = [for (final it in _items) it.$1.id == a.id ? (it.$1, DateTime.now(), context.read<Session>().me?.user.name) : it];
      }
    });
  }

  Future<void> _confirm(Appointment a) async {
    setState(() => _busy.add(a.id));
    try {
      final data = await _api.post('/appointments/${a.id}/status', {'status': 'confirmada'});
      final updated = Appointment.fromJson(data as Map<String, dynamic>);
      if (!mounted) return;
      setState(() => _items = [for (final it in _items) it.$1.id == a.id ? (updated, it.$2, it.$3) : it]);
      showMessage(context, 'Cita de ${a.client?.name ?? ''} confirmada.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(a.id));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _day, firstDate: dateOnly(DateTime.now()), lastDate: DateTime.now().add(const Duration(days: 60)));
    if (picked != null) {
      setState(() => _day = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    final today = dateOnly(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    final visible = _onlyPending ? _items.where((it) => it.$2 == null).toList() : _items;
    final notified = _items.where((it) => it.$2 != null).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Recordatorios')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                ChoiceChip(label: const Text('Hoy'), selected: sameDay(_day, today), onSelected: (_) => setState(() { _day = today; _load(); })),
                const SizedBox(width: 6),
                ChoiceChip(label: const Text('Mañana'), selected: sameDay(_day, tomorrow), onSelected: (_) => setState(() { _day = tomorrow; _load(); })),
                const SizedBox(width: 6),
                ActionChip(avatar: const Icon(Icons.event, size: 18), label: Text(sameDay(_day, today) || sameDay(_day, tomorrow) ? 'Otro día' : shortDay(_day)), onPressed: _pickDate),
              ],
            ),
          ),
          if (_templates.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: DropdownButtonFormField<int>(
                initialValue: _templateId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Plantilla', isDense: true),
                items: [for (final t in _templates) DropdownMenuItem(value: t.id, child: Text(t.name))],
                onChanged: (v) => setState(() => _templateId = v),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              children: [
                Expanded(child: Text('${_items.length} cita(s) · $notified avisada(s)', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                FilterChip(label: const Text('Sin avisar'), selected: _onlyPending, onSelected: (v) => setState(() => _onlyPending = v)),
              ],
            ),
          ),
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: visible.isEmpty
                            ? EmptyView(text: _onlyPending ? '¡Todas avisadas!' : 'No hay citas pendientes ni confirmadas ese día.', icon: Icons.notifications_none)
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                itemCount: visible.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final (a, at, by) = visible[i];
                                  final canConfirm = a.status == 'pendiente' && (a.isMine || me.can('appointments_edit'));
                                  return Card(
                                    key: ValueKey('reminder-${a.id}'),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(hm(a.startsAt), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                                              const SizedBox(width: 10),
                                              Expanded(child: Text(a.client?.name ?? 'Sin cliente', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                                              StatusPill(label: a.statusLabel, color: hexColor(a.statusColor)),
                                            ],
                                          ),
                                          Text([a.service?.name, a.personal?.name].whereType<String>().join(' · '), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                                          const SizedBox(height: 4),
                                          Text(
                                            at == null ? 'Sin avisar' : 'Avisada ${hm(at)}${by != null ? ' por $by' : ''}',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: at == null ? Brand.warning : Brand.success),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              if (a.client?.phone != null)
                                                Expanded(
                                                  child: FilledButton.icon(
                                                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: const Color(0xFF25D366)),
                                                    onPressed: _busy.contains(a.id) ? null : () => _notify(a),
                                                    icon: const Icon(Icons.chat_outlined, size: 18),
                                                    label: Text(at == null ? 'Avisar' : 'Reenviar'),
                                                  ),
                                                )
                                              else
                                                const Expanded(child: Text('Sin teléfono', style: TextStyle(fontSize: 13))),
                                              if (canConfirm) ...[
                                                const SizedBox(width: 8),
                                                OutlinedButton.icon(
                                                  onPressed: _busy.contains(a.id) ? null : () => _confirm(a),
                                                  icon: const Icon(Icons.check, size: 18),
                                                  label: const Text('Confirmó'),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
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
