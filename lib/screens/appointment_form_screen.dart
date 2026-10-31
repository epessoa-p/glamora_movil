import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'clients_screen.dart';

/// Agendar una cita. Las reglas (choques, horario del profesional) las
/// aplica el servidor; si la cita queda fuera de horario se pide
/// confirmación y se reenvía con `force_outside`.
class AppointmentFormScreen extends StatefulWidget {
  const AppointmentFormScreen({super.key, required this.day, this.options});

  final DateTime day;
  final AgendaOptions? options;

  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  static const _durations = [15, 30, 45, 60, 75, 90, 120, 150, 180, 240];

  AgendaOptions? _options;
  String? _loadError;

  ClientInfo? _client;
  ServiceOption? _service;
  int? _personalId;
  late DateTime _date;
  late TimeOfDay _time;
  int _duration = 30;
  final _notes = TextEditingController();

  DayAvailability? _availability;
  bool _loadingAvailability = false;

  bool _saving = false;
  String? _error;
  Map<String, String> _fieldErrors = {};

  ApiClient get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = dateOnly(widget.day.isBefore(dateOnly(now)) ? now : widget.day);
    // Próxima media hora.
    final next = now.add(Duration(minutes: 30 - now.minute % 30));
    _time = sameDay(_date, now) ? TimeOfDay(hour: next.hour, minute: next.minute) : const TimeOfDay(hour: 9, minute: 0);
    _personalId = context.read<Session>().me!.personal?.id;
    _options = widget.options;
    if (_options == null) _loadOptions();
    _loadAvailability();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() => _loadError = null);
    try {
      final data = await _api.get('/agenda/options');
      if (mounted) setState(() => _options = AgendaOptions.fromJson(data as Map<String, dynamic>));
    } catch (e) {
      if (mounted) setState(() => _loadError = errorText(e));
    }
  }

  Future<void> _loadAvailability() async {
    if (_personalId == null) {
      setState(() => _availability = null);
      return;
    }
    setState(() => _loadingAvailability = true);
    try {
      final data = await _api.get('/agenda/availability', {'personal_id': _personalId, 'date': ymd(_date)});
      if (mounted) setState(() => _availability = DayAvailability.fromJson(data as Map<String, dynamic>));
    } catch (_) {
      if (mounted) setState(() => _availability = null);
    } finally {
      if (mounted) setState(() => _loadingAvailability = false);
    }
  }

  Future<void> _pickClient() async {
    final client = await Navigator.push<ClientInfo>(
      context,
      MaterialPageRoute(builder: (_) => const ClientsScreen(pickMode: true)),
    );
    if (client != null) {
      setState(() {
        _client = client;
        _fieldErrors.remove('client_id');
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: dateOnly(DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _loadAvailability();
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  DateTime get _startsAt => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _submit({bool force = false}) async {
    if (_client == null) {
      setState(() => _fieldErrors = {'client_id': 'Elige el cliente.'});
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = {};
    });

    try {
      final data = await _api.post('/appointments', {
        'client_id': _client!.id,
        'service_id': _service?.id,
        'personal_id': _personalId,
        'starts_at': wallIso(_startsAt),
        'duration_minutes': _duration,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        if (force) 'force_outside': true,
      });
      if (mounted) Navigator.pop(context, Appointment.fromJson(data as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);

      final outside = e.field('outside_schedule');
      if (outside != null && !force) {
        final ok = await confirm(
          context,
          title: 'Fuera de horario',
          // El texto del servidor termina sugiriendo la casilla de la web; aquí es un botón.
          message: outside.split('. Si igual').first,
          ok: 'Agendar de todos modos',
        );
        if (ok) _submit(force: true);
        return;
      }

      setState(() {
        _fieldErrors = {for (final entry in e.fieldErrors.entries) entry.key: entry.value.first};
        _error = e.fieldErrors.isEmpty ? e.message : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva cita')),
      body: options == null
          ? (_loadError != null ? ErrorView(message: _loadError!, onRetry: _loadOptions) : const Center(child: CircularProgressIndicator()))
          : _form(options),
      bottomNavigationBar: options == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _submit(),
                  icon: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'Agendando…' : 'Agendar ${shortDay(_date)} · ${_time.format(context)}'),
                ),
              ),
            ),
    );
  }

  Widget _form(AgendaOptions options) {
    final scheme = Theme.of(context).colorScheme;
    final durations = {..._durations, _duration}.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
          ),
        _Label('Cliente'),
        Card(
          child: ListTile(
            leading: _client == null ? const Icon(Icons.person_search_outlined) : Avatar(name: _client!.name, radius: 18),
            title: Text(_client?.name ?? 'Elegir cliente', style: TextStyle(fontWeight: _client == null ? FontWeight.normal : FontWeight.w600)),
            subtitle: _client?.phone == null ? null : Text(_client!.phone!),
            trailing: const Icon(Icons.chevron_right),
            onTap: _saving ? null : _pickClient,
          ),
        ),
        _FieldError(_fieldErrors['client_id']),
        const SizedBox(height: 16),
        _Label('Servicio'),
        DropdownButtonFormField<int?>(
          initialValue: _service?.id,
          isExpanded: true,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.content_cut), errorText: _fieldErrors['service_id']),
          items: [
            const DropdownMenuItem(value: null, child: Text('Sin servicio')),
            for (final s in options.services)
              DropdownMenuItem(
                value: s.id,
                child: Text('${s.name} · ${money(s.price, context.read<Session>().me!.company.currencySymbol)}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _saving
              ? null
              : (id) => setState(() {
                    _service = options.services.where((s) => s.id == id).firstOrNull;
                    if (_service?.duration != null) _duration = _service!.duration!;
                  }),
        ),
        const SizedBox(height: 16),
        _Label('Profesional'),
        DropdownButtonFormField<int?>(
          initialValue: _personalId,
          isExpanded: true,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.person_outline), errorText: _fieldErrors['personal_id']),
          items: [
            const DropdownMenuItem(value: null, child: Text('Sin asignar')),
            for (final p in options.specialists) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: _saving
              ? null
              : (id) {
                  setState(() => _personalId = id);
                  _loadAvailability();
                },
        ),
        const SizedBox(height: 16),
        _Label('Fecha y hora'),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: _saving ? null : _pickDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(shortDay(_date)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: _saving ? null : _pickTime,
                icon: const Icon(Icons.schedule),
                label: Text(_time.format(context)),
              ),
            ),
          ],
        ),
        _FieldError(_fieldErrors['starts_at']),
        const SizedBox(height: 12),
        AvailabilityCard(availability: _availability, loading: _loadingAvailability, hasPersonal: _personalId != null),
        const SizedBox(height: 16),
        _Label('Duración'),
        DropdownButtonFormField<int>(
          initialValue: _duration,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.timelapse),
            helperText: 'Termina a las ${hm(_startsAt.add(Duration(minutes: _duration)))}',
            errorText: _fieldErrors['duration_minutes'],
          ),
          items: [for (final d in durations) DropdownMenuItem(value: d, child: Text(duration(Duration(minutes: d))))],
          onChanged: _saving ? null : (d) => setState(() => _duration = d ?? _duration),
        ),
        const SizedBox(height: 16),
        _Label('Notas (opcional)'),
        TextField(
          controller: _notes,
          enabled: !_saving,
          maxLines: 3,
          maxLength: 1000,
          decoration: InputDecoration(hintText: 'Indicaciones para la cita', errorText: _fieldErrors['notes']),
        ),
      ],
    );
  }
}

