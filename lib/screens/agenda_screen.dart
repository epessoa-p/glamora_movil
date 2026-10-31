import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../util/contact.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';
import 'appointment_form_screen.dart';
import 'client_detail_screen.dart';
import 'pos_screen.dart';
import 'reschedule_screen.dart';

/// Agenda del día o de la semana. El profesional ve sus citas; quien tiene
/// permiso general puede alternar a las de todo el equipo.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  DateTime _day = dateOnly(DateTime.now());
  bool _week = false;
  bool _onlyMine = true;
  bool _loading = true;
  String? _error;
  List<Appointment> _items = [];
  AgendaOptions? _options;

  ApiClient get _api => context.read<Session>().api;
  Me get _me => context.read<Session>().me!;

  /// Lunes de la semana del día elegido.
  DateTime get _weekStart => _day.subtract(Duration(days: _day.weekday - 1));

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
        _api.get('/agenda', {
          'date': ymd(_week ? _weekStart : _day),
          if (_week) 'days': 7,
          if (mine) 'personal_id': _me.personal!.id,
        }),
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

  void _goTo(DateTime day, {bool? week}) {
    setState(() {
      _day = dateOnly(day);
      if (week != null) _week = week;
    });
    _load();
  }

  void _shift(int direction) => _goTo(_day.add(Duration(days: direction * (_week ? 7 : 1))));

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
    final result = await showModalBottomSheet<(Appointment, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AppointmentSheet(
        appointment: a,
        statuses: _options?.statuses ?? const [],
        options: _options,
        canChange: a.isMine || _me.can('appointments_edit'),
        api: _api,
        currency: _me.company.currencySymbol,
      ),
    );
    if (result == null || !mounted) return;
    final (changed, message) = result;
    showMessage(context, message);
    // Si se movió de día (o de semana), se recarga; si no, se reemplaza en la lista.
    final visible = _week
        ? !changed.startsAt.isBefore(_weekStart) && changed.startsAt.isBefore(_weekStart.add(const Duration(days: 7)))
        : sameDay(changed.startsAt, _day);
    if (visible && sameDay(changed.startsAt, a.startsAt)) {
      setState(() => _items = [for (final x in _items) x.id == changed.id ? changed : x]..sort((x, y) => x.startsAt.compareTo(y.startsAt)));
    } else {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    final canToggle = me.can('agenda_all') && me.personal != null;
    final current = _week ? sameDay(_weekStart, dateOnly(DateTime.now()).subtract(Duration(days: DateTime.now().weekday - 1))) : sameDay(_day, DateTime.now());

    return Scaffold(
      appBar: AppBar(
        leading: shellLeading(context),
        title: const Text('Agenda'),
        // Recordatorios pasó al menú lateral para dejar sitio al perfil.
        actions: [
          if (!current) TextButton(onPressed: () => _goTo(DateTime.now()), child: const Text('Hoy')),
          IconButton(
            tooltip: _week ? 'Ver el día' : 'Ver la semana',
            onPressed: () => _goTo(_day, week: !_week),
            icon: Icon(_week ? Icons.view_day_outlined : Icons.view_week_outlined),
          ),
          IconButton(tooltip: 'Elegir fecha', onPressed: _pickDate, icon: const Icon(Icons.event_outlined)),
          const ProfileButton(),
        ],
      ),
      floatingActionButton: me.can('appointments_create')
          ? FloatingActionButton.extended(heroTag: null, onPressed: _newAppointment, icon: const Icon(Icons.add), label: const Text('Nueva cita'))
          : null,
      body: Column(
        children: [
          _DayBar(
            title: _week ? _weekTitle() : longDay(_day),
            subtitle: current ? (_week ? 'Esta semana' : 'Hoy') : null,
            onPrev: () => _shift(-1),
            onNext: () => _shift(1),
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

  /// `20 – 26 oct` o `27 oct – 2 nov`
  String _weekTitle() {
    final end = _weekStart.add(const Duration(days: 6));
    final sameMonth = _weekStart.month == end.month;
    final from = shortDay(_weekStart).split(' ').skip(1).take(sameMonth ? 1 : 2).join(' ');
    return '$from – ${shortDay(end).split(' ').skip(1).join(' ')}';
  }

  Widget _body() {
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);

    return RefreshIndicator(onRefresh: _load, child: _week ? _weekList() : _dayList());
  }

  Widget _dayList() {
    if (_items.isEmpty) return const EmptyView(text: 'No hay citas este día.', icon: Icons.event_available_outlined);

    return ListView.separated(
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
    );
  }

  /// Los 7 días de la semana, cada uno con sus citas. Tocar el día lo abre.
  Widget _weekList() {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final children = <Widget>[];

    for (var d = 0; d < 7; d++) {
      final day = _weekStart.add(Duration(days: d));
      final items = _items.where((a) => sameDay(a.startsAt, day)).toList();
      final today = sameDay(day, DateTime.now());

      children.add(InkWell(
        key: ValueKey('week-day-$d'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => _goTo(day, week: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Row(
            children: [
              Text(longDay(day), style: TextStyle(fontWeight: FontWeight.w800, color: today ? Brand.primary : null)),
              const SizedBox(width: 8),
              if (items.isNotEmpty) StatusPill(label: '${items.length}', color: Brand.primary),
              const Spacer(),
              Icon(Icons.chevron_right, size: 18, color: muted),
            ],
          ),
        ),
      ));
      if (items.isEmpty) {
        children.add(Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text('Sin citas', style: TextStyle(color: muted, fontSize: 13))));
      }
      for (final a in items) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppointmentCard(appointment: a, showSpecialist: !_onlyMine, onTap: () => _open(a)),
        ));
      }
    }

    return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 96), children: children);
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.title, this.subtitle, required this.onPrev, required this.onNext, required this.onTap});

  final String title;
  final String? subtitle;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(tooltip: 'Anterior', onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    if (subtitle != null) Text(subtitle!, style: const TextStyle(color: Brand.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          IconButton(tooltip: 'Siguiente', onPressed: onNext, icon: const Icon(Icons.chevron_right)),
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

/// Detalle de la cita: contacto, cambio de estado, reprogramar y ficha del
/// cliente. Devuelve la cita actualizada y el mensaje para mostrar.
class AppointmentSheet extends StatefulWidget {
  const AppointmentSheet({
    super.key,
    required this.appointment,
    required this.statuses,
    this.options,
    required this.canChange,
    required this.api,
    required this.currency,
  });

  final Appointment appointment;
  final List<StatusOption> statuses;
  final AgendaOptions? options;
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
      final updated = Appointment.fromJson(data as Map<String, dynamic>);
      if (mounted) Navigator.pop(context, (updated, 'Estado actualizado: ${updated.statusLabel}.'));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _saving = null;
        });
      }
    }
  }

  Future<void> _reschedule() async {
    final moved = await Navigator.push<Appointment>(
      context,
      MaterialPageRoute(builder: (_) => RescheduleScreen(appointment: widget.appointment, options: widget.options)),
    );
    if (moved != null && mounted) {
      Navigator.pop(context, (moved, 'Cita reprogramada para ${shortDay(moved.startsAt)} a las ${hm(moved.startsAt)}.'));
    }
  }

  /// Abre el cobro con la clienta, el servicio y el profesional de la cita.
  void _charge() {
    final a = widget.appointment;
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(
      builder: (_) => PosScreen(
        client: a.client,
        specialistId: a.personal?.id,
        lines: [if (a.service != null) CartLine(kind: 'service', id: a.service!.id, name: a.service!.name, price: a.price)],
      ),
    ));
  }

  /// Mensaje de WhatsApp con el recordatorio de la cita.
  String _reminder(Appointment a) {
    final company = context.read<Session>().me?.company.name ?? '';
    final first = (a.client?.name ?? '').split(' ').first;
    return 'Hola $first, te recordamos tu cita${a.service != null ? ' de ${a.service!.name}' : ''} el ${longDay(a.startsAt).toLowerCase()} a las ${hm(a.startsAt)}'
        '${company.isNotEmpty ? ' en $company' : ''}. ¡Te esperamos!';
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final me = context.read<Session>().me;
    final canReschedule = widget.canChange && (a.status == 'pendiente' || a.status == 'confirmada');
    final canSeeClient = a.client != null && (me?.can('clients_view') ?? false);
    final canCharge = (me?.can('sales_create') ?? false) && a.status != 'cancelada' && a.status != 'no_show';

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
            if (a.client?.phone != null) ...[
              const SizedBox(height: 10),
              ContactButtons(phone: a.client!.phone!, message: _reminder(a)),
            ],
            if (canReschedule || canSeeClient) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (canReschedule)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving == null ? _reschedule : null,
                        icon: const Icon(Icons.update),
                        label: const Text('Reprogramar'),
                      ),
                    ),
                  if (canReschedule && canSeeClient) const SizedBox(width: 10),
                  if (canSeeClient)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientDetailScreen(client: a.client!))),
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text('Ver ficha'),
                      ),
                    ),
                ],
              ),
            ],
            if (canCharge) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving == null ? _charge : null,
                  icon: const Icon(Icons.point_of_sale),
                  label: Text('Cobrar ${money(a.price, widget.currency)}'),
                ),
              ),
            ],
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
