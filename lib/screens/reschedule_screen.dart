import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../session.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'appointment_form_screen.dart';

/// Reprogramar una cita: fecha, hora, duración y (con permiso) profesional.
/// Las reglas las aplica el servidor: un choque se rechaza y fuera de horario
/// se pide confirmación antes de reenviar con `force_outside`.
class RescheduleScreen extends StatefulWidget {
  const RescheduleScreen({super.key, required this.appointment, this.options});

  final Appointment appointment;
  final AgendaOptions? options;

  @override
  State<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends State<RescheduleScreen> {
  static const _durations = [15, 30, 45, 60, 75, 90, 120, 150, 180, 240];

  late DateTime _date;
  late TimeOfDay _time;
  late int _duration;
  int? _personalId;
  DayAvailability? _availability;
  bool _loadingAvailability = false;
  bool _saving = false;
  String? _error;

  ApiClient get _api => context.read<Session>().api;
  bool get _canReassign => context.read<Session>().me!.can('appointments_edit');

  @override
  void initState() {
    super.initState();
    final a = widget.appointment;
    _date = dateOnly(a.startsAt);
    _time = TimeOfDay(hour: a.startsAt.hour, minute: a.startsAt.minute);
    _duration = a.endsAt.difference(a.startsAt).inMinutes.clamp(5, 1440);
    _personalId = a.personal?.id;
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    if (_personalId == null) return;
    setState(() => _loadingAvailability = true);
    try {
      final data = await _api.get('/agenda/availability', {'personal_id': _personalId, 'date': ymd(_date), 'ignore': widget.appointment.id});
      if (mounted) setState(() => _availability = DayAvailability.fromJson(data as Map<String, dynamic>));
    } catch (_) {
      if (mounted) setState(() => _availability = null);
    } finally {
      if (mounted) setState(() => _loadingAvailability = false);
    }
  }

  DateTime get _startsAt => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(dateOnly(DateTime.now())) ? dateOnly(DateTime.now()) : _date,
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

  Future<void> _submit({bool force = false}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await _api.post('/appointments/${widget.appointment.id}/reschedule', {
        'starts_at': wallIso(_startsAt),
        'duration_minutes': _duration,
        if (_canReassign) 'personal_id': _personalId,
        if (force) 'force_outside': true,
      });
      if (mounted) Navigator.pop(context, Appointment.fromJson(data as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final outside = e.field('outside_schedule');
      if (outside != null && !force) {
        final ok = await confirm(context, title: 'Fuera de horario', message: outside.split('. Si igual').first, ok: 'Reprogramar de todos modos');
        if (ok) _submit(force: true);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final durations = {..._durations, _duration}.toList()..sort();
    final specialists = widget.options?.specialists ?? const <Ref>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Reprogramar cita')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Avatar(name: a.client?.name ?? '?', radius: 18),
              title: Text(a.client?.name ?? 'Sin cliente', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${a.service?.name ?? 'Sin servicio'}\nAhora: ${shortDay(a.startsAt)} · ${hm(a.startsAt)} a ${hm(a.endsAt)}'),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
            ),
          const Text('Nueva fecha y hora', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
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
          const SizedBox(height: 12),
          AvailabilityCard(availability: _availability, loading: _loadingAvailability, hasPersonal: _personalId != null),
          const SizedBox(height: 16),
          const Text('Duración', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            initialValue: _duration,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.timelapse), helperText: 'Termina a las ${hm(_startsAt.add(Duration(minutes: _duration)))}'),
            items: [for (final d in durations) DropdownMenuItem(value: d, child: Text(duration(Duration(minutes: d))))],
            onChanged: _saving ? null : (d) => setState(() => _duration = d ?? _duration),
          ),
          if (_canReassign && specialists.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Profesional', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int?>(
              initialValue: _personalId,
              isExpanded: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline)),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin asignar')),
                for (final p in specialists) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _saving
                  ? null
                  : (id) {
                      setState(() => _personalId = id);
                      _loadAvailability();
                    },
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : () => _submit(),
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.update),
            label: Text(_saving ? 'Guardando…' : 'Mover a ${shortDay(_date)} · ${_time.format(context)}'),
          ),
        ),
      ),
    );
  }
}
