import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'appointment_form_screen.dart';

/// Citas del día. El profesional ve las suyas; quien tiene permiso general
/// puede alternar a las de todo el equipo.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  DateTime _day = dateOnly(DateTime.now());
  bool _onlyMine = true;
  bool _loading = true;
  String? _error;
  List<Appointment> _items = [];
  AgendaOptions? _options;

  ApiClient get _api => context.read<Session>().api;
  Me get _me => context.read<Session>().me!;

  @override
  void initState() {
    super.initState();
    _onlyMine = _me.personal != null;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final mine = _onlyMine && _me.personal != null;
      final results = await Future.wait([
        _api.get('/agenda', {'date': ymd(_day), if (mine) 'personal_id': _me.personal!.id}),
        if (_options == null) _api.get('/agenda/options'),
      ]);
      if (!mounted) return;
      setState(() {
        final data = results[0] as Map<String, dynamic>;
        _items = (data['appointments'] as List).whereType<Map<String, dynamic>>().map(Appointment.fromJson).toList();
        if (results.length > 1) _options = AgendaOptions.fromJson(results[1] as Map<String, dynamic>);
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

  void _goTo(DateTime day) {
    setState(() => _day = dateOnly(day));
    _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) _goTo(picked);
  }

  Future<void> _newAppointment() async {
    final created = await Navigator.push<Appointment>(
      context,
      MaterialPageRoute(builder: (_) => AppointmentFormScreen(day: _day, options: _options)),
    );
    if (created == null || !mounted) return;
    showMessage(context, 'Cita agendada para ${shortDay(created.startsAt)} a las ${hm(created.startsAt)}.');
    _goTo(created.startsAt);
  }

  Future<void> _open(Appointment a) async {
    final changed = await showModalBottomSheet<Appointment>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AppointmentSheet(
        appointment: a,
        statuses: _options?.statuses ?? const [],
        canChange: a.isMine || _me.can('appointments_edit'),
        api: _api,
        currency: _me.company.currencySymbol,
      ),
    );
    if (changed == null || !mounted) return;
    showMessage(context, 'Estado actualizado: ${changed.statusLabel}.');
    setState(() => _items = [for (final x in _items) x.id == changed.id ? changed : x]);
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    final canToggle = me.can('agenda_all') && me.personal != null;
    final isToday = sameDay(_day, DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          if (!isToday) TextButton(onPressed: () => _goTo(DateTime.now()), child: const Text('Hoy')),
          IconButton(tooltip: 'Elegir fecha', onPressed: _pickDate, icon: const Icon(Icons.event_outlined)),
        ],
      ),
      floatingActionButton: me.can('appointments_create')
          ? FloatingActionButton.extended(heroTag: null, onPressed: _newAppointment, icon: const Icon(Icons.add), label: const Text('Nueva cita'))
          : null,
      body: Column(
        children: [
          _DayBar(
            day: _day,
            onPrev: () => _goTo(_day.subtract(const Duration(days: 1))),
            onNext: () => _goTo(_day.add(const Duration(days: 1))),
            onTap: _pickDate,
          ),
          if (canToggle)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Mis citas'), icon: Icon(Icons.person_outline)),
                    ButtonSegment(value: false, label: Text('Todo el equipo'), icon: Icon(Icons.groups_outlined)),
                  ],
                  selected: {_onlyMine},
                  onSelectionChanged: (s) {
                    setState(() => _onlyMine = s.first);
                    _load();
                  },
                ),
              ),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);

    return RefreshIndicator(
      onRefresh: _load,
      child: _items.isEmpty
          ? const EmptyView(text: 'No hay citas este día.', icon: Icons.event_available_outlined)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _items.length + 1,
              separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 4 : 10),
              itemBuilder: (_, i) {
                if (i == 0) {
                  final active = _items.where((a) => a.status != 'cancelada' && a.status != 'no_show').length;
                  return Text('$active ${active == 1 ? 'cita' : 'citas'}${active != _items.length ? ' · ${_items.length - active} canceladas o ausentes' : ''}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13));
                }
                final a = _items[i - 1];
                return AppointmentCard(appointment: a, showSpecialist: !_onlyMine, onTap: () => _open(a));
              },
            ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.day, required this.onPrev, required this.onNext, required this.onTap});

  final DateTime day;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final today = sameDay(day, DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(tooltip: 'Día anterior', onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(longDay(day), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    if (today) const Text('Hoy', style: TextStyle(color: Brand.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          IconButton(tooltip: 'Día siguiente', onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({super.key, required this.appointment, this.showSpecialist = true, this.onTap});

  final Appointment appointment;
  final bool showSpecialist;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final color = hexColor(a.statusColor);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final dimmed = a.status == 'cancelada' || a.status == 'no_show';

    return Opacity(
      opacity: dimmed ? .55 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: color),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(hm(a.startsAt), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(hm(a.endsAt), style: TextStyle(fontSize: 12, color: muted)),
                    ],
                  ),
                ),
                const VerticalDivider(width: 20, indent: 12, endIndent: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(a.client?.name ?? 'Sin cliente', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          [a.service?.name ?? 'Sin servicio', if (showSpecialist && a.personal != null) a.personal!.name].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                        if (a.outsideSchedule)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text('Fuera de horario', style: TextStyle(color: Brand.warning, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Center(child: StatusPill(label: a.statusLabel, color: color)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Detalle de la cita con cambio de estado. Devuelve la cita actualizada.
class AppointmentSheet extends StatefulWidget {
  const AppointmentSheet({
    super.key,
    required this.appointment,
    required this.statuses,
    required this.canChange,
    required this.api,
    required this.currency,
  });

  final Appointment appointment;
  final List<StatusOption> statuses;
  final bool canChange;
  final ApiClient api;
  final String currency;

  @override
  State<AppointmentSheet> createState() => _AppointmentSheetState();
}

class _AppointmentSheetState extends State<AppointmentSheet> {
  String? _saving;
  String? _error;

  Future<void> _change(StatusOption s) async {
    setState(() {
      _saving = s.key;
      _error = null;
    });
    try {
      final data = await widget.api.post('/appointments/${widget.appointment.id}/status', {'status': s.key});
      if (mounted) Navigator.pop(context, Appointment.fromJson(data as Map<String, dynamic>));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _saving = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [Icon(icon, size: 20, color: muted), const SizedBox(width: 12), Expanded(child: Text(text, style: const TextStyle(fontSize: 15)))]),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(a.client?.name ?? 'Sin cliente', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                StatusPill(label: a.statusLabel, color: hexColor(a.statusColor)),
              ],
            ),
            const SizedBox(height: 12),
            row(Icons.schedule, '${shortDay(a.startsAt)} · ${hm(a.startsAt)} a ${hm(a.endsAt)} (${duration(a.endsAt.difference(a.startsAt))})'),
            row(Icons.content_cut, a.service?.name ?? 'Sin servicio'),
            row(Icons.person_outline, a.personal?.name ?? 'Sin profesional asignado'),
            if (a.client?.phone != null) row(Icons.phone_outlined, a.client!.phone!),
            row(Icons.sell_outlined, money(a.price, widget.currency)),
            if (a.notes != null && a.notes!.isNotEmpty) row(Icons.notes, a.notes!),
            if (a.outsideSchedule) row(Icons.warning_amber_rounded, 'Agendada fuera del horario del profesional'),
            if (widget.canChange && widget.statuses.isNotEmpty) ...[
              const Divider(height: 28),
              const Text('Cambiar estado', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in widget.statuses)
                    ChoiceChip(
                      label: _saving == s.key
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(s.label),
                      selected: a.status == s.key,
                      selectedColor: hexColor(s.color).withValues(alpha: .2),
                      avatar: a.status == s.key ? null : CircleAvatar(backgroundColor: hexColor(s.color), radius: 5),
                      onSelected: _saving != null || a.status == s.key ? null : (_) => _change(s),
                    ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}