class AvailabilityCard extends StatelessWidget {
  const AvailabilityCard({super.key, required this.availability, required this.loading, required this.hasPersonal});

  final DayAvailability? availability;
  final bool loading;
  final bool hasPersonal;

  @override
  Widget build(BuildContext context) {
    if (!hasPersonal) return const SizedBox.shrink();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (loading) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    final a = availability;
    if (a == null) return const SizedBox.shrink();

    final String schedule;
    Color color = Brand.success;
    if (!a.configured) {
      schedule = 'Sin horario configurado: se puede agendar a cualquier hora.';
      color = muted;
    } else if (a.off != null) {
      schedule = 'No trabaja este día (${a.off}).';
      color = Brand.warning;
    } else if (a.blocks.isEmpty) {
      schedule = 'No trabaja este día.';
      color = Brand.warning;
    } else {
      schedule = 'Atiende ${a.blocks.join(', ')}${a.special ? ' (horario especial)' : ''}';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.access_time, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(schedule, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
          ]),
          if (a.busy.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Ocupado:', style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 4),
            for (final b in a.busy) Text('• $b  ${b.label ?? ''}', style: TextStyle(color: muted, fontSize: 13)),
          ] else if (a.configured && a.off == null && a.blocks.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Sin citas ese día.', style: TextStyle(color: muted, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.text);

  final String? text;

  @override
  Widget build(BuildContext context) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(text!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
        );
}
